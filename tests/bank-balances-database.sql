-- Reversible checks: no test balances, transactions or settings are retained.
begin;
create temporary table balance_test_owner as
 select (decrypted_secret::jsonb->>'owner')::uuid as id from vault.decrypted_secrets where name='mis_gastos_bank_config';
grant select on balance_test_owner to authenticated;
do $$
declare lease jsonb; sample jsonb; old_settings jsonb; owner_id uuid; n bigint;
begin
 select id into owner_id from balance_test_owner;
 select data into old_settings from public.settings where user_id=owner_id;
 select count(*) into n from public.tx;
 lease:=public.bank_sync_worker('acquire');
 if lease ? 'busy' then raise exception 'WORKER_BUSY'; end if;
 sample:=lease||'{"bank":"Sabadell","amount":104.36,"currency":"EUR","balance_type":"XPCD"}'::jsonb;
 perform public.bank_sync_worker('balance',sample);
 if (select amount from public.bank_balances where user_id=owner_id and bank='Sabadell')<>104.36 then raise exception 'SNAPSHOT_NOT_SAVED'; end if;
 perform public.bank_sync_worker('balance',sample||'{"bank":"Revolut","amount":0,"balance_type":"ITAV"}'::jsonb);
 if (select amount from public.bank_balances where user_id=owner_id and bank='Revolut')<>0 then raise exception 'ZERO_NOT_SAVED'; end if;
 perform public.bank_sync_worker('balance',sample||'{"amount":-1.23}'::jsonb);
 if (select amount from public.bank_balances where user_id=owner_id and bank='Sabadell')<>-1.23 then raise exception 'SIGN_LOST'; end if;
 begin
  perform public.bank_sync_worker('balance',sample||'{"amount":null}'::jsonb);
  raise exception 'ACCEPTED_NULL';
 exception when others then if sqlerrm<>'INVALID_BALANCE' then raise; end if; end;
 begin
  perform public.bank_sync_worker('balance',sample||'{"currency":"USD"}'::jsonb);
  raise exception 'ACCEPTED_CURRENCY';
 exception when others then if sqlerrm<>'INVALID_BALANCE' then raise; end if; end;
 begin
  perform public.bank_sync_worker('balance',sample||jsonb_build_object('lease',gen_random_uuid()));
  raise exception 'ACCEPTED_BAD_LEASE';
 exception when others then if sqlerrm<>'INVALID_LEASE' then raise; end if; end;
 perform public.bank_sync_worker('release',lease||'{"success":false,"results":[]}'::jsonb);
 if (select amount from public.bank_balances where user_id=owner_id and bank='Sabadell')<>-1.23 then raise exception 'FAILURE_ERASED_SNAPSHOT'; end if;
 if (select data from public.settings where user_id=owner_id) is distinct from old_settings or (select count(*) from public.tx)<>n then raise exception 'HISTORY_OR_SETTINGS_CHANGED'; end if;
 if has_table_privilege('anon','public.bank_balances','select')
  or has_table_privilege('authenticated','public.bank_balances','insert')
  or has_table_privilege('authenticated','public.bank_balances','update')
  or has_table_privilege('authenticated','public.bank_balances','delete') then raise exception 'CLIENT_WRITE_ACCESS'; end if;
 if has_function_privilege('authenticated','public.bank_sync_worker(text,jsonb)','execute')
  or has_function_privilege('anon','banking_private.store_balance(jsonb)','execute') then raise exception 'CLIENT_WORKER_ACCESS'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',(select id::text from balance_test_owner),true);
do $$ begin
 if (select count(*) from public.bank_balances)<>2 then raise exception 'OWNER_CANNOT_READ'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$ begin
 if exists(select 1 from public.bank_balances) then raise exception 'OTHER_USER_CAN_READ'; end if;
end $$;
reset role;
rollback;
select 'balance_database_checks_passed' as result;

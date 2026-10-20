-- Bank snapshots are separate from client-editable settings and transaction history.
create table public.bank_balances (
 user_id uuid not null references auth.users(id) on delete cascade,
 bank text not null check(bank in ('Sabadell','Revolut')),
 amount numeric(14,2) not null check(abs(amount)<=1000000000),
 currency text not null check(currency='EUR'),
 balance_type text not null check(balance_type in ('ITAV','XPCD','CLAV','ITBD','CLBD')),
 reference_date date,
 fetched_at timestamptz not null default clock_timestamp(),
 primary key(user_id,bank)
);
alter table public.bank_balances enable row level security;
revoke all on public.bank_balances from public,anon,authenticated,service_role;
grant select on public.bank_balances to authenticated;
create policy bank_balance_owner_read on public.bank_balances for select to authenticated
 using ((select auth.uid())=user_id);

create function banking_private.store_balance(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare st banking_private.state%rowtype; cfg jsonb;
begin
 select * into st from banking_private.state where id for update;
 if st.lease_id is null or st.lease_id is distinct from (p_data->>'lease')::uuid
   or st.lease_until is null or st.lease_until<now() then raise exception 'INVALID_LEASE'; end if;
 select decrypted_secret::jsonb into cfg from vault.decrypted_secrets where name='mis_gastos_bank_config';
 if cfg is null then raise exception 'BANK_CONFIG_MISSING'; end if;
 if (select count(*) from jsonb_array_elements(cfg->'accounts') a where a->>'label'=p_data->>'bank')<>1
   then raise exception 'INVALID_BANK_ACCOUNT'; end if;
 if coalesce(p_data->>'currency','')<>'EUR'
   or coalesce(p_data->>'balance_type','') not in ('ITAV','XPCD','CLAV','ITBD','CLBD')
   or coalesce(p_data->>'amount','') !~ '^-?[0-9]+([.][0-9]{1,2})?$'
   then raise exception 'INVALID_BALANCE'; end if;
 insert into public.bank_balances(user_id,bank,amount,currency,balance_type,reference_date,fetched_at)
 values((cfg->>'owner')::uuid,p_data->>'bank',(p_data->>'amount')::numeric,'EUR',p_data->>'balance_type',
   (p_data->>'reference_date')::date,clock_timestamp())
 on conflict(user_id,bank) do update set amount=excluded.amount,currency=excluded.currency,
   balance_type=excluded.balance_type,reference_date=excluded.reference_date,fetched_at=excluded.fetched_at;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function banking_private.store_balance(jsonb) from public,anon,authenticated,service_role;

create or replace function banking_private.worker(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cfg jsonb; st banking_private.state%rowtype; e jsonb; tid uuid; n integer:=0; lease uuid;
begin
 select decrypted_secret::jsonb into cfg from vault.decrypted_secrets where name='mis_gastos_bank_config';
 if cfg is null then raise exception 'BANK_CONFIG_MISSING'; end if;
 if p_action='config' then
  select * into st from banking_private.state where id;
  return cfg || jsonb_build_object('started_at',st.started_at,'last_success',st.last_success);
 elsif p_action='acquire' then
  lease:=pg_catalog.gen_random_uuid();
  update banking_private.state set lease_id=lease,lease_until=now()+interval '15 minutes'
   where id and (lease_until is null or lease_until<now());
  if not found then return jsonb_build_object('busy',true); end if;
  return jsonb_build_object('lease',lease);
 elsif p_action='balance' then
  return banking_private.store_balance(p_data);
 elsif p_action in ('commit','release') then
  select * into st from banking_private.state where id for update;
  if st.lease_id is distinct from (p_data->>'lease')::uuid or st.lease_until<now() then raise exception 'INVALID_LEASE'; end if;
  if p_action='commit' then
   for e in select value from jsonb_array_elements(p_data->'entries') loop
    if e->>'ref' is null then continue; end if;
    if (e->>'date')::date < st.started_at::date then continue; end if;
    tid:=pg_catalog.gen_random_uuid();
    insert into banking_private.seen(ref,tx_id) values(e->>'ref',tid) on conflict do nothing;
    if not found then continue; end if;
    if e->>'t' not in ('g','i') or e->>'k' not in ('Sabadell','Revolut') or (e->>'a')::numeric<=0 then raise exception 'INVALID_ENTRY'; end if;
    insert into public.tx(id,user_id,ts,t,a,m,c,s,k,nt,r)
    values(tid,(cfg->>'owner')::uuid,(e->>'ts')::timestamptz,e->>'t',(e->>'a')::numeric,e->>'m',e->>'c','',e->>'k',e->>'nt',false);
    n:=n+1;
   end loop;
   return jsonb_build_object('inserted',n);
  else
   update banking_private.state set lease_until=null,lease_id=null,
    last_success=case when coalesce((p_data->>'success')::boolean,false) then now() else last_success end,
    last_result=p_data-'lease' where id;
   return jsonb_build_object('ok',true);
  end if;
 else raise exception 'INVALID_ACTION'; end if;
end $$;

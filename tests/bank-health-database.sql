begin;
do $$
declare old_success timestamptz; owner_id uuid; overview jsonb;
begin
 select last_success into old_success from banking_private.health where bank='Sabadell';
 update banking_private.state set last_result='{"success":false,"results":[{"bank":"Sabadell","error":"BANK_HTTP_429"},{"bank":"Revolut","inserted":0,"skipped":0}]}'::jsonb where id;
 if (select last_success from banking_private.health where bank='Sabadell') is distinct from old_success then raise exception 'FAILED_BANK_ADVANCED'; end if;
 if (select last_error from banking_private.health where bank='Sabadell')<>'BANK_HTTP_429' then raise exception 'ERROR_NOT_RECORDED'; end if;
 if (select last_success is null or last_error is not null or last_attempt is null from banking_private.health where bank='Revolut') then raise exception 'SUCCESS_NOT_RECORDED'; end if;
 if has_function_privilege('anon','public.banking_overview()','execute') or has_function_privilege('authenticated','public.banking_overview()','execute') then raise exception 'CLIENT_STATUS_ACCESS'; end if;
 if has_table_privilege('authenticated','banking_private.health','select') then raise exception 'PRIVATE_TABLE_ACCESS'; end if;
end $$;
rollback;

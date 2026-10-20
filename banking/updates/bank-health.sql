-- Estado por banco. Solo metadatos; no consulta adicional al proveedor.
create table if not exists banking_private.health (
 bank text primary key check(bank in ('Sabadell','Revolut')),
 last_success timestamptz, last_attempt timestamptz, last_error text
);
alter table banking_private.health enable row level security;
revoke all on banking_private.health from public,anon,authenticated,service_role;
insert into banking_private.health(bank,last_success)
select bank,last_success from banking_private.state cross join (values ('Sabadell'),('Revolut')) b(bank)
on conflict do nothing;
-- La instantánea previa no registra la hora de cada intento. No inventarla.
update banking_private.health h set last_error=e->>'error'
from banking_private.state st cross join lateral jsonb_array_elements(coalesce(st.last_result->'results','[]')) e
where h.bank=e->>'bank';
create or replace function banking_private.record_health() returns trigger
language plpgsql security definer set search_path='' as $$
declare e jsonb; moment timestamptz:=clock_timestamp();
begin
 for e in select value from jsonb_array_elements(coalesce(new.last_result->'results','[]')) loop
  if e->>'bank' not in ('Sabadell','Revolut') then continue; end if;
  insert into banking_private.health(bank,last_success,last_attempt,last_error)
  values(e->>'bank',case when e->>'error' is null then moment end,moment,e->>'error')
  on conflict(bank) do update set last_attempt=moment,last_error=excluded.last_error,
   last_success=coalesce(excluded.last_success,banking_private.health.last_success);
 end loop;
 if new.last_result->>'error' is not null then
  update banking_private.health set last_attempt=moment,last_error='WORKER_FAILED';
 end if;
 return new;
end $$;
revoke all on function banking_private.record_health() from public,anon,authenticated,service_role;
drop trigger if exists bank_health_after_release on banking_private.state;
create trigger bank_health_after_release after update of last_result on banking_private.state
for each row execute function banking_private.record_health();
create or replace function public.banking_overview() returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner_id uuid;
begin
 if auth.uid() is null then raise exception 'unauthorized'; end if;
 select (decrypted_secret::jsonb->>'owner')::uuid into owner_id from vault.decrypted_secrets where name='mis_gastos_bank_config';
 if auth.uid() is distinct from owner_id then raise exception 'unauthorized'; end if;
 return jsonb_build_object(
  'banks',(select coalesce(jsonb_agg(jsonb_build_object('bank',bank,'last_success',last_success,'last_attempt',last_attempt,'error',last_error) order by bank),'[]') from banking_private.health),
  'bank_tx_ids',(select coalesce(jsonb_agg(t.id),'[]') from public.tx t where t.user_id=auth.uid() and exists(select 1 from banking_private.seen s where s.tx_id=t.id and not s.excluded))
 );
end $$;
revoke all on function public.banking_overview() from public,anon;
grant execute on function public.banking_overview() to authenticated;

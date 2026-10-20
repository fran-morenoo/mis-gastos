create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create schema if not exists banking_private;
revoke all on schema banking_private from public,anon,authenticated;
grant usage on schema banking_private to service_role;
create table banking_private.state (
 id boolean primary key default true check(id), started_at timestamptz not null,
 last_success timestamptz, lease_until timestamptz, lease_id uuid,
 last_result jsonb not null default '{}'
);
create table banking_private.seen (
 ref text primary key check(ref ~ '^[a-f0-9]{64}$'),
 excluded boolean not null default false, tx_id uuid,
 created_at timestamptz not null default now()
);
alter table banking_private.state enable row level security;
alter table banking_private.seen enable row level security;
revoke all on all tables in schema banking_private from public,anon,authenticated,service_role;
create function banking_private.worker(p_action text,p_data jsonb default '{}') returns jsonb
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
revoke all on function banking_private.worker(text,jsonb) from public,anon,authenticated;
grant execute on function banking_private.worker(text,jsonb) to service_role;
create function public.bank_sync_worker(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select banking_private.worker(p_action,p_data) $$;
revoke all on function public.bank_sync_worker(text,jsonb) from public,anon,authenticated;
grant execute on function public.bank_sync_worker(text,jsonb) to service_role;

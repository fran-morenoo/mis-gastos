-- Cuatro consultas al día, a las 12, 16, 20 y 00 en Europe/Madrid.
-- El job se despierta cada hora, pero solo encola HTTP en esas cuatro horas.
-- Las credenciales y el comando de encolado existentes permanecen privados.
create table if not exists banking_private.schedule_backup (
 jobid bigint primary key, schedule text not null, command text not null,
 recorded_at timestamptz not null default now()
);
alter table banking_private.schedule_backup enable row level security;
revoke all on banking_private.schedule_backup from public,anon,authenticated,service_role;
create or replace function banking_private.bank_schedule_due(p_at timestamptz) returns boolean
language sql immutable strict set search_path='' as $$
 select extract(hour from p_at at time zone 'Europe/Madrid')::int in (0,12,16,20)
$$;
revoke all on function banking_private.bank_schedule_due(timestamptz) from public,anon,authenticated,service_role;
do $$
declare task cron.job%rowtype; guarded text;
begin
 select * into strict task from cron.job where jobname='mis-gastos-bank-sync';
 insert into banking_private.schedule_backup(jobid,schedule,command) values(task.jobid,task.schedule,task.command) on conflict do nothing;
 -- Partir siempre del comando original: evita añadir capas si se reejecuta.
 select command into task.command from banking_private.schedule_backup where jobid=task.jobid;
 guarded:=format('DO $bank_due$ BEGIN IF banking_private.bank_schedule_due(now()) THEN EXECUTE %L; END IF; END $bank_due$;',task.command);
 perform cron.alter_job(task.jobid,schedule:='0 * * * *',command:=guarded);
end $$;

begin;
do $$
declare d date; h int; calls int; at_time timestamptz;
begin
 -- Días normales y ambos cambios de hora: siempre cuatro horas civiles exactas.
 foreach d in array array['2026-10-08'::date,'2026-10-25'::date,'2027-03-28'::date,'2027-07-01'::date] loop
  calls:=0;
  for h in 0..23 loop
   at_time:=(d+h*interval '1 hour') at time zone 'Europe/Madrid';
   if banking_private.bank_schedule_due(at_time) then
    calls:=calls+1;
    if h not in (0,12,16,20) then raise exception 'WRONG_LOCAL_HOUR'; end if;
   end if;
  end loop;
  if calls<>4 then raise exception 'WRONG_DAILY_COUNT'; end if;
 end loop;
 if not banking_private.bank_schedule_due('2026-10-08T10:00:00Z') or banking_private.bank_schedule_due('2026-10-08T12:00:00Z') then raise exception 'SUMMER_TIME'; end if;
 if not banking_private.bank_schedule_due('2026-11-08T11:00:00Z') or banking_private.bank_schedule_due('2026-11-08T10:00:00Z') then raise exception 'WINTER_TIME'; end if;
 if not exists(select 1 from cron.job where jobname='mis-gastos-bank-sync' and active and schedule='0 * * * *' and command like '%banking_private.bank_schedule_due(now())%') then raise exception 'SCHEDULE_NOT_INSTALLED'; end if;
 if has_table_privilege('authenticated','banking_private.schedule_backup','select') then raise exception 'PRIVATE_BACKUP_EXPOSED'; end if;
end $$;
rollback;

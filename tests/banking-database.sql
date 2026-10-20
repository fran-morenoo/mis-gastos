-- Integration checks are always rolled back; they never leave test movements.
begin;
do $$
declare lease jsonb; sample jsonb; result jsonb; stamp timestamptz; tid uuid;
begin
 lease:=public.bank_sync_worker('acquire');
 if lease ? 'busy' then raise exception 'WORKER_BUSY'; end if;
 select started_at+interval '1 second' into stamp from banking_private.state;
 sample:=jsonb_build_object('ref',repeat('a',64),'ts',stamp,'date',stamp::date,'t','g','a',12.10,'m','BANK_SYNC_ROLLBACK_TEST','c','Sin clasificar','k','Sabadell','nt','');
 result:=public.bank_sync_worker('commit',lease||jsonb_build_object('entries',jsonb_build_array(sample)));
 if (result->>'inserted')::integer<>1 then raise exception 'FIRST_INSERT_FAILED'; end if;
 result:=public.bank_sync_worker('commit',lease||jsonb_build_object('entries',jsonb_build_array(sample)));
 if (result->>'inserted')::integer<>0 then raise exception 'DUPLICATE_INSERTED'; end if;
 sample:=sample||jsonb_build_object('ref',repeat('b',64),'k','Revolut','t','i','c','Ingresos');
 result:=public.bank_sync_worker('commit',lease||jsonb_build_object('entries',jsonb_build_array(sample)));
 if (result->>'inserted')::integer<>1 then raise exception 'SECOND_ACCOUNT_FAILED'; end if;
 select tx_id into tid from banking_private.seen where ref=repeat('b',64);
 delete from public.tx where id=tid;
 result:=public.bank_sync_worker('commit',lease||jsonb_build_object('entries',jsonb_build_array(sample)));
 if (result->>'inserted')::integer<>0 then raise exception 'DELETED_ENTRY_REAPPEARED'; end if;
 sample:=sample||jsonb_build_object('ref',repeat('c',64),'date',(stamp-interval '1 day')::date,'ts',stamp-interval '1 day');
 result:=public.bank_sync_worker('commit',lease||jsonb_build_object('entries',jsonb_build_array(sample)));
 if (result->>'inserted')::integer<>0 then raise exception 'HISTORICAL_ENTRY_IMPORTED'; end if;
end $$;
rollback;
select jsonb_build_object('integration_tests','passed','test_movements_remain',exists(select 1 from public.tx where m='BANK_SYNC_ROLLBACK_TEST'));

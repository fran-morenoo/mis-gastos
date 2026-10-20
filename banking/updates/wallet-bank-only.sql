-- El atajo no registra cuentas que ya se importan desde el banco.
-- No modifica historial, saldos, secretos ni permisos de la función existente.
create or replace function public.add_payment(p_secret text,p_merchant text,p_amount numeric,p_card text default '')
returns void language plpgsql security definer set search_path='' as $$
declare owner_id uuid; settings_data jsonb; card_name text; account_name text;
begin
 select user_id,data into owner_id,settings_data from public.settings where ingest_secret=p_secret limit 1;
 if owner_id is null then raise exception 'unauthorized'; end if;
 card_name:=lower(regexp_replace(trim(coalesce(p_card,'')),'\s+',' ','g'));
 account_name:=lower(trim(coalesce(settings_data->'links'->>p_card,p_card,'')));
 if card_name in ('sabadell','revolut','revolut visa','mastercard bscard') or account_name in ('sabadell','revolut') then return; end if;
 insert into public.tx(user_id,ts,t,a,m,c,k)
 values(owner_id,now(),'g',abs(p_amount),p_merchant,'Sin clasificar',p_card);
end $$;

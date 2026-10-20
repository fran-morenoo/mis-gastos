-- Estado y monitorización internos: no se exponen a la aplicación.
revoke all on function public.banking_overview() from public,anon,authenticated,service_role;

begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Switch the portal reader first. Mobile writes and replay have separate
-- gateways and remain available while the pilot validates those writers.
create function rm_private.activate_workshop_receiving_read_cutover_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 lock table public.rm_projetos,public.rm_celulas_projeto,public.rm_celulas in share mode;
 lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership in share mode;
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced)
  or exists(select 1 from public.rm_projetos p where not exists(
   select 1 from rm_private.workshop_project_ownership o where o.id=p.id))
  or exists(select 1 from public.rm_celulas c where not exists(
   select 1 from rm_private.workshop_cell_ownership o where o.cell_id=c.id)) then
  raise exception 'Conclua a conferência de origem dos projetos e das células antes de ativar a leitura de recebimentos.'
   using errcode='PT409';
 end if;
 revoke execute on function public.rm_web_receivings_v1(text,text,integer,integer) from authenticated;
 notify pgrst,'reload schema';
end
$$;
revoke all on function rm_private.activate_workshop_receiving_read_cutover_v1() from public,anon,authenticated,service_role;

commit;

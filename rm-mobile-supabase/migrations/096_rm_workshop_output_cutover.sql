begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Remove the old authenticated output RPCs after the Railway consumers are
-- using the session-bound workshop reader. The private projections still
-- run as the verified reader's owner and keep the same workbook contract.
create function rm_private.activate_workshop_output_cutover_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced) then
  raise exception 'Confirme o SSO e o escopo do planejamento antes de ativar as saídas por oficina.' using errcode='PT409';
 end if;

 revoke execute on function public.rm_web_planning_export_snapshot_v1(uuid[],text[]),
  public.rm_web_workshop_snapshot_v1(),
  rm_private.web_export_shared_equipment_v1(uuid[]),
  rm_private.web_planning_export_allowed_v1() from authenticated;
end
$$;
revoke all on function rm_private.activate_workshop_output_cutover_v1() from public,anon,authenticated,service_role;

commit;

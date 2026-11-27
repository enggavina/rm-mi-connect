begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The scoped reader and writer already validate the caller, project and cells.
-- Deploy the portal against them before removing the legacy entry points.
do $reader$
declare
 definition text:=pg_get_functiondef('rm_private.workshop_gantt_snapshot_v1(jsonb,uuid)'::regprocedure);
 gate constant text:=$gate$
    or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced)$gate$;
begin
 if array_length(string_to_array(definition,gate),1) is distinct from 2 then
  raise exception 'Unexpected scoped Gantt edit eligibility contract';
 end if;
 execute replace(definition,gate,'');
end
$reader$;

create function rm_private.activate_gantt_workshop_cutover_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 -- The deferred links allow creation of an initial route alongside a new
 -- project's ownership. They also stop a committed allocation from ever
 -- losing its workshop, even while legacy clients can create unplanned intake.
 lock table public.rm_celulas,public.rm_projetos,public.rm_celulas_projeto in share row exclusive mode;
 lock table rm_private.workshop_cell_ownership,rm_private.workshop_project_ownership in share row exclusive mode;
 if not exists(select 1 from rm_private.root_creation_settings where singleton and activated_at is not null)
  or not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or exists(select 1 from public.rm_celulas_projeto a
   left join rm_private.workshop_project_ownership p on p.id=a.projeto_id
   left join rm_private.workshop_cell_ownership c on c.cell_id=a.celula_id
   where p.workshop_id is null or p.workshop_id is distinct from c.workshop_id) then
  raise exception 'Conclua a conferência de origem das alocações antes de ativar o Gantt por oficina.' using errcode='PT409';
 end if;
 if not exists(select 1 from pg_constraint where conrelid='public.rm_celulas_projeto'::regclass
  and conname='workshop_planning_project_origin') then
  alter table public.rm_celulas_projeto
   add constraint workshop_planning_project_origin foreign key(projeto_id)
    references rm_private.workshop_project_ownership(id) deferrable initially deferred,
   add constraint workshop_planning_cell_origin foreign key(celula_id)
    references rm_private.workshop_cell_ownership(cell_id) deferrable initially deferred;
 end if;
 if (select count(*) from pg_constraint where conrelid='public.rm_celulas_projeto'::regclass
  and conname in('workshop_planning_project_origin','workshop_planning_cell_origin')
  and confrelid in('rm_private.workshop_project_ownership'::regclass,'rm_private.workshop_cell_ownership'::regclass)
  and contype='f' and convalidated and condeferrable and condeferred)<>2 then
  raise exception 'Os vínculos de origem do planejamento não estão íntegros.' using errcode='PT409';
 end if;
 update rm_private.gantt_workshop_write_settings set enforced=true where singleton and not enforced;
 revoke execute on function public.rm_web_gantt_snapshot_v1(jsonb),rm_private.web_gantt_snapshot_before_calendar_v1(jsonb),
  rm_private.web_gantt_project_version_v1(uuid),rm_private.web_gantt_project_version_before_calendar_v1(uuid) from authenticated;
 revoke select on rm_private.gantt_project_plans,rm_private.gantt_baselines,rm_private.gantt_project_settings from authenticated;
end
$$;
revoke all on function rm_private.activate_gantt_workshop_cutover_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

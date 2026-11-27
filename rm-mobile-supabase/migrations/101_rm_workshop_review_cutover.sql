begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Validate the final record after a submission or stage setup has finished
-- writing its links. Templates without a project are not operational stages.
create function rm_private.require_review_target_origin_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 office uuid;
 valid boolean;
begin
 if tg_relid='public.rm_registros_formulario'::regclass then
  select p.workshop_id,rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p.workshop_id)
   into office,valid
  from public.rm_registros_formulario r left join rm_private.workshop_project_ownership p on p.id=r.projeto_id
  where r.id=new.id;
 elsif tg_relid='public.rm_aprovacoes_etapas'::regclass then
  select p.workshop_id,rm_private.workshop_stage_owned_v1(a.id,p.workshop_id)
   into office,valid
  from public.rm_aprovacoes_etapas a left join rm_private.workshop_project_ownership p on p.id=a.projeto_id
  where a.id=new.id and a.projeto_id is not null;
 else
  raise exception 'Origem de revisão desconhecida.' using errcode='42501';
 end if;
 if found and (office is null or valid is not true) then
  raise exception 'O vínculo do formulário ou da etapa precisa pertencer à oficina do projeto. Preserve o protocolo para nova tentativa.'
   using errcode='PT409';
 end if;
 return null;
end
$$;
revoke all on function rm_private.require_review_target_origin_v1() from public,anon,authenticated,service_role;

create constraint trigger workshop_review_form_origin
after insert or update of projeto_id,celula_id,form_id on public.rm_registros_formulario
deferrable initially deferred for each row execute function rm_private.require_review_target_origin_v1();
create constraint trigger workshop_review_stage_origin
after insert or update of projeto_id,celula_origem_id,celula_destino_id,celula_projeto_id on public.rm_aprovacoes_etapas
deferrable initially deferred for each row execute function rm_private.require_review_target_origin_v1();
alter table public.rm_registros_formulario disable trigger workshop_review_form_origin;
alter table public.rm_aprovacoes_etapas disable trigger workshop_review_stage_origin;

-- Activate after Railway issues the workshop permit on both review actions.
-- Unallocated intake is governed separately from operational reviews.
create function rm_private.activate_workshop_review_cutover_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 lock table public.rm_celulas,public.rm_projetos,public.rm_celulas_projeto,
  public.rm_registros_formulario,public.rm_aprovacoes_etapas in share row exclusive mode;
 lock table rm_private.workshop_cell_ownership,rm_private.workshop_project_ownership,
  rm_private.workshop_catalog_ownership in share row exclusive mode;
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced)
  or exists(select 1 from public.rm_registros_formulario r
   left join rm_private.workshop_project_ownership p on p.id=r.projeto_id
   where p.workshop_id is null or rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p.workshop_id) is not true)
  or exists(select 1 from public.rm_aprovacoes_etapas a
   left join rm_private.workshop_project_ownership p on p.id=a.projeto_id
   where a.projeto_id is not null and (p.workshop_id is null or rm_private.workshop_stage_owned_v1(a.id,p.workshop_id) is not true)) then
  raise exception 'Conclua a conferência de origem dos formulários e das etapas e confirme o acesso corporativo antes de ativar a revisão.'
   using errcode='PT409';
 end if;
 alter table public.rm_registros_formulario enable trigger workshop_review_form_origin;
 alter table public.rm_aprovacoes_etapas enable trigger workshop_review_stage_origin;
 update rm_private.form_review_workshop_settings set enforced=true where singleton and not enforced;
 revoke execute on function public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer),
  public.rm_web_stage_approval_snapshot_v1(uuid) from authenticated;
 revoke select on rm_private.web_stage_approval_context_v1 from authenticated;
end
$$;
revoke all on function rm_private.activate_workshop_review_cutover_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_legacy_bma_device_v1()
returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from rm_private.workshop_legacy_catalog_access a
  join rm_private.workshop_legacy_adoption b on b.singleton and b.legacy_workshop_id=a.workshop_id
  join public.rm_users u on u.auth_user_id=a.auth_user_id and u.status='ativo'
  where a.singleton and a.auth_user_id=auth.uid() and a.revoked_at is null);
$$;
revoke all on function rm_private.workshop_legacy_bma_device_v1() from public,anon,authenticated,service_role;

create or replace function rm_private.workshop_legacy_bma_catalog_ids_v1(p_resource text)
returns setof uuid language sql stable security definer set search_path='' as $$
 select r.id from rm_private.workshop_legacy_bma_catalog_rows r
 where r.resource=p_resource and (select rm_private.workshop_legacy_bma_device_v1());
$$;

create view rm_private.workshop_legacy_bma_projects as
with legacy_device as materialized (
 select a.auth_user_id,a.workshop_id from rm_private.workshop_legacy_catalog_access a
 join rm_private.workshop_legacy_adoption b on b.singleton and b.legacy_workshop_id=a.workshop_id
 where a.singleton and a.revoked_at is null
), proofs as (
 select o.project_id::text project_id,o.equipment_id::text equipment_id,o.operator_id,d.workshop_id
 from rm_private.receiving_openings o join legacy_device d on d.auth_user_id=o.auth_user_id
 where not exists(select 1 from rm_private.receiving_workshop_protocols l
  where l.submission_id=o.client_submission_id and l.workshop_id<>d.workshop_id)
 union all
 select m.result->>'projeto_id',m.result->>'equipamento_id',m.operator_id,d.workshop_id
 from rm_private.mobile_mutation_receipts m join legacy_device d on d.auth_user_id=m.auth_user_id
 where m.rpc_name='rm_submit_recebimento_v1' and nullif(m.params->>'p_projeto_id','') is null
  and m.result->'updated_existing' is distinct from 'true'::jsonb
  and m.result->'resource_deleted' is distinct from 'true'::jsonb
  and not exists(select 1 from rm_private.receiving_workshop_protocols l
   where l.submission_id=m.client_submission_id and l.workshop_id<>d.workshop_id)
)
select p.id from rm_private.workshop_project_ownership p
 join rm_private.workshop_legacy_adoption b on b.singleton and b.legacy_workshop_id=p.workshop_id
union
-- Some older clients first see the project before the scoped gateway has
-- recorded ownership. Require the original device, author and equipment and
-- never let an old receipt override an authoritative or retired origin.
select p.id from proofs proof join public.rm_projetos p on p.id::text=proof.project_id and p.created_by_user_id=proof.operator_id
 join public.rm_equipamentos e on e.projeto_id=p.id and e.id=p.equipamento_id and e.id::text=proof.equipment_id
where not exists(select 1 from rm_private.workshop_project_ownership o where o.id=p.id)
 and not exists(select 1 from rm_private.workshop_object_origins o where o.object_kind='project' and o.object_id=p.id)
 and not exists(select 1 from rm_private.workshop_origin_retirements o where o.object_kind='project' and o.object_id=p.id)
 and (p.cliente_id is null or rm_private.workshop_read_owned_v1('client',p.cliente_id,proof.workshop_id))
 and (p.tipo_equipamento_id is null or rm_private.workshop_read_owned_v1('equipment_type',p.tipo_equipamento_id,proof.workshop_id))
 and (e.tipo_equipamento_id is null or rm_private.workshop_read_owned_v1('equipment_type',e.tipo_equipamento_id,proof.workshop_id));

create view rm_private.workshop_legacy_bma_operation_rows as
with bma as materialized (select legacy_workshop_id id from rm_private.workshop_legacy_adoption where singleton),
 projects as materialized (select p.id from rm_private.workshop_legacy_bma_projects p),
 cells as materialized (select c.cell_id id from rm_private.workshop_cell_ownership c join bma on bma.id=c.workshop_id),
 allocations as materialized (select a.id,a.projeto_id,a.celula_id from public.rm_celulas_projeto a
  join projects p on p.id=a.projeto_id join cells c on c.id=a.celula_id),
 records as materialized (select r.id,r.projeto_id,r.celula_id,r.form_id from public.rm_registros_formulario r join projects p on p.id=r.projeto_id cross join bma
  where (r.celula_id is null or r.celula_id in(select id from cells))
   and rm_private.workshop_read_owned_v1('form_model',r.form_id,bma.id))
select 'rm_projetos'::text resource,id from projects
union all select 'rm_equipamentos',r.id from public.rm_equipamentos r join projects p on p.id=r.projeto_id
union all select 'rm_celulas_projeto',id from allocations
union all select 'rm_registros_formulario',id from records
union all select 'rm_aprovacoes_registro',r.id from public.rm_aprovacoes_registro r join records f on f.id=r.registro_formulario_id
 where (r.projeto_id is null or r.projeto_id=f.projeto_id) and (r.celula_id is null or r.celula_id=f.celula_id)
  and (r.form_id is null or r.form_id=f.form_id)
union all select 'rm_aprovacoes_etapas',r.id from public.rm_aprovacoes_etapas r join cells c on c.id=r.celula_origem_id
 where (r.celula_destino_id is null or r.celula_destino_id in(select id from cells))
  and ((r.projeto_id is null and r.celula_projeto_id is null)
   or (r.projeto_id in(select id from projects) and (r.celula_projeto_id is null or exists(select 1 from allocations a
    where a.id=r.celula_projeto_id and a.projeto_id=r.projeto_id and a.celula_id=r.celula_origem_id))))
union all select 'rm_comentarios',r.id from public.rm_comentarios r join projects p on p.id=r.projeto_id
 where r.celula_id is null or r.celula_id in(select id from cells)
union all select 'rm_logs_aprovacao',r.id from public.rm_logs_aprovacao r join projects p on p.id=r.projeto_id
 where r.celula_id is null or r.celula_id in(select id from cells)
union all select 'rm_docs',r.id from public.rm_docs r join projects p on p.id=r.projeto_id
union all select 'rm_documentos',r.id from public.rm_documentos r join projects p on p.id=r.projeto_id
union all select 'rm_fotos',r.id from public.rm_fotos r cross join bma
 where (r.celula_id is null or r.celula_id in(select id from cells))
  and ((r.projeto_id is null and r.celula_projeto_id is null and rm_private.workshop_mobile_cell_type_owned_v1(r.celula_tipo_equipamento_id,bma.id))
   or (r.projeto_id in(select id from projects) and (r.celula_projeto_id is null or exists(select 1 from allocations a
    where a.id=r.celula_projeto_id and a.projeto_id=r.projeto_id and (r.celula_id is null or a.celula_id=r.celula_id)))));
revoke all on rm_private.workshop_legacy_bma_projects,rm_private.workshop_legacy_bma_operation_rows from public,anon,authenticated,service_role;

create function rm_private.workshop_legacy_bma_operation_ids_v1(p_resource text)
returns setof uuid language sql stable security definer set search_path='' as $$
 select r.id from rm_private.workshop_legacy_bma_operation_rows r
 where r.resource=p_resource and (select rm_private.workshop_legacy_bma_device_v1());
$$;
revoke all on function rm_private.workshop_legacy_bma_operation_ids_v1(text) from public,anon,authenticated,service_role;
grant execute on function rm_private.workshop_legacy_bma_operation_ids_v1(text) to authenticated;

create function rm_private.activate_workshop_legacy_bma_operations_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
declare target record;
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop-legacy-bma-catalog',119));
 if not exists(select 1 from rm_private.workshop_legacy_catalog_access where singleton) then
  raise exception 'Ative o recorte de catálogos do dispositivo legado antes das operações.' using errcode='PT409';
 end if;
 for target in select name,'id' field,name resource from unnest(array[
  'rm_projetos','rm_equipamentos','rm_celulas_projeto','rm_registros_formulario','rm_aprovacoes_registro','rm_aprovacoes_etapas',
  'rm_comentarios','rm_logs_aprovacao','rm_docs','rm_documentos','rm_fotos'
 ]) name union all select 'rm_respostas','registro_formulario_id','rm_registros_formulario' loop
  if not exists(select 1 from pg_policy where polname='rm_legacy_bma_operations_read' and polrelid=to_regclass('public.'||target.name)) then
   execute format('create policy rm_legacy_bma_operations_read on public.%I as restrictive for select to authenticated
    using(%I in(select rm_private.workshop_legacy_bma_operation_ids_v1(%L)))',target.name,target.field,target.resource);
  end if;
 end loop;
end
$$;
revoke all on function rm_private.activate_workshop_legacy_bma_operations_v1() from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;

begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_overview_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare projects boolean; forms boolean; planning boolean; documents boolean; result jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object'
  or (select array_agg(k order by k) from jsonb_object_keys(p_args) k) is distinct from array['documents','forms','planning','projects']
  or exists(select 1 from jsonb_each(p_args) value where jsonb_typeof(value.value)<>'boolean') then
  raise exception 'Indicadores solicitados inválidos.' using errcode='22023';
 end if;
 projects:=(p_args->>'projects')::boolean;
 forms:=(p_args->>'forms')::boolean;
 planning:=(p_args->>'planning')::boolean;
 documents:=(p_args->>'documents')::boolean;
 with own_projects as materialized (
  select p.id,p.numero,p.nome,p.descricao_equipamento,p.status_pcp,p.data_real_de_entrega,p.updated_at,p.cliente_id,p.cliente_nome_exportacao
  from public.rm_projetos p where projects and rm_private.workshop_project_owned_v1(p.id,p_office)
 ), pending as materialized (
  select r.id,r.numero_projeto_rm,r.codigo,r.codigo_text,r.updated_at from public.rm_registros_formulario r
  where forms and r.status='em_an_lise' and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office)
 ), late as materialized (
  select a.id,a.projeto_id,a.numero_projeto,a.data_limite from public.rm_celulas_projeto a
  where planning and not a.retirada and a.visibilidade and a.status<>'finalizado' and a.data_limite<statement_timestamp()
   and rm_private.workshop_project_owned_v1(a.projeto_id,p_office) and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)
 )
 select jsonb_build_object('counts',jsonb_build_object(
  'projects',case when projects then (select count(*) from own_projects) end,
  'activeProjects',case when projects then (select count(*) from own_projects where data_real_de_entrega is null
   and (status_pcp is null or status_pcp not in('cancelado','finalizando_para_faturar'))) end,
  'awaitingReview',case when forms then (select count(*) from pending) end,
  'overdueCells',case when planning then (select count(*) from late) end,
  'documents',case when documents then (select count(*) from public.rm_documentos d where rm_private.workshop_project_owned_v1(d.projeto_id,p_office))
   +(select count(*) from public.rm_docs d where rm_private.workshop_project_owned_v1(d.projeto_id,p_office)) end),
  'recentProjects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,
   'descricao_equipamento',p.descricao_equipamento,'status_pcp',p.status_pcp,'cliente_nome',coalesce(nullif(c.nome,''),p.cliente_nome_exportacao))
   order by p.updated_at desc,p.id) from (select * from own_projects order by updated_at desc,id limit 8) p
   left join public.rm_clientes c on c.id=p.cliente_id and rm_private.workshop_read_owned_v1('client',c.id,p_office)),'[]'),
  'recentRecords',coalesce((select jsonb_agg(to_jsonb(r) order by updated_at desc,id)
   from (select * from pending order by updated_at desc,id limit 8) r),'[]'),
  'overdue',coalesce((select jsonb_agg(to_jsonb(a) order by data_limite,id) from (select * from late order by data_limite,id limit 8) a),'[]'))
 into result;
 return result;
end
$$;
revoke all on function rm_private.workshop_overview_v1(jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview')
);
do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 tail text:='''planning_export'',''media_reference'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,tail),1) is distinct from 2 or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,tail,'''planning_export'',''media_reference'',''overview'')');
 execute replace(reader,dispatch,'  when ''overview'' then rm_private.workshop_overview_v1(p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;

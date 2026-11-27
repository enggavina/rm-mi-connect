begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.project_route_cell_snapshot_v2(p_project_id uuid,p_allocation_id uuid,p_include_choices boolean,p_office uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 p public.rm_projetos%rowtype;
 a public.rm_celulas_projeto%rowtype;
 closed boolean;
 metadata jsonb;
 form_rows jsonb;
 catalog_ids uuid[];
 missing_form boolean;
 complete boolean;
 form_reason text;
 version text;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501';end if;
 select * into p from public.rm_projetos where id=p_project_id;
 if not found or (p_office is not null and not rm_private.workshop_project_owned_v1(p.id,p_office)) then return null;end if;
 select * into a from public.rm_celulas_projeto where id=p_allocation_id and projeto_id=p.id;
 if not found then return null;end if;
 if p_office is not null and (not rm_private.workshop_cell_owned_v1(a.celula_id,p_office)
  or exists(select 1 from unnest(a.forms_ids) assigned where not rm_private.workshop_read_owned_v1('form_model',assigned,p_office))) then
  return null;
 end if;

 closed:=p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false);
 metadata:=rm_private.route_cell_removal_metadata_v1(a.id);
 select coalesce(array_agg(f.id),'{}') into catalog_ids from public.rm_forms f
 where (f.ativo or f.id=any(a.forms_ids)) and (p_office is null or rm_private.workshop_read_owned_v1('form_model',f.id,p_office));
 missing_form:=not (catalog_ids @> a.forms_ids);
 complete:=cardinality(catalog_ids)<=2000 and cardinality(a.forms_ids)<=2000 and not missing_form;
 form_reason:=case when closed then 'Projeto encerrado: somente consulta.'
  when a.retirada then 'Célula retirada: restaure o contexto antes de configurar.'
  when a.status in('finalizado','n_a') then 'Célula concluída ou N/A: somente consulta.'
  when missing_form then 'Há vínculo de formulário indisponível que exige reconciliação.'
  when not complete or cardinality(a.forms_ids)>500 then 'O conjunto excede o limite de edição completa.' end;
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'titulo',coalesce(f.titulo,f.title),'ativo',f.ativo,'assigned',f.id=any(a.forms_ids),
  'can_remove',f.id=any(a.forms_ids) and rm_private.route_cell_form_used_v1(p.id,a.celula_id,f.id) is null,
  'reason',case when f.id=any(a.forms_ids) then rm_private.route_cell_form_used_v1(p.id,a.celula_id,f.id) end)
  order by coalesce(f.titulo,f.title),f.id),'[]') into form_rows
 from public.rm_forms f where complete and f.id=any(catalog_ids) and (f.id=any(a.forms_ids) or (p_include_choices and f.ativo));
 version:=encode(sha256(convert_to(jsonb_build_object('project',p.id,'project_version',p.updated_at,'allocation',to_jsonb(a),
  'evidence',metadata->>'fingerprint','catalog',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'updated_at',f.updated_at) order by f.id)
   from public.rm_forms f where f.id=any(catalog_ids)),'[]'))::text,'UTF8')),'hex');
 return jsonb_build_object('project',jsonb_build_object('id',p.id,'numero',p.numero,'status_pcp',p.status_pcp,'data_real_de_entrega',p.data_real_de_entrega,'updated_at',p.updated_at,'closed',closed),
  'allocation',jsonb_build_object('id',a.id,'projeto_id',p.id,'celula_id',a.celula_id,'celula_nome',(select nome from public.rm_celulas where id=a.celula_id),'status',a.status,'retirada',a.retirada,'updated_at',a.updated_at,'forms_ids',a.forms_ids),
  'forms',form_rows,'context_version',version,'can_edit_forms',form_reason is null,'forms_reason',form_reason,
  'can_remove_cell',not closed and complete and metadata is not null and metadata->>'remove_reason' is null,
  'remove_reason',case when closed then 'Projeto encerrado: somente consulta.' when not complete then coalesce(form_reason,'O conjunto exige conferência completa antes de remover.') else metadata->>'remove_reason' end,
  'removal_counts',jsonb_build_object('photos',(metadata->>'photo_count')::int,'rules',(metadata->>'rule_count')::int,'reviewer_assignments',(metadata->>'reviewer_count')::int),'complete',complete);
end
$$;

create or replace function public.rm_web_project_route_cell_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_choices boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 return rm_private.project_route_cell_snapshot_v2(p_project_id,p_allocation_id,p_include_choices,null);
end
$$;

create function rm_private.workshop_project_route_cell_read_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
begin
 if p_office is null or jsonb_typeof(p_args->'project') is distinct from 'string'
  or jsonb_typeof(p_args->'allocation') is distinct from 'string' or jsonb_typeof(p_args->'include') is distinct from 'boolean' then
  raise exception 'Configuração de célula inválida.' using errcode='22023';
 end if;
 return rm_private.project_route_cell_snapshot_v2((p_args->>'project')::uuid,(p_args->>'allocation')::uuid,(p_args->>'include')::boolean,p_office);
end
$$;
revoke all on function rm_private.project_route_cell_snapshot_v2(uuid,uuid,boolean,uuid),
 rm_private.workshop_project_route_cell_read_v1(jsonb,uuid) from public,anon,authenticated,service_role;

do $install$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_before_document_folders_v1(uuid,text,jsonb)'::regprocedure);
 allowed constant text:='''project_equipment'',''project_route'')';
 dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 snapshot constant text:='snapshot:=public.rm_web_project_route_cell_snapshot_v1(project_id,allocation_id,true);';
 constraint_definition text;
begin
 if array_length(string_to_array(issuer,allowed),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2
  or array_length(string_to_array(writer,snapshot),1) is distinct from 4 then
  raise exception 'Unexpected workshop route cell contract';
 end if;
 select pg_get_constraintdef(oid) into strict constraint_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(constraint_definition from 8 for char_length(constraint_definition)-8)||') or resource=''project_route_cell'')';
 execute replace(issuer,allowed,'''project_equipment'',''project_route'',''project_route_cell'')');
 execute replace(reader,dispatch,'  when ''project_route_cell'' then rm_private.workshop_project_route_cell_read_v1(p_args,permit.workshop_id)'||chr(10)||dispatch);
 -- The planning wrapper validates and locks the permit before invoking the existing writer.
 execute replace(writer,snapshot,$scoped$snapshot:=rm_private.project_route_cell_snapshot_v2(project_id,allocation_id,true,
   (select workshop_id from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id and operation=p_operation));$scoped$);
end
$install$;

create function rm_private.activate_project_route_cell_workshop_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 if not exists(select 1 from rm_private.workshop_dossier_settings where singleton and enforced)
  or not exists(select 1 from rm_private.cell_availability_workshop_enforcement where singleton) then
  raise exception 'Ative o dossiê e a configuração de alocações por oficina.' using errcode='PT409';
 end if;
 revoke execute on function public.rm_web_project_route_cell_snapshot_v1(uuid,uuid,boolean) from authenticated;
 notify pgrst,'reload schema';
end
$$;
revoke all on function rm_private.activate_project_route_cell_workshop_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

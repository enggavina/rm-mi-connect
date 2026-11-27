begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_mobile_cell_type_owned_v1(p_id uuid,p_office uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from public.rm_celula_tipos_equipamento c where c.id=p_id
  and rm_private.workshop_cell_owned_v1(c.celula_id,p_office)
  and rm_private.workshop_read_owned_v1('equipment_type',c.tipo_equipamento_id,p_office))
$$;
create function rm_private.workshop_mobile_actor_visible_v1(p_actor uuid,p_operator uuid,p_office uuid) returns boolean
language sql stable set search_path='' as $$
 select p_actor=p_operator
  or exists(select 1 from public.rm_tablet_celula_users c where p_actor in(c.usuario_id,c.identidade_id)
   and rm_private.workshop_cell_owned_v1(c.celula_id,p_office))
  or exists(select 1 from public.rm_projetos p where p_actor in(p.created_by_user_id,p.gestor_responsavel_id)
   and rm_private.workshop_project_owned_v1(p.id,p_office))
  or exists(select 1 from public.rm_celulas_projeto a where p_actor=a.responsavel_id
   and rm_private.workshop_project_owned_v1(a.projeto_id,p_office) and rm_private.workshop_cell_owned_v1(a.celula_id,p_office))
  or exists(select 1 from public.rm_registros_formulario r
   where (p_actor in(r.created_by_user_id,r.identidade_user_id,r.responsavel_user_id,r.avaliador_user_id,r.user_revisao_id)
    or p_actor=any(r.aprovadores_ids)) and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office))
  or exists(select 1 from public.rm_comentarios c where p_actor=c.cadastrado_por_id and rm_private.workshop_project_owned_v1(c.projeto_id,p_office)
   and (c.celula_id is null or rm_private.workshop_cell_owned_v1(c.celula_id,p_office)))
  or exists(select 1 from public.rm_fotos f where p_actor in(f.created_by_user_id,f.modified_by_id) and not f.lixeira
   and rm_private.workshop_project_owned_v1(f.projeto_id,p_office) and (f.celula_id is null or rm_private.workshop_cell_owned_v1(f.celula_id,p_office)))
  or exists(select 1 from public.rm_aprovacoes_etapas s where (p_actor in(s.aprovador_id,s.aprovado_por_id)
   or p_actor=any(s.aprovadores_ids) or p_actor=any(s.aprovadores_retorno_ids)) and rm_private.workshop_stage_owned_v1(s.id,p_office))
  or exists(select 1 from public.rm_logs_aprovacao h where p_actor=h.aprovador_id and rm_private.workshop_project_owned_v1(h.projeto_id,p_office)
   and (h.celula_id is null or rm_private.workshop_cell_owned_v1(h.celula_id,p_office)))
$$;
revoke all on function rm_private.workshop_mobile_cell_type_owned_v1(uuid,uuid),
 rm_private.workshop_mobile_actor_visible_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

do $extend$
declare
 definition text:=pg_get_functiondef('public.rm_mobile_workshop_catalog_v1(uuid,uuid,text,jsonb,text,timestamptz,uuid,boolean)'::regprocedure);
 end_of_tables text:='  else null end;';
 row_value text:='when p_ids_only then ''jsonb_build_object(''''id'''',r.id,''''updated_at'''',r.updated_at)'' else ''to_jsonb(r)'' end';
begin
 if array_length(string_to_array(definition,end_of_tables),1) is distinct from 2
  or array_length(string_to_array(definition,row_value),1) is distinct from 2 then raise exception 'Unexpected mobile catalogue projection';end if;
 definition:=replace(definition,end_of_tables,$tables$
  when 'rm_users' then 'rm_private.workshop_mobile_actor_visible_v1(r.id,$2,$1)'
  when 'rm_tablet_celula_users' then 'rm_private.workshop_cell_owned_v1(r.celula_id,$1) and rm_private.operator_can_access_cell($2,r.celula_id)'
  when 'rm_celula_tipos_equipamento' then 'rm_private.workshop_mobile_cell_type_owned_v1(r.id,$1)'
  when 'rm_celula_form_tipos_equipamento' then 'rm_private.workshop_mobile_cell_type_owned_v1(r.celula_tipo_equipamento_id,$1)
   and rm_private.workshop_read_owned_v1(''form_model'',r.form_id,$1)'
  when 'rm_fotos' then 'not r.lixeira and ((r.projeto_id is null and r.celula_projeto_id is null
    and rm_private.workshop_mobile_cell_type_owned_v1(r.celula_tipo_equipamento_id,$1))
   or (rm_private.workshop_project_owned_v1(r.projeto_id,$1)
    and (r.celula_id is null or rm_private.workshop_cell_owned_v1(r.celula_id,$1))
    and (r.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a where a.id=r.celula_projeto_id
     and a.projeto_id=r.projeto_id and rm_private.workshop_cell_owned_v1(a.celula_id,$1)
     and (r.celula_id is null or r.celula_id=a.celula_id)))))'
  when 'rm_registros_formulario' then 'rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,$1)'
  when 'rm_respostas' then 'exists(select 1 from public.rm_registros_formulario f where f.id=r.registro_formulario_id
   and rm_private.workshop_form_record_owned_v1(f.projeto_id,f.celula_id,f.form_id,$1))'
  when 'rm_aprovacoes_etapas' then 'rm_private.workshop_stage_owned_v1(r.id,$1)'
  when 'rm_comentarios' then 'rm_private.workshop_project_owned_v1(r.projeto_id,$1)
   and (r.celula_id is null or rm_private.workshop_cell_owned_v1(r.celula_id,$1))'
  when 'rm_logs_aprovacao' then 'rm_private.workshop_project_owned_v1(r.projeto_id,$1)
   and (r.celula_id is null or rm_private.workshop_cell_owned_v1(r.celula_id,$1))'
  when 'rm_documentos' then 'rm_private.workshop_project_owned_v1(r.projeto_id,$1)'
  when 'rm_docs' then 'rm_private.workshop_project_owned_v1(r.projeto_id,$1)'
  when 'rm_cadastro_fotos' then 'false'
  else null end;$tables$);
 execute replace(definition,row_value,$fields$when p_ids_only then 'jsonb_build_object(''id'',r.id,''updated_at'',r.updated_at)'
  when p_table='rm_users' then 'jsonb_build_object(''id'',r.id,''nome'',r.nome,''cargo'',r.cargo,''perfil'',r.perfil,''status'',r.status,''updated_at'',r.updated_at)'
  else 'to_jsonb(r)' end$fields$);
end
$extend$;
notify pgrst,'reload schema';
commit;

begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The native pull uses the same verified device, operator and office as
-- Recebimentos. Batch boundaries are applied only after ownership filtering.
create function public.rm_mobile_workshop_catalog_v1(p_auth_user_id uuid,p_session_id uuid,p_operator_token text,
 p_workshop_context jsonb,p_table text,p_after_at timestamptz,p_after_id uuid,p_ids_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare operator_id uuid; office_id uuid; predicate text; projection text; result jsonb;
begin
 if p_ids_only is null or (p_after_at is null)<>(p_after_id is null)
  or (p_after_at is not null and not isfinite(p_after_at)) then
  raise exception 'Posição do catálogo inválida.' using errcode='22023';
 end if;
 select i.operator_subject into operator_id from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
 if operator_id is null then raise exception 'Identificação inválida.' using errcode='28000';end if;
 office_id:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,operator_id);
 if office_id is null then raise exception 'Oficina indisponível.' using errcode='42501';end if;

 predicate:=case p_table
  when 'rm_celulas' then 'rm_private.workshop_cell_owned_v1(r.id,$1) and rm_private.operator_can_access_cell($2,r.id)'
  when 'rm_projetos' then 'rm_private.workshop_project_owned_v1(r.id,$1) and r.data_real_de_entrega is null
   and (r.status_pcp is null or r.status_pcp not in(''cancelado'',''finalizando_para_faturar''))'
  when 'rm_celulas_projeto' then 'rm_private.workshop_project_owned_v1(r.projeto_id,$1)
   and rm_private.workshop_cell_owned_v1(r.celula_id,$1) and rm_private.operator_can_access_cell($2,r.celula_id)'
  when 'rm_equipamentos' then 'rm_private.workshop_project_owned_v1(r.projeto_id,$1)'
  when 'rm_clientes' then 'rm_private.workshop_read_owned_v1(''client'',r.id,$1)'
  when 'rm_tipos_equipamento' then 'rm_private.workshop_read_owned_v1(''equipment_type'',r.id,$1)'
  when 'rm_forms' then 'rm_private.workshop_read_owned_v1(''form_model'',r.id,$1)'
  when 'rm_questoes' then 'rm_private.workshop_read_owned_v1(''form_model'',r.form_id,$1)'
  when 'rm_itens_questoes' then 'rm_private.workshop_read_owned_v1(''form_model'',r.form_id,$1)'
  else null end;
 if predicate is null then raise exception 'Catálogo inválido.' using errcode='22023';end if;
 projection:=case when p_ids_only then 'jsonb_build_object(''id'',r.id,''updated_at'',r.updated_at)' else 'to_jsonb(r)' end;
 execute format($query$
  with page as materialized (
   select r.id,case when not $6 then r.updated_at end sort_time,%s value from public.%I r where (%s)
    and ($4::uuid is null or ($6 and r.id>$4) or (not $6 and (r.updated_at,r.id)>($3::timestamptz,$4)))
   order by sort_time,r.id limit 251
  ), visible as materialized (select * from page order by sort_time,id limit 250)
  select jsonb_build_object('workshop_id',$1,'table',$5,'complete',(select count(*)<=250 from page),
   'rows',coalesce((select jsonb_agg(value order by sort_time,id) from visible),'[]'::jsonb))$query$,
  projection,p_table,predicate) into result using office_id,operator_id,p_after_at,p_after_id,p_table,p_ids_only;
 if octet_length(result::text)>8388608 then
  raise exception 'A página do catálogo excedeu o limite de sincronização.' using errcode='PT413';
 end if;
 return result;
end
$$;
revoke all on function public.rm_mobile_workshop_catalog_v1(uuid,uuid,text,jsonb,text,timestamptz,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_workshop_catalog_v1(uuid,uuid,text,jsonb,text,timestamptz,uuid,boolean) to service_role;
notify pgrst,'reload schema';
commit;

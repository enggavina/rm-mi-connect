-- One read-only snapshot, under the caller's RLS, for one worksheet per cell.
begin;
create function rm_private.web_planning_export_allowed_v1() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in('administrador','padr_o','auditor'))
 and(not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.factor_type='totp' and f.status='verified') or auth.jwt()->>'aal'='aal2');
$$;
revoke all on function rm_private.web_planning_export_allowed_v1() from public,anon,authenticated,service_role;
grant execute on function rm_private.web_planning_export_allowed_v1() to authenticated;

-- Opaque batch validation: only a subset of already-supplied equipment IDs is
-- returned. Hidden project identities, names and other fields never leave it.
create function rm_private.web_export_shared_equipment_v1(p_equipment_ids uuid[]) returns uuid[]
language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(rm_private.web_planning_export_allowed_v1(),false) then raise exception 'Acesso não autorizado.' using errcode='42501';end if;
 if p_equipment_ids is null or cardinality(p_equipment_ids)>20000 then raise exception 'Seleção inválida.' using errcode='22023';end if;
 return array(select p.equipamento_id from public.rm_projetos p where p.equipamento_id=any(p_equipment_ids) group by p.equipamento_id having count(*)>1);
end $$;
revoke all on function rm_private.web_export_shared_equipment_v1(uuid[]) from public,anon,authenticated,service_role;
grant execute on function rm_private.web_export_shared_equipment_v1(uuid[]) to authenticated;

create function public.rm_web_planning_export_snapshot_v1(p_cell_ids uuid[],p_fields text[]) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare valid_fields constant text[]:=array[
 'project_number','project_name','client_name','project_status','project_pcp_status','arrival_at','project_planned_start','project_planned_end','contract_date','renegotiated_date',
 'inspection_start','inspection_end','repair_start','repair_end','project_delivered_at','project_manager','project_scope',
 'equipment_type','equipment_description','manufacturer','model','serial_number','power','motor_plate','voltage','current','speed','frequency','weight',
 'cell_name','allocation_status','allocation_start','allocation_due','allocation_finished','allocation_responsible','priority','visible','blocked','block_reason','delay_reason','planned_hours','actual_hours','allocation_note'];
 n bigint;labels jsonb;result jsonb;
begin
 if not coalesce(rm_private.web_planning_export_allowed_v1(),false) then raise exception 'Acesso à exportação não autorizado.' using errcode='42501';end if;
 if p_cell_ids is null or p_fields is null or array_ndims(p_cell_ids) is distinct from 1 or array_ndims(p_fields) is distinct from 1
 or cardinality(p_cell_ids) not between 1 and 200 or cardinality(p_fields) not between 1 and cardinality(valid_fields)
 or exists(select 1 from unnest(p_cell_ids) x where x is null) or exists(select 1 from unnest(p_fields) x where x is null or not x=any(valid_fields))
 or (select count(distinct x) from unnest(p_cell_ids) x)<>cardinality(p_cell_ids)
 or (select count(distinct x) from unnest(p_fields) x)<>cardinality(p_fields) then raise exception 'Selecione células e campos válidos, sem repetições.' using errcode='22023';end if;
 -- Every check and join below executes as the caller. A selected cell or
 -- project hidden by RLS cannot be recovered through the export function.
 if(select count(*) from public.rm_celulas where id=any(p_cell_ids))<>cardinality(p_cell_ids) then
  raise exception 'Uma célula não está disponível para exportação.' using errcode='42501';end if;
 if exists(select 1 from public.rm_celulas_projeto a left join public.rm_projetos p on p.id=a.projeto_id
  where a.celula_id=any(p_cell_ids) and not a.retirada and p.id is null) then
  raise exception 'Um projeto da seleção não está disponível para exportação.' using errcode='42501';end if;
 select count(*) into n from public.rm_celulas_projeto a where a.celula_id=any(p_cell_ids) and not a.retirada;
 if n>20000 then raise exception 'A seleção excede 20.000 alocações. Exporte menos células por vez.' using errcode='PT413';end if;
 select coalesce(jsonb_object_agg(option_set_key||'.'||option_key,bubble_display),'{}') into labels from public.rm_option_sets
  where option_set_key in('status_rm','status_pcp','status_cel_proj','prioridade0','placa_motor');
 with selected as materialized(select c.id,c.nome,w.ord from unnest(p_cell_ids) with ordinality w(id,ord) join public.rm_celulas c on c.id=w.id),
 shared_equipment as materialized(select rm_private.web_export_shared_equipment_v1(array(select distinct p.equipamento_id from public.rm_projetos p
  join public.rm_celulas_projeto a on a.projeto_id=p.id where a.celula_id=any(p_cell_ids) and not a.retirada and p.equipamento_id is not null)) ids),
 source as materialized(
  select a.id allocation_id,a.projeto_id project_id,a.celula_id,a.posicao,p.numero,
   jsonb_build_object(
    'project_number',p.numero,'project_name',p.nome,'client_name',coalesce(nullif(cl.nome,''),nullif(p.cliente_nome_exportacao,'')),
    'project_status',labels->>('status_rm.'||p.status::text),'project_pcp_status',labels->>('status_pcp.'||p.status_pcp::text),
    'arrival_at',p.chegada_do_equipamento,'project_planned_start',p.data_prevista_inicio,'project_planned_end',p.data_prevista_final,
    'contract_date',p.data_contratual,'renegotiated_date',p.data_renegociada,'inspection_start',p.data_inicio_peritagem,'inspection_end',p.data_fim_peritagem,
    'repair_start',p.data_inicio_reparo,'repair_end',p.data_fim_reparo,'project_delivered_at',p.data_real_de_entrega,'project_manager',mgr.nome,'project_scope',p.escopo_abreviado,
    'equipment_type',case when t.id is not null then concat_ws(' - ',nullif(btrim(t.sigla),''),nullif(btrim(t.nome),'')) end,
    'equipment_description',e.descricao,'manufacturer',e.fabricante,'model',e.modelo,'serial_number',e.numero_serie,'power',e.potencia,
    'motor_plate',labels->>('placa_motor.'||e.placa_motor::text),'voltage',e.tensao_estator,'current',e.corrente_estator,'speed',e.rotacao,'frequency',e.frequencia,'weight',e.peso,
    'cell_name',c.nome,'allocation_status',labels->>('status_cel_proj.'||a.status::text),'allocation_start',a.data_inicio,'allocation_due',a.data_limite,
    'allocation_finished',a.data_fim_real,'allocation_responsible',resp.nome,'priority',labels->>('prioridade0.'||a.prioridade::text),
    'visible',case when a.visibilidade then 'Sim' else 'Não' end,'blocked',case a.bloqueada when 'sim' then 'Sim' when 'n_o' then 'Não' end,
    'block_reason',a.motivo_bloqueio,'delay_reason',a.motivo_atraso,'planned_hours',a.horas_previstas,'actual_hours',a.horas_realizadas,'allocation_note',a.observacao
   ) field_values
  from public.rm_celulas_projeto a join selected c on c.id=a.celula_id join public.rm_projetos p on p.id=a.projeto_id
  left join public.rm_clientes cl on cl.id=p.cliente_id left join public.rm_users mgr on mgr.id=p.gestor_responsavel_id
  left join public.rm_users resp on resp.id=a.responsavel_id
  left join public.rm_equipamentos e on e.id=p.equipamento_id and e.projeto_id=p.id and not e.id=any((select ids from shared_equipment)::uuid[])
  left join public.rm_tipos_equipamento t on t.id=e.tipo_equipamento_id
  where not a.retirada
 ), sheets as(
  select c.id,c.nome,c.ord,coalesce(jsonb_agg(jsonb_build_object('allocation_id',s.allocation_id,'project_id',s.project_id,
   'values',(select jsonb_object_agg(k,s.field_values->k) from unnest(p_fields) k)) order by s.posicao nulls last,s.numero nulls last,s.allocation_id)
   filter(where s.allocation_id is not null),'[]') rows
  from selected c left join source s on s.celula_id=c.id group by c.id,c.nome,c.ord
 ) select jsonb_build_object('generated_at',statement_timestamp(),'fields',to_jsonb(p_fields),'row_count',n,'complete',true,
   'cells',jsonb_agg(jsonb_build_object('id',id,'name',nome,'rows',rows) order by ord)) into result from sheets;
 if octet_length(result::text)>20971520 then raise exception 'Os dados da seleção excedem o limite de exportação. Exporte menos células ou campos por vez.' using errcode='PT413';end if;
 return result;
end $$;
revoke all on function public.rm_web_planning_export_snapshot_v1(uuid[],text[]) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_planning_export_snapshot_v1(uuid[],text[]) to authenticated;
notify pgrst,'reload schema';
commit;

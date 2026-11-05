-- A read-only projection of the journals already written by the mutation
-- envelopes. No second audit store, triggers, backfill or operational writes.
begin;

create function rm_private.project_audit_changes_v1(p_before jsonb,p_after jsonb,p_fields text[])
returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('field',f,'before',p_before->f,'after',p_after->f) order by n),'[]'::jsonb)
 from unnest(p_fields) with ordinality x(f,n)
 where p_after ? f and (p_before is null or p_before->f is distinct from p_after->f);
$$;
revoke all on function rm_private.project_audit_changes_v1(jsonb,jsonb,text[]) from public,anon,authenticated,service_role;

create function rm_private.project_audit_events_v1(p_project_id uuid,p_kind text,p_topics text[])
returns table(event_id text,topic text,action text,entity_id uuid,celula_id uuid,celula_projeto_id uuid,
 actor_id uuid,occurred_at timestamptz,source text,prior_evidence boolean,changes jsonb,reason text)
language sql stable security definer set search_path='' as $$
 with web as materialized(
  select * from rm_private.web_mutation_receipts w where w.operation in
   ('plan_cell','save_cell_queue','save_project_route','manage_cell_availability','set_project_photo_selection',
    'manage_operational_photos','manage_stage_rules','assign_form_reviewer')
   and (w.result->>'projeto_id'=p_project_id::text or (w.operation='save_cell_queue' and exists(
    select 1 from jsonb_array_elements(coalesce(w.before_record->'items','[]')) i where i->>'projeto_id'=p_project_id::text)))
 ), mobile as materialized(
  select m.* from rm_private.mobile_mutation_receipts m where m.rpc_name in
   ('rm_update_cell_status_v1','rm_record_cell_photo_v1','rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_submit_recebimento_v1')
   and (m.result->>'projeto_id'=p_project_id::text or m.params->>'p_projeto_id'=p_project_id::text
    or exists(select 1 from public.rm_registros_formulario r where r.projeto_id=p_project_id
      and r.id::text=coalesce(m.result->>'registro_formulario_id',m.params->>'p_registro_formulario_id'))
    or exists(select 1 from public.rm_fotos f where f.projeto_id=p_project_id and f.id::text=m.result->>'foto_id'))
 ), events as (
  select 'route-instance:'||r.projeto_id event_id,'cells'::text topic,'route_initialized'::text action,
   r.projeto_id entity_id,null::uuid celula_id,null::uuid celula_projeto_id,r.actor_id,r.created_at occurred_at,'web'::text source,false prior_evidence,
   rm_private.project_audit_changes_v1(null,jsonb_build_object('tipo_equipamento_id',r.tipo_equipamento_id,
    'route_cell_count',jsonb_array_length(r.origin_snapshot)),array['tipo_equipamento_id','route_cell_count']) changes,null::text reason
  from rm_private.project_route_instances r where r.projeto_id=p_project_id and p_kind='cells'
  union all
  -- plan_cell writes the exact allocation before and after in the same receipt.
  select 'web:'||w.client_submission_id||':cell' event_id,'cells'::text topic,
   case when w.before_record is null then 'allocation_created' else 'allocation_changed' end action,
   a.id entity_id,a.celula_id,a.id celula_projeto_id,w.actor_id,w.created_at occurred_at,'web'::text source,
   w.before_record is not null prior_evidence,
   rm_private.project_audit_changes_v1(w.before_record,w.result->'record',array['data_inicio','data_limite','bloqueada',
    'motivo_bloqueio','motivo_atraso','observacao','visibilidade','prioridade','indice','posicao','horas_previstas',
    'horas_realizadas','responsavel_id','status','forms_ids']) changes,null::text reason
  from web w join public.rm_celulas_projeto a on a.id::text=w.result->>'id' and a.projeto_id=p_project_id
  where w.operation='plan_cell' and p_kind='cells'
  union all
  -- Queue receipts include all projects: scope EACH item, never the whole queue.
  select 'web:'||w.client_submission_id||':queue:'||a.id,'cells','queue_changed',a.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(old_item.value,jsonb_build_object('prioridade',item.value->'prioridade',
    'posicao',case when (w.payload->>'apply_order')::boolean then to_jsonb(item.ordinality) else old_item.value->'posicao' end),array['prioridade','posicao']),null
  from web w cross join lateral jsonb_array_elements(w.payload->'items') with ordinality item(value,ordinality)
   join public.rm_celulas_projeto a on a.id::text=item.value->>'id' and a.projeto_id=p_project_id
   join lateral jsonb_array_elements(w.before_record->'items') old_item on old_item.value->>'id'=a.id::text
    and old_item.value->>'projeto_id'=p_project_id::text
  where w.operation='save_cell_queue' and p_kind='cells' and w.result->'record'->'changed_ids' ? a.id::text
  union all
  select 'web:'||w.client_submission_id||':route:'||a.id,'cells','route_order_changed',a.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(old_item.value,jsonb_build_object('indice',item.ordinality),array['indice']),null
  from web w cross join lateral jsonb_array_elements(w.payload->'items') with ordinality item(value,ordinality)
   join public.rm_celulas_projeto a on a.id::text=item.value->>'id' and a.projeto_id=p_project_id
   join lateral jsonb_array_elements(w.before_record->'items') old_item on old_item.value->>'id'=a.id::text
  where w.operation='save_project_route' and p_kind='cells' and w.result->'record'->'changed_ids' ? a.id::text
  union all
  select 'web:'||w.client_submission_id||':availability','cells','allocation_'||(w.payload->>'action'),a.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(w.before_record->'allocation',w.result->'record',array['visibilidade','retirada']),null
  from web w join public.rm_celulas_projeto a on a.id::text=w.payload->>'celula_projeto_id' and a.projeto_id=p_project_id
  where w.operation='manage_cell_availability' and p_kind='cells' and jsonb_array_length(w.result->'record'->'changed_ids')>0
  union all
  select 'mobile:'||m.client_submission_id||':status','cells','allocation_status_changed',a.id,a.celula_id,a.id,m.operator_id,m.created_at,'mobile',false,
   rm_private.project_audit_changes_v1(null,jsonb_build_object('status',m.result->'status'),array['status']),null
  from mobile m join public.rm_celulas_projeto a on a.id::text=m.result->>'celula_projeto_id' and a.projeto_id=p_project_id
  where m.rpc_name='rm_update_cell_status_v1' and p_kind='cells'
  union all
  -- A forms_ids edit belongs to the allocation, and is also an operational link
  -- event. It is projected in both views from ONE existing receipt.
  select 'web:'||w.client_submission_id||':form-links','forms','form_links_changed',a.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',w.before_record is not null,
   rm_private.project_audit_changes_v1(w.before_record,w.result->'record',array['forms_ids']),null
  from web w join public.rm_celulas_projeto a on a.id::text=w.result->>'id' and a.projeto_id=p_project_id
  where w.operation='plan_cell' and p_kind='operations' and 'forms'=any(p_topics)
  union all
  select 'web:'||w.client_submission_id||':selection','photos','photo_selection_changed',f.id,f.celula_id,f.celula_projeto_id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(w.before_record,w.result->'record',array['selecao_relatorio']),null
  from web w join public.rm_fotos f on f.id::text=w.payload->>'foto_id' and f.projeto_id=p_project_id
  where w.operation='set_project_photo_selection' and p_kind='operations' and 'photos'=any(p_topics)
  union all
  select 'web:'||w.client_submission_id||':photo:'||f.id,'photos','photo_'||(w.payload->>'action'),f.id,f.celula_id,f.celula_projeto_id,w.actor_id,w.created_at,'web',w.payload->>'action'<>'add',
   case w.payload->>'action'
    when 'add' then rm_private.project_audit_changes_v1(null,jsonb_build_object('titulo',title_row.value->'titulo','categoria_foto','obrigat_ria'),array['titulo','categoria_foto'])
    when 'tag' then rm_private.project_audit_changes_v1(old_photo.value,jsonb_build_object('tag',w.payload->'tag'),array['tag'])
    else rm_private.project_audit_changes_v1(jsonb_build_object('lixeira',old_photo.value->'retired'),jsonb_build_object('lixeira',w.payload->>'action'='retire'),array['lixeira']) end,null
  from web w cross join lateral jsonb_array_elements_text(w.result->'record'->'changed_ids') changed(id)
   join public.rm_fotos f on f.id::text=changed.id and f.projeto_id=p_project_id
   left join lateral jsonb_array_elements(coalesce(w.before_record->'photos','[]')) old_photo on old_photo.value->>'id'=f.id::text
   left join lateral jsonb_array_elements(coalesce(w.payload->'items','[]')) added on added.value->>'id'=f.id::text
   left join lateral jsonb_array_elements(coalesce(w.before_record->'titles','[]')) title_row on title_row.value->>'id'=added.value->>'cadastro_foto_id'
  where w.operation='manage_operational_photos' and p_kind='operations' and 'photos'=any(p_topics)
  union all
  select 'mobile:'||m.client_submission_id||':photo','photos','photo_captured',f.id,f.celula_id,f.celula_projeto_id,m.operator_id,m.created_at,'mobile',false,
   rm_private.project_audit_changes_v1(null,jsonb_build_object('captured',true),array['captured']),null
  from mobile m join public.rm_fotos f on f.id::text=m.result->>'foto_id' and f.projeto_id=p_project_id
  where m.rpc_name='rm_record_cell_photo_v1' and p_kind='operations' and 'photos'=any(p_topics)
  union all
  select 'mobile:'||m.client_submission_id||':receiving-photos','photos','receiving_photos_recorded',p_project_id,null,null,m.operator_id,m.created_at,'mobile',false,
   rm_private.project_audit_changes_v1(null,jsonb_build_object('captured_photo_count',jsonb_array_length(m.params->'p_fotos_recebimento')),array['captured_photo_count']),null
  from mobile m where m.rpc_name='rm_submit_recebimento_v1' and m.result->>'projeto_id'=p_project_id::text
   and jsonb_array_length(coalesce(m.params->'p_fotos_recebimento','[]'))>0 and p_kind='operations' and 'photos'=any(p_topics)
  union all
  select 'mobile:'||m.client_submission_id||':form','forms',case m.rpc_name when 'rm_submit_form_inspection_v1' then 'form_submitted' else 'form_corrected' end,
   r.id,r.celula_id,a.id,m.operator_id,m.created_at,'mobile',false,
   rm_private.project_audit_changes_v1(null,jsonb_build_object('form_id',r.form_id,'status',
    coalesce(m.result->'novo_status',case when m.rpc_name='rm_submit_form_inspection_v1' then '"em_an_lise"'::jsonb end)),array['form_id','status']),null
  from mobile m join public.rm_registros_formulario r on r.id::text=coalesce(m.result->>'registro_formulario_id',m.params->>'p_registro_formulario_id') and r.projeto_id=p_project_id
   left join public.rm_celulas_projeto a on a.projeto_id=r.projeto_id and a.celula_id=r.celula_id
  where m.rpc_name in('rm_submit_form_inspection_v1','rm_submit_form_revision_v1') and p_kind='operations' and 'forms'=any(p_topics)
  union all
  select 'form-review:'||v.id,'forms','form_reviewed',v.registro_formulario_id,v.celula_id,a.id,v.aprovador_user_id,v.created_at,
   'legacy',false,
   rm_private.project_audit_changes_v1(null,jsonb_build_object('status',v.status),array['status']),v.parecer
  from public.rm_aprovacoes_registro v left join public.rm_celulas_projeto a on a.projeto_id=v.projeto_id and a.celula_id=v.celula_id
  where v.projeto_id=p_project_id and p_kind='operations' and 'forms'=any(p_topics)
  union all
  select 'web:'||w.client_submission_id||':reviewer','forms','form_reviewer_changed',r.id,a.celula_id,a.id,w.actor_id,w.created_at,'web',jsonb_typeof(w.before_record->'assignment')='object',
   rm_private.project_audit_changes_v1(case when jsonb_typeof(w.before_record->'assignment')='object' then
    jsonb_build_object('form_id',w.before_record->'id','avaliador_user_id',w.before_record->'assignment'->'avaliador_user_id') end,
    w.result->'record',array['form_id','avaliador_user_id']),null
  from web w join public.rm_celulas_projeto a on a.id::text=w.payload->>'celula_projeto_id' and a.projeto_id=p_project_id
   join public.rm_form_reviewer_assignments r on r.id::text=w.result->>'id' and r.projeto_id=p_project_id
  where w.operation='assign_form_reviewer' and p_kind='operations' and 'forms'=any(p_topics)
  union all
  -- Reapplying a default reviewer can also repair existing records. Those are
  -- distinct entity effects with their own exact prior reviewer in the snapshot.
  select 'web:'||w.client_submission_id||':record-reviewer:'||r.id,'forms','form_record_reviewer_changed',r.id,r.celula_id,a.id,w.actor_id,w.created_at,'web',true,
   rm_private.project_audit_changes_v1(previous.value,w.result->'record',array['avaliador_user_id']),null
  from web w cross join lateral jsonb_array_elements_text(w.result->'record'->'records_updated_ids') changed(id)
   join public.rm_registros_formulario r on r.id::text=changed.id and r.projeto_id=p_project_id
   join lateral jsonb_array_elements(w.before_record->'records') previous on previous.value->>'id'=r.id::text
   left join public.rm_celulas_projeto a on a.projeto_id=r.projeto_id and a.celula_id=r.celula_id
  where w.operation='assign_form_reviewer' and p_kind='operations' and 'forms'=any(p_topics)
  union all
  select 'web:'||w.client_submission_id||':rule','approvals','stage_rule_'||(w.payload->>'action'),s.id,s.celula_origem_id,s.celula_projeto_id,w.actor_id,w.created_at,'web',w.before_record is not null,
   case when w.payload->>'action' in('create','replace') then rm_private.project_audit_changes_v1(w.before_record,w.payload->'config',
    array['celula_destino_id','status_cel_proj','bloquear_avanco_sem_aprov','aprovadores_ids','aprovadores_retorno_ids'])
    else rm_private.project_audit_changes_v1(jsonb_build_object('ativo',w.before_record->'ativo'),jsonb_build_object('ativo',w.payload->>'action'='restore'),array['ativo']) end,null
  from web w join public.rm_aprovacoes_etapas s on s.id::text=w.result->>'id' and s.projeto_id=p_project_id
  where w.operation='manage_stage_rules' and p_kind='operations' and 'approvals'=any(p_topics) and jsonb_array_length(w.result->'record'->'changed_ids')>0
  union all
  -- Exactly one event per persisted decision log. Web decisions and mobile
  -- receipts enrich it; they do not generate additional timeline entries.
  select 'stage-log:'||l.id,'approvals','stage_'||coalesce(d.acao,m.params->>'p_acao',l.status_aprovacao::text),l.id,l.celula_id,a.id,
   coalesce(d.actor_id,m.operator_id,l.aprovador_id),coalesce(d.created_at,m.created_at,l.data_aprovacao,l.created_at),
   case when d.id is not null then 'web' when m.client_submission_id is not null then 'mobile' else 'legacy' end,d.id is not null,
   rm_private.project_audit_changes_v1(case when d.id is not null then jsonb_build_object('status',d.status_anterior) end,
    jsonb_build_object('status',coalesce(d.status_novo,l.status_aprovacao)),array['status']),coalesce(d.observacao,m.params->>'p_observacao')
  from public.rm_logs_aprovacao l left join public.rm_web_stage_decisions d on d.log_id=l.id and d.projeto_id=p_project_id
   left join lateral(select x.* from rm_private.mobile_mutation_receipts x where x.rpc_name='rm_transition_stage_approval_v1'
    and x.result->>'log_id'=l.id::text order by x.created_at,x.client_submission_id limit 1) m on true
   left join public.rm_celulas_projeto a on a.projeto_id=l.projeto_id and a.celula_id=l.celula_id
  where l.projeto_id=p_project_id and p_kind='operations' and 'approvals'=any(p_topics)
 ) select 'audit:'||encode(sha256(convert_to(event_id,'UTF8')),'hex'),topic,action,entity_id,celula_id,celula_projeto_id,
  actor_id,occurred_at,source,prior_evidence,changes,reason from events where jsonb_array_length(changes)>0;
$$;
revoke all on function rm_private.project_audit_events_v1(uuid,text,text[]) from public,anon,authenticated,service_role;

create function public.rm_web_project_audit_v1(p_project_id uuid,p_kind text,p_page integer default 1,
 p_topics text[] default array['photos','forms','approvals']) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; total bigint; current_page integer; begin
 if not exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid() and u.status='ativo'
  and u.perfil in('administrador','padr_o','auditor')) then raise exception 'Acesso não autorizado ao histórico.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_project_id is null or p_kind is null or p_kind not in('cells','operations') or p_page is null or p_page not between 1 and 1000000
  or p_topics is null or exists(select 1 from unnest(p_topics) t where t is null or t not in('photos','forms','approvals'))
  or cardinality(p_topics)>3 then raise exception 'Consulta de histórico inválida.' using errcode='22023'; end if;
 if not exists(select 1 from public.rm_projetos where id=p_project_id) then return null; end if;
 select count(*) into total from rm_private.project_audit_events_v1(p_project_id,p_kind,p_topics);
 current_page:=least(p_page,greatest(1,ceil(total/25.0)::int));
 select coalesce(jsonb_agg(dto order by occurred_at desc,event_id),'[]'::jsonb) into result from(
  select e.occurred_at,e.event_id,jsonb_build_object('id',e.event_id,'projeto_id',p_project_id,'topic',e.topic,'action',e.action,
   'entity_id',e.entity_id,'celula_id',e.celula_id,'celula_projeto_id',e.celula_projeto_id,'cell_name',c.nome,
   'actor_id',e.actor_id,'actor_name',u.nome,'occurred_at',e.occurred_at,'source',e.source,'prior_evidence',e.prior_evidence,
   'changes',e.changes,'reason',e.reason) dto
  from rm_private.project_audit_events_v1(p_project_id,p_kind,p_topics) e left join public.rm_users u on u.id=e.actor_id
   left join public.rm_celulas c on c.id=e.celula_id order by e.occurred_at desc,e.event_id offset (current_page-1)*25 limit 25
 ) selected;
 return jsonb_build_object('project_id',p_project_id,'kind',p_kind,'page',current_page,'page_size',25,'total',total,'items',result);
end $$;
revoke all on function public.rm_web_project_audit_v1(uuid,text,integer,text[]) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_audit_v1(uuid,text,integer,text[]) to authenticated;

-- Project-scoped journal lookup, not SELECT privileges on either private table.
create index rm_web_receipts_project_audit on rm_private.web_mutation_receipts((result->>'projeto_id'),created_at,client_submission_id)
 where operation in('plan_cell','save_project_route','manage_cell_availability','set_project_photo_selection','manage_operational_photos','manage_stage_rules','assign_form_reviewer');
create index rm_web_receipts_queue_audit on rm_private.web_mutation_receipts(created_at,client_submission_id) where operation='save_cell_queue';
create index rm_mobile_receipts_project_audit on rm_private.mobile_mutation_receipts((result->>'projeto_id'),created_at,client_submission_id);
notify pgrst,'reload schema';
commit;

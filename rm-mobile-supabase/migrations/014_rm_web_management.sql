-- Web management uses the Supabase Auth identity directly. Mobile delegation,
-- existing read policies and outbound bridge contracts are deliberately unchanged.
begin;

create table rm_private.web_mutation_receipts (
  client_submission_id uuid primary key,
  auth_user_id uuid not null,
  actor_id uuid not null,
  operation text not null,
  payload jsonb not null,
  result jsonb not null,
  before_record jsonb,
  created_at timestamptz not null default clock_timestamp()
);
revoke all on rm_private.web_mutation_receipts from public,anon,authenticated;

create function public.rm_web_mutate_v1(
  p_client_submission_id uuid,p_operation text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor public.rm_users%rowtype;
  receipt rm_private.web_mutation_receipts%rowtype;
  project public.rm_projetos%rowtype;
  next_project public.rm_projetos%rowtype;
  cell public.rm_celulas_projeto%rowtype;
  next_cell public.rm_celulas_projeto%rowtype;
  registration public.rm_registros_formulario%rowtype;
  template public.rm_celula_tipos_equipamento%rowtype;
  changes jsonb;
  allowed text[];
  record_id uuid;
  project_id uuid;
  cell_id uuid;
  expected timestamptz;
  is_new boolean;
  before_record jsonb;
  result jsonb;
  answer_ids uuid[];
  decision text;
  opinion text;
  template_forms uuid[];
begin
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null then raise exception 'Conta RM ativa necessária.' using errcode='42501'; end if;
  -- Enforce the portal's MFA boundary even for direct REST RPC calls or replays.
  -- This is deliberately scoped to web writes; device/operator auth is unchanged.
  if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
    and (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';
  end if;
  if p_client_submission_id is null or p_operation is null or p_operation not in ('save_project','plan_cell','review_form')
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Operação ou payload inválido.' using errcode='22023';
  end if;
  if p_operation in ('save_project','plan_cell') and not coalesce(actor.perfil in ('administrador','padr_o'),false) then
    raise exception 'Operação restrita à administração/PCP.' using errcode='42501';
  end if;
  -- Global request UUID, not just per user: a different actor cannot replay it.
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
  select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
  if found then
    if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
      raise exception 'Identificador de envio já utilizado com outro conteúdo.' using errcode='23505';
    end if;
    return receipt.result || jsonb_build_object('idempotent_replay',true);
  end if;
  if not p_payload?'expected_updated_at' then
    raise exception 'Informe a versão esperada, ou null para criação.' using errcode='22023';
  end if;
  expected := (p_payload->>'expected_updated_at')::timestamptz;

  if p_operation='save_project' then
    if exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('id','expected_updated_at','changes')) then
      raise exception 'Campo de projeto não permitido.' using errcode='22023'; end if;
    record_id := (p_payload->>'id')::uuid;
    project_id := record_id;
    if record_id is null then raise exception 'Informe o UUID do projeto.' using errcode='22023'; end if;
    changes := p_payload->'changes';
    allowed := array['numero','nome','cliente_id','tipo_equipamento_id','descricao_equipamento','contato','proprietario',
      'escopo_abreviado','eventualidades','gestor_responsavel_id','status','status_pcp','chegada_do_equipamento',
      'data_prevista_inicio','data_prevista_final','data_contratual','data_renegociada','replanejamento_motivo'];
    if changes is null or jsonb_typeof(changes)<>'object' or changes='{}'::jsonb
      or exists(select 1 from jsonb_object_keys(changes) k where not k=any(allowed)) then
      raise exception 'Alterações de projeto inválidas.' using errcode='22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
    select * into project from public.rm_projetos where id=record_id for update;
    is_new := not found;
    if (is_new and expected is not null) or (not is_new and (expected is null or expected<>project.updated_at)) then
      raise exception 'Projeto alterado. Atualize antes de salvar.' using errcode='40001'; end if;
    before_record := case when is_new then null else to_jsonb(project) end;
    if is_new then
      insert into public.rm_projetos(id,created_by_user_id) values(record_id,actor.id) returning * into project;
    end if;
    next_project := jsonb_populate_record(project,changes);
    if nullif(btrim(next_project.numero),'') is null and nullif(btrim(next_project.nome),'') is null then
      raise exception 'Informe número ou nome do projeto.' using errcode='22023'; end if;
    if next_project.data_prevista_inicio>next_project.data_prevista_final then
      raise exception 'Prazo final anterior ao início.' using errcode='22023'; end if;
    if next_project.gestor_responsavel_id is not null and not exists(select 1 from public.rm_users
      where id=next_project.gestor_responsavel_id and status='ativo') then
      raise exception 'Responsável inexistente ou inativo.' using errcode='22023'; end if;
    if next_project.tipo_equipamento_id is distinct from project.tipo_equipamento_id and exists(
      select 1 from public.rm_celulas_projeto where projeto_id=project.id) then
      raise exception 'Tipo de equipamento não pode mudar após alocação de células.' using errcode='22023'; end if;
    if next_project.status_pcp='finalizando_para_faturar' and project.status_pcp is distinct from next_project.status_pcp then
      if not exists(select 1 from public.rm_celulas_projeto where projeto_id=project.id)
        or exists(select 1 from public.rm_celulas_projeto where projeto_id=project.id and status not in ('finalizado','n_a'))
        or exists(select 1 from public.rm_celulas_projeto cp cross join unnest(cp.forms_ids) f
          where cp.projeto_id=project.id and cp.status<>'n_a' and not exists(
            select 1 from public.rm_registros_formulario r where r.projeto_id=project.id
              and r.celula_id=cp.celula_id and r.form_id=f and r.preenchido and r.status='aprovado'))
        or exists(select 1 from public.rm_registros_formulario where projeto_id=project.id and status<>'aprovado')
        or exists(select 1 from public.rm_fotos where projeto_id=project.id and not lixeira and categoria_foto='obrigat_ria'
          and nullif(btrim(foto_url),'') is null) then
        raise exception 'Conclua as células, formulários e fotos obrigatórias antes de faturar.' using errcode='22023'; end if;
    end if;
    update public.rm_projetos set numero=nullif(btrim(next_project.numero),''),nome=next_project.nome,
      cliente_id=next_project.cliente_id,tipo_equipamento_id=next_project.tipo_equipamento_id,
      descricao_equipamento=next_project.descricao_equipamento,contato=next_project.contato,proprietario=next_project.proprietario,
      escopo_abreviado=next_project.escopo_abreviado,eventualidades=next_project.eventualidades,
      gestor_responsavel_id=next_project.gestor_responsavel_id,status=next_project.status,status_pcp=next_project.status_pcp,
      chegada_do_equipamento=next_project.chegada_do_equipamento,data_prevista_inicio=next_project.data_prevista_inicio,
      data_prevista_final=next_project.data_prevista_final,data_contratual=next_project.data_contratual,
      data_renegociada=next_project.data_renegociada,replanejamento_motivo=next_project.replanejamento_motivo,sync_source='supabase'
      where id=record_id returning * into project;
    update public.rm_celulas_projeto set numero_projeto=project.numero
      where projeto_id=project.id and numero_projeto is distinct from project.numero;
    result := jsonb_build_object('record',to_jsonb(project),'updated_at',project.updated_at);

  elsif p_operation='plan_cell' then
    if exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('projeto_id','celula_id','expected_updated_at','changes')) then
      raise exception 'Campo de planejamento não permitido.' using errcode='22023'; end if;
    project_id := (p_payload->>'projeto_id')::uuid;
    cell_id := (p_payload->>'celula_id')::uuid;
    if project_id is null or cell_id is null then raise exception 'Informe projeto e célula.' using errcode='22023'; end if;
    changes := p_payload->'changes';
    allowed := array['data_inicio','data_limite','bloqueada','motivo_bloqueio','visibilidade','prioridade','indice','posicao',
      'horas_previstas','responsavel_id','observacao','forms_ids'];
    if changes is null or jsonb_typeof(changes)<>'object'
      or exists(select 1 from jsonb_object_keys(changes) k where not k=any(allowed)) then
      raise exception 'Alterações de planejamento inválidas.' using errcode='22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
    select * into project from public.rm_projetos where id=project_id for update;
    if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
    if project.data_real_de_entrega is not null or project.status_pcp in ('cancelado','finalizando_para_faturar') then
      raise exception 'Projeto encerrado não aceita planejamento.' using errcode='22023'; end if;
    select * into cell from public.rm_celulas_projeto where projeto_id=project_id and celula_id=cell_id for update;
    is_new := not found;
    if (is_new and expected is not null) or (not is_new and (expected is null or expected<>cell.updated_at)) then
      raise exception 'Alocação alterada. Atualize antes de salvar.' using errcode='40001'; end if;
    before_record := case when is_new then null else to_jsonb(cell) end;
    if not is_new and cell.status in ('finalizado','n_a') then
      raise exception 'Célula concluída não aceita replanejamento.' using errcode='22023'; end if;
    if is_new then
      select * into template from public.rm_celula_tipos_equipamento
        where celula_id=cell_id and tipo_equipamento_id=project.tipo_equipamento_id;
      select coalesce(array_agg(form_id),'{}'::uuid[]) into template_forms from public.rm_celula_form_tipos_equipamento
        where celula_tipo_equipamento_id=template.id;
      insert into public.rm_celulas_projeto(projeto_id,celula_id,numero_projeto,cliente_nome_export,escopo_abreviado,
        status_historico,visibilidade,forms_ids,modified_by_id)
        values(project_id,cell_id,project.numero,project.cliente_nome_exportacao,project.escopo_abreviado,
        array['pendente']::public.rm_status_cel_proj_enum[],coalesce(template.visibilidade,false),template_forms,actor.id)
        returning * into cell;
      -- Reuse the original materialization rules, restricted to the NEW allocation.
      -- Calling the old all-project UPSERT would reset existing forms and deadlines.
      insert into public.rm_fotos(projeto_id,celula_id,celula_projeto_id,celula_tipo_equipamento_id,categoria_foto,
        identificador_foto_key,titulo,descricao,numero,sync_source)
        select project_id,cell_id,cell.id,template.id,coalesce(f.categoria_foto,'obrigat_ria'),
          f.identificador_foto_key,f.titulo,f.descricao,f.numero,'supabase'
        from public.rm_fotos f where f.projeto_id is null and f.celula_tipo_equipamento_id=template.id and not f.lixeira;
      insert into public.rm_aprovacoes_etapas(projeto_id,celula_projeto_id,celula_tipo_equipamento_id,celula_origem_id,
        celula_destino_id,bloquear_avanco_sem_aprov,status,status_cel_proj,aprovador_id,aprovadores_ids,aprovadores_retorno_ids,sync_source)
        select project_id,cell.id,template.id,a.celula_origem_id,a.celula_destino_id,a.bloquear_avanco_sem_aprov,
          'nulo',a.status_cel_proj,a.aprovador_id,a.aprovadores_ids,a.aprovadores_retorno_ids,'supabase'
        from public.rm_aprovacoes_etapas a where a.projeto_id is null and a.celula_tipo_equipamento_id=template.id;
    end if;
    next_cell := jsonb_populate_record(cell,changes);
    if next_cell.data_inicio>next_cell.data_limite or next_cell.horas_previstas<0 then
      raise exception 'Prazo ou horas previstos inválidos.' using errcode='22023'; end if;
    if next_cell.visibilidade is null or next_cell.bloqueada is null or next_cell.forms_ids is null then
      raise exception 'Visibilidade, bloqueio e formulários são obrigatórios.' using errcode='22023'; end if;
    if next_cell.bloqueada='sim' and nullif(btrim(next_cell.motivo_bloqueio),'') is null then
      raise exception 'Informe o motivo do bloqueio.' using errcode='22023'; end if;
    if next_cell.responsavel_id is not null and not exists(select 1 from public.rm_users where id=next_cell.responsavel_id and status='ativo') then
      raise exception 'Responsável inexistente ou inativo.' using errcode='22023'; end if;
    if exists(select 1 from unnest(next_cell.forms_ids) f group by f having count(*)>1) or exists(
      select 1 from unnest(next_cell.forms_ids) f left join public.rm_forms definition on definition.id=f
      where definition.id is null or (not definition.ativo and (is_new or not f=any(cell.forms_ids)))) then
      raise exception 'Formulário inexistente, repetido ou inativo.' using errcode='22023'; end if;
    if exists(select 1 from public.rm_registros_formulario r where r.projeto_id=project_id and r.celula_id=cell_id
      and r.form_id=any(cell.forms_ids) and not r.form_id=any(next_cell.forms_ids)) then
      raise exception 'Formulário já enviado deve permanecer vinculado.' using errcode='22023'; end if;
    update public.rm_celulas_projeto set data_inicio=next_cell.data_inicio,data_limite=next_cell.data_limite,
      bloqueada=next_cell.bloqueada,motivo_bloqueio=next_cell.motivo_bloqueio,visibilidade=next_cell.visibilidade,
      prioridade=next_cell.prioridade,indice=next_cell.indice,posicao=next_cell.posicao,horas_previstas=next_cell.horas_previstas,
      responsavel_id=next_cell.responsavel_id,observacao=next_cell.observacao,forms_ids=next_cell.forms_ids,
      replanejada_em=clock_timestamp(),replanejada_por_id=actor.id,modified_by_id=actor.id,sync_source='supabase'
      where id=cell.id returning * into cell;
    record_id := cell.id;
    result := jsonb_build_object('record',to_jsonb(cell),'updated_at',cell.updated_at);

  else
    if exists(select 1 from jsonb_object_keys(p_payload) k where k not in
      ('registro_formulario_id','expected_updated_at','decision','parecer','resposta_ids')) then
      raise exception 'Campo de revisão não permitido.' using errcode='22023'; end if;
    record_id := (p_payload->>'registro_formulario_id')::uuid;
    decision := p_payload->>'decision';
    opinion := nullif(btrim(p_payload->>'parecer'),'');
    if record_id is null or decision is null or decision not in ('approve','return')
      or jsonb_typeof(p_payload->'resposta_ids') is distinct from 'array' then
      raise exception 'Decisão de revisão inválida.' using errcode='22023'; end if;
    answer_ids := array(select jsonb_array_elements_text(p_payload->'resposta_ids'))::uuid[];
    select * into registration from public.rm_registros_formulario where id=record_id for update;
    if not found then raise exception 'Registro inexistente.' using errcode='P0002'; end if;
    if actor.perfil is distinct from 'administrador' and actor.id is distinct from registration.avaliador_user_id
      and not actor.id=any(registration.aprovadores_ids) then
      raise exception 'Usuário não é avaliador deste registro.' using errcode='42501'; end if;
    if expected is null or expected<>registration.updated_at then
      raise exception 'Formulário alterado. Atualize antes de revisar.' using errcode='40001'; end if;
    if registration.status<>'em_an_lise' or not registration.preenchido then
      raise exception 'Somente formulário preenchido em análise pode ser revisado.' using errcode='22023'; end if;
    if not exists(select 1 from public.rm_respostas where registro_formulario_id=record_id) then
      raise exception 'Registro sem respostas não pode ser revisado.' using errcode='22023'; end if;
    before_record := to_jsonb(registration);
    project_id := registration.projeto_id;
    if decision='return' then
      if cardinality(answer_ids)=0 or opinion is null then
        raise exception 'Devolução exige parecer e respostas para correção.' using errcode='22023'; end if;
      if exists(select 1 from unnest(answer_ids) a group by a having count(*)>1) or exists(
        select 1 from unnest(answer_ids) a left join public.rm_respostas r on r.id=a and r.registro_formulario_id=record_id
        left join public.rm_questoes q on q.id=r.questao_id and q.form_id=registration.form_id
        where r.id is null or q.id is null or q.tipo='subt_tulo') then
        raise exception 'Resposta não pertence ao registro ou não pode ser corrigida.' using errcode='22023'; end if;
      update public.rm_respostas set revisar=(id=any(answer_ids)),sync_source='supabase'
        where registro_formulario_id=record_id and questao_id is not null and revisar is distinct from (id=any(answer_ids));
    else
      if cardinality(answer_ids)>0 or exists(select 1 from public.rm_respostas where registro_formulario_id=record_id and revisar) then
        raise exception 'Aprovação exige todas as correções concluídas e nenhuma resposta selecionada.' using errcode='22023'; end if;
    end if;
    update public.rm_registros_formulario set status=case when decision='approve' then 'aprovado'::public.rm_status_registro_enum else 'direcionado' end,
      parecer=opinion,avaliador_user_id=actor.id,
      acao_log=array_append(acao_log,case when decision='approve' then 'Aprovado' else 'Devolvido para revisão' end),
      historico_log=array_append(historico_log,clock_timestamp()::text || ' - ' || actor.nome),
      observacao_list=case when opinion is null then observacao_list else array_append(observacao_list,opinion) end,
      sync_source='supabase' where id=record_id returning * into registration;
    insert into public.rm_aprovacoes_registro(registro_formulario_id,projeto_id,celula_id,form_id,aprovador_user_id,
      aprovador_nome,parecer,status,historico_status)
      values(record_id,project_id,registration.celula_id,registration.form_id,actor.id,actor.nome,opinion,
      registration.status,array[registration.status]);
    result := jsonb_build_object('record',to_jsonb(registration),'updated_at',registration.updated_at);
  end if;
  result := result || jsonb_build_object('operation',p_operation,'id',record_id,'projeto_id',project_id,'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
  return result;
end $$;
revoke all on function public.rm_web_mutate_v1(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.rm_web_mutate_v1(uuid,text,jsonb) to authenticated;

-- Read the review history through the existing active RM session boundary.
grant select on public.rm_aprovacoes_registro to authenticated;
create policy rm_web_review_history_read on public.rm_aprovacoes_registro for select to authenticated
  using ((select rm_private.is_rm_authenticated()));
notify pgrst,'reload schema';
commit;

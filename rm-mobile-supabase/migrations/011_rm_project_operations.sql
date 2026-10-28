-- Project operations verified against Bubble live on 2026-10-28.
-- No remote workflow is executed: outbound work remains in the local outbox.
begin;

-- Receiving precedes the assignment of an OS number/type by planning.
alter table public.rm_projetos alter column numero drop not null;
alter table public.rm_docs add column if not exists status text;
alter table public.rm_docs add column if not exists data_vencimento timestamptz;
alter table public.rm_docs add column if not exists bubble_modified_at timestamptz;
alter table public.rm_documentos add column if not exists bubble_modified_at timestamptz;
alter table public.rm_docs add column if not exists bubble_id text unique;
alter table public.rm_documentos add column if not exists bubble_id text unique;
alter table public.rm_docs add column if not exists sync_source text not null default 'supabase' check(sync_source in ('supabase','bubble','etl'));
alter table public.rm_documentos add column if not exists sync_source text not null default 'supabase' check(sync_source in ('supabase','bubble','etl'));
update public.rm_docs set bubble_id=bubble_unique_id where bubble_id is null and bubble_unique_id is not null;
update public.rm_documentos set bubble_id=bubble_unique_id where bubble_id is null and bubble_unique_id is not null;
-- A generated document can exist before its file has finished processing.
alter table public.rm_documentos alter column arquivo_url drop not null;
alter table public.rm_docs alter column arquivo_url drop not null;

create policy rm_mobile_docs_read on public.rm_docs for select to authenticated using(rm_private.is_rm_authenticated());
create policy rm_mobile_documentos_read on public.rm_documentos for select to authenticated using(rm_private.is_rm_authenticated());
grant select on public.rm_docs,public.rm_documentos,public.rm_comentarios,public.rm_logs_aprovacao,public.rm_cadastro_fotos to authenticated;
revoke insert,update,delete on public.rm_docs,public.rm_documentos,public.rm_comentarios,public.rm_logs_aprovacao,public.rm_cadastro_fotos from authenticated;
create trigger trg_touch_rm_docs before update on public.rm_docs for each row execute function rm_private.touch_updated_at();
create trigger trg_touch_rm_documentos before update on public.rm_documentos for each row execute function rm_private.touch_updated_at();
do $$ declare t text; begin
  foreach t in array array['rm_docs','rm_documentos','rm_comentarios','rm_logs_aprovacao','rm_cadastro_fotos'] loop
    if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
      select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;

update storage.buckets set public=false,file_size_limit=52428800,
  allowed_mime_types=array['application/pdf','image/jpeg','image/png'] where id='rm-documentos';
create policy rm_mobile_documents_read on storage.objects for select to authenticated
  using(bucket_id='rm-documentos' and rm_private.is_rm_authenticated());
create policy rm_mobile_documents_insert on storage.objects for insert to authenticated
  with check(bucket_id='rm-documentos' and rm_private.is_rm_authenticated() and (storage.foldername(name))[1]=auth.uid()::text);
create policy rm_mobile_documents_update on storage.objects for update to authenticated
  using(bucket_id='rm-documentos' and rm_private.is_rm_authenticated() and (storage.foldername(name))[1]=auth.uid()::text)
  with check(bucket_id='rm-documentos' and (storage.foldername(name))[1]=auth.uid()::text);

create function rm_private.update_cell_status_v1(p_operator uuid,p_cell_project uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cp public.rm_celulas_projeto%rowtype; next_status public.rm_status_cel_proj_enum;
begin
  select * into cp from public.rm_celulas_projeto where id=p_cell_project;
  if not found then raise exception 'Célula do projeto não encontrada.' using errcode='P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended(cp.projeto_id::text,11));
  select * into cp from public.rm_celulas_projeto where id=p_cell_project for update;
  perform rm_private.assert_cell_access(p_operator,cp.celula_id);
  next_status:=p_status::public.rm_status_cel_proj_enum;
  if next_status is null then raise exception 'Selecione o status.' using errcode='22023'; end if;
  if next_status='finalizado' then
    if exists(select 1 from unnest(cp.forms_ids) f where not exists(select 1 from public.rm_registros_formulario r
      where r.projeto_id=cp.projeto_id and r.celula_id=cp.celula_id and r.form_id=f and r.preenchido)) then
      raise exception 'Preencha todos os formulários vinculados antes de finalizar.' using errcode='22023';
    end if;
    if exists(select 1 from public.rm_fotos f where f.projeto_id=cp.projeto_id and f.celula_id=cp.celula_id
      and f.categoria_foto='obrigat_ria' and not f.lixeira and nullif(btrim(f.foto_url),'') is null) then
      raise exception 'Preencha todas as fotos obrigatórias antes de finalizar.' using errcode='22023';
    end if;
  end if;
  update public.rm_celulas_projeto set status=next_status,
    status_historico=case when status is distinct from next_status then array_append(status_historico,next_status) else status_historico end,
    modified_by_id=p_operator,sync_source='supabase',
    data_fim_real=case when next_status='finalizado' then coalesce(data_fim_real,clock_timestamp()) else data_fim_real end,
    visibilidade=case when next_status='finalizado' and not exists(select 1 from public.rm_aprovacoes_etapas a
      where a.projeto_id=cp.projeto_id and a.celula_origem_id=cp.celula_id) then false else visibilidade end
    where id=cp.id;
  perform rm_private.enqueue_sync_event('bubble_data_api','Celula_Projeto_Status','update',cp.id,cp.bubble_id,
    jsonb_build_object('celula_projeto_id',cp.id,'projeto_id',cp.projeto_id,'status',next_status));
  return jsonb_build_object('celula_projeto_id',cp.id,'projeto_id',cp.projeto_id,'status',next_status);
end $$;

create function rm_private.add_cell_comment_v1(p_operator uuid,p_cell_project uuid,p_comment text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cp public.rm_celulas_projeto%rowtype; comment_id uuid;
begin
  select * into cp from public.rm_celulas_projeto where id=p_cell_project;
  if not found then raise exception 'Célula do projeto não encontrada.' using errcode='P0002'; end if;
  perform rm_private.assert_cell_access(p_operator,cp.celula_id);
  if nullif(btrim(p_comment),'') is null or length(p_comment)>10000 then
    raise exception 'Informe um comentário de até 10000 caracteres.' using errcode='22023'; end if;
  insert into public.rm_comentarios(projeto_id,celula_id,cadastrado_por_id,evento,sync_source)
    values(cp.projeto_id,cp.celula_id,p_operator,btrim(p_comment),'supabase') returning id into comment_id;
  perform rm_private.enqueue_sync_event('bubble_data_api','Comentario_Celula','create',comment_id,null,
    jsonb_build_object('comentario_id',comment_id,'projeto_id',cp.projeto_id,'celula_id',cp.celula_id));
  return jsonb_build_object('comentario_id',comment_id,'projeto_id',cp.projeto_id,'celula_id',cp.celula_id);
end $$;

create or replace function public.rm_transition_stage_approval_v1(
  p_aprovacao_etapa_id uuid,p_operador_id uuid,p_acao text,p_observacao text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.rm_aprovacoes_etapas%rowtype; cp public.rm_celulas_projeto%rowtype;
  decision public.rm_status_etapa_enum; reverse_id uuid; log_id uuid; comment_id uuid; affected uuid[]:='{}';
  pr public.rm_projetos%rowtype; equipment public.rm_equipamentos%rowtype;
begin
  select * into a from public.rm_aprovacoes_etapas where id=p_aprovacao_etapa_id;
  if not found or a.projeto_id is null then raise exception 'Aprovação do projeto não encontrada.' using errcode='P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended(a.projeto_id::text,11));
  select * into a from public.rm_aprovacoes_etapas where id=p_aprovacao_etapa_id for update;
  select * into cp from public.rm_celulas_projeto where projeto_id=a.projeto_id and celula_id=a.celula_origem_id for update;
  if not found then raise exception 'Célula de origem não encontrada.' using errcode='P0002'; end if;
  perform rm_private.assert_cell_access(p_operador_id,cp.celula_id);
  if coalesce(a.status,'nulo')<>'nulo' then raise exception 'Esta aprovação já foi decidida.' using errcode='22023'; end if;
  if p_acao='liberar' then
    if a.status_cel_proj is null or a.status_cel_proj='retornado' or cp.status<>a.status_cel_proj then
      raise exception 'A célula precisa estar no status previsto para liberar esta etapa.' using errcode='22023'; end if;
    decision:='aprovado';
  elsif p_acao in ('retornar','aprovar') then
    if a.status_cel_proj is distinct from 'retornado'::public.rm_status_cel_proj_enum then
      raise exception 'Retornar e aprovar são ações exclusivas da etapa de retorno.' using errcode='22023'; end if;
    if p_acao='retornar' and cp.status<>'retornado' then
      raise exception 'A célula precisa estar em Retornado.' using errcode='22023'; end if;
    decision:=case when p_acao='retornar' then 'reprovado'::public.rm_status_etapa_enum else 'aprovado'::public.rm_status_etapa_enum end;
  else raise exception 'Ação inválida. Use liberar, retornar ou aprovar.' using errcode='22023'; end if;
  update public.rm_aprovacoes_etapas set status=decision,data_aprovacao=clock_timestamp(),aprovado_por_id=p_operador_id,sync_source='supabase' where id=a.id;
  insert into public.rm_logs_aprovacao(projeto_id,celula_id,aprovador_id,status_aprovacao,data_aprovacao,sync_source)
    values(a.projeto_id,a.celula_origem_id,p_operador_id,decision,clock_timestamp(),'supabase') returning id into log_id;

  if p_acao='liberar' and a.celula_destino_id is not null then
    -- Re-open an existing reverse decision or create its first return path.
    select id into reverse_id from public.rm_aprovacoes_etapas where projeto_id=a.projeto_id
      and celula_origem_id=a.celula_destino_id and celula_destino_id=a.celula_origem_id
      and status_cel_proj='retornado' order by created_at,id limit 1 for update;
    if reverse_id is null then
      insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id,celula_destino_id,celula_projeto_id,
        status_cel_proj,status,aprovadores_ids,sync_source)
      values(a.projeto_id,a.celula_destino_id,a.celula_origem_id,
        (select id from public.rm_celulas_projeto where projeto_id=a.projeto_id and celula_id=a.celula_destino_id),
        'retornado','nulo',a.aprovadores_retorno_ids,'supabase') returning id into reverse_id;
    elsif exists(select 1 from public.rm_aprovacoes_etapas where id=reverse_id and status='reprovado') then
      update public.rm_aprovacoes_etapas set status='nulo',aprovado_por_id=null,data_aprovacao=null,sync_source='supabase' where id=reverse_id;
    end if;
    affected:=array_append(affected,reverse_id);
    if not a.bloquear_avanco_sem_aprov then
      update public.rm_celulas_projeto set visibilidade=true,status='pendente',modified_by_id=p_operador_id,sync_source='supabase'
        where projeto_id=a.projeto_id and celula_id=a.celula_destino_id;
    elsif not exists(select 1 from public.rm_aprovacoes_etapas where projeto_id=a.projeto_id
      and celula_destino_id=a.celula_destino_id and bloquear_avanco_sem_aprov and coalesce(status,'nulo')<>'aprovado') then
      update public.rm_celulas_projeto set visibilidade=true,status='para_execu__o',modified_by_id=p_operador_id,sync_source='supabase'
        where projeto_id=a.projeto_id and celula_id=a.celula_destino_id;
    end if;
  elsif p_acao='retornar' and a.celula_destino_id is not null then
    with changed as (
      update public.rm_aprovacoes_etapas set status='nulo',data_aprovacao=null,aprovado_por_id=null,sync_source='supabase'
      where projeto_id=a.projeto_id and celula_origem_id=a.celula_destino_id and celula_destino_id=a.celula_origem_id and status='aprovado'
      returning id
    ) select coalesce(array_agg(id),'{}') into affected from changed;
    update public.rm_celulas_projeto set status='retornado',visibilidade=true,
      status_historico=array_append(status_historico,'retornado'::public.rm_status_cel_proj_enum),modified_by_id=p_operador_id,sync_source='supabase'
      where projeto_id=a.projeto_id and celula_id=a.celula_destino_id;
  end if;
  if not exists(select 1 from public.rm_aprovacoes_etapas where projeto_id=a.projeto_id and celula_origem_id=a.celula_origem_id and coalesce(status,'nulo')='nulo') then
    update public.rm_celulas_projeto set visibilidade=false,modified_by_id=p_operador_id,sync_source='supabase' where id=cp.id;
  end if;
  if nullif(btrim(p_observacao),'') is not null then
    insert into public.rm_comentarios(projeto_id,celula_id,cadastrado_por_id,evento,sync_source)
      values(a.projeto_id,a.celula_origem_id,p_operador_id,btrim(p_observacao),'supabase') returning id into comment_id;
  end if;
  perform rm_private.enqueue_sync_event('bubble_data_api','Aprovacao_Etapa_Transition','update',a.id,a.bubble_id,
    jsonb_build_object('aprovacao_etapa_id',a.id,'projeto_id',a.projeto_id,'acao',p_acao,'operador_id',p_operador_id,'status_etapa',decision,
      'affected_approval_ids',affected,'log_id',log_id,'comentario_id',comment_id));
  -- Preserve the previous queued notification contract. The bridge stays disabled;
  -- this transaction never calls Bubble, n8n or email services directly.
  if p_acao in ('liberar','retornar') then
    select * into pr from public.rm_projetos where id=a.projeto_id;
    select * into equipment from public.rm_equipamentos where id=pr.equipamento_id;
    perform rm_private.enqueue_sync_event('n8n_webhook','enviar_email_aprovacao_etapa','trigger_webhook',a.id,a.bubble_id,
      jsonb_build_object('webhook_url','https://n8n.miconnect.app.br/webhook/fd1b9d72-ef51-4037-ba5a-ac15efdfbc3f',
        'body',jsonb_build_object('num_proj',coalesce(pr.numero,''),'cliente',coalesce(pr.cliente_nome_exportacao,''),
          'data',to_char(clock_timestamp(),'DD/MM/YYYY HH24:MI'),
          'responsavel',coalesce((select nome from public.rm_users where id=p_operador_id),''),
          'tipo_motor',coalesce(pr.escopo_abreviado,''),'fabricante',coalesce(equipment.fabricante,''),
          'potencia',coalesce(equipment.potencia,''),'rpm',coalesce(equipment.rotacao,''),'tensao',coalesce(equipment.tensao_estator,''),
          'etapa',coalesce((select nome from public.rm_celulas where id=a.celula_origem_id),''),
          'status',rm_private.resolve_option_display('status_cel_proj',a.status_cel_proj::text))));
  end if;
  return jsonb_build_object('aprovacao_etapa_id',a.id,'projeto_id',a.projeto_id,'acao',p_acao,'novo_status_etapa',decision);
end $$;

-- The envelope remains the sole authenticated mutation API. Its receipt stores
-- the original payload; normalization below cannot change a retry's identity.
do $migration$
declare definition text; marker text;
begin
  definition:=pg_get_functiondef('public.rm_submit_recebimento_v1(uuid,uuid,uuid,text,text,timestamptz,text,text,text,jsonb,jsonb)'::regprocedure);
  definition:=replace(definition,$old$  if p_numero_projeto is null or btrim(p_numero_projeto) = '' then
    raise exception 'O número do Projeto RM é obrigatório no recebimento.' using errcode = '22023';
  end if;$old$,'');
  execute definition;
  definition:=pg_get_functiondef('rm_private.update_recebimento_v1(uuid,uuid,jsonb)'::regprocedure);
  definition:=replace(definition,$old$  if nullif(btrim(p_params->>'p_numero_projeto'),'') is null then
    raise exception 'Número do projeto é obrigatório.' using errcode='22023'; end if;$old$,'');
  definition:=replace(definition,'numero=btrim(p_params->>''p_numero_projeto'')','numero=coalesce(nullif(btrim(p_params->>''p_numero_projeto''),''''),numero)');
  definition:=replace(definition,'tipo_equipamento_id=(p_params->>''p_tipo_equipamento_id'')::uuid',
    'tipo_equipamento_id=coalesce(nullif(p_params->>''p_tipo_equipamento_id'','''')::uuid,tipo_equipamento_id)');
  execute definition;
  definition:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
  definition:=replace(definition,'v_result jsonb; v_params jsonb; v_answers jsonb; v_cell uuid;',
    'v_result jsonb; v_params jsonb; v_answers jsonb; v_cell uuid; v_catalog public.rm_cadastro_fotos%rowtype;');
  definition:=replace(definition,'if nullif(p_params->>''p_cliente_id'','''') is null or nullif(p_params->>''p_tipo_equipamento_id'','''') is null then',
    'if nullif(p_params->>''p_cliente_id'','''') is null then');
  definition:=replace(definition,'Cliente e tipo de equipamento são obrigatórios.','Cliente é obrigatório.');
  marker:='    if exists(select 1 from jsonb_array_elements(coalesce(p_params->''p_fotos_recebimento''';
  if strpos(definition,marker)=0 then raise exception 'Unexpected receiving gateway definition'; end if;
  definition:=replace(definition,marker,$patch$
    if p_params?'p_descricao_equipamento' then
      p_params:=jsonb_set(p_params,'{p_equipamento}',coalesce(p_params->'p_equipamento','{}')||jsonb_build_object('descricao',p_params->>'p_descricao_equipamento'));
    end if;
    if nullif(p_params->>'p_arquivo_nota_fiscal_url','') is not null and p_params->>'p_arquivo_nota_fiscal_url' !~ '^https://' then
      raise exception 'Envie o arquivo da nota fiscal antes de concluir.' using errcode='22023'; end if;
$patch$||marker);
  marker:='    if nullif(btrim(p_params->>''p_qrcode_value''),'''') is not null then';
  definition:=replace(definition,marker,$patch$
    update public.rm_projetos set
      nota_fiscal=case when p_params?'p_nota_fiscal' then p_params->>'p_nota_fiscal' else nota_fiscal end,
      arquivo_nota_fiscal_url=case when p_params?'p_arquivo_nota_fiscal_url' then nullif(p_params->>'p_arquivo_nota_fiscal_url','') else arquivo_nota_fiscal_url end,
      descricao_equipamento=case when p_params->'p_equipamento'?'descricao' then p_params->'p_equipamento'->>'descricao' else descricao_equipamento end
      where id=(v_result->>'projeto_id')::uuid;
$patch$||marker);
  definition:=replace(definition,'  when ''rm_submit_form_inspection_v1'' then',$patch$
  when 'rm_update_cell_status_v1' then
    v_result:=rm_private.update_cell_status_v1(d.operator_id,(p_params->>'p_celula_projeto_id')::uuid,p_params->>'p_status');
  when 'rm_add_cell_comment_v1' then
    v_result:=rm_private.add_cell_comment_v1(d.operator_id,(p_params->>'p_celula_projeto_id')::uuid,p_params->>'p_comentario');
  when 'rm_submit_form_inspection_v1' then$patch$);
  marker:='    v_result:=public.rm_record_cell_photo_v1';
  definition:=replace(definition,marker,$patch$
    if nullif(p_params->>'p_cadastro_foto_id','') is not null then
      select * into v_catalog from public.rm_cadastro_fotos where id=(p_params->>'p_cadastro_foto_id')::uuid;
      if not found or (nullif(btrim(v_catalog.celula_nome),'') is not null and not exists(
        select 1 from public.rm_celulas where id=v_cell and lower(btrim(nome))=lower(btrim(v_catalog.celula_nome)))) then
        raise exception 'Título de foto não pertence ao catálogo desta célula.' using errcode='22023'; end if;
      p_params:=p_params||jsonb_build_object('p_titulo',v_catalog.titulo);
    end if;
$patch$||marker);
  -- The transition function obtains the project lock before stage row locks.
  definition:=replace(definition,'where id=(p_params->>''p_aprovacao_etapa_id'')::uuid for update;',
    'where id=(p_params->>''p_aprovacao_etapa_id'')::uuid;');
  execute definition;
end $migration$;

revoke all on function rm_private.update_cell_status_v1(uuid,uuid,text),rm_private.add_cell_comment_v1(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.rm_transition_stage_approval_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.rm_transition_stage_approval_v1(uuid,uuid,text,text) to service_role;
notify pgrst,'reload schema';
commit;

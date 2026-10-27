-- ============================================================================
-- MIGRATION 003: RM (Revisão de Motores) - Outbox de Sincronização & RPCs Transacionais
-- Substitui os workflows recursivos do Bubble (codigo_sequencial, novo_form_recursivo,
-- projetocell_copy) e as cadeias de ações de rm_mobile por transações atômicas no PostgreSQL.
-- ============================================================================

begin;

-- ============================================================================
-- 1. FILA TRANSACIONAL DE SINCRONIZAÇÃO (SUPABASE <-> BUBBLE / N8N)
-- Permite que o Mobile grave 100% no Supabase enquanto um worker sincroniza
-- assincronamente com o Bubble Desktop e os webhooks do n8n durante a transição.
-- ============================================================================

create table if not exists public.rm_sync_outbox (
  id bigint generated always as identity primary key,
  target_system text not null check (target_system in ('bubble_data_api', 'bubble_workflow_api', 'n8n_webhook')),
  entity_type text not null,         -- Ex.: 'ProjetoRM', 'Equipamento', 'Registro_Formulario', 'email_orcamento'
  operation text not null check (operation in ('create', 'update', 'delete', 'trigger_webhook')),
  record_id uuid not null,
  bubble_id text,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed', 'dead_letter')),
  attempts integer not null default 0,
  max_attempts integer not null default 8,
  next_retry_at timestamptz not null default clock_timestamp(),
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  processed_at timestamptz
);

create index if not exists idx_rm_sync_outbox_pending
  on public.rm_sync_outbox (status, next_retry_at, id)
  where status in ('pending', 'failed');

-- Helper interno para enfileirar eventos de sincronização apenas quando originados no Supabase/Mobile
create or replace function rm_private.enqueue_sync_event(
  p_target_system text,
  p_entity_type text,
  p_operation text,
  p_record_id uuid,
  p_bubble_id text,
  p_payload jsonb
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into public.rm_sync_outbox (
    target_system,
    entity_type,
    operation,
    record_id,
    bubble_id,
    payload
  )
  values (
    p_target_system,
    p_entity_type,
    p_operation,
    p_record_id,
    p_bubble_id,
    p_payload
  )
  returning id;
$$;

-- ============================================================================
-- 2. RPC: AUTENTICAÇÃO DE OPERADOR DE CHÃO DE FÁBRICA (Substitui página `identify` coZum)
-- Valida Matrícula + Palavra-chave sem expor a tabela de credenciais, faz upgrade
-- automático de senhas legadas para bcrypt, vincula o operador ao Tablet_Celula_User
-- e grava EventoSistema (tipo = 'identidade').
-- ============================================================================

create or replace function public.rm_authenticate_operator_v1(
  p_matricula text,
  p_palavra_chave text,
  p_tablet_user_id uuid default null,
  p_celula_id uuid default null,
  p_ip text default null,
  p_local text default 'rm_mobile'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.rm_users%rowtype;
  v_cred rm_private.user_credentials%rowtype;
  v_password_ok boolean := false;
  v_celulas jsonb;
begin
  if p_matricula is null or btrim(p_matricula) = '' or p_palavra_chave is null or p_palavra_chave = '' then
    raise exception 'Matrícula e palavra-chave são obrigatórias.' using errcode = '28000';
  end if;

  select u.*
  into v_user
  from public.rm_users u
  where lower(btrim(u.matricula)) = lower(btrim(p_matricula))
  limit 1;

  if not found then
    raise exception 'Operador não encontrado para a matrícula informada.' using errcode = '28P01';
  end if;

  if v_user.status <> 'ativo' then
    raise exception 'Operador inativo no sistema RM.' using errcode = '28000';
  end if;

  select c.*
  into v_cred
  from rm_private.user_credentials c
  where c.user_id = v_user.id;

  if found then
    if v_cred.palavra_chave_hash is not null then
      v_password_ok := (v_cred.palavra_chave_hash = extensions.crypt(p_palavra_chave, v_cred.palavra_chave_hash));
    elsif v_cred.palavra_chave_legacy_plain is not null then
      v_password_ok := (v_cred.palavra_chave_legacy_plain = p_palavra_chave);
      if v_password_ok then
        -- Faz upgrade transparente da palavra-chave legada do Bubble para bcrypt
        update rm_private.user_credentials
        set palavra_chave_hash = extensions.crypt(p_palavra_chave, extensions.gen_salt('bf', 10)),
            palavra_chave_legacy_plain = null,
            updated_at = pg_catalog.clock_timestamp()
        where user_id = v_user.id;
      end if;
    end if;
  end if;

  if not v_password_ok then
    update public.rm_users
    set tentativas_login = coalesce(tentativas_login, 0) + 1
    where id = v_user.id;

    raise exception 'Palavra-chave inválida.' using errcode = '28P01';
  end if;

  -- Atualiza último acesso e zera contador de falhas
  update public.rm_users
  set ultimo_acesso = pg_catalog.clock_timestamp(),
      tentativas_login = 0
  where id = v_user.id;

  -- Se o tablet/célula foi informado, atualiza a identidade delegada em Tablet_Celula_User
  if p_tablet_user_id is not null then
    update public.rm_tablet_celula_users
    set identidade_id = v_user.id
    where usuario_id = p_tablet_user_id
      and (p_celula_id is null or celula_id = p_celula_id);
  end if;

  -- Registra EventoSistema (tipo = 'identidade'), replicando o fluxo de identify (coZum)
  insert into public.rm_eventos_sistema (user_id, tipo, ip, local, sync_source)
  values (v_user.id, 'identidade', p_ip, p_local, 'supabase');

  -- Busca células vinculadas ao tablet ou ao operador
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'celula_id', c.id,
        'bubble_id', c.bubble_id,
        'codigo', c.codigo,
        'nome', c.nome,
        'ordem', c.ordem
      )
      order by c.ordem nulls last, c.indice nulls last
    ),
    '[]'::jsonb
  )
  into v_celulas
  from public.rm_celulas c
  where exists (
    select 1
    from public.rm_tablet_celula_users tcu
    where tcu.celula_id = c.id
      and (
        tcu.identidade_id = v_user.id
        or (p_tablet_user_id is not null and tcu.usuario_id = p_tablet_user_id)
      )
  );

  return jsonb_build_object(
    'operador_id', v_user.id,
    'bubble_id', v_user.bubble_id,
    'matricula', v_user.matricula,
    'nome', v_user.nome,
    'cargo', v_user.cargo,
    'perfil', v_user.perfil,
    'perfil_assinante', v_user.perfil_assinante,
    'equipe_id', v_user.equipe_id,
    'criar_form', v_user.criar_form,
    'celulas_vinculadas', v_celulas,
    'authenticated_at', pg_catalog.clock_timestamp()
  );
end;
$$;

-- ============================================================================
-- 3. RPC: SEQUENCIAL ATÔMICO POR FORMULÁRIO (Substitui `codigo_sequencial` coUMy)
-- Elimina a condição de corrida do Bubble usando UPSERT atômico com lock de linha.
-- ============================================================================

create or replace function rm_private.next_form_sequence_v1(p_form_id uuid)
returns integer
language sql
security definer
set search_path = ''
as $$
  insert into public.rm_numeracoes (form_id, ult_numero, sync_source)
  values (p_form_id, 1, 'supabase')
  on conflict (form_id) do update
    set ult_numero = public.rm_numeracoes.ult_numero + 1,
        updated_at = pg_catalog.clock_timestamp()
  returning ult_numero;
$$;

-- ============================================================================
-- 4. RPC: RECEBIMENTO COMPLETO DE EQUIPAMENTO (Substitui wizard `formrecebimento`
-- eventos cojXG, cojXl e cofqG + disparo de e-mail para n8n)
-- ============================================================================

create or replace function public.rm_submit_recebimento_v1(
  p_operador_id uuid,
  p_cliente_id uuid,
  p_tipo_equipamento_id uuid,
  p_numero_projeto text,
  p_nome_projeto text,
  p_chegada_equipamento timestamptz,
  p_contato text,
  p_proprietario text,
  p_eventualidades text,
  p_equipamento jsonb,
  p_fotos_recebimento jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_projeto_id uuid;
  v_equipamento_id uuid;
  v_cliente_nome text;
  v_tipo_eq_nome text;
  v_operador_nome text;
  v_foto jsonb;
  v_foto_id uuid;
  v_fotos_criadas integer := 0;
begin
  if p_numero_projeto is null or btrim(p_numero_projeto) = '' then
    raise exception 'O número do Projeto RM é obrigatório no recebimento.' using errcode = '22023';
  end if;

  select nome into v_cliente_nome from public.rm_clientes where id = p_cliente_id;
  select nome into v_tipo_eq_nome from public.rm_tipos_equipamento where id = p_tipo_equipamento_id;
  select nome into v_operador_nome from public.rm_users where id = p_operador_id;

  -- 1. Cria ProjetoRM (custom.projeto_rm)
  insert into public.rm_projetos (
    numero,
    nome,
    cliente_id,
    cliente_nome_exportacao,
    tipo_equipamento_id,
    contato,
    proprietario,
    eventualidades,
    chegada_do_equipamento,
    descricao_equipamento,
    escopo_abreviado,
    status,
    status_pcp,
    created_by_user_id,
    sync_source
  )
  values (
    btrim(p_numero_projeto),
    coalesce(nullif(btrim(p_nome_projeto), ''), btrim(p_numero_projeto)),
    p_cliente_id,
    v_cliente_nome,
    p_tipo_equipamento_id,
    p_contato,
    p_proprietario,
    p_eventualidades,
    coalesce(p_chegada_equipamento, pg_catalog.clock_timestamp()),
    p_equipamento->>'descricao',
    v_tipo_eq_nome,
    'peritagem',
    'equipamento_em_inspe__o',
    p_operador_id,
    'supabase'
  )
  returning id into v_projeto_id;

  -- 2. Cria Equipamento (custom.dados_equipamento) com os passos A-G do wizard
  insert into public.rm_equipamentos (
    projeto_id,
    tipo_equipamento_id,
    placa_motor,
    desmontar_para_orcar,
    ensaiar_antes_desmontar,
    teste_intermediario,
    embarcacao,
    fabricante,
    modelo,
    numero_serie,
    descricao,
    certificado,
    norma,
    potencia,
    rotacao,
    tensao_estator,
    tipo_tensao,
    corrente_estator,
    corrente_partida,
    frequencia,
    classe_isolamento,
    grau_ip,
    forma,
    regime,
    peso,
    ligacao,
    componentes,
    fp,
    fs,
    numero_cabos,
    sync_source
  )
  values (
    v_projeto_id,
    p_tipo_equipamento_id,
    nullif(p_equipamento->>'placa_motor', '')::public.rm_placa_motor_enum,
    nullif(p_equipamento->>'desmontar_para_orcar', '')::public.rm_sim_nao_enum,
    nullif(p_equipamento->>'ensaiar_antes_desmontar', '')::public.rm_sim_nao_enum,
    nullif(p_equipamento->>'teste_intermediario', '')::public.rm_sim_nao_enum,
    p_equipamento->>'embarcacao',
    p_equipamento->>'fabricante',
    p_equipamento->>'modelo',
    p_equipamento->>'numero_serie',
    p_equipamento->>'descricao',
    p_equipamento->>'certificado',
    p_equipamento->>'norma',
    p_equipamento->>'potencia',
    p_equipamento->>'rotacao',
    p_equipamento->>'tensao_estator',
    p_equipamento->>'tipo_tensao',
    p_equipamento->>'corrente_estator',
    p_equipamento->>'corrente_partida',
    p_equipamento->>'frequencia',
    p_equipamento->>'classe_isolamento',
    p_equipamento->>'grau_ip',
    p_equipamento->>'forma',
    p_equipamento->>'regime',
    p_equipamento->>'peso',
    p_equipamento->>'ligacao',
    p_equipamento->>'componentes',
    nullif(p_equipamento->>'fp', '')::numeric,
    nullif(p_equipamento->>'fs', '')::numeric,
    nullif(p_equipamento->>'numero_cabos', '')::integer,
    'supabase'
  )
  returning id into v_equipamento_id;

  -- Vincula Equipamento de volta ao ProjetoRM
  update public.rm_projetos
  set equipamento_id = v_equipamento_id
  where id = v_projeto_id;

  -- 3. Insere Fotos de Recebimento (Obrigatórias e Complementares)
  for v_foto in select * from jsonb_array_elements(coalesce(p_fotos_recebimento, '[]'::jsonb))
  loop
    insert into public.rm_fotos (
      projeto_id,
      etapa,
      categoria_foto,
      tipo_recebimento,
      identificador_foto_key,
      titulo,
      descricao,
      legenda,
      foto_url,
      numero,
      numero_foto_complementar,
      created_by_user_id,
      modified_by_id,
      sync_source
    )
    values (
      v_projeto_id,
      'recebimento',
      coalesce(nullif(v_foto->>'categoria_foto', '')::public.rm_categoria_foto_enum, 'obrigat_ria'),
      nullif(v_foto->>'tipo_recebimento', '')::public.rm_tipo_foto_recebimento_enum,
      v_foto->>'identificador_foto_key',
      v_foto->>'titulo',
      v_foto->>'descricao',
      v_foto->>'legenda',
      v_foto->>'foto_url',
      nullif(v_foto->>'numero', '')::integer,
      nullif(v_foto->>'numero_foto_complementar', '')::integer,
      p_operador_id,
      p_operador_id,
      'supabase'
    )
    returning id into v_foto_id;

    v_fotos_criadas := v_fotos_criadas + 1;
  end loop;

  -- 4. Enfileira sincronização para o Bubble Desktop + Webhook n8n (Enviar E-mail Orçamentos)
  perform rm_private.enqueue_sync_event(
    'bubble_data_api',
    'Recebimento_Bundle',
    'create',
    v_projeto_id,
    null,
    jsonb_build_object(
      'projeto_id', v_projeto_id,
      'equipamento_id', v_equipamento_id,
      'numero_projeto', btrim(p_numero_projeto)
    )
  );

  perform rm_private.enqueue_sync_event(
    'n8n_webhook',
    'enviar_email_orcamento',
    'trigger_webhook',
    v_projeto_id,
    null,
    jsonb_build_object(
      'webhook_url', 'https://n8n.miconnect.app.br/webhook/f3e0bb34-4090-49b0-a11d-2ed4fb7bd7ab',
      'body', jsonb_build_object(
        'num_proj', btrim(p_numero_projeto),
        'cliente', coalesce(v_cliente_nome, ''),
        'data', to_char(coalesce(p_chegada_equipamento, pg_catalog.clock_timestamp()), 'DD/MM/YYYY'),
        'responsavel', coalesce(v_operador_nome, ''),
        'tipo_motor', coalesce(v_tipo_eq_nome, ''),
        'fabricante', coalesce(p_equipamento->>'fabricante', ''),
        'potencia', coalesce(p_equipamento->>'potencia', ''),
        'rpm', coalesce(p_equipamento->>'rotacao', ''),
        'tensao', coalesce(p_equipamento->>'tensao_estator', '')
      )
    )
  );

  return jsonb_build_object(
    'projeto_id', v_projeto_id,
    'equipamento_id', v_equipamento_id,
    'fotos_criadas', v_fotos_criadas
  );
end;
$$;

-- ============================================================================
-- 5. RPC: MATERIALIZAÇÃO DE CÉLULAS DO PROJETO (Substitui `projetocell_copy` coZAA)
-- Clona em uma única transação SQL todas as Fotos RM modelo (projeto_id IS NULL),
-- Aprovaçao_etapas modelo (projeto_id IS NULL) e cria as Celula_Projeto do ProjetoRM.
-- ============================================================================

create or replace function public.rm_materialize_project_cells_v1(
  p_projeto_id uuid,
  p_data_inicio timestamptz default clock_timestamp(),
  p_data_limite timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_projeto public.rm_projetos%rowtype;
  v_cte record;
  v_celula_projeto_id uuid;
  v_forms_ids uuid[];
  v_celulas_criadas integer := 0;
  v_fotos_clonadas integer := 0;
  v_aprovacoes_clonadas integer := 0;
begin
  select * into v_projeto from public.rm_projetos where id = p_projeto_id;
  if not found then
    raise exception 'ProjetoRM (%) não encontrado.', p_projeto_id using errcode = 'P0002';
  end if;

  if v_projeto.tipo_equipamento_id is null then
    raise exception 'ProjetoRM (%) não possui Tipo_Equipamento definido para materializar células.', v_projeto.numero using errcode = '22023';
  end if;

  for v_cte in
    select
      cte.*,
      c.ordem as celula_ordem,
      c.indice as celula_indice
    from public.rm_celula_tipos_equipamento cte
    join public.rm_celulas c on c.id = cte.celula_id
    where cte.tipo_equipamento_id = v_projeto.tipo_equipamento_id
    order by c.ordem nulls last, c.indice nulls last
  loop
    -- Coleta formulários associados a esta Celula_Tipo_Equipamento
    select coalesce(array_agg(cfte.form_id), '{}')
    into v_forms_ids
    from public.rm_celula_form_tipos_equipamento cfte
    where cfte.celula_tipo_equipamento_id = v_cte.id;

    -- Cria ou atualiza Celula_Projeto (status inicial = 'pendente', replicando projetocell_copy)
    insert into public.rm_celulas_projeto (
      projeto_id,
      celula_id,
      numero_projeto,
      cliente_nome_export,
      tipo_equipamento_nome_export,
      escopo_abreviado,
      status,
      status_historico,
      visibilidade,
      indice,
      data_inicio,
      data_limite,
      forms_ids,
      sync_source
    )
    values (
      v_projeto.id,
      v_cte.celula_id,
      v_projeto.numero,
      v_projeto.cliente_nome_exportacao,
      v_projeto.escopo_abreviado,
      v_projeto.escopo_abreviado,
      'pendente',
      array['pendente'::public.rm_status_cel_proj_enum],
      coalesce(v_cte.visibilidade, false),
      coalesce(v_cte.celula_ordem, v_cte.celula_indice),
      p_data_inicio,
      p_data_limite,
      v_forms_ids,
      'supabase'
    )
    on conflict (projeto_id, celula_id) do update
      set numero_projeto = excluded.numero_projeto,
          data_limite = coalesce(excluded.data_limite, public.rm_celulas_projeto.data_limite),
          forms_ids = excluded.forms_ids
    returning id into v_celula_projeto_id;

    v_celulas_criadas := v_celulas_criadas + 1;

    -- Clona Fotos RM modelo (onde projeto_id IS NULL para esta Celula_Tipo_Equipamento) se ainda não clonadas
    if not exists (
      select 1 from public.rm_fotos f
      where f.projeto_id = v_projeto.id
        and f.celula_tipo_equipamento_id = v_cte.id
    ) then
      insert into public.rm_fotos (
        projeto_id,
        celula_id,
        celula_projeto_id,
        celula_tipo_equipamento_id,
        categoria_foto,
        identificador_foto_key,
        titulo,
        descricao,
        numero,
        sync_source
      )
      select
        v_projeto.id,
        v_cte.celula_id,
        v_celula_projeto_id,
        v_cte.id,
         coalesce(ft.categoria_foto, 'obrigat_ria'),
        ft.identificador_foto_key,
        ft.titulo,
        ft.descricao,
        ft.numero,
        'supabase'
      from public.rm_fotos ft
      where ft.projeto_id is null
        and ft.celula_tipo_equipamento_id = v_cte.id
        and ft.lixeira = false;

      get diagnostics v_fotos_clonadas = row_count;
    end if;

    -- Clona Aprovaçao_etapas modelo (onde projeto_id IS NULL para esta Celula_Tipo_Equipamento)
    if not exists (
      select 1 from public.rm_aprovacoes_etapas ae
      where ae.projeto_id = v_projeto.id
        and ae.celula_tipo_equipamento_id = v_cte.id
    ) then
      insert into public.rm_aprovacoes_etapas (
        projeto_id,
        celula_projeto_id,
        celula_tipo_equipamento_id,
        celula_origem_id,
        celula_destino_id,
        bloquear_avanco_sem_aprov,
        status,
        status_cel_proj,
        aprovador_id,
        aprovadores_ids,
        aprovadores_retorno_ids,
        sync_source
      )
      select
        v_projeto.id,
        v_celula_projeto_id,
        v_cte.id,
        ae.celula_origem_id,
        ae.celula_destino_id,
        ae.bloquear_avanco_sem_aprov,
        'nulo',
        ae.status_cel_proj,
        ae.aprovador_id,
        ae.aprovadores_ids,
        ae.aprovadores_retorno_ids,
        'supabase'
      from public.rm_aprovacoes_etapas ae
      where ae.projeto_id is null
        and ae.celula_tipo_equipamento_id = v_cte.id;

      get diagnostics v_aprovacoes_clonadas = row_count;
    end if;
  end loop;

  return jsonb_build_object(
    'projeto_id', v_projeto.id,
    'celulas_materializadas', v_celulas_criadas,
    'fotos_clonadas', v_fotos_clonadas,
    'aprovacoes_clonadas', v_aprovacoes_clonadas
  );
end;
$$;

-- ============================================================================
-- 6. RPC: SUBMISSÃO ATÔMICA E IDEMPOTENTE DE FORMULÁRIO DINÂMICO
-- Substitui `coVnW` -> `coVuI`/`conTa` + `codigo_sequencial` + `novo_form_recursivo`.
-- Recebe o lote completo de respostas do SQLite local do app mobile.
-- ============================================================================

create or replace function public.rm_submit_form_inspection_v1(
  p_client_submission_id uuid,
  p_projeto_id uuid,
  p_celula_id uuid,
  p_form_id uuid,
  p_operador_id uuid,
  p_tablet_user_id uuid default null,
  p_tempo_de_vida integer default 0,
  p_respostas jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id uuid;
  v_existing_codigo integer;
  v_projeto public.rm_projetos%rowtype;
  v_form public.rm_forms%rowtype;
  v_operador public.rm_users%rowtype;
  v_codigo integer;
  v_codigo_text text;
  v_registro_id uuid;
  v_resp jsonb;
  v_respostas_count integer := 0;
begin
  -- 1. Verificação de idempotência (evita duplicação em retentativas offline/online)
  if p_client_submission_id is not null then
    select id, codigo
    into v_existing_id, v_existing_codigo
    from public.rm_registros_formulario
    where client_submission_id = p_client_submission_id;

    if found then
      return jsonb_build_object(
        'registro_formulario_id', v_existing_id,
        'codigo', v_existing_codigo,
        'idempotent_replay', true
      );
    end if;
  end if;

  select * into v_projeto from public.rm_projetos where id = p_projeto_id;
  if not found then
    raise exception 'ProjetoRM (%) não encontrado.', p_projeto_id using errcode = 'P0002';
  end if;

  select * into v_form from public.rm_forms where id = p_form_id;
  if not found then
    raise exception 'Formulário (%) não encontrado.', p_form_id using errcode = 'P0002';
  end if;

  select * into v_operador from public.rm_users where id = p_operador_id;

  -- 2. Reserva número sequencial atômico por Form (substitui codigo_sequencial)
  v_codigo := rm_private.next_form_sequence_v1(p_form_id);
  v_codigo_text := lpad(v_codigo::text, 4, '0');

  -- 3. Cria Registro_Formulario (status = 'em_an_lise', preenchido = true)
  insert into public.rm_registros_formulario (
    client_submission_id,
    projeto_id,
    numero_projeto_rm,
    celula_id,
    form_id,
    empresa_id,
    equipe_id,
    codigo,
    codigo_text,
    descricao,
    status,
    preenchido,
    revisado,
    tempo_de_vida,
    data_conclusao,
    created_by_user_id,
    identidade_user_id,
    responsavel_user_id,
    sync_source
  )
  values (
    p_client_submission_id,
    p_projeto_id,
    v_projeto.numero,
    p_celula_id,
    p_form_id,
    v_projeto.cliente_id,
    v_operador.equipe_id,
    v_codigo,
    v_codigo_text,
    v_form.titulo,
    'em_an_lise',
    true,
    false,
    coalesce(p_tempo_de_vida, 0),
    pg_catalog.clock_timestamp(),
    coalesce(p_tablet_user_id, p_operador_id),
    p_operador_id,
    p_operador_id,
    'supabase'
  )
  returning id into v_registro_id;

  -- 4. Grava todas as Respostas em lote (substitui novo_form_recursivo cofnw)
  for v_resp in select * from jsonb_array_elements(coalesce(p_respostas, '[]'::jsonb))
  loop
    insert into public.rm_respostas (
      registro_formulario_id,
      questao_id,
      id_registro_text,
      titulo_form,
      indice,
      enunciado,
      tag,
      tipo,
      dimensoes,
      resposta,
      itens,
      itens_questoes_ids,
      fotos_urls,
      assinatura_url,
      date_inicio,
      data_fim,
      hora,
      revisar,
      sync_source
    )
    values (
      v_registro_id,
      (v_resp->>'questao_id')::uuid,
      v_registro_id::text,
      v_form.titulo,
      nullif(v_resp->>'indice', '')::integer,
      v_resp->>'enunciado',
      v_resp->>'tag',
      nullif(v_resp->>'tipo', '')::public.rm_tipo_questao_enum,
      nullif(v_resp->>'dimensoes', '')::public.rm_dimensao_enum,
      v_resp->>'resposta',
      coalesce(
        array(select jsonb_array_elements_text(coalesce(v_resp->'itens', '[]'::jsonb))),
        '{}'
      ),
      coalesce(
        array(select (jsonb_array_elements_text(coalesce(v_resp->'itens_questoes_ids', '[]'::jsonb)))::uuid),
        '{}'
      ),
      coalesce(
        array(select jsonb_array_elements_text(coalesce(v_resp->'fotos_urls', '[]'::jsonb))),
        '{}'
      ),
      v_resp->>'assinatura_url',
      nullif(v_resp->>'date_inicio', '')::timestamptz,
      nullif(v_resp->>'data_fim', '')::timestamptz,
      nullif(v_resp->>'hora', '')::timestamptz,
      false,
      'supabase'
    )
    on conflict (registro_formulario_id, questao_id) do update
      set resposta = excluded.resposta,
          itens = excluded.itens,
          itens_questoes_ids = excluded.itens_questoes_ids,
          fotos_urls = excluded.fotos_urls,
          assinatura_url = excluded.assinatura_url,
          date_inicio = excluded.date_inicio,
          data_fim = excluded.data_fim,
          hora = excluded.hora;

    v_respostas_count := v_respostas_count + 1;
  end loop;

  -- 5. Remove rascunhos temporários no servidor (caso existam para este projeto/form/operador)
  delete from public.rm_respostas_temp
  where projeto_id = p_projeto_id
    and form_id = p_form_id
    and (operador_user_id = p_operador_id or operador_user_id is null);

  -- 6. Enfileira sincronização do Registro_Formulario + Respostas para o Bubble Desktop
  perform rm_private.enqueue_sync_event(
    'bubble_data_api',
    'Registro_Formulario_Bundle',
    'create',
    v_registro_id,
    null,
    jsonb_build_object(
      'registro_formulario_id', v_registro_id,
      'projeto_id', p_projeto_id,
      'form_id', p_form_id,
      'codigo', v_codigo,
      'respostas_count', v_respostas_count
    )
  );

  return jsonb_build_object(
    'registro_formulario_id', v_registro_id,
    'codigo', v_codigo,
    'codigo_text', v_codigo_text,
    'respostas_gravadas', v_respostas_count,
    'idempotent_replay', false
  );
end;
$$;

-- ============================================================================
-- 7. RPC: CORREÇÃO DE RESPOSTAS EM REVISÃO (Substitui `Popup Corrigir` cofgY)
-- Quando o supervisor no desktop marca respostas com `revisar = true` e muda o
-- Registro_Formulario para `direcionado` (Display "Revisar"), o operador corrige
-- os itens no mobile e devolve o formulário para `em_an_lise`.
-- ============================================================================

create or replace function public.rm_submit_form_revision_v1(
  p_registro_formulario_id uuid,
  p_operador_id uuid,
  p_respostas_corrigidas jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_corrigidas integer := 0;
  v_pendentes integer := 0;
begin
  for v_item in select * from jsonb_array_elements(coalesce(p_respostas_corrigidas, '[]'::jsonb))
  loop
    update public.rm_respostas
    set resposta = coalesce(v_item->>'resposta', resposta),
        itens = case
          when v_item ? 'itens' then array(select jsonb_array_elements_text(v_item->'itens'))
          else itens
        end,
        fotos_urls = case
          when v_item ? 'fotos_urls' then array(select jsonb_array_elements_text(v_item->'fotos_urls'))
          else fotos_urls
        end,
        assinatura_url = coalesce(v_item->>'assinatura_url', assinatura_url),
        date_inicio = coalesce(nullif(v_item->>'date_inicio', '')::timestamptz, date_inicio),
        data_fim = coalesce(nullif(v_item->>'data_fim', '')::timestamptz, data_fim),
        hora = coalesce(nullif(v_item->>'hora', '')::timestamptz, hora),
        revisar = false,
        sync_source = 'supabase'
    where registro_formulario_id = p_registro_formulario_id
      and (
        (v_item ? 'resposta_id' and id = (v_item->>'resposta_id')::uuid)
        or (v_item ? 'questao_id' and questao_id = (v_item->>'questao_id')::uuid)
      );

    v_corrigidas := v_corrigidas + 1;
  end loop;

  -- Verifica se ainda restou alguma resposta marcada como revisar = true
  select count(*)
  into v_pendentes
  from public.rm_respostas
  where registro_formulario_id = p_registro_formulario_id
    and revisar = true;

  if v_pendentes = 0 then
    update public.rm_registros_formulario
    set status = 'em_an_lise',
        revisado = true,
        data_revisao = pg_catalog.clock_timestamp(),
        user_revisao_id = p_operador_id,
        sync_source = 'supabase'
    where id = p_registro_formulario_id;
  end if;

  perform rm_private.enqueue_sync_event(
    'bubble_data_api',
    'Registro_Formulario_Revision',
    'update',
    p_registro_formulario_id,
    null,
    jsonb_build_object(
      'registro_formulario_id', p_registro_formulario_id,
      'operador_id', p_operador_id,
      'corrigidas', v_corrigidas,
      'pendentes_revisao', v_pendentes
    )
  );

  return jsonb_build_object(
    'registro_formulario_id', p_registro_formulario_id,
    'respostas_corrigidas', v_corrigidas,
    'pendentes_revisao', v_pendentes,
    'novo_status', case when v_pendentes = 0 then 'em_an_lise' else 'direcionado' end
  );
end;
$$;

-- ============================================================================
-- 8. RPC: TRANSIÇÃO DE APROVAÇÃO DE ETAPAS ENTRE CÉLULAS
-- Substitui os 4 workflows de `aprovacoes` em rm_mobile:
--   - 'liberar'         (copmq - 13 ações)
--   - 'retornar'        (copmY - 6 ações)
--   - 'aprovar'         (copzz - 5 ações)
--   - 'finalizar_ciclo' (conwe - 5 ações)
-- ============================================================================

create or replace function public.rm_transition_stage_approval_v1(
  p_aprovacao_etapa_id uuid,
  p_operador_id uuid,
  p_acao text, -- 'liberar' | 'retornar' | 'aprovar' | 'finalizar_ciclo'
  p_observacao text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ae public.rm_aprovacoes_etapas%rowtype;
  v_projeto public.rm_projetos%rowtype;
  v_equipamento public.rm_equipamentos%rowtype;
  v_celula_origem_nome text;
  v_celula_destino_nome text;
  v_operador_nome text;
  v_novo_status_etapa public.rm_status_etapa_enum;
  v_target_celula_id uuid;
begin
  select * into v_ae from public.rm_aprovacoes_etapas where id = p_aprovacao_etapa_id for update;
  if not found then
    raise exception 'Aprovaçao_etapas (%) não encontrada.', p_aprovacao_etapa_id using errcode = 'P0002';
  end if;

  select * into v_projeto from public.rm_projetos where id = v_ae.projeto_id;
  select * into v_equipamento from public.rm_equipamentos where projeto_id = v_ae.projeto_id limit 1;
  select nome into v_celula_origem_nome from public.rm_celulas where id = v_ae.celula_origem_id;
  select nome into v_celula_destino_nome from public.rm_celulas where id = v_ae.celula_destino_id;
  select nome into v_operador_nome from public.rm_users where id = p_operador_id;

  if p_acao = 'liberar' then
    -- Equivalente exato de copmq (Button Liberar etapa is clicked)
    v_novo_status_etapa := 'nulo';

    update public.rm_aprovacoes_etapas
    set status = 'nulo',
        data_aprovacao = pg_catalog.clock_timestamp(),
        aprovado_por_id = p_operador_id,
        sync_source = 'supabase'
    where id = v_ae.id;

    -- Se não exige bloqueio de aprovação ou avança direto para célula destino
    v_target_celula_id := coalesce(v_ae.celula_destino_id, v_ae.celula_origem_id);

    update public.rm_celulas_projeto
    set visibilidade = true,
        status = coalesce(v_ae.status_cel_proj, 'para_execu__o'),
        status_historico = array_append(status_historico, coalesce(v_ae.status_cel_proj, 'para_execu__o')),
        modified_by_id = p_operador_id,
        sync_source = 'supabase'
    where projeto_id = v_ae.projeto_id
      and celula_id = v_target_celula_id;

    insert into public.rm_logs_aprovacao (
      projeto_id,
      celula_id,
      aprovador_id,
      status_aprovacao,
      data_aprovacao,
      sync_source
    )
    values (
      v_ae.projeto_id,
      v_ae.celula_origem_id,
      p_operador_id,
      'aprovado',
      pg_catalog.clock_timestamp(),
      'supabase'
    );

  elsif p_acao = 'retornar' then
    -- Equivalente exato de copmY (Button Retornar etapa is clicked)
    v_novo_status_etapa := 'reprovado';

    update public.rm_aprovacoes_etapas
    set status = 'reprovado',
        data_aprovacao = pg_catalog.clock_timestamp(),
        aprovado_por_id = p_operador_id,
        sync_source = 'supabase'
    where id = v_ae.id;

    update public.rm_celulas_projeto
    set status = 'retornado',
        status_historico = array_append(status_historico, 'retornado'::public.rm_status_cel_proj_enum),
        visibilidade = true,
        modified_by_id = p_operador_id,
        sync_source = 'supabase'
    where projeto_id = v_ae.projeto_id
      and celula_id = v_ae.celula_origem_id;

    insert into public.rm_logs_aprovacao (
      projeto_id,
      celula_id,
      aprovador_id,
      status_aprovacao,
      data_aprovacao,
      sync_source
    )
    values (
      v_ae.projeto_id,
      v_ae.celula_origem_id,
      p_operador_id,
      'reprovado',
      pg_catalog.clock_timestamp(),
      'supabase'
    );

  elsif p_acao = 'aprovar' then
    -- Equivalente exato de copzz (Button Aprovar etapa is clicked)
    v_novo_status_etapa := 'aprovado';

    update public.rm_aprovacoes_etapas
    set status = 'aprovado',
        data_aprovacao = pg_catalog.clock_timestamp(),
        aprovado_por_id = p_operador_id,
        sync_source = 'supabase'
    where id = v_ae.id;

    if v_ae.celula_destino_id is not null then
      update public.rm_celulas_projeto
      set visibilidade = true,
          status = coalesce(v_ae.status_cel_proj, 'para_execu__o'),
          status_historico = array_append(status_historico, coalesce(v_ae.status_cel_proj, 'para_execu__o')),
          modified_by_id = p_operador_id,
          sync_source = 'supabase'
      where projeto_id = v_ae.projeto_id
        and celula_id = v_ae.celula_destino_id;
    end if;

    insert into public.rm_logs_aprovacao (
      projeto_id,
      celula_id,
      aprovador_id,
      status_aprovacao,
      data_aprovacao,
      sync_source
    )
    values (
      v_ae.projeto_id,
      v_ae.celula_origem_id,
      p_operador_id,
      'aprovado',
      pg_catalog.clock_timestamp(),
      'supabase'
    );

  elsif p_acao = 'finalizar_ciclo' then
    -- Equivalente exato de conwe (Button Finalizar ciclo is clicked)
    v_novo_status_etapa := 'aprovado';

    update public.rm_celulas_projeto
    set status = 'finalizado',
        status_historico = array_append(status_historico, 'finalizado'::public.rm_status_cel_proj_enum),
        data_fim_real = pg_catalog.clock_timestamp(),
        modified_by_id = p_operador_id,
        sync_source = 'supabase'
    where projeto_id = v_ae.projeto_id
      and celula_id = v_ae.celula_origem_id;

    insert into public.rm_logs_aprovacao (
      projeto_id,
      celula_id,
      aprovador_id,
      status_aprovacao,
      data_aprovacao,
      sync_source
    )
    values (
      v_ae.projeto_id,
      v_ae.celula_origem_id,
      p_operador_id,
      'aprovado',
      pg_catalog.clock_timestamp(),
      'supabase'
    );

  else
    raise exception 'Ação de etapa inválida: %. Use liberar, retornar, aprovar ou finalizar_ciclo.', p_acao
      using errcode = '22023';
  end if;

  -- Registra comentário opcional na célula
  if p_observacao is not null and btrim(p_observacao) <> '' then
    insert into public.rm_comentarios (
      projeto_id,
      celula_id,
      cadastrado_por_id,
      evento,
      sync_source
    )
    values (
      v_ae.projeto_id,
      v_ae.celula_origem_id,
      p_operador_id,
      btrim(p_observacao),
      'supabase'
    );
  end if;

  -- Enfileira sincronização para o Bubble Desktop + Webhook n8n (Enviar E-mail Orçamentos Aprovação)
  perform rm_private.enqueue_sync_event(
    'bubble_data_api',
    'Aprovacao_Etapa_Transition',
    'update',
    v_ae.id,
    v_ae.bubble_id,
    jsonb_build_object(
      'aprovacao_etapa_id', v_ae.id,
      'projeto_id', v_ae.projeto_id,
      'acao', p_acao,
      'operador_id', p_operador_id,
      'status_etapa', v_novo_status_etapa
    )
  );

  if p_acao in ('liberar', 'retornar') then
    perform rm_private.enqueue_sync_event(
      'n8n_webhook',
      'enviar_email_aprovacao_etapa',
      'trigger_webhook',
      v_ae.id,
      v_ae.bubble_id,
      jsonb_build_object(
        'webhook_url', 'https://n8n.miconnect.app.br/webhook/fd1b9d72-ef51-4037-ba5a-ac15efdfbc3f',
        'body', jsonb_build_object(
          'num_proj', coalesce(v_projeto.numero, ''),
          'cliente', coalesce(v_projeto.cliente_nome_exportacao, ''),
          'data', to_char(pg_catalog.clock_timestamp(), 'DD/MM/YYYY HH24:MI'),
          'responsavel', coalesce(v_operador_nome, ''),
          'tipo_motor', coalesce(v_projeto.escopo_abreviado, ''),
          'fabricante', coalesce(v_equipamento.fabricante, ''),
          'potencia', coalesce(v_equipamento.potencia, ''),
          'rpm', coalesce(v_equipamento.rotacao, ''),
          'tensao', coalesce(v_equipamento.tensao_estator, ''),
          'etapa', coalesce(v_celula_origem_nome, ''),
          'status', rm_private.resolve_option_display('status_cel_proj', v_ae.status_cel_proj::text)
        )
      )
    );
  end if;

  return jsonb_build_object(
    'aprovacao_etapa_id', v_ae.id,
    'projeto_id', v_ae.projeto_id,
    'acao', p_acao,
    'novo_status_etapa', v_novo_status_etapa
  );
end;
$$;

-- ============================================================================
-- 9. RPC: REGISTRO DE FOTO EM SLOT PRÉ-CADASTRADO OU COMPLEMENTAR NA CÉLULA
-- No Desktop (rm_gestao / rm_planejamento), os títulos das fotos são
-- pré-cadastrados em `Cadastro Fotos` e materializados como linhas em `Fotos RM`
-- (com `titulo` preenchido e `foto_url` nulo) vinculadas à `Celula_Projeto`.
-- No Tablet (rm_mobile), o operador seleciona o slot pré-cadastrado e registra
-- a foto (ou adiciona uma foto complementar).
-- ============================================================================

create or replace function public.rm_record_cell_photo_v1(
  p_operador_id uuid,
  p_foto_id uuid default null,           -- Slot pré-cadastrado em rm_fotos (quando Obrigatória)
  p_projeto_id uuid default null,
  p_celula_id uuid default null,
  p_celula_projeto_id uuid default null,
  p_foto_url text default null,
  p_legenda text default null,
  p_titulo text default null,
  p_categoria_foto public.rm_categoria_foto_enum default 'obrigat_ria'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_foto public.rm_fotos%rowtype;
  v_pendencias_obrigatorias integer := 0;
begin
  if p_foto_url is null or btrim(p_foto_url) = '' then
    raise exception 'A URL da foto capturada é obrigatória.' using errcode = '22023';
  end if;

  if p_foto_id is not null then
    -- Atualiza o slot de foto obrigatória pré-cadastrado pelo Desktop
    update public.rm_fotos
    set foto_url = btrim(p_foto_url),
        legenda = coalesce(p_legenda, legenda),
        modified_by_id = p_operador_id,
        lixeira = false,
        sync_source = 'supabase'
    where id = p_foto_id
    returning * into v_foto;

    if not found then
      raise exception 'Slot de foto pré-cadastrado (%) não encontrado.', p_foto_id using errcode = 'P0002';
    end if;
  else
    -- Cria nova foto complementar na célula
    if p_projeto_id is null or p_celula_id is null then
      raise exception 'p_projeto_id e p_celula_id são obrigatórios para nova foto na célula.' using errcode = '22023';
    end if;

    insert into public.rm_fotos (
      projeto_id,
      celula_id,
      celula_projeto_id,
      categoria_foto,
      titulo,
      legenda,
      foto_url,
      created_by_user_id,
      modified_by_id,
      lixeira,
      sync_source
    )
    values (
      p_projeto_id,
      p_celula_id,
      p_celula_projeto_id,
      coalesce(p_categoria_foto, 'complementar'),
      coalesce(p_titulo, 'Foto complementar'),
      p_legenda,
      btrim(p_foto_url),
      p_operador_id,
      p_operador_id,
      false,
      'supabase'
    )
    returning * into v_foto;
  end if;

  -- Conta quantas fotos obrigatórias pré-cadastradas ainda estão sem imagem nesta célula do projeto
  select count(*)
  into v_pendencias_obrigatorias
  from public.rm_fotos f
  where f.projeto_id = v_foto.projeto_id
    and f.celula_id = v_foto.celula_id
    and f.categoria_foto = 'obrigat_ria'
    and f.lixeira = false
    and (f.foto_url is null or btrim(f.foto_url) = '');

  -- Enfileira sincronização da foto preenchida para o Bubble Desktop (rm_planejamento / project_rm)
  perform rm_private.enqueue_sync_event(
    'bubble_data_api',
    'Fotos_RM_Sync',
    case when v_foto.bubble_id is not null then 'update' else 'create' end,
    v_foto.id,
    v_foto.bubble_id,
    jsonb_build_object(
      'foto_id', v_foto.id,
      'bubble_id', v_foto.bubble_id,
      'projeto_id', v_foto.projeto_id,
      'celula_id', v_foto.celula_id,
      'titulo', v_foto.titulo,
      'foto_url', v_foto.foto_url,
      'legenda', v_foto.legenda
    )
  );

  return jsonb_build_object(
    'foto_id', v_foto.id,
    'bubble_id', v_foto.bubble_id,
    'titulo', v_foto.titulo,
    'categoria_foto', v_foto.categoria_foto,
    'fotos_obrigatorias_pendentes_na_celula', v_pendencias_obrigatorias
  );
end;
$$;

commit;

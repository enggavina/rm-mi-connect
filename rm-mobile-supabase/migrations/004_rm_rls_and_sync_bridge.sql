-- ============================================================================
-- MIGRATION 004: RM (Revisão de Motores) - Row Level Security (RLS),
-- Storage Buckets, Realtime & Ponte Bidirecional (Bubble Desktop -> Supabase)
-- ============================================================================

begin;

-- ============================================================================
-- 1. FUNÇÕES AUXILIARES DE AUTORIZAÇÃO (RLS)
-- Suporta tanto vínculo direto com auth.uid() quanto claim JWT 'rm_operador_id'
-- emitida para tablets compartilhados no chão de fábrica.
-- ============================================================================

create or replace function rm_private.current_rm_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb->>'rm_operador_id', '')::uuid,
    (
      select u.id
      from public.rm_users u
      where u.auth_user_id = auth.uid()
        and u.status = 'ativo'
      limit 1
    )
  );
$$;

create or replace function rm_private.is_rm_authenticated()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select rm_private.current_rm_user_id() is not null;
$$;

create or replace function rm_private.is_rm_admin_or_pcp()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.rm_users u
    where u.id = rm_private.current_rm_user_id()
      and u.status = 'ativo'
      and u.perfil in ('administrador', 'padr_o')
  );
$$;

-- ============================================================================
-- 2. HABILITAÇÃO DE RLS EM TODAS AS TABELAS PÚBLICAS RM
-- Corrige a exposição pública de 94 Data Types e da tabela User no Bubble.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'rm_option_sets',
    'rm_clientes',
    'rm_contatos_clientes',
    'rm_equipes',
    'rm_users',
    'rm_tablets',
    'rm_celulas',
    'rm_tablet_celula_users',
    'rm_tipos_equipamento',
    'rm_celula_tipos_equipamento',
    'rm_cadastro_fotos',
    'rm_forms',
    'rm_celula_form_tipos_equipamento',
    'rm_questoes',
    'rm_itens_questoes',
    'rm_numeracoes',
    'rm_projetos',
    'rm_equipamentos',
    'rm_celulas_projeto',
    'rm_aprovacoes_etapas',
    'rm_fotos',
    'rm_registros_formulario',
    'rm_respostas',
    'rm_respostas_temp',
    'rm_logs_aprovacao',
    'rm_aprovacoes_registro',
    'rm_comentarios',
    'rm_notificacoes',
    'rm_eventos_sistema',
    'rm_eventos_api',
    'rm_sync_outbox'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('revoke all on table public.%I from anon;', t);
  end loop;
end
$$;

-- Políticas de leitura autenticada para catálogos e dados operacionais de campo
create policy rm_authenticated_read_option_sets on public.rm_option_sets
  for select to authenticated using (true);

create policy rm_authenticated_read_clientes on public.rm_clientes
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_contatos on public.rm_contatos_clientes
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_equipes on public.rm_equipes
  for select to authenticated using (rm_private.is_rm_authenticated());

-- rm_users não contém CPF, senha nem segredo TOTP (movidos para rm_private.user_credentials)
create policy rm_authenticated_read_users on public.rm_users
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_tablets on public.rm_tablets
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_celulas on public.rm_celulas
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_tcu on public.rm_tablet_celula_users
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_tipos_eq on public.rm_tipos_equipamento
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_cte on public.rm_celula_tipos_equipamento
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_cad_fotos on public.rm_cadastro_fotos
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_forms on public.rm_forms
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_cfte on public.rm_celula_form_tipos_equipamento
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_questoes on public.rm_questoes
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_itens_questoes on public.rm_itens_questoes
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_numeracoes on public.rm_numeracoes
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_projetos on public.rm_projetos
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_equipamentos on public.rm_equipamentos
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_celulas_projeto on public.rm_celulas_projeto
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_aprovacoes_etapas on public.rm_aprovacoes_etapas
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_fotos on public.rm_fotos
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_write_fotos on public.rm_fotos
  for insert to authenticated with check (rm_private.is_rm_authenticated());

create policy rm_authenticated_update_fotos on public.rm_fotos
  for update to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_registros_form on public.rm_registros_formulario
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_respostas on public.rm_respostas
  for select to authenticated using (rm_private.is_rm_authenticated());

-- Rascunhos temporários isolados estritamente pelo operador autenticado
create policy rm_operator_own_respostas_temp on public.rm_respostas_temp
  for all to authenticated
  using (operador_user_id = rm_private.current_rm_user_id() or rm_private.is_rm_admin_or_pcp())
  with check (operador_user_id = rm_private.current_rm_user_id() or rm_private.is_rm_admin_or_pcp());

create policy rm_authenticated_read_logs_aprovacao on public.rm_logs_aprovacao
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_read_comentarios on public.rm_comentarios
  for select to authenticated using (rm_private.is_rm_authenticated());

create policy rm_authenticated_insert_comentarios on public.rm_comentarios
  for insert to authenticated with check (rm_private.is_rm_authenticated());

create policy rm_operator_own_notificacoes on public.rm_notificacoes
  for select to authenticated
  using (user_id = rm_private.current_rm_user_id() or rm_private.is_rm_admin_or_pcp());

-- ============================================================================
-- 3. PONTE DE RECEBIMENTO DE ATUALIZAÇÕES DO DESKTOP BUBBLE (BUBBLE -> SUPABASE)
-- Quando o supervisor em `rm_planejamento` ou `proposta` aprova um formulário,
-- solicita revisão (`direcionado` / `Revisar = true`), cria um ProjetoRM ou
-- altera status de `Celula_Projeto`, este RPC aplica a mudança no Supabase com
-- `sync_source = 'bubble'` (sem gerar loop na fila rm_sync_outbox).
-- ============================================================================

create or replace function public.rm_apply_bubble_webhook_v1(
  p_entity_type text,
  p_bubble_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_status_key text;
begin
  if p_bubble_id is null or btrim(p_bubble_id) = '' then
    raise exception 'p_bubble_id é obrigatório para sincronização Bubble -> Supabase.' using errcode = '22023';
  end if;

  if p_entity_type = 'Registro_Formulario' then
    v_status_key := rm_private.resolve_option_key('status_registro0', p_payload->>'status_option_status_registro0');

    update public.rm_registros_formulario
    set status = coalesce(v_status_key::public.rm_status_registro_enum, status),
        parecer = coalesce(p_payload->>'parecer_text', parecer),
        revisado = coalesce((p_payload->>'revisado_boolean')::boolean, revisado),
        bubble_modified_at = coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
        sync_source = 'bubble'
    where bubble_id = p_bubble_id
       or (p_payload ? 'supabase_id' and id = (p_payload->>'supabase_id')::uuid)
    returning id into v_id;

    if v_id is not null and p_bubble_id is not null then
      update public.rm_registros_formulario set bubble_id = p_bubble_id where id = v_id and bubble_id is null;
    end if;

  elsif p_entity_type = 'Respostas' then
    update public.rm_respostas
    set revisar = coalesce((p_payload->>'revisar_boolean')::boolean, revisar),
        resposta = coalesce(p_payload->>'resposta_text', resposta),
        bubble_modified_at = coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
        sync_source = 'bubble'
    where bubble_id = p_bubble_id
       or (p_payload ? 'supabase_id' and id = (p_payload->>'supabase_id')::uuid)
    returning id into v_id;

  elsif p_entity_type = 'Celula_Projeto' then
    v_status_key := rm_private.resolve_option_key('status_cel_proj', p_payload->>'status_option_status_cel_proj');

    update public.rm_celulas_projeto
    set status = coalesce(v_status_key::public.rm_status_cel_proj_enum, status),
        visibilidade = coalesce((p_payload->>'visibilidade1_boolean')::boolean, visibilidade),
        bloqueada = coalesce(
          rm_private.resolve_option_key('sim_ou_nao', p_payload->>'bloqueada_option_sim_ou_nao')::public.rm_sim_nao_enum,
          bloqueada
        ),
        motivo_bloqueio = coalesce(p_payload->>'motivo_bloqueio_text', motivo_bloqueio),
        motivo_atraso = coalesce(p_payload->>'motivo_atraso_text', motivo_atraso),
        data_inicio = coalesce(nullif(p_payload->>'data_inicio_date', '')::timestamptz, data_inicio),
        data_limite = coalesce(nullif(p_payload->>'data_limite_date', '')::timestamptz, data_limite),
        horas_previstas = coalesce(nullif(p_payload->>'horas_previstas_number', '')::numeric, horas_previstas),
        forms_ids = case
          when jsonb_typeof(p_payload->'Celula_Form_Tipo_Equipamento') = 'array' then
            coalesce(
              array(
                select f.id
                from public.rm_forms f
                where f.bubble_id in (
                  select jsonb_array_elements_text(p_payload->'Celula_Form_Tipo_Equipamento')
                )
              ),
              forms_ids
            )
          else forms_ids
        end,
        bubble_modified_at = coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
        sync_source = 'bubble'
    where bubble_id = p_bubble_id
       or (p_payload ? 'supabase_id' and id = (p_payload->>'supabase_id')::uuid)
    returning id into v_id;

  elsif p_entity_type = 'Form' then
    -- Sincroniza formulários criados/editados no Construtor de Formulários Desktop (rm_gestao / settings_rm)
    insert into public.rm_forms (
      bubble_id,
      titulo,
      title,
      descricao,
      description,
      tipo,
      ativo,
      usa_aprovacao,
      celulas_ids,
      equipes_ids,
      bubble_modified_at,
      sync_source
    )
    values (
      p_bubble_id,
      coalesce(p_payload->>'Titulo', p_payload->>'Title', 'Formulário ' || right(p_bubble_id, 6)),
      p_payload->>'Title',
      p_payload->>'Descricao',
      p_payload->>'Description',
      rm_private.resolve_option_key('tipo_formulario', p_payload->>'Tipo')::public.rm_tipo_formulario_enum,
      coalesce((p_payload->>'Ativo')::boolean, true),
      coalesce((p_payload->>'Usa Aprovacao')::boolean, true),
      coalesce(
        array(
          select c.id from public.rm_celulas c
          where jsonb_typeof(p_payload->'Celulas') = 'array'
            and c.bubble_id in (select jsonb_array_elements_text(p_payload->'Celulas'))
        ),
        '{}'
      ),
      coalesce(
        array(
          select e.id from public.rm_equipes e
          where jsonb_typeof(p_payload->'Equipes') = 'array'
            and e.bubble_id in (select jsonb_array_elements_text(p_payload->'Equipes'))
        ),
        '{}'
      ),
      coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
      'bubble'
    )
    on conflict (bubble_id) do update
      set titulo = excluded.titulo,
          title = excluded.title,
          descricao = excluded.descricao,
          description = excluded.description,
          tipo = excluded.tipo,
          ativo = excluded.ativo,
          usa_aprovacao = excluded.usa_aprovacao,
          celulas_ids = excluded.celulas_ids,
          equipes_ids = excluded.equipes_ids,
          bubble_modified_at = excluded.bubble_modified_at,
          sync_source = 'bubble'
    returning id into v_id;

  elsif p_entity_type = 'Questoes' then
    -- Sincroniza questões criadas/editadas/reordenadas no Construtor de Formulários Desktop
    insert into public.rm_questoes (
      bubble_id,
      form_id,
      indice,
      enunciado,
      title,
      subtitulo,
      tag,
      tipo,
      subtipo,
      dimensoes,
      obrigatorio,
      bubble_modified_at,
      sync_source
    )
    select
      p_bubble_id,
      f.id,
      coalesce(nullif(p_payload->>'Indice', '')::integer, 1),
      coalesce(p_payload->>'Enunciado', p_payload->>'Title', 'Questão'),
      p_payload->>'Title',
      p_payload->>'Subtitulo',
      p_payload->>'Tag',
      coalesce(
        rm_private.resolve_option_key('tipo_quest_o', p_payload->>'Tipo')::public.rm_tipo_questao_enum,
        'texto_curto'
      ),
      rm_private.resolve_option_key('subtipos', p_payload->>'Subtipo')::public.rm_subtipo_questao_enum,
      rm_private.resolve_option_key('dimensoes', p_payload->>'Dimensoes')::public.rm_dimensao_enum,
      coalesce((p_payload->>'Obrigatorio')::boolean, false),
      coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
      'bubble'
    from public.rm_forms f
    where f.bubble_id = p_payload->>'Form'
    on conflict (bubble_id) do update
      set indice = excluded.indice,
          enunciado = excluded.enunciado,
          title = excluded.title,
          subtitulo = excluded.subtitulo,
          tag = excluded.tag,
          tipo = excluded.tipo,
          subtipo = excluded.subtipo,
          dimensoes = excluded.dimensoes,
          obrigatorio = excluded.obrigatorio,
          bubble_modified_at = excluded.bubble_modified_at,
          sync_source = 'bubble'
    returning id into v_id;

  elsif p_entity_type = 'Fotos_RM' then
    -- Sincroniza slots de fotos pré-cadastradas (templates ou clonadas para o ProjetoRM em projetocell_copy / Cria_fotos)
    insert into public.rm_fotos (
      bubble_id,
      projeto_id,
      celula_id,
      categoria_foto,
      etapa,
      tipo_recebimento,
      identificador_foto_key,
      titulo,
      descricao,
      legenda,
      foto_url,
      numero,
      numero_foto_complementar,
      selecao_relatorio,
      bubble_modified_at,
      sync_source
    )
    values (
      p_bubble_id,
      (select id from public.rm_projetos where bubble_id = p_payload->>'ProjetoRM' limit 1),
      (select id from public.rm_celulas where bubble_id = p_payload->>'Celula' limit 1),
      rm_private.resolve_option_key('categoriafoto', p_payload->>'Categoria Foto')::public.rm_categoria_foto_enum,
      rm_private.resolve_option_key('etapa', p_payload->>'Etapa')::public.rm_etapa_foto_enum,
      rm_private.resolve_option_key('rmtipofoto', p_payload->>'tipo')::public.rm_tipo_foto_recebimento_enum,
      p_payload->>'Identificaçao foto',
      p_payload->>'Titulo',
      p_payload->>'descrição',
      p_payload->>'Legenda',
      case
        when (p_payload->>'foto') like '//%' then 'https:' || (p_payload->>'foto')
        else nullif(p_payload->>'foto', '')
      end,
      nullif(p_payload->>'Numero', '')::integer,
      nullif(p_payload->>'Numero foto complementar', '')::integer,
      coalesce((p_payload->>'Seleçao_relatorio')::boolean, false),
      coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
      'bubble'
    )
    on conflict (bubble_id) do update
      set projeto_id = coalesce(excluded.projeto_id, public.rm_fotos.projeto_id),
          celula_id = coalesce(excluded.celula_id, public.rm_fotos.celula_id),
          categoria_foto = coalesce(excluded.categoria_foto, public.rm_fotos.categoria_foto),
          titulo = coalesce(excluded.titulo, public.rm_fotos.titulo),
          descricao = coalesce(excluded.descricao, public.rm_fotos.descricao),
          legenda = coalesce(excluded.legenda, public.rm_fotos.legenda),
          foto_url = coalesce(excluded.foto_url, public.rm_fotos.foto_url),
          numero = coalesce(excluded.numero, public.rm_fotos.numero),
          selecao_relatorio = excluded.selecao_relatorio,
          bubble_modified_at = excluded.bubble_modified_at,
          sync_source = 'bubble'
    returning id into v_id;

  elsif p_entity_type = 'ProjetoRM' then
    update public.rm_projetos
    set status = coalesce(
          rm_private.resolve_option_key('status_rm', p_payload->>'status_option_status_rm')::public.rm_status_rm_enum,
          status
        ),
        status_pcp = coalesce(
          rm_private.resolve_option_key('status_pcp', p_payload->>'status_pcp1_option_status_pcp')::public.rm_status_pcp_enum,
          status_pcp
        ),
        escopo_abreviado = coalesce(p_payload->>'escopo_abreviado_text', escopo_abreviado),
        data_prevista_inicio = coalesce(nullif(p_payload->>'data_prevista_inicio_date', '')::timestamptz, data_prevista_inicio),
        data_prevista_final = coalesce(nullif(p_payload->>'data_prevista_final_date', '')::timestamptz, data_prevista_final),
        bubble_modified_at = coalesce(nullif(p_payload->>'Modified Date', '')::timestamptz, pg_catalog.clock_timestamp()),
        sync_source = 'bubble'
    where bubble_id = p_bubble_id
       or (p_payload ? 'supabase_id' and id = (p_payload->>'supabase_id')::uuid)
    returning id into v_id;
  end if;

  return jsonb_build_object(
    'entity_type', p_entity_type,
    'bubble_id', p_bubble_id,
    'updated_supabase_id', v_id,
    'applied_at', pg_catalog.clock_timestamp()
  );
end;
$$;

revoke all on function public.rm_apply_bubble_webhook_v1(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.rm_apply_bubble_webhook_v1(text, text, jsonb) to service_role;

-- ============================================================================
-- 4. SUPABASE STORAGE BUCKETS PARA MÍDIAS DO CHÃO DE FÁBRICA
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values
      ('rm-fotos', 'rm-fotos', true, 15728640, array['image/jpeg', 'image/png', 'image/webp']),
      ('rm-assinaturas', 'rm-assinaturas', true, 5242880, array['image/png', 'image/svg+xml']),
      ('rm-documentos', 'rm-documentos', false, 52428800, array['application/pdf'])
    on conflict (id) do nothing;
  end if;
end
$$;

-- ============================================================================
-- 5. SUPABASE REALTIME PUBLICATION PARA SINCRONIZAÇÃO INSTANTÂNEA NO APP MOBILE
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.rm_celulas_projeto,
      public.rm_registros_formulario,
      public.rm_respostas,
      public.rm_aprovacoes_etapas,
      public.rm_notificacoes;
  end if;
exception
  when duplicate_object then null;
end
$$;

commit;

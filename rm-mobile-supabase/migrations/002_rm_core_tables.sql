-- ============================================================================
-- MIGRATION 002: RM (Revisão de Motores) - Core & Operational Tables
-- Mapeia integralmente os Data Types de rmmi consumidos/gravados por rm_mobile
-- e pelos painéis desktop (rm_planejamento, proposta, dashboard_tv, identify).
-- ============================================================================

begin;

-- Função padrão para manter updated_at atualizado
create or replace function rm_private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.clock_timestamp();
  return new;
end;
$$;

-- ============================================================================
-- 1. CLIENTES & CONTATOS (custom.cliente, custom.contatos_clientes)
-- ============================================================================

create table if not exists public.rm_clientes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  codigo text,                       -- codigo_text
  nome text not null,                -- nome_text
  descricao text,                    -- descri_ao_text
  logo_icon_url text,                -- logo_image
  logo_lateral_url text,             -- logolateral_image
  background_url text,               -- background_image
  slug text,
  created_by_bubble_id text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_clientes_nome on public.rm_clientes (nome);

create table if not exists public.rm_contatos_clientes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  cliente_id uuid references public.rm_clientes(id) on delete cascade, -- cliente_custom_cliente
  nome text not null,                -- nome_text
  email text,                        -- email1_text
  telefone text,                     -- telefone_text
  foto_url text,                     -- foto_image
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_contatos_clientes_cliente on public.rm_contatos_clientes (cliente_id);

-- ============================================================================
-- 2. EQUIPES & USUÁRIOS (custom.equipes1, user, rm_private.user_credentials)
-- Separa dados operacionais de User das credenciais/PII sensíveis (CPF, TOTP,
-- palavra_chave), corrigindo a falha crítica de privacidade do Bubble.
-- ============================================================================

create table if not exists public.rm_equipes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  nome text not null,                -- nome_text
  descricao text,                    -- descricao_text
  cor text,                          -- cor_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create table if not exists public.rm_users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  bubble_id text unique,
  matricula text unique,             -- matricula3_text (chave de login de operador em identify)
  nome text not null,                -- nome_text
  email text,                        -- email (built-in Bubble)
  email_corporativo text,            -- email_corporativo_text
  cargo text,                        -- cargo_text
  telefone text,                     -- telefone2_text
  foto_url text,                     -- foto_image
  idioma text default 'por_br',      -- idioma_text
  empresa_id uuid references public.rm_clientes(id) on delete set null, -- empresa_custom_cliente
  equipe_id uuid references public.rm_equipes(id) on delete set null,   -- equipe_custom_equipes1
  perfil public.rm_perfil_usuario_enum default 'mobile',                -- perfil_option_tipo_de_usu_rio
  perfil_assinante public.rm_perfil_assinante_enum[] not null default '{}', -- perfil_assinante_list_option_perfil_assinante
  status public.rm_status_user_enum not null default 'ativo',           -- status_option_status
  criar_form boolean not null default false,                            -- criar_form1_boolean
  hora_entrada numeric(4,2) default 0,                                  -- horaentrada_number
  hora_saida numeric(4,2) default 24,                                   -- horasaida_number
  primeiro_login boolean not null default false,                        -- primeirologin_boolean
  tentativas_login integer not null default 0,                          -- tentativaslogin_number
  totp_auth boolean not null default false,                             -- totpauth_boolean
  ultimo_acesso timestamptz,                                            -- ultimo_acesso_date
  criado_por_id uuid references public.rm_users(id) on delete set null, -- criado_por_user
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_users_matricula on public.rm_users (matricula);
create index if not exists idx_rm_users_email on public.rm_users (lower(email));
create index if not exists idx_rm_users_equipe on public.rm_users (equipe_id);

-- Credenciais e PII restritas exclusivamente ao schema rm_private (inacessível via PostgREST direto)
create table if not exists rm_private.user_credentials (
  user_id uuid primary key references public.rm_users(id) on delete cascade,
  cpf text,                          -- cpf1_text
  palavra_chave_hash text,           -- bcrypt hash da palavra_chave_text do operador
  palavra_chave_legacy_plain text,   -- apenas durante transição ETL caso necessário revalidar no Bubble
  segredo_totp text,                 -- segredototp_text
  qrcode_totp_url text,              -- qrcodetotp_image
  data_mod_senha timestamptz,        -- datamodsenha_date
  n_char_pass integer default 8,     -- ncharpass_number
  updated_at timestamptz not null default clock_timestamp()
);

revoke all on table rm_private.user_credentials from public, anon, authenticated;

-- ============================================================================
-- 3. TABLETS, CÉLULAS E VÍNCULO DE OPERAÇÃO (custom.tablet, custom.celulas, custom.celula_user)
-- ============================================================================

create table if not exists public.rm_tablets (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  marca text,                        -- marca_text
  modelo text,                       -- modelo_text
  descricao text,                    -- descri_ao_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create table if not exists public.rm_celulas (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  codigo text,                       -- codigo_text
  nome text not null,                -- nome_text
  icone_url text,                    -- icone_image
  indice integer,                    -- indice_number
  ordem integer,                     -- ordem_number
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_celulas_ordem on public.rm_celulas (ordem, indice);

-- Vincula Conta do Tablet (usuario_id), Operador identificado (identidade_id), Tablet físico e Célula
create table if not exists public.rm_tablet_celula_users (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  celula_id uuid not null references public.rm_celulas(id) on delete cascade, -- celula_custom_celulas
  tablet_id uuid references public.rm_tablets(id) on delete set null,         -- tablet_custom_tablet
  usuario_id uuid references public.rm_users(id) on delete cascade,           -- usuario_user (Current User / conta do tablet)
  identidade_id uuid references public.rm_users(id) on delete set null,       -- identidade_user (Operador autenticado via matrícula)
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_tablet_celula_users_usuario on public.rm_tablet_celula_users (usuario_id, celula_id);
create index if not exists idx_rm_tablet_celula_users_identidade on public.rm_tablet_celula_users (identidade_id, celula_id);

-- ============================================================================
-- 4. ENGENHARIA DE PROCESSO: TIPOS DE EQUIPAMENTO E TEMPLATES DE CÉLULA
-- (custom.tipo_equipamento, custom.celula_tipo_equipamento, custom.cadastro_fotos)
-- ============================================================================

create table if not exists public.rm_tipos_equipamento (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  nome text not null,                -- nome_text
  sigla text,                        -- sigla_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create table if not exists public.rm_celula_tipos_equipamento (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  celula_id uuid not null references public.rm_celulas(id) on delete cascade,                  -- celula_custom_celulas
  tipo_equipamento_id uuid not null references public.rm_tipos_equipamento(id) on delete cascade, -- tipo_equipamento_custom_tipo_equipamento
  numero_fotos integer default 0,    -- numero_fotos_number
  visibilidade boolean default true, -- visibilidade_boolean
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl')),
  unique (celula_id, tipo_equipamento_id)
);

create table if not exists public.rm_cadastro_fotos (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  celula_nome text,                  -- celula_text
  numero integer,                    -- numero_number
  titulo text not null,              -- titulo_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

-- ============================================================================
-- 5. MOTOR DE FORMULÁRIOS DINÂMICOS
-- (custom.form1, custom.celula_form_tipo_equipamento, custom.questoes2,
--  custom.itens_questoes3, custom.numeracoes)
-- ============================================================================

create table if not exists public.rm_forms (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  titulo text not null,              -- titulo_text
  title text,                        -- title_text
  descricao text,                    -- descricao_text
  description text,                  -- description_text
  imagem_capa_url text,              -- imagem_capa_image
  tipo public.rm_tipo_formulario_enum, -- tipo_option_tipo_formulario
  ativo boolean not null default true, -- ativo_boolean
  usa_aprovacao boolean not null default true, -- usa_aprovacao_boolean
  unique_id_aux text,                -- unique_id_aux_text
  celulas_ids uuid[] not null default '{}', -- celula_list_custom_celulas
  equipes_ids uuid[] not null default '{}', -- equipes_list_custom_equipes1
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_forms_celulas on public.rm_forms using gin (celulas_ids);
create index if not exists idx_rm_forms_equipes on public.rm_forms using gin (equipes_ids);

create table if not exists public.rm_celula_form_tipos_equipamento (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  celula_tipo_equipamento_id uuid not null references public.rm_celula_tipos_equipamento(id) on delete cascade,
  form_id uuid not null references public.rm_forms(id) on delete cascade,
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl')),
  unique (celula_tipo_equipamento_id, form_id)
);

create table if not exists public.rm_questoes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  form_id uuid not null references public.rm_forms(id) on delete cascade, -- form_custom_form1
  indice integer not null default 1, -- indice_number
  enunciado text not null,           -- enunciado_text
  title text,                        -- title_text
  subtitulo text,                    -- subtitulo_text
  tag text,                          -- tag_text
  tipo public.rm_tipo_questao_enum not null, -- tipo_option_tipo_quest_o
  subtipo public.rm_subtipo_questao_enum,    -- subtipo_option_subtipos
  dimensoes public.rm_dimensao_enum,         -- dimensoes_option_dimensoes
  obrigatorio boolean not null default false,-- obrigatorio_boolean
  colaborador_filtro_perfil public.rm_perfil_usuario_enum, -- de custom.quest_o_colaborador_filtros
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_questoes_form_indice on public.rm_questoes (form_id, indice);

create table if not exists public.rm_itens_questoes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  form_id uuid references public.rm_forms(id) on delete cascade,          -- form_custom_form1
  questao_id uuid not null references public.rm_questoes(id) on delete cascade, -- questao_custom_questoes2
  indice integer not null default 1, -- indice_number
  descricao text not null,           -- descricao_text
  description text,                  -- description_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_itens_questoes_questao on public.rm_itens_questoes (questao_id, indice);

create table if not exists public.rm_numeracoes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  form_id uuid not null unique references public.rm_forms(id) on delete cascade, -- form_custom_form1
  ult_numero integer not null default 0, -- ult_numero_number
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

-- ============================================================================
-- 6. PROJETOS RM E EQUIPAMENTOS (custom.projeto_rm, custom.dados_equipamento)
-- ============================================================================

create table if not exists public.rm_projetos (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  numero text not null,              -- numero_text (Ex.: número da OS / Projeto RM)
  nome text,                         -- nome_text
  cliente_id uuid references public.rm_clientes(id) on delete set null, -- cliente_custom_cliente
  cliente_nome_exportacao text,      -- cliente_nome_exporta__o1_text
  contato text,                      -- contato_text
  proprietario text,                 -- proprietario_text
  nome_parceiro text,                -- nome_parceiro_text
  tipo_equipamento_id uuid references public.rm_tipos_equipamento(id) on delete set null, -- tipo_de_equipamento_custom_tipo_equipamento
  descricao_equipamento text,        -- descricao_equipamento_text
  escopo_abreviado text,             -- escopo_abreviado_text
  descricao_cod_escopo text,         -- descri_ao_cod__escopo_text
  descricao_status_relatorio text,   -- descri_ao__status_relat_rio__text
  centro_de_resultado text,          -- centro_de_resultado_text
  unidade_de_negocio_bu text,        -- unidade_de_negocio__bu__text
  nota_fiscal text,                  -- nota_fiscal_text
  arquivo_nota_fiscal_url text,      -- arquivo_nota_fiscal_file
  documento_proposta_url text,       -- documento_proposta_file
  qrcode_url text,                   -- qrcode_image
  bid_date text,                     -- bid_date_text
  prazo_execucao text,               -- prazo_execu_ao_text
  chegada_do_equipamento timestamptz,-- chegada_do_equipamento_date
  data_nota_entrada timestamptz,     -- data_nota_entrada_date
  data_inicio_delineamento timestamptz, -- data_inicio_delineamento_date
  data_final_delineamento timestamptz,  -- data_final_delineamento_date
  data_envio_para_comercial timestamptz,-- data_envio_para_comercial_date
  data_prevista_inicio timestamptz,  -- data_prevista_inicio_date
  data_prevista_final timestamptz,   -- data_prevista_final_date
  data_contratual timestamptz,       -- data_contratual_date
  data_renegociada timestamptz,      -- data_renegociada_date
  data_de_handover timestamptz,      -- data_de_handover_date
  data_real_de_entrega timestamptz,  -- data_real_de_entrega_date
  estimado boolean default false,    -- estimada_boolean
  new_offer boolean default false,   -- new_offer_boolean
  eventualidades text,               -- eventualidades_text
  replanejamento_motivo text,        -- replanejamento_motivo_text
  gestor_responsavel_id uuid references public.rm_users(id) on delete set null, -- gestor_responsavel_user
  status public.rm_status_rm_enum default 'peritagem', -- status_option_status_rm
  status_pcp public.rm_status_pcp_enum default 'aguardando_recebimento_equipamento', -- status_pcp1_option_status_pcp
  created_by_user_id uuid references public.rm_users(id) on delete set null,
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_projetos_numero on public.rm_projetos (numero);
create index if not exists idx_rm_projetos_cliente on public.rm_projetos (cliente_id);
create index if not exists idx_rm_projetos_status_pcp on public.rm_projetos (status_pcp);

create table if not exists public.rm_equipamentos (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid unique references public.rm_projetos(id) on delete cascade, -- projetorm_custom_projeto_rm
  tipo_equipamento_id uuid references public.rm_tipos_equipamento(id) on delete set null, -- tipo_equipamento_custom_tipo_equipamento
  placa_motor public.rm_placa_motor_enum,          -- placa_motor_option_placa_motor
  desmontar_para_orcar public.rm_sim_nao_enum,     -- desmontar_para_or_ar_option_sim_ou_nao
  ensaiar_antes_desmontar public.rm_sim_nao_enum,  -- ensaiar_antes_desmontar_option_sim_ou_nao
  teste_intermediario public.rm_sim_nao_enum,      -- teste_intermediario_option_sim_ou_nao
  embarcacao text,                   -- embarca__o_text
  fabricante text,                   -- fabricante_text
  modelo text,                       -- modelo_text
  numero_serie text,                 -- n__serie_text
  descricao text,                    -- descri_ao_text
  certificado text,                  -- certificado_text
  norma text,                        -- norma_text
  potencia text,                     -- potencia_text
  rotacao text,                      -- rota_ao_text
  tensao_estator text,               -- tensao_estator_text
  tipo_tensao text,                  -- tipo_tensao_text
  corrente_estator text,             -- corrente_estator_text
  corrente_partida text,             -- corrente_partida_text
  frequencia text,                   -- frequencia_text
  classe_isolamento text,            -- classe_isolamento_text
  grau_ip text,                      -- grau_ip_text
  forma text,                        -- forma_text
  regime text,                       -- regime_text
  peso text,                         -- peso_text
  ligacao text,                      -- liga_ao_text
  componentes text,                  -- componentes_text
  fp numeric,                        -- fp_number
  fs numeric,                        -- fs_number
  numero_cabos integer,              -- n__cabos_number
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

-- Adiciona FK reversa opcional em rm_projetos para manter paridade com equipamento_custom_dados_equipamento
alter table public.rm_projetos
  add column if not exists equipamento_id uuid references public.rm_equipamentos(id) on delete set null;

-- ============================================================================
-- 7. CÉLULAS DO PROJETO, APROVAÇÕES DE ETAPAS E FOTOS RM
-- (custom.celula_projeto, custom.aprovador_projeto, custom.foto_rm)
-- ============================================================================

create table if not exists public.rm_celulas_projeto (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid not null references public.rm_projetos(id) on delete cascade, -- projeto_custom_projeto_rm
  celula_id uuid not null references public.rm_celulas(id) on delete cascade,   -- celula_custom_celulas
  numero_projeto text,               -- numero_projeto_text
  cliente_nome_export text,          -- cliente_nome_export_text
  tipo_equipamento_nome_export text, -- tipo_equipamento_nome_export_text
  escopo_abreviado text,             -- escopo_abreviado_text
  status public.rm_status_cel_proj_enum not null default 'pendente',            -- status_option_status_cel_proj
  status_historico public.rm_status_cel_proj_enum[] not null default '{}',      -- status_historico_list_option_status_cel_proj
  bloqueada public.rm_sim_nao_enum default 'n_o',                               -- bloqueada_option_sim_ou_nao
  motivo_bloqueio text,              -- motivo_bloqueio_text
  motivo_atraso text,                -- motivo_atraso_text
  observacao text,                   -- observa_ao_text
  visibilidade boolean not null default false,                                  -- visibilidade1_boolean
  prioridade public.rm_prioridade_cel_enum,                                     -- prioridade_option_prioridade0
  indice integer,                    -- indice_number
  posicao integer,                   -- posi_ao_number
  ordem_status integer,              -- ordem_status_number
  horas_previstas numeric(10,2),     -- horas_previstas_number
  horas_realizadas numeric(10,2),    -- horas_realizadas_number
  data_inicio timestamptz,           -- data_inicio_date
  data_limite timestamptz,           -- data_limite_date
  data_fim_real timestamptz,         -- data_fim_real_date
  replanejada_em timestamptz,        -- replanejada_em_date
  replanejada_por_id uuid references public.rm_users(id) on delete set null,    -- replanejada_por_user
  responsavel_id uuid references public.rm_users(id) on delete set null,        -- responsavel_user
  modified_by_id uuid references public.rm_users(id) on delete set null,        -- modified_by_user
  criticidade text,                  -- criticidade_text
  depende_de text,                   -- depende_de_text
  equipe text,                       -- equipe_text
  oficina text,                      -- oficina_text
  peso_progresso text,               -- peso_progresso_text
  tipo_perde_lean text,              -- tipo_perde_lean_text
  forms_ids uuid[] not null default '{}', -- celula_form_tipo_equipamento_list_custom_form1
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl')),
  unique (projeto_id, celula_id)
);

create index if not exists idx_rm_celulas_projeto_celula_vis on public.rm_celulas_projeto (celula_id, visibilidade, status);
create index if not exists idx_rm_celulas_projeto_projeto on public.rm_celulas_projeto (projeto_id);

-- Aprovaçao_etapas (custom.aprovador_projeto)
-- Quando projeto_id IS NULL, atua como template para Celula_Tipo_Equipamento (clonado em projetocell_copy)
create table if not exists public.rm_aprovacoes_etapas (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid references public.rm_projetos(id) on delete cascade,          -- projetorm_custom_projeto_rm (NULL = template)
  celula_projeto_id uuid references public.rm_celulas_projeto(id) on delete cascade,
  celula_tipo_equipamento_id uuid references public.rm_celula_tipos_equipamento(id) on delete set null, -- celula_tipo_equipamento_custom_celula_tipo_equipamento
  celula_origem_id uuid not null references public.rm_celulas(id) on delete cascade, -- celula_custom_celulas
  celula_destino_id uuid references public.rm_celulas(id) on delete set null,   -- celula_destino_custom_celulas
  bloquear_avanco_sem_aprov boolean not null default false,                     -- bloquear_avanco_sem_aprov_boolean
  status public.rm_status_etapa_enum default 'nulo',                            -- status_option_statusetapa
  status_cel_proj public.rm_status_cel_proj_enum,                               -- status_cel_proj_option_status_cel_proj
  aprovador_id uuid references public.rm_users(id) on delete set null,          -- aprovador_user
  aprovado_por_id uuid references public.rm_users(id) on delete set null,       -- aprovado_por_user
  aprovadores_ids uuid[] not null default '{}',                                 -- aprovador_list_user
  aprovadores_retorno_ids uuid[] not null default '{}',                         -- aprovadores_retorno_list_user
  data_aprovacao timestamptz,                                                   -- data_aprova__o_date
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_aprovacoes_etapas_projeto_origem on public.rm_aprovacoes_etapas (projeto_id, celula_origem_id);
create index if not exists idx_rm_aprovacoes_etapas_template on public.rm_aprovacoes_etapas (celula_tipo_equipamento_id) where projeto_id is null;

-- Fotos RM (custom.foto_rm)
-- Quando projeto_id IS NULL, atua como template de foto obrigatória para Celula_Tipo_Equipamento
create table if not exists public.rm_fotos (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid references public.rm_projetos(id) on delete cascade,          -- projetorm_custom_projeto_rm (NULL = template)
  celula_id uuid references public.rm_celulas(id) on delete set null,           -- celula_custom_celulas
  celula_projeto_id uuid references public.rm_celulas_projeto(id) on delete set null,
  celula_tipo_equipamento_id uuid references public.rm_celula_tipos_equipamento(id) on delete set null, -- celula_tipo_equipamento1_custom_celula_tipo_equipamento
  categoria_foto public.rm_categoria_foto_enum,                                 -- categoria_foto_option_categoriafoto
  etapa public.rm_etapa_foto_enum,                                              -- etapa_option_etapa
  tipo_recebimento public.rm_tipo_foto_recebimento_enum,                        -- tipo_option_rmtipofoto
  identificador_foto_key text,                                                  -- tipo_fotos_option_tipofotos (164 opções em rm_option_sets)
  titulo text,                       -- titulo_text
  descricao text,                    -- descri__o_text
  legenda text,                      -- legenda_text
  tag text,                          -- tag_text
  foto_url text,                     -- foto1_image
  fotos_arquivos_urls text[] not null default '{}', -- fotos_list_file
  numero integer,                    -- numero_number
  numero_foto_complementar integer,  -- numero_foto_complementar_number
  lixeira boolean not null default false,           -- lixeira_boolean
  selecao_relatorio boolean not null default false, -- sele__o_relatorio_boolean
  modified_by_id uuid references public.rm_users(id) on delete set null,        -- modified_by_user
  created_by_user_id uuid references public.rm_users(id) on delete set null,
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_fotos_projeto_celula on public.rm_fotos (projeto_id, celula_id) where lixeira = false;
create index if not exists idx_rm_fotos_template on public.rm_fotos (celula_tipo_equipamento_id) where projeto_id is null;

-- ============================================================================
-- 8. EXECUÇÃO DE FORMULÁRIOS E RESPOSTAS
-- (custom.registro_formulario1, custom.respostas2, custom.respostas_temp)
-- ============================================================================

create table if not exists public.rm_registros_formulario (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  client_submission_id uuid unique,  -- Chave de idempotência gerada pelo SQLite offline no app mobile
  projeto_id uuid not null references public.rm_projetos(id) on delete cascade, -- projetorm_custom_projeto_rm
  numero_projeto_rm text,            -- numero_projetorm_text
  celula_id uuid references public.rm_celulas(id) on delete set null,           -- celula_custom_celulas
  form_id uuid not null references public.rm_forms(id) on delete restrict,      -- form_custom_form1
  empresa_id uuid references public.rm_clientes(id) on delete set null,         -- empresa_custom_cliente
  equipe_id uuid references public.rm_equipes(id) on delete set null,           -- equipe_custom_equipes1
  codigo integer,                    -- codigo_number
  codigo_text text,                  -- codigo_text_text (ex.: '0042')
  descricao text,                    -- descricao_text
  status public.rm_status_registro_enum not null default 'em_an_lise',          -- status_option_status_registro0
  preenchido boolean not null default true,                                     -- preenchido_boolean
  revisado boolean not null default false,                                      -- revisado_boolean
  parecer text,                      -- parecer_text
  tempo_de_vida integer default 0,   -- tempo_de_vida_number (segundos gastos no preenchimento)
  data_conclusao timestamptz,        -- data_conclusao_date
  data_revisao timestamptz,          -- data_revisao_date
  created_by_user_id uuid references public.rm_users(id) on delete set null,    -- created_by_user (conta do tablet)
  identidade_user_id uuid references public.rm_users(id) on delete set null,    -- identidade_user (operador real autenticado)
  responsavel_user_id uuid references public.rm_users(id) on delete set null,   -- responsavel_user
  avaliador_user_id uuid references public.rm_users(id) on delete set null,     -- avaliador_user
  user_revisao_id uuid references public.rm_users(id) on delete set null,       -- user_revis_o_user
  aprovadores_ids uuid[] not null default '{}',                                 -- aprovadores_list_user
  acao_log text[] not null default '{}',                                        -- acao_list_text
  historico_log text[] not null default '{}',                                   -- historico_list_text
  observacao_list text[] not null default '{}',                                 -- observacao_list_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_registros_formulario_projeto_celula
  on public.rm_registros_formulario (projeto_id, celula_id, status);
create index if not exists idx_rm_registros_formulario_form
  on public.rm_registros_formulario (form_id, codigo);

create table if not exists public.rm_respostas (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  registro_formulario_id uuid not null references public.rm_registros_formulario(id) on delete cascade, -- registro_formulario_custom_registro_formulario1
  questao_id uuid not null references public.rm_questoes(id) on delete restrict, -- questao_custom_questoes2
  id_registro_text text,             -- id_registro_text (ID textual do Registro_Formulario)
  titulo_form text,                  -- titulo_form_text
  indice integer,                    -- indice_number
  enunciado text,                    -- enunciado__text
  tag text,                          -- tag_text
  tipo public.rm_tipo_questao_enum,  -- tipo_option_tipo_quest_o
  dimensoes public.rm_dimensao_enum, -- dimens_es_option_dimensoes
  resposta text,                     -- resposta_text
  itens text[] not null default '{}',-- itens_list_text
  itens_questoes_ids uuid[] not null default '{}', -- itens_questoes_list_custom_itens_questoes3
  fotos_urls text[] not null default '{}',         -- foto_list_image
  assinatura_url text,               -- assinatura_image
  date_inicio timestamptz,           -- date_inicio_date
  data_fim timestamptz,              -- data_fim_date
  date_range tstzrange,              -- date_range_date_range
  hora timestamptz,                  -- hora_date
  revisar boolean not null default false, -- revisar_boolean (marcado pelo supervisor no desktop para correção no mobile)
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl')),
  -- Impede duplicação de respostas para a mesma questão no mesmo envio (corrige bug do novo_form_recursivo)
  unique (registro_formulario_id, questao_id)
);

create index if not exists idx_rm_respostas_registro_revisar
  on public.rm_respostas (registro_formulario_id, revisar);

-- Tabela opcional de rascunhos no servidor (com isolamento por operador_user_id, ausente no Bubble)
create table if not exists public.rm_respostas_temp (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid not null references public.rm_projetos(id) on delete cascade,
  form_id uuid not null references public.rm_forms(id) on delete cascade,
  questao_id uuid not null references public.rm_questoes(id) on delete cascade,
  operador_user_id uuid references public.rm_users(id) on delete cascade, -- Isolamento de sessão!
  registro_formulario_id uuid references public.rm_registros_formulario(id) on delete cascade,
  empresa_id uuid references public.rm_clientes(id) on delete set null,
  indice integer,
  enunciado text,
  tipo public.rm_tipo_questao_enum,
  dimensoes public.rm_dimensao_enum,
  resposta text,
  itens text[] not null default '{}',
  itens_questoes_ids uuid[] not null default '{}',
  fotos_urls text[] not null default '{}',
  assinatura_url text,
  date_inicio timestamptz,
  data_fim timestamptz,
  date_range tstzrange,
  hora timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl')),
  unique nulls not distinct (projeto_id, form_id, questao_id, operador_user_id)
);

-- ============================================================================
-- 9. AUDITORIA, LOGS DE APROVAÇÃO, COMENTÁRIOS E EVENTOS
-- (custom.log_aprocacao, custom.aprovacao, custom.comentarios,
--  custom.notificacoes, custom.eventosistema, custom.processos)
-- ============================================================================

create table if not exists public.rm_logs_aprovacao (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid not null references public.rm_projetos(id) on delete cascade, -- projeto_rm_custom_projeto_rm
  celula_id uuid references public.rm_celulas(id) on delete set null,           -- celula_custom_celulas
  aprovador_id uuid references public.rm_users(id) on delete set null,          -- aprovador_user
  status_aprovacao public.rm_status_etapa_enum not null,                        -- status_aprovacao_option_statusetapa
  data_aprovacao timestamptz not null default clock_timestamp(),                -- data_aprovacao_date
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_logs_aprovacao_projeto on public.rm_logs_aprovacao (projeto_id, data_aprovacao desc);

create table if not exists public.rm_aprovacoes_registro (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  registro_formulario_id uuid not null references public.rm_registros_formulario(id) on delete cascade,
  projeto_id uuid references public.rm_projetos(id) on delete cascade,
  celula_id uuid references public.rm_celulas(id) on delete set null,
  form_id uuid references public.rm_forms(id) on delete set null,
  aprovador_user_id uuid references public.rm_users(id) on delete set null,
  aprovador_nome text,
  parecer text,
  status public.rm_status_registro_enum,
  historico_status public.rm_status_registro_enum[] not null default '{}',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create table if not exists public.rm_comentarios (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  projeto_id uuid not null references public.rm_projetos(id) on delete cascade, -- projeto_custom_projeto_rm
  celula_id uuid references public.rm_celulas(id) on delete set null,           -- celula_custom_celulas
  cadastrado_por_id uuid references public.rm_users(id) on delete set null,     -- cadastrado_por1_user
  evento text not null,              -- evento_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_comentarios_projeto_celula on public.rm_comentarios (projeto_id, celula_id, created_at desc);

create table if not exists public.rm_notificacoes (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  user_id uuid references public.rm_users(id) on delete cascade,                -- user_user
  empresa_id uuid references public.rm_clientes(id) on delete set null,         -- empresa_custom_cliente
  registro_formulario_id uuid references public.rm_registros_formulario(id) on delete cascade, -- registro_formulario_custom_registro_formulario1
  origem public.rm_origem_notificacao_enum,                                     -- origem_option_origem_notifica__o0
  tipo text,                         -- tipo_text
  mensagem text,                     -- mensagem_text
  resposta text,                     -- resposta_text
  visto boolean not null default false, -- visto_boolean
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create index if not exists idx_rm_notificacoes_user_visto on public.rm_notificacoes (user_id, visto, created_at desc);

create table if not exists public.rm_eventos_sistema (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  user_id uuid references public.rm_users(id) on delete set null,               -- user_user
  tipo public.rm_tipo_evento_sistema_enum not null,                             -- tipo_option_tipo_evento_sistema
  ip text,                           -- ip_text
  local text,                        -- local_text
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

create table if not exists public.rm_eventos_api (
  id uuid primary key default gen_random_uuid(),
  bubble_id text unique,
  id_evento text,                    -- id_evento_text
  resposta text,                     -- resposta_text
  status public.rm_status_processo_enum default 'em_processamento',             -- status_option_statusprocesso
  slug text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  bubble_modified_at timestamptz,
  sync_source text not null default 'supabase' check (sync_source in ('supabase', 'bubble', 'etl'))
);

-- ============================================================================
-- 10. TRIGGERS DE UPDATED_AT EM TODAS AS TABELAS RM
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
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
    'rm_eventos_api'
  ]
  loop
    execute format('drop trigger if exists trg_touch_%I on public.%I;', t, t);
    execute format(
      'create trigger trg_touch_%I before update on public.%I for each row execute function rm_private.touch_updated_at();',
      t, t
    );
  end loop;
end
$$;

commit;

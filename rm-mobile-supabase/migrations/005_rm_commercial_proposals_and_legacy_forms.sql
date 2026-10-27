-- ============================================================================
-- MIGRATION 005: RM Completo — Módulo Comercial (Propostas/Precificação),
-- Relatórios/Documentos, Fichas Laboratoriais Estruturadas, RBAC (Elemento) e Suporte
-- Fonte: Dicionário Completo de Dados do Bubble (rmmi - 98 Data Types, 49 Option Sets)
-- ============================================================================

-- 1. OPTION SETS ADICIONAIS DO MÓDULO COMERCIAL, PROJETOS E SUPORTE
DO $$ BEGIN
  CREATE TYPE public.rm_classificacao_proposta_enum AS ENUM ('Firme', 'Estimada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.rm_status_proposta_enum AS ENUM (
    'Ag. Aprovação', 'Em Aprovação', 'Aprovada', 'Reprovada', 'Cancelada', 'Concluída'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.rm_incoterms_enum AS ENUM ('CIF', 'FOB', 'EXW');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.rm_linguagem_proposta_enum AS ENUM ('Português', 'Inglês', 'Espanhol');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.rm_prioridade_suporte_enum AS ENUM ('Baixa', 'Média', 'Alta', 'Crítica');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.rm_status_suporte_enum AS ENUM ('Aberto', 'Em Andamento', 'Concluído', 'Cancelado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- 2. RBAC GRANULAR POR ELEMENTO DE UI (Páginas: autorizacao, painel, proposta,
--    rm_planejamento, rm_gestao, settings_rm, project_rm, projeto)
--    Bubble Data Type: Elemento (custom.elemento)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.rm_elementos_permissao (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  codigo TEXT NOT NULL UNIQUE,                  -- codigo_text (Ex: PN001..PN007, PL001..PL028, GT001..GT025, CF001..CF011, CM001..CM011, DJ001..DJ013)
  nome TEXT NOT NULL,                           -- nome_text
  aplicacao TEXT,                               -- aplicacao_option_aplicacao ('RM', 'NR12', 'Geral')
  pagina TEXT,                                  -- pagina_option_paginas_rm ('Painel', 'Planejamento', 'Gestão', 'Configurações', 'Comercial')
  tipo TEXT,                                    -- tipo_option_tipo_elemento ('Botão', 'Menu', 'Aba', 'Ícone', 'Seção')
  usuarios_permitidos UUID[] DEFAULT '{}',      -- permissoes_list_user (Array de rm_users.id com permissão explícita)
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rm_elementos_codigo ON public.rm_elementos_permissao(codigo);
CREATE INDEX IF NOT EXISTS idx_rm_elementos_usuarios ON public.rm_elementos_permissao USING GIN(usuarios_permitidos);

-- Função helper para checar permissão de elemento no Backend/RLS/Frontend:
CREATE OR REPLACE FUNCTION public.rm_user_has_element_permission(
  p_user_id UUID,
  p_codigo_elemento TEXT
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.rm_elementos_permissao e
    WHERE e.codigo = p_codigo_elemento
      AND p_user_id = ANY(e.usuarios_permitidos)
  ) OR EXISTS (
    SELECT 1
    FROM public.rm_users u
    WHERE u.id = p_user_id
      AND u.perfil = 'administrador' -- chave canônica do enum definido em 001
  );
$$;

-- ============================================================================
-- 3. MÓDULO COMERCIAL, PRECIFICAÇÃO E PROPOSTAS (Páginas: proposta, rm_planejamento)
-- ============================================================================

-- 3.1 VendedorCliente (custom.vendedorcliente)
CREATE TABLE IF NOT EXISTS public.rm_vendedores_clientes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  nome TEXT NOT NULL,                           -- nome_text
  email TEXT,                                   -- email_text
  telefone TEXT,                                -- telefone_text
  cliente_id UUID REFERENCES public.rm_clientes(id) ON DELETE SET NULL,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.2 Escopo RM (custom.escopo_rm)
CREATE TABLE IF NOT EXISTS public.rm_escopo_rm (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  titulo TEXT NOT NULL,                         -- titulo_text
  descricao TEXT,                               -- descricao_text
  descricao_en TEXT,                            -- descricao_ingles_text
  descricao_es TEXT,                            -- descricao_espanhol_text
  tipo_escopo TEXT,                             -- tipo_escopo_option_escopo_proposta ('Básico', 'Complementar', 'Ex', etc.)
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.3 Material (custom.material) & Peça RM (custom.peca_rm)
CREATE TABLE IF NOT EXISTS public.rm_materiais (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  nome TEXT NOT NULL,                           -- nome_text
  codigo TEXT,                                  -- codigo_text
  unidade TEXT,                                 -- unidade_text
  valor_unitario NUMERIC(14,2) DEFAULT 0,       -- valor_number
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rm_pecas_rm (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  nome TEXT NOT NULL,                           -- nome_text
  descricao TEXT,                               -- descricao_text
  quantidade NUMERIC(12,2) DEFAULT 1,           -- quantidade_number
  valor_unitario NUMERIC(14,2) DEFAULT 0,       -- valor_unitario_number
  valor_total NUMERIC(14,2) DEFAULT 0,          -- valor_total_number
  material_id UUID REFERENCES public.rm_materiais(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.4 Template_Proposta (custom.template_proposta)
CREATE TABLE IF NOT EXISTS public.rm_templates_proposta (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  nome TEXT NOT NULL,                           -- nome_text (ex: 'proposta_comercial_ex_manutençao_basica_pt-br')
  template_folder TEXT NOT NULL,                -- pasta no serviço Render PDF Generator
  idioma public.rm_linguagem_proposta_enum DEFAULT 'Português',
  tipo_manutencao TEXT,                         -- Básica / Geral / Ex / Padrão
  orientacao TEXT DEFAULT 'portrait',
  margin_top TEXT DEFAULT '23mm',
  margin_bottom TEXT DEFAULT '18.5mm',
  margin_left TEXT DEFAULT '0',
  margin_right TEXT DEFAULT '0',
  zoom TEXT DEFAULT '1.0',
  json_schema_default JSONB DEFAULT '{}'::jsonb,
  ativo BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.5 Precificaçao Orçamentaria (custom.precifica_ao_or_amentaria - 26 campos)
CREATE TABLE IF NOT EXISTS public.rm_precificacao_orcamentaria (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  carcaca TEXT,                                 -- carcaca_text
  polaridade TEXT,                              -- polaridade_text
  potencia_cv_texto TEXT,                       -- potencia_cv_text
  potencia_kw_texto TEXT,                       -- potencia_kw_text
  potencia_cv NUMERIC(12,2),                    -- _potencia_cv_number (convertido pelo workflow Alimentar_Potencia_PO)
  potencia_kw NUMERIC(12,2),                    -- potencia_kw_number
  tensao TEXT,                                  -- tensao_text
  tipo_equipamento TEXT,                        -- tipo_equipamento_option_tipo_equipamento
  tipo_manutencao TEXT,                         -- tipo_manutencao_text
  valor_base_basica NUMERIC(14,2),              -- valor_manutencao_basica_number
  valor_base_geral NUMERIC(14,2),               -- valor_manutencao_geral_number
  valor_rebobinamento_estator NUMERIC(14,2),    -- valor_rebobinamento_estator_number
  valor_rebobinamento_rotor NUMERIC(14,2),      -- valor_rebobinamento_rotor_number
  horas_estimadas NUMERIC(10,2),                -- horas_estimadas_number
  custo_hora NUMERIC(12,2),                     -- custo_hora_number
  fator_ex NUMERIC(8,4) DEFAULT 1.0,            -- fator_ex_number
  metadados_extras JSONB DEFAULT '{}'::jsonb,   -- demais coeficientes de precificação
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.6 Proposta_controle (custom.proposta_controle - 46 campos)
CREATE TABLE IF NOT EXISTS public.rm_propostas_controle (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  codigo_proposta TEXT,                         -- codigo_proposta_text
  numero_proposta INTEGER,                      -- numero_proposta_number
  revisao INTEGER DEFAULT 0,                    -- revisao_number
  classificacao public.rm_classificacao_proposta_enum,
  status public.rm_status_proposta_enum DEFAULT 'Ag. Aprovação',
  projeto_id UUID REFERENCES public.rm_projetos(id) ON DELETE SET NULL,
  cliente_id UUID REFERENCES public.rm_clientes(id) ON DELETE SET NULL,
  vendedor_id UUID REFERENCES public.rm_vendedores_clientes(id) ON DELETE SET NULL,
  equipamento_id UUID REFERENCES public.rm_equipamentos(id) ON DELETE SET NULL,
  carcaca TEXT,
  polaridade TEXT,
  potencia_cv_texto TEXT,
  potencia_kw_texto TEXT,
  potencia_cv NUMERIC(12,2),                    -- alimentado por alimentar_Potencia_PC
  potencia_kw NUMERIC(12,2),                    -- alimentado por alimentar_Potencia_PC
  tensao TEXT,
  incoterms public.rm_incoterms_enum,
  prazo_entrega_dias INTEGER,
  condicao_pagamento TEXT,
  validade_proposta_dias INTEGER DEFAULT 15,
  valor_total NUMERIC(14,2) DEFAULT 0,
  desconto_percentual NUMERIC(6,2) DEFAULT 0,
  valor_final NUMERIC(14,2) DEFAULT 0,
  observacoes TEXT,
  aprovado_por UUID REFERENCES public.rm_users(id),
  data_aprovacao TIMESTAMPTZ,
  motivo_reprovacao TEXT,
  pdf_url_pt TEXT,
  pdf_url_en TEXT,
  pdf_url_es TEXT,
  dados_calculo JSONB DEFAULT '{}'::jsonb,      -- preserva todos os 46 campos orçamentários
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.7 Proposta_motor_Budgetaria (custom.proposta - 12 campos)
CREATE TABLE IF NOT EXISTS public.rm_propostas_budgetarias (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  proposta_controle_id UUID REFERENCES public.rm_propostas_controle(id) ON DELETE CASCADE,
  projeto_id UUID REFERENCES public.rm_projetos(id) ON DELETE SET NULL,
  cliente_id UUID REFERENCES public.rm_clientes(id) ON DELETE SET NULL,
  titulo TEXT,
  idioma public.rm_linguagem_proposta_enum DEFAULT 'Português',
  template_folder TEXT,
  pdf_file_name TEXT,
  pdf_url TEXT,
  valor1_number NUMERIC(14,2),                  -- convertido por Transferencia_valor
  valor_texto_legado TEXT,
  json_tags_enviado JSONB,                      -- payload enviado ao Render PDF_Proposta
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 4. DOCUMENTOS, TEMPLATES WORD/GOOGLE DOCS E RELATÓRIOS COMPILADOS
--    (Páginas: project_rm, projeto, rm_gestao, visualizar-documento)
-- ============================================================================

-- 4.1 Templates (custom.templates - Templates .docx integrados ao Google Docs via n8n)
CREATE TABLE IF NOT EXISTS public.rm_templates_word (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  nome TEXT NOT NULL,                           -- nome_text
  descricao TEXT,                               -- descricao_text
  arquivo_docx_url TEXT,                        -- arquivo_file (URL do .docx original)
  google_doc_id TEXT,                           -- google_id_text (retornado pelo n8n Criar_template cogtC)
  form_id UUID REFERENCES public.rm_forms(id) ON DELETE SET NULL,
  tipo_equipamento TEXT,
  ativo BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4.2 Documentos (custom.documentos - Relatórios gerados e PDFs compilados no S3)
CREATE TABLE IF NOT EXISTS public.rm_documentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  projeto_id UUID NOT NULL REFERENCES public.rm_projetos(id) ON DELETE CASCADE,
  registro_formulario_id UUID REFERENCES public.rm_registros_formulario(id) ON DELETE SET NULL,
  template_id UUID REFERENCES public.rm_templates_word(id) ON DELETE SET NULL,
  nome TEXT NOT NULL,                           -- nome_text
  tipo_documento TEXT,                          -- 'Relatório Formulário', 'Relatório Fotográfico', 'Compilado', 'Anexo S3'
  arquivo_url TEXT NOT NULL,                    -- arquivo_file / S3 URL retornada pelo n8n
  s3_key TEXT,
  ordem_compilacao INTEGER DEFAULT 0,
  incluir_no_compilado BOOLEAN DEFAULT false,
  documentos_origem_ids UUID[] DEFAULT '{}',    -- IDs dos documentos mesclados em Gerar_relatorio_compilado
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rm_documentos_projeto ON public.rm_documentos(projeto_id);

-- 4.3 Docs (custom.docs - Anexos gerais do projeto na página `projeto` e `visualizar-documento`)
CREATE TABLE IF NOT EXISTS public.rm_docs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  projeto_id UUID NOT NULL REFERENCES public.rm_projetos(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,                           -- nome_text
  descricao TEXT,                               -- descricao_text
  arquivo_url TEXT NOT NULL,                    -- arquivo_file
  tipo_arquivo TEXT,
  visivel_cliente BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5. FICHAS LABORATORIAIS ESTRUTURADAS (Página `formulario` ID coAOy0)
--    21 Data Types estáticos de Ordem de Serviço, Desmontagem e Testes Elétricos
-- ============================================================================

-- 5.1 Ordem Serviço (custom.ordem_servico) & Componentes (custom.componentes)
CREATE TABLE IF NOT EXISTS public.rm_ordens_servico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  numero_os TEXT NOT NULL,                      -- numero_os_text
  projeto_id UUID REFERENCES public.rm_projetos(id) ON DELETE SET NULL,
  cliente_id UUID REFERENCES public.rm_clientes(id) ON DELETE SET NULL,
  equipamento_id UUID REFERENCES public.rm_equipamentos(id) ON DELETE SET NULL,
  status TEXT,
  data_abertura TIMESTAMPTZ DEFAULT now(),
  data_fechamento TIMESTAMPTZ,
  observacoes TEXT,
  dados_os JSONB DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rm_componentes_os (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  ordem_servico_id UUID REFERENCES public.rm_ordens_servico(id) ON DELETE CASCADE,
  nome TEXT NOT NULL,
  estado_recebimento TEXT,
  acao_recomendada TEXT,
  fotos_urls TEXT[] DEFAULT '{}',
  dados_componente JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5.2 Ficha Delineamento & Itens Ficha Delineamento
CREATE TABLE IF NOT EXISTS public.rm_fichas_delineamento (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  ordem_servico_id UUID REFERENCES public.rm_ordens_servico(id) ON DELETE CASCADE,
  projeto_id UUID REFERENCES public.rm_projetos(id) ON DELETE SET NULL,
  responsavel_id UUID REFERENCES public.rm_users(id),
  observacoes TEXT,
  dados_ficha JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rm_itens_ficha_delineamento (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  ficha_delineamento_id UUID REFERENCES public.rm_fichas_delineamento(id) ON DELETE CASCADE,
  descricao TEXT NOT NULL,
  quantidade NUMERIC(12,2) DEFAULT 1,
  unidade TEXT,
  status_item TEXT,
  observacao TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5.3 Ficha Desmontagem (custom.ficha_desmontagem - 46 campos dimensionais/mecânicos)
CREATE TABLE IF NOT EXISTS public.rm_fichas_desmontagem (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  ordem_servico_id UUID REFERENCES public.rm_ordens_servico(id) ON DELETE SET NULL,
  projeto_id UUID REFERENCES public.rm_projetos(id) ON DELETE SET NULL,
  equipamento_id UUID REFERENCES public.rm_equipamentos(id) ON DELETE SET NULL,
  rolamento_la TEXT,
  rolamento_loa TEXT,
  medida_colo_eixo_la NUMERIC(10,4),
  medida_colo_eixo_loa NUMERIC(10,4),
  medida_alojamento_tampa_la NUMERIC(10,4),
  medida_alojamento_tampa_loa NUMERIC(10,4),
  folga_axial NUMERIC(10,4),
  folga_radial NUMERIC(10,4),
  batimento_eixo NUMERIC(10,4),
  estado_estator TEXT,
  estado_rotor TEXT,
  estado_caixa_ligacao TEXT,
  estado_tampas TEXT,
  estado_ventilador TEXT,
  observacoes TEXT,
  medicoes_completas JSONB NOT NULL DEFAULT '{}'::jsonb, -- armazena os 46 campos de Ficha Desmontagem
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5.4 Ensaios Elétricos Estruturados (Teste Eletrico Inicial, Teste Eletrico Final e Sub-ensaios)
CREATE TABLE IF NOT EXISTS public.rm_ensaios_eletricos_laboratorio (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  tipo_ensaio TEXT NOT NULL CHECK (tipo_ensaio IN ('INICIAL', 'FINAL')),
  ordem_servico_id UUID REFERENCES public.rm_ordens_servico(id) ON DELETE SET NULL,
  projeto_id UUID REFERENCES public.rm_projetos(id) ON DELETE SET NULL,
  equipamento_id UUID REFERENCES public.rm_equipamentos(id) ON DELETE SET NULL,
  -- Sub-documentos normalizados equivalentes às tabelas satélite do Bubble:
  resistencia_isolamento JSONB DEFAULT '{}'::jsonb,   -- custom.resistencia_isolamento (23 campos: 30s, 1m, 10m, IA, IP, tensão ensaio)
  resistencia_ohmica JSONB DEFAULT '{}'::jsonb,       -- custom.resistencia_ohmica (13 campos: UV, VW, WU, desequilíbrio %, temp ambiente)
  resistencia_aquecimento JSONB DEFAULT '{}'::jsonb,  -- custom.resistencia_aquecimento (9 campos)
  teste_tensao_aplicada JSONB DEFAULT '{}'::jsonb,    -- custom.teste_tensao_aplicada (6 campos: Hipot kV, corrente fuga mA)
  teste_surto_eletrico JSONB DEFAULT '{}'::jsonb,     -- custom.teste_surto_eletrico (9 campos: Surge Test EAR %)
  teste_dinamico_rotativo JSONB DEFAULT '{}'::jsonb,  -- custom.teste_dinamico_rotativo (25 campos: vibração LA/LOA H/V/A, corrente vazio)
  elevacao_temperatura JSONB DEFAULT '{}'::jsonb,     -- custom.elevacao_temperatura (25 campos: curva térmica temporal)
  sistema_freio JSONB DEFAULT '{}'::jsonb,            -- custom.sistema_freio (7 campos)
  inspecao_eletrica JSONB DEFAULT '{}'::jsonb,        -- custom.inspecao (9 campos)
  compras_teste JSONB DEFAULT '{}'::jsonb,            -- custom.compras (2 campos)
  termino_teste JSONB DEFAULT '{}'::jsonb,            -- custom.termino (8 campos: conclusão, laudo, responsável)
  assinaturas JSONB DEFAULT '[]'::jsonb,              -- custom.assinatura (4 campos)
  created_by UUID REFERENCES public.rm_users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 6. SUPORTE INTERNO (Página `miit` / Solicitações de Suporte), LOGS E DISPOSITIVOS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.rm_solicitacoes_suporte (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  codigo TEXT,                                  -- codigo_text
  titulo TEXT NOT NULL,                         -- titulo_text
  descricao TEXT,                               -- descricao_text
  modulo TEXT,                                  -- modulo_option_modulo_suporte
  prioridade public.rm_prioridade_suporte_enum DEFAULT 'Média',
  status public.rm_status_suporte_enum DEFAULT 'Aberto',
  anexos_urls TEXT[] DEFAULT '{}',
  solicitante_id UUID REFERENCES public.rm_users(id),
  responsavel_id UUID REFERENCES public.rm_users(id),
  data_conclusao TIMESTAMPTZ,
  resposta_tecnica TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rm_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_unique_id TEXT UNIQUE,
  user_id UUID REFERENCES public.rm_users(id) ON DELETE CASCADE,
  device_token TEXT,
  platform TEXT,                                -- 'ios', 'android', 'web'
  app_version TEXT,
  last_seen_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Habilitar RLS nas novas tabelas
ALTER TABLE public.rm_elementos_permissao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_vendedores_clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_escopo_rm ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_materiais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_pecas_rm ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_templates_proposta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_precificacao_orcamentaria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_propostas_controle ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_propostas_budgetarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_templates_word ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_ordens_servico ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_componentes_os ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_fichas_delineamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_itens_ficha_delineamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_fichas_desmontagem ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_ensaios_eletricos_laboratorio ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_solicitacoes_suporte ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rm_devices ENABLE ROW LEVEL SECURITY;

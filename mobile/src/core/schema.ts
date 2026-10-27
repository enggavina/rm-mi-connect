/**
 * ============================================================================
 * SCHEMA SQLITE LOCAL (OFFLINE-FIRST) PARA REACT NATIVE / EXPO (expo-sqlite)
 * ============================================================================
 * Elimina a dependência da tabela `Respostas Temp` no servidor durante a
 * inspeção de campo: cada resposta e foto é salva instantaneamente no SQLite
 * do tablet (isolada por `operador_id`) e submetida em lote atômico via RPC
 * `rm_submit_form_inspection_v1` com `client_submission_id` idempotente.
 */

export const RM_MOBILE_SQLITE_DDL = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- 1. Sessão ativa do Operador no Tablet (Substitui Current page's User do Bubble)
CREATE TABLE IF NOT EXISTS local_operator_session (
  operador_id TEXT PRIMARY KEY,
  matricula TEXT NOT NULL,
  nome TEXT NOT NULL,
  cargo TEXT,
  perfil TEXT NOT NULL,
  perfil_assinante_json TEXT NOT NULL DEFAULT '[]',
  equipe_id TEXT,
  celula_ativa_id TEXT,
  celulas_vinculadas_json TEXT NOT NULL DEFAULT '[]',
  authenticated_at TEXT NOT NULL
);

-- 2. Cache offline de Catálogos e Projetos da Célula
CREATE TABLE IF NOT EXISTS local_projetos_cache (
  id TEXT PRIMARY KEY,
  numero TEXT NOT NULL,
  nome TEXT,
  cliente_nome TEXT,
  escopo_abreviado TEXT,
  status TEXT,
  status_pcp TEXT,
  equipamento_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS local_celulas_projeto_cache (
  id TEXT PRIMARY KEY,
  projeto_id TEXT NOT NULL,
  celula_id TEXT NOT NULL,
  numero_projeto TEXT,
  status TEXT NOT NULL,
  visibilidade INTEGER NOT NULL DEFAULT 1,
  bloqueada TEXT DEFAULT 'n_o',
  motivo_bloqueio TEXT,
  prioridade TEXT,
  data_inicio TEXT,
  data_limite TEXT,
  forms_ids_json TEXT NOT NULL DEFAULT '[]',
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS local_forms_cache (
  id TEXT PRIMARY KEY,
  titulo TEXT NOT NULL,
  descricao TEXT,
  tipo TEXT,
  questoes_json TEXT NOT NULL DEFAULT '[]',
  updated_at TEXT NOT NULL
);

-- Slots de fotos obrigatórias pré-cadastradas pelo Desktop (rm_gestao / rm_planejamento)
-- com título preenchido e aguardando captura pelo operador no tablet
CREATE TABLE IF NOT EXISTS local_fotos_slots_cache (
  id TEXT PRIMARY KEY,
  bubble_id TEXT,
  projeto_id TEXT NOT NULL,
  celula_id TEXT NOT NULL,
  celula_projeto_id TEXT,
  categoria_foto TEXT NOT NULL DEFAULT 'obrigat_ria',
  titulo TEXT NOT NULL,
  descricao TEXT,
  legenda TEXT,
  numero INTEGER,
  foto_url TEXT,
  local_foto_uri TEXT,
  updated_at TEXT NOT NULL
);

-- 3. Rascunhos de Inspeção 100% Locais (Substitui Respostas Temp do Bubble sem colisão!)
CREATE TABLE IF NOT EXISTS local_form_drafts (
  draft_id TEXT PRIMARY KEY,
  client_submission_id TEXT NOT NULL UNIQUE,
  projeto_id TEXT NOT NULL,
  celula_id TEXT NOT NULL,
  form_id TEXT NOT NULL,
  operador_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  elapsed_seconds INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'ready_to_sync', 'synced')),
  UNIQUE (projeto_id, celula_id, form_id, operador_id)
);

CREATE TABLE IF NOT EXISTS local_respostas_draft (
  id TEXT PRIMARY KEY,
  draft_id TEXT NOT NULL REFERENCES local_form_drafts(draft_id) ON DELETE CASCADE,
  questao_id TEXT NOT NULL,
  indice INTEGER NOT NULL,
  enunciado TEXT NOT NULL,
  tipo TEXT NOT NULL,
  dimensoes TEXT,
  resposta TEXT,
  itens_json TEXT NOT NULL DEFAULT '[]',
  itens_questoes_ids_json TEXT NOT NULL DEFAULT '[]',
  local_fotos_uris_json TEXT NOT NULL DEFAULT '[]',
  uploaded_fotos_urls_json TEXT NOT NULL DEFAULT '[]',
  local_assinatura_uri TEXT,
  uploaded_assinatura_url TEXT,
  date_inicio TEXT,
  data_fim TEXT,
  hora TEXT,
  is_na INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  UNIQUE (draft_id, questao_id)
);

-- 4. Fila de Upload de Mídias (Fotos de Recebimento, Fotos de Célula e Assinaturas)
CREATE TABLE IF NOT EXISTS local_media_upload_queue (
  id TEXT PRIMARY KEY,
  bucket TEXT NOT NULL CHECK (bucket IN ('rm-fotos', 'rm-assinaturas')),
  local_uri TEXT NOT NULL,
  remote_path TEXT NOT NULL,
  public_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'uploading', 'uploaded', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL
);

-- 5. Fila Offline de Mutação RPC para o Supabase
CREATE TABLE IF NOT EXISTS local_rpc_outbox (
  id TEXT PRIMARY KEY,
  rpc_name TEXT NOT NULL CHECK (
    rpc_name IN (
      'rm_submit_recebimento_v1',
      'rm_submit_form_inspection_v1',
      'rm_submit_form_revision_v1',
      'rm_transition_stage_approval_v1',
      'rm_record_cell_photo_v1'
    )
  ),
  params_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'syncing', 'completed', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL
);
`;

/**
 * Regra canônica do botão "Preencher N/A" (substitui backend workflow `Preenche NA` cooNJ
 * diretamente no SQLite local, em <5ms e sem chamadas de rede).
 */
export function buildDefaultNaAnswer(questao: {
  id: string;
  indice: number;
  enunciado: string;
  tipo: string;
  dimensoes?: string | null;
}) {
  const nowIso = new Date().toISOString();
  switch (questao.tipo) {
    case 'texto_curto':
    case 'texto_longo':
    case 'escolha__nica':
    case 'lista_suspensa':
    case 'colaborador':
    case 'cliente':
      return {
        questao_id: questao.id,
        indice: questao.indice,
        enunciado: questao.enunciado,
        tipo: questao.tipo,
        dimensoes: questao.dimensoes ?? null,
        resposta: 'N/A',
        itens_json: '[]',
        is_na: 1,
        updated_at: nowIso,
      };
    case 'numero':
      return {
        questao_id: questao.id,
        indice: questao.indice,
        enunciado: questao.enunciado,
        tipo: questao.tipo,
        dimensoes: questao.dimensoes ?? null,
        resposta: '0,000',
        itens_json: '[]',
        is_na: 1,
        updated_at: nowIso,
      };
    case 'data':
    case 'hora':
      return {
        questao_id: questao.id,
        indice: questao.indice,
        enunciado: questao.enunciado,
        tipo: questao.tipo,
        dimensoes: questao.dimensoes ?? null,
        resposta: null,
        date_inicio: '1900-01-01T00:00:00.000Z',
        data_fim: '1900-01-01T00:00:00.000Z',
        hora: '1900-01-01T00:00:00.000Z',
        itens_json: '[]',
        is_na: 1,
        updated_at: nowIso,
      };
    default:
      return {
        questao_id: questao.id,
        indice: questao.indice,
        enunciado: questao.enunciado,
        tipo: questao.tipo,
        dimensoes: questao.dimensoes ?? null,
        resposta: null,
        itens_json: '[]',
        is_na: 1,
        updated_at: nowIso,
      };
  }
}

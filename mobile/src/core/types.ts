export type Row = Record<string, any> & { id: string };
export const TABLES = [
  'rm_clientes', 'rm_users', 'rm_tipos_equipamento', 'rm_celulas',
  'rm_tablet_celula_users', 'rm_celula_tipos_equipamento',
  'rm_celula_form_tipos_equipamento', 'rm_forms', 'rm_questoes',
  'rm_itens_questoes', 'rm_projetos', 'rm_equipamentos',
  'rm_celulas_projeto', 'rm_fotos', 'rm_registros_formulario',
  'rm_respostas', 'rm_aprovacoes_etapas',
] as const;
export type CatalogTable = typeof TABLES[number];
export const RPC_NAMES = [
  'rm_submit_recebimento_v1', 'rm_submit_form_inspection_v1',
  'rm_submit_form_revision_v1', 'rm_transition_stage_approval_v1',
  'rm_record_cell_photo_v1',
] as const;
export type RpcName = typeof RPC_NAMES[number];
export type Bucket = 'rm-fotos' | 'rm-assinaturas';
export interface Operator {
  operador_id: string; matricula: string; nome: string; perfil: string;
  cargo?: string; perfil_assinante: string[]; equipe_id?: string;
  celulas_vinculadas: {celula_id: string; nome: string; codigo?: string}[];
  authenticated_at: string; token_expires_at?: string;
  cell_access_policy_version?: number;
}
export interface Answer {
  questao_id: string; indice: number; enunciado: string; tipo: string;
  dimensoes?: string | null; tag?: string | null; resposta?: string | null;
  itens?: string[]; itens_questoes_ids?: string[]; fotos_urls?: string[];
  assinatura_url?: string | null; date_inicio?: string | null;
  data_fim?: string | null; hora?: string | null; is_na?: boolean;
  resposta_id?: string; revisar?: boolean;
}
export interface DraftContext {
  projeto_id: string; celula_id: string; form_id: string;
  registro_formulario_id?: string;
}
export interface Draft extends DraftContext {
  draft_id: string; client_submission_id: string; operador_id: string;
  started_at: string; status: 'in_progress' | 'ready_to_sync' | 'synced';
  answers: Answer[];
}
export interface AppSnapshot {
  ready: boolean; configured: boolean; online: boolean; syncing: boolean;
  sessionUserId: string | null; operator: Operator | null;
  pendingMedia: number; pendingMutations: number;
  lastSync: string | null; error: string | null; revision: number;
}
export interface MediaRow {
  id: string; bucket: Bucket; local_uri: string; remote_path: string;
  public_url: string | null; status: string; attempts: number;
  created_at: string; next_retry_at: number;
}
export interface OutboxRow {
  id: string; rpc_name: RpcName; params_json: string; status: string;
  attempts: number; created_at: string; next_retry_at: number;
  actor_id: string; token_key: string; draft_id: string | null;
  last_error?: string; result_json?: string;
}

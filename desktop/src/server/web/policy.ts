import { z } from 'zod';

export const uuid = z.string().uuid();
const timestamp = z.string().datetime({ offset: true });
const nullableText = (max = 1000) => z.string().max(max).nullable().optional();
const nullableId = uuid.nullable().optional();
const nullableDate = timestamp.nullable().optional();
const option = z.string().min(1).max(100).regex(/^[a-z0-9_]+$/).nullable().optional();
const version = timestamp.nullable();

export const saveProjectSchema = z.object({
  submissionId: uuid, id: uuid, expected_updated_at: version,
  changes: z.object({
    numero: nullableText(100), nome: nullableText(500), cliente_id: nullableId, tipo_equipamento_id: nullableId,
    descricao_equipamento: nullableText(10_000), contato: nullableText(500), proprietario: nullableText(500),
    escopo_abreviado: nullableText(5000), eventualidades: nullableText(10_000), gestor_responsavel_id: nullableId,
    status: option, status_pcp: option, chegada_do_equipamento: nullableDate, data_prevista_inicio: nullableDate,
    data_prevista_final: nullableDate, data_contratual: nullableDate, data_renegociada: nullableDate,
    replanejamento_motivo: nullableText(5000),
  }).strict().refine(value => Object.keys(value).length > 0, 'Informe uma alteração.'),
}).strict();

export const planCellSchema = z.object({
  submissionId: uuid, projeto_id: uuid, celula_id: uuid, expected_updated_at: version,
  changes: z.object({
    data_inicio: nullableDate, data_limite: nullableDate, bloqueada: z.enum(['sim', 'n_o']).optional(),
    motivo_bloqueio: nullableText(5000), visibilidade: z.boolean().optional(), prioridade: option,
    indice: z.number().int().min(0).max(1_000_000).nullable().optional(),
    posicao: z.number().int().min(0).max(1_000_000).nullable().optional(),
    horas_previstas: z.number().min(0).max(1_000_000).nullable().optional(),
    responsavel_id: nullableId, observacao: nullableText(10_000), forms_ids: z.array(uuid).max(500).optional(),
  }).strict().refine(value => Object.keys(value).length > 0, 'Informe uma alteração.'),
}).strict();

export const reviewFormSchema = z.object({
  submissionId: uuid, registro_formulario_id: uuid, expected_updated_at: timestamp,
  decision: z.enum(['approve', 'return']), parecer: z.string().max(10_000), resposta_ids: z.array(uuid).max(2000),
}).strict().superRefine((value, context) => {
  if (value.decision === 'return' && (!value.resposta_ids.length || !value.parecer.trim())) context.addIssue({ code: 'custom', path: ['resposta_ids'], message: 'Selecione respostas e informe o motivo da revisão.' });
  if (value.decision === 'approve' && value.resposta_ids.length) context.addIssue({ code: 'custom', path: ['resposta_ids'], message: 'A aprovação não recebe respostas para revisão.' });
  if (new Set(value.resposta_ids).size !== value.resposta_ids.length) context.addIssue({ code: 'custom', path: ['resposta_ids'], message: 'Respostas repetidas.' });
});

export function pageNumber(value: unknown): number {
  const parsed = Number(value ?? 1);
  return Number.isInteger(parsed) && parsed > 0 ? Math.min(parsed, 10_000) : 1;
}

/** Values interpolated in PostgREST OR syntax cannot introduce filters/wildcards. */
export function searchTerm(value: unknown): string {
  return typeof value === 'string' ? value.trim().slice(0, 100).replace(/[,()%_*"\\.]/g, ' ').replace(/\s+/g, ' ').trim() : '';
}

export function mutationError(code?: string): { code: string; error: string } {
  switch (code) {
    case '42501': return { code, error: 'Seu usuário não tem permissão para esta alteração.' };
    case 'PT409': case '40001': return { code, error: 'O registro mudou desde que a tela foi aberta. Atualize os dados antes de tentar novamente.' };
    case '23505': return { code, error: 'Este protocolo já foi usado com outros dados. Atualize a tela antes de enviar novamente.' };
    case 'P0002': return { code, error: 'O registro não está mais disponível.' };
    case '23503': return { code, error: 'Um dos vínculos selecionados não está mais disponível.' };
    case '22023': case '22P02': case '23514': return { code, error: 'Os dados não atendem às regras desta operação. Confira os campos e a situação do registro.' };
    default: return { code: 'UNAVAILABLE', error: 'Não foi possível confirmar a alteração. Tente novamente com o mesmo protocolo.' };
  }
}

export type DocumentTarget = { kind: 'private'; bucket: 'rm-documentos'; path: string } | { kind: 'external'; url: string };
export function documentSource(source: string | null): { table: string; column: string } | null {
  if (source === null) return { table: 'rm_documentos', column: 'arquivo_url' };
  if (source === 'docs') return { table: 'rm_docs', column: 'arquivo_url' };
  if (source === 'invoice') return { table: 'rm_projetos', column: 'arquivo_nota_fiscal_url' };
  return null;
}
export function documentTarget(raw: unknown, supabaseUrl: string): DocumentTarget | null {
  if (typeof raw !== 'string') return null;
  try {
    const url = new URL(raw), base = new URL(supabaseUrl);
    if (url.protocol !== 'https:' || url.username || url.password || url.hash) return null;
    if (url.origin === base.origin) {
      const prefix = '/storage/v1/object/authenticated/rm-documentos/';
      if (!url.pathname.startsWith(prefix) || url.search) return null;
      const path = decodeURIComponent(url.pathname.slice(prefix.length));
      if (!path || /[%\\\x00-\x1f]/.test(path) || path.split('/').some(part => !part || part === '.' || part === '..')) return null;
      return { kind: 'private', bucket: 'rm-documentos', path };
    }
    // Existing attachments were imported from Bubble's CDN. Redirect only;
    // no arbitrary HTTP fetch, private-network access or service credentials.
    if (url.hostname.endsWith('.cdn.bubble.io') && !url.port) return { kind: 'external', url: url.toString() };
    return null;
  } catch { return null; }
}

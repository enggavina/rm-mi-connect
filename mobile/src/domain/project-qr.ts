import type { AppSnapshot, CatalogFilter, Operator, Row } from '../core/types';
import { hasCurrentCellPolicy } from '../core/operator-policy';
import { canAccessCell, resolveJourneyContext } from './journey';

const PROJECT_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const unavailable = 'Este projeto não está disponível nesta célula no catálogo local. Confira a célula ou sincronize quando houver conexão.';
const changed = 'A célula, o operador ou o catálogo mudou durante a leitura. Leia o QR Code novamente.';

/** The EM label contains only its canonical project UUID, never a URL or a legacy OS. */
export function parseProjectQr(value: unknown): string | null {
  return typeof value === 'string' && value.length === 36 && PROJECT_UUID.test(value) ? value : null;
}

export type ProjectQrContext = Pick<AppSnapshot, 'ready' | 'syncing' | 'sessionUserId' | 'operator'> & {
  cellId?: string; focused: boolean; catalogRevision: number;
};
type QrFailure = { ok: false; reason: string };
type QrTarget = { ok: true; params: { celula: string; projeto: string } };
export type ProjectQrResult = QrFailure | (QrTarget & { contextKey: string });

/** Only changes relevant to this read invalidate it; queue/network notices do not. */
export function projectQrContextKey(context: ProjectQrContext): string {
  const operator = context.operator;
  return JSON.stringify([context.ready, context.focused, context.syncing, context.sessionUserId, context.cellId,
    context.catalogRevision, operator?.operador_id, operator?.authenticated_at, operator?.token_expires_at,
    operator?.perfil, operator?.cell_access_policy_version,
    operator?.celulas_vinculadas.map(link => link.celula_id).sort()]);
}

function contextError(context: ProjectQrContext, now: number): string | null {
  if (!context.ready || !context.focused || context.catalogRevision < 0) return 'Aguarde o catálogo local ficar disponível e tente novamente.';
  if (context.syncing) return 'O catálogo está sendo atualizado. Aguarde e leia o QR Code novamente.';
  const operator = context.operator;
  if (!context.sessionUserId || !operator) return 'Identifique o operador e escolha uma célula antes de ler o QR Code.';
  if (!hasCurrentCellPolicy(operator)) return 'Conecte e identifique o operador novamente para atualizar as células permitidas.';
  const authenticated = Date.parse(operator.authenticated_at), expires = Date.parse(operator.token_expires_at ?? '');
  if (!Number.isFinite(authenticated) || !Number.isFinite(expires) || authenticated > now || now - authenticated >= 86_400_000 || expires <= now) {
    return 'A identificação do turno expirou. Identifique o operador novamente; seus trabalhos estão preservados.';
  }
  if (!canAccessCell(operator, context.cellId)) return 'Escolha uma célula vinculada ao operador identificado.';
  return null;
}

export function projectQrContextCurrent(key: string, context: ProjectQrContext, now = Date.now()): boolean {
  return !contextError(context, now) && key === projectQrContextKey(context);
}

/** Uses the normal journey permission rules, refusing ambiguous/withdrawn allocations. */
export function resolveProjectQr(projectId: string, operator: Operator | null, cellId: string | undefined, cells: Row[], projects: Row[], allocations: Row[]): QrFailure | QrTarget {
  if (!parseProjectQr(projectId)) return { ok: false, reason: 'Este QR Code não é uma identificação de projeto do EM. Use o QR Code gerado no portal.' };
  const candidates = allocations.filter(row => row.celula_id === cellId && row.projeto_id === projectId && row.visibilidade === true && row.retirada !== true);
  // Never select the first allocation if a corrupt/stale catalog contains two live ones.
  if (candidates.length !== 1 || cells.filter(row => row.id === cellId).length !== 1 || projects.filter(row => row.id === projectId).length !== 1) return { ok: false, reason: unavailable };
  const context = resolveJourneyContext(operator, cellId, projectId, cells, projects, candidates);
  return context.ok ? { ok: true, params: { celula: context.cell.id, projeto: context.project.id } } : { ok: false, reason: unavailable };
}

type QrCatalog = 'rm_celulas' | 'rm_projetos' | 'rm_celulas_projeto';
export interface ProjectQrReader {
  context: () => ProjectQrContext;
  list: (table: QrCatalog, filter?: CatalogFilter) => Promise<Row[]>;
  now?: () => number;
}

/** Reads SQLite only. No synchronization, RPC, receiving draft or outbox operation. */
export async function readProjectQr(value: unknown, reader: ProjectQrReader): Promise<ProjectQrResult> {
  const projectId = parseProjectQr(value);
  if (!projectId) return { ok: false, reason: 'Este QR Code não é uma identificação de projeto do EM. Use o QR Code gerado no portal.' };
  try {
    const initial = reader.context(), now = reader.now ?? Date.now;
    const error = contextError(initial, now());
    if (error) return { ok: false, reason: error };
    const key = projectQrContextKey(initial);
    const [cells, projects, allocations] = await Promise.all([
      reader.list('rm_celulas'), reader.list('rm_projetos'),
      reader.list('rm_celulas_projeto', { field: 'celula_id', value: initial.cellId! }),
    ]);
    if (!projectQrContextCurrent(key, reader.context(), now())) return { ok: false, reason: changed };
    const result = resolveProjectQr(projectId, initial.operator, initial.cellId, cells, projects, allocations);
    return result.ok ? { ...result, contextKey: key } : result;
  } catch {
    // Do not expose database errors or any other project's metadata.
    return { ok: false, reason: 'Não foi possível consultar o catálogo local. Tente novamente; seus trabalhos estão preservados.' };
  }
}

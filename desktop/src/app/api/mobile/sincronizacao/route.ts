import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { loadNativeCatalogPage } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const tables = ['rm_celulas', 'rm_projetos', 'rm_celulas_projeto', 'rm_equipamentos', 'rm_clientes', 'rm_tipos_equipamento',
  'rm_forms', 'rm_questoes', 'rm_itens_questoes', 'rm_users', 'rm_tablet_celula_users', 'rm_celula_tipos_equipamento',
  'rm_celula_form_tipos_equipamento', 'rm_fotos', 'rm_registros_formulario', 'rm_respostas', 'rm_aprovacoes_etapas',
  'rm_comentarios', 'rm_logs_aprovacao', 'rm_documentos', 'rm_docs', 'rm_cadastro_fotos'] as const;
const schema = z.object({ operatorToken, table: z.enum(tables),
  after: z.object({ at: z.iso.datetime({ offset: true }), id: z.uuid() }).strict().nullable(), idsOnly: z.boolean() }).strict();
const page = z.object({ workshop_id: z.uuid(), table: z.enum(tables), complete: z.boolean(),
  rows: z.array(z.looseObject({ id: z.uuid(), updated_at: z.iso.datetime({ offset: true }) })).max(250) }).strict();
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
const messages: Record<number, string> = {
  400: 'Consulta de sincronização inválida.', 401: 'Identifique novamente o operador.',
  403: 'Sincronização indisponível para este dispositivo e operador.',
  413: 'A página do catálogo excedeu o limite de sincronização.',
  503: 'Não foi possível sincronizar o catálogo da oficina. Os trabalhos salvos foram preservados.',
};
const failure = (status: number) => Response.json({ error: messages[status] }, { status, headers });

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return failure(401);
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 4096);
  let input: z.infer<typeof schema>;
  try { input = schema.parse(JSON.parse(raw ?? 'null')); }
  catch { return failure(400); }
  try {
    const { data, error } = await loadNativeCatalogPage(bearer, input.operatorToken, input.table, input.after, input.idsOnly);
    if (error || !data) return failure(error?.code === '28000' ? 401 : error?.code === '42501' ? 403 : error?.code === 'PT413' ? 413 : 503);
    const parsed = page.safeParse(data);
    if (!parsed.success || new Set(parsed.data.rows.map(row => row.id)).size !== parsed.data.rows.length
      || (!parsed.data.complete && parsed.data.rows.length !== 250)) return failure(503);
    return Response.json(parsed.data, { headers });
  } catch (error) {
    return failure(error instanceof WorkshopContextError && [401, 403].includes(error.status) ? error.status : 503);
  }
}

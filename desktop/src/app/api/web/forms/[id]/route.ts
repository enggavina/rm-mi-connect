import { getWebUser } from '@/server/web/auth';
import { createWebData } from '@/server/web/data';
import { uuid } from '@/server/web/policy';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const headers = { 'Cache-Control': 'private, no-store' };
  const current = await getWebUser();
  if (!current) return Response.json({ error: 'Autenticação necessária.' }, { status: 401, headers });
  const { id } = await context.params;
  if (!uuid.safeParse(id).success) return Response.json({ error: 'Registro inválido.' }, { status: 400, headers });
  try {
    const record = await createWebData(current.client).getRecord(id);
    return record ? Response.json(record, { headers }) : Response.json({ error: 'Registro não encontrado.' }, { status: 404, headers });
  } catch { return Response.json({ error: 'Não foi possível consultar as respostas.' }, { status: 503, headers }); }
}

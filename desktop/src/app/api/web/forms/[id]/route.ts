import { getWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { createWebData } from '@/server/web/data';
import { uuid } from '@/server/web/policy';
import { CorporateAuthError } from '@/server/web/sso-policy';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const headers = { 'Cache-Control': 'private, no-store' };
  try {
    const current = await getWebUser();
    if (!current) return Response.json({ error: 'Autenticação necessária.' }, { status: 401, headers });
    if (!hasWebCapability(current, 'em.forms.read')) return Response.json({ error: 'Acesso a formulários não autorizado.' }, { status: 403, headers });
    const { id } = await context.params;
    if (!uuid.safeParse(id).success) return Response.json({ error: 'Registro inválido.' }, { status: 400, headers });
    const record = await createWebData(current.client, current.sso?.capabilities).getRecord(id);
    return record ? Response.json(record, { headers }) : Response.json({ error: 'Registro não encontrado.' }, { status: 404, headers });
  } catch (error) {
    const status = error instanceof CorporateAuthError ? error.status : 503;
    return Response.json({ error: status === 403 ? 'Acesso a formulários não autorizado.' : 'Não foi possível consultar as respostas.' }, { status, headers });
  }
}

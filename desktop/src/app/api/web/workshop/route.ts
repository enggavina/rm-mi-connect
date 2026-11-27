import { getWebUser } from '@/server/web/auth';
import { CorporateAuthError } from '@/server/web/sso-policy';
import { createWorkshopData, WORKSHOP_CAPABILITIES } from '@/server/web/workshop-data';
import { readWorkshopOperations } from '@/server/web/workshop-operation-reader';
import { WorkshopContextError } from '@/server/web/workshop-context';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const headers = { 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };
export async function GET() {
  try {
    const current = await getWebUser(WORKSHOP_CAPABILITIES);
    if (!current) return Response.json({ error: 'Autenticação necessária.' }, { status: 401, headers });
    const snapshot = await createWorkshopData(current.client, current.sso?.capabilities, await readWorkshopOperations(current)).getWorkshopSnapshot();
    return Response.json(snapshot, { headers });
  } catch (error) {
    const status = error instanceof CorporateAuthError || error instanceof WorkshopContextError ? error.status : 503;
    return Response.json({ error: status === 403 ? 'Acesso ao gêmeo digital não autorizado.' : 'Não foi possível consultar os dados da oficina. Tente novamente.' }, { status, headers });
  }
}

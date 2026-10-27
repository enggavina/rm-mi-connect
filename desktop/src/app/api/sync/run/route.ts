import { authorized } from '@/server/security';
import { Bridge } from '@/server/bridge/engine';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export async function POST(request: Request) {
  if (!authorized(request)) return Response.json({error:'Não autorizado'},{status:401});
  try { const result = await new Bridge().cycle(); return Response.json(result,{status:result.outbox.failed || result.inbox.errors.length?207:200}); }
  catch (error) { const busy = error instanceof Error && error.message === 'BRIDGE_BUSY'; return Response.json({error:busy?'Sincronização em andamento.':'Falha de sincronização; consulte logs.'},{status:busy?409:503}); }
}

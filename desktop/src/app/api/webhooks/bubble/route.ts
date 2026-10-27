import { z } from 'zod';
import { authorized, readJson } from '@/server/security';
import { Bridge } from '@/server/bridge/engine';
import { getEntity } from '@/server/bridge/mapping';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const schema = z.object({ entity_type:z.string().min(1).max(80), bubble_id:z.string().min(1).max(150) });
export async function POST(request: Request) {
  if (!authorized(request,'BUBBLE_WEBHOOK_SECRET')) return Response.json({error:'Não autorizado'},{status:401});
  let body: z.infer<typeof schema>;
  try { body = schema.parse(await readJson(request)); getEntity(body.entity_type); }
  catch { return Response.json({error:'Informe entity_type suportado e bubble_id.'},{status:400}); }
  try {
    const bridge = new Bridge(); const entity = getEntity(body.entity_type);
    // Read canonical data with server credentials; caller cannot inject arbitrary columns.
    const id = await bridge.withLease(async () => bridge.apply(entity,await bridge.bubble.get(entity.endpoint,body.bubble_id)));
    return Response.json({applied:true,id});
  } catch (error) {
    const busy = error instanceof Error && error.message === 'BRIDGE_BUSY';
    console.error('bubble_webhook_failed',error instanceof Error ? error.message : 'falha');
    return Response.json({error:busy?'Sincronização em andamento; tente novamente.':'Falha ao aplicar atualização. O remetente deve tentar novamente.'},{status:busy?409:503,headers:{'Retry-After':'15'}});
  }
}

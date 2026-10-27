import { authorized } from './security';
export function phaseTwo(request: Request, feature: string) {
  if (!authorized(request)) return Response.json({ error: 'Não autorizado' }, { status: 401 });
  return Response.json({ error: 'NOT_IMPLEMENTED', feature, phase: 2, message: 'Serviço reservado para implementação na Fase 2.' }, { status: 501 });
}

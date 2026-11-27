const receivingUrl = 'https://em-web-production.up.railway.app/api/mobile/recebimentos';
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
export type ReceivingPhase = 'open' | 'complete';

export async function sendScopedReceiving(input: {
  deviceToken: string;
  operatorToken: string;
  submission: string;
  phase: ReceivingPhase;
  workshopOrigin?: string;
  payload: Record<string, unknown>;
}, signal: AbortSignal, request = fetch): Promise<unknown> {
  const { deviceToken, ...body } = input;
  const response = await request(receivingUrl, {
    method: 'POST', redirect: 'error', signal,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}` },
    body: JSON.stringify(body),
  });
  const parsed = await response.json().catch(() => null);
  if (response.ok && typeof parsed?.projeto_id === 'string' && uuid.test(parsed.projeto_id)
    && typeof parsed.equipamento_id === 'string' && uuid.test(parsed.equipamento_id)) return parsed;
  const code = ['28000', '42501', '22023', 'P0002', 'PT409', 'PT410', 'PT503'].includes(parsed?.code) ? parsed.code : 'PT503';
  const message = typeof parsed?.message === 'string' && parsed.message.length <= 250
    ? parsed.message : 'Não foi possível confirmar a oficina. O recebimento original foi preservado.';
  throw Object.assign(new Error(message), { code });
}

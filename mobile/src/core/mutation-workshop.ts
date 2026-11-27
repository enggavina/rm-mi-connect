import type { RpcName } from './types';

const destination = 'https://em-web-production.up.railway.app/api/mobile/registros';
type NativeOperation = Exclude<RpcName, 'rm_submit_recebimento_v1'>;
const codes = new Set(['28000', '42501', '22023', 'P0002', 'PT409', 'PT410', 'PT422', 'PT503']);

export async function sendWorkshopMutation(input: { deviceToken: string; operatorToken: string; submission: string;
  operation: NativeOperation; payload: Record<string, unknown> }, request = fetch) {
  const { deviceToken, ...body } = input;
  const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 25_000);
  let response: Response, data;
  try {
    response = await request(destination, {
      method: 'POST', redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}` },
      body: JSON.stringify(body),
    });
    data = await response.json().catch(() => null);
  } finally { clearTimeout(timeout); }
  if (response.ok && data && typeof data === 'object' && !Array.isArray(data)) return data;
  const message = typeof data?.message === 'string' && data.message.length <= 250
    ? data.message : 'O registro original permanece salvo. Tente novamente com a oficina confirmada.';
  throw Object.assign(new Error(message), { code: codes.has(data?.code) ? data.code : 'PT503' });
}

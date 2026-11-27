import { parseExecutionSnapshot } from './execution';

const destination = 'https://em-web-production.up.railway.app/api/mobile/apontamentos';
const refusals = new Set(['28000', '42501', 'P0002', 'PT410', 'PT413']);

export async function readWorkshopExecution(input: { deviceToken: string; operatorToken: string; workshopOrigin: string;
  operatorId: string; allocation: string }, request = fetch) {
  const { deviceToken, operatorId, ...body } = input;
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 25_000);
  try {
    const response = await request(destination, { method: 'POST', redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}` }, body: JSON.stringify(body) });
    const value = await response.json().catch(() => null);
    if (!response.ok) throw Object.assign(new Error('Não foi possível confirmar os apontamentos desta etapa.'),
      { code: refusals.has(value?.code) ? value.code : 'PT503' });
    if (value?.workshop_id !== input.workshopOrigin) throw Object.assign(new Error('A consulta retornou outra oficina.'), { code: '42501' });
    return parseExecutionSnapshot(value.snapshot, operatorId, input.allocation);
  } finally {
    clearTimeout(timer);
  }
}

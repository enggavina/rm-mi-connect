import type { Operator } from './types';

const catalogUrl = 'https://em-web-production.up.railway.app/api/mobile/catalogo';
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export function operatorWorkshopDenied(error: unknown) {
  return typeof error === 'object' && error !== null && 'code' in error && ['28000', '42501'].includes(String(error.code));
}

export async function readWorkshopOperatorCells(
  deviceId: string, deviceToken: string, operator: Operator, operatorToken: string,
  signal: AbortSignal, { androidBuild, request = fetch }: { androidBuild?: string; request?: typeof fetch } = {},
) {
  const response = await request(catalogUrl, {
    method: 'POST', redirect: 'error', signal,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}`,
      ...(androidBuild ? { 'X-EM-Android-Build': androidBuild } : {}) },
    body: JSON.stringify({ operatorToken }),
  });
  if (!response.ok) throw Object.assign(new Error('Não foi possível confirmar as células da oficina. Os trabalhos salvos foram preservados.'),
    { code: response.status === 401 ? '28000' : response.status === 403 ? '42501' : 'PT503' });
  const value = await response.json();
  if (value?.deviceId !== deviceId || value.operatorId !== operator.operador_id || typeof value.workshop?.id !== 'string'
    || !uuid.test(value.workshop.id) || !Number.isSafeInteger(value.workshop.revision) || value.workshop.revision < 1
    || value.data?.kind !== 'cells' || !Array.isArray(value.data.items) || value.data.items.length > 2000
    || !Number.isFinite(Date.parse(value.expiresAt)) || Date.parse(value.expiresAt) <= Date.now()) {
    throw new Error('A leitura das células não corresponde a este dispositivo e operador.');
  }
  const cells = new Set<string>();
  for (const cell of value.data.items) {
    if (typeof cell?.id !== 'string' || !uuid.test(cell.id) || cells.has(cell.id)) throw new Error('A lista de células da oficina está incompleta.');
    cells.add(cell.id);
  }
  return { workshopId: value.workshop.id as string, operator: { ...operator,
    celulas_vinculadas: operator.celulas_vinculadas.filter(cell => cells.has(cell.celula_id)) } };
}

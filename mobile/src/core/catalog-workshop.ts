import type { CatalogTable } from './types';

const syncUrl = 'https://em-web-production.up.railway.app/api/mobile/sincronizacao';
const tables = new Set<CatalogTable>(['rm_celulas', 'rm_projetos', 'rm_celulas_projeto', 'rm_equipamentos',
  'rm_clientes', 'rm_tipos_equipamento', 'rm_forms', 'rm_questoes', 'rm_itens_questoes']);
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export type CatalogCursor = { at: string; id: string };
export type CatalogSession = { deviceToken: string; operatorToken: string; workshopId: string };
export const scopedCatalogTable = (table: CatalogTable) => tables.has(table);

export async function readWorkshopCatalogPage(session: CatalogSession, table: CatalogTable, after: CatalogCursor | null,
  idsOnly: boolean, request = fetch) {
  const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 20_000);
  let value;
  try {
    const response = await request(syncUrl, {
      method: 'POST', redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.deviceToken}` },
      body: JSON.stringify({ operatorToken: session.operatorToken, table, after, idsOnly }),
    });
    if (!response.ok) throw Object.assign(new Error('Não foi possível sincronizar o catálogo da oficina.'),
      { code: response.status === 401 ? '28000' : response.status === 403 ? '42501' : 'PT503' });
    value = await response.json();
  } finally { clearTimeout(timeout); }

  if (value?.workshop_id !== session.workshopId || value.table !== table || typeof value.complete !== 'boolean'
    || !Array.isArray(value.rows) || value.rows.length > 250 || (!value.complete && value.rows.length !== 250)
    || value.rows.some((row: any) => typeof row?.id !== 'string' || !uuid.test(row.id) || typeof row.updated_at !== 'string'
      || !Number.isFinite(Date.parse(row.updated_at)) || (idsOnly && Object.keys(row).length !== 2))
    || new Set(value.rows.map((row: any) => row.id)).size !== value.rows.length) {
    throw new Error('A página do catálogo não corresponde à oficina confirmada. Os trabalhos salvos foram preservados.');
  }
  return { rows: value.rows as { id: string; updated_at: string; [field: string]: any }[], complete: value.complete as boolean };
}

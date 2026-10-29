import { getCatalogs, listProjects } from './data';
import type { CatalogKind, WebRow } from './data';

async function catalog(kind: CatalogKind) {
  const first = await getCatalogs({ kind }); const rows: WebRow[] = [...first.rows];
  for (let page = 2; page <= Math.ceil(first.total / first.pageSize); page++) rows.push(...(await getCatalogs({ kind, page })).rows);
  return rows;
}
export async function editorChoices() {
  const [clients, types, users, forms, projects] = await Promise.all([catalog('clients'), catalog('types'), catalog('users'), catalog('forms'), listProjects()]);
  return { clients, types, users, forms, statuses: projects.statuses };
}

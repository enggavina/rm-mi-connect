import type { ProjectDocumentPage } from '@/server/web/project-dossier-search-policy';
export type ProjectDocumentFolder = NonNullable<ProjectDocumentPage['navigation']>['folders'][number];
export function documentDirectoryHref(projectId: string, folderId: string | null) {
  return `/projetos/${projectId}?tab=documentos${folderId ? `&doc_folder=${encodeURIComponent(folderId)}` : ''}`;
}
/** Iterative traversal avoids depth limits and stack overflows. Reject corrupt
 * metadata instead of inventing a plausible path or a cross-project fallback. */
export function documentFolderPaths(folders: ProjectDocumentFolder[]) {
  const byId = new Map(folders.map(folder => [folder.id, folder])), paths = new Map<string, string>();
  if (byId.size !== folders.length) throw new Error('Pastas repetidas.');
  for (const folder of folders) {
    const chain: ProjectDocumentFolder[] = [], seen = new Set<string>(); let current: ProjectDocumentFolder | undefined = folder;
    while (current && !paths.has(current.id)) {
      if (seen.has(current.id)) throw new Error('Ciclo na estrutura de pastas.');
      seen.add(current.id); chain.push(current);
      if (current.parent_id && !byId.has(current.parent_id)) throw new Error('Pasta superior indisponível.');
      current = current.parent_id ? byId.get(current.parent_id) : undefined;
    }
    let prefix = current ? paths.get(current.id)! : 'Documentos';
    for (const item of chain.reverse()) { prefix += ` / ${item.nome}`; paths.set(item.id, prefix); }
  }
  return paths;
}
export function documentFolderDescendants(folders: ProjectDocumentFolder[], folderId: string) {
  const result = new Set([folderId]), children = new Map<string, string[]>();
  for (const folder of folders) if (folder.parent_id) children.set(folder.parent_id, [...(children.get(folder.parent_id) ?? []), folder.id]);
  const pending = [folderId];
  while (pending.length) for (const child of children.get(pending.pop()!) ?? []) if (!result.has(child)) { result.add(child); pending.push(child); }
  return result;
}

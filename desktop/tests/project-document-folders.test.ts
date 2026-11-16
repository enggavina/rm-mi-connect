import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { manageProjectDocumentsSchema } from '../src/server/web/project-document-folder-policy';
import { createProjectDocumentFolderActions } from '../src/server/web/project-document-folder-mutations';
import { createProjectDossierSearchData } from '../src/server/web/project-dossier-search-data';
import { projectDocumentFiltersSchema, type ProjectDocumentPage } from '../src/server/web/project-dossier-search-policy';
import { dossierAttachmentRequest } from '../src/components/web/project-dossier-model';
import { documentDirectoryHref, documentFolderDescendants, documentFolderPaths } from '../src/components/web/project-document-folder-model';
import { dossierSearchHref, readDossierSearchQuery } from '../src/components/web/project-dossier-search-model';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';
const id = (n: number) => `04400000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const time = '2026-11-16T12:00:00.123456+00:00';
const folders = [{ id: id(1), parent_id: null, nome: 'Engenharia', updated_at: time }, { id: id(2), parent_id: id(1), nome: 'Relatórios', updated_at: time }, { id: id(3), parent_id: null, nome: 'Qualidade', updated_at: time }];
const base = { submissionId: id(90), projeto_id: id(10), expected_project_updated_at: time };
const create = { ...base, action: 'create_folder' as const, parent_id: id(2), nome: 'Inspeções' };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.documents.read', 'em.projects.manage'];
function actions(capabilities = caps, role = 'administrador', patch?: (result: WebActionResult) => WebActionResult) {
  const calls: unknown[][] = [];
  const access = { client: {}, user: { id: id(20) }, profile: { id: id(21), perfil: role }, sso: { capabilities, sessionHash: 'opaque', bindingId: id(22), subject: id(23) } } as Awaited<ReturnType<typeof actionUser>>;
  const factory = createProjectDocumentFolderActions({ actionUser: async capability => capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' },
    mutate: async (...args) => { calls.push(args); const request = args[2]; const result: WebActionResult = { ok: true, data: { operation: 'manage_project_documents', id: request.submissionId, projeto_id: request.projeto_id as string, updated_at: time, idempotent_replay: calls.length > 1,
      record: { id: request.submissionId, projeto_id: request.projeto_id, action: request.action, parent_id: request.parent_id, nome: request.nome, before: { private: true } } } }; return patch ? patch(result) : result; } });
  return { ...factory, calls };
}
function directoryPage(): ProjectDocumentPage {
  const { page: _, ...filters } = projectDocumentFiltersSchema.parse({ folder_id: id(2) });
  return { project_id: id(10), total: 0, unfiltered_total: 0, page: 1, page_size: 25, filters, items: [], facets: { authors: [], statuses: [] },
    navigation: { current_folder_id: id(2), folders: structuredClone(folders), breadcrumbs: structuredClone(folders.slice(0, 2)) } };
}
test('directory navigation persists root/deep folder context through filters and pagination', () => {
  const paths = documentFolderPaths(folders);
  assert.equal(paths.get(id(2)), 'Documentos / Engenharia / Relatórios');
  assert.equal(documentDirectoryHref(id(10), id(2)), `/projetos/${id(10)}?tab=documentos&doc_folder=${id(2)}`);
  assert.equal(documentDirectoryHref(id(10), null), `/projetos/${id(10)}?tab=documentos`);
  const query = readDossierSearchQuery('documents', { doc_folder: id(2), doc_q: 'Motor', document_page: '2' });
  assert.deepEqual(query.errors, []); assert.equal(query.filters.folder_id, id(2));
  assert.match(dossierSearchHref(id(10), 'documents', query.filters, 3), new RegExp(`doc_folder=${id(2)}`));
  assert.equal(readDossierSearchQuery('documents', {}).filters.folder_id, null);
  assert.ok(readDossierSearchQuery('documents', { doc_folder: 'wrong' }).errors.length);
});
test('directory paths have no artificial one-level or recursive stack limit and reject corrupt hierarchy', () => {
  const chain = Array.from({ length: 5000 }, (_, index) => ({ id: id(index + 100), parent_id: index ? id(index + 99) : null, nome: `N${index}`, updated_at: time }));
  assert.ok(documentFolderPaths(chain).get(id(5099))?.endsWith('/ N4999'));
  assert.deepEqual([...documentFolderDescendants(folders, id(1))], [id(1), id(2)]);
  assert.throws(() => documentFolderPaths([{ ...folders[0], parent_id: id(2) }, folders[1]]), /Ciclo/);
  assert.throws(() => documentFolderPaths([folders[1]]), /superior/);
  assert.throws(() => documentFolderPaths([folders[0], folders[0]]), /repetidas/);
});
test('folder actions reject paths, spoofed authors, stale malformed versions and unconfirmed destructive requests', async () => {
  for (const nome of ['../escape', 'a\\b', '.', '..', '\u0000', ' ', 'a'.repeat(201)]) assert.equal(manageProjectDocumentsSchema.safeParse({ ...create, nome }).success, false);
  const trimmed = manageProjectDocumentsSchema.parse({ ...create, nome: ' Inspeções ' }); assert.equal(trimmed.action, 'create_folder'); if (trimmed.action === 'create_folder') assert.equal(trimmed.nome, 'Inspeções');
  const remove = { ...base, action: 'delete_folder', folder_id: id(1), expected_folder_updated_at: time, confirm_change: true };
  for (const input of [{ ...create, created_by: id(21) }, { ...create, expected_project_updated_at: 'yesterday' }, { ...remove, confirm_change: false }, { ...remove, confirm_change: undefined }]) {
    const f = actions(), result = await f.manageProjectDocuments(input); assert.ok(!result.ok); assert.equal(result.code, 'INVALID_INPUT'); assert.equal(f.calls.length, 0);
  }
});
test('folder mutations require exact existing project/document/management scopes and internal profiles', async () => {
  for (const f of [actions(caps, 'auditor'), actions(caps, 'mobile'), ...caps.map(cap => actions(caps.filter(value => value !== cap)))]) {
    assert.equal((await f.manageProjectDocuments(create)).ok, false); assert.equal(f.calls.length, 0);
  }
  assert.equal((await actions(caps, 'padr_o').manageProjectDocuments(create)).ok, true);
});
test('folder requests keep stable receipt, SSO scope and exact current parent; action response drops private journal', async () => {
  const f = actions(), first = await f.manageProjectDocuments(create), second = await f.manageProjectDocuments(create);
  assert.ok(first.ok && second.ok); assert.equal(second.data.idempotent_replay, true); assert.deepEqual(f.calls[0], f.calls[1]);
  assert.equal(f.calls[0][1], 'manage_project_documents'); assert.equal(f.calls[0][3], 'em.projects.manage');
  assert.deepEqual(first.data.record, { action: 'create_folder', folder_id: id(90), nome: 'Inspeções', parent_id: id(2) });
  for (const patch of [{ id: id(99) }, { projeto_id: id(99) }, { updated_at: 'bad' }, { record: { action: 'create_folder' } }]) {
    const result = await actions(caps, 'administrador', result => result.ok ? { ok: true, data: { ...result.data, ...patch } } : result).manageProjectDocuments(create);
    assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
});
test('nonempty folder rejection explains pending uploads without turning a safe validation into an uncertain retry', async () => {
  const f = actions(caps, 'administrador', () => ({ ok: false, code: '22023', error: 'Generic validation' }));
  const result = await f.manageProjectDocuments({ ...base, action: 'delete_folder', folder_id: id(2), expected_folder_updated_at: time, confirm_change: true });
  assert.ok(!result.ok); assert.equal(result.code, '22023'); assert.match(result.error, /envios pendentes/);
});
test('upload selection freezes actual destination UUID in existing request without altering file identity', () => {
  const file = { name: 'motor.pdf', type: 'application/pdf', size: 12 }, draft = { nome: 'Placa', descricao: '', expiry: '', status: 'No prazo', folder_id: id(2) };
  const request = dossierAttachmentRequest(id(10), time, file, draft, 'a'.repeat(64), id(91)); draft.folder_id = id(3);
  assert.equal(request.folder_id, id(2)); assert.equal(request.filename, 'motor.pdf'); assert.equal(Object.isFrozen(request), true);
});
test('folder reader reuses one RLS RPC and rejects substituted, missing, cyclic or incomplete directory metadata', async () => {
  const read = (page: unknown) => createProjectDossierSearchData({ rpc: async (rpc: string, args: unknown) => { assert.equal(rpc, 'rm_web_project_documents_v1'); assert.ok(args); return { data: page, error: null }; } } as unknown as SupabaseClient, caps).getProjectDocuments(id(10), { folder_id: id(2) });
  assert.equal((await read(directoryPage()))?.navigation?.current_folder_id, id(2));
  for (const patch of [(page: ProjectDocumentPage) => { delete page.navigation; }, (page: ProjectDocumentPage) => { page.navigation!.current_folder_id = id(3); },
    (page: ProjectDocumentPage) => { page.navigation!.breadcrumbs.reverse(); }, (page: ProjectDocumentPage) => { page.navigation!.folders[0].parent_id = id(2); },
    (page: ProjectDocumentPage) => { page.navigation!.folders.pop(); page.navigation!.folders[0].parent_id = id(3); }]) {
    const page = directoryPage(); patch(page); await assert.rejects(read(page), /Não foi possível/);
  }
});

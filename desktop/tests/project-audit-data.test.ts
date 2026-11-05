import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createProjectAuditData, type ProjectAuditPage } from '../src/server/web/project-audit-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.history.read', 'em.planning.read', 'em.photos.read', 'em.forms.read', 'em.approvals.read'];
function page(kind: 'cells' | 'operations' = 'cells'): ProjectAuditPage {
  return { project_id: id(1), kind, total: 1, page: 1, page_size: 25, items: [{ id: `audit:${'a'.repeat(64)}`, projeto_id: id(1),
    topic: kind === 'cells' ? 'cells' : 'photos', action: kind === 'cells' ? 'allocation_changed' : 'photo_selection_changed',
    entity_id: id(2), celula_id: id(3), celula_projeto_id: id(2), actor_id: id(4), actor_name: 'Autora', cell_name: 'Montagem',
    occurred_at: '2026-11-05T15:00:00.123456+00:00', source: 'web', prior_evidence: true,
    changes: [{ field: kind === 'cells' ? 'data_limite' : 'selecao_relatorio', before: kind === 'cells' ? '2026-11-10T15:00:00Z' : false,
      after: kind === 'cells' ? '2026-11-18T15:00:00Z' : true }], reason: null }] };
}
function fixture(data: unknown, capabilities: CorporateCapability[] = caps, error: unknown = null) {
  const calls: unknown[][] = [];
  const client = { rpc: async (...args: unknown[]) => { calls.push(args); if (error instanceof Error) throw error; return { data, error }; },
    from: () => { throw new Error('Private journals cannot be fetched as tables'); } } as unknown as SupabaseClient;
  return { ...createProjectAuditData(client, capabilities), calls };
}
test('audit scopes require portal, project and history; cell audit independently requires planning', async () => {
  for (const scope of ['em.portal.read', 'em.projects.read', 'em.history.read', 'em.planning.read'] as const) {
    const f = fixture(page(), caps.filter(cap => cap !== scope));
    await assert.rejects(f.getProjectAudit(id(1), 'cells'), /Acesso/); assert.deepEqual(f.calls, []);
  }
  const f = fixture(page('operations'), caps.filter(cap => cap !== 'em.planning.read'));
  assert.equal((await f.getProjectAudit(id(1), 'operations'))?.total, 1);
});
test('audit uses one project-scoped read RPC and topic grants before pagination', async () => {
  const f = fixture(page('operations'), caps.filter(cap => cap !== 'em.forms.read' && cap !== 'em.approvals.read'));
  assert.deepEqual(await f.getProjectAudit(id(1), 'operations', '1'), page('operations'));
  assert.deepEqual(f.calls, [['rm_web_project_audit_v1', { p_project_id: id(1), p_kind: 'operations', p_page: 1, p_topics: ['photos'] }]]);
  const deniedTopic = page('operations'); deniedTopic.items[0].topic = 'forms';
  await assert.rejects(fixture(deniedTopic, caps.filter(cap => cap !== 'em.forms.read')).getProjectAudit(id(1), 'operations'), /Não foi possível/);
});
test('audit rejects missing, cross-project, duplicated, unordered and malformed DTO evidence', async () => {
  const variants: unknown[] = [undefined, {}, { ...page(), total: 26 }, { ...page(), project_id: id(9) }, { ...page(), kind: 'operations' }];
  for (const patch of [{ id: 'private-submission-protocol' }, { projeto_id: id(9) }, { topic: 'photos' }, { entity_id: 'name' }, { actor_id: 'auth@example.test' },
    { occurred_at: 'yesterday' }, { source: 'sync-secret' }, { changes: [] },
    { changes: [{ field: 'foto_url', before: null, after: 'https://private.invalid' }] },
    { changes: [{ field: 'observacao', before: {}, after: { auth_user_id: id(4) } }] }]) {
    const value = page(); Object.assign(value.items[0], patch); variants.push(value);
  }
  const duplicate = page(); duplicate.total = 2; duplicate.items.push({ ...duplicate.items[0] }); variants.push(duplicate);
  const unordered = page(); unordered.total = 2; unordered.items.push({ ...unordered.items[0], id: `audit:${'b'.repeat(64)}`, occurred_at: '2026-11-05T16:00:00+00:00' }); variants.push(unordered);
  for (const value of variants) await assert.rejects(fixture(value).getProjectAudit(id(1), 'cells'), /Não foi possível/);
});
test('audit preserves microsecond timestamps and field values but strips unrelated RPC metadata', async () => {
  const value = page(); const extended = { ...value, private_metadata: 'secret', items: [{ ...value.items[0], foto_url: 'https://private.invalid', auth_user_id: id(9) }] };
  assert.deepEqual(await fixture(extended).getProjectAudit(id(1), 'cells'), value);
  const historical = page(); historical.items[0].actor_id = null; historical.items[0].actor_name = null; historical.items[0].prior_evidence = false; historical.items[0].changes[0].before = null;
  assert.deepEqual(await fixture(historical).getProjectAudit(id(1), 'cells'), historical);
});
test('audit accepts null legacy project and clamps beyond-last pages without repeating full journals', async () => {
  assert.equal(await fixture(null).getProjectAudit(id(1), 'cells'), null);
  assert.deepEqual(await fixture(page()).getProjectAudit(id(1), 'cells', 9), page());
  const f = fixture(page()); assert.equal(await f.getProjectAudit('bad-id', 'cells'), null); assert.equal(f.calls.length, 0);
  for (const value of [null, 0, -1, '0', '01', 'abc', 1.5, 1000001, []]) await assert.rejects(f.getProjectAudit(id(1), 'cells', value), /Não foi possível/);
});
test('audit errors stay generic and never return private database or transport details', async () => {
  for (const error of [new Error('password private transport'), { message: 'private schema details' }]) {
    await assert.rejects(fixture(null, caps, error).getProjectAudit(id(1), 'cells'), error => error instanceof Error && !/password|schema|transport/.test(error.message));
  }
});

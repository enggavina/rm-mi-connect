import test from 'node:test';
import assert from 'node:assert/strict';
import { saveGanttPlanSchema } from '../src/server/web/gantt-policy';
import { createGanttActions } from '../src/server/web/gantt-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-11-16T18:03:24.123456+00:00';
const caps: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.planning.manage', 'em.projects.read'];
const request = { submissionId: id(20), reason: 'Ajuste de prazo confirmado', projects: [{ id: id(1), expected_updated_at: version, expected_plan_version: 'a'.repeat(64) }],
  items: [{ id: id(2), expected_updated_at: version, changes: { data_inicio: '2026-11-16', data_limite: '2026-11-20' } }] };
const link = { predecessor_id: id(2), successor_id: id(3), lag_days: 0 };

test('Gantt command retains exact versions, partial date changes and explicit baseline/dependency decisions', () => {
  assert.deepEqual(saveGanttPlanSchema.parse(request), request);
  assert.equal(saveGanttPlanSchema.parse({ ...request, items: [{ ...request.items[0], changes: { data_inicio: null } }] }).items[0].changes.data_inicio, null);
  const dependencies = { projeto_id: id(1), links: [link] };
  assert.deepEqual(saveGanttPlanSchema.parse({ ...request, items: [], dependencies }).dependencies, dependencies);
  assert.equal(saveGanttPlanSchema.parse({ ...request, items: [], dependencies: { projeto_id: id(1), links: [] } }).dependencies?.links.length, 0);
  assert.equal(saveGanttPlanSchema.parse({ ...request, items: [], baseline: { projeto_id: id(1), label: '  Plano aprovado  ' } }).baseline?.label, 'Plano aprovado');
});

test('Gantt rejects actor injection, unsupported edits, invalid calendar dates and absent revision proof', () => {
  for (const invalid of [
    { ...request, actor_id: id(8) }, { ...request, operation: 'delete_project' }, { ...request, reason: ' ' },
    { ...request, projects: [] }, { ...request, projects: [...request.projects, request.projects[0]] },
    { ...request, projects: [{ ...request.projects[0], expected_plan_version: 'not-a-revision' }] },
    { ...request, projects: [{ ...request.projects[0], expected_updated_at: '2026-11-16' }] },
    { ...request, items: [] }, { ...request, items: [...request.items, request.items[0]] },
    { ...request, items: [{ ...request.items[0], changes: {} }] },
    { ...request, items: [{ ...request.items[0], changes: { status: 'finalizado' } }] },
    { ...request, items: [{ ...request.items[0], changes: { data_inicio: '2026-02-30' } }] },
    { ...request, items: [{ ...request.items[0], changes: { data_inicio: '0000-01-01' } }] },
    { ...request, items: [{ ...request.items[0], changes: { data_inicio: '1899-12-31' } }] },
    { ...request, items: [{ ...request.items[0], changes: { data_inicio: '2201-01-01' } }] },
    { ...request, items: [{ ...request.items[0], changes: { data_inicio: version } }] },
    { ...request, items: [{ ...request.items[0], changes: { data_inicio: '2026-11-20', data_limite: '2026-11-16' } }] },
    { ...request, items: [{ ...request.items[0], expected_updated_at: null }] },
    { ...request, baseline: { projeto_id: id(99), label: 'Plano' } },
    { ...request, baseline: { projeto_id: id(1), label: '' } },
    { ...request, baseline: { projeto_id: id(1), label: 'Plano' } },
    { ...request, items: [], baseline: { projeto_id: id(1), label: 'Plano' }, dependencies: { projeto_id: id(1), links: [] } },
    { ...request, projects: [...request.projects, { ...request.projects[0], id: id(9) }], dependencies: { projeto_id: id(1), links: [] } },
    { ...request, dependencies: { projeto_id: id(99), links: [] } },
  ]) assert.equal(saveGanttPlanSchema.safeParse(invalid).success, false, JSON.stringify(invalid));
});

test('Gantt dependencies reject cycles, self-reference, duplicate edges and invalid lag without changing route or queue', () => {
  for (const links of [
    [link, link], [{ ...link, successor_id: link.predecessor_id }], [{ ...link, lag_days: -1 }], [{ ...link, lag_days: 1.5 }], [{ ...link, lag_days: 3651 }],
    [link, { predecessor_id: id(3), successor_id: id(4), lag_days: 1 }, { predecessor_id: id(4), successor_id: id(2), lag_days: 0 }],
  ]) assert.equal(saveGanttPlanSchema.safeParse({ ...request, dependencies: { projeto_id: id(1), links } }).success, false);
  const branch = [link, { predecessor_id: id(2), successor_id: id(4), lag_days: 3 }, { predecessor_id: id(4), successor_id: id(5), lag_days: 0 }];
  assert.equal(saveGanttPlanSchema.safeParse({ ...request, dependencies: { projeto_id: id(1), links: branch } }).success, true);
});

function fixture(profile = 'administrador', capabilities = caps, injected?: WebActionResult) {
  const calls: any[] = [], auth: string[] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Pessoa', perfil: profile },
    sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createGanttActions({
    actionUser: async capability => { auth.push(capability); return access; },
    mutate: async (...args) => { calls.push(args); return injected ?? { ok: true, data: { operation: 'save_gantt_plan', id: id(1), projeto_id: id(1), updated_at: version,
      record: { changed_ids: [id(2)], links_changed: false, baseline_id: null, private: 'never expose' }, idempotent_replay: false } }; },
  });
  return { ...actions, calls, auth };
}

test('Gantt action requires current management grant, reading grants and an allowed local profile', async () => {
  for (const f of [fixture('auditor'), fixture('mobile'), fixture('administrador', caps.filter(c => c !== 'em.projects.read')), fixture('administrador', caps.filter(c => c !== 'em.planning.read')), fixture('administrador', caps.filter(c => c !== 'em.planning.manage'))]) {
    assert.equal((await f.saveGanttPlan(request)).ok, false); assert.deepEqual(f.calls, []); assert.deepEqual(f.auth, ['em.planning.manage']);
  }
  const denied = createGanttActions({ actionUser: async () => ({ ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' }), mutate: async () => { throw new Error('must not run'); } });
  assert.equal((await denied.saveGanttPlan(request)).ok, false);
  for (const profile of ['administrador', 'padr_o']) {
    const f = fixture(profile); assert.equal((await f.saveGanttPlan(request)).ok, true); assert.equal(f.calls[0][1], 'save_gantt_plan'); assert.equal(f.calls[0][3], 'em.planning.manage');
  }
});

test('Gantt retry preserves one submission with exact payload and returns only a validated public receipt', async () => {
  const f = fixture(); const first = await f.saveGanttPlan(request); await f.saveGanttPlan(request);
  assert.deepEqual(f.calls[0], f.calls[1]); assert.deepEqual(f.calls[0][2], request);
  assert.ok(first.ok); assert.deepEqual(first.data.record, { changed_ids: [id(2)], links_changed: false, baseline_id: null });
  assert.ok(!JSON.stringify(first).includes('private'));
  await f.saveGanttPlan({ ...request, actor: id(99) }); assert.equal(f.calls.length, 2);
});

test('Gantt checks batch ownership, changed members and baseline receipt before acknowledging success', async () => {
  const good: any = { ok: true, data: { operation: 'save_gantt_plan', id: id(1), projeto_id: id(1), updated_at: version,
    record: { changed_ids: [id(2)], links_changed: false, baseline_id: null }, idempotent_replay: true } };
  for (const patch of [
    { operation: 'plan_cell' }, { id: id(99) }, { projeto_id: null }, { updated_at: 'invalid' }, { idempotent_replay: undefined },
    { record: { ...good.data.record, changed_ids: [id(99)] } }, { record: { ...good.data.record, changed_ids: [id(2), id(2)] } },
    { record: { ...good.data.record, links_changed: true } }, { record: { ...good.data.record, baseline_id: id(30) } },
  ]) {
    const result = await fixture('administrador', caps, { ok: true, data: { ...good.data, ...patch } }).saveGanttPlan(request);
    assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
  const multi = { ...request, projects: [...request.projects, { ...request.projects[0], id: id(9) }] };
  const result = await fixture('administrador', caps, { ...good, data: { ...good.data, id: request.submissionId, projeto_id: null } }).saveGanttPlan(multi);
  assert.ok(result.ok); assert.equal(result.data.id, request.submissionId); assert.equal(result.data.projeto_id, null);
  for (const code of ['PT409', '42501', '23505', 'UNAVAILABLE']) {
    const failure = await fixture('administrador', caps, { ok: false, code, error: 'Sanitized' }).saveGanttPlan(request);
    assert.ok(!failure.ok); assert.equal(failure.code, code);
  }
});

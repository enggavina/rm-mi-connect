import test from 'node:test';
import assert from 'node:assert/strict';
import { formReviewerBootstrapId, formReviewerBootstrapSql, prepareFormReviewerBootstrap, readBubbleFormReviewerAssignments, type FormReviewerBootstrapLookups } from '../src/server/bridge/form-reviewer-bootstrap';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const at = '2026-10-30T10:00:00.123456+00:00', cutoff = '2026-10-30T12:00:00.000000Z';
const lookup = (): FormReviewerBootstrapLookups => ({ projects: [{ id: id(1), bubble_id: '100x1', updated_at: at, status_pcp: null, data_real_de_entrega: null }],
  allocations: [{ id: id(2), projeto_id: id(1), celula_id: id(3), updated_at: at, forms_ids: [id(4)] }], cells: [{ id: id(3), bubble_id: '100x3' }],
  forms: [{ id: id(4), bubble_id: '100x4' }], users: [{ id: id(5), bubble_id: '100x5', status: 'ativo' }, { id: id(6), bubble_id: '100x6', status: 'ativo' }],
  links: [{ celula_id: id(3), identidade_id: id(5) }], records: [], assignments: [] });
const source = () => ({ cutoff, assignments: [{ _id: '100x11', ProjetoRM: '100x1', Celula: '100x3', Form: '100x4', Aprovador: '100x5',
  'Created Date': '2026-10-01T10:00:00.000001Z', 'Modified Date': '2026-10-29T10:00:00.000001Z', Status: 'Aprovado', Parecer: 'Private text must not enter a plan' }] as Record<string, any>[] });

test('reviewer bootstrap groups identical context duplicates and retains every source ID with deterministic UUID/provenance', () => {
  const raw = source(); raw.assignments.push({ ...raw.assignments[0], _id: '100x10', 'Created Date': '2026-10-01T10:00:00.000000Z', 'Modified Date': '2026-10-29T10:00:00.000002Z' });
  const plan = prepareFormReviewerBootstrap(raw, lookup()), entry = plan.entries[0];
  assert.deepEqual(entry.payload.legacy_source_ids, ['100x10', '100x11']); assert.equal(entry.payload.bubble_id, '100x10');
  assert.equal(entry.payload.created_at, '2026-10-01T10:00:00.000000Z'); assert.equal(entry.payload.bubble_modified_at, '2026-10-29T10:00:00.000002Z');
  assert.equal(entry.payload.expected_project_updated_at, at); assert.equal(entry.payload.expected_allocation_updated_at, at);
  assert.equal(entry.payload.id, formReviewerBootstrapId(id(1), id(3), id(4))); assert.equal(entry.payload.avaliador_user_id, id(5));
  assert.deepEqual(plan.counts, { source: 2, contexts: 1, source_ids: 2, existing: 0, linked: 1, unlinked: 0, closed: 0, approved: 0, without_records: 1, quarantined_rows: 0 });
  const reordered = prepareFormReviewerBootstrap({ ...raw, assignments: [...raw.assignments].reverse() }, lookup());
  assert.deepEqual(reordered, plan); assert.ok(!JSON.stringify(plan).includes('Private text'));
});

test('missing contexts/references and conflicting reviewers are quarantined without filling context from a record pointer', () => {
  for (const [change, reason] of [[{ ProjetoRM: undefined, Registro_Formulario: '100x90' }, 'missing_context'], [{ ProjetoRM: '100x99' }, 'project_not_imported'],
    [{ Celula: '100x99' }, 'unresolved_context_reference'], [{ Form: '100x99' }, 'unresolved_context_reference'], [{ Aprovador: undefined }, 'missing_reviewer'],
    [{ Aprovador: '100x99' }, 'unresolved_reviewer'], [{ 'Modified Date': '2027-01-01T00:00:00Z' }, 'invalid_source_dates_or_cutoff']] as const) {
    const raw = source(); Object.assign(raw.assignments[0], change); const plan = prepareFormReviewerBootstrap(raw, lookup());
    assert.equal(plan.entries.length, 0); assert.equal(plan.quarantine[0].reason, reason); assert.equal(plan.counts.quarantined_rows, 1);
  }
  const missing = lookup(); missing.allocations = []; assert.equal(prepareFormReviewerBootstrap(source(), missing).quarantine[0].reason, 'allocation_missing');
  const raw = source(); raw.assignments.push({ ...raw.assignments[0], _id: '100x12', Aprovador: '100x6' });
  const conflict = prepareFormReviewerBootstrap(raw, lookup()); assert.equal(conflict.entries.length, 0); assert.deepEqual(conflict.quarantine[0], { source_ids: ['100x11', '100x12'], reason: 'conflicting_reviewers' });
  raw.assignments[1].Aprovador = undefined; assert.equal(prepareFormReviewerBootstrap(raw, lookup()).quarantine[0].reason, 'conflicting_reviewers');
  const large = source(); large.assignments = Array.from({ length: 101 }, (_, index) => ({ ...large.assignments[0], _id: `100x${index + 1000}` }));
  assert.equal(prepareFormReviewerBootstrap(large, lookup()).quarantine[0].reason, 'too_many_duplicate_sources');
});

test('historical unlinked/inactive/closed/approved assignments remain metadata and never rewrite records or access links', () => {
  const db = lookup(); db.projects[0].status_pcp = 'cancelado'; db.allocations[0].forms_ids = []; db.users[0].status = 'inativo'; db.links = [];
  db.records = [{ id: id(10), projeto_id: id(1), celula_id: id(3), form_id: id(4), status: 'aprovado', avaliador_user_id: id(6) },
    { id: id(11), projeto_id: id(1), celula_id: id(3), form_id: id(4), status: 'em_an_lise', avaliador_user_id: null }];
  const before = structuredClone(db), plan = prepareFormReviewerBootstrap(source(), db), entry = plan.entries[0];
  assert.equal(entry.linked, false); assert.equal(entry.closed, true); assert.equal(entry.approved, true); assert.equal(entry.reviewer_active, false);
  assert.equal(entry.reviewer_cell_linked, false); assert.equal(entry.record_count, 2); assert.equal(entry.records_without_evaluator, 1); assert.equal(entry.records_with_other_evaluator, 1);
  assert.deepEqual(db, before); assert.equal(plan.counts.unlinked, 1); assert.equal(plan.counts.closed, 1); assert.equal(plan.counts.approved, 1);
});

test('matching imported assignments replay with existing IDs; local changes or another provenance are never overwritten', () => {
  const db = lookup(), initial = prepareFormReviewerBootstrap(source(), db), payload = initial.entries[0].payload;
  const existing = { ...payload, id: id(19), sync_source: 'bubble', updated_at: at };
  db.assignments = [existing]; const replay = prepareFormReviewerBootstrap(source(), db);
  assert.equal(replay.entries[0].payload.id, id(19)); assert.equal(replay.counts.existing, 1);
  for (const change of [{ sync_source: 'supabase' }, { avaliador_user_id: id(6) }, { legacy_source_ids: ['100x9', '100x11'] }, { created_at: cutoff }]) {
    db.assignments = [{ ...existing, ...change }]; const conflict = prepareFormReviewerBootstrap(source(), db);
    assert.equal(conflict.entries.length, 0); assert.equal(conflict.quarantine[0].reason, 'existing_assignment_conflict');
  }
});

test('ambiguous crosswalks and repeated source IDs refuse a partial plan', () => {
  const duplicate = source(); duplicate.assignments.push({ ...duplicate.assignments[0] }); assert.throws(() => prepareFormReviewerBootstrap(duplicate, lookup()), /Duplicate source/);
  const db = lookup(); db.users.push({ ...db.users[0], id: id(7) }); assert.throws(() => prepareFormReviewerBootstrap(source(), db), /Ambiguous/);
});

test('source reader is bounded GET-only pinned to Live and retains source data without calling generic sync or writes', async () => {
  const calls: { url: URL; init?: RequestInit }[] = [];
  const fetcher = (async (url: URL, init: RequestInit) => {
    calls.push({ url, init }); const cursor = Number(url.searchParams.get('cursor'));
    return Response.json({ response: { cursor, remaining: cursor ? 0 : 1, results: [{ ...source().assignments[0], _id: cursor ? '100x12' : '100x11' }] } });
  }) as typeof fetch;
  const rows = await readBubbleFormReviewerAssignments({ baseUrl: 'https://rmmi.bubbleapps.io/api/1.1', token: 'test-only', cutoff, fetcher });
  assert.equal(rows.length, 2); assert.deepEqual(calls.map(call => call.init?.method), ['GET', 'GET']);
  assert.deepEqual(calls.map(call => call.url.pathname), ['/api/1.1/obj/aprovacao_form', '/api/1.1/obj/aprovacao_form']);
  assert.equal(calls[1].url.searchParams.get('cursor'), '1'); assert.ok(calls.every(call => call.init?.redirect === 'error'));
  for (const baseUrl of ['https://rmmi.bubbleapps.io/version-test/api/1.1', 'https://other.bubbleapps.io/api/1.1', 'http://rmmi.bubbleapps.io/api/1.1']) {
    await assert.rejects(readBubbleFormReviewerAssignments({ baseUrl, token: 'test-only', cutoff, fetcher }), /pinned/);
  }
  await assert.rejects(readBubbleFormReviewerAssignments({ baseUrl: 'https://rmmi.bubbleapps.io/api/1.1', token: 'test-only', cutoff,
    fetcher: (async () => Response.json({ response: { cursor: 0, remaining: 1, results: [] } })) as typeof fetch }), /stalled/);
});

test('reviewed SQL defaults to rollback, calls the insert primitive and proves exact output plus all previous snapshots', () => {
  const plan = prepareFormReviewerBootstrap(source(), lookup()), sql = formReviewerBootstrapSql(plan);
  assert.match(sql, /rollback;\s*$/); assert.match(formReviewerBootstrapSql(plan, true), /commit;\s*$/);
  assert.match(sql, /rm_bootstrap_form_reviewer_assignment_v1\(item\)/); assert.doesNotMatch(sql, /\bupdate public\.|\bdelete from\b/i);
  assert.match(sql, /Bootstrap changed an existing assignment/); assert.match(sql, /Imported assignment differs/); assert.match(sql, /different assignment set/);
  assert.match(sql, /actual_assignment_count/); assert.match(sql, /preserved_source_ids/); assert.match(sql, /count\(\*\).*reviewer_bootstrap_before/);
  const encoded = sql.match(/decode\('([A-Za-z0-9+/=]+)','base64'\)/)![1];
  assert.deepEqual(JSON.parse(Buffer.from(encoded, 'base64').toString('utf8')), plan.entries.map(entry => entry.payload));
  const tampered = { ...plan, counts: { ...plan.counts, contexts: '0; delete from public.rm_users; --' } } as any;
  assert.ok(!formReviewerBootstrapSql(tampered).includes('delete from public.rm_users'));
});

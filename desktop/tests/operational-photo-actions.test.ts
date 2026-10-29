import test from 'node:test';
import assert from 'node:assert/strict';
import { manageOperationalPhotosSchema } from '../src/server/web/operational-photo-policy';
import { createOperationalPhotoActions } from '../src/server/web/operational-photo-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
const common = { submissionId: id(1), projeto_id: id(2), celula_projeto_id: id(3), expected_project_updated_at: version,
  expected_allocation_updated_at: version, expected_photos_version: 'a'.repeat(64) };
const add = { ...common, action: 'add' as const, items: [{ id: id(4), cadastro_foto_id: id(5) }] };
const target = { ...common, foto_id: id(4), expected_foto_updated_at: version };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.planning.manage', 'em.photos.read'];

function fixture(options: { role?: string; capabilities?: CorporateCapability[]; failure?: string; transform?: (value: WebActionResult) => WebActionResult } = {}) {
  const calls: any[][] = [], auth: string[] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(9), nome: 'Pessoa', perfil: options.role || 'administrador' },
    sso: { sessionHash: 'hash', bindingId: id(10), subject: id(11), capabilities: options.capabilities || caps } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createOperationalPhotoActions({
    actionUser: async capability => { auth.push(capability); return options.failure === 'CORP_FORBIDDEN' ? { ok: false, code: options.failure, error: 'Denied' } : access; },
    mutate: async (...args) => {
      calls.push(args);
      const value: WebActionResult = options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'manage_operational_photos', id: id(3), projeto_id: id(2), updated_at: version, idempotent_replay: false,
        record: { projeto_id: id(2), celula_projeto_id: id(3), action: args[2].action, photos_version: 'b'.repeat(64), changed_ids: [id(4)], private_snapshot: 'excluded' },
      } };
      return options.transform ? options.transform(value) : value;
    },
  });
  return { ...actions, auth, calls };
}

test('operational photo payloads preserve opaque versions, raw tags and stable IDs without accepting extra actor/media fields', () => {
  assert.deepEqual(manageOperationalPhotosSchema.parse(add), add);
  const tag = { ...target, action: 'tag', tag: '  Tag à preservar  ' };
  assert.deepEqual(manageOperationalPhotosSchema.parse(tag), tag);
  for (const body of [{ ...add, actor_id: id(8) }, { ...add, foto_url: 'https://example.test/a.jpg' }, { ...add, expected_project_updated_at: null },
    { ...target, action: 'retire', tag: 'not permitted' }, { ...target, action: 'restore', selected: false }, { ...tag, tag: 'a'.repeat(2001) },
    { ...add, items: [] }, { ...add, items: [add.items[0], { id: id(12), cadastro_foto_id: id(5) }] },
    { ...add, items: [add.items[0], { id: id(4), cadastro_foto_id: id(12) }] }]) assert.equal(manageOperationalPhotosSchema.safeParse(body).success, false);
  assert.equal(manageOperationalPhotosSchema.safeParse({ ...target, action: 'retire' }).success, true);
  assert.equal(manageOperationalPhotosSchema.safeParse({ ...target, action: 'restore' }).success, true);
});

test('operational management requires planning write plus scoped reads, without an engineering catalog grant', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ failure: 'CORP_FORBIDDEN' }),
    ...(['em.projects.read', 'em.planning.read', 'em.photos.read'] as const).map(cap => fixture({ capabilities: caps.filter(value => value !== cap) }))]) {
    assert.equal((await f.manageOperationalPhotos(add)).ok, false); assert.deepEqual(f.auth, ['em.planning.manage']); assert.equal(f.calls.length, 0);
  }
  const planner = fixture({ role: 'padr_o' }); assert.equal((await planner.manageOperationalPhotos(add)).ok, true);
  assert.equal(planner.calls[0][3], 'em.planning.manage');
});

test('each action uses the common gateway, preserves retry body and strips private snapshots', async () => {
  const f = fixture();
  for (const body of [add, { ...target, action: 'tag', tag: null }, { ...target, action: 'retire' }, { ...target, action: 'restore' }]) {
    const result = await f.manageOperationalPhotos(body); assert.ok(result.ok); assert.equal(result.data.record.private_snapshot, undefined);
    assert.deepEqual(f.calls.at(-1)?.[2], body); assert.equal(f.calls.at(-1)?.[1], 'manage_operational_photos');
  }
  await f.manageOperationalPhotos(add); assert.deepEqual(f.calls[0], f.calls[4]);
  for (const code of ['PT409', 'UNAVAILABLE', 'CORP_UNAVAILABLE', '42501']) {
    const result = await fixture({ failure: code }).manageOperationalPhotos(add); assert.ok(!result.ok); assert.equal(result.code, code);
  }
});

test('unrelated operation, context or changed photo IDs cannot confirm a successful management action', async () => {
  for (const patch of [{ operation: 'save_project_route' }, { id: id(99) }, { projeto_id: id(99) }, { updated_at: 'bad' },
    { record: {} }, { record: { projeto_id: id(2), celula_projeto_id: id(3), action: 'tag', photos_version: 'b'.repeat(64), changed_ids: [id(4)] } },
    { record: { projeto_id: id(2), celula_projeto_id: id(3), action: 'add', photos_version: 'b'.repeat(64), changed_ids: [id(99)] } },
    { record: { projeto_id: id(2), celula_projeto_id: id(3), action: 'add', photos_version: 'b'.repeat(64), changed_ids: [id(4), id(4)] } }]) {
    const f = fixture({ transform: value => value.ok ? { ok: true, data: { ...value.data, ...patch } } : value });
    const result = await f.manageOperationalPhotos(add); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
});

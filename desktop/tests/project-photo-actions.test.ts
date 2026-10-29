import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectPhotoActions } from '../src/server/web/project-photo-mutations';
import { projectPhotoSelectionSchema, projectPhotoFilters } from '../src/server/web/project-photo-policy';
import { freezeEngineeringRequest } from '../src/components/web/engineering-model';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
const body = { submissionId: id(1), projeto_id: id(2), foto_id: id(3), expected_updated_at: version, selected: true };
const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.projects.manage', 'em.photos.read'];

function fixture(options: { profile?: string; caps?: CorporateCapability[]; failure?: string; response?: (value: WebActionResult) => WebActionResult } = {}) {
  const calls: any[][] = []; const auth: string[] = [];
  const session = { client: {}, user: { id: id(4) }, profile: { id: id(5), nome: 'Pessoa', perfil: options.profile || 'administrador' },
    sso: { sessionHash: 'hash', bindingId: id(6), subject: id(7), capabilities: options.caps || capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createProjectPhotoActions({
    actionUser: async capability => { auth.push(capability); return options.failure === 'CORP_FORBIDDEN' ? { ok: false, code: options.failure, error: 'Denied' } : session; },
    mutate: async (...args) => {
      calls.push(args);
      const value: WebActionResult = options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'set_project_photo_selection', id: id(3), projeto_id: id(2), updated_at: version, idempotent_replay: false,
        record: { foto_id: id(3), projeto_id: id(2), selecao_relatorio: args[2].selected, updated_at: version, before_record: 'private' },
      } };
      return options.response ? options.response(value) : value;
    },
  });
  return { ...actions, calls, auth };
}

test('photo selection rejects actor injection, coercion and missing exact version; preserves timestamp text', () => {
  assert.deepEqual(projectPhotoSelectionSchema.parse(body), body);
  for (const patch of [{ selected: 'true' }, { selected: 1 }, { foto_id: 'bad' }, { actor_id: id(4) }, { expected_updated_at: null }, { expected_updated_at: '' }]) {
    assert.equal(projectPhotoSelectionSchema.safeParse({ ...body, ...patch }).success, false);
  }
  assert.deepEqual(projectPhotoFilters({ selection: 'selected', photoOrder: 'selected' }), { selectedOnly: true, selectedFirst: true });
  assert.deepEqual(projectPhotoFilters({ selection: 'other', photoOrder: 'sql' }), { selectedOnly: false, selectedFirst: false });
});

test('photo selection requires management, photo/project visibility and an operational write profile', async () => {
  for (const f of [fixture({ profile: 'auditor' }), fixture({ caps: capabilities.filter(cap => cap !== 'em.photos.read') }),
    fixture({ caps: capabilities.filter(cap => cap !== 'em.projects.read') }), fixture({ failure: 'CORP_FORBIDDEN' })]) {
    const result = await f.setProjectPhotoSelection(body);
    assert.equal(result.ok, false); assert.deepEqual(f.auth, ['em.projects.manage']); assert.equal(f.calls.length, 0);
  }
  assert.equal((await fixture({ profile: 'padr_o' }).setProjectPhotoSelection(body)).ok, true);
});

test('selection and deselection use the existing gateway; retry retains protocol and strips private snapshots', async () => {
  const f = fixture(); const frozen = freezeEngineeringRequest(body);
  const result = await f.setProjectPhotoSelection(frozen); await f.setProjectPhotoSelection(frozen);
  assert.deepEqual(f.calls[0], f.calls[1]); assert.equal(f.calls[0][1], 'set_project_photo_selection');
  assert.equal(f.calls[0][3], 'em.projects.manage'); assert.deepEqual(f.calls[0][2], body);
  assert.ok(result.ok); assert.equal(result.data.record.before_record, undefined);
  assert.equal((await f.setProjectPhotoSelection({ ...body, selected: false })).ok, true);
  await f.setProjectPhotoSelection({ ...body, modified_by_id: id(4) }); assert.equal(f.calls.length, 3);
  assert.equal(Object.isFrozen(frozen), true); assert.equal(frozen.expected_updated_at, version);
});

test('conflicts and ambiguous responses remain explicit; an unrelated/stale receipt cannot confirm selection', async () => {
  for (const code of ['PT409', 'UNAVAILABLE', '42501', 'CORP_UNAVAILABLE']) {
    const result = await fixture({ failure: code }).setProjectPhotoSelection(body);
    assert.ok(!result.ok); assert.equal(result.code, code);
  }
  for (const patch of [{ operation: 'save_project' }, { id: id(9) }, { projeto_id: id(9) }, { updated_at: 'bad' },
    { record: {} }, { record: { foto_id: id(3), projeto_id: id(2), selecao_relatorio: false, updated_at: version } },
    { record: { foto_id: id(3), projeto_id: id(2), selecao_relatorio: true, updated_at: '2026-10-29T18:03:25Z' } }]) {
    const result = await fixture({ response: value => value.ok ? { ok: true, data: { ...value.data, ...patch } } : value }).setProjectPhotoSelection(body);
    assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectEquipmentActions } from '../src/server/web/project-equipment-mutations';
import { projectEquipmentEditableFields, projectEquipmentTextFields, saveProjectEquipmentSchema } from '../src/server/web/project-equipment-policy';
import { freezeEngineeringRequest } from '../src/components/web/engineering-model';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', hash = 'a'.repeat(64);
const input = { submissionId: id(1), projeto_id: id(2), equipamento_id: id(3), expected_project_updated_at: version,
  expected_equipment_updated_at: '2026-10-30T15:30:02.000001Z', expected_context_version: hash, confirm_change: true as const,
  changes: { potencia: '150 CV / 110 kW', fp: '-0.12345678901234567890' } };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.projects.manage'];
type Options = { role?: string; capabilities?: CorporateCapability[]; failure?: string; changedFields?: string[];
  patch?: (value: WebActionResult) => WebActionResult };

function fixture(options: Options = {}) {
  const auth: string[] = [], calls: any[][] = [], capabilities = options.capabilities ?? caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role ?? 'administrador' },
    sso: { sessionHash: 'session', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createProjectEquipmentActions({
    actionUser: async capability => { auth.push(capability); return capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' }; },
    mutate: async (...args) => {
      calls.push(args); const request = args[2];
      const result = (options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'save_project_equipment', id: request.equipamento_id as string, projeto_id: request.projeto_id as string,
        updated_at: version, idempotent_replay: calls.length > 1,
        record: { projeto_id: request.projeto_id, equipamento_id: request.equipamento_id, project_updated_at: version,
          changed_fields: options.changedFields ?? Object.keys(request.changes as object), context_version: hash,
          private_audit: { before: 'not public' }, actor_auth_user_id: id(10), removed_legacy_flags: ['sim'] },
        private_journal: 'not public',
      } }) as WebActionResult;
      return options.patch ? options.patch(result) : result;
    },
  });
  return { ...actions, calls, auth };
}

test('technical changes preserve every supported text, decimal precision and explicit nullable clear', async () => {
  assert.equal(projectEquipmentTextFields.length, 21); assert.equal(projectEquipmentEditableFields.length, 25);
  const texts = Object.fromEntries(projectEquipmentTextFields.map(key => [key, '  220/380 V; 50–60 Hz; ligação Δ/Y  '])) as Record<typeof projectEquipmentTextFields[number], string>;
  const changes = { ...texts, placa_motor: 's___placa', fp: '-123456789012345678901234567890.12345678901234567890', fs: '+1.1500', numero_cabos: 2147483647 };
  const request = { ...input, changes }, f = fixture(), result = await f.saveProjectEquipment(request);
  assert.ok(result.ok); assert.deepEqual(f.calls[0][2], request);
  assert.equal(f.calls[0][2].changes.fp, changes.fp); assert.equal(f.calls[0][2].changes.potencia, texts.potencia);
  const cleared = Object.fromEntries(projectEquipmentEditableFields.map(key => [key, null]));
  assert.deepEqual(saveProjectEquipmentSchema.parse({ ...input, changes: cleared }).changes, cleared);
  for (const numero_cabos of [0, 2147483647]) assert.ok(saveProjectEquipmentSchema.safeParse({ ...input, changes: { numero_cabos } }).success);
  for (const fp of ['-1.5', '-0.5', '+0.00000000000000000001', '12345678901234567890']) {
    assert.equal(saveProjectEquipmentSchema.parse({ ...input, changes: { fp } }).changes.fp, fp);
  }
});

test('technical requests are partial and strict, never accepting identities, planning or removed receiving flags', async () => {
  const forbidden = ['id', 'projeto_id', 'equipamento_id', 'tipo_equipamento_id', 'bubble_id', 'sync_source', 'updated_at',
    'created_at', 'actor_id', 'auth_user_id', 'cadastrado_por_id', 'desmontar_para_orcar', 'ensaiar_antes_desmontar', 'teste_intermediario'];
  const invalid: unknown[] = [
    {}, null, { ...input, changes: {} }, { ...input, changes: null }, { ...input, changes: [] },
    { ...input, changes: { fabricante: undefined } }, { ...input, changes: { fabricante: 'WEG', modelo: undefined } },
    ...forbidden.map(key => ({ ...input, changes: { potencia: '10 CV', [key]: id(99) } })),
    ...['actor_id', 'auth_user_id', 'tipo_equipamento_id', 'private_journal', 'created_by_user_id'].map(key => ({ ...input, [key]: id(99) })),
    ...['false', false, 1, null, undefined].map(confirm_change => ({ ...input, confirm_change })),
    ...['submissionId', 'projeto_id', 'equipamento_id'].map(key => ({ ...input, [key]: 'invalid' })),
    ...['expected_project_updated_at', 'expected_equipment_updated_at'].flatMap(key => [
      { ...input, [key]: '2026-10-30' }, { ...input, [key]: '2026-10-30T12:00:00' }, { ...input, [key]: null }]),
    ...[hash.toUpperCase(), 'g'.repeat(64), 'a'.repeat(63), null, undefined].map(expected_context_version => ({ ...input, expected_context_version })),
    { ...input, changes: { potencia: 10 } }, { ...input, changes: { potencia: ['1', '2'] } },
    { ...input, changes: { potencia: 'x'.repeat(10001) } }, { ...input, changes: { potencia: 'before' + String.fromCharCode(0) + 'after' } },
    ...['1,25', '1e3', 'Infinity', 'NaN', ' 1', '1.', '.5', '1'.repeat(31), '0.' + '1'.repeat(21)].map(fp => ({ ...input, changes: { fp } })),
    { ...input, changes: { fp: 0.5 } }, { ...input, changes: { fs: true } },
    ...[-1, 2147483648, 1.5, '2', Infinity, NaN].map(numero_cabos => ({ ...input, changes: { numero_cabos } })),
    { ...input, changes: { placa_motor: 'com_placa' } },
  ];
  for (const request of invalid) {
    const f = fixture(), result = await f.saveProjectEquipment(request);
    assert.ok(!result.ok, JSON.stringify(request)); assert.equal(result.code, 'INVALID_INPUT'); assert.equal(f.calls.length, 0);
  }
  const one = { ...input, changes: { modelo: 'modelo atual' } }, f = fixture();
  assert.equal((await f.saveProjectEquipment(one)).ok, true); assert.deepEqual(f.calls[0][2].changes, one.changes);
});

test('technical authorization precedes parsing and requires project management, portal/project read and local role', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ role: 'mobile' }), fixture({ role: 'supervisor' }),
    ...caps.map(capability => fixture({ capabilities: caps.filter(value => value !== capability) })),
    fixture({ capabilities: ['em.portal.read', 'em.projects.read', 'em.engineering.manage', 'em.approvals.decide'] })]) {
    const result = await f.saveProjectEquipment(input);
    assert.ok(!result.ok); assert.deepEqual(f.auth, ['em.projects.manage']); assert.equal(f.calls.length, 0);
  }
  const unauthenticated = fixture({ capabilities: [] }), denied = await unauthenticated.saveProjectEquipment({});
  assert.ok(!denied.ok); assert.equal(denied.code, 'CORP_FORBIDDEN'); assert.equal(denied.fieldErrors, undefined);
  for (const role of ['administrador', 'padr_o']) assert.equal((await fixture({ role }).saveProjectEquipment(input)).ok, true);
});

test('technical retries retain exact microsecond versions, canonical UUIDs, decimals and current SSO binding', async () => {
  const f = fixture(), upper = { ...input, submissionId: input.submissionId.toUpperCase(), projeto_id: input.projeto_id.toUpperCase(), equipamento_id: input.equipamento_id.toUpperCase() };
  const frozen = freezeEngineeringRequest(upper), first = await f.saveProjectEquipment(frozen), retry = await f.saveProjectEquipment(frozen);
  assert.ok(first.ok && retry.ok); assert.equal(retry.data.idempotent_replay, true); assert.deepEqual(f.calls[0], f.calls[1]);
  assert.deepEqual(f.calls[0][2], input); assert.equal(f.calls[0][1], 'save_project_equipment');
  assert.equal(f.calls[0][3], 'em.projects.manage'); assert.equal(f.calls[0][4].bindingId, id(12)); assert.equal(f.calls[0][4].subject, id(13));
  assert.equal(f.calls[0][2].expected_equipment_updated_at, '2026-10-30T15:30:02.000001Z');
  assert.deepEqual(Object.keys(first.data).sort(), ['id', 'idempotent_replay', 'operation', 'projeto_id', 'record', 'updated_at']);
  assert.deepEqual(first.data.record, { projeto_id: id(2), equipamento_id: id(3), project_updated_at: version,
    changed_fields: ['potencia', 'fp'], context_version: hash });
});

test('technical no-op receipts and backend conflict/authorization/retry errors retain their semantics', async () => {
  const unchanged = await fixture({ changedFields: [] }).saveProjectEquipment(input);
  assert.ok(unchanged.ok); assert.deepEqual(unchanged.data.record.changed_fields, []);
  for (const code of ['PT409', 'P0002', '22023', '42501', 'UNAVAILABLE', 'CORP_UNAVAILABLE', 'CORP_FORBIDDEN']) {
    const f = fixture({ failure: code }), result = await f.saveProjectEquipment(input);
    assert.ok(!result.ok); assert.equal(result.code, code); assert.equal(result.error, 'Sanitized'); assert.equal(f.calls.length, 1);
  }
});

test('technical receipts cannot confirm another context or expose malformed/extra changed fields', async () => {
  const patches = [
    { operation: 'save_project' }, { id: id(99) }, { id: 'invalid' }, { projeto_id: id(99) },
    { updated_at: 'invalid' }, { idempotent_replay: 'true' }, { record: null }, { record: [] },
    ...['projeto_id', 'equipamento_id'].flatMap(key => [{ nested: { [key]: id(99) } }, { nested: { [key]: 'invalid' } }]),
    { nested: { project_updated_at: 'invalid' } }, { nested: { context_version: 'wrong' } },
    { nested: { changed_fields: ['potencia', 'potencia'] } }, { nested: { changed_fields: ['modelo'] } },
    { nested: { changed_fields: ['actor_id'] } }, { nested: { changed_fields: null } },
  ];
  for (const patch of patches) {
    const f = fixture({ patch: value => value.ok ? { ok: true, data: { ...value.data, ...patch,
      ...('nested' in patch ? { record: { ...value.data.record, ...patch.nested } } : {}) } } as unknown as WebActionResult : value });
    const result = await f.saveProjectEquipment(input);
    assert.ok(!result.ok, JSON.stringify(patch)); assert.equal(result.code, 'UNAVAILABLE'); assert.equal('data' in result, false);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createCapacityActions } from '../src/server/web/capacity-mutations';
import { createCapacityData } from '../src/server/web/capacity-data';
import { capacityFiltersSchema, saveCapacityBookingsSchema, saveCapacityResourceSchema } from '../src/server/web/capacity-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const stamp = '2026-11-17T13:05:06.123456+00:00', version = 'a'.repeat(64);
const caps: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.projects.read', 'em.planning.manage'];
const resource = { id: id(1), name: 'Bancada de ensaio', kind: 'maquina' as const, active: true, weekly_minutes: [480, 480, 480, 480, 480, 0, 0], exceptions: [{ date: '2026-11-20', minutes: 0, label: 'Manutenção programada' }], updated_at: stamp, version, booked_days: [{ date: '2026-11-17', minutes: 120 }] };
const resourceInput = { submissionId: id(90), id: id(1), expected_version: version, name: resource.name, kind: resource.kind, active: resource.active, weekly_minutes: resource.weekly_minutes, exceptions: resource.exceptions, acknowledge_overload: false, reason: 'Disponibilidade informada pela oficina' };
const bookingInput = { submissionId: id(91), resource_id: id(1), expected_resource_version: version, allocation_id: id(3), expected_allocation_updated_at: stamp, expected_project_version: version, days: [{ date: '2026-11-17', minutes: 120 }], acknowledge_overload: false, reason: 'Programação da bancada' };
const booking = { id: id(4), resource_id: id(1), allocation_id: id(3), project_id: id(2), numero_projeto: 'OS local', cell_name: 'Ensaios', status: 'em_dia', retired: false, project_closed: false, planned_start: stamp, planned_end: stamp, project_working: true, day: '2026-11-17', minutes: 120, updated_at: stamp, allocation_updated_at: stamp };
const filters = { start: '2026-11-17', days: 14 as const, project_id: null };
const snapshot = () => ({ as_of: stamp, start: filters.start, days: filters.days, complete: true, totals: { resources: 1, bookings: 1 }, resources: [structuredClone(resource)], bookings: [structuredClone(booking)], project_plan: null });
function projectPlan() {
  return { as_of: stamp, filters: { project_id: id(2), cell_id: null, include_closed: true }, total: 1, complete: true,
    projects: [{ id: id(2), numero: 'OS local', nome: null, updated_at: stamp, plan_version: version, closed: false, planned_start: stamp, planned_end: stamp, contract_date: null, renegotiated_date: null }],
    cells: [{ id: id(5), nome: 'Ensaios' }], items: [{ id: id(3), projeto_id: id(2), celula_id: id(5), numero_projeto: 'OS local', cliente_nome_export: null, celula_nome: 'Ensaios', status: 'em_dia', bloqueada: 'n_o', motivo_bloqueio: null, visibilidade: true, prioridade: null, indice: 1, posicao: 1, responsavel_nome: null, data_inicio: stamp, data_limite: stamp, updated_at: stamp, can_edit: true }], links: [], baseline: null, settings: [] };
}
function reader(data: unknown, capabilities = caps) {
  const calls: unknown[][] = [], client = { rpc: async (...args: unknown[]) => { calls.push(args); return { data, error: null }; } } as unknown as SupabaseClient;
  return { ...createCapacityData(client, capabilities), calls };
}
function writer(profile = 'administrador', capabilities = caps, supplied?: WebActionResult) {
  const calls: unknown[][] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'PCP', perfil: profile }, sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  return { ...createCapacityActions({ actionUser: async () => access, mutate: async (...args) => {
    calls.push(args); const operation = args[1];
    return supplied ?? { ok: true, data: { operation, id: id(1), projeto_id: operation === 'save_capacity_resource' ? null : id(2), updated_at: stamp, idempotent_replay: false, record: operation === 'save_capacity_resource' ? { resource_changed: true } : { changed_days: 1 } } };
  } }), calls };
}

test('capacity distinguishes explicit units, exact minute quantities, civil dates and versions', () => {
  assert.ok(saveCapacityResourceSchema.safeParse(resourceInput).success);
  assert.ok(saveCapacityResourceSchema.safeParse({ ...resourceInput, id: null, expected_version: null }).success);
  assert.ok(saveCapacityBookingsSchema.safeParse(bookingInput).success);
  assert.ok(saveCapacityBookingsSchema.safeParse({ ...bookingInput, days: [{ date: '2026-11-17', minutes: 0 }] }).success);
  assert.ok(capacityFiltersSchema.safeParse(filters).success);
  for (const input of [{ ...filters, start: '2026-02-30' }, { ...filters, days: 31 }, { ...filters, start: '2200-12-31' }]) assert.equal(capacityFiltersSchema.safeParse(input).success, false);
});
test('resource and booking writes reject ambiguous effort, identity overrides, duplicate days and unknown keys', () => {
  for (const patch of [{ expected_version: null }, { id: null }, { weekly_minutes: [480] }, { weekly_minutes: [480, 480, 480, 480, 480, -1, 0] }, { kind: 'equipe' }, { active: 'true' }, { name: 'X\nY' }, { auth_user_id: id(8) }, { hours: 8 }, { exceptions: [...resource.exceptions, ...resource.exceptions] }, { exceptions: [{ date: '2026-11-20', minutes: 1441, label: 'Parada' }] }]) assert.equal(saveCapacityResourceSchema.safeParse({ ...resourceInput, ...patch }).success, false);
  for (const patch of [{ expected_project_version: 'old' }, { acknowledge_overload: 'yes' }, { days: [...bookingInput.days, ...bookingInput.days] }, { days: [{ date: stamp, minutes: 1 }] }, { days: [{ date: '2026-11-17', minutes: 1.5 }] }, { days: [{ date: '2026-11-17', minutes: 1441 }] }, { reserve_all_projects: true }]) assert.equal(saveCapacityBookingsSchema.safeParse({ ...bookingInput, ...patch }).success, false);
});
test('capacity boundary requires every read capability before performing a request', async () => {
  for (const missing of caps.slice(0, 3)) { const f = reader(snapshot(), caps.filter(cap => cap !== missing)); await assert.rejects(() => f.getCapacitySnapshot(filters), /Acesso/); assert.equal(f.calls.length, 0); }
  const f = reader(snapshot()); const result = await f.getCapacitySnapshot(filters);
  assert.equal(result.bookings[0].updated_at, stamp); assert.deepEqual(result.resources[0].weekly_minutes, resource.weekly_minutes); assert.equal(f.calls.length, 1);
});
test('capacity rejects partial, mismatched, duplicated and unreferenced snapshots', async () => {
  const data = snapshot();
  for (const raw of [{ ...data, complete: false }, { ...data, start: '2026-11-18' }, { ...data, totals: { resources: 0, bookings: 1 } }, { ...data, resources: [resource, resource] }, { ...data, bookings: [booking, booking] }, { ...data, bookings: [{ ...booking, resource_id: id(99) }] }, { ...data, bookings: [{ ...booking, day: '2026-12-01' }] }, { ...data, resources: [{ ...resource, weekly_minutes: [] }] }]) await assert.rejects(() => reader(raw).getCapacitySnapshot(filters), /consultar/);
  const empty = { ...data, complete: false, resources: [], bookings: [], project_plan: null, totals: { resources: 201, bookings: 10001 } };
  assert.equal((await reader(empty).getCapacitySnapshot(filters)).complete, false);
});
test('capacity selected project never removes the load from other projects and reuses strict Gantt validation', async () => {
  const data = { ...snapshot(), resources: [{ ...resource, booked_days: [{ date: '2026-11-17', minutes: 240 }] }], project_plan: projectPlan(), bookings: [booking, { ...booking, id: id(7), allocation_id: id(6), project_id: id(9) }], totals: { resources: 1, bookings: 2 } };
  const result = await reader(data).getCapacitySnapshot({ ...filters, project_id: id(2) });
  assert.equal(result.bookings.length, 2); assert.equal(result.project_plan!.items[0].updated_at, stamp);
  const readonly = await reader(data, caps.filter(cap => cap !== 'em.planning.manage')).getCapacitySnapshot({ ...filters, project_id: id(2) });
  assert.equal(readonly.project_plan!.items[0].can_edit, false);
  for (const raw of [{ ...data, project_plan: { ...projectPlan(), filters: { project_id: id(99), cell_id: null, include_closed: true } } }, { ...data, bookings: [{ ...booking, allocation_updated_at: '2026-11-17T14:00:00+00:00' }] }]) await assert.rejects(() => reader(raw).getCapacitySnapshot({ ...filters, project_id: id(2) }), /consultar/);
});
test('capacity writers recheck capabilities, local roles and preserve frozen request bodies', async () => {
  for (const f of [writer('auditor'), writer('mobile'), ...caps.map(cap => writer('administrador', caps.filter(candidate => candidate !== cap)))]) { const result = await f.saveCapacityResource(resourceInput); assert.ok(!result.ok); assert.equal(result.code, '42501'); assert.equal(f.calls.length, 0); }
  const f = writer(); assert.ok((await f.saveCapacityResource(resourceInput)).ok); assert.ok((await f.saveCapacityBookings(bookingInput)).ok); await f.saveCapacityBookings(bookingInput);
  assert.deepEqual(f.calls[1], f.calls[2]); assert.equal(f.calls[1][3], 'em.planning.manage'); assert.deepEqual(f.calls[1][2], bookingInput);
});
test('capacity only acknowledges typed matching receipts and sanitizes private extras', async () => {
  const receipt = { operation: 'save_capacity_bookings', id: id(1), projeto_id: id(2), updated_at: stamp, idempotent_replay: false, record: { changed_days: 1 } };
  for (const patch of [{ id: id(99) }, { operation: 'other' }, { projeto_id: null }, { record: { changed_days: 32 } }, { record: { changed_days: 1, private: 'leak' } }, { idempotent_replay: undefined }]) { const f = writer('administrador', caps, { ok: true, data: { ...receipt, ...patch } } as unknown as WebActionResult); const result = await f.saveCapacityBookings(bookingInput); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE'); }
  const f = writer('administrador', caps, { ok: true, data: { ...receipt, idempotent_replay: true, private: 'strip' } } as unknown as WebActionResult); const result = await f.saveCapacityBookings(bookingInput); assert.ok(result.ok); assert.ok(!JSON.stringify(result).includes('strip'));
  const deleted = { ok: false as const, code: 'PT410', error: 'Projeto excluído; preserve o envio para reconciliação.' };
  assert.deepEqual(await writer('administrador', caps, deleted).saveCapacityBookings(bookingInput), deleted);
});

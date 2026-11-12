import test from 'node:test';
import assert from 'node:assert/strict';
import { linkedEquipmentTypeId, projectEquipmentTypeDisplay } from '../src/components/web/project-equipment-type-display';
import { createProjectEquipmentTypeData } from '../src/server/web/project-equipment-type-data';
import type { ProjectEquipmentSnapshot } from '../src/server/web/project-equipment-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const project = { id: id(1), updated_at: '2026-11-12T12:00:00.000000+00:00', equipamento_id: id(2), tipo_equipamento_id: id(4), status_pcp: null, data_real_de_entrega: null };
const snapshot = { project: { ...project }, equipment: { id: id(2), projeto_id: id(1), tipo_equipamento_id: id(3) }, binding_state: 'linked', can_edit: true, type_mismatch: true } as unknown as ProjectEquipmentSnapshot;
const canonicalType = { id: id(3), nome: 'Motor elétrico', sigla: 'MA-BT' };
function client(data: unknown = canonicalType, error: unknown = null) {
  const reads: unknown[][] = [];
  const db = { from: (table: string) => {
    reads.push(['table', table]);
    return { select: (columns: string) => {
      reads.push(['columns', columns]);
      return { eq: (field: string, value: string) => {
        reads.push(['where', field, value]);
        return { maybeSingle: async () => ({ data, error }) };
      } };
    } };
  } } as any;
  return { db, reads };
}

test('project information resolves the canonical equipment type, never the legacy project type', () => {
  assert.equal(linkedEquipmentTypeId(project, snapshot), id(3));
  assert.equal(projectEquipmentTypeDisplay(project, snapshot, canonicalType), 'MA-BT - Motor elétrico');
  assert.equal(projectEquipmentTypeDisplay(project, snapshot, { id: id(4), nome: 'Tipo legado', sigla: 'LEG' }), 'Não informado');
  assert.equal(projectEquipmentTypeDisplay(project, snapshot, { ...canonicalType, sigla: null }), 'Motor elétrico');
});

test('missing, stale or ambiguous equipment bindings display an empty state without a project fallback', async () => {
  const { db, reads } = client();
  const data = createProjectEquipmentTypeData(db);
  const variants: (ProjectEquipmentSnapshot | null)[] = [null, { ...snapshot, equipment: null, binding_state: 'missing' },
    { ...snapshot, binding_state: 'shared' }, { ...snapshot, equipment: { ...snapshot.equipment!, tipo_equipamento_id: null } },
    { ...snapshot, equipment: { ...snapshot.equipment!, id: id(20) } },
    { ...snapshot, equipment: { ...snapshot.equipment!, projeto_id: id(21) } },
    { ...snapshot, project: { ...snapshot.project, updated_at: '2026-11-12T13:00:00.000000+00:00' } }];
  for (const variant of variants) {
    assert.equal(await data.getProjectEquipmentType(project, variant), null);
    assert.equal(projectEquipmentTypeDisplay(project, variant, canonicalType), 'Não informado');
  }
  assert.equal(reads.length, 0);
});

test('a closed project keeps its current verified equipment type readable', async () => {
  const closed = { ...project, status_pcp: 'finalizando_para_faturar', data_real_de_entrega: '2026-11-12T14:00:00+00:00' };
  const value = { ...snapshot, project: { ...snapshot.project, ...closed, closed: true }, can_edit: false };
  const { db } = client();
  const type = await createProjectEquipmentTypeData(db).getProjectEquipmentType(closed, value);
  assert.equal(projectEquipmentTypeDisplay(closed, value, type), 'MA-BT - Motor elétrico');
});

test('type lookup uses the reader capabilities, a single exact UUID query and minimal projection', async () => {
  const { db, reads } = client();
  const type = await createProjectEquipmentTypeData(db, ['em.portal.read', 'em.projects.read']).getProjectEquipmentType(project, snapshot);
  assert.deepEqual(type, canonicalType);
  assert.deepEqual(reads, [['table', 'rm_tipos_equipamento'], ['columns', 'id,nome,sigla'], ['where', 'id', id(3)]]);
  for (const scopes of [[], ['em.portal.read'], ['em.projects.read']] as const) {
    const blocked = client();
    await assert.rejects(createProjectEquipmentTypeData(blocked.db, scopes).getProjectEquipmentType(project, snapshot), /não autorizado/);
    assert.equal(blocked.reads.length, 0);
  }
});

test('missing type rows are empty while mismatched or overbroad responses fail closed', async () => {
  const missing = client(null);
  assert.equal(await createProjectEquipmentTypeData(missing.db).getProjectEquipmentType(project, snapshot), null);
  for (const value of [{ ...canonicalType, id: id(99) }, { ...canonicalType, internal_secret: 'private' }]) {
    const invalid = client(value);
    await assert.rejects(createProjectEquipmentTypeData(invalid.db).getProjectEquipmentType(project, snapshot), /Não foi possível consultar/);
  }
  const denied = client(null, { message: 'private upstream detail' });
  await assert.rejects(createProjectEquipmentTypeData(denied.db).getProjectEquipmentType(project, snapshot), error => {
    assert.equal(String(error).includes('private upstream detail'), false); return true;
  });
});

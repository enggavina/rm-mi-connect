import assert from 'node:assert/strict';
import test from 'node:test';
import { saveProjectSchema } from '../src/server/web/policy';
import { calendarDate } from '../src/components/web/ui';
import { projectMilestoneChanges } from '../src/components/web/project-milestone-model';

const id = '49c12f88-1074-4c38-814d-3b2b95cb727d';
const payload = (changes: Record<string, unknown>) => ({ submissionId: id, id, expected_updated_at: null, changes });

test('project milestone calendar days are optional, independently ordered and strictly validated', () => {
  assert.equal(saveProjectSchema.safeParse(payload({ nome: 'Motor' })).success, true);
  assert.equal(saveProjectSchema.safeParse(payload({ data_inicio_peritagem: null, data_fim_reparo: '2026-01-01' })).success, true);
  assert.equal(saveProjectSchema.safeParse(payload({ data_inicio_peritagem: '2026-11-10', data_fim_peritagem: '2026-11-10', data_inicio_reparo: '2026-01-01', data_fim_reparo: '2026-01-02' })).success, true);
  assert.equal(saveProjectSchema.safeParse(payload({ data_inicio_peritagem: '2026-11-11', data_fim_peritagem: '2026-11-10' })).success, false);
  assert.equal(saveProjectSchema.safeParse(payload({ data_inicio_reparo: '2026-11-11', data_fim_reparo: '2026-11-10' })).success, false);
  for (const value of ['0000-01-01', '2026-02-30', '2026-01-01T00:00:00Z', 'not-a-date'])
    assert.equal(saveProjectSchema.safeParse(payload({ data_inicio_peritagem: value })).success, false);
});

test('SQL date presentation preserves the calendar day in Brazil, independent of timezone', () => {
  assert.equal(calendarDate('2026-01-01'), '01/01/2026');
  assert.equal(calendarDate('2026-12-31'), '31/12/2026');
  assert.equal(calendarDate(null), '—');
  assert.equal(calendarDate('2026-01-01T00:00:00Z'), '—');
});

test('project editor validates visible pairs and preserves unchanged optional dates', () => {
  const values = { data_inicio_peritagem: '2026-11-01', data_fim_peritagem: '2026-11-02', data_inicio_reparo: null, data_fim_reparo: '2026-11-10' };
  assert.deepEqual(projectMilestoneChanges(values), { error: '', changes: values });
  assert.deepEqual(projectMilestoneChanges(values, values), { error: '', changes: {} });
  assert.deepEqual(projectMilestoneChanges({ ...values, data_fim_peritagem: null }, values), { error: '', changes: { data_fim_peritagem: null } });
  assert.deepEqual(projectMilestoneChanges({ ...values, data_inicio_peritagem: '2026-11-03' }, values), { error: 'O fim da peritagem não pode ser anterior ao início.', changes: null });
  assert.deepEqual(projectMilestoneChanges({ ...values, data_inicio_reparo: '2026-11-11' }, values), { error: 'O fim do reparo não pode ser anterior ao início.', changes: null });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mapWorkshopSnapshot, WORKSHOP_MAX_BYTES, type RawWorkshopSnapshot } from '../src/server/web/workshop-policy';
import { snapshotSchema } from '../src/components/workshop/domain/schema';
import { getCellSummaries, resolveProductionCells } from '../src/components/workshop/data/layout';
import { getMetrics } from '../src/components/workshop/domain/metrics';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const instant = '2026-11-16T18:03:24.123456+00:00';
function raw(): RawWorkshopSnapshot {
  return { as_of: instant, project_count: 1, allocation_count: 1, cell_count: 2,
    projects: [{ id: id(1), numero: 'DEMO-001', nome: 'Nome do projeto', descricao_equipamento: 'Descrição histórica do equipamento', status_pcp: 'executando',
      chegada_do_equipamento: '2026-11-01T15:00:00.000001Z', data_real_de_entrega: null, data_prevista_final: '2026-12-08T15:00:00Z',
      data_contratual: '2026-12-10T15:00:00.123456Z', data_renegociada: '2026-12-15T15:00:00Z', cliente_nome: 'Cliente atual', gestor_nome: 'Gestor atual',
      equipamento_tipo: 'MOTOR - AC-BT - STANDARD', equipamento_descricao: 'Descrição técnica', fabricante: 'Fabricante exemplo', modelo: 'Modelo exemplo',
      potencia: '75,5 kW', rotacao: '1780 rpm', numero_serie: 'DEMO-001', equipment_binding: true }],
    allocations: [{ id: id(2), projeto_id: id(1), celula_id: id(3), status: 'em_dia', bloqueada: 'n_o', motivo_bloqueio: null,
      data_inicio: '2026-11-15T15:00:00.123456Z', data_limite: instant, data_fim_real: null, responsavel_nome: 'Responsável da etapa',
      prioridade: 'alta', horas_previstas: '8.00', horas_realizadas: '2.50', visibilidade: false, indice: 1 }],
    cells: [{ id: id(3), nome: 'Montagem', ordem: 11 }, { id: id(4), nome: 'Pintura', ordem: null }],
  };
}
function activity(n: number, changes: Partial<RawWorkshopSnapshot['allocations'][number]> = {}): RawWorkshopSnapshot['allocations'][number] {
  return { ...raw().allocations[0], id: id(n), celula_id: id(n + 100), indice: n, ...changes };
}
function extraActivities(changes: Partial<RawWorkshopSnapshot['allocations'][number]>[]) {
  const data = raw(); data.allocations = changes.map((change, index) => activity(index + 10, change)); data.allocation_count = data.allocations.length;
  data.cells = data.allocations.map(allocation => ({ id: allocation.celula_id, nome: `Célula ${allocation.indice}`, ordem: allocation.indice }));
  data.cell_count = data.cells.length; return data;
}

test('real Supabase projection preserves precise timestamps, current identities and a complete source-compatible DTO', () => {
  const data = raw(), before = structuredClone(data), output = mapWorkshopSnapshot(data), order = output.orders[0];
  assert.equal(snapshotSchema.safeParse(output).success, true);
  assert.equal(output.source, 'supabase'); assert.equal(output.referenceAt, instant); assert.equal(output.fetchedAt, instant);
  assert.equal(order.enteredAt, data.projects[0].chegada_do_equipamento); assert.equal(order.dueAt, data.projects[0].data_contratual);
  assert.equal(order.activities![0].dueAt, instant); assert.equal(order.activities![0].startedAt, data.allocations[0].data_inicio);
  assert.equal(order.responsible, 'Gestor atual'); assert.equal(order.activities![0].responsible, 'Responsável da etapa');
  assert.equal(order.sourceUrl, `/projetos/${id(1)}`); assert.deepEqual(order.activeStageNames, ['Montagem']);
  // Hidden mobile allocations remain valid internal planning evidence.
  assert.equal(order.activities!.length, 1); assert.equal(output.cells!.length, 2); assert.deepEqual(data, before);
});

test('a receipt awaiting its OS preserves the whole workshop and its own identity without inventing an OS', () => {
  for (const numero of [null, '', '   ']) {
    const data = raw();
    data.projects.push({ ...data.projects[0], id: id(50), numero, equipamento_tipo: null }); data.project_count++;
    const original = structuredClone(data), output = mapWorkshopSnapshot(data);
    assert.equal(snapshotSchema.safeParse(output).success, true);
    assert.equal(output.orders.length, 2); assert.equal(output.orders[0].code, 'DEMO-001');
    assert.equal(output.orders[1].code, 'Recebimento sem OS'); assert.equal(output.orders[1].id, id(50));
    assert.equal(output.orders[1].sourceUrl, `/projetos/${id(50)}`);
    assert.deepEqual(output.orders[1].activities, []); assert.equal(output.orders[1].stage, null);
    assert.equal(output.orders[1].modelVerified, false); assert.equal(getMetrics(output.orders, output.referenceAt).open, 2);
    assert.deepEqual(data, original);
  }
  for (const numero of [123, undefined, false]) {
    const malformed = raw() as any; malformed.projects[0].numero = numero;
    assert.throws(() => mapWorkshopSnapshot(malformed));
  }
});

test('project cohort uses São Paulo civil arrival date and explicit PCP allowlist, without guessing active states', () => {
  const today = raw(); today.as_of = '2026-11-16T02:59:59.999999Z'; today.projects[0].chegada_do_equipamento = '2026-11-15T23:00:00-03:00';
  assert.equal(mapWorkshopSnapshot(today).orders.length, 1);
  today.projects[0].chegada_do_equipamento = '2026-11-16T03:00:00Z'; assert.throws(() => mapWorkshopSnapshot(today));
  for (const status of [null, 'sem_status', 'aguardando_recebimento_equipamento', 'cancelado', 'finalizando_para_faturar', 'inventado']) {
    const data = raw(); data.projects[0].status_pcp = status; assert.throws(() => mapWorkshopSnapshot(data));
  }
  for (const status of ['equipamento_inspecionado', 'aguardando_aprova__o', 'revis_o_comercial', 'revis_o_comercial0', 'susponso__hold_', 'sem_previs_o', 'executando_com_garantia']) {
    const data = raw(); data.projects[0].status_pcp = status;
    const snapshot = mapWorkshopSnapshot(data); assert.equal(getMetrics(snapshot.orders, snapshot.referenceAt).open, 1);
  }
  const ended = raw(); ended.projects[0].data_real_de_entrega = instant; assert.throws(() => mapWorkshopSnapshot(ended));
  const undated = raw(); undated.projects[0].chegada_do_equipamento = null; assert.throws(() => mapWorkshopSnapshot(undated));
});

test('only actual running stages place a project in the process map; waiting and completed stages remain detailed', () => {
  const data = extraActivities([{ status: 'em_dia' }, { status: 'para_execu__o' }, { status: 'atrasado' },
    { status: 'em_dia', data_fim_real: instant }, { status: 'finalizado' }, { status: 'n_a' }]);
  const output = mapWorkshopSnapshot(data); assert.equal(output.orders[0].activities!.length, 6);
  assert.deepEqual(output.orders[0].activeStageNames, ['Célula 10']);
  const summaries = getCellSummaries(output.orders, resolveProductionCells(output.cells));
  assert.equal(summaries.reduce((sum, cell) => sum + cell.count, 0), 1);
  assert.equal(output.orders[0].activities![1].status, 'Para execução');
});

test('simultaneous execution retains all cell IDs and counts one project per stage', () => {
  const output = mapWorkshopSnapshot(extraActivities([{ status: 'em_dia' }, { status: 'em_dia' }]));
  assert.equal(output.orders[0].stage, 'Múltiplas etapas em execução'); assert.equal(output.orders[0].activeStageNames!.length, 2);
  assert.deepEqual(output.orders[0].activities!.map(activity => activity.cellId), [id(110), id(111)]);
  assert.equal(getMetrics(output.orders, output.referenceAt).open, 1);
});

test('closed block evidence cannot become a current block and unknown is preserved', () => {
  let output = mapWorkshopSnapshot(extraActivities([{ status: 'finalizado', bloqueada: 'sim', motivo_bloqueio: 'Bloqueio antigo' }, { bloqueada: null }]));
  assert.equal(output.orders[0].blockDeclared, null); assert.equal(output.orders[0].blockReason, null);
  assert.equal(output.orders[0].activities![0].blockReason, 'Bloqueio antigo'); assert.ok(output.warnings.some(value => value.includes('bloqueio histórico')));
  output = mapWorkshopSnapshot(extraActivities([{ bloqueada: 'n_o' }, { bloqueada: 'sim', motivo_bloqueio: 'Aguardando material' }]));
  assert.equal(output.orders[0].blockDeclared, true); assert.equal(output.orders[0].blockReason, 'Aguardando material');
  output = mapWorkshopSnapshot(extraActivities([{ bloqueada: 'n_o' }])); assert.equal(output.orders[0].blockDeclared, false);
});

test('contractual deadline does not silently fall back to planned or renegotiated dates', () => {
  const data = raw(); let output = mapWorkshopSnapshot(data);
  assert.equal(output.orders[0].dueAt, data.projects[0].data_contratual); assert.equal(output.orders[0].dueSource, 'contractual');
  data.projects[0].data_contratual = null; output = mapWorkshopSnapshot(data);
  assert.equal(output.orders[0].dueAt, null); assert.equal(output.orders[0].dueSource, null);
  assert.equal(getMetrics(output.orders, output.referenceAt).noDeadline, 1);
});

test('equipment uses canonical projection, exact catalog classification and explicit units only', () => {
  const data = raw(); let output = mapWorkshopSnapshot(data);
  assert.equal(output.orders[0].equipment, 'Descrição histórica do equipamento');
  assert.equal(output.orders[0].powerKw, 75.5); assert.equal(output.orders[0].rpm, 1780);
  data.projects[0].equipamento_tipo = ' GERADOR '; output = mapWorkshopSnapshot(data);
  assert.equal(output.orders[0].model, 'generator'); assert.equal(output.orders[0].modelVerified, true);
  data.projects[0].equipamento_tipo = 'GERADOR inventado'; data.projects[0].nome = 'Motor gerador'; data.projects[0].potencia = '75'; data.projects[0].rotacao = '1.780';
  output = mapWorkshopSnapshot(data); assert.equal(output.orders[0].modelVerified, false);
  assert.equal(output.orders[0].powerKw, null); assert.equal(output.orders[0].rpm, null); assert.equal(output.orders[0].powerRaw, '75');
  const detached = raw(); detached.projects[0].equipment_binding = false; assert.throws(() => mapWorkshopSnapshot(detached));
  for (const field of ['equipamento_descricao', 'fabricante', 'modelo', 'potencia', 'rotacao', 'numero_serie'] as const) detached.projects[0][field] = null;
  output = mapWorkshopSnapshot(detached); assert.equal(output.orders[0].serial, null); assert.equal(output.orders[0].modelVerified, true);
});

test('missing operational data never invents capacity, location, historical events or active stages', () => {
  const data = raw(); data.allocations = []; data.allocation_count = 0; const snapshot = mapWorkshopSnapshot(data), order = snapshot.orders[0];
  assert.deepEqual(snapshot.resources, []); assert.equal(order.locationId, null); assert.equal(order.locationVerified, false);
  assert.deepEqual(order.history, []); assert.deepEqual(order.activities, []); assert.deepEqual(order.activeStageNames, []);
  assert.equal(order.stage, null); assert.equal(order.blockDeclared, null); assert.equal(order.priority, null);
  assert.ok(snapshot.warnings.some(value => value.includes('Nenhuma etapa em execução')));
});

test('incomplete, duplicate and unrelated projections are refused before UI metrics are derived', () => {
  const invalid: RawWorkshopSnapshot[] = [];
  let data = raw(); data.project_count++; invalid.push(data);
  data = raw(); data.allocation_count++; invalid.push(data);
  data = raw(); data.cell_count++; invalid.push(data);
  data = raw(); data.projects.push({ ...data.projects[0], id: data.projects[0].id.toUpperCase() }); data.project_count++; invalid.push(data);
  data = raw(); data.cells.push({ ...data.cells[0] }); data.cell_count++; invalid.push(data);
  data = raw(); data.allocations.push({ ...data.allocations[0] }); data.allocation_count++; invalid.push(data);
  data = raw(); data.allocations.push({ ...data.allocations[0], id: id(55) }); data.allocation_count++; invalid.push(data);
  data = raw(); data.allocations[0].projeto_id = id(50); invalid.push(data);
  data = raw(); data.allocations[0].celula_id = id(50); invalid.push(data);
  for (const value of invalid) assert.throws(() => mapWorkshopSnapshot(value));
});

test('invalid dates, scalar types, oversized responses and private extras never escape the boundary', () => {
  let data: any = raw(); data.as_of = '2026-02-30T12:00:00Z'; assert.throws(() => mapWorkshopSnapshot(data));
  data = raw(); data.allocations[0].data_inicio = '2026-11-16T12:00:00'; assert.throws(() => mapWorkshopSnapshot(data));
  data = raw(); data.allocations[0].visibilidade = 'true'; assert.throws(() => mapWorkshopSnapshot(data));
  data = raw(); data.projects[0].equipment_binding = 'true'; assert.throws(() => mapWorkshopSnapshot(data));
  data = raw(); data.projects[0].nome = 'x'.repeat(WORKSHOP_MAX_BYTES); assert.throws(() => mapWorkshopSnapshot(data));
  data = raw(); data.secret = 'private marker'; data.projects[0].email = 'private marker'; data.projects[0].sourceUrl = 'https://attacker.invalid';
  data.allocations[0].answers = ['private marker']; const output = mapWorkshopSnapshot(data);
  assert.equal(JSON.stringify(output).includes('private marker'), false); assert.equal(output.orders[0].sourceUrl, `/projetos/${id(1)}`);
});

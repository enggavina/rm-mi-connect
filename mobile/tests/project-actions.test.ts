import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import type { Operator, OutboxRow, Row } from '../src/core/types';
import type { JourneyContext } from '../src/domain/journey';
import { availableStageActions, cellCompletionRequirements, cellProjectComments, cellProjectLogs, cellProjectStages, cellStatusOptions, frontProjectPhoto, projectClientName, queuedProjectActions } from '../src/domain/project-actions';

const admin: Operator = { operador_id: 'admin', nome: 'Admin', matricula: '1', perfil: 'administrador', perfil_assinante: [], celulas_vinculadas: [], authenticated_at: '2026-10-28T12:00:00Z' };
const allocation: Row = { id: 'allocation', projeto_id: 'project', celula_id: 'cell', status: 'em_dia' };
const context = (status = 'em_dia'): JourneyContext => ({ ok: true, cell: { id: 'cell' }, project: { id: 'project' }, allocation: { ...allocation, status }, canEdit: true });
const stage: Row = { id: 'stage', projeto_id: 'project', celula_origem_id: 'cell', status_cel_proj: 'em_dia', status: 'nulo' };

test('status selector contains every canonical SQL status including all release and N/A statuses', () => {
  const sql = readFileSync(new URL('../../rm-mobile-supabase/migrations/001_rm_enums_and_option_sets.sql', import.meta.url), 'utf8');
  const body = sql.match(/create type public\.rm_status_cel_proj_enum as enum\s*\(([\s\S]*?)\)/)![1];
  const statuses = [...body.matchAll(/'([^']+)'/g)].map(match => match[1]);
  assert.deepEqual(cellStatusOptions.map(option => option.value).sort(), statuses.sort());
});

test('release is tied to the selected origin project/cell and its exact current stage status', () => {
  assert.deepEqual(availableStageActions(admin, context(), stage), ['liberar']);
  assert.deepEqual(availableStageActions(admin, context('pendente'), stage), []);
  assert.deepEqual(availableStageActions(admin, context(), { ...stage, celula_origem_id: 'another-cell' }), []);
  assert.deepEqual(availableStageActions(admin, context(), { ...stage, projeto_id: 'another-project' }), []);
  assert.deepEqual(availableStageActions(admin, context(), { ...stage, celula_projeto_id: 'another-allocation' }), []);
  assert.deepEqual(availableStageActions(null, context(), stage), []);
});

test('return stages match Bubble: approve does not require returned cell status, return does', () => {
  const returned = { ...stage, status_cel_proj: 'retornado' };
  assert.deepEqual(availableStageActions(admin, context('retornado'), returned), ['retornar', 'aprovar']);
  assert.deepEqual(availableStageActions(admin, context('em_dia'), returned), ['aprovar']);
  const returnOnly = { ...admin, perfil: 'mobile', operador_id: 'return-only' };
  const assigned = { ...returned, aprovador_id: 'someone-else', aprovadores_retorno_ids: ['return-only'] };
  assert.deepEqual(availableStageActions(returnOnly, context('retornado'), assigned), ['retornar']);
  assert.deepEqual(availableStageActions(returnOnly, context('em_dia'), assigned), []);
});

test('retired stages disappear from operational counts and actions while older offline catalogs remain usable', () => {
  const active = Object.freeze({ ...stage, id: 'active', ativo: true });
  const retired = Object.freeze({ ...stage, id: 'retired', ativo: false });
  const retiredApproved = Object.freeze({ ...retired, id: 'retired-approved', status: 'aprovado' });
  const legacy = Object.freeze({ ...stage, id: 'legacy' });
  const catalog = Object.freeze([active, retired, retiredApproved, legacy]);
  const visible = cellProjectStages(allocation, catalog);
  assert.deepEqual(visible.map(row => row.id), ['active', 'legacy']);
  assert.equal(visible.filter(row => row.status === 'aprovado').length, 0);
  assert.deepEqual(availableStageActions(admin, context(), retired), []);
  assert.deepEqual(availableStageActions(admin, context('retornado'), { ...retired, status_cel_proj: 'retornado' }), []);
  assert.deepEqual(availableStageActions(admin, context(), legacy), ['liberar']);
  assert.equal(catalog.length, 4, 'retirement must not delete cached catalog rows');
  assert.deepEqual(cellProjectStages(allocation, [{ ...retired, ativo: true }]).map(row => row.id), ['retired'], 'explicit restoration retains the original stage ID');
});

test('retirement or replacement never rewrites an existing queued approval, its actor or completed receipt', () => {
  const retired = Object.freeze({ ...stage, ativo: false });
  const replacement = Object.freeze({ ...stage, id: 'replacement-stage', ativo: true });
  const params = JSON.stringify({ p_aprovacao_etapa_id: stage.id, p_acao: 'liberar', p_observacao: 'Decisão offline' });
  const pending: Readonly<OutboxRow> = Object.freeze({ id: 'original-protocol', rpc_name: 'rm_transition_stage_approval_v1', params_json: params, status: 'pending', actor_id: 'original-operator', attempts: 0, created_at: '2026-10-30T12:00:00Z', next_retry_at: 0, token_key: 'original-token-reference', draft_id: 'original-draft' });
  const failed = Object.freeze({ ...pending, id: 'failed-protocol', status: 'failed' } as OutboxRow);
  const completed = Object.freeze({ ...pending, id: 'completed-protocol', status: 'completed', result_json: '{"ok":true}' } as OutboxRow);
  const queue = Object.freeze([pending, failed, completed]);
  const before = JSON.stringify(queue);
  assert.deepEqual(cellProjectStages(allocation, [retired, replacement]).map(row => row.id), ['replacement-stage']);
  assert.deepEqual(queuedProjectActions(queue, 'rm_transition_stage_approval_v1', { field: 'p_aprovacao_etapa_id', id: stage.id }).map(row => row.operation.id), ['original-protocol', 'failed-protocol']);
  assert.deepEqual(queuedProjectActions(queue, 'rm_transition_stage_approval_v1', { field: 'p_aprovacao_etapa_id', id: replacement.id }), []);
  assert.equal(JSON.stringify(queue), before, 'existing requests and completed receipt remain unchanged');
  assert.equal(queue[0].actor_id, 'original-operator');
});

test('approved and returned decisions are terminal; pending null is supported and no finalize action exists', () => {
  for (const status of ['aprovado', 'reprovado']) {
    assert.deepEqual(availableStageActions(admin, context(), { ...stage, status }), []);
    assert.deepEqual(availableStageActions(admin, context('retornado'), { ...stage, status_cel_proj: 'retornado', status }), []);
  }
  assert.deepEqual(availableStageActions(admin, context(), { ...stage, status: null }), ['liberar']);
  assert.deepEqual(availableStageActions(admin, context(), { ...stage, status_cel_proj: null }), []);
});

test('front image must be a real, non-deleted front photo of this project, never an unrelated placeholder', () => {
  const photos: Row[] = [
    { id: 'back', projeto_id: 'project', titulo: 'Vista traseira', foto_url: 'https://photos/back' },
    { id: 'foreign', projeto_id: 'other', tipo_recebimento: 'frente', foto_url: 'https://photos/foreign' },
    { id: 'deleted', projeto_id: 'project', tipo_recebimento: 'frente', foto_url: 'https://photos/deleted', lixeira: true },
    { id: 'empty', projeto_id: 'project', tipo_recebimento: 'frente' },
    { id: 'named', projeto_id: 'project', titulo: 'Vista Frontal', foto_url: 'https://photos/front' },
  ];
  assert.equal(frontProjectPhoto('project', photos)?.id, 'named');
  assert.equal(frontProjectPhoto('project', photos.slice(0, 4)), undefined);
  assert.equal(frontProjectPhoto('project', [...photos, { id: 'typed', projeto_id: 'project', tipo_recebimento: 'frente', foto_url: 'https://photos/typed' }])?.id, 'typed');
});

test('front image recognizes the real project inspection title and keeps receiving priority', () => {
  const inspection: Row = Object.freeze({ id: 'inspection', projeto_id: 'project', titulo: 'Inspeção visual do motor (vista dianteira)', tipo_recebimento: null, numero: 1, foto_url: 'https://photos/inspection' });
  const other: Row = { id: 'back', projeto_id: 'project', titulo: 'Inspeção visual do motor (vista traseira)', numero: 0, foto_url: 'https://photos/back' };
  const photos = [other, inspection];
  assert.equal(frontProjectPhoto('project', photos), inspection);
  assert.deepEqual(photos.map(photo => photo.id), ['back', 'inspection'], 'selection cannot reorder the catalog');
  assert.equal(frontProjectPhoto('project', [{ ...inspection, titulo: '  INSPEÇÃO VISUAL DO MOTOR — VISTA DIANTEIRA  ' }])?.id, 'inspection');
  assert.equal(frontProjectPhoto('project', [{ ...inspection, titulo: 'Frontal' }])?.id, 'inspection', 'complementary photos use the real catalog label Frontal');
  assert.equal(frontProjectPhoto('project', [...photos, { id: 'receiving', projeto_id: 'project', tipo_recebimento: 'frente', numero: 99, foto_url: 'https://photos/receiving' }])?.id, 'receiving');
});

test('front image never substitutes a generic, rear, deleted, empty or foreign inspection photo', () => {
  const base = { projeto_id: 'project', titulo: 'Inspeção visual do motor (vista dianteira)', foto_url: 'https://photos/front' };
  const photos: Row[] = [
    { ...base, id: 'foreign', projeto_id: 'other' }, { ...base, id: 'deleted', lixeira: true },
    { ...base, id: 'empty', foto_url: '   ' }, { ...base, id: 'missing', foto_url: null },
    { ...base, id: 'generic', titulo: 'Inspeção visual do equipamento' },
    { ...base, id: 'rear', titulo: 'Inspeção visual do motor (vista traseira)' },
    { ...base, id: 'component', titulo: 'Inspeção visual da tampa dianteira' },
  ];
  assert.equal(frontProjectPhoto('project', photos), undefined);
  const a = { ...base, id: 'a' }, b = { ...base, id: 'b' };
  assert.equal(frontProjectPhoto('project', [b, a])?.id, 'a');
  assert.equal(frontProjectPhoto('project', [a, b])?.id, 'a');
});

test('project client resolves the actual relationship before legacy exported name fallbacks', () => {
  assert.equal(projectClientName({ id: 'p', cliente_id: 'client', cliente_nome_exportacao: 'Outdated' }, { ...allocation, cliente_nome_export: 'Old cell label' }, [{ id: 'client', nome: 'Current client' }]), 'Current client');
  assert.equal(projectClientName({ id: 'p', cliente_nome_exportacao: 'Project export' }, allocation, []), 'Project export');
  assert.equal(projectClientName(undefined, { ...allocation, cliente_nome_export: 'Cell export' }, []), 'Cell export');
});

test('comments and approval history remain scoped to both project and cell without mixing stage and log counts', () => {
  const rows: Row[] = [{ id: 'old', projeto_id: 'project', celula_id: 'cell', created_at: '2026-10-27' }, { id: 'new', projeto_id: 'project', celula_id: 'cell', created_at: '2026-10-28' }, { id: 'foreign', projeto_id: 'other', celula_id: 'cell' }, { id: 'other-cell', projeto_id: 'project', celula_id: 'other' }, { id: 'project-general', projeto_id: 'project', celula_id: null }];
  assert.deepEqual(cellProjectComments(allocation, rows).map(row => row.id), ['new', 'old']);
  assert.deepEqual(cellProjectLogs(allocation, rows).map(row => row.id), ['new', 'old']);
  assert.deepEqual(cellProjectStages(allocation, [stage, { ...stage, id: 'foreign', celula_origem_id: 'other' }]).map(row => row.id), ['stage']);
});

test('queued actions retain original actor and protocol after a switch and block only the matching allocation', () => {
  const op = Object.freeze({ id: 'original-protocol', rpc_name: 'rm_update_cell_status_v1', actor_id: 'original-author', status: 'pending', params_json: JSON.stringify({ p_celula_projeto_id: 'allocation', p_status: 'finalizado', p_operador_id: 'original-author' }) }) as OutboxRow;
  const queue = Object.freeze([op, { ...op, id: 'foreign', params_json: JSON.stringify({ p_celula_projeto_id: 'other' }) }, { ...op, id: 'done', status: 'completed' }, { ...op, id: 'broken', params_json: '{invalid' }]);
  const found = queuedProjectActions(queue, 'rm_update_cell_status_v1', { field: 'p_celula_projeto_id', id: 'allocation' });
  assert.equal(found.length, 1); assert.equal(found[0].operation, op);
  assert.equal(found[0].operation.actor_id, 'original-author'); assert.equal(found[0].operation.id, 'original-protocol');
  assert.equal(found[0].params.p_operador_id, 'original-author');
  assert.deepEqual(queuedProjectActions(queue, 'rm_add_cell_comment_v1', { field: 'p_celula_projeto_id', id: 'allocation' }), []);
});

test('finalization counts required form IDs, not duplicate completed records or unrelated contexts', () => {
  const cp = { ...allocation, forms_ids: ['form-a', 'form-b', 'form-a'] };
  const records: Row[] = [{ id: 'a1', projeto_id: 'project', celula_id: 'cell', form_id: 'form-a', preenchido: true }, { id: 'a2', projeto_id: 'project', celula_id: 'cell', form_id: 'form-a', preenchido: true }, { id: 'foreign', projeto_id: 'other', celula_id: 'cell', form_id: 'form-b', preenchido: true }, { id: 'incomplete', projeto_id: 'project', celula_id: 'cell', form_id: 'form-b', preenchido: false }];
  const result = cellCompletionRequirements(cp, records, [], [], true);
  assert.deepEqual(result.missingFormIds, ['form-b']);
  assert.equal(result.missingForms, 1);
  assert.equal(result.canFinalize, false);
});

test('valid pending inspections and exact required-photo slots permit ordered offline finalization without changing authorship', () => {
  const cp = { ...allocation, forms_ids: ['form-a'] };
  const photos: Row[] = [{ id: 'slot', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'obrigat_ria' }];
  const queue = [{ id: 'form-protocol', rpc_name: 'rm_submit_form_inspection_v1', status: 'pending', actor_id: 'first-person', params_json: JSON.stringify({ p_projeto_id: 'project', p_celula_id: 'cell', p_form_id: 'form-a', p_respostas: [{ questao_id: 'q', resposta: 'OK' }] }) }, { id: 'photo-protocol', rpc_name: 'rm_record_cell_photo_v1', status: 'syncing', actor_id: 'second-person', params_json: JSON.stringify({ p_projeto_id: 'project', p_celula_id: 'cell', p_celula_projeto_id: 'allocation', p_foto_id: 'slot', p_foto_url: 'file:///persisted.jpg' }) }] as OutboxRow[];
  const before = JSON.stringify(queue);
  const result = cellCompletionRequirements(cp, [], photos, queue, true);
  assert.equal(result.canFinalize, true);
  assert.equal(result.missingForms, 0); assert.equal(result.missingPhotos, 0);
  assert.equal(JSON.stringify(queue), before);
});

test('failed, malformed, foreign and complementary operations cannot satisfy finalization requirements', () => {
  const cp = { ...allocation, forms_ids: ['form-a'] };
  const photos: Row[] = [{ id: 'slot', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'obrigat_ria' }];
  const inspection = { id: 'f', rpc_name: 'rm_submit_form_inspection_v1', status: 'pending', params_json: JSON.stringify({ p_projeto_id: 'project', p_celula_id: 'cell', p_form_id: 'form-a', p_respostas: [{ questao_id: 'q', resposta: 'OK' }] }) } as OutboxRow;
  const photo = { id: 'p', rpc_name: 'rm_record_cell_photo_v1', status: 'pending', params_json: JSON.stringify({ p_projeto_id: 'project', p_celula_id: 'cell', p_foto_id: 'slot', p_foto_url: 'file:///persisted.jpg' }) } as OutboxRow;
  const patch = (operation: OutboxRow, values: Record<string, unknown>) => ({ ...operation, params_json: JSON.stringify({ ...JSON.parse(operation.params_json), ...values }) });
  const invalid = [{ ...inspection, status: 'failed' }, { ...photo, status: 'failed' }, patch(inspection, { p_celula_id: 'other' }), patch(inspection, { p_projeto_id: 'other' }), patch(inspection, { p_respostas: [null] }), patch(inspection, { p_respostas: undefined }), patch(photo, { p_foto_id: null, p_categoria_foto: 'complementar' }), patch(photo, { p_celula_projeto_id: 'other' }), patch(photo, { p_foto_url: '' }), { ...photo, params_json: '{broken' }];
  const result = cellCompletionRequirements(cp, [], photos, invalid, true);
  assert.equal(result.canFinalize, false);
  assert.equal(result.missingForms, 1); assert.equal(result.missingPhotos, 1);
});

test('finalization ignores deleted/non-required/foreign photos and accepts existing filled evidence', () => {
  const photos: Row[] = [
    { id: 'saved', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'obrigat_ria', foto_url: 'https://photos/saved.jpg' },
    { id: 'deleted', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'obrigat_ria', lixeira: true },
    { id: 'optional', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'complementar' },
    { id: 'other', projeto_id: 'project', celula_id: 'other', categoria_foto: 'obrigat_ria' },
  ];
  assert.equal(cellCompletionRequirements({ ...allocation, forms_ids: [] }, [], photos, [], true).canFinalize, true);
  assert.equal(cellCompletionRequirements(allocation, [], [{ ...photos[0], foto_url: '   ' }], [], true).missingPhotos, 1);
});

test('an unloaded catalog never allows finalization, while genuinely empty loaded catalogs do', () => {
  const cp = { ...allocation, forms_ids: [] };
  assert.equal(cellCompletionRequirements(cp, [], [], [], false).canFinalize, false);
  assert.equal(cellCompletionRequirements(cp, [], [], [], true).canFinalize, true);
});

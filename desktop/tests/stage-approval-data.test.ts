import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createStageApprovalData } from '../src/server/web/stage-approval-data';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00', cellVersion = '2026-10-29T18:03:25.654321+00:00';
function snapshot() {
  return {
    stage: { id: id(1), projeto_id: id(2), celula_projeto_id: null, celula_origem_id: id(3), celula_destino_id: null,
      status: 'nulo', status_cel_proj: 'finalizado', bloquear_avanco_sem_aprov: false, aprovador_id: null,
      aprovadores_ids: [], aprovadores_retorno_ids: [], aprovado_por_id: null, data_aprovacao: null,
      created_at: version, updated_at: version, bubble_id: 'private-stage', sync_source: 'private-source' },
    allocation: { id: id(4), projeto_id: id(2), celula_id: id(3), status: 'finalizado', visibilidade: true,
      bloqueada: 'n_o', motivo_bloqueio: null, updated_at: cellVersion, modified_by_id: 'private-actor' },
    project: { id: id(2), numero: 'OS1', nome: 'Motor', cliente_id: null, cliente_nome_exportacao: 'Cliente', cliente_nome: null,
      descricao_equipamento: 'Descrição', arquivo_nota_fiscal_url: 'https://private.invalid/invoice' },
    origin: { id: id(3), nome: 'Oficina' }, destination: null,
    available_actions: ['liberar'], action_reason: null,
    approvers: [{ id: id(5), nome: 'Aprovador', email: 'private@example.invalid', auth_user_id: 'private-auth' }],
    return_approvers: [], decided_by: null,
    history: [{ id: id(6), aprovacao_etapa_id: id(1), acao: 'liberar', status_anterior: 'nulo', status_novo: 'aprovado',
      observacao: null, actor_id: id(5), actor_nome: 'Aprovador', created_at: version, source: 'web', receipt_id: 'private-receipt' }],
    legacy_history: [{ id: id(7), projeto_id: id(2), celula_id: id(3), aprovador_id: id(5), aprovador_nome: 'Aprovador',
      status_aprovacao: 'aprovado', data_aprovacao: version, created_at: version, bubble_id: 'private-log' }],
    private_metadata: 'private-top-level',
  };
}
function fixture(capabilities: readonly CorporateCapability[] = ['em.portal.read', 'em.approvals.read', 'em.approvals.decide']) {
  const calls: { name: string; args?: unknown }[] = []; let current: any = snapshot(); let rows: any[] = [];
  const client = {
    async rpc(name: string, args: any) { calls.push({ name, args }); return { data: name === 'rm_web_stage_approvals_v1' ? { items: current ? [current] : [], total: current ? 1 : 0, page: args.p_page, page_size: args.p_page_size } : current, error: null }; },
    from(table: string) {
      calls.push({ name: table }); const query: any = { select(columns: string) { calls.push({ name: 'select', args: columns }); return query; }, order() { return query; },
        async range(from: number, to: number) { return { data: rows.slice(from, to + 1), error: null }; } }; return query;
    },
  };
  return { calls, data: createStageApprovalData(client as unknown as SupabaseClient, capabilities), set(value: any) { current = value; }, cells(value: any[]) { rows = value; } };
}

test('approval readers need portal plus the dedicated read grant, without leaking via choices or history', async () => {
  for (const caps of [[], ['em.approvals.read'], ['em.portal.read', 'em.planning.manage', 'em.history.read'], ['em.portal.read', 'em.approvals.decide']] as CorporateCapability[][]) {
    const fixtureData = fixture(caps);
    await assert.rejects(fixtureData.data.listStageApprovals(), /Acesso/);
    await assert.rejects(fixtureData.data.getStageApproval(id(1)), /Acesso/);
    await assert.rejects(fixtureData.data.getStageApprovalChoices(), /Acesso/);
    assert.deepEqual(fixtureData.calls, []);
  }
});

test('single-statement stage snapshot preserves microseconds, resolves legacy null links, and strips private/media data', async () => {
  const f = fixture(); const result = await f.data.getStageApproval(id(1)); assert.ok(result);
  assert.equal(result.stage.updated_at, version); assert.equal(result.allocation?.updated_at, cellVersion);
  assert.equal(result.stage.celula_projeto_id, null); assert.equal(result.allocation?.id, id(4));
  assert.deepEqual(result.available_actions, ['liberar']); assert.equal(result.history[0].actor_nome, 'Aprovador');
  assert.equal(result.legacy_history[0].aprovador_nome, 'Aprovador');
  assert.ok(!/private|email|auth_user|bubble_id|sync_source|arquivo_nota/.test(JSON.stringify(result)));
  assert.deepEqual(f.calls, [{ name: 'rm_web_stage_approval_snapshot_v1', args: { p_id: id(1) } }]);
});

test('read-only approval access never presents a decision and has no actions waiting in mine', async () => {
  const f = fixture(['em.portal.read', 'em.approvals.read']);
  const detail = await f.data.getStageApproval(id(1)); assert.ok(detail); assert.deepEqual(detail.available_actions, []);
  assert.match(detail.action_reason!, /consultar/);
  const list = await f.data.listStageApprovals(); assert.deepEqual(list.items[0].available_actions, []);
  const count = f.calls.length; assert.deepEqual(await f.data.listStageApprovals({ mine: true }), { items: [], total: 0, page: 1, page_size: 25 });
  assert.equal(f.calls.length, count);
});

test('queue sends server-side state/mine/project/cell/search filters with real pagination and explicit field DTOs', async () => {
  const f = fixture(); const result = await f.data.listStageApprovals({ project: id(2), cell: id(3), q: ' %OS1,_(Motor) ', state: 'pending', mine: true, page: '2' });
  assert.equal(result.page, 2); assert.equal(result.total, 1); assert.equal(result.page_size, 25);
  assert.ok(!/private/.test(JSON.stringify(result)));
  assert.deepEqual(f.calls, [{ name: 'rm_web_stage_approvals_v1', args: { p_project_id: id(2), p_cell_id: id(3), p_state: 'pending', p_mine: true,
    p_search: 'OS1 Motor', p_page: 2, p_page_size: 25 } }]);
});

test('orphaned historical stages remain viewable without inventing an allocation or rewriting IDs', async () => {
  const f = fixture(); const raw = snapshot(); const orphan: any = { ...raw, allocation: null, available_actions: [], action_reason: 'Célula do projeto não encontrada.' };
  f.set(orphan); const result = await f.data.getStageApproval(id(1)); assert.ok(result);
  assert.equal(result.allocation, null); assert.equal(result.stage.celula_projeto_id, null); assert.deepEqual(result.available_actions, []);
  assert.equal(result.action_reason, orphan.action_reason);
  f.set(null); assert.equal(await f.data.getStageApproval(id(1)), null);
});

test('malformed or crossed snapshots fail closed and invalid URL filters cannot broaden the queue', async () => {
  const f = fixture(); assert.equal(await f.data.getStageApproval('../id'), null);
  assert.equal((await f.data.listStageApprovals({ project: 'invalid' })).total, 0);
  assert.equal((await f.data.listStageApprovals({ cell: 'invalid' })).total, 0);
  assert.deepEqual(f.calls, []);
  for (const corrupt of [
    { ...snapshot(), stage: { ...snapshot().stage, id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, projeto_id: id(99) } },
    { ...snapshot(), project: { ...snapshot().project, id: id(99) } },
    { ...snapshot(), available_actions: ['finalizar_ciclo'] },
    { ...snapshot(), history: [{ ...snapshot().history[0], aprovacao_etapa_id: id(99) }] },
    { ...snapshot(), legacy_history: [{ ...snapshot().legacy_history[0], projeto_id: id(99) }] },
    { ...snapshot(), legacy_history: [{ ...snapshot().legacy_history[0], celula_id: id(99) }] },
  ]) { f.set(corrupt); await assert.rejects(f.data.getStageApproval(id(1)), /Não foi possível/); }
  f.set(snapshot());
  for (const filters of [{ project: id(99) }, { cell: id(99) }, { state: 'approved' as const }, { state: 'returned' as const }]) await assert.rejects(f.data.listStageApprovals(filters), /Não foi possível/);
});

test('approval filter choices load only safe cell identities with complete pagination', async () => {
  const f = fixture(); f.cells(Array.from({ length: 501 }, (_, n) => ({ id: id(100 + n), nome: `Cell ${n}`, email: 'private' })));
  const result = await f.data.getStageApprovalChoices(); assert.equal(result.cells.length, 501);
  assert.ok(!JSON.stringify(result).includes('private'));
  assert.deepEqual(f.calls.filter(call => call.name === 'select').map(call => call.args), ['id,nome', 'id,nome']);
});

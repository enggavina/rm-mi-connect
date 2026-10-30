import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createProjectCommentData } from '../src/server/web/project-comment-data';
import type { ProjectCommentSnapshot } from '../src/server/web/project-comment-policy';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', hash = 'b'.repeat(64);
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.history.read'];
function snapshot(): ProjectCommentSnapshot {
  return { project: { id: id(1), numero: 'OS 01', status_pcp: 'em_execu_o', data_real_de_entrega: null, updated_at: version, closed: false },
    comment: { id: id(2), projeto_id: id(1), celula_id: id(3), cadastrado_por_id: id(4), evento: 'Texto original\ncom detalhe técnico.',
      created_at: '2026-10-29T09:00:00.000001Z', updated_at: version, author_name: 'Autora original', author_registration: 'M-001', cell_name: 'Célula A' },
    allocation: { id: id(5), updated_at: '2026-10-30T14:00:00.000001Z', retirada: false },
    can_edit: true, reason: null, context_version: hash, history: { total: 0, page: 1, page_size: 25, items: [] } };
}
function history(data: ProjectCommentSnapshot, total: number, page = 1) {
  const start = total - (page - 1) * 25, length = Math.min(25, Math.max(0, start));
  data.history = { total, page, page_size: 25, items: Array.from({ length }, (_, index) => ({ id: id(100 + start - index),
    revision: start - index, evento_anterior: index ? `Anterior ${start - index}` : null, evento_novo: `Texto ${start - index}`,
    motivo: 'Conferência do relato', editor_id: id(4), editor_name: 'Editora', editor_registration: 'M-001', created_at: version })) };
  return data;
}
function fixture(data?: unknown, options: { error?: boolean; thrown?: boolean; capabilities?: CorporateCapability[] } = {}) {
  const calls: unknown[][] = [], fromCalls: string[] = [], resultData = arguments.length === 0 ? snapshot() : data;
  const client = { rpc: async (...args: unknown[]) => { calls.push(args); if (options.thrown) throw Error('network private payload');
    return { data: resultData, error: options.error ? { code: 'private', message: 'private SQL details' } : null }; },
    from: (table: string) => { fromCalls.push(table); throw Error('Comment detail must not query unrestricted tables'); } } as unknown as SupabaseClient;
  return { ...createProjectCommentData(client, options.capabilities ?? caps), calls, fromCalls };
}

test('comment detail is one JWT-scoped RPC for the exact project/comment with canonical UUIDs and precise versions', async () => {
  const data = snapshot(); data.project.id = data.project.id.toUpperCase(); data.comment.id = data.comment.id.toUpperCase();
  data.comment.projeto_id = data.comment.projeto_id.toUpperCase();
  const f = fixture(data), result = await f.getProjectComment(id(1).toUpperCase(), id(2).toUpperCase());
  assert.ok(result); assert.equal(result.project.id, id(1)); assert.equal(result.comment.id, id(2));
  assert.equal(result.project.updated_at, version); assert.equal(result.comment.created_at, '2026-10-29T09:00:00.000001Z');
  assert.equal(result.allocation!.updated_at, '2026-10-30T14:00:00.000001Z');
  assert.deepEqual(f.calls, [['rm_web_project_comment_snapshot_v1', { p_project_id: id(1), p_comment_id: id(2), p_history_page: 1 }]]);
  assert.deepEqual(f.fromCalls, []);
});

test('comment history has exact descending revision pages and clamps a valid request beyond the final page', async () => {
  for (const [total, requested, actual] of [[0, 1, 1], [25, 1, 1], [26, 2, 2], [51, 2, 2], [51, 7, 3], [1, 100_000, 1]]) {
    const data = history(snapshot(), total, actual), f = fixture(data), result = await f.getProjectComment(id(1), id(2), String(requested));
    assert.deepEqual(result?.history, data.history); assert.equal((f.calls[0][1] as Record<string, unknown>).p_history_page, requested);
  }
  for (const page of [0, -1, 1.5, 100_001, NaN, Infinity, '', '01', '1.0', '1e2', '100001', null, {}, ['1']]) {
    const f = fixture(); await assert.rejects(f.getProjectComment(id(1), id(2), page), /Confira a página/); assert.deepEqual(f.calls, []);
  }
});

test('closed, retired, unclassified and historical comments remain readable with original authorship and exact text', async () => {
  const cases: ProjectCommentSnapshot[] = [];
  for (const patch of [{ status_pcp: 'cancelado' }, { status_pcp: 'finalizando_para_faturar' }, { data_real_de_entrega: version }]) {
    const data = snapshot(); data.project = { ...data.project, ...patch, closed: true }; data.can_edit = false; data.reason = 'Projeto encerrado.'; cases.push(data);
  }
  const retired = snapshot(); retired.allocation!.retirada = true; retired.can_edit = false; retired.reason = 'Célula retirada.'; cases.push(retired);
  const legacy = snapshot(); legacy.can_edit = false; legacy.reason = 'Origem não comprovada.'; legacy.comment.evento = '  ' + 'x'.repeat(10_001) + '\n'; cases.push(legacy);
  const unknown = snapshot(); unknown.can_edit = false; unknown.allocation = null; unknown.comment.celula_id = null;
  unknown.comment.cadastrado_por_id = null; unknown.comment.author_name = null; unknown.comment.author_registration = null; unknown.comment.cell_name = null; cases.push(unknown);
  for (const data of cases) {
    const result = await fixture(data).getProjectComment(id(1), id(2)); assert.ok(result); assert.deepEqual(result, data); assert.equal(result.can_edit, false);
    if (data.project.closed || !data.allocation || data.allocation.retirada) {
      await assert.rejects(fixture({ ...data, can_edit: true }).getProjectComment(id(1), id(2)), /Não foi possível consultar/);
    }
  }
  const reader = snapshot(); reader.can_edit = false; reader.reason = 'Consulta conforme seu perfil.';
  assert.deepEqual(await fixture(reader).getProjectComment(id(1), id(2)), reader);
});

test('comment reader rejects crossed project/comment, inconsistent edit flags and private audit data', async () => {
  const invalid: unknown[] = [undefined, [], {}, { ...snapshot(), private_audit: 'private' }, { ...snapshot(), context_version: 'invalid' }];
  for (const patch of [{ id: id(99) }, { closed: true }, { updated_at: 'invalid' }, { data_real_de_entrega: '2026-10-30T12:00:00' }]) {
    const data = snapshot(); data.project = { ...data.project, ...patch }; invalid.push(data);
  }
  for (const patch of [{ id: id(99) }, { projeto_id: id(99) }, { evento: ['another'] }, { cadastrado_por_id: null }, { celula_id: null },
    { updated_at: 'invalid' }, { created_at: 'invalid' }, { actor_auth_user_id: id(99) }]) {
    const data = snapshot(); data.comment = { ...data.comment, ...patch } as ProjectCommentSnapshot['comment']; invalid.push(data);
  }
  invalid.push({ ...snapshot(), allocation: null }, { ...snapshot(), allocation: { ...snapshot().allocation, retirada: true } });
  for (const data of invalid) await assert.rejects(fixture(data).getProjectComment(id(1), id(2)), /Não foi possível consultar/);
});

test('comment history cannot leak raw journal identities or return missing, duplicated or reordered revisions', async () => {
  const cases: unknown[] = [];
  for (const patch of [{ page: 2 }, { total: -1 }, { total: 1.5 }, { page_size: 50 }, { items: [] }]) {
    const data = history(snapshot(), 2); cases.push({ ...data, history: { ...data.history, ...patch } });
  }
  for (const patch of [{ revision: 0 }, { revision: 1 }, { revision: 2.5 }, { id: 'invalid' }, { editor_id: 'invalid' },
    { created_at: 'invalid' }, { auth_user_id: id(99) }, { before_record: { private: 'data' } }, { evento_novo: null }]) {
    const data = history(snapshot(), 2); data.history.items[0] = { ...data.history.items[0], ...patch } as ProjectCommentSnapshot['history']['items'][number]; cases.push(data);
  }
  const duplicate = history(snapshot(), 2); duplicate.history.items[1].id = duplicate.history.items[0].id; cases.push(duplicate);
  const reverse = history(snapshot(), 2); reverse.history.items.reverse(); cases.push(reverse);
  const huge = history(snapshot(), 26); huge.history.items.push({ ...huge.history.items[24], id: id(999), revision: 1 }); cases.push(huge);
  for (const data of cases) await assert.rejects(fixture(data).getProjectComment(id(1), id(2)), /Não foi possível consultar/);
});

test('comment reader denies missing current scopes before SQL and distinguishes missing data from an unavailable database', async () => {
  for (const capabilities of [[], ...caps.map(capability => caps.filter(value => value !== capability)), ['em.projects.manage']] as CorporateCapability[][]) {
    const f = fixture(snapshot(), { capabilities }); await assert.rejects(f.getProjectComment(id(1), id(2)), /Acesso não autorizado/); assert.deepEqual(f.calls, []);
  }
  for (const [project, comment] of [['invalid', id(2)], [id(1), 'invalid']]) {
    const f = fixture(); assert.equal(await f.getProjectComment(project, comment), null); assert.deepEqual(f.calls, []);
  }
  const missing = fixture(null); assert.equal(await missing.getProjectComment(id(1), id(2)), null); assert.equal(missing.calls.length, 1);
  for (const options of [{ error: true }, { thrown: true }]) {
    const f = fixture(snapshot(), options); await assert.rejects(f.getProjectComment(id(1), id(2)), error => error instanceof Error
      && /Não foi possível consultar/.test(error.message) && !/private/.test(error.message));
    assert.equal(f.calls.length, 1); assert.deepEqual(f.fromCalls, []);
  }
});

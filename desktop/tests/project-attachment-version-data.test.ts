import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createProjectAttachmentVersionData } from '../src/server/web/project-attachment-version-data';
import type { ProjectAttachmentSnapshot } from '../src/server/web/project-attachment-version-policy';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', hash = 'b'.repeat(64);
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.documents.read'];
const revisionId = (revision: number) => revision === 1 ? id(2) : id(100 + revision);
function metadata(revision: number): ProjectAttachmentSnapshot['attachment'] {
  return { id: revisionId(revision), projeto_id: id(1), nome: `Anexo ${revision}`, descricao: 'Observação preservada.',
    tipo_arquivo: 'application/pdf', status: 'No prazo', data_vencimento: null, created_at: version, updated_at: version,
    created_by: id(4), visivel_cliente: false, author_name: 'Responsável registrado', author_registration: 'M-001',
    has_file: true, filename: `anexo-${revision}.pdf`, byte_size: 512 };
}
function snapshot(total = 1, selected = total, page = 1): ProjectAttachmentSnapshot {
  const start = total - (page - 1) * 25;
  return { project: { id: id(1), numero: 'OS 033', updated_at: version, status_pcp: null, data_real_de_entrega: null, closed: false },
    attachment: metadata(selected), series: { root_id: id(2), head_id: revisionId(total), head_updated_at: version,
      selected_revision: selected, head_revision: total }, can_replace: selected === total, reason: selected === total ? null : 'Versão anterior preservada.',
    context_version: hash, history: { total, page, page_size: 25,
      items: Array.from({ length: Math.min(25, Math.max(0, start)) }, (_, i) => { const revision = start - i;
        return { ...metadata(revision), revision, motivo: revision === 1 ? null : 'Conferência do arquivo', current: revision === total };
      }) } };
}
function fixture(data?: unknown, options: { error?: boolean; thrown?: boolean; capabilities?: CorporateCapability[] } = {}) {
  const calls: unknown[][] = [], fromCalls: string[] = [], resultData = arguments.length === 0 ? snapshot() : data;
  const client = { rpc: async (...args: unknown[]) => { calls.push(args); if (options.thrown) throw Error('network private URL');
    return { data: resultData, error: options.error ? { code: 'private', message: 'private SQL data' } : null }; },
    from: (table: string) => { fromCalls.push(table); throw Error('Version consultation must use the single scoped RPC'); } } as unknown as SupabaseClient;
  return { ...createProjectAttachmentVersionData(client, options.capabilities ?? caps), calls, fromCalls };
}

test('attachment versions use one exact project/attachment RPC with canonical UUIDs and precise timestamps', async () => {
  const data = snapshot(); data.project.id = data.project.id.toUpperCase(); data.attachment.id = data.attachment.id.toUpperCase();
  data.attachment.projeto_id = data.attachment.projeto_id.toUpperCase();
  const f = fixture(data), result = await f.getProjectAttachment(id(1).toUpperCase(), id(2).toUpperCase());
  assert.equal(result?.project.id, id(1)); assert.equal(result?.attachment.id, id(2)); assert.equal(result?.attachment.updated_at, version);
  assert.deepEqual(f.calls, [['rm_web_project_attachment_snapshot_v1', { p_project_id: id(1), p_attachment_id: id(2), p_history_page: 1 }]]);
  assert.deepEqual(f.fromCalls, []);
});

test('version history is bounded, descending and clamped without losing selected historical metadata', async () => {
  for (const [total, selected, requested, actual] of [[1, 1, 1, 1], [25, 25, 1, 1], [26, 1, 2, 2], [51, 1, 2, 2], [51, 51, 7, 3], [1, 1, 100_000, 1]]) {
    const data = snapshot(total, selected, actual), f = fixture(data), result = await f.getProjectAttachment(id(1), revisionId(selected), String(requested));
    assert.deepEqual(result, data); assert.equal((f.calls[0][1] as Record<string, unknown>).p_history_page, requested);
  }
  for (const page of [0, -1, 1.5, 100_001, NaN, Infinity, '', '01', '1e2', '1.0', '100001', null, {}, ['1']]) {
    const f = fixture(); await assert.rejects(f.getProjectAttachment(id(1), id(2), page), /Confira a página/); assert.deepEqual(f.calls, []);
  }
});

test('legacy origin, unavailable files, old revisions and closed projects remain readable without fabricated provenance', async () => {
  const legacy = snapshot(); legacy.series = null; legacy.can_replace = false; legacy.reason = 'Origem não comprovada.';
  legacy.history = { total: 0, page: 1, page_size: 25, items: [] };
  legacy.attachment = { ...legacy.attachment, nome: '  Registro legado  ', descricao: 'x'.repeat(2001), filename: null, byte_size: null,
    created_by: null, author_name: null, has_file: false, tipo_arquivo: 'application/legacy', status: 'Situação antiga', visivel_cliente: null };
  assert.deepEqual(await fixture(legacy).getProjectAttachment(id(1), id(2)), legacy);
  for (const patch of [{ status_pcp: 'cancelado' }, { status_pcp: 'finalizando_para_faturar' }, { data_real_de_entrega: version }]) {
    const data = snapshot(); data.project = { ...data.project, ...patch, closed: true }; data.can_replace = false; data.reason = 'Projeto encerrado.';
    assert.deepEqual(await fixture(data).getProjectAttachment(id(1), id(2)), data);
  }
  const historical = snapshot(3, 1); assert.equal((await fixture(historical).getProjectAttachment(id(1), id(2)))?.can_replace, false);
});

test('attachment detail rejects crossed context, invalid eligibility and malformed private projection fields', async () => {
  const cases: unknown[] = [];
  for (const patch of [{ id: id(99) }, { closed: true }, { updated_at: 'invalid' }]) { const data = snapshot(); cases.push({ ...data, project: { ...data.project, ...patch } }); }
  for (const patch of [{ id: id(99) }, { projeto_id: id(99) }, { updated_at: 'invalid' }, { has_file: false }, { visivel_cliente: true },
    { filename: null }, { byte_size: 0 }, { byte_size: 20 * 1024 * 1024 + 1 }, { arquivo_url: 'https://private.invalid/object' }, { object_path: 'private/key' }]) {
    const data = snapshot(); cases.push({ ...data, attachment: { ...data.attachment, ...patch } });
  }
  cases.push({ ...snapshot(), series: null }, { ...snapshot(), context_version: 'a'.repeat(63) }, { ...snapshot(), auth_user_id: id(99) });
  for (const data of cases) await assert.rejects(fixture(data).getProjectAttachment(id(1), id(2)), /Não foi possível consultar/);
});

test('root, head, selected version and visible row metadata must describe the same immutable chain', async () => {
  const cases: ProjectAttachmentSnapshot[] = [];
  const wrongHead = snapshot(3); wrongHead.history.items[0].id = id(999); wrongHead.history.items[0].current = false; cases.push(wrongHead);
  const wrongRoot = snapshot(51, 1); wrongRoot.series!.root_id = id(999); cases.push(wrongRoot);
  const sameRootHead = snapshot(51); sameRootHead.series!.root_id = sameRootHead.series!.head_id; cases.push(sameRootHead);
  const wrongSelectedRevision = snapshot(51, 2); wrongSelectedRevision.series!.selected_revision = 1; cases.push(wrongSelectedRevision);
  for (const patch of [{ nome: 'Other title' }, { status: 'Vencido' }, { filename: 'different.pdf' }, { byte_size: 3 }, { author_name: 'Other author' }]) {
    const data = snapshot(3); data.history.items[0] = { ...data.history.items[0], ...patch }; cases.push(data);
  }
  for (const data of cases) await assert.rejects(fixture(data).getProjectAttachment(id(1), data.attachment.id), /Não foi possível consultar/);
});

test('history cannot leak raw files or return missing, repeated, misordered or foreign versions', async () => {
  const cases: unknown[] = [];
  for (const patch of [{ total: -1 }, { total: 1.5 }, { page: 2 }, { page_size: 50 }, { items: [] }]) {
    const data = snapshot(3); cases.push({ ...data, history: { ...data.history, ...patch } });
  }
  for (const patch of [{ revision: 0 }, { revision: 2 }, { current: false }, { projeto_id: id(99) }, { id: 'invalid' },
    { arquivo_url: 'https://private.invalid/object' }, { sha256: hash }, { auth_user_id: id(99) }, { upload_id: id(99) }]) {
    const data = snapshot(3); data.history.items[0] = { ...data.history.items[0], ...patch } as ProjectAttachmentSnapshot['history']['items'][number]; cases.push(data);
  }
  const duplicate = snapshot(3); duplicate.history.items[1].id = duplicate.history.items[0].id; cases.push(duplicate);
  const reverse = snapshot(3); reverse.history.items.reverse(); cases.push(reverse);
  for (const data of cases) await assert.rejects(fixture(data).getProjectAttachment(id(1), revisionId(3)), /Não foi possível consultar/);
});

test('current document scopes precede SQL and absence remains distinct from network or database failure', async () => {
  for (const capabilities of [[], ...caps.map(capability => caps.filter(value => value !== capability)), ['em.projects.manage']] as CorporateCapability[][]) {
    const f = fixture(snapshot(), { capabilities }); await assert.rejects(f.getProjectAttachment(id(1), id(2)), /Acesso não autorizado/); assert.deepEqual(f.calls, []);
  }
  for (const [project, attachment] of [['invalid', id(2)], [id(1), 'invalid']]) {
    const f = fixture(); assert.equal(await f.getProjectAttachment(project, attachment), null); assert.deepEqual(f.calls, []);
  }
  assert.equal(await fixture(null).getProjectAttachment(id(1), id(2)), null);
  for (const options of [{ error: true }, { thrown: true }]) {
    const f = fixture(snapshot(), options); await assert.rejects(f.getProjectAttachment(id(1), id(2)), error => error instanceof Error
      && /Não foi possível consultar/.test(error.message) && !/private/.test(error.message)); assert.equal(f.calls.length, 1);
  }
});

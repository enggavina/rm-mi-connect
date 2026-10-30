import test from 'node:test';
import assert from 'node:assert/strict';
import type { ProjectCommentSnapshot } from '../src/server/web/project-comment-policy';
import { commentHistoryPage, projectCommentChanged, projectCommentDraft, projectCommentRequest, projectCommentValidation } from '../src/components/web/project-comment-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T18:22:10.123456+00:00';
function snapshot(): ProjectCommentSnapshot {
  return { project: { id: id(1), numero: 'EM-032', updated_at: version, status_pcp: 'peritagem', data_real_de_entrega: null, closed: false },
    comment: { id: id(2), projeto_id: id(1), celula_id: id(3), cadastrado_por_id: id(4), evento: 'Observação original\nSegunda linha', created_at: version,
      updated_at: version, author_name: 'Autora original', author_registration: 'EM123', cell_name: 'Inspeção' },
    allocation: { id: id(5), updated_at: version, retirada: false }, can_edit: true, reason: null, context_version: 'a'.repeat(64),
    history: { items: [], total: 0, page: 1, page_size: 25 } };
}

test('comment correction preserves original context and freezes its exact protocol, body and reason', () => {
  const source = snapshot(), draft = projectCommentDraft(source); draft.evento = '  Texto corrigido\nCom nova informação  '; draft.motivo = '  Corrigir referência do equipamento  ';
  const request = projectCommentRequest(source, draft, id(6)); draft.evento = 'Outro texto'; draft.motivo = 'Outro motivo';
  assert.equal(request.evento, 'Texto corrigido\nCom nova informação'); assert.equal(request.motivo, 'Corrigir referência do equipamento');
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_comment_updated_at, version); assert.equal(request.expected_context_version, source.context_version);
  assert.equal(request.projeto_id, id(1)); assert.equal(request.comentario_id, id(2)); assert.equal(request.submissionId, id(6)); assert.equal(request.confirm_change, true);
  assert.equal(Object.isFrozen(request), true);
  assert.deepEqual(Object.keys(request).sort(), ['submissionId', 'projeto_id', 'comentario_id', 'expected_project_updated_at', 'expected_comment_updated_at', 'expected_context_version', 'evento', 'motivo', 'confirm_change'].sort());
  assert.equal(source.comment.evento, 'Observação original\nSegunda linha'); assert.equal(source.comment.cadastrado_por_id, id(4)); assert.equal(source.comment.created_at, version);
});

test('a reason alone or an equivalent trimmed text never starts a comment correction', () => {
  const source = snapshot(), draft = projectCommentDraft(source); draft.motivo = 'Conferência';
  assert.equal(projectCommentChanged(source, draft), false); assert.throws(() => projectCommentRequest(source, draft, id(6)), /Altere o texto/);
  draft.evento += '  '; assert.equal(projectCommentChanged(source, draft), false);
  source.comment.evento = null; const empty = projectCommentDraft(source); assert.equal(projectCommentChanged(source, empty), false);
  source.comment.evento = '  Legado exato  '; assert.equal(projectCommentChanged(source, { evento: source.comment.evento, motivo: '' }), false);
});

test('comment text and mandatory reason have independent limits without truncating the draft', () => {
  assert.equal(projectCommentValidation({ evento: 'x'.repeat(10_000), motivo: 'm'.repeat(2_000) }), '');
  for (const evento of ['', ' \n\t', 'x'.repeat(10_001), 'Texto\u0000inválido']) assert.match(projectCommentValidation({ evento, motivo: 'Motivo' }), /comentário/);
  for (const motivo of ['', ' \n\t', 'm'.repeat(2_001), 'Motivo\u0000inválido']) assert.match(projectCommentValidation({ evento: 'Corrigido', motivo }), /motivo/);
});

test('closed, retired, unproven or crossed comment context never creates a command', () => {
  const source = snapshot(), draft = { evento: 'Correção', motivo: 'Referência corrigida' };
  for (const blocked of [{ ...source, can_edit: false }, { ...source, allocation: null }, { ...source, allocation: { ...source.allocation!, retirada: true } },
    { ...source, project: { ...source.project, closed: true } }, { ...source, comment: { ...source.comment, projeto_id: id(9) } }]) {
    assert.throws(() => projectCommentRequest(blocked, draft, id(6)), /somente para consulta/);
  }
});

test('comment history navigation accepts only bounded positive integer pages', () => {
  assert.equal(commentHistoryPage('2'), 2); assert.equal(commentHistoryPage('100000'), 100000);
  for (const invalid of [undefined, '', '0', '-1', '1.5', '1e2', '100001', '0002', ['2']]) assert.equal(commentHistoryPage(invalid), 1);
});

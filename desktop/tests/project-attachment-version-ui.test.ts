import test from 'node:test';
import assert from 'node:assert/strict';
import type { ProjectAttachmentSnapshot } from '../src/server/web/project-attachment-version-policy';
import { attachmentFileSize, attachmentHistoryPage, attachmentVersionDraft, attachmentVersionEligible, attachmentVersionRequest, attachmentVersionValidation } from '../src/components/web/project-attachment-version-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T18:22:10.123456+00:00';
function snapshot(): ProjectAttachmentSnapshot {
  return { project: { id: id(1), numero: 'EM-033', updated_at: version, status_pcp: 'peritagem', data_real_de_entrega: null, closed: false },
    attachment: { id: id(2), projeto_id: id(1), nome: 'Laudo original', descricao: 'Observação original', tipo_arquivo: 'application/pdf', status: 'No prazo',
      data_vencimento: '2026-11-10T12:00:00Z', created_at: version, updated_at: version, created_by: id(3), visivel_cliente: false,
      author_name: 'Autora original', author_registration: 'EM123', has_file: true, filename: 'original.pdf', byte_size: 256 },
    series: { root_id: id(2), head_id: id(2), head_updated_at: version, selected_revision: 1, head_revision: 1 },
    can_replace: true, reason: null, context_version: 'a'.repeat(64), history: { items: [], total: 1, page: 1, page_size: 25 } };
}
const file = { name: 'revisao.pdf', size: 320, type: 'application/pdf' };

test('new attachment version freezes exact file, metadata, source versions and mandatory reason without modifying the original', () => {
  const source = snapshot(), draft = attachmentVersionDraft(source);
  draft.nome = '  Laudo revisado  '; draft.descricao = '  Correção de referência  '; draft.motivo = '  Acrescentar resultado do ensaio  '; draft.status = 'Vencido';
  const request = attachmentVersionRequest(source, file, draft, 'b'.repeat(64), id(4)); draft.nome = 'Outro título'; draft.motivo = 'Outro motivo';
  assert.equal(request.submissionId, id(4)); assert.equal(request.source_attachment_id, id(2)); assert.equal(request.expected_attachment_updated_at, version);
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_context_version, source.context_version);
  assert.equal(request.filename, file.name); assert.equal(request.byte_size, file.size); assert.equal(request.mime_type, file.type); assert.equal(request.sha256, 'b'.repeat(64));
  assert.equal(request.nome, 'Laudo revisado'); assert.equal(request.descricao, 'Correção de referência'); assert.equal(request.motivo, 'Acrescentar resultado do ensaio');
  assert.equal(request.data_vencimento, '2026-11-10T12:00:00.000Z'); assert.equal(request.status, 'Vencido'); assert.equal(request.confirm_change, true); assert.ok(Object.isFrozen(request));
  assert.equal(source.attachment.nome, 'Laudo original'); assert.equal(source.attachment.created_by, id(3)); assert.equal(source.attachment.created_at, version);
  assert.equal(source.attachment.filename, 'original.pdf'); assert.ok(!Object.hasOwn(request, 'created_by')); assert.ok(!Object.hasOwn(request, 'arquivo_url'));
});

test('an explicitly selected file can have the same bytes while still preserving a separate confirmed version intent', () => {
  const source = snapshot(), draft = attachmentVersionDraft(source); draft.motivo = 'Republicar com conferência documental';
  const request = attachmentVersionRequest(source, { ...file, name: 'original.pdf', size: 256 }, draft, 'c'.repeat(64), id(4));
  assert.equal(request.nome, source.attachment.nome); assert.equal(request.filename, source.attachment.filename); assert.equal(request.motivo, draft.motivo);
  assert.equal(attachmentVersionValidation(null, draft), 'Selecione o novo arquivo PDF, JPEG ou PNG.');
});

test('file, metadata, reason and expiry limits are independent and never truncate the selected intent', () => {
  const draft = { ...attachmentVersionDraft(snapshot()), motivo: 'Conferência' };
  assert.equal(attachmentVersionValidation({ ...file, size: 20 * 1024 * 1024 }, draft), '');
  for (const invalid of [{ ...file, size: 0 }, { ...file, size: 20 * 1024 * 1024 + 1 }, { ...file, type: 'application/zip' }, { ...file, name: 'wrong.png' }, { ...file, name: '../file.pdf' }]) assert.notEqual(attachmentVersionValidation(invalid, draft), '');
  for (const patch of [{ nome: ' ' }, { nome: 'x'.repeat(201) }, { descricao: 'x'.repeat(2001) }, { status: 'Concluído' }, { expiry: '2026-02-30' }, { motivo: ' \n\t' }, { motivo: 'x'.repeat(2001) }, { motivo: 'Motivo\u0000inválido' }]) {
    assert.notEqual(attachmentVersionValidation(file, { ...draft, ...patch }), '');
  }
  const cleared = attachmentVersionRequest(snapshot(), file, { ...draft, descricao: '', expiry: '' }, 'b'.repeat(64), id(4));
  assert.equal(cleared.descricao, null); assert.equal(cleared.data_vencimento, null);
});

test('only the current eligible private attachment in an open project can prepare a replacement', () => {
  const source = snapshot(), draft = { ...attachmentVersionDraft(source), motivo: 'Conferência' };
  for (const blocked of [{ ...source, can_replace: false }, { ...source, series: null }, { ...source, project: { ...source.project, closed: true } },
    { ...source, attachment: { ...source.attachment, projeto_id: id(9) } }, { ...source, attachment: { ...source.attachment, has_file: false } },
    { ...source, attachment: { ...source.attachment, visivel_cliente: true } }, { ...source, series: { ...source.series!, head_id: id(9) } },
    { ...source, series: { ...source.series!, selected_revision: 1, head_revision: 2 } }, { ...source, series: { ...source.series!, head_updated_at: '2026-10-30T18:22:10.123457+00:00' } }]) {
    assert.equal(attachmentVersionEligible(blocked), false); assert.throws(() => attachmentVersionRequest(blocked, file, draft, 'b'.repeat(64), id(4)), /somente para consulta/);
  }
});

test('attachment history pages remain bounded and file size labels never invent an unknown value', () => {
  assert.equal(attachmentHistoryPage('2'), 2); assert.equal(attachmentHistoryPage('100000'), 100000);
  for (const invalid of [undefined, '', '0', '-1', '1.5', '1e2', '100001', '0002', ['2']]) assert.equal(attachmentHistoryPage(invalid), 1);
  assert.equal(attachmentFileSize(null), 'Tamanho não informado'); assert.match(attachmentFileSize(256), /KiB/); assert.match(attachmentFileSize(3 * 1024 * 1024), /MiB/);
});

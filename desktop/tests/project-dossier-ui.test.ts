import test from 'node:test';
import assert from 'node:assert/strict';
import { DOSSIER_MAX_FILE_BYTES, dossierAttachmentRequest, dossierCommentRequest, dossierExpiry, dossierFileError } from '../src/components/web/project-dossier-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T14:02:10.123456+00:00';
const allocation = { id: id(2), projeto_id: id(1), celula_id: id(3), updated_at: version, retirada: false, visibilidade: false, name: 'Peritagem' };
const file = { name: 'Laudo do motor.pdf', size: 2048, type: 'application/pdf' };

test('project comments require an active allocation of this project while hidden work remains eligible', () => {
  const request = dossierCommentRequest(id(1), version, allocation, '  Conferir a montagem.\nSem alteração de dados.  ', id(5));
  assert.equal(request.evento, 'Conferir a montagem.\nSem alteração de dados.');
  assert.equal(request.celula_projeto_id, allocation.id); assert.equal(request.expected_allocation_updated_at, version);
  assert.equal(request.expected_project_updated_at, version); assert.equal(Object.isFrozen(request), true);
  for (const choice of [undefined, { ...allocation, retirada: true }, { ...allocation, projeto_id: id(4) }]) assert.throws(() => dossierCommentRequest(id(1), version, choice, 'Comentário', id(5)), /Selecione uma célula ativa/);
  assert.throws(() => dossierCommentRequest(id(1), version, allocation, ' \n ', id(5)), /Informe um comentário/);
  assert.throws(() => dossierCommentRequest(id(1), version, allocation, 'a'.repeat(10_001), id(5)), /10.000/);
  assert.deepEqual(Object.keys(request).sort(), ['submissionId', 'projeto_id', 'celula_projeto_id', 'expected_project_updated_at', 'expected_allocation_updated_at', 'evento'].sort(), 'Actor, status and history remain server-owned.');
});

test('attachment selection bounds files before hashing and never accepts a mismatched extension or empty file', () => {
  for (const candidate of [file, { name: 'Placa.JPEG', type: 'image/jpeg', size: DOSSIER_MAX_FILE_BYTES }, { name: 'Motor.png', type: 'image/png', size: 1 }]) assert.equal(dossierFileError(candidate), null);
  for (const candidate of [{ ...file, size: 0 }, { ...file, size: DOSSIER_MAX_FILE_BYTES + 1 }, { ...file, type: 'text/html' },
    { ...file, type: 'image/png' }, { ...file, name: '../Laudo.pdf' }, { ...file, name: 'Laudo\\motor.pdf' }, { ...file, name: `${'a'.repeat(181)}.pdf` }]) assert.ok(dossierFileError(candidate));
});

test('attachment metadata freezes protocol, project version, digest and exact file identity without client URL or actor', () => {
  const draft = { nome: '  Laudo de inspeção ', descricao: ' Documento recebido. ', status: 'No prazo', expiry: '2026-11-05' };
  const request = dossierAttachmentRequest(id(1), version, file, draft, 'a'.repeat(64), id(5));
  draft.nome = 'Outro título'; draft.status = 'Vencido';
  assert.equal(request.nome, 'Laudo de inspeção'); assert.equal(request.descricao, 'Documento recebido.'); assert.equal(request.status, 'No prazo');
  assert.equal(request.submissionId, id(5)); assert.equal(request.expected_project_updated_at, version); assert.equal(request.sha256, 'a'.repeat(64));
  assert.equal(request.filename, file.name); assert.equal(request.byte_size, file.size); assert.equal(request.mime_type, file.type);
  assert.equal(request.data_vencimento, '2026-11-05T12:00:00.000Z'); assert.equal(Object.isFrozen(request), true);
  for (const key of ['arquivo_url', 'storage_path', 'bucket', 'actor_id', 'created_by', 'visivel_cliente', 'file']) assert.ok(!(key in request));
});

test('attachment status is explicit and optional expiry preserves the selected calendar date', () => {
  assert.equal(dossierExpiry(''), null); assert.equal(dossierExpiry('2028-02-29'), '2028-02-29T12:00:00.000Z');
  for (const date of ['2026-02-29', '2026-13-05', '2026-01-32', '2026-11-05T14:00:00Z', '05/11/2026']) assert.throws(() => dossierExpiry(date), /data de vencimento/);
  for (const patch of [{ nome: '' }, { status: '' }, { status: 'ativo' }, { descricao: 'a'.repeat(2001) }]) assert.throws(() => dossierAttachmentRequest(id(1), version, file,
    { nome: 'Laudo', descricao: '', status: 'Vencido', expiry: '', ...patch }, 'b'.repeat(64), id(5)));
  assert.equal(dossierAttachmentRequest(id(1), version, file, { nome: 'Laudo', descricao: ' ', status: 'Vencido', expiry: '' }, 'b'.repeat(64), id(5)).descricao, null);
});

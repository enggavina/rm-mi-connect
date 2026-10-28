import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import { newReceiving, receivingPayload, restoreReceiving, setArrivalPart, validateReceiving,
  RECEIVING_PHOTO_TITLES, type Receiving } from '../src/domain/receiving';

const now = '2026-10-28T12:34:00.000Z';
function complete(): Receiving {
  return { ...newReceiving('submission-fixed', now), cliente: 'client',
    fotos: [{ id: 'photo-one', uri: 'file:///durable/one.jpg', tipo: 'frente', comentario: '' }] };
}

test('new receiving sends the simplified fields without manufacturing an OS or equipment type', () => {
  const data = { ...complete(), notaFiscal: ' 12345 ', arquivoNotaFiscal: 'file:///durable/invoice.pdf',
    descricaoEquipamento: ' Motor de teste ', placaMotor: 'c___placa', eventualidades: 'Embalagem avariada' };
  assert.equal(validateReceiving(data), null);
  const payload = receivingPayload(data);
  assert.equal(payload.p_nota_fiscal, '12345');
  assert.equal(payload.p_arquivo_nota_fiscal_url, 'file:///durable/invoice.pdf');
  assert.equal(payload.p_descricao_equipamento, 'Motor de teste');
  assert.equal(payload.p_chegada_equipamento, now);
  assert.equal(payload.p_eventualidades, 'Embalagem avariada');
  assert.deepEqual(payload.p_equipamento, { descricao: 'Motor de teste', placa_motor: 'c___placa' });
  for (const removed of ['p_numero_projeto', 'p_tipo_equipamento_id', 'p_nome_projeto', 'p_contato', 'p_proprietario']) assert.equal(removed in payload, false);
});

test('legacy draft keeps its protocol, original fields, equipment and every photo without guessing titles', () => {
  const old = { id: 'old-protocol', step: 5, cliente: 'client', tipo: 'type', numero: 'OS-15', nome: 'Saved name',
    contato: 'Saved contact', proprietario: 'Saved owner', chegada: now, eventualidades: 'Saved condition',
    projeto_id: 'project', qr: 'legacy-qr', equipamento: { descricao: 'Saved equipment', fabricante: 'Maker', fp: '0,8', numero_cabos: '6', placa_motor: 's___placa', desmontar_para_orcar: 'sim' },
    fotos: ['file:///old/a.jpg', 'https://cdn.example/b.jpg'] };
  const migrated = restoreReceiving(old, 'unused-new-id', '2026-11-01T00:00:00Z');
  assert.equal(migrated.id, old.id); assert.equal(migrated.step, 1);
  assert.equal(migrated.descricaoEquipamento, old.equipamento.descricao);
  assert.equal(migrated.placaMotor, 's___placa');
  assert.deepEqual(migrated.equipamento, old.equipamento);
  assert.deepEqual(migrated.legacySnapshot, old);
  assert.deepEqual(migrated.fotos.map(photo => photo.uri), old.fotos);
  assert.ok(migrated.fotos.every(photo => photo.tipo === ''));
  assert.match(validateReceiving(migrated)!, /título cadastrado/);
  const classified = { ...migrated, fotos: migrated.fotos.map(photo => ({ ...photo, tipo: 'embalagem' })) };
  const payload = receivingPayload(classified);
  assert.equal(payload.p_numero_projeto, old.numero); assert.equal(payload.p_tipo_equipamento_id, old.tipo);
  assert.equal(payload.p_projeto_id, old.projeto_id); assert.equal(payload.p_qrcode_value, old.qr);
  assert.equal((payload.p_equipamento as Record<string, unknown>).fabricante, 'Maker');
  assert.equal((payload.p_equipamento as Record<string, unknown>).fp, 0.8);
  assert.equal((payload.p_equipamento as Record<string, unknown>).numero_cabos, 6);
  assert.equal(old.equipamento.fp, '0,8'); // Original data never mutated.
});

test('reopening the migrated draft keeps photo identity, comments, file URI and the same replay payload', () => {
  const data = { ...complete(), notaFiscal: 'NF-A', arquivoNotaFiscal: 'file:///durable/nf.pdf',
    fotos: [{ id: 'stable-photo', uri: 'file:///durable/a.jpg', tipo: 'vista_superior', comentario: ' Pequena avaria ' }] };
  const reopened = restoreReceiving(JSON.parse(JSON.stringify(data)), 'different-id', '2027-01-01T00:00:00Z');
  assert.deepEqual(reopened, data);
  assert.deepEqual(receivingPayload(reopened), receivingPayload(data));
  assert.deepEqual(receivingPayload(data).p_fotos_recebimento, [{ foto_url: 'file:///durable/a.jpg', titulo: 'Vista Traseira', tipo_recebimento: 'vista_superior', legenda: 'Pequena avaria', numero: 1, categoria_foto: 'obrigat_ria' }]);
});

test('migration maps removed steps safely and preserves already submitted drafts', () => {
  for (const step of [0, 1, 2, 3, 4]) assert.equal(restoreReceiving({ ...complete(), version: 1, step }, 'x', now).step, 0);
  const restored = restoreReceiving({ ...complete(), version: 1, step: 6, submitted: true }, 'x', now);
  assert.equal(restored.step, 2); assert.equal(restored.submitted, true); assert.equal(restored.id, 'submission-fixed');
});

test('damaged existing drafts never silently receive a new protocol or an invented arrival time', () => {
  const incomplete = { cliente: 'client', fotos: ['file:///saved.jpg'] };
  assert.throws(() => restoreReceiving(incomplete, 'new-id', now), /sem protocolo/);
  assert.deepEqual(incomplete, { cliente: 'client', fotos: ['file:///saved.jpg'] });
  const missingArrival = restoreReceiving({ id: 'original', cliente: 'client', chegada: '' }, 'new-id', now);
  assert.equal(missingArrival.chegada, '');
  assert.match(validateReceiving(missingArrival, false)!, /data e uma hora/);
});

test('arrival date and time edits preserve the other part in local time', () => {
  const original = new Date(2026, 9, 28, 15, 47, 0, 0);
  const changedDate = new Date(setArrivalPart(original.toISOString(), new Date(2026, 10, 4, 0, 0), 'date'));
  assert.equal(changedDate.getDate(), 4); assert.equal(changedDate.getMonth(), 10);
  assert.equal(changedDate.getHours(), 15); assert.equal(changedDate.getMinutes(), 47);
  const changedTime = new Date(setArrivalPart(changedDate.toISOString(), new Date(2020, 0, 1, 9, 12), 'time'));
  assert.equal(changedTime.getDate(), 4); assert.equal(changedTime.getFullYear(), 2026);
  assert.equal(changedTime.getHours(), 9); assert.equal(changedTime.getMinutes(), 12);
});

test('validation rejects missing client, invalid arrival and unclassified photos but allows optional NF and comments', () => {
  assert.equal(validateReceiving(complete()), null);
  assert.match(validateReceiving({ ...complete(), cliente: '' })!, /cliente/);
  assert.match(validateReceiving({ ...complete(), chegada: 'not-a-date' })!, /data e uma hora/);
  assert.match(validateReceiving({ ...complete(), fotos: [] })!, /ao menos uma foto/);
  assert.match(validateReceiving({ ...complete(), placaMotor: 'unknown' })!, /placa/);
  assert.equal(validateReceiving({ ...complete(), fotos: [] }, false), null);
  assert.equal(receivingPayload(complete()).p_nota_fiscal, null);
  assert.equal(receivingPayload(complete()).p_arquivo_nota_fiscal_url, null);
  assert.equal((receivingPayload(complete()).p_fotos_recebimento as Record<string, unknown>[])[0].legenda, null);
});

test('pre-registered photo titles retain every backend enum and its historical display', () => {
  const sql = readFileSync(new URL('../../rm-mobile-supabase/migrations/001_rm_enums_and_option_sets.sql', import.meta.url), 'utf8');
  const catalog = [...sql.matchAll(/\('rmtipofoto', '([^']+)', '([^']+)'/g)].map(match => ({ value: match[1], label: match[2] }));
  assert.deepEqual(RECEIVING_PHOTO_TITLES, catalog);
});

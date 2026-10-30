import assert from 'node:assert/strict';
import test from 'node:test';
import { projectQrImageHref, projectQrLabel, projectQrSummary } from '../src/components/web/project-qr-model';

const id = 'ABCDEFAB-0000-4000-8000-000000000001';
test('QR controls use only a canonical project identity, never visible title or legacy image URL', () => {
  assert.equal(projectQrImageHref(id), `/api/web/projects/${id.toLowerCase()}/qr`);
  assert.equal(projectQrImageHref(id, true), `/api/web/projects/${id.toLowerCase()}/qr?download=1`);
  for (const invalid of ['OS 42', 'https://example.invalid/project', '../project', id + '?download=1']) assert.throws(() => projectQrImageHref(invalid), /inválido/);
});
test('QR labels preserve a real OS while receiving projects are identified truthfully', () => {
  assert.equal(projectQrLabel({ numero: ' 123 / A ' }), 'OS 123 / A');
  assert.equal(projectQrLabel({ numero: null }), 'Projeto em recebimento');
  assert.equal(projectQrLabel({ numero: ' ' }), 'Projeto em recebimento');
});
test('the printable description is bounded without breaking Unicode or inventing unavailable metadata', () => {
  assert.equal(projectQrSummary({ nome: ' Nome ', descricao_equipamento: 'Outra descrição' }), 'Nome');
  assert.equal(projectQrSummary({ nome: null, descricao_equipamento: ' Motor 55 kW ' }), 'Motor 55 kW');
  assert.equal(projectQrSummary({ nome: null, descricao_equipamento: null }), '');
  const value = projectQrSummary({ nome: '😀'.repeat(241), descricao_equipamento: null });
  assert.equal(Array.from(value).length, 241); assert.equal(value, '😀'.repeat(240) + '…');
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { canManageCatalogs, catalogFailureState, confirmsCatalogDeletion, editableKind, freezeCatalogAttempt, readCatalogForm } from '../src/components/web/catalog-model';
import type { SaveCatalogInput } from '../src/server/web/catalog-policy';

const fields = (values: Record<string, string>) => { const form = new FormData(); for (const [key, value] of Object.entries(values)) form.set(key, value); return form; };
test('catalog controls require both RM administrator and the exact SSO management grant', () => {
  assert.equal(canManageCatalogs({ profile: { perfil: 'administrador' }, sso: { capabilities: ['em.portal.read', 'em.catalogs.read'] } }), false);
  for (const perfil of ['padr_o', 'auditor', 'cliente', 'mobile']) assert.equal(canManageCatalogs({ profile: { perfil }, sso: { capabilities: ['em.catalogs.manage'] } }), false);
  assert.equal(canManageCatalogs({ profile: { perfil: 'administrador' }, sso: { capabilities: ['em.catalogs.read', 'em.catalogs.manage'] } }), true);
  assert.equal(canManageCatalogs({ profile: { perfil: 'administrador' } }), true, 'Explicit legacy mode retains its existing server authorization policy.');
  for (const value of ['users', 'forms', '../users', null, ['clients']]) assert.equal(editableKind(value), null);
});

test('catalog form builds only permitted fields and preserves blank versus zero ordering', () => {
  const values = fields({ nome: ' Motor ', codigo: ' ', descricao: '  Descrição  ', ordem: '0', indice: '900', perfil: 'administrador', sigla: ' M ' });
  assert.deepEqual(readCatalogForm('clients', values), { changes: { nome: 'Motor', codigo: null, descricao: 'Descrição' }, errors: {} });
  assert.deepEqual(readCatalogForm('types', values), { changes: { nome: 'Motor', sigla: 'M' }, errors: {} });
  assert.deepEqual(readCatalogForm('cells', values), { changes: { nome: 'Motor', codigo: null, ordem: 0 }, errors: {} });
  values.set('ordem', ''); assert.equal((readCatalogForm('cells', values).changes as { ordem?: number | null }).ordem, null);
  for (const order of ['-1', '1.5', '1e3', 'NaN', '1000001']) {
    values.set('ordem', order); assert.ok(readCatalogForm('cells', values).errors.ordem, order);
  }
  values.set('nome', '   '); assert.equal(readCatalogForm('types', values).errors.nome, 'Informe o nome.');
});

test('ambiguous retries preserve the original identifier, exact timestamp and body after form edits', () => {
  const input: SaveCatalogInput = { submissionId: '12345678-1234-4234-8234-123456789012', id: '12345678-1234-4234-8234-123456789013', kind: 'clients',
    expected_updated_at: '2026-10-29T15:04:03.123456+00:00', changes: { nome: 'Cliente original', codigo: null } };
  const frozen = freezeCatalogAttempt({ action: 'save', payload: input });
  input.changes.nome = 'Outro nome'; input.expected_updated_at = '2026-10-29T15:05:00Z';
  assert.equal(frozen.payload.submissionId, '12345678-1234-4234-8234-123456789012');
  assert.equal(frozen.payload.expected_updated_at, '2026-10-29T15:04:03.123456+00:00');
  assert.equal(frozen.action, 'save');
  if (frozen.action === 'save') { assert.equal(frozen.payload.changes.nome, 'Cliente original'); assert.equal(Object.isFrozen(frozen.payload.changes), true); }
  assert.equal(Object.isFrozen(frozen.payload), true);
  const deletion = freezeCatalogAttempt({ action: 'delete', payload: { kind: 'clients', id: input.id, submissionId: input.submissionId, expected_updated_at: '2026-10-29T15:04:03.123456+00:00' } });
  assert.equal(deletion.payload.expected_updated_at, '2026-10-29T15:04:03.123456+00:00'); assert.equal(Object.isFrozen(deletion.payload), true);
});

test('deletion requires the exact displayed name; stale state is distinct from an uncertain result', () => {
  assert.equal(confirmsCatalogDeletion('Célula de testes', ' Célula de testes '), true);
  for (const confirmation of ['', 'sim', 'célula de testes', 'Célula de teste']) assert.equal(confirmsCatalogDeletion('Célula de testes', confirmation), false);
  assert.equal(confirmsCatalogDeletion('', ''), false);
  for (const code of ['UNAVAILABLE', 'CORP_UNAVAILABLE']) assert.deepEqual(catalogFailureState({ ok: false, code, error: '' }), { uncertain: true, stale: false, unauthorized: false });
  for (const code of ['PT409', '40001', 'P0002']) assert.deepEqual(catalogFailureState({ ok: false, code, error: '' }), { uncertain: false, stale: true, unauthorized: false });
  assert.deepEqual(catalogFailureState({ ok: false, code: '23503', error: '' }), { uncertain: false, stale: false, unauthorized: false });
});

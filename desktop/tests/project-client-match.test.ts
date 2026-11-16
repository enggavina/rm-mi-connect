import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectClientMatcher, projectClientNameTokens } from '../src/components/web/project-client-match';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const gmc = { id: id(1), nome: 'GMC COMPONENTES ELÉTRICOS E AUTOMAÇÃO LTDA' };

test('project name matching returns the actual client record and never changes its stored name', () => {
  const match = createProjectClientMatcher([gmc]);
  assert.deepEqual(match('Reparo Motor - GMC COMPONENTES ELÉTRICOS E AUTOMAÇÃO LTDA - 2026'), { kind: 'match', client: gmc });
  const result = match(gmc.nome); assert.equal(result.kind, 'match');
  if (result.kind === 'match') { assert.equal(result.client, gmc); assert.equal(result.client.id, id(1)); }
  assert.equal(gmc.nome, 'GMC COMPONENTES ELÉTRICOS E AUTOMAÇÃO LTDA');
});

test('comparison folds case, combining accents, punctuation, symbols and repeated spaces', () => {
  const match = createProjectClientMatcher([gmc]);
  for (const name of ['reparo - gmc componentes eletricos e automacao ltda - 2026', 'Motor GMC,COMPONENTES/ELÉTRICOS & E:AUTOMAÇÃO-LTDA', '  GMC   COMPONENTES   ELE\u0301TRICOS E AUTOMAC\u0327A\u0303O  LTDA  '])
    assert.deepEqual(match(name), { kind: 'match', client: gmc });
  assert.deepEqual(projectClientNameTokens('Á&B / Ç--9'), ['a', 'b', 'c', '9']);
});

test('complete token boundaries prevent a short client matching part of another word', () => {
  const match = createProjectClientMatcher([{ id: id(1), nome: 'ABC' }]);
  for (const name of ['XABC', 'ABCDEF', 'projeto abcd', 'A B C', '']) assert.deepEqual(match(name), { kind: 'none' });
  assert.equal(match('Projeto (ABC) 2026').kind, 'match');
});

test('a unique more specific client wins only when its full name contains the shorter matches', () => {
  const abc = { id: id(1), nome: 'ABC' }, engineering = { id: id(2), nome: 'ABC ENGENHARIA' }, engineeringBrasil = { id: id(3), nome: 'ABC ENGENHARIA BRASIL' };
  const match = createProjectClientMatcher([abc, engineering, engineeringBrasil]);
  assert.deepEqual(match('Projeto ABC ENGENHARIA'), { kind: 'match', client: engineering });
  assert.deepEqual(match('ABC engenharia Brasil / reparo'), { kind: 'match', client: engineeringBrasil });
});

test('multiple unrelated clients are ambiguous even when one name is longer', () => {
  const clients = [{ id: id(1), nome: 'ABC' }, { id: id(2), nome: 'Oficina de Engenharia Nacional' }];
  const match = createProjectClientMatcher(clients);
  assert.deepEqual(match('ABC / Oficina de Engenharia Nacional'), { kind: 'ambiguous' });
  assert.deepEqual(match('Oficina de Engenharia Nacional / ABC'), { kind: 'ambiguous' });
});

test('different UUIDs with the same normalized name remain ambiguous instead of picking the first', () => {
  const clients = [{ id: id(1), nome: 'ÁBC / Engenharia' }, { id: id(2), nome: 'abc engenharia' }];
  for (const rows of [clients, [...clients].reverse()]) assert.deepEqual(createProjectClientMatcher(rows)('Reparo ABC ENGENHARIA'), { kind: 'ambiguous' });
  assert.deepEqual(createProjectClientMatcher([clients[0], clients[0]])('Reparo ABC ENGENHARIA'), { kind: 'match', client: clients[0] });
});

test('empty and unnamed clients never become false suggestions', () => {
  const match = createProjectClientMatcher([{ id: id(1), nome: null }, { id: id(2), nome: ' -- ' }, { id: '', nome: 'Motor' }]);
  for (const text of ['', 'Projeto', ' -- ', 'Motor']) assert.deepEqual(match(text), { kind: 'none' });
});

test('the compiled index searches a large loaded catalogue including its last record without fetching', () => {
  const clients = Array.from({ length: 20_000 }, (_, n) => ({ id: id(n + 1), nome: `Cliente Equipamentos ${n + 1}` }));
  const match = createProjectClientMatcher(clients);
  assert.deepEqual(match('Reparo Motor - Cliente Equipamentos 20000 - OS 81'), { kind: 'match', client: clients[19_999] });
  assert.deepEqual(match('Outro equipamento'), { kind: 'none' });
  assert.deepEqual(match('Cliente Equipamentos 1 / Cliente Equipamentos 20000'), { kind: 'ambiguous' });
});

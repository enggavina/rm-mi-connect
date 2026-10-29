import test from 'node:test';
import assert from 'node:assert/strict';
import { blankQuestion, canManageFormTemplates, comparePositions, decimal, normalizeTemplatePositions, ordered, positionBetween, positionWarnings, templateSections, templateWarnings, type TemplateContent } from '../src/components/web/form-template-model';
import { validTemplateIndex } from '../src/server/web/form-template-policy';
import { formTemplateContentBytes } from '../src/shared/form-template-size';

const content = (): TemplateContent => ({ titulo: 'Ensaio', descricao: 'Instruções', title: 'Test', description: 'Instructions', tipo: null, questions: [
  { ...blankQuestion('heading', '1.1000', 'subt_tulo'), enunciado: 'Medições', title: 'Measurements', obrigatorio: true },
  { ...blankQuestion('question', '1.200000000000000000001', 'numero'), enunciado: 'Resistência', dimensoes: 'mili_ohms', title: 'Resistance', tag: 'R', obrigatorio: true },
] });

test('template editor management requires its own capability and RM administrator', () => {
  assert.equal(canManageFormTemplates({ profile: { perfil: 'administrador' }, sso: { capabilities: ['em.engineering.manage', 'em.form_templates.read'] } }), false);
  for (const perfil of ['padr_o', 'auditor', 'mobile']) assert.equal(canManageFormTemplates({ profile: { perfil }, sso: { capabilities: ['em.form_templates.manage'] } }), false);
  assert.equal(canManageFormTemplates({ profile: { perfil: 'administrador' }, sso: { capabilities: ['em.form_templates.manage'] } }), true);
});

test('decimal validation matches the wire schema without losing significant fractional digits', () => {
  for (const value of ['0', '-0.0', '+0001.2000', '.5', '1.', '999999999.9999999999999999', '1000000000.00000', '-1000000000', '0.' + '0'.repeat(56) + '1']) {
    assert.ok(decimal(value), value); assert.equal(validTemplateIndex(value), true);
  }
  for (const value of ['', ' ', '1e2', 'NaN', 'Infinity', '1,2', '1000000000.000000000001', '-1000000001', '0.' + '0'.repeat(59)]) {
    assert.equal(decimal(value), null, value); assert.equal(validTemplateIndex(value), false, value);
  }
  assert.equal(comparePositions('1.00000000000000000001', '1.00000000000000000002'), -1);
  assert.equal(comparePositions('+0001.2000', '1.2'), 0);
  assert.equal(comparePositions('-3.25', '-3.2'), -1);
});

test('insertions use an exact midpoint and leave neighbouring values untouched', () => {
  assert.equal(positionBetween('1.1', '1.2'), '1.15');
  assert.equal(positionBetween('1.00000000000000000001', '1.00000000000000000002'), '1.000000000000000000015');
  assert.equal(positionBetween('-0.02', '-0.01'), '-0.015');
  assert.equal(positionBetween(undefined, '-2.50'), '-3.5');
  assert.equal(positionBetween('1.2500'), '2.25'); assert.equal(positionBetween(), '1');
  for (const pair of [['1', '1.0'], ['2', '1'], ['bad', '2'], ['1000000000', undefined]] as const) assert.equal(positionBetween(...pair), null);
});

test('sorting and a text edit preserve exact old indices, alternative labels and item metadata', () => {
  const model = content(); model.questions.push({ ...blankQuestion('list', '10', 'lista_suspensa'), enunciado: 'Condição', items: [
    { id: 'item-a', indice: '2.0000000000001', descricao: 'A', description: 'Alternative A' }, { id: 'item-b', indice: '1.12500', descricao: 'B', description: null },
  ] });
  const before = structuredClone(model); const sorted = ordered(model.questions);
  assert.deepEqual(sorted.map(question => question.id), ['heading', 'question', 'list']); assert.deepEqual(model, before);
  const edited = { ...model, titulo: 'Novo título' }; assert.equal(edited.questions[1].indice, '1.200000000000000000001');
  assert.equal(edited.questions[2].items[0].description, 'Alternative A'); assert.equal(edited.questions[2].items[1].indice, '1.12500');
  assert.equal(edited.title, 'Test'); assert.equal(edited.description, 'Instructions');
});

test('duplicate numeric positions and mobile Number collisions are different publish blockers', () => {
  assert.match(positionWarnings([{ indice: '01.20' }, { indice: '+1.2000' }], 'Questões').join(' '), /repetidas/);
  assert.match(positionWarnings([{ indice: '1.0000000000000000001' }, { indice: '1.0000000000000000002' }], 'Questões').join(' '), /aplicativo/);
  assert.deepEqual(positionWarnings([{ indice: '1.1' }, { indice: '1.2' }], 'Questões'), []);
});

test('explicit normalization resolves ties while retaining IDs, alternative text and section boundaries', () => {
  const model = content(); model.questions.push({ ...blankQuestion('choices', '1.200000000000000000002', 'caixas_de_sele__o'), enunciado: 'Estado', items: [
    { id: 'i2', indice: '2.1', descricao: 'B', description: null }, { id: 'i1', indice: '2.10', descricao: 'A', description: 'Alternative' },
  ] });
  const before = structuredClone(model), normalized = normalizeTemplatePositions(model);
  assert.deepEqual(model, before); assert.deepEqual(normalized.questions.map(question => question.indice), ['1', '2', '3']);
  assert.deepEqual(normalized.questions[2].items.map(item => [item.id, item.indice]), [['i2', '1'], ['i1', '2']]);
  assert.equal(normalized.questions[2].items[1].description, 'Alternative'); assert.equal(normalized.questions[1].title, 'Resistance');
  assert.deepEqual(templateSections(normalized.questions).map(section => [section.title, section.questions.map(question => question.id)]), [['Medições', ['question', 'choices']]]);
  assert.deepEqual(templateWarnings(normalized), []);
});

test('preview keeps ungrouped questions and empty subtitles with exact decimal order', () => {
  const questions = [blankQuestion('late', '10'), { ...blankQuestion('section-b', '9', 'subt_tulo'), enunciado: 'Final' }, blankQuestion('first', '0.1'),
    { ...blankQuestion('section-a', '1.1', 'subt_tulo'), enunciado: 'Inicial' }, blankQuestion('middle', '1.2')];
  assert.deepEqual(templateSections(questions).map(section => [section.id, section.questions.map(question => question.id)]), [['general', ['first']], ['section-a', ['middle']], ['section-b', ['late']]]);
  assert.equal(templateSections([blankQuestion('empty', '1', 'subt_tulo')])[0].questions.length, 0);
});

test('publish warnings permit null classification and ignored subtitle flag but catch incomplete choices and incompatible fields', () => {
  assert.deepEqual(templateWarnings(content()), []);
  const model = content(); model.questions[1] = { ...model.questions[1], tipo: 'lista_suspensa', dimensoes: null };
  assert.match(templateWarnings(model).join(' '), /opção/);
  model.questions[1].items = [{ id: 'item', indice: '1', descricao: 'Aceito', description: null }];
  assert.deepEqual(templateWarnings(model), []);
  model.questions[1].tipo = 'data'; model.questions[1].subtipo = 'intervalo_de_hor_rios'; model.questions[1].dimensoes = 'volts'; model.questions[1].colaborador_filtro_perfil = 'mobile';
  const warnings = templateWarnings(model).join(' '); assert.match(warnings, /não usa opções/); assert.match(warnings, /intervalo/); assert.match(warnings, /unidade/); assert.match(warnings, /filtro de perfil/);
  assert.equal(model.questions[1].items.length, 1, 'Warnings never discard the prior choices.');
});

test('global content size and cross-question/item identity conflicts are detected before publication', () => {
  const model = content(); model.questions[1].items = [{ id: 'heading', indice: '1', descricao: 'Duplicado', description: null }];
  assert.match(templateWarnings(model).join(' '), /identificações repetidas/);
  model.descricao = 'á'.repeat(400_000); assert.match(templateWarnings(model).join(' '), /800 KB/);
  model.questions = [blankQuestion('only-title', '1', 'subt_tulo')]; assert.match(templateWarnings(model).join(' '), /ao menos uma questão/);
});

test('shared byte budget includes PostgreSQL separator spaces and UTF-8 near the publication boundary', () => {
  assert.equal(formTemplateContentBytes({ a: 'á', b: [true, null, '"\\\n'] }), Buffer.byteLength('{"a": "á", "b": [true, null, "\\\"\\\\\\n"]}', 'utf8'));
  assert.equal(formTemplateContentBytes({ a: [], b: {} }), Buffer.byteLength('{"a": [], "b": {}}'));
  const model = content(); model.descricao = '';
  const available = 800_000 - formTemplateContentBytes(model); model.descricao = 'a'.repeat(available);
  assert.equal(formTemplateContentBytes(model), 800_000); assert.equal(templateWarnings(model).some(warning => warning.includes('800 KB')), false);
  model.descricao += 'a'; assert.ok(Buffer.byteLength(JSON.stringify(model)) < 800_000, 'Compact JSON alone would allow the oversized JSONB value.');
  assert.equal(formTemplateContentBytes(model), 800_001); assert.equal(templateWarnings(model).some(warning => warning.includes('800 KB')), true);
});

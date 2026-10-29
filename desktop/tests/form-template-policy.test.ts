import test from 'node:test';
import assert from 'node:assert/strict';
import { formTemplateContentSchema, formTemplateContentBytes, validTemplateIndex, saveFormTemplateSchema, createFormTemplateSchema, publishFormTemplateSchema } from '../src/server/web/form-template-policy';
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const content = () => ({ titulo: '', descricao: null, title: null, description: null, tipo: null, questions: [
  { id: id(1), indice: '1.0000000000000000000000000000001', enunciado: '', title: null, subtitulo: null, tag: null, tipo: 'escolha__nica', subtipo: null, dimensoes: null, obrigatorio: true, colaborador_filtro_perfil: null, items: [] },
] });
const version = '2026-10-29T18:10:20.123456+00:00';
test('decimal indices retain all digits and reject exponent/rounding overflow without Number conversion', () => {
  for (const value of ['-1000000000.000', '+0001.5000', '.5', '-.5', '1.', '0', '1.00000000000000000000000000000000000000000000000000001']) assert.equal(validTemplateIndex(value), true, value);
  for (const value of ['1e2', '.', '+.', ' NaN', '1000000000.000000000000000000000000001', '-1000000001', '1'.repeat(61), 'Infinity']) assert.equal(validTemplateIndex(value), false, value);
  const input = { submissionId: id(8), id: id(9), expected_updated_at: version, content: content() };
  assert.deepEqual(saveFormTemplateSchema.parse(input), input);
});
test('drafts preserve blanks, no-choice questions and duplicate ordering while IDs stay globally unique', () => {
  const draft = content(); assert.equal(formTemplateContentSchema.safeParse(draft).success, true);
  draft.questions.push({ ...draft.questions[0], id: id(2) });
  assert.equal(formTemplateContentSchema.safeParse(draft).success, true);
  const collision = { ...draft, questions: [{ ...draft.questions[0], items: [{ id: id(2), indice: '0', descricao: '', description: null }] }, draft.questions[1]] };
  assert.equal(formTemplateContentSchema.safeParse(collision).success, false);
  assert.equal(formTemplateContentSchema.safeParse({ ...draft, questions: Array.from({ length: 1001 }, (_, n) => ({ ...draft.questions[0], id: id(n + 100) })) }).success, false);
});
test('content is strict, permits long text within the shared UTF8 budget and accounts for PostgreSQL separators', () => {
  const draft = content();
  assert.equal(formTemplateContentSchema.safeParse({ ...draft, descricao: 'x'.repeat(20_000) }).success, true);
  assert.equal(formTemplateContentSchema.safeParse({ ...draft, descricao: 'é'.repeat(400_000) }).success, false);
  assert.equal(formTemplateContentBytes({ a: ['é', 1] }), Buffer.byteLength('{"a": ["é", 1]}'));
  for (const bad of [{ ...draft, source_snapshot: { imagem_capa_url: 'https://private.invalid' } },
    { ...draft, created_by: id(2) }, { ...draft, questions: [{ ...draft.questions[0], tipo: 'unknown' }] },
    { ...draft, questions: [{ ...draft.questions[0], origem_id: id(9) }] },
    { ...draft, questions: [{ ...draft.questions[0], items: [{ id: id(3), indice: '1', descricao: '', description: null, actor: id(4) }] }] }]) {
    assert.equal(formTemplateContentSchema.safeParse(bad).success, false);
  }
});
test('create source semantics and exact publish revision cannot be bypassed with extra payload', () => {
  const base = { submissionId: id(8), id: id(9), kind: 'new', source_form_id: null };
  assert.equal(createFormTemplateSchema.safeParse(base).success, true);
  assert.equal(createFormTemplateSchema.safeParse({ ...base, kind: 'copy', source_form_id: id(7) }).success, true);
  for (const value of [{ ...base, kind: 'version' }, { ...base, source_form_id: id(7) }, { ...base, actor_id: id(6) }]) assert.equal(createFormTemplateSchema.safeParse(value).success, false);
  assert.equal(publishFormTemplateSchema.parse({ submissionId: id(8), id: id(9), expected_updated_at: version }).expected_updated_at, version);
  assert.equal(publishFormTemplateSchema.safeParse({ submissionId: id(8), id: id(9), expected_updated_at: null }).success, false);
});

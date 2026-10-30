import test from 'node:test';
import assert from 'node:assert/strict';
import { answerDisplayKey, answerHasValue, approvalActions, canApprove, canCorrectAnswer, displayedRecordAnswers, emptyAnswer, firstInvalidSection, formSections, hasQuestionId, naAnswer, qrProjectValue, recordedQuestions, sectionForQuestion, storedAnswer, validateAnswer } from '../src/domain/forms';

test('retirement blocks every approval role, including administrators, without rejecting legacy active stages', () => {
  const stage = { id: 'retired', ativo: false, aprovador_id: 'assigned', aprovadores_ids: ['listed'], aprovadores_retorno_ids: ['return-only'] };
  for (const operator of [{ operador_id: 'admin', perfil: 'administrador' }, { operador_id: 'assigned' }, { operador_id: 'listed' }, { operador_id: 'return-only' }, { operador_id: 'signer', perfil_assinante: ['aprovador'] }]) {
    assert.equal(canApprove(operator, stage), false);
    assert.ok(approvalActions.every(action => !canApprove(operator, stage, action)));
  }
  assert.equal(canApprove({ operador_id: 'admin', perfil: 'administrador' }, { id: 'legacy' }), true);
  assert.equal(canApprove({ operador_id: 'assigned' }, { ...stage, ativo: true }, 'aprovar'), true);
});
import type { Row } from '../src/core/types';

const stage: Row = {id:'gate',aprovador_id:null,aprovadores_ids:[],aprovadores_retorno_ids:['return-only']};
test('a return-only approver cannot queue approval or release actions', () => {
  const operator={operador_id:'return-only',perfil:'mobile',perfil_assinante:[]};
  assert.equal(canApprove(operator,stage),true);
  assert.deepEqual(approvalActions.filter(action => canApprove(operator,stage,action)),['retornar']);
});
test('unassigned stage accepts verifier signature roles, but explicit assignment overrides fallback', () => {
  const operator={operador_id:'verifier',perfil:'mobile',perfil_assinante:['aprovador_supervis_o']};
  assert.ok(approvalActions.every(action => canApprove(operator,stage,action)));
  assert.equal(canApprove(operator,{...stage,aprovador_id:'other'},'aprovar'),false);
  assert.equal(canApprove({operador_id:'admin',perfil:'administrador'},stage,'finalizar_ciclo'),true);
  assert.equal(canApprove({operador_id:'x',perfil:'gestor'},stage,'aprovar'),false);
});
test('legacy N/A media remains valid during form revision', () => {
  const q:Row={id:'photo',indice:1,enunciado:'Antes/depois',tipo:'foto_antes_depois',obrigatorio:true};
  assert.equal(validateAnswer(q,{...emptyAnswer(q),resposta:'N/A'}),null);
  assert.equal(validateAnswer(q,naAnswer(q)),null);
});
test('optional before/after photos allow none, but one side cannot be submitted', () => {
  const q:Row={id:'photo',indice:1,enunciado:'Antes/depois',tipo:'foto_antes_depois',obrigatorio:false};
  assert.equal(validateAnswer(q,emptyAnswer(q)),null);
  assert.match(validateAnswer(q,{...emptyAnswer(q),fotos_urls:['','file:///after.jpg']})!,/antes e depois/);
  assert.equal(validateAnswer(q,{...emptyAnswer(q),fotos_urls:['file:///before.jpg','file:///after.jpg']}),null);
});
test('time intervals require both endpoints and maintain chronological order', () => {
  const q:Row={id:'time',indice:1,enunciado:'Ensaio',tipo:'hora',subtipo:'intervalo_de_hor_rios',obrigatorio:true};
  const a={...emptyAnswer(q),hora:'2026-10-27T12:00:00Z',date_inicio:'2026-10-27T12:00:00Z',data_fim:'2026-10-27T13:00:00Z'};
  assert.equal(validateAnswer(q,a),null);
  assert.match(validateAnswer(q,{...a,data_fim:null})!,/início e o fim/);
  assert.match(validateAnswer(q,{...a,data_fim:'2026-10-27T11:00:00Z'})!,/posterior/);
});
test('question type determines whether mandatory data is present', () => {
  const q:Row={id:'sign',indice:1,enunciado:'Assine',tipo:'assinatura',obrigatorio:true};
  assert.equal(validateAnswer(q,{...emptyAnswer(q),resposta:'old imported text'}),'Preenchimento obrigatório.');
});
test('QR payloads resolve project UUID, number, legacy path, and plain OS', () => {
  assert.equal(qrProjectValue('https://rm.example/projeto?projeto=id-1'),'id-1');
  assert.equal(qrProjectValue('https://rm.example/projeto/123'),'123');
  assert.equal(qrProjectValue(' OS-42 '),'OS-42');
});

test('subtitles own following questions by numeric fractional index without dropping ungrouped answers', () => {
  const questions: Row[] = [
    { id: 'late', indice: 10, tipo: 'texto_curto' },
    { id: 'early', indice: 0, tipo: 'texto_curto' },
    { id: 'section-b', indice: 9, tipo: 'subt_tulo', enunciado: 'Final' },
    { id: 'decimal', indice: 1.2, tipo: 'numero' },
    { id: 'section-a', indice: 1.1, tipo: 'subt_tulo', enunciado: 'Medições' },
  ];
  const before = JSON.stringify(questions); const sections = formSections(questions);
  assert.deepEqual(sections.map(section => [section.id, section.questions.map(question => question.id)]), [['__general', ['early']], ['section-a', ['decimal']], ['section-b', ['late']]]);
  assert.equal(sections[0].subtitle, undefined);
  assert.equal(sections[1].title, 'Medições');
  assert.equal(JSON.stringify(questions), before);
});

test('empty consecutive subtitles and a form without subtitles retain their question boundaries', () => {
  const questions: Row[] = [{ id: 'a', indice: 1, tipo: 'subt_tulo' }, { id: 'b', indice: 2, tipo: 'subt_tulo' }, { id: 'q', indice: 3, tipo: 'texto_curto' }];
  assert.deepEqual(formSections(questions).map(section => section.questions.length), [0, 1]);
  assert.deepEqual(formSections([questions[2]]).map(section => section.questions.map(q => q.id)), [['q']]);
  assert.deepEqual(formSections([]), []);
});

test('validation opens the first invalid section in form order, including a hidden mandatory photo', () => {
  const photo: Row = { id: 'photo', indice: 2, tipo: 'foto', enunciado: 'Evidência', obrigatorio: true };
  const sections = formSections([{ id: 'one', indice: 1, tipo: 'subt_tulo' }, photo, { id: 'two', indice: 3, tipo: 'subt_tulo' }, { id: 'later', indice: 4, tipo: 'texto_curto' }]);
  const errors = { later: 'Preenchimento obrigatório.', photo: validateAnswer(photo, emptyAnswer(photo))! };
  assert.equal(firstInvalidSection(sections, errors)?.id, 'one');
  assert.equal(sectionForQuestion(sections, 'later')?.id, 'two');
  assert.equal(sectionForQuestion(sections, 'unknown'), undefined);
  assert.equal(firstInvalidSection(sections, {}), undefined);
});

test('post-submission corrections require both the returned record status and the answer review flag', () => {
  const answer = { ...emptyAnswer({ id: 'q', indice: 1, tipo: 'texto_curto', enunciado: 'Questão' }), revisar: true, resposta_id: 'original-answer', resposta: 'Original' };
  assert.equal(canCorrectAnswer({ id: 'record', status: 'direcionado' }, answer), true);
  for (const status of ['em_an_lise', 'aprovado', 'pendente']) assert.equal(canCorrectAnswer({ id: 'record', status }, answer), false);
  assert.equal(canCorrectAnswer({ id: 'record', status: 'direcionado' }, { ...answer, revisar: false }), false);
  assert.equal(canCorrectAnswer(undefined, answer), false);
  assert.equal(canCorrectAnswer({ id: 'record', status: 'direcionado' }, undefined), false);
  assert.equal(answer.resposta_id, 'original-answer');
  assert.equal(answer.resposta, 'Original');
});

test('viewing a submitted record preserves answer snapshots and never invents newly added questions', () => {
  const templates: Row[] = [
    { id: 'subtitle', indice: 1, tipo: 'subt_tulo', enunciado: 'Seção' },
    { id: 'original', indice: 7, tipo: 'numero', enunciado: 'Rótulo novo', obrigatorio: true, subtipo: null },
    { id: 'new', indice: 8, tipo: 'texto_curto', enunciado: 'Criada depois do envio' },
  ];
  const original = storedAnswer({ id: 'response', questao_id: 'original', indice: 1.5, enunciado: 'Rótulo enviado', tipo: 'numero', dimensoes: 'mm', resposta: '0,000', revisar: true });
  const legacy = storedAnswer({ id: 'response-legacy', questao_id: 'legacy', indice: 2, enunciado: 'Questão preservada', tipo: 'texto_curto', resposta: 'Texto' });
  const rows = recordedQuestions(templates, [original, legacy]);
  assert.deepEqual(rows.map(row => row.id), ['subtitle', 'original', 'legacy']);
  assert.equal(rows[1].enunciado, 'Rótulo enviado');
  assert.equal(rows[1].indice, 1.5);
  assert.equal(rows[1].obrigatorio, true);
  assert.equal(original.resposta_id, 'response');
  assert.equal(original.revisar, true);
  assert.deepEqual(recordedQuestions(templates, []), []);
});

test('section progress counts typed data and explicit N/A while excluding visual dividers', () => {
  const photo: Row = { id: 'photo', indice: 1, tipo: 'foto', enunciado: 'Foto' };
  assert.equal(answerHasValue(photo, emptyAnswer(photo)), false);
  assert.equal(answerHasValue(photo, { ...emptyAnswer(photo), resposta: 'Texto antigo' }), false);
  assert.equal(answerHasValue(photo, naAnswer(photo)), true);
  assert.equal(answerHasValue(photo, { ...emptyAnswer(photo), fotos_urls: ['file:///image.jpg'] }), true);
  const number: Row = { id: 'number', indice: 2, tipo: 'numero', enunciado: 'Número' };
  assert.equal(answerHasValue(number, { ...emptyAnswer(number), resposta: '0,000' }), true);
  assert.equal(answerHasValue({ ...number, tipo: 'subt_tulo' }, { ...emptyAnswer(number), resposta: 'N/A' }), false);
});

test('historical responses without a question retain distinct stable keys, order and subtitle snapshots', () => {
  const originals = [
    storedAnswer({ id: 'legacy-title', questao_id: null, indice: 1.1, tipo: 'subt_tulo', enunciado: 'Título original', subtitulo: 'Instrução original' }),
    storedAnswer({ id: 'legacy-one', questao_id: null, indice: 1.2, tipo: 'texto_curto', enunciado: 'Questão removida A', resposta: 'Primeira resposta', revisar: true }),
    storedAnswer({ id: 'legacy-two', indice: 1.3, tipo: 'texto_curto', enunciado: 'Questão removida B', resposta: 'Segunda resposta', revisar: true }),
  ];
  const shown = displayedRecordAnswers(originals);
  assert.deepEqual(Object.keys(shown), ['snapshot:legacy-title', 'snapshot:legacy-one', 'snapshot:legacy-two']);
  assert.equal(shown['snapshot:legacy-one'].resposta, 'Primeira resposta');
  assert.equal(shown['snapshot:legacy-two'].resposta, 'Segunda resposta');
  const questions = recordedQuestions([], Object.values(shown));
  const sections = formSections(questions);
  assert.equal(sections[0].title, 'Título original');
  assert.equal(sections[0].description, 'Instrução original');
  assert.deepEqual(sections[0].questions.map(question => question.id), ['snapshot:legacy-one', 'snapshot:legacy-two']);
  assert.deepEqual(questions.map(question => question.indice), [1.1, 1.2, 1.3]);
  const changedTemplate = [{ id: 'new-template-title', indice: 1.1, tipo: 'subt_tulo', enunciado: 'Título alterado depois' }];
  const snapshotSections = formSections(recordedQuestions(changedTemplate, originals));
  assert.equal(snapshotSections.length, 1);
  assert.equal(snapshotSections[0].title, 'Título original');
  for (const original of originals) {
    assert.equal(hasQuestionId(original), false);
    assert.equal(canCorrectAnswer({ id: 'record', status: 'direcionado' }, original), false);
  }
});

test('loading an editable revision preserves read-only orphan snapshots without putting them into the draft', () => {
  const orphan = storedAnswer({ id: 'orphan', questao_id: null, indice: 2, tipo: 'numero', enunciado: 'Histórico', resposta: '4,2', revisar: true });
  const linked = storedAnswer({ id: 'linked-response', questao_id: 'linked-question', indice: 3, tipo: 'texto_curto', enunciado: 'Corrigir', resposta: 'Original', revisar: true });
  assert.ok(hasQuestionId(linked));
  const draft = { 'linked-question': { ...linked, resposta: 'Correção local' } };
  const before = JSON.stringify(draft);
  const shown = displayedRecordAnswers([orphan, linked], draft);
  assert.equal(shown['linked-question'].resposta, 'Correção local');
  assert.equal(shown['snapshot:orphan'].resposta, '4,2');
  assert.equal(canCorrectAnswer({ id: 'record', status: 'direcionado' }, shown['snapshot:orphan']), false);
  assert.equal(canCorrectAnswer({ id: 'record', status: 'direcionado' }, shown['linked-question']), true);
  assert.equal(answerDisplayKey(linked), 'linked-question');
  assert.equal(JSON.stringify(draft), before);
  assert.deepEqual(Object.keys(draft), ['linked-question']);
});

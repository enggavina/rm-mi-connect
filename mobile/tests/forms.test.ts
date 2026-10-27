import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalActions, canApprove, emptyAnswer, naAnswer, qrProjectValue, validateAnswer } from '../src/domain/forms';
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

import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { canonicalJson, decodeBase64, isConnectivityError, replaceMedia, retryDelay, uploadThenMutate, validateAnswers } from '../src/core/sync-policy';
import { RM_MOBILE_SQLITE_DDL } from '../src/core/schema';
import type { Answer, Row } from '../src/core/types';

test('all media uploads must complete before any mutation is attempted', async () => {
  const order: string[] = [];
  await uploadThenMutate(async () => { order.push('photo', 'signature'); }, async () => { order.push('rpc'); });
  assert.deepEqual(order, ['photo', 'signature', 'rpc']);
  let mutations = 0;
  await assert.rejects(uploadThenMutate(async () => { throw new Error('Wi-Fi dropped'); }, async () => { mutations++; }));
  assert.equal(mutations, 0);
});
test('reusing a submission ID compares payload content independently of object key order', () => {
  assert.equal(canonicalJson({b:2,a:{z:3,y:1}}),canonicalJson({a:{y:1,z:3},b:2}));
  assert.notEqual(canonicalJson({a:['before','after']}),canonicalJson({a:['after','before']}));
  assert.notEqual(canonicalJson({p_operador_id:'alice'}),canonicalJson({p_operador_id:'bob'}));
});
test('Wi-Fi connectivity failure permits cached identification while rejected credentials never do', () => {
  assert.equal(isConnectivityError(new TypeError('Network request failed')),true);
  assert.equal(isConnectivityError({message:'Failed to fetch',code:''}),true);
  assert.equal(isConnectivityError({code:'28P01',message:'Invalid password'}),false);
  assert.equal(isConnectivityError({status:401,message:'Network request failed'}),false);
  assert.equal(isConnectivityError(new TypeError('Cannot read properties of undefined')),false);
});
test('media replacement resolves nested array fields and rejects missing uploads', () => {
  const original = { p_respostas: [{ fotos_urls: ['file:///photo.jpg'], assinatura_url: 'file:///signature.png' }], note: 'file name is plain text' };
  const urls = new Map([['file:///photo.jpg', 'https://storage/photo.jpg'], ['file:///signature.png', 'https://storage/signature.png']]);
  const result = replaceMedia(original, urls);
  assert.equal(result.p_respostas[0].fotos_urls[0], 'https://storage/photo.jpg');
  assert.equal(result.p_respostas[0].assinatura_url, 'https://storage/signature.png');
  assert.equal(original.p_respostas[0].assinatura_url, 'file:///signature.png');
  assert.throws(() => replaceMedia(original, new Map()), /mídia ainda não foi enviada/);
});
test('retry backoff increases exponentially and remains bounded', () => {
  assert.equal(retryDelay(1, () => 0), 1000);
  assert.equal(retryDelay(2, () => 0), 2000);
  assert.equal(retryDelay(6, () => 0), 32000);
  assert.ok(retryDelay(1000, () => 1) <= 301000);
});
test('required media and date range cannot be silently submitted empty', () => {
  const questions: Row[] = [
    {id: 'a', enunciado: 'Antes/depois', tipo: 'foto_antes_depois', obrigatorio: true},
    {id: 'b', enunciado: 'Período', tipo: 'data', subtipo: 'intervalo_de_datas', obrigatorio: true},
    {id: 'c', enunciado: 'Seção', tipo: 'subt_tulo', obrigatorio: true},
  ];
  const answers: Answer[] = [
    {questao_id: 'a', indice: 1, enunciado: 'Antes/depois', tipo: 'foto_antes_depois', fotos_urls: ['file://a']},
    {questao_id: 'b', indice: 2, enunciado: 'Período', tipo: 'data', date_inicio: '2026-10-27', data_fim: '2026-10-26'},
  ];
  assert.deepEqual(validateAnswers(questions, answers), ['Antes/depois', 'Período']);
  answers[0].is_na = true;
  answers[1].data_fim = '2026-10-28';
  assert.deepEqual(validateAnswers(questions, answers), []);
});
test('required decimal accepts a decimal comma and rejects malformed text', () => {
  const q = {id: 'n', enunciado: 'Corrente', tipo: 'numero', obrigatorio: true};
  const a: Answer = {questao_id: 'n', enunciado: 'Corrente', indice: 1, tipo: 'numero', resposta: '0,000'};
  assert.deepEqual(validateAnswers([q], [a]), []);
  assert.deepEqual(validateAnswers([q], [{...a, resposta: '1,2,3'}]), ['Corrente']);
});
test('image decoding preserves binary data for Supabase Storage upload', () => {
  assert.deepEqual(decodeBase64('AAECA/7/'), Uint8Array.from([0,1,2,3,254,255]));
  assert.deepEqual(decodeBase64('aGVsbG8='), Uint8Array.from(Buffer.from('hello')));
  assert.throws(() => decodeBase64('***'));
});
test('provided SQLite schema isolates drafts by actor and enforces stable submission ids', () => {
  const db = new DatabaseSync(':memory:');
  db.exec(RM_MOBILE_SQLITE_DDL);
  const insert = db.prepare('INSERT INTO local_form_drafts(draft_id,client_submission_id,projeto_id,celula_id,form_id,operador_id,started_at) VALUES (?,?,?,?,?,?,?)');
  insert.run('d1','submission-1','project','cell','form','alice','2026-10-27');
  insert.run('d2','submission-2','project','cell','form','bob','2026-10-27');
  assert.throws(() => insert.run('d3','submission-1','project','cell','form','carol','2026-10-27'), /UNIQUE/);
  assert.throws(() => insert.run('d4','submission-4','project','cell','form','alice','2026-10-27'), /UNIQUE/);
  db.exec("INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES ('operation','rm_submit_form_inspection_v1','{}','2026-10-27')");
  db.exec("DELETE FROM local_operator_session");
  assert.equal(db.prepare('SELECT count(*) AS n FROM local_rpc_outbox').get()?.n, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM local_form_drafts').get()?.n, 2);
  db.close();
});

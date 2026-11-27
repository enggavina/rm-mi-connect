import assert from 'node:assert/strict';
import test from 'node:test';
import { freezeReviewRequest, mayReview, recordSections, safeAnswerMedia } from '../src/components/web/review-model';
import { relayLegacyWorkshopImage, resolveWorkshopMedia, workshopMediaTarget } from '../src/server/web/workshop-media';
import { workshopMediaUrl } from '../src/shared/workshop-media';

test('record sections preserve submitted text, fractional order, choices and orphan answers without adding unanswered questions', () => {
  const sections = recordSections([
    { id: 'a2', questao_id: 'q2', indice: 1.5, enunciado: 'Texto na época', resposta: 'Medida preservada', itens: ['Escolha na época'] },
    { id: 'a1', questao_id: 'q1', indice: 1.2, enunciado: 'Primeira resposta', itens_questoes_ids: ['item'] },
    { id: 'old-null', questao_id: null, indice: 2, enunciado: 'Questão removida', resposta: 'Snapshot' },
    { id: 'old-other', questao_id: 'other-form', indice: 3, enunciado: 'Questão de outro modelo', fotos_urls: ['https://files.cdn.bubble.io/old.jpg'] },
  ], [
    { id: 'subtitle', tipo: 'subt_tulo', indice: 1, enunciado: 'Medições', subtitulo: 'Conferir dimensões' },
    { id: 'q2', tipo: 'texto', indice: 5, enunciado: 'Título novo' },
    { id: 'q1', tipo: 'lista', indice: 1.2 }, { id: 'new', indice: 8, enunciado: 'Questão adicionada depois' },
  ], [{ id: 'item', descricao: 'Descrição do item' }]);
  assert.equal(sections.length, 2); assert.equal(sections[0].title, 'Medições');
  assert.deepEqual(sections[0].answers.map(answer => answer.id), ['a1', 'a2']);
  assert.equal(sections[0].answers[1].label, 'Texto na época'); assert.equal(sections[0].answers[1].indice, 1.5);
  assert.equal(sections[0].answers[1].resposta, 'Medida preservada');
  assert.deepEqual(sections[0].answers[0].itemLabels, ['Descrição do item']);
  assert.deepEqual(sections[0].answers[1].itemLabels, ['Escolha na época']);
  assert.equal(sections.flatMap(section => section.answers).length, 4);
  assert.ok(sections[1].answers.every(answer => answer.historical && !answer.canCorrect));
  assert.deepEqual(sections[1].answers[1].fotos_urls, ['https://files.cdn.bubble.io/old.jpg']);
});

test('submitted subtitle remains visible but cannot be selected for correction', () => {
  const sections = recordSections([{ id: 'a', questao_id: 'q', tipo: 'subt_tulo', indice: 1, enunciado: 'Título original' }], [{ id: 'q', tipo: 'subt_tulo', indice: 9, enunciado: 'Novo título' }], []);
  assert.equal(sections[0].title, 'Título original');
  assert.equal(sections[0].answers[0].canCorrect, false);
});

test('only an administrator or assigned reviewer sees actions on a submitted record in analysis', () => {
  const record = { id: 'r', status: 'em_an_lise', preenchido: true, avaliador_user_id: 'reviewer', aprovadores_ids: ['assigned'] };
  for (const profile of [{ id: 'admin', perfil: 'administrador' }, { id: 'reviewer', perfil: 'padr_o' }, { id: 'assigned', perfil: 'auditor' }]) assert.equal(mayReview(record, profile), true);
  assert.equal(mayReview(record, { id: 'unassigned', perfil: 'padr_o' }), false);
  for (const status of ['direcionado', 'aprovado', 'nulo']) assert.equal(mayReview({ ...record, status }, { id: 'admin', perfil: 'administrador' }), false);
  assert.equal(mayReview({ ...record, preenchido: false }, { id: 'admin', perfil: 'administrador' }), false);
});

test('retry request keeps its UUID, precise database version and frozen selection after editing draft state', () => {
  const selected = ['a']; const timestamp = '2026-10-29T01:00:00.123456+00:00';
  const draft = { submissionId: 'attempt-1', registro_formulario_id: 'r', expected_updated_at: timestamp, decision: 'return' as const, parecer: 'Conferir', resposta_ids: selected };
  const request = freezeReviewRequest(draft); selected.push('b'); draft.parecer = 'Other decision';
  assert.deepEqual(request.resposta_ids, ['a']); assert.equal(request.parecer, 'Conferir');
  assert.equal(request.expected_updated_at, timestamp); assert.equal(request.submissionId, 'attempt-1');
  assert.equal(Object.isFrozen(request), true); assert.equal(Object.isFrozen(request.resposta_ids), true);
});

test('answer media allows existing Bubble CDN and configured public photo/signature buckets only', () => {
  const base = 'https://project.supabase.co';
  for (const value of ['https://files.cdn.bubble.io/image.jpg', `${base}/storage/v1/object/public/rm-assinaturas/a.png`, `${base}/storage/v1/object/public/rm-fotos/a.jpg`]) assert.equal(safeAnswerMedia(value, base), value);
  for (const value of ['javascript:alert(1)', 'file:///secret.png', 'data:image/svg+xml,bad', 'http://files.cdn.bubble.io/a', 'https://u:p@files.cdn.bubble.io/a', 'https://files.cdn.bubble.io.evil.test/a', 'https://127.0.0.1/a', `${base}/storage/v1/object/authenticated/rm-documentos/a.pdf`, `${base}/storage/v1/object/public/rm-documentos/a.pdf`]) assert.equal(safeAnswerMedia(value, base), null);
});

test('workshop media accepts exact local references and restricts signing by storage origin and media bucket', () => {
  const base = 'https://example.supabase.co';
  const id = '00000000-0000-4000-8000-000000000001';
  const photo = workshopMediaUrl(id, 'answer_photo', 2);
  assert.equal(safeAnswerMedia(photo, base), photo);
  assert.equal(safeAnswerMedia(`${photo}&unexpected=1`, base), null);
  assert.equal(workshopMediaTarget('https://files.cdn.bubble.io/legacy.jpg', base, 'project_photo')?.kind, 'legacy');
  assert.deepEqual(workshopMediaTarget(`${base}/storage/v1/object/public/rm-fotos/owner/title%20view.jpg`, base, 'answer_photo'),
    { kind: 'storage', origin: base, bucket: 'rm-fotos', path: 'owner/title view.jpg' });
  assert.equal(workshopMediaTarget(`${base}/storage/v1/object/public/rm-fotos/owner/f.jpg`, base, 'answer_signature'), null);
  assert.equal(workshopMediaTarget(`${base}/storage/v1/object/public/rm-fotos/owner%2F..%2Ffile.jpg`, base, 'project_photo'), null);
  assert.equal(workshopMediaTarget(`${base}/storage/v1/object/public/rm-fotos/other/%2e%2e/file.jpg`, base, 'project_photo'), null);
  assert.equal(workshopMediaTarget(`${base}/storage/v1/object/public/rm-fotos/owner/f.jpg?token=known`, base, 'project_photo'), null);
  assert.equal(workshopMediaTarget('https://files.cdn.bubble.io.example.org/legacy.jpg', base, 'project_photo'), null);
});

test('media download signs only the expected object and keeps legacy attachments readable', async () => {
  const base = 'https://example.supabase.co';
  const invoice = `${base}/storage/v1/object/authenticated/rm-documentos/device/a%20b.pdf`;
  const signed = `${base}/storage/v1/object/sign/rm-documentos/device/a%20b.pdf?token=opaque`;
  assert.equal(await resolveWorkshopMedia(invoice, base, 'document', async (bucket, path) => {
    assert.equal(bucket, 'rm-documentos');
    assert.equal(path, 'device/a b.pdf');
    return signed;
  }), signed);
  assert.equal(await resolveWorkshopMedia(invoice, base, 'document', async () => signed.replace('a%20b.pdf', 'different.pdf')), null);
  assert.equal(await resolveWorkshopMedia(invoice, base, 'document', async () => signed.replace(base, 'https://unrelated.example')), null);
  assert.equal(await resolveWorkshopMedia(invoice, base, 'document', async () => `${signed}&token=duplicate`), null);
  const legacy = 'https://files.cdn.bubble.io/legacy.jpg';
  assert.equal(await resolveWorkshopMedia(legacy, base, 'answer_photo', async () => assert.fail('Legacy URL does not sign storage')), legacy);
});

test('the legacy image relay streams approved image formats without forwarding credentials or redirects', async t => {
  const url = 'https://files.cdn.bubble.io/legacy.heic';
  const bytes = new Uint8Array([1, 2, 3]);
  const fetchMock = t.mock.method(globalThis, 'fetch', async (input: Parameters<typeof fetch>[0], options?: RequestInit) => {
    assert.equal(input, url);
    assert.equal(options?.redirect, 'error');
    assert.equal(options?.credentials, 'omit');
    assert.equal(options?.cache, 'no-store');
    assert.equal(options?.headers, undefined);
    return new Response(bytes, { headers: { 'Content-Type': 'image/heic', 'Content-Length': '3' } });
  });
  const relay = await relayLegacyWorkshopImage(url, new AbortController().signal);
  assert.equal(fetchMock.mock.callCount(), 1);
  assert.equal(relay?.type, 'image/heic');
  assert.deepEqual(new Uint8Array(await new Response(relay?.body).arrayBuffer()), bytes);
});

test('the legacy image relay rejects unsafe types, failed responses and over-limit bodies', async t => {
  const url = 'https://files.cdn.bubble.io/legacy.jpg';
  const signal = new AbortController().signal;
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => new Response('file'));
  const denied: ResponseInit[] = [
    { headers: { 'Content-Type': 'image/svg+xml' } },
    { status: 404, headers: { 'Content-Type': 'image/jpeg' } },
    { headers: { 'Content-Type': 'image/jpeg', 'Content-Length': String(21 * 1024 * 1024) } },
  ];
  for (const init of denied) {
    fetchMock.mock.mockImplementationOnce(async () => new Response('file', init));
    assert.equal(await relayLegacyWorkshopImage(url, signal), null);
  }
  fetchMock.mock.mockImplementationOnce(async () => new Response(new Uint8Array(21 * 1024 * 1024), { headers: { 'Content-Type': 'image/jpeg' } }));
  const relay = await relayLegacyWorkshopImage(url, signal);
  await assert.rejects(new Response(relay?.body).arrayBuffer(), /excede o limite/);
});

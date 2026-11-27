import assert from 'node:assert/strict';
import test from 'node:test';
import { mediaUploadMime, queuedMediaIntents, receivingMediaTransfer, sendWorkshopMediaUpload } from '../src/core/media-upload-workshop';
import type { OutboxRow } from '../src/core/types';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const origin = 'https://example.supabase.co';
const asset = id(5), workshopOrigin = id(6), submission = id(7);
const receipt = `file:///local/rm-media/${asset}.pdf`, photo = `file:///local/rm-media/${id(8)}.jpg`;
const signature = `file:///local/rm-media/${id(9)}.png`, freeText = `file:///this-is-just-a-note`;
const outbox = (rpc_name: OutboxRow['rpc_name'], payload: object, n: number): OutboxRow => ({
  id: id(n), workshop_id: workshopOrigin, rpc_name, params_json: JSON.stringify(payload), status: 'pending', attempts: 0,
  created_at: '2026-11-27T02:00:00Z', next_retry_at: 0, actor_id: id(11), token_key: `local:${n}`, draft_id: null,
});

test('the offline uploader selects only the original attachment fields and keeps the first pending protocol', () => {
  const initial = outbox('rm_submit_recebimento_v1', { p_arquivo_nota_fiscal_url: receipt,
    p_fotos_recebimento: [{ foto_url: photo }], p_descricao_equipamento: freeText }, 7);
  const correction = outbox('rm_submit_form_revision_v1', { p_respostas_corrigidas: [{
    assinatura_url: signature, fotos_urls: [photo, 'https://legacy.invalid/file.png'], resposta: freeText,
  }] }, 12);
  const available = queuedMediaIntents([initial, correction, { ...initial, params_json: 'invalid JSON' }]);
  assert.deepEqual([...available.keys()], [receipt, photo, signature]);
  assert.deepEqual([available.get(receipt)?.kind, available.get(photo)?.row.id, available.get(signature)?.kind], ['document', submission, 'signature']);
  assert.equal(available.has(freeText), false);
  assert.equal(mediaUploadMime('rm-assinaturas'), 'image/png');
  assert.equal(mediaUploadMime('rm-documentos', 'application/pdf'), 'application/pdf');
});

test('binary uploads accept only the stored response for the original file and workshop', async () => {
  const path = `mobile-oficina/${workshopOrigin}/${submission}/${asset}.pdf`;
  const url = `${origin}/storage/v1/object/authenticated/rm-documentos/${path}`;
  const metadata = { workshopOrigin, submission, asset, operation: 'rm_submit_recebimento_v1' as const,
    payload: { p_arquivo_nota_fiscal_url: receipt }, kind: 'document' as const, mime: 'application/pdf' as const,
    reference: receipt, size: 5, sha256: '8'.repeat(64) };
  const input = { ...metadata, deviceToken: 'example-device', operatorToken: 'example-operator' };
  const file = new File(['%PDF-'], `${asset}.pdf`, { type: 'application/pdf' });
  const result = { asset_id: asset, workshop_id: workshopOrigin, submission_id: submission, path, stored: true, url };
  const saved = await sendWorkshopMediaUpload(input, file, origin, async (target, init) => {
    assert.match(String(target), /\/api\/mobile\/midia\/envio$/);
    assert.equal(new Headers(init?.headers).get('x-em-operator'), input.operatorToken);
    assert.equal(new Headers(init?.headers).get('authorization'), `Bearer ${input.deviceToken}`);
    const form = init?.body as FormData;
    assert.deepEqual(JSON.parse(String(form.get('input'))), metadata);
    assert.equal((form.get('file') as File).size, file.size);
    return Response.json(result);
  });
  assert.equal(saved, url);
  await assert.rejects(sendWorkshopMediaUpload(input, file, origin, async () => Response.json({ ...result, workshop_id: id(99) })));
  await assert.rejects(sendWorkshopMediaUpload(input, file, origin, async () => Response.json({ ...result, stored: false })));
});

test('the same receiving asset uses a stable upload contract before and after queuing its draft', () => {
  const fromDraft = receivingMediaTransfer(submission, id(11), id(12), null, receipt, 'document');
  const pending = outbox('rm_submit_recebimento_v1', { p_cliente_id: id(12), p_arquivo_nota_fiscal_url: receipt }, 7);
  const intent = queuedMediaIntents([pending]).get(receipt)!;
  assert.deepEqual(receivingMediaTransfer(pending.id, pending.actor_id, intent.payload.p_cliente_id, intent.payload.p_projeto_id, receipt, 'document'), fromDraft);
  assert.equal(fromDraft.payload.p_receiving_draft_id, pending.id);
  assert.equal(fromDraft.payload.p_arquivo_nota_fiscal_url, receipt);
  assert.deepEqual(receivingMediaTransfer(submission, id(11), id(12), null, photo, 'photo').payload.p_fotos_recebimento, [{ foto_url: photo }]);
});

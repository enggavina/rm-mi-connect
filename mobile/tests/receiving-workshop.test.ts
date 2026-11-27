import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sendScopedReceiving, sendWorkshopReceivingDraft } from '../src/core/receiving-workshop';

const id = '16b86a9e-d20d-4000-a970-ec344ae6d366';
const workshopOrigin = '16b86a9e-d20d-4000-a970-ec344ae6d368';
const payload = { p_cliente_id: id, p_fotos_recebimento: [{ foto_url: 'file:///cache/intake.jpg' }] };
const draft = { deviceToken: 'local-device-fixture', operatorToken: 'local-operator-fixture', submission: id, payload, workshopOrigin };

test('the native receiving transport sends the frozen payload to the EM origin and keeps the device token in the header', async () => {
  const signal = new AbortController().signal;
  const receipt = { projeto_id: id, equipamento_id: id, receiving_id: id, opening_created: true, attachments_pending: true,
    idempotent_replay: false, confirmacao: { protocolo: id, oficina_id: workshopOrigin, fase: 'open', projeto_id: id, equipamento_id: id } };
  const response = await sendScopedReceiving({ ...draft, phase: 'open' }, signal, async (url, options) => {
    assert.equal(url, 'https://em-web-production.up.railway.app/api/mobile/recebimentos');
    assert.equal(options?.redirect, 'error');
    assert.equal(options?.signal, signal);
    assert.equal(new Headers(options?.headers).get('authorization'), `Bearer ${draft.deviceToken}`);
    assert.deepEqual(JSON.parse(String(options?.body)), { operatorToken: draft.operatorToken, submission: id, phase: 'open', payload, workshopOrigin });
    return Response.json(receipt);
  });
  assert.deepEqual(response, receipt);
});

test('refused or unconfirmed receipts report failure so the native queue keeps the original protocol', async () => {
  for (const [response, code] of [
    [Response.json({ code: '42501', message: 'Fora da oficina' }, { status: 403 }), '42501'],
    [Response.json({ projeto_id: id }), 'PT503'],
  ] as const) {
    let requests = 0;
    await assert.rejects(sendScopedReceiving({ ...draft, phase: 'complete' }, new AbortController().signal, async () => {
      requests++; return response;
    }), { code });
    assert.equal(requests, 1);
  }
});

test('draft transport carries the current confirmed workshop and preserves the original save on refused recovery', async () => {
  const input = { deviceToken: draft.deviceToken, operatorToken: draft.operatorToken, workshopOrigin,
    args: { action: 'save' as const, draftId: id, payload, expectedRevision: 2, saveId: id } };
  const signal = new AbortController().signal;
  await assert.rejects(sendWorkshopReceivingDraft(input, signal, async (target, init) => {
    assert.match(String(target), /\/recebimentos\/rascunho$/);
    assert.equal(init?.signal, signal);
    assert.equal(new Headers(init?.headers).get('authorization'), `Bearer ${draft.deviceToken}`);
    assert.deepEqual(JSON.parse(String(init?.body)), { operatorToken: input.operatorToken, workshopOrigin, args: input.args });
    return Response.json({ code: '42501', message: 'A origem precisa ser conferida.' }, { status: 403 });
  }), { code: '42501' });
  assert.equal(await sendWorkshopReceivingDraft({ ...input, args: { action: 'read', draftId: null } }, signal,
    async () => Response.json(null)), null);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sendScopedReceiving } from '../src/core/receiving-workshop';

const id = '16b86a9e-d20d-4000-a970-ec344ae6d366';
const payload = { p_cliente_id: id, p_fotos_recebimento: [{ foto_url: 'file:///cache/intake.jpg' }] };
const draft = { deviceToken: 'local-device-fixture', operatorToken: 'local-operator-fixture', submission: id, payload };

test('the native receiving transport sends the frozen payload to the EM origin and keeps the device token in the header', async () => {
  const signal = new AbortController().signal;
  const receipt = { projeto_id: id, equipamento_id: id };
  const response = await sendScopedReceiving({ ...draft, phase: 'open' }, signal, async (url, options) => {
    assert.equal(url, 'https://em-web-production.up.railway.app/api/mobile/recebimentos');
    assert.equal(options?.redirect, 'error');
    assert.equal(options?.signal, signal);
    assert.equal(new Headers(options?.headers).get('authorization'), `Bearer ${draft.deviceToken}`);
    assert.deepEqual(JSON.parse(String(options?.body)), { operatorToken: draft.operatorToken, submission: id, phase: 'open', payload });
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

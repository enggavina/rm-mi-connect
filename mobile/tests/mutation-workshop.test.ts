import assert from 'node:assert/strict';
import test from 'node:test';
import { sendWorkshopMutation } from '../src/core/mutation-workshop';

const input = { deviceToken: 'local-device-token', operatorToken: 'original-local-operator',
  submission: '08300000-0000-4000-8000-000000000002', operation: 'rm_add_cell_comment_v1' as const,
  workshopOrigin: '08300000-0000-4000-8000-000000000005',
  payload: { p_celula_projeto_id: '08300000-0000-4000-8000-000000000003', p_comentario: 'Comentário local' } };

test('a queued mutation uses the original protocol, actor delegation and payload to reach the workshop writer', async () => {
  const reply = await sendWorkshopMutation(input, async (url, init) => {
    assert.equal(url, 'https://em-web-production.up.railway.app/api/mobile/registros');
    assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer local-device-token');
    assert.equal(init?.redirect, 'error');
    const { deviceToken: _ignored, ...wanted } = input;
    assert.deepEqual(JSON.parse(String(init?.body)), wanted);
    return Response.json({ comment_id: input.submission, idempotent_replay: true });
  });
  assert.equal(reply.idempotent_replay, true);
});

test('a different-office denial and invalid acknowledgement stay errors eligible for existing queue handling', async () => {
  await assert.rejects(sendWorkshopMutation(input, async () => Response.json({ code: '42501', message: 'Registro indisponível.' }, { status: 403 })),
    { code: '42501' });
  await assert.rejects(sendWorkshopMutation(input, async () => Response.json(null)), { code: 'PT503' });
});

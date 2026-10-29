import test from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { useEngineeringSave } from '../src/components/web/engineering-save';
import type { PhotoTitleAttempt } from '../src/components/web/engineering-model';
import type { WebActionResult } from '../src/server/web/mutation';

function mount<T>(action: (input: T) => Promise<WebActionResult>, destination: string | ((input: T) => string)) {
  let result: ReturnType<typeof useEngineeringSave<T>>;
  function Probe() { result = useEngineeringSave<T>(action, destination); return null; }
  renderToStaticMarkup(createElement(Probe));
  return result!;
}
const success: WebActionResult = { ok: true, data: { operation: 'delete_photo_title', id: 'title', projeto_id: null,
  updated_at: '2026-10-29T18:03:24.123456Z', record: {}, idempotent_replay: false } };

test('one frozen title attempt prevents parallel save and keeps delete through an uncertain retry', async () => {
  const paths: string[] = [], calls: PhotoTitleAttempt[] = [];
  const prior = Object.getOwnPropertyDescriptor(globalThis, 'window');
  Object.defineProperty(globalThis, 'window', { configurable: true, value: { location: { assign: (path: string) => paths.push(path) } } });
  try {
    let release!: (value: WebActionResult) => void;
    const first = new Promise<WebActionResult>(resolve => { release = resolve; });
    const hook = mount<PhotoTitleAttempt>(async input => { calls.push(input); return calls.length === 1 ? first : success; },
      input => `/engenharia/titulos?resultado=${input.action === 'delete' ? 'excluido' : 'salvo'}`);
    const deletion: PhotoTitleAttempt = { action: 'delete', payload: { submissionId: 'delete-id', id: 'title', expected_updated_at: '2026-10-29T18:03:24.123456Z' } };
    const save: PhotoTitleAttempt = { action: 'save', payload: { submissionId: 'save-id', id: 'title', expected_updated_at: null, changes: { titulo: 'Another value' } } };
    const pending = hook.send(deletion);
    await hook.send(save);
    assert.equal(calls.length, 1, 'A second command cannot start while delete is in flight.');
    release({ ok: false, code: 'UNAVAILABLE', error: 'Unknown outcome' }); await pending;
    deletion.payload.expected_updated_at = '2026-11-01T00:00:00Z';
    await hook.send(save);
    assert.equal(calls.length, 2); assert.equal(calls[1], calls[0]);
    assert.equal(calls[1].action, 'delete'); assert.equal(calls[1].payload.submissionId, 'delete-id');
    assert.equal(calls[1].payload.expected_updated_at, '2026-10-29T18:03:24.123456Z');
    assert.equal(Object.isFrozen(calls[1].payload), true);
    await new Promise(resolve => setTimeout(resolve, 5));
    assert.deepEqual(paths, ['/engenharia/titulos?resultado=excluido'], 'Destination uses the completed frozen attempt before it is cleared.');
    const legacy = mount(async () => success, '/engenharia');
    await legacy.send({ submissionId: 'legacy' });
    await new Promise(resolve => setTimeout(resolve, 5));
    assert.equal(paths[1], '/engenharia', 'Existing string destinations remain compatible.');
  } finally {
    if (prior) Object.defineProperty(globalThis, 'window', prior); else Reflect.deleteProperty(globalThis, 'window');
  }
});

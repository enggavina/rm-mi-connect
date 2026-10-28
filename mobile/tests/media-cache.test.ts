import test from 'node:test';
import assert from 'node:assert/strict';
import { MEDIA_CACHE_RESERVE_BYTES, prefetchWithSpaceReserve } from '../src/core/media-cache-policy';

test('background prefetch stops at the reserve boundary without downloading or removing queued items', async () => {
  const items = Object.freeze(['remote-photo']);
  for (const freeBytes of [0, MEDIA_CACHE_RESERVE_BYTES - 1, MEDIA_CACHE_RESERVE_BYTES]) {
    let downloads = 0;
    assert.equal(await prefetchWithSpaceReserve(items, async () => freeBytes, async () => { downloads++; }), 'low_space');
    assert.equal(downloads, 0); assert.deepEqual(items, ['remote-photo']);
  }
  let downloads = 0;
  assert.equal(await prefetchWithSpaceReserve(items, async () => MEDIA_CACHE_RESERVE_BYTES + 1, async () => { downloads++; }), null);
  assert.equal(downloads, 1);
});

test('free storage is rechecked before every sequential download and paused work resumes after space is freed', async () => {
  const queue = Object.freeze(['first', 'second', 'third']); const downloaded: string[] = []; const events: string[] = [];
  let checks = 0;
  const pause = await prefetchWithSpaceReserve(queue, async () => { events.push('check'); return ++checks === 1 ? MEDIA_CACHE_RESERVE_BYTES + 100 : MEDIA_CACHE_RESERVE_BYTES; }, async item => { events.push(`download:${item}`); downloaded.push(item); });
  assert.equal(pause, 'low_space');
  assert.deepEqual(events, ['check', 'download:first', 'check']);
  assert.deepEqual(downloaded, ['first']);
  assert.deepEqual(queue, ['first', 'second', 'third']);
  assert.equal(await prefetchWithSpaceReserve(queue.slice(1), async () => MEDIA_CACHE_RESERVE_BYTES + 100, async item => { downloaded.push(item); }), null);
  assert.deepEqual(downloaded, ['first', 'second', 'third']);
});

test('unavailable or invalid storage readings pause background caching without failing synchronization', async () => {
  for (const reading of [NaN, Infinity, -1]) {
    assert.equal(await prefetchWithSpaceReserve(['photo'], async () => reading, async () => { assert.fail('must not download'); }), 'space_unavailable');
  }
  assert.equal(await prefetchWithSpaceReserve(['photo'], async () => { throw new Error('Storage API unavailable'); }, async () => { assert.fail('must not download'); }), 'space_unavailable');
  assert.equal(await prefetchWithSpaceReserve([], async () => { assert.fail('no work means no storage query'); }, async () => {}), null);
});

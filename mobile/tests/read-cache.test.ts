import test from 'node:test';
import assert from 'node:assert/strict';
import { SharedReadCache } from '../src/core/read-cache';
import { pageItems } from '../src/domain/pagination';

test('identical simultaneous catalog reads share the decoded snapshot and retry failures', async () => {
  const cache = new SharedReadCache<{ id: string }>(); let reads = 0;
  const load = async () => { reads++; return [{ id: 'photo' }]; };
  const first = cache.read('project/photos', 1, load);
  const second = cache.read('project/photos', 1, load);
  assert.equal(first, second);
  const rows = await first;
  assert.equal(await second, rows);
  assert.equal(await cache.read('project/photos', 1, load), rows);
  assert.equal(reads, 1);
  await assert.rejects(cache.read('failed', 1, async () => { throw new Error('SQLite unavailable'); }));
  assert.deepEqual(await cache.read('failed', 1, load), [{ id: 'photo' }]);
});

test('a late old catalog read cannot replace the current revision or another filter', async () => {
  const cache = new SharedReadCache<string>();
  let finishOld!: (rows: string[]) => void;
  const old = cache.read('project-a', 1, () => new Promise(resolve => { finishOld = resolve; }));
  await Promise.resolve();
  const current = await cache.read('project-a', 2, async () => ['new']);
  finishOld(['old']);
  assert.deepEqual(await old, ['old']);
  assert.equal(await cache.read('project-a', 2, async () => { assert.fail('current snapshot must remain shared'); }), current);
  assert.deepEqual(await cache.read('project-b', 2, async () => ['other project']), ['other project']);
});

test('decoded row and query limits evict inactive snapshots without retaining oversized tables', async () => {
  const cache = new SharedReadCache<number>(2, 3); let reads = 0;
  const load = async () => { reads++; return [1, 2]; };
  await cache.read('first', 1, load);
  await cache.read('second', 1, load);
  await cache.read('second', 1, load);
  assert.equal(reads, 2);
  await cache.read('first', 1, load);
  assert.equal(reads, 3, 'oldest decoded rows are released when the row budget is exceeded');
  let hugeReads = 0;
  const huge = async () => { hugeReads++; return [1, 2, 3, 4]; };
  await cache.read('huge', 1, huge); await cache.read('huge', 1, huge);
  assert.equal(hugeReads, 2, 'oversized results are delivered but not retained');
  const tiny = new SharedReadCache<number>(2, 100); let emptyReads = 0;
  const empty = async () => { emptyReads++; return []; };
  await tiny.read('a', 1, empty); await tiny.read('b', 1, empty); await tiny.read('c', 1, empty); await tiny.read('a', 1, empty);
  assert.equal(emptyReads, 4, 'empty queries also obey the entry limit');
});

test('bitmap pages keep every result reachable while bounding rendered items after filtering', () => {
  const all = Array.from({ length: 137 }, (_, index) => ({ id: `photo-${index}` }));
  const visited: typeof all = [];
  for (let page = 0; page < Math.ceil(all.length / 12); page++) {
    const result = pageItems(all, page, 12);
    assert.ok(result.items.length <= 12); visited.push(...result.items);
  }
  assert.deepEqual(visited, all);
  assert.equal(pageItems(all.slice(0, 3), 11, 12).page, 0);
  assert.deepEqual(pageItems([], 11, 12), { items: [], page: 0, pages: 1, total: 0 });
  assert.equal(pageItems(all, -1, 10).items.length, 10);
});

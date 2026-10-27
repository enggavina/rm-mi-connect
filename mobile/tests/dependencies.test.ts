import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';

test('Expo query parser preserves UTF-8 and handles malformed deep links in bounded time', { timeout: 2000 }, () => {
  const query = require('query-string');
  assert.equal(query.parse('nome=Jo%C3%A3o+Silva').nome, 'João Silva');
  assert.equal(query.parse('projeto=OS%2F42').projeto, 'OS/42');
  const malformed = '%FF%C3%28'.repeat(5000);
  assert.equal(typeof query.parse(`q=${malformed}`).q, 'string');
  assert.equal(query.stringify({ projeto: 'OS/42' }), 'projeto=OS%2F42');
});

test('Metro asset loader remains compatible with patched image-size', () => {
  const { getAssetSize } = require('metro/private/Assets');
  const bytes = readFileSync(new URL('../assets/icon.png', import.meta.url));
  assert.deepEqual(getAssetSize('png', bytes, 'icon.png'), { width: 1024, height: 1024 });
});

test('Metro getAssetData reads a filename using the patched image parser', async () => {
  const {getAssetData} = require('metro/private/Assets');
  const file = fileURLToPath(new URL('../assets/icon.png', import.meta.url));
  const asset = await getAssetData(file, 'assets/icon.png', [], 'android', '/assets');
  assert.equal(asset.width,1024);
  assert.equal(asset.height,1024);
  assert.equal(asset.type,'png');
  assert.equal(asset.files[0],file);
});

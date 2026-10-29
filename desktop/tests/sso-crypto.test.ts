import assert from 'node:assert/strict';
import test from 'node:test';
import { opaqueToken, openSso, sealSso, tokenHash } from '../src/server/web/sso-crypto';

const key = Buffer.alloc(32, 11).toString('base64url');
test('SSO tokens stay opaque and encrypted sessions are bound to their purpose and key', () => {
  const token = opaqueToken(), second = opaqueToken();
  assert.notEqual(token, second); assert.equal(tokenHash(token).length, 64);
  assert.throws(() => tokenHash('../invalid'));
  const contents = { accessToken: 'synthetic-private-token', expiresAt: 123 };
  const encrypted = sealSso(contents, 'session', key);
  assert.ok(!encrypted.includes(contents.accessToken)); assert.deepEqual(openSso(encrypted, 'session', key), contents);
  assert.throws(() => openSso(encrypted, 'flow', key));
  assert.throws(() => openSso(encrypted, 'session', Buffer.alloc(32, 12).toString('base64url')));
});
test('tampered, malformed and oversized SSO envelopes are rejected without disclosing their contents', () => {
  const encrypted = sealSso({ token: 'synthetic-token' }, 'flow', key);
  const parts = encrypted.split('.');
  parts[2] = Buffer.alloc(16).toString('base64url');
  assert.throws(() => openSso(parts.join('.'), 'flow', key), /confirmar a sessão/);
  assert.throws(() => openSso('v1.invalid.invalid.invalid', 'flow', key));
  assert.throws(() => sealSso({ value: 'x'.repeat(40_001) }, 'flow', key));
  assert.throws(() => sealSso({}, 'flow', 'invalid'));
});

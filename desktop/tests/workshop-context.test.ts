import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorkshopContextReader, EM_IDENTITY_ISSUER, MOBILE_WORKSHOP_CONTEXT_URL, validateWorkshopContext, validateWorkshopTeam, WORKSHOP_CONTEXT_URL, WORKSHOP_TEAM_URL, WorkshopContextError } from '../src/server/web/workshop-context';
import { CORPORATE_ISSUER, type VerifiedCorporateSession } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const now = Date.parse('2026-11-17T12:00:00Z');
function context(mobile = false) { return { version: 2, application: 'em', channel: mobile ? 'mobile' : 'web', authority: CORPORATE_ISSUER,
  workshop: { id: id(1), code: 'BMA', name: 'BMA', active: true, revision: 1, updated_at: '2026-11-17T11:00:00+00:00' },
  principals: mobile ? [{ kind: 'device', issuer: EM_IDENTITY_ISSUER, subject: id(3), revision: 2 }, { kind: 'operator', issuer: EM_IDENTITY_ISSUER, subject: id(4), revision: 3 }]
    : [{ kind: 'corporate', issuer: CORPORATE_ISSUER, subject: id(2), revision: 1 }],
  issued_at: '2026-11-17T12:00:00.000001+00:00', expires_at: '2026-11-17T12:05:00.000001+00:00' }; }
function session(): VerifiedCorporateSession { return { accessToken: 'synthetic.jwt.signature', user: { id: id(2), email: 'qa@example.invalid' }, expiresAt: now + 60_000,
  decision: { application: 'em', issuer: CORPORATE_ISSUER, subject: id(2), app_access: true, capabilities: ['em.portal.read'], all_employees: false, fields: [], export_allowed: false } }; }
const expected = { channel: 'web', subject: id(2) } as const;
const rejected = (error: unknown) => error instanceof WorkshopContextError && error.status === 503 && !error.message.includes('private');

test('v2 preserves exact authority identity and revisions without granting data or mutating input', () => {
  const value = context(), before = JSON.stringify(value);
  const result = validateWorkshopContext(value, expected, now);
  assert.equal(result.workshop.code, 'BMA'); assert.equal(result.principals[0].revision, 1);
  assert.equal(JSON.stringify(value), before); assert.notEqual(result, value);
  assert.equal('capabilities' in result, false);
});

test('team consultation uses the corporate JWT and an empty request, and validates the expiring membership snapshot', async () => {
  const corporate = session(); corporate.decision.capabilities.push('em.catalogs.read');
  const current = { context: { ...context(), expires_at: '2026-11-17T12:00:10Z' },
    members: [{ kind: 'corporate', subject: id(2) }, { kind: 'operator', subject: id(4) }] };
  const reader = createWorkshopContextReader({ now: () => now, teamKey: () => 'sb_publishable_local_test', fetcher: async (url, opts) => {
    assert.equal(url, WORKSHOP_TEAM_URL);
    assert.equal(opts?.body, '{}'); assert.equal(opts?.cache, 'no-store'); assert.equal(opts?.redirect, 'error');
    const headers = new Headers(opts?.headers);
    assert.equal(headers.get('authorization'), `Bearer ${corporate.accessToken}`);
    assert.equal(headers.get('apikey'), 'sb_publishable_local_test');
    return Response.json(current);
  } });
  assert.deepEqual(await reader.readTeam(corporate), current);
  await assert.rejects(reader.readTeam(session()), (error: unknown) => error instanceof WorkshopContextError && error.status === 403);
  for (const members of [[current.members[1]], [...current.members, current.members[1]],
    [...current.members, { kind: 'device', subject: id(5) }], [{ kind: 'corporate', subject: id(2), label: 'extra' }]]) {
    assert.throws(() => validateWorkshopTeam({ ...current, members }, id(2), now), rejected);
  }
  assert.throws(() => validateWorkshopTeam(current, id(5), now), rejected);
  assert.throws(() => validateWorkshopTeam(current, id(2), now + 11_000), rejected);
  assert.throws(() => validateWorkshopTeam({ ...current, context: context() }, id(2), now), rejected);
});

test('unknown top-level, office and identity fields cannot be silently discarded', () => {
  for (const value of [{ ...context(), application_access: true }, { ...context(), workshop: { ...context().workshop, default: true } },
    { ...context(), principals: [{ ...context().principals[0], global_admin: true }] }]) {
    assert.throws(() => validateWorkshopContext(value, expected, now), rejected);
  }
});

test('authority version application channel and exact principal cannot be substituted', () => {
  for (const patch of [{ version: '2' }, { version: true }, { application: 'other' }, { authority: EM_IDENTITY_ISSUER }, { channel: 'mobile' },
    { principals: [] }, { principals: [...context().principals, ...context().principals] },
    { principals: [{ ...context().principals[0], issuer: EM_IDENTITY_ISSUER }] },
    { principals: [{ ...context().principals[0], subject: id(5) }] }]) assert.throws(() => validateWorkshopContext({ ...context(), ...patch }, expected, now), rejected);
});

test('inactive office, unsafe text, invalid UUID and unsafe revisions are rejected', () => {
  for (const patch of [{ active: false }, { id: 'BMA' }, { name: ' BMA' }, { name: 'BMA\u0000' }, { code: 'bma' },
    { revision: '1' }, { revision: 0 }, { revision: Number.MAX_SAFE_INTEGER + 1 }, { updated_at: '2026-11-17' }]) {
    assert.throws(() => validateWorkshopContext({ ...context(), workshop: { ...context().workshop, ...patch } }, expected, now), rejected);
  }
});

test('freshness and maximum five-minute lifetime are checked independently of wall-clock format', () => {
  for (const patch of [{ issued_at: '2026-11-17T11:59:49Z' }, { issued_at: '2026-11-17T12:00:11Z' },
    { expires_at: '2026-11-17T12:00:00Z' }, { expires_at: '2026-11-17T11:59:59Z' }, { expires_at: '2026-11-17T12:05:01Z' },
    { issued_at: '2026-11-17' }]) assert.throws(() => validateWorkshopContext({ ...context(), ...patch }, expected, now), rejected);
  assert.throws(() => validateWorkshopContext(context(), expected, NaN), rejected);
  assert.equal(validateWorkshopContext(context(), expected, now + 10_000).workshop.code, 'BMA');
});

test('mobile context binds the existing password device and operator by ordered kind issuer and UUID', () => {
  const expectedMobile = { channel: 'mobile', deviceSubject: id(3), operatorSubject: id(4) } as const;
  assert.equal(validateWorkshopContext(context(true), expectedMobile, now).channel, 'mobile');
  for (const principals of [[...context(true).principals].reverse(), [context(true).principals[0]],
    context(true).principals.map(p => ({ ...p, issuer: CORPORATE_ISSUER }))]) {
    assert.throws(() => validateWorkshopContext({ ...context(true), principals }, expectedMobile, now), rejected);
  }
  assert.throws(() => validateWorkshopContext(context(true), { ...expectedMobile, operatorSubject: id(8) }, now), rejected);
});

test('reader pins HTTPS destination and sends only current corporate Bearer with bounded uncached GET', async () => {
  const calls: RequestInit[] = [];
  const reader = createWorkshopContextReader({ now: () => now, fetcher: async (url, options) => {
    assert.equal(url, WORKSHOP_CONTEXT_URL); calls.push(options!); return Response.json(context());
  } });
  assert.equal((await reader.readWeb(session())).workshop.code, 'BMA');
  assert.equal(calls.length, 1); assert.equal(calls[0].method, 'GET'); assert.equal(calls[0].cache, 'no-store'); assert.equal(calls[0].redirect, 'error');
  assert.deepEqual(calls[0].headers, { Authorization: 'Bearer synthetic.jwt.signature', Accept: 'application/json' });
  assert.ok(calls[0].signal instanceof AbortSignal); assert.equal(calls[0].body, undefined);
});

test('mobile context reads pin their own destination with only verified principals and a server credential', async () => {
  const expected = { channel: 'mobile', deviceSubject: id(3), operatorSubject: id(4) } as const;
  const key = 'm'.repeat(43);
  const reader = createWorkshopContextReader({ now: () => now, fetcher: async (url, options) => {
    assert.equal(url, MOBILE_WORKSHOP_CONTEXT_URL);
    assert.equal(options?.method, 'POST');
    assert.equal(options?.redirect, 'error');
    assert.equal(options?.cache, 'no-store');
    assert.equal(new Headers(options?.headers).get('authorization'), `Bearer ${key}`);
    assert.deepEqual(JSON.parse(String(options?.body)), { device_subject: id(3), operator_subject: id(4) });
    return Response.json(context(true));
  } });
  assert.equal((await reader.readMobile(expected, now + 60_000, key)).workshop.code, 'BMA');
  await assert.rejects(reader.readMobile(expected, now + 60_000, 'unconfigured'), rejected);
  await assert.rejects(reader.readMobile(expected, now, key), (e: unknown) => e instanceof WorkshopContextError && e.status === 401);
});

test('expired or inconsistent sessions never contact the workshop service', async () => {
  const reader = createWorkshopContextReader({ now: () => now, fetcher: async () => assert.fail('must reject before network') });
  for (const patch of [{ expiresAt: now }, { accessToken: 'password' }, { user: { ...session().user, id: 'BMA' } }]) {
    await assert.rejects(reader.readWeb({ ...session(), ...patch }), e => e instanceof WorkshopContextError && e.status === 401);
  }
  await assert.rejects(reader.readWeb({ ...session(), decision: { ...session().decision, subject: id(5) } }), e => e instanceof WorkshopContextError && e.status === 403);
});

test('revocation is re-read after success without fallback or a positive context cache', async () => {
  let calls = 0;
  const reader = createWorkshopContextReader({ now: () => now, fetcher: async () => ++calls === 1 ? Response.json(context()) : Response.json({ private: 'upstream details' }, { status: 403 }) });
  await reader.readWeb(session());
  await assert.rejects(reader.readWeb(session()), e => e instanceof WorkshopContextError && e.status === 403 && !JSON.stringify(e).includes('details'));
  assert.equal(calls, 2);
});

test('errors, redirects, content types and malformed payloads expose no upstream diagnostics', async () => {
  const responses = [() => Response.json({ private: 'diagnostics' }, { status: 503 }), () => Response.json({}, { status: 422 }),
    () => new Response(null, { status: 302, headers: { Location: 'https://other.invalid' } }),
    () => new Response(JSON.stringify(context()), { headers: { 'Content-Type': 'text/html' } }),
    () => new Response('private invalid json', { headers: { 'Content-Type': 'application/json' } }),
    () => Response.json({ ...context(), workshop: { ...context().workshop, active: false } })];
  for (const response of responses) await assert.rejects(createWorkshopContextReader({ now: () => now, fetcher: async () => response() }).readWeb(session()), rejected);
  await assert.rejects(createWorkshopContextReader({ now: () => now, fetcher: async () => { throw new Error('private token'); } }).readWeb(session()), rejected);
});

test('oversized declared and streamed bodies are refused without parsing or trusting content-length', async () => {
  const bodies = [new Response('{}', { headers: { 'Content-Type': 'application/json', 'Content-Length': '65537' } }),
    new Response('{}', { headers: { 'Content-Type': 'application/json', 'Content-Length': 'invalid' } }),
    new Response(' '.repeat(65537), { headers: { 'Content-Type': 'application/json', 'Content-Length': '2' } })];
  for (const body of bodies) await assert.rejects(createWorkshopContextReader({ now: () => now, fetcher: async () => body }).readWeb(session()), rejected);
});

test('total deadline closes both a stalled fetch and a stalled response stream', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  for (const fetcher of [async () => new Promise<Response>(() => {}), async () => new Response(new ReadableStream<Uint8Array>({ start() {} }), { headers: { 'Content-Type': 'application/json' } })]) {
    const reading = createWorkshopContextReader({ now: () => now, fetcher }).readWeb(session());
    const rejection = assert.rejects(reading, rejected);
    await new Promise<void>(resolve => setImmediate(resolve));
    t.mock.timers.tick(10_000); await rejection;
  }
});

test('session expiration during a request and invalid UTF-8 both close the decision', async () => {
  let clock = now;
  const reader = createWorkshopContextReader({ now: () => clock, fetcher: async () => { clock += 60_000; return Response.json(context()); } });
  await assert.rejects(reader.readWeb(session()), e => e instanceof WorkshopContextError && e.status === 401);
  await assert.rejects(createWorkshopContextReader({ now: () => now, fetcher: async () => new Response(new Uint8Array([255]), { headers: { 'Content-Type': 'application/json' } }) }).readWeb(session()), rejected);
});

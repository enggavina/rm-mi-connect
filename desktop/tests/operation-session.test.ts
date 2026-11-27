import assert from 'node:assert/strict';
import test from 'node:test';
import { createOperationService } from '../src/server/operation/service';
import { openDeviceLogin, openOperationSession, operationClaims, operationQuery, readOperationCredentials,
  readOperatorCredentials } from '../src/server/operation/policy';
import { sealSso } from '../src/server/web/sso-crypto';
import { onlineFormSubmission } from '../src/shared/online-form';
import { CORPORATE_ISSUER } from '../src/server/web/sso-policy';
import { EM_IDENTITY_ISSUER, WorkshopContextError, type WorkshopContext } from '../src/server/web/workshop-context';

const key = Buffer.alloc(32, 104).toString('base64url');
const now = Date.parse('2026-11-24T12:00:00Z');
const id = (suffix: string) => `00000000-0000-4000-8000-00000000000${suffix}`;
const userId = id('1'), sessionId = id('2'), operatorId = id('3'), deviceId = id('4'), cellId = id('5'), projectId = id('6');
const operatorToken = 'e'.repeat(64);
const credentials = { email: 'tablet@example.invalid', password: 'device-password', matricula: '100', palavra_chave: 'operator-password' };
const encoded = (value: Record<string, unknown>) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = (patch: Record<string, unknown> = {}) => `synthetic.${encoded({
  sub: userId, session_id: sessionId, iss: EM_IDENTITY_ISSUER,
  exp: (now + 3600_000) / 1000, aud: 'authenticated', role: 'authenticated', aal: 'aal1', ...patch,
})}.signature`;
const accessToken = jwt();
const exampleWorkshop: WorkshopContext = {
  version: 2, application: 'em', channel: 'mobile', authority: CORPORATE_ISSUER,
  workshop: { id: id('7'), name: 'Segundo turno', code: 'OUTRA', active: true, revision: 1, updated_at: new Date(now).toISOString() },
  principals: [{ kind: 'device', issuer: EM_IDENTITY_ISSUER, subject: userId, revision: 1 },
    { kind: 'operator', issuer: EM_IDENTITY_ISSUER, subject: operatorId, revision: 1 }],
  issued_at: new Date(now).toISOString(), expires_at: new Date(now + 300_000).toISOString(),
};

function fixture(overrides: Partial<Parameters<typeof createOperationService>[0]> = {}) {
  const calls: string[] = [];
  const service = createOperationService({
    cookieKey: key, now: () => now,
    signIn: async (email, password) => {
      calls.push('signIn'); assert.equal(email, credentials.email); assert.equal(password, credentials.password); return accessToken;
    },
    verify: async token => { calls.push('verify'); assert.equal(token, accessToken); return { id: userId, requiresMfa: false }; },
    identify: async (token, matricula, password) => {
      calls.push('identify'); assert.equal(token, accessToken); assert.equal(matricula, credentials.matricula);
      assert.equal(password, credentials.palavra_chave);
      return { data: { authenticated: true, operator_token: operatorToken }, error: null };
    },
    readIdentity: async args => {
      calls.push('identity'); assert.deepEqual(args, { p_auth_user_id: userId, p_session_id: sessionId, p_operator_token: operatorToken });
      return { data: { device_subject: userId, operator_subject: operatorId, operator_name: 'Operadora', expires_at: new Date(now + 2_000_000).toISOString() }, error: null };
    },
    readWorkshop: async (identity, expiresAt) => {
      calls.push('authority'); assert.deepEqual(identity, { channel: 'mobile', deviceSubject: userId, operatorSubject: operatorId });
      assert.equal(expiresAt, now + 2_000_000);
      return exampleWorkshop;
    },
    readData: async args => {
      calls.push('db');
      assert.deepEqual(args, { p_auth_user_id: userId, p_session_id: sessionId, p_operator_token: operatorToken,
        p_workshop_context: exampleWorkshop, p_cell_id: null, p_project_id: null, p_page: 1 });
      return { data: { kind: 'cells', items: [{ id: cellId, nome: 'Ensaios' }] }, error: null };
    },
    writeForm: async () => assert.fail('Unexpected form write'),
    signOut: async token => { calls.push('signOut'); assert.equal(token, accessToken); },
    ...overrides,
  });
  return { service, calls };
}

test('login and every new read validate both principals and obtain office from fresh authority, never the browser', async () => {
  const { service, calls } = fixture();
  const { envelope, maxAge } = await service.login(credentials);
  assert.equal(maxAge, 2000);
  assert.equal(envelope.includes(accessToken) || envelope.includes(operatorToken), false);
  assert.deepEqual(await service.load(envelope, {}), {
    status: 'ok', workshop: { name: 'Segundo turno', code: 'OUTRA' }, operatorName: 'Operadora',
    data: { kind: 'cells', items: [{ id: cellId, nome: 'Ensaios' }] },
  });
  assert.deepEqual(calls, ['signIn', 'verify', 'identify', 'identity', 'authority', 'verify', 'identity', 'authority', 'db']);
  await service.logout(envelope);
  assert.deepEqual(calls.slice(-2), ['verify', 'signOut']);
});

test('queued native writes compare their original workshop against each fresh authority decision', async () => {
  const { service, calls } = fixture();
  assert.deepEqual((await service.authorizeNativeOperation(accessToken, operatorToken, exampleWorkshop.workshop.id)).p_workshop_context, exampleWorkshop);
  await assert.rejects(service.authorizeNativeOperation(accessToken, operatorToken, id('8')), { code: 'WORKSHOP_FORBIDDEN' });
  assert.deepEqual(calls, ['verify', 'identity', 'authority', 'verify', 'identity', 'authority']);
  assert.deepEqual((await service.authorizeNativeOperation(accessToken, operatorToken)).p_workshop_context, exampleWorkshop);
});

test('native catalog verifies the device, operator and assigned workshop before returning scoped data', async () => {
  const { service, calls } = fixture();
  const response = await service.loadNativeCatalog(accessToken, operatorToken, {});
  assert.deepEqual(response, {
    workshop: { id: exampleWorkshop.workshop.id, code: 'OUTRA', revision: 1 },
    deviceId: userId, operatorId, expiresAt: exampleWorkshop.expires_at,
    data: { kind: 'cells', items: [{ id: cellId, nome: 'Ensaios' }] },
  });
  assert.deepEqual(calls, ['verify', 'identity', 'authority', 'db']);
  assert.equal(await service.loadNativeCatalog(accessToken, operatorToken, { projectId }), null);
  const denied = fixture({ readWorkshop: async () => { throw new WorkshopContextError('WORKSHOP_FORBIDDEN'); },
    readData: async () => assert.fail('Must not read without the current workshop') });
  await assert.rejects(denied.service.loadNativeCatalog(accessToken, operatorToken, {}), { status: 403 });
});

test('revoked or unavailable Central context never uses a previous office or calls the data RPC', async () => {
  for (const [code, status] of [['WORKSHOP_FORBIDDEN', 'forbidden'], ['WORKSHOP_UNAVAILABLE', 'unavailable']] as const) {
    let calls = 0;
    const { service } = fixture({ readWorkshop: async () => {
      if (calls++ === 0) return exampleWorkshop;
      throw new WorkshopContextError(code);
    }, readData: async () => assert.fail('Must not read without fresh authority') });
    const { envelope } = await service.login(credentials);
    assert.deepEqual(await service.load(envelope, {}), { status });
  }
});

test('the browser device step cannot read data and only operator identification opens the workshop', async () => {
  const { service, calls } = fixture();
  const pending = await service.beginDeviceLogin(credentials);
  assert.equal(pending.maxAge, 300);
  assert.equal(openDeviceLogin(pending.envelope, now, key)?.expiresAt, now + 300_000);
  assert.equal(pending.envelope.includes(accessToken), false);
  assert.deepEqual(await service.load(pending.envelope, {}), { status: 'session' });
  assert.deepEqual(calls, ['signIn', 'verify']);

  const complete = await service.identifyDeviceLogin(pending.envelope, credentials);
  assert.equal(complete.status, 'ok');
  if (complete.status !== 'ok') return;
  assert.equal(complete.maxAge, 2000);
  assert.deepEqual(calls, ['signIn', 'verify', 'verify', 'identify', 'identity', 'authority']);
  assert.deepEqual(await service.identifyDeviceLogin(complete.envelope, credentials), { status: 'session' });
  await service.cancelDeviceLogin(complete.envelope);
  assert.equal((await service.load(complete.envelope, {})).status, 'ok');
  assert.ok(!calls.includes('signOut'));
});

test('operator can retry a rejected password and a cancelled or expired device cannot continue', async () => {
  let clock = now;
  let cancelled = false;
  let attempts = 0;
  const { service } = fixture({
    now: () => clock,
    verify: async () => cancelled ? null : { id: userId, requiresMfa: false },
    identify: async () => ({ data: ++attempts === 1 ? { authenticated: false } : { authenticated: true, operator_token: operatorToken }, error: null }),
    signOut: async () => { cancelled = true; },
  });
  const pending = await service.beginDeviceLogin(credentials);
  assert.deepEqual(await service.identifyDeviceLogin(pending.envelope, credentials), { status: 'invalid' });
  assert.equal((await service.identifyDeviceLogin(pending.envelope, credentials)).status, 'ok');
  const next = await service.beginDeviceLogin(credentials);
  clock += 300_000;
  assert.deepEqual(await service.identifyDeviceLogin(next.envelope, credentials), { status: 'session' });
  const latest = await service.beginDeviceLogin(credentials);
  await service.cancelDeviceLogin(latest.envelope);
  assert.deepEqual(await service.identifyDeviceLogin(latest.envelope, credentials), { status: 'session' });
  assert.equal(attempts, 2);
});

test('login denies a bad operator, revoked delegation and a tablet that requires MFA', async () => {
  for (const patch of [{ identify: async () => ({ data: { authenticated: false }, error: null }) },
    { readIdentity: async () => ({ data: null, error: { code: '42501' } }) },
    { verify: async () => ({ id: userId, requiresMfa: true }) }]) {
    const { service, calls } = fixture({ ...patch, readWorkshop: async () => assert.fail('Should not ask Central') });
    await assert.rejects(service.login(credentials), (e: unknown) => e instanceof WorkshopContextError && e.status === 401);
    assert.equal(calls.at(-1), 'signOut');
  }
});

test('device identity must match the verified JWT and the session cannot expire while Central responds', async () => {
  const wrongDevice = fixture({
    readIdentity: async () => ({ data: { device_subject: deviceId, operator_subject: operatorId, operator_name: 'Operadora', expires_at: new Date(now + 2_000_000).toISOString() }, error: null }),
    readWorkshop: async () => assert.fail('Should reject a different device before asking Central'),
  });
  await assert.rejects(wrongDevice.service.login(credentials), (e: unknown) => e instanceof WorkshopContextError && e.status === 401);
  let clock = now;
  const expiring = fixture({ now: () => clock, readWorkshop: async () => { clock += 2_000_000; return exampleWorkshop; } });
  await assert.rejects(expiring.service.login(credentials), (e: unknown) => e instanceof WorkshopContextError && e.status === 401);
});

test('expired, forged and SSO-purpose cookies cannot authenticate the operation', async () => {
  const { service } = fixture({ verify: async () => assert.fail('Should reject before verifying credentials') });
  const session = { token: accessToken, operatorToken, expiresAt: now + 1000 };
  for (const cookie of [undefined, 'not.a.cookie', sealSso(session, 'session', key)]) {
    assert.deepEqual(await service.load(cookie, {}), { status: 'session' });
  }
  assert.equal(openOperationSession(sealSso({ ...session, expiresAt: now }, 'operation', key), now, key), null);
  assert.equal(operationClaims(accessToken, deviceId, now), null);
  assert.equal(operationClaims(jwt({ iss: CORPORATE_ISSUER }), userId, now), null);
});

test('a project returned for the wrong cell or project does not reach the browser', async () => {
  const { service } = fixture({ readData: async args => {
    assert.equal(args.p_cell_id, cellId);
    assert.equal(args.p_project_id, projectId);
    return { data: {
      kind: 'project', cell: { id: cellId, nome: 'Ensaios' },
      project: { id: deviceId, numero: null, nome: 'Wrong record', status: null, descricao: null, cliente: null }, forms: [],
    }, error: null };
  } });
  const { envelope } = await service.login(credentials);
  assert.deepEqual(await service.load(envelope, { cellId, projectId }), { status: 'unavailable' });
  assert.deepEqual(await service.load(envelope, { projectId }), { status: 'missing' });
  assert.equal(operationQuery({ cellId, page: '10000' })?.page, 10_000);
  assert.equal(operationQuery({ cellId, page: '10001' }), null);
});

test('operator form reads bind the model to the authenticated cell and project', async () => {
  const formId = id('8');
  const data = {
    kind: 'form', cell: { id: cellId, nome: 'Ensaios' },
    project: { id: projectId, numero: '123', nome: null, status: null, descricao: null, cliente: null },
    form: { id: formId, titulo: 'Conferência', descricao: null }, questions: [],
  };
  let payload: unknown = data;
  let reads = 0;
  const { service } = fixture({ readData: async args => {
    reads++;
    assert.deepEqual(args, { p_auth_user_id: userId, p_session_id: sessionId, p_operator_token: operatorToken,
      p_workshop_context: exampleWorkshop, p_cell_id: cellId, p_project_id: projectId, p_form_id: formId });
    return { data: payload, error: null };
  } });
  const { envelope } = await service.login(credentials);
  const selection = { cellId, projectId, formId };
  const result = await service.load(envelope, selection);
  assert.equal(result.status, 'ok');
  if (result.status === 'ok') assert.deepEqual(result.data, data);
  for (const invalid of [{ cellId, formId }, { ...selection, formId: 'invalid' }, { ...selection, page: 2 }]) {
    assert.deepEqual(await service.load(envelope, invalid), { status: 'missing' });
  }
  assert.equal(reads, 1);
  for (const wrong of [{ ...data, form: { ...data.form, id: deviceId } }, { ...data, project: { ...data.project, id: deviceId } },
    { ...data, cell: { ...data.cell, id: deviceId } }, { ...data, answers: [] }]) {
    payload = wrong;
    assert.deepEqual(await service.load(envelope, selection), { status: 'unavailable' });
  }
  payload = null;
  assert.deepEqual(await service.load(envelope, selection), { status: 'missing' });
});

test('a form intent binds protocol, model, office and operator across exact retries', async () => {
  const formId = id('8'), questionId = id('9'), version = 'a'.repeat(64);
  const selection = { cellId, projectId, formId };
  const data = {
    kind: 'form', cell: { id: cellId, nome: 'Ensaios' },
    project: { id: projectId, numero: '123', nome: null, status: null, descricao: null, cliente: null },
    form: { id: formId, titulo: 'Conferência', descricao: null },
    questions: [{ id: questionId, indice: '1', enunciado: 'Medida', subtitulo: null, tipo: 'numero', obrigatorio: true, items: [] }],
    edition: { version, dateIntervals: [] },
  };
  let workshop = { ...exampleWorkshop, workshop: { ...exampleWorkshop.workshop, code: 'BMA' } };
  let resultCode: string | null = 'PT503';
  let currentOperator = operatorId;
  const writes: Parameters<Parameters<typeof createOperationService>[0]['writeForm']>[0][] = [];
  const { service } = fixture({
    readData: async () => ({ data, error: null }),
    readIdentity: async () => ({ data: { device_subject: userId, operator_subject: currentOperator,
      operator_name: 'Operadora', expires_at: new Date(now + 2_000_000).toISOString() }, error: null }),
    readWorkshop: async () => workshop,
    writeForm: async args => {
      writes.push(args);
      return { data: resultCode ? null : { registro_formulario_id: id('a'), codigo_text: '0039' }, error: resultCode ? { code: resultCode } : null };
    },
  });
  const { envelope } = await service.login(credentials);
  const loaded = await service.load(envelope, selection);
  assert.equal(loaded.status, 'ok');
  if (loaded.status !== 'ok' || !loaded.submissionProof) return assert.fail('Missing form intent');
  assert.ok(!loaded.submissionProof.includes(operatorId));
  const input = onlineFormSubmission.parse({ proof: loaded.submissionProof, answers: { [questionId]: '25,5' } });
  assert.deepEqual(await service.submitForm(undefined, selection, input), { status: 'session' });
  assert.deepEqual(await service.submitForm(envelope, { ...selection, formId: deviceId }, input), { status: 'forbidden' });
  assert.deepEqual(await service.submitForm(envelope, selection, { ...input, proof: envelope }), { status: 'forbidden' });
  currentOperator = deviceId;
  assert.deepEqual(await service.submitForm(envelope, selection, input), { status: 'forbidden' });
  currentOperator = operatorId;
  const originalWorkshop = workshop;
  workshop = { ...originalWorkshop, workshop: { ...originalWorkshop.workshop, id: deviceId, code: 'BRJ' } };
  assert.deepEqual(await service.submitForm(envelope, selection, input), { status: 'forbidden' });
  assert.equal(writes.length, 0);
  workshop = originalWorkshop;
  assert.deepEqual(await service.submitForm(envelope, selection, input), { status: 'unavailable' });
  resultCode = null;
  assert.deepEqual(await service.submitForm(envelope, selection, input), { status: 'ok', code: '0039' });
  assert.deepEqual(writes[0], writes[1]);
  assert.equal(writes[0].p_version, version);
  assert.equal(writes[0].p_form_id, formId);
  assert.deepEqual(writes[0].p_answers, input.answers);
});

test('online submissions accept bounded answer values without authors, metadata or media URLs', () => {
  const value = { proof: 'local proof', answers: { [id('a')]: { inicio: '2026-11-24', fim: '2026-11-25' },
    [id('b')]: true, [id('c')]: [id('d')], [id('e')]: 'texto' } };
  assert.equal(onlineFormSubmission.safeParse(value).success, true);
  for (const invalid of [{ ...value, operator: operatorId }, { ...value, answers: {} },
    { ...value, answers: { [id('a')]: { assinatura_url: 'https://example.invalid' } } },
    { ...value, answers: { [id('b')]: false } }, { ...value, answers: { [id('e')]: 'x'.repeat(4001) } }]) {
    assert.equal(onlineFormSubmission.safeParse(invalid).success, false);
  }
});

test('login form refuses ambiguous fields, an office supplied by the browser, and oversized bodies', async () => {
  const params = new URLSearchParams(credentials);
  function request(body: string) {
    return new Request('https://example.invalid/operacao/login/entrar', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
    });
  }
  assert.deepEqual(await readOperationCredentials(request(params.toString())), credentials);
  for (const body of [`${params}&email=other@example.invalid`, `${params}&office=BMA`, 'email=' + 'x'.repeat(9000)]) {
    assert.equal(await readOperationCredentials(request(body)), null);
  }
});

test('both browser login steps accept only their credential fields', async () => {
  const { email, password, ...operator } = credentials;
  const device = { email, password };
  function request(data: Record<string, string>, extra = '') {
    return new Request('https://example.invalid/operacao/login/identificar', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: `${new URLSearchParams(data)}${extra}`,
    });
  }
  assert.deepEqual(await readOperationCredentials(request(device)), device);
  assert.deepEqual(await readOperatorCredentials(request(operator)), operator);
  assert.equal(await readOperationCredentials(request(operator)), null);
  assert.equal(await readOperatorCredentials(request(device)), null);
  assert.equal(await readOperatorCredentials(request(credentials)), null);
  assert.equal(await readOperatorCredentials(request(operator, '&matricula=outra')), null);
  assert.equal(await readOperatorCredentials(request(operator, '&office=BMA')), null);
});

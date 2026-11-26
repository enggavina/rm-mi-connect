import { NextResponse } from 'next/server';
import { fixedOriginPost, SSO_HEADERS } from '../../app/auth/sso/handlers';
import { onlineFormSubmission, type OnlineFormSubmission } from '../../shared/online-form';
import { WorkshopContextError } from '../web/workshop-context';
import { OPERATION_COOKIE, OPERATION_DEVICE_COOKIE, OPERATION_LOGIN_PATH, operationCookieOptions,
  readOperationCredentials, readOperationText, readOperatorCredentials, type OperationSelection } from './policy';
import { operationService } from './session';

function publicOrigin() {
  try {
    const configured = process.env.EM_PUBLIC_ORIGIN;
    const parsed = new URL(configured ?? '');
    if (configured !== parsed.origin || parsed.username || parsed.password) return null;
    if (parsed.protocol === 'https:' || (process.env.NODE_ENV !== 'production'
      && parsed.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname))) return parsed.origin;
  } catch { /* Configuration must be explicit. */ }
  return null;
}

function go(path: string, origin?: string | null) {
  return new NextResponse(null, { status: 303, headers: { ...SSO_HEADERS, Location: origin ? new URL(path, origin).href : path } });
}

function denied() {
  return NextResponse.json({ error: 'Solicitação não autorizada.' }, { status: 403, headers: SSO_HEADERS });
}

function setDeviceCookie(response: NextResponse, envelope = '', maxAge = 0) {
  response.cookies.set(OPERATION_DEVICE_COOKIE, envelope, operationCookieOptions(maxAge, OPERATION_LOGIN_PATH));
  return response;
}

function completeLogin(origin: string, { envelope, maxAge }: { envelope: string; maxAge: number }) {
  const response = go('/operacao', origin);
  response.cookies.set(OPERATION_COOKIE, envelope, operationCookieOptions(maxAge));
  return setDeviceCookie(response);
}

export async function signInOperation(request: Request, previousDevice?: string) {
  const origin = publicOrigin();
  if (!origin) return go('/operacao/login?erro=unavailable');
  if (!fixedOriginPost(request, origin)) return denied();
  const input = await readOperationCredentials(request);
  if (!input) return go('/operacao/login?erro=invalid', origin);
  try {
    // An already open login page may still submit both sets of credentials during rollout.
    if ('matricula' in input) {
      const session = await operationService.login(input);
      await operationService.cancelDeviceLogin(previousDevice).catch(() => undefined);
      return completeLogin(origin, session);
    }
    const { envelope, maxAge } = await operationService.beginDeviceLogin(input);
    await operationService.cancelDeviceLogin(previousDevice).catch(() => undefined);
    const response = go('/operacao/login/operador', origin);
    response.cookies.set(OPERATION_COOKIE, '', operationCookieOptions(0));
    return setDeviceCookie(response, envelope, maxAge);
  } catch (error) {
    const code = error instanceof WorkshopContextError && error.status === 401 ? 'invalid'
      : error instanceof WorkshopContextError && error.status === 403 ? 'forbidden' : 'unavailable';
    const response = go(`/operacao/login?erro=${code}`, origin);
    response.cookies.set(OPERATION_COOKIE, '', operationCookieOptions(0));
    return response;
  }
}

export async function identifyOperation(request: Request, device?: string) {
  const origin = publicOrigin();
  if (!origin) return go('/operacao/login?erro=unavailable');
  if (!fixedOriginPost(request, origin)) return denied();
  const input = await readOperatorCredentials(request);
  if (!input) return go('/operacao/login/operador?erro=invalid', origin);
  const result = await operationService.identifyDeviceLogin(device, input);
  if (result.status === 'session') return setDeviceCookie(go('/operacao/login?erro=session', origin));
  if (result.status === 'ok') return completeLogin(origin, result);
  return go(`/operacao/login/operador?erro=${result.status}`, origin);
}

export async function cancelOperationLogin(request: Request, device?: string) {
  const origin = publicOrigin();
  if (!origin) return go('/operacao/login?erro=unavailable');
  if (!fixedOriginPost(request, origin)) return denied();
  await operationService.cancelDeviceLogin(device).catch(() => undefined);
  return setDeviceCookie(go('/operacao/login', origin));
}

export async function signOutOperation(request: Request, envelope?: string) {
  const origin = publicOrigin();
  if (!origin) return go('/operacao/login?erro=unavailable');
  if (!fixedOriginPost(request, origin)) return denied();
  await operationService.logout(envelope).catch(() => undefined);
  const response = go('/operacao/login', origin);
  response.cookies.set(OPERATION_COOKIE, '', operationCookieOptions(0));
  return response;
}

const submissionStatus = { ok: 200, session: 401, forbidden: 403, invalid: 422, changed: 412, conflict: 409, unavailable: 503 };

export async function submitOperationForm(request: Request, envelope: string | undefined, selection: OperationSelection) {
  const origin = publicOrigin();
  if (!origin || !fixedOriginPost(request, origin)) return denied();
  if (!envelope) return NextResponse.json({ status: 'session' }, { status: 401, headers: SSO_HEADERS });
  const body = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 512_000);
  let input: OnlineFormSubmission;
  try {
    input = onlineFormSubmission.parse(JSON.parse(body ?? 'null'));
  } catch {
    return NextResponse.json({ status: 'invalid' }, { status: 422, headers: SSO_HEADERS });
  }
  const result = await operationService.submitForm(envelope, selection, input);
  return NextResponse.json(result, { status: submissionStatus[result.status], headers: SSO_HEADERS });
}

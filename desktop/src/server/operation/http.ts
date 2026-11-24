import { NextResponse } from 'next/server';
import { fixedOriginPost, SSO_HEADERS } from '../../app/auth/sso/handlers';
import { WorkshopContextError } from '../web/workshop-context';
import { OPERATION_COOKIE, operationCookieOptions, readOperationCredentials } from './policy';
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

export async function signInOperation(request: Request) {
  const origin = publicOrigin();
  if (!origin) return go('/operacao/login?erro=unavailable');
  if (!fixedOriginPost(request, origin)) return denied();
  const input = await readOperationCredentials(request);
  if (!input) return go('/operacao/login?erro=invalid', origin);
  try {
    const { envelope, maxAge } = await operationService.login(input);
    const response = go('/operacao', origin);
    response.cookies.set(OPERATION_COOKIE, envelope, operationCookieOptions(maxAge));
    return response;
  } catch (error) {
    const code = error instanceof WorkshopContextError && error.status === 401 ? 'invalid'
      : error instanceof WorkshopContextError && error.status === 403 ? 'forbidden' : 'unavailable';
    const response = go(`/operacao/login?erro=${code}`, origin);
    response.cookies.set(OPERATION_COOKIE, '', operationCookieOptions(0));
    return response;
  }
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

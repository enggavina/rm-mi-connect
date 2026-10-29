import { CorporateAuthError } from '../../../server/web/sso-policy';

// These handlers take the bridge as a dependency so the HTTP boundary can be
// exercised without real credentials, cookies or calls to either Supabase.
type SsoDependencies = {
  settings: () => { publicOrigin: string } | null;
  begin: () => Promise<string>;
  finish: (code: string, flowId?: string) => Promise<'/painel' | '/login/sso-mfa'>;
};
export const SSO_HEADERS = { 'Cache-Control': 'private, no-store, max-age=0', 'Pragma': 'no-cache', 'Referrer-Policy': 'no-referrer' };

export function fixedOriginPost(request: Request, origin: string): boolean {
  // Never derive the trusted origin or redirect destination from Host/X-Forwarded-Host.
  return request.method === 'POST' && request.headers.get('origin') === origin
    && request.headers.get('sec-fetch-site') !== 'cross-site';
}
function redirectTo(path: string, origin?: string) {
  return new Response(null, { status: 303, headers: { ...SSO_HEADERS, Location: origin ? new URL(path, origin).href : path } });
}
function failure(error: unknown, origin?: string) {
  const path = error instanceof CorporateAuthError && error.code === 'CORP_FORBIDDEN' ? '/acesso?motivo=permissao'
    : error instanceof CorporateAuthError && error.code === 'CORP_UNAUTHORIZED' ? '/login?erro=sso' : '/login?erro=sso_indisponivel';
  return redirectTo(path, origin);
}
function disabled() { return Response.json({ error: 'Acesso indisponível.' }, { status: 404, headers: SSO_HEADERS }); }

export function createSsoHandlers(dependencies: SsoDependencies) {
  return {
    async start(request: Request): Promise<Response> {
      let origin: string | undefined;
      try {
        const settings = dependencies.settings(); if (!settings) return disabled();
        origin = settings.publicOrigin;
        if (!fixedOriginPost(request, origin)) return Response.json({ error: 'Solicitação não autorizada.' }, { status: 403, headers: SSO_HEADERS });
        return redirectTo(await dependencies.begin());
      } catch (error) { return failure(error, origin); }
    },
    async callback(request: Request): Promise<Response> {
      let origin: string | undefined;
      try {
        const settings = dependencies.settings(); if (!settings) return disabled();
        origin = settings.publicOrigin;
        const url = new URL(request.url), parameters = url.searchParams;
        const allowed = new Set(['code', 'sb_flow_id', 'error', 'error_code', 'error_description']);
        // OAuth errors are deliberately not reflected in the page, logs or redirect.
        if (request.method !== 'GET' || request.url.length > 4096 || url.hash
          || [...parameters.keys()].some(key => !allowed.has(key) || parameters.getAll(key).length !== 1)
          || parameters.has('error') || parameters.has('error_code') || parameters.has('error_description')) throw new CorporateAuthError('CORP_UNAUTHORIZED');
        const code = parameters.get('code'), flowId = parameters.get('sb_flow_id');
        if (!code || !/^[A-Za-z0-9_-]{8,2048}$/.test(code)
          || (flowId !== null && !/^[A-Za-z0-9_-]{8,64}$/.test(flowId))) throw new CorporateAuthError('CORP_UNAUTHORIZED');
        const target = await dependencies.finish(code, flowId ?? undefined);
        // Keep the route safe even if a later bridge change returns a dynamic target.
        if (target !== '/painel' && target !== '/login/sso-mfa') throw new CorporateAuthError('CORP_UNAUTHORIZED');
        return redirectTo(target, origin);
      } catch (error) { return failure(error, origin); }
    },
  };
}

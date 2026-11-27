import { androidPilotKey, androidPilotRelease as release } from '@/shared/android-pilot-release';
import type { SsoContext, WebAccess } from './auth-policy';
import { CorporateAuthError } from './sso-policy';
import { WorkshopContextError, type WorkshopContext } from './workshop-context';

type Authentication = WebAccess | { state: 'unconfigured' };
type PilotAdmin = Extract<WebAccess, { state: 'authenticated' }> & { sso: SsoContext };

export function canUseAndroidPilot(access: Authentication): access is PilotAdmin {
  return access.state === 'authenticated' && access.profile.perfil === 'administrador'
    && !!access.sso?.capabilities.includes('em.portal.read');
}

type Dependencies = {
  authenticate(): Promise<Authentication>;
  workshop(context: SsoContext): Promise<WorkshopContext>;
  sign(): Promise<string | null>;
};

const headers = {
  'Cache-Control': 'private, no-store',
  Vary: 'Cookie',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
};
const messages = {
  400: 'Opção de download inválida.',
  401: 'Entre no portal para baixar o aplicativo.',
  403: 'Sua conta precisa de acesso administrativo e vínculo ativo de oficina.',
  503: 'Não foi possível disponibilizar o aplicativo. Tente novamente.',
};
const errorResponse = (status: keyof typeof messages) => Response.json({ error: messages[status] }, { status, headers });

function approvedDownload(location: string | null) {
  if (!location) return null;
  const url = new URL(location);
  if (url.origin !== release.platformOrigin || url.username || url.password || url.hash
    || url.pathname !== `/storage/v1/object/sign/${release.bucket}/${androidPilotKey}`
    || url.searchParams.size !== 2 || !url.searchParams.get('token')
    || url.searchParams.get('download') !== release.file) return null;
  return url.href;
}

export function createAndroidPilotService(deps: Dependencies) {
  async function authorize(): Promise<200 | 401 | 403 | 503> {
    try {
      const access = await deps.authenticate();
      if (access.state === 'unconfigured') return 503;
      if (access.state === 'anonymous' || access.state === 'mfa') return 401;
      if (!canUseAndroidPilot(access)) return 403;
      await deps.workshop(access.sso);
      return 200;
    } catch (error) {
      if (error instanceof CorporateAuthError || error instanceof WorkshopContextError) {
        if (error.status === 401 || error.status === 403) return error.status;
      }
      return 503;
    }
  }

  return {
    authorize,
    async download(request: Request) {
      const status = await authorize();
      if (status !== 200) return errorResponse(status);
      if (new URL(request.url).search) return errorResponse(400);
      try {
        const location = approvedDownload(await deps.sign());
        return location ? new Response(null, { status: 303, headers: { ...headers, Location: location } }) : errorResponse(503);
      } catch {
        return errorResponse(503);
      }
    },
  };
}

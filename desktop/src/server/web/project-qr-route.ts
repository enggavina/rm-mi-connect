import type { getWebUser } from './auth';
import { hasWebCapability } from './auth-policy';
import { CorporateAuthError } from './sso-policy';
import { createProjectQrData, projectQrScopes } from './project-qr-data';
import { projectQrIdSchema } from './project-qr-policy';
import { renderProjectQrSvg } from './project-qr-image';

const headers = { 'Cache-Control': 'private, no-store', Vary: 'Cookie', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
type Dependencies = { getWebUser: typeof getWebUser; renderQr?: typeof renderProjectQrSvg };
const errorResponse = (status: number, message: string) => Response.json({ error: message }, { status, headers });
export async function handleProjectQrImage(request: Request, projectId: string, dependencies: Dependencies): Promise<Response> {
  try {
    const access = await dependencies.getWebUser(projectQrScopes);
    if (!access) return errorResponse(401, 'Autenticação necessária.');
    if (!['administrador', 'padr_o', 'auditor'].includes(access.profile.perfil)
      || !projectQrScopes.every(capability => hasWebCapability(access, capability))) return errorResponse(403, 'Acesso à identificação do projeto não autorizado.');
    const input = projectQrIdSchema.safeParse(projectId), query = new URL(request.url).searchParams;
    if (!input.success || [...query.keys()].some(key => key !== 'download') || query.getAll('download').length > 1
      || query.has('download') && query.get('download') !== '1') return errorResponse(400, 'Projeto ou opção de imagem inválidos.');
    const project = await createProjectQrData(access.client, access.sso?.capabilities).getProjectQr(input.data);
    if (!project) return errorResponse(404, 'Projeto não encontrado.');
    const svg = await (dependencies.renderQr ?? renderProjectQrSvg)(project.id);
    return new Response(svg, { headers: { ...headers, 'Content-Type': 'image/svg+xml; charset=utf-8',
      'Content-Disposition': `${query.get('download') === '1' ? 'attachment' : 'inline'}; filename="em-projeto-${project.id}.svg"`,
      'Content-Security-Policy': "default-src 'none'; sandbox" } });
  } catch (error) {
    const status = error instanceof CorporateAuthError ? error.status : 503;
    return errorResponse(status, status === 403 ? 'Acesso à identificação do projeto não autorizado.' : status === 401 ? 'Autenticação necessária.' : 'Não foi possível gerar a identificação do projeto.');
  }
}

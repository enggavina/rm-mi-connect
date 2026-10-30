import { getWebUser } from '@/server/web/auth';
import { handleProjectQrImage } from '@/server/web/project-qr-route';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return handleProjectQrImage(request, id, { getWebUser });
}

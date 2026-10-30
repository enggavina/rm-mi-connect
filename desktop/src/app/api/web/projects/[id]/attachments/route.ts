import { actionUser, mutate } from '@/server/web/mutation';
import { handleProjectAttachmentUpload } from '@/server/web/project-dossier-upload';
import { storeProjectAttachment } from '@/server/web/project-dossier-storage';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return handleProjectAttachmentUpload(request, id, { actionUser, mutate, storeAttachment: storeProjectAttachment });
}

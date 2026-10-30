import { actionUser, mutate } from '@/server/web/mutation';
import { handleProjectAttachmentVersionUpload } from '@/server/web/project-attachment-version-upload';
import { storeProjectAttachment } from '@/server/web/project-dossier-storage';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export async function POST(request: Request, context: { params: Promise<{ id: string; attachmentId: string }> }) {
  const { id, attachmentId } = await context.params;
  return handleProjectAttachmentVersionUpload(request, id, attachmentId, { actionUser, mutate, storeAttachment: storeProjectAttachment });
}

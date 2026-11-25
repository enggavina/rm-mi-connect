import { cookies } from 'next/headers';
import { submitOperationForm } from '@/server/operation/http';
import { OPERATION_COOKIE } from '@/server/operation/policy';

export const dynamic = 'force-dynamic';

export async function POST(request: Request, { params }: { params: Promise<{ cellId: string; projectId: string; formId: string }> }) {
  return submitOperationForm(request, (await cookies()).get(OPERATION_COOKIE)?.value, await params);
}

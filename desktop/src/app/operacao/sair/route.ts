import { cookies } from 'next/headers';
import { signOutOperation } from '@/server/operation/http';
import { OPERATION_COOKIE } from '@/server/operation/policy';

export const dynamic = 'force-dynamic';
export async function POST(request: Request) {
  return signOutOperation(request, (await cookies()).get(OPERATION_COOKIE)?.value);
}

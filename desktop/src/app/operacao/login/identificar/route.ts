import { cookies } from 'next/headers';
import { identifyOperation } from '@/server/operation/http';
import { OPERATION_DEVICE_COOKIE } from '@/server/operation/policy';

export const dynamic = 'force-dynamic';
export async function POST(request: Request) {
  return identifyOperation(request, (await cookies()).get(OPERATION_DEVICE_COOKIE)?.value);
}

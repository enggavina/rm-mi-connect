import {getWebUser} from '@/server/web/auth';
import {handleAllocationExport} from '@/server/web/allocation-export-route';
export const runtime='nodejs';
export const dynamic='force-dynamic';
export async function POST(request:Request){return handleAllocationExport(request,{getWebUser});}

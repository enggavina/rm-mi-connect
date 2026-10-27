import { phaseTwo } from '@/server/phase-two';
export const runtime = 'nodejs';
export function POST(request: Request) { return phaseTwo(request, 'report-generation'); }

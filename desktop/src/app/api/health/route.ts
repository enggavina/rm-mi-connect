export const runtime = 'nodejs';
export function GET() { return Response.json({ status: 'ok', service: 'rm-mi-connect', phase: 1 }); }

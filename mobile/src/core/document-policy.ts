export const MAX_DOCUMENT_BYTES = 20 * 1024 * 1024;
export const DOCUMENT_MIME_TYPES = ['application/pdf', 'image/jpeg', 'image/png'];
export function documentType(name: string, mimeType?: string) {
  const extension = name.toLowerCase().match(/\.([a-z0-9]+)$/)?.[1];
  const known: Record<string, string> = { pdf: 'application/pdf', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png' };
  const mime = mimeType && mimeType !== 'application/octet-stream' ? mimeType : known[extension || ''];
  if (!mime || !DOCUMENT_MIME_TYPES.includes(mime) || (extension && known[extension] !== mime)) throw new Error('Selecione um arquivo PDF, JPG ou PNG.');
  return { mimeType: mime, extension: mime === 'application/pdf' ? 'pdf' : mime === 'image/png' ? 'png' : 'jpg' };
}
export function privateDocumentPath(uri: string, supabaseUrl: string): string | null {
  try {
    const target = new URL(uri), base = new URL(supabaseUrl);
    if (target.origin !== base.origin) return null;
    const match = target.pathname.match(/^\/storage\/v1\/object\/(?:authenticated|public|sign)\/rm-documentos\/(.+)$/);
    return match ? decodeURIComponent(match[1]) : null;
  } catch { return null; }
}
export function documentFileName(uri: string): string {
  try { return decodeURIComponent(uri.split('?')[0].split('/').at(-1) || 'Documento'); }
  catch { return 'Documento'; }
}

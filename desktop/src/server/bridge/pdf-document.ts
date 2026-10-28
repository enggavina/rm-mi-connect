import { createHash } from 'node:crypto';

export const MAX_LEGACY_PDF_BYTES = 50 * 1024 * 1024;

/** Reject error pages/truncated downloads before making an imported file available. */
export function inspectLegacyPdf(bytes: Uint8Array): { bytes: number; sha256: string } {
  const content = Buffer.from(bytes);
  if (content.byteLength === 0 || content.byteLength > MAX_LEGACY_PDF_BYTES) throw new Error('PDF_SIZE_INVALID');
  if (!/^%PDF-\d\.\d/.test(content.subarray(0, 16).toString('ascii'))) throw new Error('PDF_HEADER_INVALID');
  if (!content.subarray(-4096).toString('ascii').includes('%%EOF')) throw new Error('PDF_EOF_MISSING');
  return { bytes: content.byteLength, sha256: createHash('sha256').update(content).digest('hex') };
}

export function legacyPdfPath(id: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new Error('DOCUMENT_ID_INVALID');
  return `legacy/${id}.pdf`;
}

/** A title/metadata change in Bubble must not erase a resolved copy of the same key. */
export function preserveImportedPdf(row: Record<string, unknown>, existing?: Record<string, unknown> | null): void {
  if (row.arquivo_url !== null || typeof row.s3_key !== 'string' || !row.s3_key || row.s3_key !== existing?.s3_key || typeof existing.arquivo_url !== 'string' || typeof existing.id !== 'string') return;
  try {
    const url = new URL(existing.arquivo_url);
    if (url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash &&
      url.pathname === `/storage/v1/object/authenticated/rm-documentos/${legacyPdfPath(existing.id)}`) row.arquivo_url = existing.arquivo_url;
  } catch { /* An unrecognized URL must be handled by the normal source mapping. */ }
}

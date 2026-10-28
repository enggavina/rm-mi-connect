/** Copy existing report files only. Does not generate reports or process outbox.
 * From repository root: node desktop/node_modules/tsx/dist/cli.mjs
 * rm-mobile-supabase/scripts/import_existing_document_pdfs.ts [--apply]
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { Bridge } from '../../desktop/src/server/bridge/engine';
import { inspectLegacyPdf, legacyPdfPath, MAX_LEGACY_PDF_BYTES } from '../../desktop/src/server/bridge/pdf-document';

// Audited live API Connector: coZeU/cohec, Download_pdf_n8n_s3.
// This endpoint returns an existing file for Documentos.PDF; it does not generate one.
const DOWNLOAD_URL = 'https://n8n-service-zeek.onrender.com/webhook/9fd6e2aa-19c6-4464-ab46-97b5eece9407';
const BUCKET = 'rm-documentos';

async function main() {
  process.loadEnvFile('desktop/.env');
  const base = process.env.SUPABASE_URL!;
  if (new URL(base).hostname !== 'ellpxfbsrbhblyizvbbk.supabase.co') throw new Error('DESTINATION_NOT_AUTHORIZED');
  const apply = process.argv.includes('--apply');
  const bridge = new Bridge();
  const { data: documents, error } = await bridge.db.from('rm_documentos')
    .select('id,projeto_id,s3_key,arquivo_url').not('s3_key', 'is', null).order('id');
  if (error || !documents || documents.length !== 11) throw new Error('EXPECTED_ELEVEN_SOURCE_KEYS');
  const directory = `.tmp/etl/${new Date().toISOString().replace(/[:.]/g, '-')}-existing-pdfs`;
  const cache = '.tmp/existing-document-pdfs';
  mkdirSync(directory, { recursive: true });
  const report = { apply, expected: 11, imported: 0, unchanged: 0, failed: 0, files: [] as Record<string, unknown>[] };
  const save = () => writeFileSync(`${directory}/summary.json`, JSON.stringify(report, null, 2));
  save();
  if (!apply) { console.info(JSON.stringify({ apply, candidates: documents.length })); return; }
  mkdirSync(cache, { recursive: true });
  const probePath = '.tmp/download-probe/probe.json';
  const probe = existsSync(probePath) ? JSON.parse(readFileSync(probePath, 'utf8')) as { documentId?: string; sourceKeySha256?: string } : {};

  await bridge.withLease(async () => {
    for (const document of documents) {
      let stage = 'scope';
      try {
        const objectPath = legacyPdfPath(String(document.id));
        const canonicalUrl = `${base.replace(/\/$/, '')}/storage/v1/object/authenticated/${BUCKET}/${objectPath}`;
        if (document.arquivo_url === canonicalUrl) { report.unchanged++; continue; }
        if (document.arquivo_url || typeof document.s3_key !== 'string' || !document.s3_key.trim() || /^https?:/i.test(document.s3_key)) throw new Error('SOURCE_CHANGED');
        const pending = await bridge.db.from('rm_sync_outbox').select('id')
          .in('record_id', [document.id, document.projeto_id].filter(Boolean)).neq('status', 'completed').limit(1);
        if (pending.error || pending.data?.length) throw new Error('PENDING_LOCAL_EDIT');
        stage = 'download';
        const sourceKeySha256 = createHash('sha256').update(document.s3_key).digest('hex');
        const localPath = `${cache}/${document.id}-${sourceKeySha256}.pdf`;
        const reuseProbe = probe.documentId === document.id && probe.sourceKeySha256 === sourceKeySha256;
        let bytes: Buffer;
        if (existsSync(localPath)) bytes = readFileSync(localPath);
        else if (reuseProbe) bytes = readFileSync('.tmp/download-probe/document.bin');
        else {
          const response = await fetch(DOWNLOAD_URL, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ pdf: document.s3_key }), redirect: 'error', signal: AbortSignal.timeout(55_000),
          });
          if (!response.ok || !response.headers.get('content-type')?.toLowerCase().includes('application/pdf')) throw new Error('DOWNLOAD_NOT_PDF');
          if (Number(response.headers.get('content-length') || 0) > MAX_LEGACY_PDF_BYTES) throw new Error('PDF_SIZE_INVALID');
          const reader = response.body?.getReader();
          if (!reader) throw new Error('DOWNLOAD_EMPTY');
          const chunks: Uint8Array[] = []; let size = 0;
          try {
            while (true) {
              const { done, value } = await reader.read(); if (done) break;
              size += value.byteLength;
              if (size > MAX_LEGACY_PDF_BYTES) throw new Error('PDF_SIZE_INVALID');
              chunks.push(value);
            }
          } catch (downloadError) { await reader.cancel(); throw downloadError; }
          bytes = Buffer.concat(chunks);
        }
        const inspected = inspectLegacyPdf(bytes);
        writeFileSync(localPath, bytes);
        stage = 'storage';
        const storage = bridge.db.storage.from(BUCKET);
        const listed = await storage.list('legacy', { search: `${document.id}.pdf`, limit: 100 });
        if (listed.error) throw new Error('STORAGE_LIST_FAILED');
        if (listed.data?.some(object => object.name === `${document.id}.pdf`)) {
          const existing = await storage.download(objectPath);
          if (existing.error || !existing.data || inspectLegacyPdf(new Uint8Array(await existing.data.arrayBuffer())).sha256 !== inspected.sha256) throw new Error('EXISTING_OBJECT_MISMATCH');
        } else {
          const upload = await storage.upload(objectPath, bytes, { contentType: 'application/pdf', upsert: false });
          if (upload.error) throw new Error('STORAGE_UPLOAD_FAILED');
        }
        stage = 'link';
        const updated = await bridge.db.from('rm_documentos').update({ arquivo_url: canonicalUrl })
          .eq('id', document.id).eq('s3_key', document.s3_key).is('arquivo_url', null).select('id');
        if (updated.error || updated.data?.length !== 1) throw new Error('DOCUMENT_CHANGED_BEFORE_LINK');
        report.imported++; report.files.push({ id: document.id, ...inspected, sourceKeySha256, reusedProbe: reuseProbe });
      } catch {
        report.failed++; report.files.push({ id: document.id, failed: true, stage });
      } finally { save(); }
    }
  });
  console.info(JSON.stringify({ apply, expected: report.expected, imported: report.imported, unchanged: report.unchanged, failed: report.failed }));
  if (report.failed) process.exitCode = 1;
}

main().catch(() => { console.error('Existing PDF import failed; no source keys or credentials logged.'); process.exitCode = 1; });

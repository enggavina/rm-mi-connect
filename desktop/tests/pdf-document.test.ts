import assert from 'node:assert/strict';
import test from 'node:test';
import { inspectLegacyPdf, legacyPdfPath, MAX_LEGACY_PDF_BYTES } from '../src/server/bridge/pdf-document';

test('legacy file inspection rejects HTML, empty, truncated and oversized downloads', () => {
  assert.throws(() => inspectLegacyPdf(Buffer.from('<html>gateway error</html>')), /PDF_HEADER_INVALID/);
  assert.throws(() => inspectLegacyPdf(new Uint8Array()), /PDF_SIZE_INVALID/);
  assert.throws(() => inspectLegacyPdf(Buffer.from('%PDF-1.7\ntruncated')), /PDF_EOF_MISSING/);
  assert.throws(() => inspectLegacyPdf(new Uint8Array(MAX_LEGACY_PDF_BYTES + 1)), /PDF_SIZE_INVALID/);
  const sample = Buffer.from('%PDF-1.7\nexample\n%%EOF\n');
  assert.equal(inspectLegacyPdf(sample).bytes, sample.length);
  assert.equal(inspectLegacyPdf(sample).sha256.length, 64);
});

test('legacy object paths use a document UUID and reject source names or traversal', () => {
  assert.equal(legacyPdfPath('49c12f88-1074-4c38-814d-3b2b95cb727d'), 'legacy/49c12f88-1074-4c38-814d-3b2b95cb727d.pdf');
  assert.throws(() => legacyPdfPath('../another.pdf'), /DOCUMENT_ID_INVALID/);
  assert.throws(() => legacyPdfPath('source name.pdf'), /DOCUMENT_ID_INVALID/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { RM_MOBILE_SQLITE_DDL } from '../src/core/schema';
import { QUEUE_DOCUMENTS_MIGRATION } from '../src/core/queue-migration';
import { documentType, privateDocumentPath } from '../src/core/document-policy';
import { decodeBase64 } from '../src/core/sync-policy';

function oldDatabase() {
  const db = new DatabaseSync(':memory:');
  db.exec(RM_MOBILE_SQLITE_DDL.replace('numero TEXT,', 'numero TEXT NOT NULL,').replace(", 'rm-documentos'", '').replace(",\n      'rm_update_cell_status_v1',\n      'rm_add_cell_comment_v1'", ''));
  db.exec(`CREATE TABLE local_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    CREATE TABLE local_queue_meta(id TEXT PRIMARY KEY,actor_id TEXT,token_key TEXT,next_retry_at INTEGER);
    CREATE INDEX idx_local_media_pending ON local_media_upload_queue(status,created_at);
    CREATE INDEX idx_local_outbox_pending ON local_rpc_outbox(status,created_at);
    INSERT INTO local_projetos_cache(id,numero,updated_at) VALUES('existing-project','OS 42','2026-10-01');
    INSERT INTO local_media_upload_queue(id,bucket,local_uri,remote_path,status,attempts,last_error,created_at)
      VALUES('photo','rm-fotos','file:///persistent/photo.jpg','owner/photo.jpg','failed',3,'network','2026-10-01');
    INSERT INTO local_rpc_outbox(id,rpc_name,params_json,status,attempts,last_error,created_at)
      VALUES('protocol','rm_record_cell_photo_v1','{"p_foto_url":"file:///persistent/photo.jpg"}','failed',2,'offline','2026-10-01');
    INSERT INTO local_queue_meta VALUES('protocol','original-operator','secure-storage-reference',900);`);
  return db;
}
test('queue upgrade preserves offline protocols, attribution and retries while allowing documents and unnumbered projects', () => {
  const db = oldDatabase();
  const operation = db.prepare('SELECT * FROM local_rpc_outbox').get();
  const identity = db.prepare('SELECT * FROM local_queue_meta').get();
  db.exec(`BEGIN;${QUEUE_DOCUMENTS_MIGRATION}COMMIT;`);
  assert.deepEqual(db.prepare('SELECT * FROM local_rpc_outbox WHERE id=?').get('protocol'), operation);
  assert.deepEqual(db.prepare('SELECT * FROM local_queue_meta').get(), identity);
  const media = db.prepare('SELECT * FROM local_media_upload_queue').get()!;
  assert.equal(media.local_uri, 'file:///persistent/photo.jpg'); assert.equal(media.status, 'failed'); assert.equal(media.attempts, 3); assert.equal(media.mime_type, 'image/jpeg');
  db.exec(`INSERT INTO local_projetos_cache(id,numero,updated_at) VALUES('new-receipt',NULL,'2026-10-28');
    INSERT INTO local_media_upload_queue(id,bucket,local_uri,remote_path,created_at,mime_type,file_name) VALUES('invoice','rm-documentos','file:///nf.pdf','owner/nf.pdf','2026-10-28','application/pdf','NF.pdf');
    INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES('status','rm_update_cell_status_v1','{}','2026-10-28');
    INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES('comment','rm_add_cell_comment_v1','{}','2026-10-28');`);
  assert.equal(db.prepare('SELECT numero FROM local_projetos_cache WHERE id=?').get('existing-project')?.numero, 'OS 42');
  assert.equal(db.prepare('SELECT value FROM local_meta WHERE key=?').get('queue_schema_version')?.value, '2');
  db.close();
});
test('failed queue upgrade rolls back with the original pending work intact', () => {
  const db = oldDatabase(); db.exec('BEGIN');
  assert.throws(() => db.exec(`${QUEUE_DOCUMENTS_MIGRATION}INSERT INTO missing_table VALUES(1);`)); db.exec('ROLLBACK');
  assert.equal(db.prepare('SELECT actor_id FROM local_queue_meta').get()?.actor_id, 'original-operator');
  assert.equal(db.prepare('SELECT status FROM local_rpc_outbox').get()?.status, 'failed');
  assert.equal(db.prepare('SELECT value FROM local_meta WHERE key=?').get('queue_schema_version'), undefined);
  assert.throws(() => db.exec("INSERT INTO local_projetos_cache(id,numero,updated_at) VALUES('receipt',NULL,'2026-10-28')"));
  db.close();
});
test('invoice selection validates the supported filename and MIME combination', () => {
  assert.deepEqual(documentType('NF.PDF', 'application/pdf'), { mimeType: 'application/pdf', extension: 'pdf' });
  assert.equal(documentType('NF.jpeg', 'application/octet-stream').mimeType, 'image/jpeg');
  assert.throws(() => documentType('NF.html', 'application/pdf'));
  assert.throws(() => documentType('NF.pdf', 'text/html'));
});
test('private document signing applies only to the configured Supabase origin and bucket', () => {
  const base = 'https://project.supabase.co';
  assert.equal(privateDocumentPath(`${base}/storage/v1/object/authenticated/rm-documentos/owner/NF.pdf`, base), 'owner/NF.pdf');
  assert.equal(privateDocumentPath('https://foreign.example/storage/v1/object/authenticated/rm-documentos/owner/NF.pdf', base), null);
  assert.equal(privateDocumentPath(`${base}/storage/v1/object/public/rm-fotos/image.jpg`, base), null);
});
test('document-sized binary data decodes exactly without a temporary number array', () => {
  const bytes = Buffer.alloc(1024 * 1024 + 2); for (let i = 0; i < bytes.length; i++) bytes[i] = i % 256;
  assert.deepEqual(Buffer.from(decodeBase64(bytes.toString('base64'))), bytes);
});

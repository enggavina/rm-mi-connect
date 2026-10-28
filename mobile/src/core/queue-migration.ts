/** Atomic queue upgrade; preserves protocols, attribution metadata and retry state. */
export const QUEUE_DOCUMENTS_VERSION = 2;
export const QUEUE_DOCUMENTS_MIGRATION = `
ALTER TABLE local_projetos_cache RENAME TO local_projetos_cache_v1;
CREATE TABLE local_projetos_cache (
  id TEXT PRIMARY KEY, numero TEXT, nome TEXT, cliente_nome TEXT, escopo_abreviado TEXT,
  status TEXT, status_pcp TEXT, equipamento_json TEXT NOT NULL DEFAULT '{}', updated_at TEXT NOT NULL
);
INSERT INTO local_projetos_cache SELECT * FROM local_projetos_cache_v1;
DROP TABLE local_projetos_cache_v1;
ALTER TABLE local_media_upload_queue RENAME TO local_media_upload_queue_v1;
CREATE TABLE local_media_upload_queue (
  id TEXT PRIMARY KEY,
  bucket TEXT NOT NULL CHECK(bucket IN ('rm-fotos','rm-assinaturas','rm-documentos')),
  local_uri TEXT NOT NULL, remote_path TEXT NOT NULL, public_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','uploading','uploaded','failed')),
  attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_at TEXT NOT NULL,
  mime_type TEXT, file_name TEXT
);
INSERT INTO local_media_upload_queue(id,bucket,local_uri,remote_path,public_url,status,attempts,last_error,created_at,mime_type)
SELECT id,bucket,local_uri,remote_path,public_url,status,attempts,last_error,created_at,
  CASE WHEN bucket='rm-assinaturas' THEN 'image/png' ELSE 'image/jpeg' END FROM local_media_upload_queue_v1;
DROP TABLE local_media_upload_queue_v1;
CREATE INDEX idx_local_media_pending ON local_media_upload_queue(status,created_at);
ALTER TABLE local_rpc_outbox RENAME TO local_rpc_outbox_v1;
CREATE TABLE local_rpc_outbox (
  id TEXT PRIMARY KEY,
  rpc_name TEXT NOT NULL CHECK(rpc_name IN ('rm_submit_recebimento_v1','rm_submit_form_inspection_v1',
    'rm_submit_form_revision_v1','rm_transition_stage_approval_v1','rm_record_cell_photo_v1',
    'rm_update_cell_status_v1','rm_add_cell_comment_v1')),
  params_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','syncing','completed','failed')),
  attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_at TEXT NOT NULL
);
INSERT INTO local_rpc_outbox SELECT * FROM local_rpc_outbox_v1;
DROP TABLE local_rpc_outbox_v1;
CREATE INDEX idx_local_outbox_pending ON local_rpc_outbox(status,created_at);
INSERT INTO local_meta(key,value) VALUES ('queue_schema_version','2') ON CONFLICT(key) DO UPDATE SET value='2';
`;

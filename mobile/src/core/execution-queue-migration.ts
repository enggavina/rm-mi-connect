/** v3 is additive to the applied v2 upgrade. Rebuild only the RPC allowlist;
 * payloads, protocols, authors, results, retries and equal-time FIFO survive. */
export const QUEUE_EXECUTION_VERSION = 3;
export const QUEUE_EXECUTION_MIGRATION = `
ALTER TABLE local_rpc_outbox RENAME TO local_rpc_outbox_before_execution;
CREATE TABLE local_rpc_outbox (
 id TEXT PRIMARY KEY,
 rpc_name TEXT NOT NULL CHECK(rpc_name IN ('rm_submit_recebimento_v1','rm_submit_form_inspection_v1',
  'rm_submit_form_revision_v1','rm_transition_stage_approval_v1','rm_record_cell_photo_v1',
  'rm_update_cell_status_v1','rm_add_cell_comment_v1','rm_record_execution_event_v1')),
 params_json TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','syncing','completed','failed')),
 attempts INTEGER NOT NULL DEFAULT 0,last_error TEXT,created_at TEXT NOT NULL
);
INSERT INTO local_rpc_outbox(id,rpc_name,params_json,status,attempts,last_error,created_at)
 SELECT id,rpc_name,params_json,status,attempts,last_error,created_at FROM local_rpc_outbox_before_execution ORDER BY rowid;
DROP TABLE local_rpc_outbox_before_execution;
CREATE INDEX idx_local_outbox_pending ON local_rpc_outbox(status,created_at);
INSERT INTO local_meta(key,value) VALUES('queue_schema_version','3') ON CONFLICT(key) DO UPDATE SET value='3';
`;

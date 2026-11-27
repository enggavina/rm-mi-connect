export const QUEUE_WORKSHOP_VERSION = 4;

// Existing protocols retain their original payload and token. A prior queue row
// has no local proof of its workshop, so its origin is deliberately left null.
export const QUEUE_WORKSHOP_MIGRATION = `
ALTER TABLE local_queue_meta ADD COLUMN workshop_id TEXT;
INSERT INTO local_meta(key,value) VALUES('queue_schema_version','4') ON CONFLICT(key) DO UPDATE SET value='4';
`;

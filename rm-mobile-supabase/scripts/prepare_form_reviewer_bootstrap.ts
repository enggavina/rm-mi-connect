/** Offline only: compiles a read-only export and local-reference snapshot into
 * reviewable SQL. It loads no .env, opens no connection and applies nothing. */
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { formReviewerBootstrapSql, prepareFormReviewerBootstrap } from '../../desktop/src/server/bridge/form-reviewer-bootstrap';

const [sourcePath, lookupPath, outputPath] = process.argv.slice(2);
if (!sourcePath || !lookupPath || !outputPath) throw Error('Usage: tsx prepare_form_reviewer_bootstrap.ts source.json lookups.json .tmp/form-reviewer-bootstrap/<run>');
const root = path.resolve(import.meta.dirname, '../..'), allowed = path.join(root, '.tmp/form-reviewer-bootstrap'), out = path.resolve(outputPath);
if (out !== allowed && !out.startsWith(allowed + path.sep)) throw Error('Bootstrap artifacts must stay inside the ignored workspace .tmp/form-reviewer-bootstrap directory.');
const rawSource = readFileSync(path.resolve(sourcePath)), rawLookups = readFileSync(path.resolve(lookupPath));
const plan = prepareFormReviewerBootstrap(JSON.parse(rawSource.toString('utf8')), JSON.parse(rawLookups.toString('utf8')));
mkdirSync(out, { recursive: true });
const files = { 'plan.json': JSON.stringify(plan, null, 2) + '\n', 'quarantine.json': JSON.stringify(plan.quarantine, null, 2) + '\n',
  'rehearsal.sql': formReviewerBootstrapSql(plan), 'apply.sql': formReviewerBootstrapSql(plan, true) };
for (const [file, text] of Object.entries(files)) writeFileSync(path.join(out, file), text);
const sha256 = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
const summary = { preparedAt: new Date().toISOString(), mode: 'prepared-only; no database or remote source contacted', version: plan.version,
  cutoff: plan.cutoff, sourceHash: plan.sourceHash, ...plan.counts,
  quarantineReasons: plan.quarantine.reduce<Record<string, number>>((counts, item) => ({ ...counts, [item.reason]: (counts[item.reason] ?? 0) + item.source_ids.length }), {}) };
writeFileSync(path.join(out, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
writeFileSync(path.join(out, 'manifest.json'), JSON.stringify({ raw_source_sha256: sha256(rawSource), lookups_sha256: sha256(rawLookups),
  files: Object.fromEntries(Object.entries(files).map(([file, text]) => [file, sha256(text)])) }, null, 2) + '\n');
console.info(JSON.stringify(summary));

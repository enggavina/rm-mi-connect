import { z } from 'zod';
import { workshopScopeInventory } from './workshop-inventory';

const code = z.string().regex(/^[A-Z0-9][A-Z0-9_-]{0,39}$/);
const adoption = z.object({
  format_version: z.literal(1), application: z.literal('em'),
  operational_project_ref: z.literal('ellpxfbsrbhblyizvbbk'), authority_project_ref: z.literal('kxoriwvzmxhatzqcgnht'),
  confirmation: z.object({ source: z.literal('explicit_user_reply'), date: z.iso.date(),
    statement: z.string().min(1).max(2000) }).strict(),
  legacy_workshop_code: code,
  workshops: z.array(z.object({ code, name: z.string().trim().min(1).max(200).regex(/^[^\u0000-\u001f\u007f]+$/) }).strict()).min(1).max(100),
}).strict();

/** Generates a migration REVIEW plan, never SQL, assignments, IDs or grants.
 * User confirmation assigns the existing acervo to BMA; FK paths alone cannot
 * decide how private sessions, shared catalogs or future offline work are scoped. */
export function workshopAdoptionPlan(metadata: unknown, declaration: unknown) {
  const parsed = adoption.safeParse(declaration);
  if (!parsed.success) throw new Error('Declaração de oficinas inválida.');
  const source = parsed.data;
  const codes = new Set(source.workshops.map(item => item.code));
  if (codes.size !== source.workshops.length || !codes.has(source.legacy_workshop_code)) throw new Error('Oficinas duplicadas ou origem do acervo não declarada.');
  const inventory = workshopScopeInventory(metadata);
  if (!['public.rm_projetos', 'public.rm_celulas'].every(name => inventory.tables.some(t => t.name === name))) {
    throw new Error('Inventário sem as raízes de projetos e células.');
  }
  return {
    format_version: 1 as const, application: 'em' as const,
    operational_project_ref: source.operational_project_ref, authority_project_ref: source.authority_project_ref,
    confirmation: source.confirmation, metadata_captured_at: inventory.captured_at,
    legacy_workshop_code: source.legacy_workshop_code,
    central_registration_verified: false as const, isolation_proven: false as const, activation_ready: false as const,
    workshops: source.workshops.map(item => ({ ...item, central_id: null, proposed_availability: item.code === source.legacy_workshop_code ? 'existing_operation' : 'blocked_until_isolation' })),
    // All 90 tables remain accounted for, including objects not reached by an FK.
    tables: inventory.tables.map(table => ({ ...table,
      legacy_root_owner_code: ['public.rm_projetos', 'public.rm_celulas'].includes(table.name) ? source.legacy_workshop_code : null,
      migration_rule: 'pending_review' as const,
    })),
    routines: inventory.routines, totals: inventory.totals,
    pending_gates: ['register_and_verify_central_ids', 'explicit_principal_bindings', 'classify_all_relations_and_files',
      'preserving_backfill_with_concurrent_writes', 'database_rpc_storage_job_isolation', 'web_current_context_enforcement',
      'mobile_password_delegation_and_offline_origin', 'cross_workshop_denial_tests', 'authenticated_acceptance'],
    constraints: { login_workshop_selector: false, mobile_sso: false, implicit_principal_grants: false,
      reassign_offline_queue: false, execute_sql: false, production_data_modified: false },
  };
}

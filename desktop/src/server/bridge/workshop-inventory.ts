import { z } from 'zod';

// Catalog names are output metadata, never SQL interpolation. PostgreSQL also
// permits quoted constraint/column names (Storage uses objects_bucketId_fkey).
const identifier = z.string().min(1).max(63).regex(/^[^\u0000-\u001f\u007f]+$/);
const relation = z.string().regex(/^[a-z_][a-z0-9_]{0,62}\.[a-z_][a-z0-9_]{0,62}$/);
const foreignKey = z.object({ name: identifier, columns: z.array(identifier).min(1).max(32),
  target: relation, target_columns: z.array(identifier).min(1).max(32) }).strict();
const privileges = z.object({ schema_usage: z.boolean(), select: z.boolean(), insert: z.boolean(), update: z.boolean(), delete: z.boolean() }).strict();
const table = z.object({ name: relation, rls_enabled: z.boolean(), rls_forced: z.boolean(),
  access: z.object({ anon: privileges, authenticated: privileges, service_role: privileges }).strict(),
  columns: z.array(identifier).min(1).max(1600), foreign_keys: z.array(foreignKey).max(128),
  policies: z.array(z.object({ name: identifier, command: z.enum(['r', 'a', 'w', 'd', '*']), permissive: z.boolean(), roles: z.array(identifier).min(1).max(128) }).strict()).max(128),
}).strict();
const routine = z.object({ name: relation, signature: z.string().max(4096), security_definer: z.boolean(),
  anon_execute: z.boolean(), authenticated_execute: z.boolean(), service_role_execute: z.boolean() }).strict();
const inventorySchema = z.object({ format_version: z.literal(1), source: z.literal('postgresql_catalog'),
  captured_at: z.iso.datetime({ offset: true }), tables: z.array(table).min(1).max(2000), routines: z.array(routine).max(5000),
}).strict();
type Table = z.infer<typeof table>;
type ReferenceStep = { table: string; constraint: string; columns: string[]; target: string; target_columns: string[] };
const unique = (values: string[]) => new Set(values).size === values.length;
const belongs = (name: string) => /^public\.rm_/.test(name) || name.startsWith('rm_private.') || ['storage.objects', 'storage.buckets'].includes(name);

/** One shortest FK path for review. A reference path never assigns ownership,
 * proves row consistency or authorizes any principal. The full FK list is kept. */
function referencePath(tables: Map<string, Table>, from: string, root: string): ReferenceStep[] | null {
  if (!tables.has(root)) return null;
  const queue: { name: string; path: ReferenceStep[] }[] = [{ name: from, path: [] }];
  const visited = new Set([from]);
  for (let index = 0; index < queue.length; index++) {
    const entry = queue[index];
    if (entry.name === root) return entry.path;
    for (const key of tables.get(entry.name)?.foreign_keys ?? []) {
      if (!tables.has(key.target) || visited.has(key.target)) continue;
      visited.add(key.target);
      queue.push({ name: key.target, path: [...entry.path, { table: entry.name, constraint: key.name,
        columns: [...key.columns], target: key.target, target_columns: [...key.target_columns] }] });
    }
  }
  return null;
}

export function workshopScopeInventory(value: unknown) {
  const parsed = inventorySchema.safeParse(value);
  if (!parsed.success) throw new Error('Inventário de metadados inválido ou incompleto.');
  const source = parsed.data;
  const sorted = [...source.tables].sort((a,b) => a.name.localeCompare(b.name, 'en'));
  const byName = new Map(sorted.map(item => [item.name, item]));
  if (byName.size !== sorted.length || !unique(source.routines.map(r => `${r.name}(${r.signature})`))) throw new Error('Inventário com objetos duplicados.');
  for (const item of sorted) {
    if (!belongs(item.name) || !unique(item.columns) || !unique(item.foreign_keys.map(k => k.name)) || !unique(item.policies.map(p => p.name))) throw new Error('Inventário fora do escopo EM ou com referências duplicadas.');
    for (const key of item.foreign_keys) {
      if (key.columns.length !== key.target_columns.length || !unique(key.columns) || !unique(key.target_columns)
        || key.columns.some(column => !item.columns.includes(column))) throw new Error('Vínculo inválido no inventário.');
      const target = byName.get(key.target);
      if (target && key.target_columns.some(column => !target.columns.includes(column))
        || !target && belongs(key.target)) throw new Error('Inventário com vínculo EM incompleto.');
    }
  }
  if (source.routines.some(r => !/^public\.rm_|^rm_private\./.test(r.name))) throw new Error('Rotina fora do escopo EM.');
  const tables = sorted.map(item => ({ ...item,
    review_status: 'pending' as const,
    scope_columns: item.columns.filter(column => ['workshop_id', 'oficina_id', 'tenant_id'].includes(column)),
    project_reference_path: referencePath(byName, item.name, 'public.rm_projetos'),
    cell_reference_path: referencePath(byName, item.name, 'public.rm_celulas'),
  }));
  return {
    format_version: 1 as const, source: source.source, captured_at: source.captured_at,
    isolation_proven: false as const,
    interpretation: 'Metadados e caminhos relacionais para revisão; não atribuem oficina, propriedade ou acesso. A ausência de objetos esperados exige conferir a origem e a completude da captura.',
    totals: { tables: tables.length, foreign_keys: tables.reduce((sum,t) => sum+t.foreign_keys.length,0),
      tables_with_scope_column: tables.filter(t => t.scope_columns.length).length,
      tables_without_rls: tables.filter(t => !t.rls_enabled).length,
      routines: source.routines.length, security_definer_routines: source.routines.filter(r => r.security_definer).length },
    tables, routines: [...source.routines].sort((a,b) => `${a.name}(${a.signature})`.localeCompare(`${b.name}(${b.signature})`, 'en')),
  };
}

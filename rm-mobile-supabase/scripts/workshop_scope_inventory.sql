begin isolation level repeatable read read only;
set local statement_timeout = '30s';
set local search_path = '';

-- Catalog metadata only: no business rows, user records, Storage keys or JWTs.
-- This is an inventory, never evidence that workshop isolation is implemented.
with relations as (
  select c.oid, n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p') and (
    n.nspname = 'public' and c.relname like 'rm\_%' escape '\'
    or n.nspname = 'rm_private'
    or n.nspname = 'storage' and c.relname in ('objects', 'buckets')
  )
), tables as (
  select jsonb_build_object(
    'name', r.nspname || '.' || r.relname,
    'rls_enabled', r.relrowsecurity,
    'rls_forced', r.relforcerowsecurity,
    'access', (select jsonb_object_agg(role_name, jsonb_build_object(
      'schema_usage', pg_catalog.has_schema_privilege(role_name, r.nspname, 'usage'),
      'select', pg_catalog.has_table_privilege(role_name, r.oid, 'select'),
      'insert', pg_catalog.has_table_privilege(role_name, r.oid, 'insert'),
      'update', pg_catalog.has_table_privilege(role_name, r.oid, 'update'),
      'delete', pg_catalog.has_table_privilege(role_name, r.oid, 'delete')
    )) from (values ('anon'), ('authenticated'), ('service_role')) roles(role_name)),
    'columns', coalesce((select jsonb_agg(a.attname order by a.attnum)
      from pg_catalog.pg_attribute a where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped), '[]'::jsonb),
    'foreign_keys', coalesce((select jsonb_agg(jsonb_build_object(
      'name', k.conname,
      'columns', (select jsonb_agg(a.attname order by x.ord)
        from unnest(k.conkey) with ordinality x(num, ord)
        join pg_catalog.pg_attribute a on a.attrelid = k.conrelid and a.attnum = x.num),
      'target', tn.nspname || '.' || tc.relname,
      'target_columns', (select jsonb_agg(a.attname order by x.ord)
        from unnest(k.confkey) with ordinality x(num, ord)
        join pg_catalog.pg_attribute a on a.attrelid = k.confrelid and a.attnum = x.num)
    ) order by k.conname)
      from pg_catalog.pg_constraint k
      join pg_catalog.pg_class tc on tc.oid = k.confrelid
      join pg_catalog.pg_namespace tn on tn.oid = tc.relnamespace
      where k.conrelid = r.oid and k.contype = 'f'), '[]'::jsonb),
    'policies', coalesce((select jsonb_agg(jsonb_build_object(
      'name', p.polname, 'command', p.polcmd::text, 'permissive', p.polpermissive,
      'roles', (select jsonb_agg(case when role_id = 0 then 'public' else pg_catalog.pg_get_userbyid(role_id)::text end order by role_id)
        from unnest(p.polroles) role_ids(role_id))
    ) order by p.polname) from pg_catalog.pg_policy p where p.polrelid = r.oid), '[]'::jsonb)
  ) item
  from relations r
), routines as (
  select jsonb_build_object(
    'name', n.nspname || '.' || p.proname,
    'signature', pg_catalog.pg_get_function_identity_arguments(p.oid),
    'security_definer', p.prosecdef,
    'anon_execute', pg_catalog.has_function_privilege('anon', p.oid, 'execute'),
    'authenticated_execute', pg_catalog.has_function_privilege('authenticated', p.oid, 'execute'),
    'service_role_execute', pg_catalog.has_function_privilege('service_role', p.oid, 'execute')
  ) item
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'rm_private' or n.nspname = 'public' and p.proname like 'rm\_%' escape '\'
)
select jsonb_build_object(
  'format_version', 1,
  'source', 'postgresql_catalog',
  'captured_at', pg_catalog.clock_timestamp(),
  'tables', coalesce((select jsonb_agg(item order by item->>'name') from tables), '[]'::jsonb),
  'routines', coalesce((select jsonb_agg(item order by item->>'name', item->>'signature') from routines), '[]'::jsonb)
) as inventory;
commit;

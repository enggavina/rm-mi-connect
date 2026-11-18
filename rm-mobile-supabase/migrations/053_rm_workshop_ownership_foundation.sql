-- Private ownership foundation only. Does NOT activate workshop isolation,
-- grant access, create central offices or assign future/offline records by default.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_references (
  id uuid primary key,
  code text not null unique check(code in ('BMA','BRJ','BBH')),
  authority text not null check(authority='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1')
);
create table rm_private.workshop_legacy_adoption (
  singleton boolean primary key default true check(singleton),
  legacy_workshop_id uuid not null references rm_private.workshop_references(id),
  declaration_sha256 text not null check(declaration_sha256='c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2'),
  central_manifest jsonb not null check(jsonb_typeof(central_manifest)='array' and jsonb_array_length(central_manifest)=3),
  manifest_sha256 text not null check(manifest_sha256 ~ '^[0-9a-f]{64}$'),
  project_count bigint not null check(project_count>=0),
  cell_count bigint not null check(cell_count>=0),
  recorded_at timestamptz not null default clock_timestamp(),
  database_actor text not null default session_user,
  phase text not null default 'foundation_only' check(phase='foundation_only')
);
create table rm_private.workshop_project_ownership (
  -- Same ID as its project, compatible with the existing deletion closure.
  id uuid primary key references public.rm_projetos(id) on delete cascade,
  workshop_id uuid not null references rm_private.workshop_references(id),
  adoption boolean not null default true references rm_private.workshop_legacy_adoption(singleton) check(adoption)
);
create table rm_private.workshop_cell_ownership (
  cell_id uuid primary key references public.rm_celulas(id) on delete cascade,
  workshop_id uuid not null references rm_private.workshop_references(id),
  adoption boolean not null default true references rm_private.workshop_legacy_adoption(singleton) check(adoption)
);
create index workshop_project_owner on rm_private.workshop_project_ownership(workshop_id,id);
create index workshop_cell_owner on rm_private.workshop_cell_ownership(workshop_id,cell_id);

alter table rm_private.workshop_references enable row level security;
alter table rm_private.workshop_legacy_adoption enable row level security;
alter table rm_private.workshop_project_ownership enable row level security;
alter table rm_private.workshop_cell_ownership enable row level security;
revoke all on rm_private.workshop_references,rm_private.workshop_legacy_adoption,
  rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership from public,anon,authenticated,service_role;

create function rm_private.workshop_adoption_immutable_v1()
returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='42501',message='Workshop adoption receipt is immutable.'; end;
$$;
create trigger workshop_adoption_immutable before update or delete on rm_private.workshop_legacy_adoption
  for each row execute function rm_private.workshop_adoption_immutable_v1();

-- Technical owner-only operation, not an RPC for application users. The caller
-- must verify the exact IDs against Acessos before executing. No JWT/user is
-- fabricated; the receipt records the real database session role.
create function rm_private.workshop_adopt_bma_roots_v1(p_offices jsonb,p_declaration_sha256 text,
  p_expected_projects bigint,p_expected_cells bigint)
returns jsonb language plpgsql volatile set search_path='' as $$
declare canonical jsonb; item jsonb; bma uuid; digest text; receipt rm_private.workshop_legacy_adoption;
begin
  if p_declaration_sha256 is distinct from 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2'
    or p_expected_projects is null or p_expected_projects<0 or p_expected_cells is null or p_expected_cells<0
    or p_offices is null or jsonb_typeof(p_offices)<>'array' or jsonb_array_length(p_offices)<>3
    then raise exception using errcode='22023',message='Explicit BMA declaration and central office manifest required.'; end if;
  for item in select value from jsonb_array_elements(p_offices) loop
    if jsonb_typeof(item)<>'object' or (select count(*) from jsonb_object_keys(item))<>2
      or not(item ?& array['id','code']) or jsonb_typeof(item->'id')<>'string' or jsonb_typeof(item->'code')<>'string'
      or item->>'id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or item->>'code' not in ('BMA','BRJ','BBH')
      then raise exception using errcode='22023',message='Invalid central office manifest.'; end if;
  end loop;
  if (select count(distinct value->>'code') from jsonb_array_elements(p_offices))<>3
    or (select count(distinct value->>'id') from jsonb_array_elements(p_offices))<>3
    then raise exception using errcode='22023',message='Central office identity must be unique.'; end if;
  select jsonb_agg(value order by value->>'code') into canonical from jsonb_array_elements(p_offices);
  digest:=encode(pg_catalog.sha256(convert_to(canonical::text,'UTF8')),'hex');
  select (value->>'id')::uuid into bma from jsonb_array_elements(canonical) where value->>'code'='BMA';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('em:workshop-adoption:v1',0));
  select * into receipt from rm_private.workshop_legacy_adoption where singleton;
  if found then
    if receipt.central_manifest is distinct from canonical or receipt.declaration_sha256<>p_declaration_sha256
      or receipt.project_count<>p_expected_projects or receipt.cell_count<>p_expected_cells
      then raise exception using errcode='PT409',message='Workshop adoption already recorded with different inputs.'; end if;
    -- A retry acknowledges the original batch; it NEVER assigns newly created
    -- or pending offline projects to BMA. Readiness exposes that remaining work.
    return jsonb_build_object('replayed',true,'legacy_workshop_id',receipt.legacy_workshop_id,
      'classified_projects',receipt.project_count,'classified_cells',receipt.cell_count,'isolation_active',false);
  end if;
  if exists(select 1 from rm_private.workshop_references) or exists(select 1 from rm_private.workshop_project_ownership)
    or exists(select 1 from rm_private.workshop_cell_ownership)
    then raise exception using errcode='PT409',message='Ownership foundation is not empty.'; end if;
  -- Briefly serialize the initial batch with legacy root writes. No project or
  -- cell row, ID, timestamp, response or attachment is updated by this function.
  lock table public.rm_projetos,public.rm_celulas in share row exclusive mode;
  if (select count(*) from public.rm_projetos)<>p_expected_projects or (select count(*) from public.rm_celulas)<>p_expected_cells
    then raise exception using errcode='PT409',message='Legacy roots changed; review the batch again.'; end if;
  insert into rm_private.workshop_references(id,code,authority)
    select (value->>'id')::uuid,value->>'code','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1' from jsonb_array_elements(canonical);
  insert into rm_private.workshop_legacy_adoption(singleton,legacy_workshop_id,declaration_sha256,central_manifest,manifest_sha256,project_count,cell_count)
    values(true,bma,p_declaration_sha256,canonical,digest,p_expected_projects,p_expected_cells);
  insert into rm_private.workshop_project_ownership(id,workshop_id) select id,bma from public.rm_projetos;
  insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) select id,bma from public.rm_celulas;
  return jsonb_build_object('replayed',false,'legacy_workshop_id',bma,'classified_projects',p_expected_projects,
    'classified_cells',p_expected_cells,'isolation_active',false);
end;
$$;

-- Counts only, for a technical migration review. It cannot activate isolation.
create function rm_private.workshop_ownership_readiness_v1()
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object('foundation_only',true,'isolation_active',false,
    'adoption_recorded',exists(select 1 from rm_private.workshop_legacy_adoption),
    'projects_total',(select count(*) from public.rm_projetos),
    'projects_classified',(select count(*) from rm_private.workshop_project_ownership),
    'projects_pending',(select count(*) from public.rm_projetos p where not exists(select 1 from rm_private.workshop_project_ownership o where o.id=p.id)),
    'cells_total',(select count(*) from public.rm_celulas),
    'cells_classified',(select count(*) from rm_private.workshop_cell_ownership),
    'cells_pending',(select count(*) from public.rm_celulas c where not exists(select 1 from rm_private.workshop_cell_ownership o where o.cell_id=c.id)),
    'allocation_conflicts',(select count(*) from public.rm_celulas_projeto a
      join rm_private.workshop_project_ownership p on p.id=a.projeto_id
      join rm_private.workshop_cell_ownership c on c.cell_id=a.celula_id where p.workshop_id<>c.workshop_id));
$$;
revoke all on function rm_private.workshop_adoption_immutable_v1(),
  rm_private.workshop_adopt_bma_roots_v1(jsonb,text,bigint,bigint),rm_private.workshop_ownership_readiness_v1()
  from public,anon,authenticated,service_role;

-- Keep the existing shared-reference protection effective after adoption. The
-- new one-to-one metadata belongs to the project's proven deletion closure.
-- Preserve the existing function OID, owner and ACL; only its body is extended.
do $$begin
 if (select encode(sha256(convert_to(prosrc,'UTF8')),'hex') from pg_proc
   where oid='rm_private.project_delete_scope_v1(uuid)'::regprocedure)
   is distinct from 'b5a90b40d994b03a131d95b1a316fee6bb72a96be89d555d5cbad2dd1ff2dced'
 then raise exception 'Unexpected existing project deletion scope';end if;
end$$;
create or replace function rm_private.project_delete_scope_v1(p_project uuid) returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 select * from rm_private.project_delete_scope_before_execution_v1(p_project)
 union all select 'rm_private','execution_reviews',array(select r.id from rm_private.execution_reviews r join rm_private.execution_sessions s on s.id=r.session_id join public.rm_celulas_projeto a on a.id=s.allocation_id where a.projeto_id=p_project)
 union all select 'rm_private','execution_events',array(select e.id from rm_private.execution_events e join rm_private.execution_sessions s on s.id=e.session_id join public.rm_celulas_projeto a on a.id=s.allocation_id where a.projeto_id=p_project)
 union all select 'rm_private','execution_sessions',array(select s.id from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id where a.projeto_id=p_project)
 union all select 'rm_private','workshop_project_ownership',array(select o.id from rm_private.workshop_project_ownership o where o.id=p_project);
$$;
commit;

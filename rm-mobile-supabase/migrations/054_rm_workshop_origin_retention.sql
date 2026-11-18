-- Durable origin metadata only. No personal grants, office default, tenant
-- activation or change to the login/password and offline protocols.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
-- Serialize the initial snapshot with assignment/deletion of live ownership.
lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership in share row exclusive mode;

create table rm_private.workshop_object_origins (
  object_kind text not null check(object_kind in('project','cell')),
  object_id uuid not null,
  workshop_id uuid not null references rm_private.workshop_references(id),
  captured_from text not null check(captured_from in('existing_ownership','ownership_write')),
  captured_at timestamptz not null default clock_timestamp(),
  database_actor text not null default session_user,
  primary key(object_kind,object_id)
  -- Deliberately no FK to the business object or its disposable live mapping.
  -- The original namespace must survive deletion and delayed offline work.
);
create table rm_private.workshop_origin_retirements (
  object_kind text not null,
  object_id uuid not null,
  reason text not null default 'ownership_removed' check(reason='ownership_removed'),
  retired_at timestamptz not null default clock_timestamp(),
  database_actor text not null default session_user,
  primary key(object_kind,object_id),
  foreign key(object_kind,object_id) references rm_private.workshop_object_origins(object_kind,object_id)
);
create index workshop_origins_by_office on rm_private.workshop_object_origins(workshop_id,object_kind,object_id);
alter table rm_private.workshop_object_origins enable row level security;
alter table rm_private.workshop_origin_retirements enable row level security;
revoke all on rm_private.workshop_object_origins,rm_private.workshop_origin_retirements from public,anon,authenticated,service_role;

-- Copy only the ownership explicitly recorded by 053 or a later authorized
-- assignment. Unknown roots and historical deleted objects are not inferred.
insert into rm_private.workshop_object_origins(object_kind,object_id,workshop_id,captured_from)
select 'project',id,workshop_id,'existing_ownership' from rm_private.workshop_project_ownership
union all select 'cell',cell_id,workshop_id,'existing_ownership' from rm_private.workshop_cell_ownership;

create function rm_private.workshop_origin_immutable_v1()
returns trigger language plpgsql set search_path='' as $$
begin raise exception using errcode='42501',message='Workshop origin history is immutable.';end;
$$;
create trigger workshop_origins_immutable before update or delete on rm_private.workshop_object_origins
 for each row execute function rm_private.workshop_origin_immutable_v1();
create trigger workshop_origins_no_truncate before truncate on rm_private.workshop_object_origins
 for each statement execute function rm_private.workshop_origin_immutable_v1();
create trigger workshop_retirements_immutable before update or delete on rm_private.workshop_origin_retirements
 for each row execute function rm_private.workshop_origin_immutable_v1();
create trigger workshop_retirements_no_truncate before truncate on rm_private.workshop_origin_retirements
 for each statement execute function rm_private.workshop_origin_immutable_v1();

create function rm_private.workshop_capture_origin_v1()
returns trigger language plpgsql set search_path='' as $$
declare kind text;object_key uuid;office_key uuid;stored_office uuid;
begin
 if tg_table_schema<>'rm_private' or tg_table_name not in('workshop_project_ownership','workshop_cell_ownership')
 then raise exception using errcode='42501',message='Unexpected origin source.';end if;
 kind:=case when tg_table_name='workshop_project_ownership' then 'project' else 'cell' end;
 if tg_op='UPDATE' then
  if new.workshop_id is distinct from old.workshop_id then
   raise exception using errcode='PT409',message='Origin identity cannot be reassigned.';end if;
  if kind='project' then
   if new.id is distinct from old.id then
    raise exception using errcode='PT409',message='Origin identity cannot be reassigned.';end if;
  else
   if new.cell_id is distinct from old.cell_id then
    raise exception using errcode='PT409',message='Origin identity cannot be reassigned.';end if;
  end if;
 end if;
 if kind='project' then object_key:=case when tg_op='DELETE' then old.id else new.id end;
 else object_key:=case when tg_op='DELETE' then old.cell_id else new.cell_id end;end if;
 office_key:=case when tg_op='DELETE' then old.workshop_id else new.workshop_id end;
 -- A nonblocking key lock prevents delete/recreate races without introducing a
 -- wait cycle with the existing project row and deletion locks. Retry preserves
 -- the same client submission and all business/offline content.
 if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-origin:v1:'||kind||':'||object_key::text,0))
 then raise exception using errcode='PT409',message='Origin is being reviewed; retry the same operation.';end if;
 if tg_op<>'DELETE' and exists(select 1 from rm_private.workshop_origin_retirements where object_kind=kind and object_id=object_key)
 then raise exception using errcode='PT410',message='Origin was retired; preserve the pending record for review.';end if;
 insert into rm_private.workshop_object_origins(object_kind,object_id,workshop_id,captured_from)
 values(kind,object_key,office_key,'ownership_write') on conflict(object_kind,object_id) do nothing;
 select workshop_id into stored_office from rm_private.workshop_object_origins where object_kind=kind and object_id=object_key;
 if stored_office is distinct from office_key
 then raise exception using errcode='PT409',message='Origin identity cannot be reassigned.';end if;
 if tg_op='DELETE' then
  insert into rm_private.workshop_origin_retirements(object_kind,object_id) values(kind,object_key)
   on conflict(object_kind,object_id) do nothing;
  return old;
 end if;
 return new;
end;
$$;
create trigger workshop_project_origin before insert or update or delete on rm_private.workshop_project_ownership
 for each row execute function rm_private.workshop_capture_origin_v1();
create trigger workshop_cell_origin before insert or update or delete on rm_private.workshop_cell_ownership
 for each row execute function rm_private.workshop_capture_origin_v1();
create trigger workshop_project_origin_no_truncate before truncate on rm_private.workshop_project_ownership
 for each statement execute function rm_private.workshop_origin_immutable_v1();
create trigger workshop_cell_origin_no_truncate before truncate on rm_private.workshop_cell_ownership
 for each statement execute function rm_private.workshop_origin_immutable_v1();

-- Internal building block for the future authenticated scope boundary. It does
-- not authenticate a person, validate Acessos, grant capabilities or scope SQL
-- by itself. The caller must supply a previously verified authority context.
create function rm_private.workshop_assert_origin_v1(p_kind text,p_id uuid,p_workshop uuid)
returns void language plpgsql set search_path='' as $$
begin
 if p_kind is null or p_kind not in('project','cell') or p_id is null or p_workshop is null
 then raise exception using errcode='42501',message='Verified origin required.';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-origin:v1:'||p_kind||':'||p_id::text,0))
 then raise exception using errcode='PT409',message='Origin is being reviewed; retry the same operation.';end if;
 if not exists(select 1 from rm_private.workshop_object_origins where object_kind=p_kind and object_id=p_id and workshop_id=p_workshop)
  or exists(select 1 from rm_private.workshop_origin_retirements where object_kind=p_kind and object_id=p_id)
  or (p_kind='project' and not exists(select 1 from rm_private.workshop_project_ownership where id=p_id and workshop_id=p_workshop))
  or (p_kind='cell' and not exists(select 1 from rm_private.workshop_cell_ownership where cell_id=p_id and workshop_id=p_workshop))
 then raise exception using errcode='42501',message='Verified origin required.';end if;
end;
$$;

create function rm_private.workshop_origin_readiness_v1()
returns jsonb language sql stable set search_path='' as $$
 with mappings as (
  select 'project'::text kind,id object_id,workshop_id from rm_private.workshop_project_ownership
  union all select 'cell',cell_id,workshop_id from rm_private.workshop_cell_ownership
 ), deleted as (
  select distinct case when payload->>'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   then (payload->>'id')::uuid end id from rm_private.web_mutation_receipts where operation='delete_project'
 )
 select jsonb_build_object('format_version',1,'origin_retention_enabled',true,'isolation_active',false,
  'roots',rm_private.workshop_ownership_readiness_v1(),
  'project_origins',(select count(*) from rm_private.workshop_object_origins where object_kind='project'),
  'cell_origins',(select count(*) from rm_private.workshop_object_origins where object_kind='cell'),
  'retirements',(select count(*) from rm_private.workshop_origin_retirements),
  'mappings_without_matching_origin',(select count(*) from mappings m where not exists(select 1 from rm_private.workshop_object_origins o where o.object_kind=m.kind and o.object_id=m.object_id and o.workshop_id=m.workshop_id)),
  'mappings_with_retirement',(select count(*) from mappings m join rm_private.workshop_origin_retirements r on r.object_kind=m.kind and r.object_id=m.object_id),
  'origins_without_mapping_or_retirement',(select count(*) from rm_private.workshop_object_origins o where not exists(select 1 from mappings m where m.kind=o.object_kind and m.object_id=o.object_id) and not exists(select 1 from rm_private.workshop_origin_retirements r where r.object_kind=o.object_kind and r.object_id=o.object_id)),
  'known_legacy_deletions_without_origin',(select count(*) from deleted d where d.id is not null and not exists(select 1 from rm_private.workshop_object_origins o where o.object_kind='project' and o.object_id=d.id)));
$$;
revoke all on function rm_private.workshop_origin_immutable_v1(),rm_private.workshop_capture_origin_v1(),
 rm_private.workshop_assert_origin_v1(text,uuid,uuid),rm_private.workshop_origin_readiness_v1()
 from public,anon,authenticated,service_role;
commit;

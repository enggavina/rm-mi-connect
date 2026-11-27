begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

alter table rm_private.root_creation_settings add column edits_enforced boolean not null default false;
alter table rm_private.root_creation_permits drop constraint root_creation_permits_operation_check;
alter table rm_private.root_creation_permits add constraint root_creation_permits_operation_check
 check(operation in('save_project','save_project_with_equipment','save_catalog','delete_catalog'));

create function rm_private.web_root_edit_kind_v1(p_operation text,p_payload jsonb)
returns text language sql immutable set search_path='' as $$
 select case when jsonb_typeof(p_payload->'expected_updated_at')='string' then
  case
   when p_operation in('save_project','save_project_with_equipment') then 'project'
   when p_operation='save_catalog' and p_payload->>'kind'='cells' then 'cell'
  end
 end;
$$;
revoke all on function rm_private.web_root_edit_kind_v1(text,jsonb) from public,anon,authenticated,service_role;

create or replace function rm_private.web_root_write_kind_v1(p_operation text,p_payload jsonb)
returns text language sql immutable set search_path='' as $$
 select case when p_operation='delete_catalog' and p_payload->>'kind'='cells' then 'cell'
 when p_payload->'expected_updated_at' = 'null'::jsonb then
  case
   when p_operation='save_project_with_equipment' then 'project'
   when p_operation='save_catalog' and p_payload->>'kind'='cells' then 'cell'
  end
 else rm_private.web_root_edit_kind_v1(p_operation,p_payload)
 end;
$$;

do $extend$
declare
 dispatch text:=pg_get_functiondef('rm_private.web_mutate_root_creation_v1(uuid,text,jsonb)'::regprocedure);
 legacy text:='if exists(select 1 from rm_private.root_creation_settings where singleton and deployment_id is null for share) then';
 owner_check text:='if (office is not null or root_exists) and office is distinct from permit.workshop_id then';
begin
 if array_length(string_to_array(dispatch,legacy),1) is distinct from 2
  or array_length(string_to_array(dispatch,owner_check),1) is distinct from 2 then
  raise exception 'Unexpected root write dispatch';
 end if;
 dispatch:=replace(dispatch,legacy,$fallback$if exists(select 1 from rm_private.root_creation_settings where singleton and
   case when rm_private.web_root_edit_kind_v1(p_operation,p_payload) is not null then not edits_enforced
    else deployment_id is null end for share) then$fallback$);
 execute replace(dispatch,owner_check,$scope$if ((office is not null or root_exists) and office is distinct from permit.workshop_id)
   or (rm_private.web_root_edit_kind_v1(p_operation,p_payload) is not null and not root_exists) then$scope$);
end
$extend$;

create function rm_private.activate_root_workshop_edits_v1()
returns void language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from rm_private.workshop_root_enforcement where singleton and activated_at is not null) then
  raise exception 'Conclua a ativação da origem antes de habilitar edições por oficina.' using errcode='PT409';
 end if;
 update rm_private.root_creation_settings set edits_enforced=true where singleton and not edits_enforced;
end
$$;
revoke all on function rm_private.activate_root_workshop_edits_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

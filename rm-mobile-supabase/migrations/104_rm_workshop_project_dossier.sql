begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_dossier_settings (
 singleton boolean primary key default true check(singleton),
 enforced boolean not null default false
);
insert into rm_private.workshop_dossier_settings(singleton) values(true);
alter table rm_private.workshop_dossier_settings enable row level security;
revoke all on rm_private.workshop_dossier_settings from public,anon,authenticated,service_role;

create function rm_private.project_dossier_write_v1(p_operation text)
returns boolean language sql immutable set search_path='' as $$
 select p_operation in('add_project_comment','edit_project_comment','manage_project_documents','set_project_photo_selection',
  'reserve_project_attachment','finalize_project_attachment','reserve_project_attachment_version','finalize_project_attachment_version');
$$;

alter table rm_private.root_creation_permits drop constraint root_creation_permits_operation_check;
alter table rm_private.root_creation_permits add constraint root_creation_permits_operation_check
 check(operation in('save_project','save_project_with_equipment','save_project_equipment','delete_project','save_catalog','delete_catalog')
  or rm_private.project_dossier_write_v1(operation));

do $write$
declare
 kind text:=pg_get_functiondef('rm_private.web_root_edit_kind_v1(text,jsonb)'::regprocedure);
 mutation text:=pg_get_functiondef('rm_private.web_mutate_root_creation_v1(uuid,text,jsonb)'::regprocedure);
 kind_marker constant text:='  when p_operation in(''save_project'',''save_project_equipment'',''delete_project'') then ''project''';
 fallback constant text:='case when rm_private.web_root_edit_kind_v1(p_operation,p_payload) is not null then not edits_enforced';
 project_id constant text:='when p_operation=''save_project_equipment'' then ''projeto_id''';
begin
 if array_length(string_to_array(kind,kind_marker),1) is distinct from 2
  or array_length(string_to_array(mutation,fallback),1) is distinct from 2
  or array_length(string_to_array(mutation,project_id),1) is distinct from 2 then
  raise exception 'Unexpected project dossier mutation contract';
 end if;
 execute replace(kind,kind_marker,'  when rm_private.project_dossier_write_v1(p_operation) then ''project'''||chr(10)||kind_marker);
 mutation:=replace(mutation,fallback,$fallback$case when rm_private.project_dossier_write_v1(p_operation) then
   coalesce((select not enforced from rm_private.workshop_dossier_settings where singleton for share),false)
   when rm_private.web_root_edit_kind_v1(p_operation,p_payload) is not null then not edits_enforced$fallback$);
 execute replace(mutation,project_id,'when p_operation=''save_project_equipment'' or rm_private.project_dossier_write_v1(p_operation) then ''projeto_id''');
end
$write$;

-- Reuse pagination, filters and evidence rules. Apply cell ownership before
-- counts and facets, so a linked cell awaiting classification stays private.
do $scoped$
declare
 comments text:=pg_get_functiondef('public.rm_web_project_comments_v1(uuid,jsonb)'::regprocedure);
 audit text:=pg_get_functiondef('public.rm_web_project_audit_v1(uuid,text,integer,text[])'::regprocedure);
 events text:=pg_get_functiondef('rm_private.project_audit_events_v1(uuid,text,text[])'::regprocedure);
 cell_marker constant text:=' where c.projeto_id=p_project_id';
 events_call constant text:='rm_private.project_audit_events_v1(p_project_id,p_kind,p_topics)';
 events_end constant text:='from events where jsonb_array_length(changes)>0';
begin
 if array_length(string_to_array(comments,cell_marker),1) is distinct from 2
  or array_length(string_to_array(audit,events_call),1) is distinct from 3
  or array_length(string_to_array(events,events_end),1) is distinct from 2 then
  raise exception 'Unexpected project dossier search contract';
 end if;
 comments:=replace(comments,'FUNCTION public.rm_web_project_comments_v1(p_project_id ',
  'FUNCTION rm_private.workshop_project_comments_v1(p_office uuid, p_project_id ');
 execute replace(comments,cell_marker,cell_marker||
  ' and (c.celula_id is null or rm_private.workshop_cell_owned_v1(c.celula_id,p_office))');
 events:=replace(events,'FUNCTION rm_private.project_audit_events_v1(p_project_id ',
  'FUNCTION rm_private.workshop_project_audit_events_v1(p_office uuid, p_project_id ');
 execute replace(events,events_end,events_end||
  ' and (celula_id is null or rm_private.workshop_cell_owned_v1(celula_id,p_office))');
 audit:=replace(audit,'FUNCTION public.rm_web_project_audit_v1(p_project_id ',
  'FUNCTION rm_private.workshop_project_audit_v1(p_office uuid, p_project_id ');
 execute replace(audit,events_call,'rm_private.workshop_project_audit_events_v1(p_office,p_project_id,p_kind,p_topics)');
end
$scoped$;

create function rm_private.workshop_project_dossier_read_v1(p_resource text,p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare project uuid; ident uuid; page integer; keys text[]; required text[];
begin
 required:=case p_resource
  when 'project_comments' then array['p_filters','p_project_id']
  when 'project_documents' then array['p_filters','p_project_id']
  when 'project_comment' then array['p_comment_id','p_history_page','p_project_id']
  when 'project_attachment' then array['p_attachment_id','p_history_page','p_project_id']
  when 'project_audit' then array['p_kind','p_page','p_project_id','p_topics']
  when 'project_equipment' then array['p_project_id']
  when 'project_route' then array['p_project_id'] end;
 if required is null or jsonb_typeof(p_args) is distinct from 'object' then
  raise exception 'Consulta de projeto inválida.' using errcode='22023';
 end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_args) k;
 if keys is distinct from required or jsonb_typeof(p_args->'p_project_id') is distinct from 'string' then
  raise exception 'Identificação de projeto inválida.' using errcode='22023';
 end if;
 project:=(p_args->>'p_project_id')::uuid;
 if not rm_private.workshop_project_owned_v1(project,p_office) then return null;end if;
 case p_resource
  when 'project_comments' then return rm_private.workshop_project_comments_v1(p_office,project,p_args->'p_filters');
  when 'project_documents' then return public.rm_web_project_documents_v1(project,p_args->'p_filters');
  when 'project_comment' then
   ident:=(p_args->>'p_comment_id')::uuid;page:=(p_args->>'p_history_page')::integer;
   if not exists(select 1 from public.rm_comentarios c where c.id=ident and c.projeto_id=project
    and (c.celula_id is null or rm_private.workshop_cell_owned_v1(c.celula_id,p_office))) then return null;end if;
   return public.rm_web_project_comment_snapshot_v1(project,ident,page);
  when 'project_attachment' then return public.rm_web_project_attachment_snapshot_v1(
   project,(p_args->>'p_attachment_id')::uuid,(p_args->>'p_history_page')::integer);
  when 'project_audit' then return rm_private.workshop_project_audit_v1(p_office,project,p_args->>'p_kind',
   (p_args->>'p_page')::integer,array(select jsonb_array_elements_text(p_args->'p_topics')));
  when 'project_equipment' then return public.rm_web_project_equipment_snapshot_v1(project);
  when 'project_route' then return public.rm_web_project_route_snapshot_v1(project);
 end case;
end
$$;

create function rm_private.workshop_dossier_private_path_v1(p_file text,p_office uuid)
returns text language plpgsql stable set search_path='' as $$
declare
 prefix constant text:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/';
 path text; attachment uuid;
begin
 if not starts_with(p_file,prefix||'web-dossier/') then return null;end if;
 path:=substr(p_file,length(prefix)+1);
 select u.finalized_doc_id into attachment from rm_private.project_attachment_uploads u
 where u.object_path=path and rm_private.workshop_project_owned_v1(u.projeto_id,p_office);
 if not found or (rm_private.project_attachment_publication_v1(attachment)->>'has_file') is distinct from 'true'
  then return null;end if;
 return path;
end
$$;

revoke all on function rm_private.project_dossier_write_v1(text),
 rm_private.workshop_project_comments_v1(uuid,uuid,jsonb),
 rm_private.workshop_project_audit_events_v1(uuid,uuid,text,text[]),
 rm_private.workshop_project_audit_v1(uuid,uuid,text,integer,text[]),
 rm_private.workshop_project_dossier_read_v1(text,jsonb,uuid),rm_private.workshop_dossier_private_path_v1(text,uuid)
 from public,anon,authenticated,service_role;

do $read$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 links text:=pg_get_functiondef('rm_private.workshop_project_link_v1(text,jsonb,uuid)'::regprocedure);
 media text:=pg_get_functiondef('public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[])'::regprocedure);
 allowed_resources text:=substring(issuer from 'p_resource not in[(][^)]*[)]');
 resources constant text[]:=array['project_comments','project_documents','project_comment','project_attachment','project_audit','project_equipment','project_route'];
 fallback constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 link_marker constant text:=' return result||rm_private.workshop_archive_link_v1';
 link_variable constant text:=' record_id uuid;';
 media_marker constant text:='select distinct u url from unnest(p_urls) u';
 items text; dispatch text; check_definition text;
begin
 select pg_get_constraintdef(oid) into strict check_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 if right(allowed_resources,length('''project_delete_context'')')) is distinct from '''project_delete_context'')'
  or array_length(string_to_array(issuer,allowed_resources),1) is distinct from 2
  or array_length(string_to_array(reader,fallback),1) is distinct from 2
  or array_length(string_to_array(links,link_marker),1) is distinct from 2
  or array_length(string_to_array(links,link_variable),1) is distinct from 2
  or array_length(string_to_array(media,media_marker),1) is distinct from 2 then
  raise exception 'Unexpected project dossier read contract';
 end if;
 select string_agg(quote_literal(r),','), string_agg(format(
  '  when %L then rm_private.workshop_project_dossier_read_v1(p_resource,p_args,permit.workshop_id)',r),chr(10))
  into items,dispatch from unnest(resources) r;
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(check_definition from 8 for char_length(check_definition)-8)||') or resource in('||items||'))';
 execute replace(issuer,allowed_resources,left(allowed_resources,-1)||','||items||')');
 execute replace(reader,fallback,dispatch||chr(10)||fallback);
 links:=replace(links,link_variable,link_variable||chr(10)||' private_path text;');
 execute replace(links,link_marker,$link$ if p_resource='document_link' and starts_with(result->>'file',
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/') then
  private_path:=rm_private.workshop_dossier_private_path_v1(result->>'file',p_office);
  return case when private_path is not null then result||jsonb_build_object('web_dossier_path',private_path) end;
 end if;
$link$||link_marker);
 execute replace(media,media_marker,media_marker||$media$
  where not starts_with(u,'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/')
   or rm_private.workshop_dossier_private_path_v1(u,office_id) is not null$media$);
end
$read$;

create function rm_private.activate_workshop_project_dossier_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 if not exists(select 1 from rm_private.root_creation_settings where singleton and edits_enforced)
  or not exists(select 1 from rm_private.sso_settings where singleton and require_sso) then
  raise exception 'Ative o controle de oficina e o SSO antes do dossiê.' using errcode='PT409';
 end if;
 update rm_private.workshop_dossier_settings set enforced=true where singleton and not enforced;
 revoke execute on function public.rm_web_project_comments_v1(uuid,jsonb),public.rm_web_project_documents_v1(uuid,jsonb),
  public.rm_web_project_comment_snapshot_v1(uuid,uuid,integer),public.rm_web_project_attachment_snapshot_v1(uuid,uuid,integer),
  public.rm_web_project_audit_v1(uuid,text,integer,text[]),public.rm_web_project_equipment_snapshot_v1(uuid),
  public.rm_web_project_route_snapshot_v1(uuid),rm_private.project_comment_revision_context_v1(uuid,uuid,integer),
  rm_private.project_attachment_version_context_v1(uuid,uuid,integer),rm_private.project_route_state_v1(uuid) from authenticated;
 alter policy rm_web_dossier_published_read on storage.objects using (
  bucket_id is distinct from 'rm-documentos' or coalesce(name not like 'web-dossier/%',true));
 notify pgrst,'reload schema';
end
$$;
revoke all on function rm_private.activate_workshop_project_dossier_v1() from public,anon,authenticated,service_role;

commit;

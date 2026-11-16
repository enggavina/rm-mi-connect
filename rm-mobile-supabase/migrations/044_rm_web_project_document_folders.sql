-- Project-local directory metadata. Existing documents, URLs and immutable files
-- remain unchanged; absence of a location means the project's root directory.
begin;

create table public.rm_project_document_folders (
 id uuid primary key,
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 parent_id uuid,
 nome text not null check(nome=btrim(nome) and length(nome) between 1 and 200 and nome not in('.','..') and nome !~ '[[:cntrl:]/\\]'),
 created_by uuid not null references public.rm_users(id) on delete restrict,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(projeto_id,id),
 foreign key(projeto_id,parent_id) references public.rm_project_document_folders(projeto_id,id) on delete cascade,
 check(parent_id is distinct from id)
);
create unique index rm_document_folders_sibling_name_v1 on public.rm_project_document_folders(projeto_id,parent_id,lower(nome)) nulls not distinct;
alter table public.rm_docs add constraint rm_docs_project_identity_v1 unique(projeto_id,id);
alter table public.rm_documentos add constraint rm_documents_project_identity_v1 unique(projeto_id,id);
create table public.rm_project_document_locations (
 id uuid primary key default gen_random_uuid(),
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 folder_id uuid not null,
 anexo_id uuid unique,
 documento_id uuid unique,
 updated_by uuid not null references public.rm_users(id) on delete restrict,
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(projeto_id,folder_id) references public.rm_project_document_folders(projeto_id,id) on delete restrict,
 foreign key(projeto_id,anexo_id) references public.rm_docs(projeto_id,id) on delete cascade,
 foreign key(projeto_id,documento_id) references public.rm_documentos(projeto_id,id) on delete cascade,
 check(num_nonnulls(anexo_id,documento_id)=1)
);
create index rm_document_locations_directory_v1 on public.rm_project_document_locations(projeto_id,folder_id);
alter table rm_private.project_attachment_uploads add column folder_id uuid;
alter table rm_private.project_attachment_uploads add constraint project_attachment_upload_folder_v1
 foreign key(projeto_id,folder_id) references public.rm_project_document_folders(projeto_id,id) on delete restrict;
-- Directory metadata is not part of immutable file publication. Keep the exact
-- old proof projection so already-reserved replacement contexts remain valid.
do $$ declare d text; begin
 d:=pg_get_functiondef('rm_private.project_attachment_publication_v1(uuid)'::regprocedure);
 if strpos(d,'then to_jsonb(u) else null')=0 then raise exception 'Unexpected immutable attachment proof'; end if;
 execute replace(d,'then to_jsonb(u) else null','then to_jsonb(u)-''folder_id'' else null');
end $$;

alter table public.rm_project_document_folders enable row level security;
alter table public.rm_project_document_locations enable row level security;
revoke all on public.rm_project_document_folders,public.rm_project_document_locations from public,anon,authenticated,service_role;
grant select on public.rm_project_document_folders,public.rm_project_document_locations to authenticated;
create policy rm_document_folders_read_v1 on public.rm_project_document_folders for select to authenticated
 using(rm_private.can_read_project_dossier_v1() and exists(select 1 from public.rm_projetos p where p.id=projeto_id));
create policy rm_document_locations_read_v1 on public.rm_project_document_locations for select to authenticated
 using(rm_private.can_read_project_dossier_v1() and exists(select 1 from public.rm_projetos p where p.id=projeto_id));

create function rm_private.guard_document_folder_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.projeto_id::text,11));
 if tg_op='UPDATE' and (new.id is distinct from old.id or new.projeto_id is distinct from old.projeto_id) then
  raise exception 'A identidade da pasta não pode ser alterada.' using errcode='22023'; end if;
 if new.parent_id is not null and exists(
  with recursive ancestors as(
   select id,parent_id,array[id] seen from public.rm_project_document_folders where id=new.parent_id and projeto_id=new.projeto_id
   union all select p.id,p.parent_id,a.seen||p.id from public.rm_project_document_folders p join ancestors a on p.id=a.parent_id
    where p.projeto_id=new.projeto_id and not p.id=any(a.seen)) select 1 from ancestors where id=new.id
 ) then raise exception 'Uma pasta não pode ser movida para dentro de si mesma.' using errcode='22023'; end if;
 if tg_op='UPDATE' then new.updated_at:=clock_timestamp(); end if;
 return new;
end $$;
revoke all on function rm_private.guard_document_folder_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_document_folder_v1 before insert or update on public.rm_project_document_folders
 for each row execute function rm_private.guard_document_folder_v1();

-- Extend the same ownership closure and preflight token used by project deletion.
alter function rm_private.project_delete_scope_v1(uuid) rename to project_delete_scope_before_folders_v1;
create function rm_private.project_delete_scope_v1(p_project uuid)
returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 select * from rm_private.project_delete_scope_before_folders_v1(p_project)
 union all select 'public','rm_project_document_locations',array(select id from public.rm_project_document_locations where projeto_id=p_project)
 union all select 'public','rm_project_document_folders',array(select id from public.rm_project_document_folders where projeto_id=p_project);
$$;
revoke all on function rm_private.project_delete_scope_v1(uuid),rm_private.project_delete_scope_before_folders_v1(uuid) from public,anon,authenticated,service_role;
do $$ declare d text; target regprocedure; needle text:='foreach label in array array[''rm_private.project_attachment_versions'''; begin
 select p.oid::regprocedure into target from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='rm_private' and p.proname='web_mutate_before_route_config_v1';
 d:=pg_get_functiondef(target);
 if strpos(d,needle)=0 then raise exception 'Unexpected project deletion leaf order'; end if;
 d:=replace(d,needle,'foreach label in array array[''public.rm_project_document_locations'',''rm_private.project_attachment_versions''');
 d:=replace(d,'''rm_private.project_attachment_uploads'',''rm_private.project_comment_revisions''','''rm_private.project_attachment_uploads'',''public.rm_project_document_folders'',''rm_private.project_comment_revisions''');
 execute d;
 -- Rebind the context's SQL call to the newly installed scope wrapper.
 execute pg_get_functiondef('rm_private.project_delete_context_v1(uuid)'::regprocedure);
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_document_folders_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
<<document_folder_mutation>>
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype; project public.rm_projetos%rowtype;
 folder public.rm_project_document_folders%rowtype; location public.rm_project_document_locations%rowtype;
 result jsonb; pid uuid; fid uuid; parent uuid; did uuid; source text; action text; expected timestamptz; destination uuid;
 has_destination boolean; allowed text[]; record jsonb; previous jsonb; upload_id uuid;
begin
 if p_operation is null or p_operation not in('manage_project_documents','reserve_project_attachment','reserve_project_attachment_version','finalize_project_attachment','finalize_project_attachment_version') then
  return rm_private.web_mutate_before_document_folders_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 pid:=(p_payload->>'projeto_id')::uuid;
 if pid is null then raise exception 'Projeto inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,11));
 if p_operation<>'manage_project_documents' then
  has_destination:=p_payload?'folder_id';
  if has_destination and (p_operation<>'reserve_project_attachment' or jsonb_typeof(p_payload->'folder_id') not in('null','string')) then
   raise exception 'Destino de documento inválido.' using errcode='22023'; end if;
  if has_destination then destination:=(p_payload->>'folder_id')::uuid; end if;
  if p_operation='reserve_project_attachment_version' then
   select folder_id into destination from public.rm_project_document_locations where projeto_id=pid and anexo_id=(p_payload->>'source_attachment_id')::uuid;
  end if;
  if destination is not null and not exists(select 1 from public.rm_project_document_folders where id=destination and projeto_id=pid) then
   raise exception 'A pasta não pertence a este projeto.' using errcode='22023'; end if;
  upload_id:=(p_payload->>'upload_id')::uuid;
  if p_operation like 'finalize_%' then
   select folder_id into destination from rm_private.project_attachment_uploads where id=upload_id and projeto_id=pid;
  end if;
  result:=rm_private.web_mutate_before_document_folders_v1(p_client_submission_id,p_operation,p_payload-'folder_id');
  if p_operation like 'reserve_%' then
   update rm_private.project_attachment_uploads set folder_id=destination where id=upload_id and projeto_id=pid and finalized_doc_id is null;
  elsif destination is not null then
   insert into public.rm_project_document_locations(projeto_id,folder_id,anexo_id,updated_by) values(pid,destination,upload_id,actor.id);
  end if;
  if p_operation like 'finalize_%' then
   update rm_private.project_attachment_uploads set folder_id=null where id=upload_id and projeto_id=pid;
  end if;
  if has_destination then
   result:=jsonb_set(result,'{record,folder_id}',coalesce(to_jsonb(destination),'null'));
   update rm_private.web_mutation_receipts set payload=p_payload,result=document_folder_mutation.result where client_submission_id=p_client_submission_id;
  end if;
  return result;
 end if;
 action:=p_payload->>'action';
 allowed:=array['projeto_id','expected_project_updated_at','action'];
 case action
  when 'create_folder' then allowed:=allowed||array['parent_id','nome'];
  when 'rename_folder' then allowed:=allowed||array['folder_id','expected_folder_updated_at','nome'];
  when 'move_folder' then allowed:=allowed||array['folder_id','expected_folder_updated_at','parent_id','confirm_change'];
  when 'delete_folder' then allowed:=allowed||array['folder_id','expected_folder_updated_at','confirm_change'];
  when 'move_document' then allowed:=allowed||array['source','document_id','folder_id','expected_folder_id','confirm_change'];
  else raise exception 'Operação documental inválida.' using errcode='22023';
 end case;
 if not p_payload?&allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed)) then raise exception 'Campos documentais inválidos.' using errcode='22023'; end if;
 if jsonb_typeof(p_payload->'expected_project_updated_at') is distinct from 'string' or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then raise exception 'Versão de projeto inválida.' using errcode='22023'; end if;
 expected:=(p_payload->>'expected_project_updated_at')::timestamptz;
 select * into project from public.rm_projetos where id=pid for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 if not isfinite(expected) or project.updated_at<>expected then raise exception 'O projeto mudou. Recarregue a página.' using errcode='PT409'; end if;
 if project.data_real_de_entrega is not null or coalesce(project.status_pcp in('cancelado','finalizando_para_faturar'),false) then raise exception 'Projeto encerrado: somente consulta.' using errcode='22023'; end if;
 if action in('move_folder','delete_folder','move_document') and p_payload->'confirm_change' is distinct from 'true'::jsonb then raise exception 'Confirme a alteração.' using errcode='22023'; end if;
 if p_payload?'parent_id' then
  if jsonb_typeof(p_payload->'parent_id') not in('null','string') then raise exception 'Pasta de destino inválida.' using errcode='22023'; end if;
  parent:=(p_payload->>'parent_id')::uuid;
  if parent is not null and not exists(select 1 from public.rm_project_document_folders where id=parent and projeto_id=pid) then raise exception 'A pasta não pertence a este projeto.' using errcode='22023'; end if;
 end if;
 if action in('create_folder','rename_folder') and (jsonb_typeof(p_payload->'nome') is distinct from 'string' or length(btrim(p_payload->>'nome')) not between 1 and 200 or btrim(p_payload->>'nome') in('.','..') or p_payload->>'nome' ~ '[[:cntrl:]/\\]') then raise exception 'Informe um nome de pasta válido.' using errcode='22023'; end if;
 if action='create_folder' then
  insert into public.rm_project_document_folders(id,projeto_id,parent_id,nome,created_by) values(p_client_submission_id,pid,parent,btrim(p_payload->>'nome'),actor.id) returning * into folder;
  fid:=folder.id; record:=to_jsonb(folder);
 elsif action='move_document' then
  if jsonb_typeof(p_payload->'folder_id') not in('null','string') or jsonb_typeof(p_payload->'expected_folder_id') not in('null','string') or jsonb_typeof(p_payload->'source') is distinct from 'string' or p_payload->>'source' not in('docs','documents') then raise exception 'Documento ou destino inválido.' using errcode='22023'; end if;
  source:=p_payload->>'source';did:=(p_payload->>'document_id')::uuid;fid:=did;destination:=(p_payload->>'folder_id')::uuid;
  if not (case source when 'docs' then exists(select 1 from public.rm_docs where id=did and projeto_id=pid) else exists(select 1 from public.rm_documentos where id=did and projeto_id=pid) end) then raise exception 'Documento inexistente neste projeto.' using errcode='P0002'; end if;
  if destination is not null and not exists(select 1 from public.rm_project_document_folders where id=destination and projeto_id=pid) then raise exception 'A pasta não pertence a este projeto.' using errcode='22023'; end if;
  select * into location from public.rm_project_document_locations where projeto_id=pid and case source when 'docs' then anexo_id=did else documento_id=did end for update;
  if location.folder_id is distinct from (p_payload->>'expected_folder_id')::uuid then raise exception 'O documento foi movido. Recarregue a página.' using errcode='PT409'; end if;
  previous:=coalesce(to_jsonb(location),'null');
  delete from public.rm_project_document_locations where id=location.id;
  if destination is not null then
   insert into public.rm_project_document_locations(projeto_id,folder_id,anexo_id,documento_id,updated_by)
    values(pid,destination,case when source='docs' then did end,case when source='documents' then did end,actor.id) returning * into location;
  end if;
  record:=jsonb_build_object('document_id',did,'source',source,'folder_id',destination,'before',previous);
 else
  fid:=(p_payload->>'folder_id')::uuid;
  select * into folder from public.rm_project_document_folders where id=fid and projeto_id=pid for update;
  if not found then raise exception 'Pasta inexistente neste projeto.' using errcode='P0002'; end if;
  if jsonb_typeof(p_payload->'expected_folder_updated_at') is distinct from 'string' or folder.updated_at is distinct from (p_payload->>'expected_folder_updated_at')::timestamptz then raise exception 'A pasta mudou. Recarregue a página.' using errcode='PT409'; end if;
  previous:=to_jsonb(folder);
  if action='rename_folder' then update public.rm_project_document_folders set nome=btrim(p_payload->>'nome') where id=fid returning * into folder;
  elsif action='move_folder' then update public.rm_project_document_folders set parent_id=parent where id=fid returning * into folder;
  else
   if exists(select 1 from public.rm_project_document_folders where parent_id=fid)
    or exists(select 1 from public.rm_project_document_locations where folder_id=fid)
    or exists(select 1 from rm_private.project_attachment_uploads where folder_id=fid) then
    raise exception 'A pasta contém subpastas, documentos ou envios pendentes. Mova o conteúdo antes de excluir.' using errcode='22023'; end if;
   delete from public.rm_project_document_folders where id=fid;
  end if;
  record:=to_jsonb(folder)||jsonb_build_object('before',previous);
 end if;
 result:=jsonb_build_object('operation',p_operation,'id',fid,'projeto_id',pid,'updated_at',clock_timestamp(),'record',record||jsonb_build_object('action',action),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result) values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
 if p_operation in('manage_project_documents','reserve_project_attachment','reserve_project_attachment_version','finalize_project_attachment','finalize_project_attachment_version') then
  raise exception 'Identificador, versão ou diretório inválidos.' using errcode='22023';
 end if;
 raise;
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_document_folders_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Preserve the established global dossier reader when folder_id is omitted.
-- An explicit null selects the root. Existing rows require no migration/backfill.
do $$ declare d text; begin
 d:=pg_get_functiondef('public.rm_web_project_documents_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'declare filters jsonb; result jsonb;','declare filters jsonb; result jsonb; folder_id uuid; directory_mode boolean; navigation jsonb;');
 d:=replace(d,'filters:=rm_private.project_dossier_filters_v1(p_filters,true);',
  $patch$directory_mode:=coalesce(p_filters?'folder_id',false);
 if directory_mode and jsonb_typeof(p_filters->'folder_id') not in('null','string') then raise exception 'Diretório inválido.' using errcode='22023'; end if;
 folder_id:=(p_filters->>'folder_id')::uuid;
 filters:=rm_private.project_dossier_filters_v1(p_filters-'folder_id',true);
 if directory_mode then filters:=filters||jsonb_build_object('folder_id',folder_id); end if;$patch$);
 d:=replace(d,'with project_rows as materialized (',
  $patch$if directory_mode and folder_id is not null and not exists(select 1 from public.rm_project_document_folders where id=folder_id and projeto_id=p_project_id) then raise exception 'Pasta inexistente neste projeto.' using errcode='22023'; end if;
 if directory_mode and (select count(*) from public.rm_project_document_folders where projeto_id=p_project_id)>10000 then raise exception 'Há pastas demais para esta consulta.' using errcode='54000'; end if;
 with project_rows as materialized ($patch$);
 d:=replace(d,'select r.* from project_rows r where',
  $patch$select r.* from project_rows r where
   (not directory_mode or (select l.folder_id from public.rm_project_document_locations l where l.projeto_id=p_project_id and case r.source when 'docs' then l.anexo_id=r.id else l.documento_id=r.id end) is not distinct from folder_id) and$patch$);
 d:=replace(d,' return result;',
  $patch$if directory_mode then
  with recursive ancestors as(
   select id,parent_id,nome,updated_at,0 depth,array[id] seen from public.rm_project_document_folders where projeto_id=p_project_id and id=folder_id
   union all select p.id,p.parent_id,p.nome,p.updated_at,a.depth+1,a.seen||p.id from public.rm_project_document_folders p join ancestors a on p.id=a.parent_id
    where p.projeto_id=p_project_id and not p.id=any(a.seen))
  select jsonb_build_object('current_folder_id',folder_id,
   'breadcrumbs',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'parent_id',a.parent_id,'nome',a.nome,'updated_at',a.updated_at) order by a.depth desc) from ancestors a),'[]'::jsonb),
   'folders',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'parent_id',f.parent_id,'nome',f.nome,'updated_at',f.updated_at) order by lower(f.nome),f.id) from public.rm_project_document_folders f where f.projeto_id=p_project_id),'[]'::jsonb)) into navigation;
  result:=result||jsonb_build_object('navigation',navigation);
 end if;
 return result;$patch$);
 if strpos(d,'directory_mode:=')=0 or strpos(d,'''navigation'',navigation')=0 then raise exception 'Unexpected dossier reader'; end if;
 execute d;
end $$;

do $$ declare d text; c text; begin
 select pg_get_constraintdef(oid) into c from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check';
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check check (('||substring(c from 8 for length(c)-8)||') or operation=''manage_project_documents'')';
 d:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(d,'when ''delete_project'' then ''em.projects.manage''')=0 then raise exception 'Unexpected document management permit map'; end if;
 execute replace(d,'when ''delete_project'' then ''em.projects.manage''','when ''manage_project_documents'' then ''em.projects.manage'' when ''delete_project'' then ''em.projects.manage''');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;

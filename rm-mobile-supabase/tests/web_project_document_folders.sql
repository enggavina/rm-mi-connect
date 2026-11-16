-- ISOLATED TEST DATABASE ONLY. No production fixture or business data is used.
\set ON_ERROR_STOP on
begin;
create function pg_temp.df_check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.df_id(n int) returns uuid language sql immutable as $$ select ('df440000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.df_payload(action text,extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
 select jsonb_build_object('projeto_id',p.id,'expected_project_updated_at',p.updated_at,'action',action)||extra from public.rm_projetos p where id=pg_temp.df_id(11); $$;
create function pg_temp.df_call(p jsonb,rid uuid default gen_random_uuid()) returns jsonb language plpgsql as $$
declare r jsonb; begin set local role authenticated;r:=public.rm_web_mutate_v1(rid,'manage_project_documents',p);reset role;return r;
 exception when others then reset role;raise;end $$;
create function pg_temp.df_reject(p jsonb,wanted text) returns void language plpgsql as $$ declare actual text;begin
 begin perform pg_temp.df_call(p);exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return;end if;raise exception 'FAIL: wanted %, got %: %',wanted,actual,sqlerrm;end;raise exception 'FAIL: operation unexpectedly succeeded';end $$;
insert into auth.users(id) values(pg_temp.df_id(1)),(pg_temp.df_id(2)),(pg_temp.df_id(3));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.df_id(4),pg_temp.df_id(1),'Folder administrator','administrador','ativo'),(pg_temp.df_id(5),pg_temp.df_id(2),'Folder auditor','auditor','ativo'),(pg_temp.df_id(6),pg_temp.df_id(3),'Folder client','cliente','ativo');
insert into public.rm_projetos(id,nome) values(pg_temp.df_id(11),'Directory project'),(pg_temp.df_id(12),'Other project');
insert into public.rm_docs(id,projeto_id,nome,arquivo_url) values(pg_temp.df_id(21),pg_temp.df_id(11),'Legacy attachment','https://example.test/legacy.pdf'),(pg_temp.df_id(22),pg_temp.df_id(12),'Unrelated attachment','https://example.test/other.pdf');
insert into public.rm_documentos(id,projeto_id,nome,arquivo_url) values(pg_temp.df_id(23),pg_temp.df_id(11),'Generated report','https://example.test/report.pdf');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub',pg_temp.df_id(1)::text,true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
select pg_temp.df_check(not has_table_privilege('authenticated','public.rm_project_document_folders','insert') and not has_table_privilege('authenticated','public.rm_project_document_locations','update'),'clients cannot bypass document mutation authorization');
select pg_temp.df_check(not has_table_privilege('anon','public.rm_project_document_folders','select') and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute'),'no public metadata or private writer grants');

-- Persistent root/subdirectories, stable receipts and explicit confirmation.
select pg_temp.df_call(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',null,'nome','Engenharia')),pg_temp.df_id(31));
select pg_temp.df_call(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',pg_temp.df_id(31),'nome','Relatórios')),pg_temp.df_id(32));
do $$ declare r jsonb;p jsonb;begin
 p:=pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',null,'nome','Engenharia'));
 r:=pg_temp.df_call(p,pg_temp.df_id(31));perform pg_temp.df_check((r->>'idempotent_replay')::boolean,'create retry uses same persistent folder');
 perform pg_temp.df_reject(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',null,'nome','engenharia')),'23505');
 perform pg_temp.df_reject(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',null,'nome','../escape')),'22023');
 insert into public.rm_project_document_folders(id,projeto_id,nome,created_by) values(pg_temp.df_id(33),pg_temp.df_id(12),'Other directory',pg_temp.df_id(4));
 perform pg_temp.df_reject(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',pg_temp.df_id(33),'nome','Cross project')),'22023');
 p:=pg_temp.df_payload('move_folder',jsonb_build_object('folder_id',pg_temp.df_id(31),'expected_folder_updated_at',(select updated_at from public.rm_project_document_folders where id=pg_temp.df_id(31)),'parent_id',pg_temp.df_id(32),'confirm_change',true));
 perform pg_temp.df_reject(p,'22023');
 perform pg_temp.df_reject(p||jsonb_build_object('parent_id',pg_temp.df_id(31)),'22023');
 perform pg_temp.df_reject(p||jsonb_build_object('confirm_change',false),'22023');
end $$;

-- Database constraints independently enforce project ownership.
do $$ begin
 begin insert into public.rm_project_document_locations(projeto_id,folder_id,anexo_id,updated_by) values(pg_temp.df_id(11),pg_temp.df_id(33),pg_temp.df_id(21),pg_temp.df_id(4));raise exception 'FAIL: cross project folder accepted';exception when foreign_key_violation then null;end;
 begin insert into public.rm_project_document_locations(projeto_id,folder_id,anexo_id,updated_by) values(pg_temp.df_id(11),pg_temp.df_id(31),pg_temp.df_id(22),pg_temp.df_id(4));raise exception 'FAIL: cross project document accepted';exception when foreign_key_violation then null;end;
 begin update public.rm_project_document_folders set parent_id=pg_temp.df_id(32) where id=pg_temp.df_id(31);raise exception 'FAIL: cycle accepted';exception when invalid_parameter_value then null;end;
end $$;
select pg_temp.df_call(pg_temp.df_payload('move_document',jsonb_build_object('source','docs','document_id',pg_temp.df_id(21),'folder_id',pg_temp.df_id(32),'expected_folder_id',null,'confirm_change',true)));
select pg_temp.df_call(pg_temp.df_payload('move_document',jsonb_build_object('source','documents','document_id',pg_temp.df_id(23),'folder_id',pg_temp.df_id(32),'expected_folder_id',null,'confirm_change',true)));
do $$ declare r jsonb;p jsonb;begin
 set local role authenticated;
 r:=public.rm_web_project_documents_v1(pg_temp.df_id(11));perform pg_temp.df_check(r->>'total'='2' and not r?'navigation','old global dossier reader retains contract');
 begin perform public.rm_web_project_documents_v1(pg_temp.df_id(11),null);raise exception 'FAIL: legacy null filter was silently reinterpreted';exception when invalid_parameter_value then null;end;
 r:=public.rm_web_project_documents_v1(pg_temp.df_id(11),'{"folder_id":null}');perform pg_temp.df_check(r->>'total'='0' and r->'navigation'->>'current_folder_id' is null,'root excludes documents moved into folders');
 r:=public.rm_web_project_documents_v1(pg_temp.df_id(11),jsonb_build_object('folder_id',pg_temp.df_id(32)));perform pg_temp.df_check(r->>'total'='2' and jsonb_array_length(r->'navigation'->'breadcrumbs')=2,'directory lists both existing document sources and full ancestry');
 reset role;
 p:=pg_temp.df_payload('delete_folder',jsonb_build_object('folder_id',pg_temp.df_id(32),'expected_folder_updated_at',(select updated_at from public.rm_project_document_folders where id=pg_temp.df_id(32)),'confirm_change',true));perform pg_temp.df_reject(p,'22023');
 p:=pg_temp.df_payload('move_document',jsonb_build_object('source','docs','document_id',pg_temp.df_id(21),'folder_id',null,'expected_folder_id',null,'confirm_change',true));perform pg_temp.df_reject(p,'PT409');
 p:=pg_temp.df_payload('rename_folder',jsonb_build_object('folder_id',pg_temp.df_id(32),'expected_folder_updated_at','2000-01-01T00:00:00Z','nome','Stale'));perform pg_temp.df_reject(p,'PT409');
 p:=pg_temp.df_payload('rename_folder',jsonb_build_object('folder_id',pg_temp.df_id(32),'expected_folder_updated_at',(select updated_at from public.rm_project_document_folders where id=pg_temp.df_id(32)),'nome','Inspeções'));perform pg_temp.df_call(p);
end $$;

-- Existing two-phase upload publishes into the frozen folder atomically.
do $$ declare p jsonb;r jsonb;begin
 select jsonb_build_object('projeto_id',id,'expected_project_updated_at',updated_at,'upload_id',pg_temp.df_id(41),'nome','New attachment','descricao',null,'filename','new.pdf','mime_type','application/pdf','byte_size',12,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo','folder_id',pg_temp.df_id(32)) into p from public.rm_projetos where id=pg_temp.df_id(11);
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(42),'reserve_project_attachment',p);reset role;
 perform pg_temp.df_check(r->'record'->>'folder_id'=pg_temp.df_id(32)::text,'reservation acknowledges exact folder');
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(42),'reserve_project_attachment',p);reset role;
 perform pg_temp.df_check((r->>'idempotent_replay')::boolean,'folder-aware reservation retry matches original payload');
 perform pg_temp.df_check(not exists(select 1 from public.rm_docs where id=pg_temp.df_id(41)),'reservation does not publish partial document');
 insert into storage.objects(bucket_id,name,metadata,user_metadata) select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256) from rm_private.project_attachment_uploads where id=pg_temp.df_id(41);
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(41),'finalize_project_attachment',jsonb_build_object('projeto_id',pg_temp.df_id(11),'upload_id',pg_temp.df_id(41)));reset role;
 perform pg_temp.df_check((select folder_id=pg_temp.df_id(32) from public.rm_project_document_locations where anexo_id=pg_temp.df_id(41)),'publication and folder metadata committed in same transaction');
 perform pg_temp.df_check((select folder_id is null from rm_private.project_attachment_uploads where id=pg_temp.df_id(41)),'completed upload no longer pins folder');
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(41),'finalize_project_attachment',jsonb_build_object('projeto_id',pg_temp.df_id(11),'upload_id',pg_temp.df_id(41)));reset role;
 perform pg_temp.df_check((r->>'idempotent_replay')::boolean and (select count(*)=1 from public.rm_project_document_locations where anexo_id=pg_temp.df_id(41)),'publication retry does not duplicate locations');
 begin update public.rm_docs set nome='Change original content' where id=pg_temp.df_id(41);raise exception 'FAIL: immutable document edited';exception when invalid_parameter_value then null;end;
end $$;

-- Replacement versions inherit the source directory without changing immutable
-- publication proof or the post-publication context returned by existing API033.
do $$ declare s jsonb;p jsonb;r jsonb;begin
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.df_id(11),pg_temp.df_id(41),1);
 perform pg_temp.df_check((s->>'can_replace')::boolean,'folder metadata does not invalidate private publication');
 p:=jsonb_build_object('projeto_id',pg_temp.df_id(11),'upload_id',pg_temp.df_id(43),'source_attachment_id',pg_temp.df_id(41),
  'expected_project_updated_at',s->'project'->>'updated_at','expected_attachment_updated_at',s->'attachment'->>'updated_at','expected_context_version',s->>'context_version',
  'nome','Replacement PDF','descricao',null,'filename','replacement.pdf','mime_type','application/pdf','byte_size',13,'sha256',repeat('b',64),'data_vencimento',null,'status','No prazo','motivo','Confirmed technical replacement','confirm_change',true);
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(44),'reserve_project_attachment_version',p);reset role;
 perform pg_temp.df_check((select folder_id=pg_temp.df_id(32) from rm_private.project_attachment_uploads where id=pg_temp.df_id(43)),'replacement destination inherits source directory');
 insert into storage.objects(bucket_id,name,metadata,user_metadata) select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256) from rm_private.project_attachment_uploads where id=pg_temp.df_id(43);
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(43),'finalize_project_attachment_version',jsonb_build_object('projeto_id',pg_temp.df_id(11),'upload_id',pg_temp.df_id(43)));reset role;
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.df_id(11),pg_temp.df_id(43),1);
 perform pg_temp.df_check(r->'record'->>'context_version'=s->>'context_version','clearing pending folder does not stale the returned file context');
 perform pg_temp.df_check((select folder_id=pg_temp.df_id(32) from public.rm_project_document_locations where anexo_id=pg_temp.df_id(43)),'replacement published into same directory');
end $$;

-- Moving file metadata does not rewrite immutable documents or legacy URLs.
select pg_temp.df_call(pg_temp.df_payload('move_document',jsonb_build_object('source','docs','document_id',pg_temp.df_id(41),'folder_id',null,'expected_folder_id',pg_temp.df_id(32),'confirm_change',true)));
select pg_temp.df_check((select nome='New attachment' and arquivo_url like '%web-dossier/%' from public.rm_docs where id=pg_temp.df_id(41)),'moving only affects directory metadata');
select pg_temp.df_check((select arquivo_url='https://example.test/legacy.pdf' from public.rm_docs where id=pg_temp.df_id(21)),'legacy source URL preserved');
select pg_temp.df_call(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',null,'nome','Empty')),pg_temp.df_id(34));
select pg_temp.df_call(pg_temp.df_payload('delete_folder',jsonb_build_object('folder_id',pg_temp.df_id(34),'expected_folder_updated_at',(select updated_at from public.rm_project_document_folders where id=pg_temp.df_id(34)),'confirm_change',true)));
select pg_temp.df_check(not exists(select 1 from public.rm_project_document_folders where id=pg_temp.df_id(34)),'confirmed empty directory removed');
select pg_temp.df_call(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',null,'nome','Pending upload')),pg_temp.df_id(35));
do $$ declare p jsonb;r jsonb;begin
 select jsonb_build_object('projeto_id',id,'expected_project_updated_at',updated_at,'upload_id',pg_temp.df_id(45),'nome','Pending attachment','descricao',null,'filename','pending.pdf','mime_type','application/pdf','byte_size',12,'sha256',repeat('c',64),'data_vencimento',null,'status','No prazo','folder_id',pg_temp.df_id(35)) into p from public.rm_projetos where id=pg_temp.df_id(11);
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(46),'reserve_project_attachment',p);reset role;
 perform pg_temp.df_reject(pg_temp.df_payload('delete_folder',jsonb_build_object('folder_id',pg_temp.df_id(35),'expected_folder_updated_at',(select updated_at from public.rm_project_document_folders where id=pg_temp.df_id(35)),'confirm_change',true)),'22023');
 perform pg_temp.df_check(not exists(select 1 from public.rm_docs where id=pg_temp.df_id(45)),'pending upload pins destination without a partial public document');
end $$;

-- No depth-one restriction, including navigation after a fresh query.
do $$ declare n int;last_id uuid:=pg_temp.df_id(32);r jsonb;begin
 for n in 101..140 loop perform pg_temp.df_call(pg_temp.df_payload('create_folder',jsonb_build_object('parent_id',last_id,'nome','Nested '||n)),pg_temp.df_id(n));last_id:=pg_temp.df_id(n);end loop;
 set local role authenticated;r:=public.rm_web_project_documents_v1(pg_temp.df_id(11),jsonb_build_object('folder_id',last_id));reset role;
 perform pg_temp.df_check(jsonb_array_length(r->'navigation'->'breadcrumbs')=42,'forty-two persistent levels navigable');
end $$;

-- Read-only users cannot mutate; client identities cannot list internal folders.
select set_config('request.jwt.claim.sub',pg_temp.df_id(2)::text,true);
select pg_temp.df_reject(pg_temp.df_payload('create_folder','{"parent_id":null,"nome":"Denied"}'),'42501');
set local role authenticated;
select pg_temp.df_check((select count(*)>0 from public.rm_project_document_folders where projeto_id=pg_temp.df_id(11)),'auditor can read directory metadata');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.df_id(3)::text,true);
set local role authenticated;
select pg_temp.df_check((select count(*)=0 from public.rm_project_document_folders),'client cannot read internal directory metadata');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.df_id(1)::text,true);

-- The existing corporate permit channel authorizes the new operation with its
-- existing project-management capability; an unused permit cannot be bypassed.
insert into auth.sessions(id,user_id) values(pg_temp.df_id(7),pg_temp.df_id(1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(pg_temp.df_id(8),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.df_id(9),pg_temp.df_id(4),pg_temp.df_id(1),true,pg_temp.df_id(4),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('f',64),pg_temp.df_id(8),pg_temp.df_id(7),'opaque-folder-fixture',clock_timestamp()+interval '45 minutes');
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1','session_id',pg_temp.df_id(7))::text,true);
update rm_private.sso_settings set require_sso=true;
do $$ declare p jsonb:=pg_temp.df_payload('create_folder','{"parent_id":null,"nome":"SSO authorized"}');r jsonb;begin
 begin perform pg_temp.df_call(p,pg_temp.df_id(61));raise exception 'FAIL: SSO permit bypassed';exception when insufficient_privilege then null;end;
 perform public.rm_sso_action_permit_v1(repeat('f',64),pg_temp.df_id(61),'manage_project_documents',p,'em.projects.manage');
 r:=pg_temp.df_call(p,pg_temp.df_id(61));perform pg_temp.df_check(r->>'id'=pg_temp.df_id(61)::text,'same corporate permit flow accepts document folder management');
end $$;
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);

-- All directory metadata is included in existing deletion context and leaf order.
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1','session_id',pg_temp.df_id(7))::text,true);
do $$ declare c jsonb;r jsonb;p jsonb;begin
 c:=public.rm_web_project_delete_snapshot_v1(pg_temp.df_id(11));perform pg_temp.df_check((c->>'can_delete')::boolean,'owned folder graph does not block legitimate project deletion');
 p:=jsonb_build_object('id',pg_temp.df_id(11),'expected_updated_at',c->'project'->>'updated_at','expected_context_version',c->>'context_version','confirm_delete',true,'justificativa','Delete local folder test fixture');
 perform public.rm_sso_action_permit_v1(repeat('f',64),pg_temp.df_id(51),'delete_project',p,'em.projects.manage');
 set local role authenticated;r:=public.rm_web_mutate_v1(pg_temp.df_id(51),'delete_project',p);reset role;
end $$;
select pg_temp.df_check(not exists(select 1 from public.rm_project_document_folders where projeto_id=pg_temp.df_id(11)) and not exists(select 1 from public.rm_project_document_locations where projeto_id=pg_temp.df_id(11)),'project deletion removes exclusively owned folder metadata');
select pg_temp.df_check(exists(select 1 from public.rm_project_document_folders where id=pg_temp.df_id(33)) and exists(select 1 from public.rm_docs where id=pg_temp.df_id(22)),'other project directory and files preserved');
rollback;

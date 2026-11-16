-- Disposable database only: warm 043 publication and pending replacement, apply
-- the exact next migration, and finish/replay the original protocols unchanged.
\set ON_ERROR_STOP on
\if :{?rm_migration_044_path}
\else
\echo 'Isolated runner must supply migration044 path.'
\quit 3
\endif
select set_config('rm.test.migration_044_path',:'rm_migration_044_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create temporary table document_folder_upgrade_proof(key text primary key,value jsonb);
insert into auth.users(id) values('dd440000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('dd440000-0000-4000-8000-000000000002','dd440000-0000-4000-8000-000000000001','Folder upgrade administrator','administrador','ativo');
insert into public.rm_projetos(id,nome) values('dd440000-0000-4000-8000-000000000003','Folder upgrade project');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','dd440000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
do $$ declare p jsonb;s jsonb;begin
 p:=jsonb_build_object('projeto_id','dd440000-0000-4000-8000-000000000003','upload_id','dd440000-0000-4000-8000-000000000004',
  'expected_project_updated_at',(select updated_at from public.rm_projetos where id='dd440000-0000-4000-8000-000000000003'),
  'nome','Original before044','descricao',null,'filename','original.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo');
 insert into document_folder_upgrade_proof values('reserve',p);
 set local role authenticated;perform public.rm_web_mutate_v1('dd440000-0000-4000-8000-000000000005','reserve_project_attachment',p);reset role;
 insert into storage.objects(bucket_id,name,metadata,user_metadata) select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256) from rm_private.project_attachment_uploads where id='dd440000-0000-4000-8000-000000000004';
 p:='{"projeto_id":"dd440000-0000-4000-8000-000000000003","upload_id":"dd440000-0000-4000-8000-000000000004"}';
 set local role authenticated;perform public.rm_web_mutate_v1('dd440000-0000-4000-8000-000000000004','finalize_project_attachment',p);reset role;
 insert into document_folder_upgrade_proof values('finalize',p);
 s:=public.rm_web_project_attachment_snapshot_v1('dd440000-0000-4000-8000-000000000003','dd440000-0000-4000-8000-000000000004',1);
 insert into document_folder_upgrade_proof values('context',s);
 p:=jsonb_build_object('projeto_id','dd440000-0000-4000-8000-000000000003','upload_id','dd440000-0000-4000-8000-000000000006','source_attachment_id','dd440000-0000-4000-8000-000000000004',
  'expected_project_updated_at',s->'project'->>'updated_at','expected_attachment_updated_at',s->'attachment'->>'updated_at','expected_context_version',s->>'context_version',
  'nome','Replacement reserved before044','descricao',null,'filename','replacement.pdf','mime_type','application/pdf','byte_size',6,'sha256',repeat('b',64),'data_vencimento',null,'status','No prazo','motivo','Existing pending replacement','confirm_change',true);
 insert into document_folder_upgrade_proof values('replacement',p);
 set local role authenticated;perform public.rm_web_mutate_v1('dd440000-0000-4000-8000-000000000007','reserve_project_attachment_version',p);reset role;
 insert into document_folder_upgrade_proof values('uploads',(select jsonb_agg(to_jsonb(u) order by id) from rm_private.project_attachment_uploads u));
 insert into document_folder_upgrade_proof values('documents',(select jsonb_agg(to_jsonb(d) order by id) from public.rm_docs d));
 insert into document_folder_upgrade_proof values('receipts',(select jsonb_agg(to_jsonb(receipt_row) order by client_submission_id) from rm_private.web_mutation_receipts receipt_row));
 insert into document_folder_upgrade_proof values('storage',(select jsonb_agg(to_jsonb(o) order by id) from storage.objects o));
end $$;
-- Compile and exercise the exact source inside this disposable transaction.
-- Rollback removes every warm fixture and restores the prior SSO settings;
-- then install the original source once more against the clean baseline.
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_044_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'FAIL: unexpected044 source wrappers';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end $$;
do $$ declare s jsonb;r jsonb;p jsonb;begin
 if (select jsonb_agg(to_jsonb(u)-'folder_id' order by id) from rm_private.project_attachment_uploads u) is distinct from (select value from document_folder_upgrade_proof where key='uploads')
  or (select jsonb_agg(to_jsonb(d) order by id) from public.rm_docs d) is distinct from (select value from document_folder_upgrade_proof where key='documents')
  or (select jsonb_agg(to_jsonb(receipt_row) order by client_submission_id) from rm_private.web_mutation_receipts receipt_row) is distinct from (select value from document_folder_upgrade_proof where key='receipts')
  or (select jsonb_agg(to_jsonb(o) order by id) from storage.objects o) is distinct from (select value from document_folder_upgrade_proof where key='storage') then raise exception 'FAIL: pre-existing upload/document/receipt/Storage row changed';end if;
 s:=public.rm_web_project_attachment_snapshot_v1('dd440000-0000-4000-8000-000000000003','dd440000-0000-4000-8000-000000000004',1);
 if s is distinct from (select value from document_folder_upgrade_proof where key='context') then raise exception 'FAIL: old immutable file context changed across044';end if;
 select value into p from document_folder_upgrade_proof where key='reserve';set local role authenticated;r:=public.rm_web_mutate_v1('dd440000-0000-4000-8000-000000000005','reserve_project_attachment',p);reset role;
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: old reservation replay failed';end if;
 select value into p from document_folder_upgrade_proof where key='replacement';set local role authenticated;r:=public.rm_web_mutate_v1('dd440000-0000-4000-8000-000000000007','reserve_project_attachment_version',p);reset role;
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: old replacement reservation replay failed';end if;
 insert into storage.objects(bucket_id,name,metadata,user_metadata) select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256) from rm_private.project_attachment_uploads where id='dd440000-0000-4000-8000-000000000006';
 set local role authenticated;r:=public.rm_web_mutate_v1('dd440000-0000-4000-8000-000000000006','finalize_project_attachment_version','{"projeto_id":"dd440000-0000-4000-8000-000000000003","upload_id":"dd440000-0000-4000-8000-000000000006"}');reset role;
 if r->'record'->>'revision'<>'2' or not exists(select 1 from public.rm_docs where id='dd440000-0000-4000-8000-000000000006') then raise exception 'FAIL: pending replacement no longer finalizes after044';end if;
end $$;
rollback;
\i :rm_migration_044_path
select 'PASS: 044 preserves old publications/context/receipts/Storage and finalizes a replacement reserved before migration' result;

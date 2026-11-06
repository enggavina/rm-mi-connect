-- Disposable database only: cross-project ownership, rollback and private protocol cleanup.
\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create function pg_temp.di_id(h text,n int) returns uuid language sql immutable as $$select(h||'d390000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.di_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
insert into auth.users(id) values(pg_temp.di_id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.di_id('2',1),pg_temp.di_id('1',1),'Delete integrity administrator','administrador','ativo');
insert into public.rm_projetos(id,nome) select pg_temp.di_id('5',n),'Delete integrity '||n from generate_series(1,6)n;
insert into public.rm_celulas(id,nome) values(pg_temp.di_id('4',1),'Shared catalog cell');
insert into public.rm_forms(id,titulo) values(pg_temp.di_id('7',1),'Shared form');
insert into public.rm_questoes(id,form_id,enunciado,tipo) values(pg_temp.di_id('a',1),pg_temp.di_id('7',1),'Shared question','texto_curto');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id) select pg_temp.di_id('6',n),pg_temp.di_id('5',n),pg_temp.di_id('4',1) from generate_series(1,2)n;
insert into public.rm_registros_formulario(id,projeto_id,form_id,celula_id) select pg_temp.di_id('8',n),pg_temp.di_id('5',n),pg_temp.di_id('7',1),pg_temp.di_id('4',1) from generate_series(1,2)n;
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub',pg_temp.di_id('1',1)::text,true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
create function pg_temp.di_payload(n int) returns jsonb language sql as $$with s as(select public.rm_web_project_delete_snapshot_v1(pg_temp.di_id('5',n)) v)select jsonb_build_object('id',v->'project'->>'id','expected_updated_at',v->'project'->>'updated_at','expected_context_version',v->>'context_version','confirm_delete',true,'justificativa','Explicit disposable integrity check') from s$$;
create function pg_temp.di_delete(n int,rid uuid default gen_random_uuid()) returns jsonb language plpgsql as $$declare p jsonb;r jsonb;begin
 p:=pg_temp.di_payload(n);set local role authenticated;r:=public.rm_web_mutate_v1(rid,'delete_project',p);reset role;return r;
exception when others then reset role;raise;end$$;
create function pg_temp.di_blocked(n int) returns void language plpgsql as $$declare state text;rid uuid:=gen_random_uuid();begin
 perform pg_temp.di_check(not(public.rm_web_project_delete_snapshot_v1(pg_temp.di_id('5',n))->>'can_delete')::boolean,'shared preflight rejects');
 begin perform pg_temp.di_delete(n,rid);raise exception 'FAIL: shared delete accepted';exception when sqlstate 'PT424' then null;end;
 perform pg_temp.di_check(exists(select 1 from public.rm_projetos where id=pg_temp.di_id('5',n)) and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=rid),'shared delete is atomic');
end$$;
-- Both ownership directions matter: an owned child pointing outside its graph
-- is just as shared as a foreign child pointing into the graph.
-- Seed a legacy inconsistency that predates the allocation validator. Only the
-- disposable fixture disables that one writer trigger; all FKs remain active.
alter table public.rm_fotos disable trigger rm_guard_allocation_child;
insert into public.rm_fotos(id,projeto_id,celula_projeto_id,titulo) values(pg_temp.di_id('9',1),pg_temp.di_id('5',1),pg_temp.di_id('6',2),'Own photo foreign allocation');
select pg_temp.di_blocked(1);
delete from public.rm_fotos where id=pg_temp.di_id('9',1);
insert into public.rm_fotos(id,projeto_id,celula_projeto_id,titulo) values(pg_temp.di_id('9',2),pg_temp.di_id('5',2),pg_temp.di_id('6',1),'Foreign photo owned allocation');
select pg_temp.di_blocked(1);
delete from public.rm_fotos where id=pg_temp.di_id('9',2);
alter table public.rm_fotos enable trigger rm_guard_allocation_child;
insert into public.rm_documentos(id,projeto_id,registro_formulario_id,nome) values(pg_temp.di_id('b',1),pg_temp.di_id('5',1),pg_temp.di_id('8',2),'Foreign record document');
select pg_temp.di_blocked(1);
delete from public.rm_documentos where id=pg_temp.di_id('b',1);
insert into public.rm_respostas_temp(id,projeto_id,registro_formulario_id,form_id,questao_id,operador_user_id,resposta) values(pg_temp.di_id('c',1),pg_temp.di_id('5',1),pg_temp.di_id('8',2),pg_temp.di_id('7',1),pg_temp.di_id('a',1),pg_temp.di_id('2',1),'Shared context');
select pg_temp.di_blocked(1);
delete from public.rm_respostas_temp where id=pg_temp.di_id('c',1);
insert into public.rm_docs(id,projeto_id,nome) values(pg_temp.di_id('b',2),pg_temp.di_id('5',1),'Owned source');
insert into public.rm_documentos(id,projeto_id,documentos_origem_ids,nome) values(pg_temp.di_id('b',3),pg_temp.di_id('5',2),array[pg_temp.di_id('b',2)],'Foreign dossier source');
select pg_temp.di_blocked(1);
delete from public.rm_documentos where id=pg_temp.di_id('b',3);
insert into public.rm_equipamentos(id,projeto_id) values(pg_temp.di_id('e',1),pg_temp.di_id('5',1));
insert into public.rm_propostas_controle(id,projeto_id,equipamento_id) values(pg_temp.di_id('d',1),pg_temp.di_id('5',2),pg_temp.di_id('e',1));
select pg_temp.di_blocked(1);
delete from public.rm_propostas_controle where id=pg_temp.di_id('d',1);
-- Private journals are real dependencies, not a second full dossier left behind.
insert into public.rm_comentarios(id,projeto_id,cadastrado_por_id,evento,sync_source) values(pg_temp.di_id('c',2),pg_temp.di_id('5',1),pg_temp.di_id('2',1),'Current comment','supabase');
insert into rm_private.project_comment_revisions(projeto_id,comentario_id,revision,actor_id,auth_user_id,client_submission_id,motivo,before_record,after_record)
 values(pg_temp.di_id('5',1),pg_temp.di_id('c',2),1,pg_temp.di_id('2',1),pg_temp.di_id('1',1),pg_temp.di_id('f',1),'Correction','{"evento":"Original secret body"}','{"evento":"Current comment"}');
insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
 values(pg_temp.di_id('f',2),pg_temp.di_id('1',1),pg_temp.di_id('2',1),'save_project',jsonb_build_object('id',pg_temp.di_id('5',1),'changes',jsonb_build_object('nome','Historical payload')),jsonb_build_object('id',pg_temp.di_id('5',1),'projeto_id',pg_temp.di_id('5',1)),jsonb_build_object('private_body','Original full project'));
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('delete-integrity-mobile','sha256'),pg_temp.di_id('1',1),pg_temp.di_id('2',1),pg_temp.di_id('2',1),clock_timestamp()+interval '1 day');
insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result)
 values(pg_temp.di_id('f',3),pg_temp.di_id('1',1),pg_temp.di_id('2',1),'rm_submit_recebimento_v1','{"p_nome_projeto":"Offline old receiving without project ID"}',jsonb_build_object('projeto_id',pg_temp.di_id('5',1)));
-- An injected failure at the very last parent DELETE must roll back the entire
-- graph, all receipt reductions and the newly reserved deletion protocol.
create function pg_temp.di_late_failure() returns trigger language plpgsql as $$begin raise exception 'Injected final parent failure' using errcode='P0039';end$$;
create trigger di_fail_last before delete on public.rm_projetos for each row when(old.id='5d390000-0000-4000-8000-000000000001') execute function pg_temp.di_late_failure();
create temporary table di_before(name text,hash text);
do $$declare t record;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and(ns.nspname='rm_private' or(ns.nspname='public' and c.relname like 'rm\_%' escape '\')) loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into h;insert into di_before values(format('%I.%I',t.nspname,t.relname),h);
 end loop;
 begin perform pg_temp.di_delete(1,pg_temp.di_id('f',4));raise exception 'FAIL: injected failure not reached';exception when sqlstate 'P0039' then null;end;
 for t in select * from di_before loop execute format('select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into h;if h<>t.hash then raise exception 'FAIL: partial delete survived: %',t.name;end if;end loop;
end$$;
drop trigger di_fail_last on public.rm_projetos;
select pg_temp.di_delete(1,pg_temp.di_id('f',4));
select pg_temp.di_check(not exists(select 1 from rm_private.project_comment_revisions where projeto_id=pg_temp.di_id('5',1)),'private full history removed');
select pg_temp.di_check((select before_record is null and payload?'original_sha256' and result->'resource_deleted'='true' from rm_private.web_mutation_receipts where client_submission_id=pg_temp.di_id('f',2)),'old web receipt minimized');
select pg_temp.di_check((select params?'original_sha256' and result->'resource_deleted'='true' from rm_private.mobile_mutation_receipts where client_submission_id=pg_temp.di_id('f',3)),'old receiving receipt minimized');
do $$begin
 set local role authenticated;
 begin perform public.rm_web_mutate_v1(pg_temp.di_id('f',2),'save_project',jsonb_build_object('id',pg_temp.di_id('5',1),'changes',jsonb_build_object('nome','Historical payload')));raise exception 'FAIL: old web replay recreated dossier';exception when sqlstate 'PT410' then null;end;
 begin perform public.rm_mobile_mutate_v1(pg_temp.di_id('f',3),'rm_submit_recebimento_v1','{"p_nome_projeto":"Offline old receiving without project ID"}','delete-integrity-mobile');raise exception 'FAIL: old receiving replay recreated project';exception when sqlstate 'PT410' then null;end;
 reset role;
 begin insert into public.rm_documentos(projeto_id,documentos_origem_ids,nome) values(pg_temp.di_id('5',2),array[pg_temp.di_id('b',2)],'Deleted source');raise exception 'FAIL: deleted document referenced';exception when sqlstate 'PT410' then null;end;
end$$;
select pg_temp.di_check(exists(select 1 from public.rm_registros_formulario where id=pg_temp.di_id('8',2)) and exists(select 1 from public.rm_celulas where id=pg_temp.di_id('4',1)) and exists(select 1 from public.rm_questoes where id=pg_temp.di_id('a',1)),'foreign project and global templates remain intact');
-- Shared protocols survive while another project still needs their evidence.
-- Once their last project is deleted, the original full snapshots are removed.
insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
 values(pg_temp.di_id('f',8),pg_temp.di_id('1',1),pg_temp.di_id('2',1),'save_cell_queue','{"celula_id":"4d390000-0000-4000-8000-000000000001","changes":[]}',jsonb_build_object('id',pg_temp.di_id('4',1),'projeto_id',null),jsonb_build_object('items',jsonb_build_array(jsonb_build_object('projeto_id',pg_temp.di_id('5',3)),jsonb_build_object('projeto_id',pg_temp.di_id('5',5)))));
-- Proven files may also be referenced by a surviving project. Their blobs must
-- remain, while unshared files are retried with an exact lease after failure.
insert into public.rm_docs(id,projeto_id,nome,arquivo_url)
 select pg_temp.di_id('b',n),pg_temp.di_id('5',n),'Private owned attachment','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/'||pg_temp.di_id('5',n)||'/'||pg_temp.di_id('b',n)||'.pdf' from unnest(array[3,5])n;
insert into public.rm_docs(id,projeto_id,nome,arquivo_url) values(pg_temp.di_id('b',4),pg_temp.di_id('5',4),'Shared signed reference','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/sign/rm-documentos/web-dossier/'||pg_temp.di_id('5',3)||'/'||pg_temp.di_id('b',3)||'.pdf?token=local-fixture');
insert into rm_private.project_attachment_uploads(id,auth_user_id,actor_id,projeto_id,nome,filename,mime_type,byte_size,sha256,object_path,status_documento,finalized_doc_id,completed_at)
 select pg_temp.di_id('b',n),pg_temp.di_id('1',1),pg_temp.di_id('2',1),pg_temp.di_id('5',n),'Owned PDF','file.pdf','application/pdf',12,repeat('a',64),'web-dossier/'||pg_temp.di_id('5',n)||'/'||pg_temp.di_id('b',n)||'.pdf','No prazo',pg_temp.di_id('b',n),clock_timestamp() from unnest(array[3,5])n;
select pg_temp.di_delete(3,pg_temp.di_id('f',9));
select pg_temp.di_check((select before_record is not null and not(payload?'original_sha256') from rm_private.web_mutation_receipts where client_submission_id=pg_temp.di_id('f',8)),'mixed receipt retained for surviving project');
select pg_temp.di_delete(5,pg_temp.di_id('f',10));
select pg_temp.di_check((select before_record is null and payload?'original_sha256' from rm_private.web_mutation_receipts where client_submission_id=pg_temp.di_id('f',8)),'mixed receipt reduced after its last project deleted');
do $$begin
 begin insert into public.rm_docs(projeto_id,nome,arquivo_url) values(pg_temp.di_id('5',4),'Forbidden new reference','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/'||pg_temp.di_id('5',5)||'/'||pg_temp.di_id('b',5)||'.pdf');raise exception 'FAIL: GC path reused';exception when sqlstate 'PT410' then null;end;
 begin insert into public.rm_docs(projeto_id,nome,arquivo_url) values(pg_temp.di_id('5',4),'Forbidden signed reference','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/sign/rm-documentos/web-dossier/'||pg_temp.di_id('5',5)||'/'||pg_temp.di_id('b',5)||'.pdf?token=local-fixture');raise exception 'FAIL: GC signed path reused';exception when sqlstate 'PT410' then null;end;
 begin insert into public.rm_docs(projeto_id,nome,arquivo_url) values(pg_temp.di_id('5',4),'Forbidden public reference','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-documentos/'||replace('web-dossier/'||pg_temp.di_id('5',5)||'/'||pg_temp.di_id('b',5)||'.pdf','/','%2F'));raise exception 'FAIL: GC encoded public path reused';exception when sqlstate 'PT410' then null;end;
 begin insert into public.rm_docs(projeto_id,nome,arquivo_url) values(pg_temp.di_id('5',4),'Forbidden encoded name','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/sign/rm-documentos/'||replace(replace('web-dossier/'||pg_temp.di_id('5',5)||'/'||pg_temp.di_id('b',5)||'.pdf','-','%2D'),'.','%2e')||'?token=local-fixture');raise exception 'FAIL: GC encoded UUID path reused';exception when sqlstate 'PT410' then null;end;
end$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select pg_temp.di_check(public.rm_project_delete_files_claim_v1(1,pg_temp.di_id('f',9))='[]'::jsonb,'surviving cross-reference prevents physical removal');
do $$declare jobs jsonb;j jsonb;begin
 jobs:=public.rm_project_delete_files_claim_v1(1,pg_temp.di_id('f',10));perform pg_temp.di_check(jsonb_array_length(jobs)=1,'exclusive file claimed');j:=jobs->0;
 perform pg_temp.di_check(public.rm_project_delete_files_finish_v1((j->>'id')::uuid,(j->>'lease_token')::uuid,false),'failure acknowledgement retained');
 perform pg_temp.di_check(not public.rm_project_delete_files_finish_v1((j->>'id')::uuid,(j->>'lease_token')::uuid,true),'old failure lease cannot complete');
 perform pg_temp.di_check(public.rm_project_delete_files_claim_v1(1,pg_temp.di_id('f',10))='[]'::jsonb,'retry obeys backoff');
end$$;
reset role;
select pg_temp.di_check((select status='preserved_shared' from rm_private.project_delete_files where delete_submission_id=pg_temp.di_id('f',9)),'shared file retained without Storage claim');
update rm_private.project_delete_files set next_attempt_at=clock_timestamp()-interval '1 second' where delete_submission_id=pg_temp.di_id('f',10);
set local role service_role;
do $$declare j jsonb;begin
 j:=public.rm_project_delete_files_claim_v1(1,pg_temp.di_id('f',10))->0;perform pg_temp.di_check(j is not null,'due durable retry claimed');
 perform pg_temp.di_check(public.rm_project_delete_files_finish_v1((j->>'id')::uuid,(j->>'lease_token')::uuid,true),'durable retry completed');
end$$;
reset role;
select 'PASS: 039 bidirectional/soft/commercial ownership blockers, complete private-history cleanup, all-table atomic rollback and old web/mobile replay safety' result;
rollback;

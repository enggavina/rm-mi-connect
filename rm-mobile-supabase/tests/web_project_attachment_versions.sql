-- TEST DATABASE ONLY: immutable attachment versions, private uploads and exact retries.
\set ON_ERROR_STOP on
begin;
create function pg_temp.av_key(h text,n int) returns uuid language sql immutable as $$ select(h||'a360000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.av_check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.av_actor(n int,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.av_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.av_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.av.actor',n::text,true); end $$;
create function pg_temp.av_call(op text,p jsonb,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns jsonb language plpgsql as $$ declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.av.actor'),64,'a6'),rid,op,p,cap);
 set local role authenticated;r:=public.rm_web_mutate_v1(rid,op,p);reset role;return r;
 exception when others then reset role;raise;end $$;
create function pg_temp.av_reject(op text,p jsonb,wanted text,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns void language plpgsql as $$ declare actual text;begin
 begin perform pg_temp.av_call(op,p,rid,cap);exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return;end if;raise exception 'FAIL: wanted %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: attachment operation unexpectedly succeeded';end $$;
create function pg_temp.av_base(n int,project_no int default 1) returns uuid language plpgsql as $$ declare p jsonb;cid uuid:=pg_temp.av_key('c',n);begin
 p:=jsonb_build_object('projeto_id',pg_temp.av_key('5',project_no),'upload_id',cid,'expected_project_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.av_key('5',project_no)),
 'nome','Original attachment '||n,'descricao','Preserved source','filename','original.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo');
 perform pg_temp.av_call('reserve_project_attachment',p,pg_temp.av_key('f',n));
 insert into storage.objects(bucket_id,name,metadata,user_metadata)values('rm-documentos','web-dossier/'||pg_temp.av_key('5',project_no)::text||'/'||cid::text||'.pdf','{"size":5,"mimetype":"application/pdf"}',jsonb_build_object('sha256',repeat('a',64)));
 perform pg_temp.av_call('finalize_project_attachment',jsonb_build_object('projeto_id',pg_temp.av_key('5',project_no),'upload_id',cid),cid);return cid;end $$;
create function pg_temp.av_payload(source_id uuid,n int) returns jsonb language plpgsql as $$ declare s jsonb;pid uuid;begin
 select projeto_id into pid from public.rm_docs where id=source_id;s:=public.rm_web_project_attachment_snapshot_v1(pid,source_id,1);
 return jsonb_build_object('projeto_id',pid,'upload_id',pg_temp.av_key('d',n),'source_attachment_id',source_id,'expected_project_updated_at',s->'project'->>'updated_at',
 'expected_attachment_updated_at',s->'attachment'->>'updated_at','expected_context_version',s->>'context_version','nome','Replacement '||n,'descricao','Version metadata','filename','replacement.pdf',
 'mime_type','application/pdf','byte_size',5,'sha256',repeat('b',64),'data_vencimento',null,'status','Vencido','motivo','Verified replacement '||n,'confirm_change',true);end $$;
create function pg_temp.av_put(n int,hash text default repeat('b',64)) returns void language plpgsql as $$ declare u rm_private.project_attachment_uploads%rowtype;begin
 select * into u from rm_private.project_attachment_uploads where id=pg_temp.av_key('d',n);
 insert into storage.objects(bucket_id,name,metadata,user_metadata)values('rm-documentos',u.object_path,jsonb_build_object('size',u.byte_size,'mimetype',u.mime_type),jsonb_build_object('sha256',hash));end $$;
create function pg_temp.av_final(n int) returns jsonb language plpgsql as $$ declare pid uuid;begin
 select projeto_id into pid from rm_private.project_attachment_versions where id=pg_temp.av_key('d',n);
 return pg_temp.av_call('finalize_project_attachment_version',jsonb_build_object('projeto_id',pid,'upload_id',pg_temp.av_key('d',n)),pg_temp.av_key('d',n));end $$;
do $$ declare n int;begin for n in 1..6 loop
 insert into auth.users(id)values(pg_temp.av_key('1',n));
 insert into public.rm_users(id,auth_user_id,nome,perfil,status)values(pg_temp.av_key('2',n),pg_temp.av_key('1',n),'Attachment actor '||n,
 case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=4 then 'auditor' when n=6 then 'cliente' else 'padr_o' end,case when n=5 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
 insert into auth.sessions(id,user_id)values(pg_temp.av_key('3',n),pg_temp.av_key('1',n));
 insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(pg_temp.av_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.av_key('9',n),pg_temp.av_key('2',n),pg_temp.av_key('1',n),true,pg_temp.av_key('2',1),clock_timestamp());
 if n in(1,2,3,4)then perform public.rm_sso_session_put_v1(lpad(n::text,64,'a6'),pg_temp.av_key('8',n),pg_temp.av_key('3',n),'opaque-attachment-fixture-'||n,clock_timestamp()+interval '45 minutes');end if;
 end loop;end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero)values(pg_temp.av_key('5',1),'ATTACHMENTS-33'),(pg_temp.av_key('5',2),'OTHER-33');
select pg_temp.av_actor(2);
select pg_temp.av_base(1);select pg_temp.av_base(2,2);select pg_temp.av_base(3);
insert into public.rm_docs(id,projeto_id,nome,arquivo_url,visivel_cliente)values(pg_temp.av_key('c',9),pg_temp.av_key('5',1),'Historical file','https://cdn.bubble.io/legacy.pdf',true),
 (pg_temp.av_key('c',10),pg_temp.av_key('5',1),'Unproven private-looking path','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/unproven.pdf',false);
do $$ declare s jsonb;p jsonb;r jsonb;old_doc jsonb;old_object jsonb;original_token text;new_id uuid:=pg_temp.av_key('d',1);begin
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('c',1),1);
 perform pg_temp.av_check((s->>'can_replace')::boolean and s->'series'->>'head_revision'='1' and s->'history'->>'total'='1' and s->'history'->'items'->0->>'motivo' is null,'original029 is virtual revision1 without backfill');
 perform pg_temp.av_check(s->'attachment'->>'filename'='original.pdf' and s->'attachment'->>'byte_size'='5' and not(s::text~'web-dossier|sha256|auth_user_id|object_path|before_record'),'safe business snapshot excludes storage locations and private proof');
 perform pg_temp.av_check(public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',2),pg_temp.av_key('c',1),1)is null,'cross-project attachment is absent');
 for s in select public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),x,1) from unnest(array[pg_temp.av_key('c',9),pg_temp.av_key('c',10)])x loop
  perform pg_temp.av_check(not(s->>'can_replace')::boolean and s->'series'='null'::jsonb and s->'history'->>'total'='0','unproven external/private-looking origin remains readonly without invented history');
 end loop;
 select to_jsonb(d)into old_doc from public.rm_docs d where id=pg_temp.av_key('c',1);
 select to_jsonb(o)into old_object from storage.objects o where name like '%'||pg_temp.av_key('c',1)::text||'.pdf';
 p:=pg_temp.av_payload(pg_temp.av_key('c',1),1);original_token:=p->>'expected_context_version';
 r:=pg_temp.av_call('reserve_project_attachment_version',p,pg_temp.av_key('e',1));
 perform pg_temp.av_check(r->'record'->>'revision'='2' and r->'record'->>'context_version'=original_token,'reserve freezes next revision/context');
 perform pg_temp.av_check(not exists(select 1 from public.rm_docs where id=new_id) and(select before_record=old_doc and after_record is null from rm_private.project_attachment_versions where id=new_id),'pending reserve has no published row and retains source before image');
 perform pg_temp.av_check(public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('c',1),1)->>'context_version'=original_token,'pending version does not invalidate its own source context');
 perform pg_temp.av_reject('finalize_project_attachment_version',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',new_id),'PT503',new_id);
 perform pg_temp.av_put(1,'wrong-hash');
 perform pg_temp.av_reject('finalize_project_attachment_version',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',new_id),'PT409',new_id);
 update storage.objects set user_metadata=jsonb_build_object('sha256',repeat('b',64))where name like '%'||new_id::text||'.pdf';
 -- Merely reading a file may refresh unrelated access metadata. It is not a new file.
 update storage.objects set metadata=metadata||'{"access_note":"read-only view"}'::jsonb where name like '%'||pg_temp.av_key('c',1)::text||'.pdf';
 perform pg_temp.av_check(public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('c',1),1)->>'context_version'=original_token,'incidental access metadata does not invalidate content proof');
 update storage.objects set metadata=old_object->'metadata' where name like '%'||pg_temp.av_key('c',1)::text||'.pdf';
 perform pg_temp.av_reject('finalize_project_attachment',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',new_id),'22023',new_id);
 perform pg_temp.av_check(not exists(select 1 from public.rm_docs where id=new_id) and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=new_id),'old029 finalizer cannot bypass version-kind/head guards');
 r:=pg_temp.av_final(1);
 perform pg_temp.av_check(r->>'id'=new_id::text and r->'record'->>'revision'='2' and r->'record'->>'source_attachment_id'=pg_temp.av_key('c',1)::text,'finalize publishes a new immutable row linked to original');
 perform pg_temp.av_check((select to_jsonb(d)=old_doc from public.rm_docs d where id=pg_temp.av_key('c',1)) and(select to_jsonb(o)=old_object from storage.objects o where name like '%'||pg_temp.av_key('c',1)::text||'.pdf'),'old source row/object unchanged byte-for-byte');
 perform pg_temp.av_check((select finalized_doc_id=new_id and after_record=(select to_jsonb(d)from public.rm_docs d where id=new_id)from rm_private.project_attachment_versions where id=new_id),'final journal keeps exact after image');
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),new_id,1);
 perform pg_temp.av_check(s->'series'->>'head_id'=new_id::text and s->'history'->>'total'='2' and s->'history'->'items'->0->>'revision'='2' and r->'record'->>'context_version'=s->>'context_version','published new head and exact fresh context/history');
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('c',1),1);perform pg_temp.av_check(not(s->>'can_replace')::boolean and s->'series'->>'head_id'=new_id::text,'old selected version stays consultative and identifies current head');
 r:=pg_temp.av_call('reserve_project_attachment_version',p,pg_temp.av_key('e',1));perform pg_temp.av_check((r->>'idempotent_replay')::boolean,'completed reserve retries after newer head');
 r:=pg_temp.av_final(1);perform pg_temp.av_check((r->>'idempotent_replay')::boolean,'exact final retry creates no duplicate row/revision');
 begin update public.rm_docs set nome='external rewrite'where id=new_id;raise exception 'FAIL: version metadata was mutable';exception when invalid_parameter_value then null;end;
 begin delete from public.rm_docs where id=new_id;raise exception 'FAIL: version was deletable';exception when invalid_parameter_value then null;end;
end $$;
do $$ declare p jsonb;s jsonb;r jsonb;n int;head uuid:=pg_temp.av_key('d',1);old_count bigint;begin
 select count(*)into old_count from public.rm_sync_outbox;
 for n in 2..26 loop p:=pg_temp.av_payload(head,n);perform pg_temp.av_call('reserve_project_attachment_version',p);perform pg_temp.av_put(n);perform pg_temp.av_final(n);head:=pg_temp.av_key('d',n);end loop;
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),head,1);
 perform pg_temp.av_check(s->'history'->>'total'='27' and jsonb_array_length(s->'history'->'items')=25 and s->'history'->'items'->0->>'revision'='27','history is bounded25 and descending without losing versions');
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),head,999);
 perform pg_temp.av_check(s->'history'->>'page'='2' and jsonb_array_length(s->'history'->'items')=2 and s->'history'->'items'->1->>'revision'='1','clamped second page retains original virtual version');
 perform pg_temp.av_check((select count(*)=old_count from public.rm_sync_outbox),'versioning emits no bridge/outbox work');
 -- Any current padrão manager may replace an eligible file, not only its creator.
 perform pg_temp.av_actor(3);p:=pg_temp.av_payload(head,30);perform pg_temp.av_call('reserve_project_attachment_version',p);perform pg_temp.av_put(30);perform pg_temp.av_final(30);
 perform pg_temp.av_check((select created_by=pg_temp.av_key('2',3)from public.rm_docs where id=pg_temp.av_key('d',30)),'new author belongs to the new file; original author preserved');
 perform pg_temp.av_actor(2);p:=pg_temp.av_payload(pg_temp.av_key('d',30),31);perform pg_temp.av_call('reserve_project_attachment_version',p);perform pg_temp.av_put(31);
 perform pg_temp.av_actor(1);perform pg_temp.av_reject('finalize_project_attachment_version',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',pg_temp.av_key('d',31)),'42501',pg_temp.av_key('d',31));
 perform pg_temp.av_actor(2);perform pg_temp.av_final(31);
 perform pg_temp.av_actor(4);s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('d',31),1);perform pg_temp.av_check(not(s->>'can_replace')::boolean,'auditor reads only');
 perform pg_temp.av_reject('reserve_project_attachment_version',pg_temp.av_payload(pg_temp.av_key('d',31),32),'42501');
 perform pg_temp.av_actor(6);begin perform public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('d',31),1);raise exception 'FAIL: customer read internal versions';exception when insufficient_privilege then null;end;
 perform pg_temp.av_actor(2);
 p:=pg_temp.av_payload(pg_temp.av_key('d',31),33);
 for r in select x from unnest(array[p||'{"confirm_change":false}'::jsonb,p||'{"motivo":"   "}'::jsonb,p||jsonb_build_object('motivo',E'\t\n'),p||'{"mime_type":"text/plain"}'::jsonb,
  p||'{"byte_size":0}'::jsonb,p||'{"sha256":"invalid"}'::jsonb,p||'{"filename":"../escape.pdf"}'::jsonb,p||'{"nome":""}'::jsonb,p||'{"actor_id":"forbidden"}'::jsonb])x loop
  perform pg_temp.av_reject('reserve_project_attachment_version',r,'22023');
 end loop;
 perform pg_temp.av_reject('reserve_project_attachment_version',p||jsonb_build_object('expected_context_version',repeat('0',64)),'PT409');
 perform pg_temp.av_reject('reserve_project_attachment_version',p||jsonb_build_object('projeto_id',pg_temp.av_key('5',2)),'P0002');
 perform pg_temp.av_reject('reserve_project_attachment_version',pg_temp.av_payload(pg_temp.av_key('c',1),33),'42501');
 p:=pg_temp.av_payload(pg_temp.av_key('d',31),34);perform pg_temp.av_call('reserve_project_attachment_version',p);perform pg_temp.av_put(34);
 update public.rm_projetos set eventualidades='Project context changed during upload'where id=pg_temp.av_key('5',1);
 perform pg_temp.av_reject('finalize_project_attachment_version',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',pg_temp.av_key('d',34)),'PT409',pg_temp.av_key('d',34));
 perform pg_temp.av_check((select finalized_doc_id is null from rm_private.project_attachment_versions where id=pg_temp.av_key('d',34)) and exists(select 1 from storage.objects where name like '%'||pg_temp.av_key('d',34)::text||'.pdf'),'stale context preserves pending intent and private file');
 perform pg_temp.av_reject('finalize_project_attachment',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',pg_temp.av_key('d',34)),'22023',pg_temp.av_key('d',34));
 -- MFA and current local role precede completed receipt recovery.
 insert into auth.mfa_factors(id,user_id,factor_type,status)values(gen_random_uuid(),pg_temp.av_key('1',2),'totp','verified');
 perform pg_temp.av_reject('finalize_project_attachment_version',jsonb_build_object('projeto_id',pg_temp.av_key('5',1),'upload_id',pg_temp.av_key('d',31)),'42501',pg_temp.av_key('d',31));
 perform pg_temp.av_actor(2,'aal2');r:=pg_temp.av_final(31);perform pg_temp.av_check((r->>'idempotent_replay')::boolean,'fresh MFA recovers completed receipt');
 update public.rm_projetos set data_real_de_entrega=clock_timestamp()where id=pg_temp.av_key('5',1);
 r:=pg_temp.av_final(31);perform pg_temp.av_check((r->>'idempotent_replay')::boolean,'completed receipt remains replayable after closure');
 s:=public.rm_web_project_attachment_snapshot_v1(pg_temp.av_key('5',1),pg_temp.av_key('d',31),1);perform pg_temp.av_check(not(s->>'can_replace')::boolean,'closed project remains consultative');
end $$;
select pg_temp.av_check(not has_table_privilege('authenticated','rm_private.project_attachment_versions','select')
 and not has_table_privilege('service_role','rm_private.project_attachment_versions','insert')
 and not has_function_privilege('authenticated','rm_private.project_attachment_publication_v1(uuid)','execute')
 and not has_function_privilege('anon','public.rm_web_project_attachment_snapshot_v1(uuid,uuid,integer)','execute')
 and not has_function_privilege('service_role','public.rm_web_project_attachment_snapshot_v1(uuid,uuid,integer)','execute'),'private journal/proof and public reader scopes');
rollback;
select 'PASS:033 immutable attachment versions, scoped provenance/history, exact file intent, old-finalizer kind guard, current SSO/MFA replay and retained pending uploads' as result;

-- Real concurrent transactions. All committed fixtures are inside the disposable cluster.
create extension if not exists dblink;
begin;
create schema rm_test_attachment_versions;
create function rm_test_attachment_versions.key(h text,n int)returns uuid language sql immutable as $$select(h||'a370000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;$$;
create function rm_test_attachment_versions.check(v boolean,msg text)returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
insert into auth.users(id)values(rm_test_attachment_versions.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil)values(rm_test_attachment_versions.key('2',1),rm_test_attachment_versions.key('1',1),'Attachment race actor','administrador');
insert into auth.sessions(id,user_id)values(rm_test_attachment_versions.key('3',1),rm_test_attachment_versions.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
values(rm_test_attachment_versions.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_attachment_versions.key('9',1),rm_test_attachment_versions.key('2',1),rm_test_attachment_versions.key('1',1),true,rm_test_attachment_versions.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('a7',32),rm_test_attachment_versions.key('8',1),rm_test_attachment_versions.key('3',1),'opaque-attachment-races',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub',rm_test_attachment_versions.key('1',1)::text,false);
insert into public.rm_projetos(id,numero)select rm_test_attachment_versions.key('5',n),'ATTACHMENT-RACE-33-'||n from generate_series(1,13)n;
create function rm_test_attachment_versions.run(mode text,rid uuid,p jsonb,hold_seconds real default 0)returns jsonb language plpgsql as $$
declare r jsonb;op text:=mode;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_attachment_versions.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_attachment_versions.key('3',1),'aal','aal1')::text,true);
 if mode='raw_content' or mode='raw_access' then
  update storage.objects set metadata=metadata||case when mode='raw_content' then '{"eTag":"external-new-content-generation"}'::jsonb else '{"access_note":"incidental-view"}'::jsonb end
   where bucket_id='rm-documentos' and name like '%'||(p->>'source_attachment_id')||'.pdf';r:='{}';
 elsif mode='read_published' then
  set local role authenticated;
  select jsonb_build_object('documents',(select count(*)from public.rm_docs where id=(p->>'upload_id')::uuid),
   'objects',(select count(*)from storage.objects where bucket_id='rm-documentos' and name=p->>'path'))into r;
  reset role;
 else
  if mode='reserve_with_bytes'then op:='reserve_project_attachment_version';end if;
  perform public.rm_sso_action_permit_v1(repeat('a7',32),rid,op,p,'em.projects.manage');
  set local role authenticated;r:=public.rm_web_mutate_v1(rid,op,p);reset role;
  if mode='reserve_with_bytes'then
   insert into storage.objects(bucket_id,name,metadata,user_metadata)select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)
    from rm_private.project_attachment_uploads where id=(p->>'upload_id')::uuid;
  end if;
 end if;
 perform pg_sleep(hold_seconds);return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);end$$;
create function rm_test_attachment_versions.payload(n int,uid uuid default null)returns jsonb language plpgsql as $$declare s jsonb;begin
 s:=public.rm_web_project_attachment_snapshot_v1(rm_test_attachment_versions.key('5',n),rm_test_attachment_versions.key('c',n),1);
 return jsonb_build_object('upload_id',coalesce(uid,rm_test_attachment_versions.key('d',n)),'projeto_id',rm_test_attachment_versions.key('5',n),'source_attachment_id',rm_test_attachment_versions.key('c',n),
 'expected_project_updated_at',s->'project'->>'updated_at','expected_attachment_updated_at',s->'attachment'->>'updated_at','expected_context_version',s->>'context_version',
 'nome','Concurrent replacement '||n,'descricao',null,'filename','new.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('b',64),'data_vencimento',null,'status','No prazo','motivo','Concurrent verified replacement','confirm_change',true);end$$;
do $$declare n int;p jsonb;r jsonb;begin
 for n in 1..13 loop
  p:=jsonb_build_object('upload_id',rm_test_attachment_versions.key('c',n),'projeto_id',rm_test_attachment_versions.key('5',n),'expected_project_updated_at',(select updated_at from public.rm_projetos where id=rm_test_attachment_versions.key('5',n)),
   'nome','Original race file '||n,'descricao',null,'filename','old.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo');
  r:=rm_test_attachment_versions.run('reserve_project_attachment',rm_test_attachment_versions.key('f',n),p);perform rm_test_attachment_versions.check(r->>'sqlstate'='00000','old base reserve fixture');
  insert into storage.objects(bucket_id,name,metadata,user_metadata)select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)from rm_private.project_attachment_uploads where id=rm_test_attachment_versions.key('c',n);
  r:=rm_test_attachment_versions.run('finalize_project_attachment',rm_test_attachment_versions.key('c',n),jsonb_build_object('projeto_id',rm_test_attachment_versions.key('5',n),'upload_id',rm_test_attachment_versions.key('c',n)));
  perform rm_test_attachment_versions.check(r->>'sqlstate'='00000','old base final fixture');
  if n in(1,2,4,5,6,7,11,12)then
   r:=rm_test_attachment_versions.run('reserve_with_bytes',rm_test_attachment_versions.key('e',n),rm_test_attachment_versions.payload(n));perform rm_test_attachment_versions.check(r->>'sqlstate'='00000','pending version fixture');
  end if;
 end loop;
 r:=rm_test_attachment_versions.run('reserve_with_bytes',rm_test_attachment_versions.key('e',1001),rm_test_attachment_versions.payload(1,rm_test_attachment_versions.key('d',1001)));perform rm_test_attachment_versions.check(r->>'sqlstate'='00000','competing pending version fixture');
 p:=jsonb_build_object('upload_id',rm_test_attachment_versions.key('b',9),'projeto_id',rm_test_attachment_versions.key('5',9),'expected_project_updated_at',(select updated_at from public.rm_projetos where id=rm_test_attachment_versions.key('5',9)),
 'nome','Ordinary old pending file','descricao',null,'filename','ordinary.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo');
 r:=rm_test_attachment_versions.run('reserve_project_attachment',rm_test_attachment_versions.key('f',1009),p);perform rm_test_attachment_versions.check(r->>'sqlstate'='00000','old command-kind fixture');
 insert into storage.objects(bucket_id,name,metadata,user_metadata)select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)from rm_private.project_attachment_uploads where id=rm_test_attachment_versions.key('b',9);
end$$;
commit;
do $$declare n int;first_op text;second_op text;first_p jsonb;second_p jsonb;first_id uuid;second_id uuid;s jsonb;a jsonb;b jsonb;pid_a int;pid_b int;waited int;expected text;begin
 perform dblink_connect('attachment_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('attachment_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('attachment_a','select pg_backend_pid()')as t(pid int);select pid into pid_b from dblink('attachment_b','select pg_backend_pid()')as t(pid int);
 for n in 1..13 loop
  first_p:=jsonb_build_object('projeto_id',rm_test_attachment_versions.key('5',n),'upload_id',rm_test_attachment_versions.key('d',n));second_p:=first_p;
  first_op:='finalize_project_attachment_version';second_op:=first_op;first_id:=rm_test_attachment_versions.key('d',n);second_id:=first_id;expected:='00000';
  if n=1 then second_id:=rm_test_attachment_versions.key('d',1001);second_p:=second_p||jsonb_build_object('upload_id',second_id);expected:='PT409';
  elsif n=3 then first_op:='reserve_project_attachment_version';second_op:=first_op;first_p:=rm_test_attachment_versions.payload(n);second_p:=first_p;first_id:=rm_test_attachment_versions.key('e',n);second_id:=first_id;
  elsif n in(4,5,10)then
   s:=public.rm_web_project_attachment_snapshot_v1(rm_test_attachment_versions.key('5',n),rm_test_attachment_versions.key('c',n),1);
   second_op:='save_project';second_id:=gen_random_uuid();second_p:=jsonb_build_object('id',rm_test_attachment_versions.key('5',n),'expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('status_pcp','cancelado'));
   if n=5 then first_op:=second_op;first_p:=second_p;first_id:=second_id;second_op:='finalize_project_attachment_version';second_p:=jsonb_build_object('projeto_id',rm_test_attachment_versions.key('5',n),'upload_id',rm_test_attachment_versions.key('d',n));second_id:=rm_test_attachment_versions.key('d',n);expected:='PT409';
   elsif n=10 then first_op:='reserve_with_bytes';first_p:=rm_test_attachment_versions.payload(n);first_id:=rm_test_attachment_versions.key('e',n);end if;
  elsif n in(6,7,12)then
   second_op:=case when n=12 then 'raw_access'else 'raw_content'end;second_p:=jsonb_build_object('source_attachment_id',rm_test_attachment_versions.key('c',n));second_id:=gen_random_uuid();
   if n in(6,12)then first_op:=second_op;first_p:=second_p;first_id:=second_id;second_op:='finalize_project_attachment_version';second_p:=jsonb_build_object('projeto_id',rm_test_attachment_versions.key('5',n),'upload_id',rm_test_attachment_versions.key('d',n));second_id:=rm_test_attachment_versions.key('d',n);if n=6 then expected:='PT409';end if;end if;
  elsif n=8 then first_op:='reserve_with_bytes';first_p:=rm_test_attachment_versions.payload(n);first_id:=rm_test_attachment_versions.key('e',n);second_op:='finalize_project_attachment';expected:='22023';
  elsif n=9 then first_op:='finalize_project_attachment';first_id:=rm_test_attachment_versions.key('b',n);first_p:=jsonb_build_object('projeto_id',rm_test_attachment_versions.key('5',n),'upload_id',first_id);second_op:='reserve_project_attachment_version';second_p:=rm_test_attachment_versions.payload(n,first_id);second_id:=rm_test_attachment_versions.key('e',n);expected:='23505';
  elsif n=11 then second_op:='read_published';second_p:=second_p||jsonb_build_object('path',(select object_path from rm_private.project_attachment_uploads where id=rm_test_attachment_versions.key('d',n)));second_id:=gen_random_uuid();
  elsif n=13 then first_op:='reserve_project_attachment_version';first_p:=rm_test_attachment_versions.payload(n);first_id:=rm_test_attachment_versions.key('e',n);second_op:=first_op;second_p:=rm_test_attachment_versions.payload(n,rm_test_attachment_versions.key('d',1013));second_id:=rm_test_attachment_versions.key('e',1013);
  end if;
  perform dblink_send_query('attachment_a',format('select rm_test_attachment_versions.run(%L,%L,%L::jsonb,1.0)',first_op,first_id,first_p::text));
  waited:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');waited:=waited+1;if waited>250 then raise exception 'FAIL: attachment race% first writer did not hold',n;end if;perform pg_sleep(0.01);end loop;
  perform dblink_send_query('attachment_b',format('select rm_test_attachment_versions.run(%L,%L,%L::jsonb,0)',second_op,second_id,second_p::text));
  if n=11 then select r into b from dblink_get_result('attachment_b')as t(r jsonb);perform r from dblink_get_result('attachment_b')as t(r jsonb);
   perform rm_test_attachment_versions.check(b->'result'->>'documents'='0'and b->'result'->>'objects'='0','uncommitted new file remains private');
  else waited:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');waited:=waited+1;if waited>150 then raise exception 'FAIL: attachment race% second writer did not contend',n;end if;perform pg_sleep(0.005);end loop;end if;
  select r into a from dblink_get_result('attachment_a')as t(r jsonb);perform r from dblink_get_result('attachment_a')as t(r jsonb);
  if n<>11 then select r into b from dblink_get_result('attachment_b')as t(r jsonb);perform r from dblink_get_result('attachment_b')as t(r jsonb);end if;
  perform rm_test_attachment_versions.check(a->>'sqlstate'='00000',format('first attachment race%s: %s',n,a));perform rm_test_attachment_versions.check(b->>'sqlstate'=expected,format('second attachment race%s: %s',n,b));
  if n=1 then perform rm_test_attachment_versions.check((select count(*)=1 from rm_private.project_attachment_versions where root_doc_id=rm_test_attachment_versions.key('c',n)and finalized_doc_id is not null)and(select finalized_doc_id is null from rm_private.project_attachment_versions where id=rm_test_attachment_versions.key('d',1001)),'only one child publishes; losing intent/file retained');end if;
  if n in(2,3)then perform rm_test_attachment_versions.check((b->'result'->>'idempotent_replay')::boolean,'same protocol recovers one result');end if;
  if n in(5,6,8,10)then perform rm_test_attachment_versions.check(not exists(select 1 from public.rm_docs where id=rm_test_attachment_versions.key('d',n))and(select finalized_doc_id is null from rm_private.project_attachment_versions where id=rm_test_attachment_versions.key('d',n)),'rejected/unfinished publication keeps private pending intent');end if;
  if n=8 then perform rm_test_attachment_versions.check(not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=rm_test_attachment_versions.key('d',n)),'old finalizer cannot publish an initially invisible version reservation');end if;
  if n=9 then perform rm_test_attachment_versions.check(exists(select 1 from public.rm_docs where id=rm_test_attachment_versions.key('b',n))and not exists(select 1 from rm_private.project_attachment_versions where id=rm_test_attachment_versions.key('b',n)),'ordinary old finalizer remains valid and cannot be reclassified as a version');end if;
  if n=11 then select r into b from dblink('attachment_b',format('select rm_test_attachment_versions.run(%L,%L,%L::jsonb,0)','read_published',gen_random_uuid(),second_p::text))as t(r jsonb);perform rm_test_attachment_versions.check(b->'result'->>'documents'='1'and b->'result'->>'objects'='1','committed new version and exact file become readable together');end if;
  if n=13 then perform rm_test_attachment_versions.check((select count(*)=2 from rm_private.project_attachment_versions where root_doc_id=rm_test_attachment_versions.key('c',n)and finalized_doc_id is null),'pending intents do not invalidate each other or create duplicate heads');end if;
 end loop;
 perform dblink_disconnect('attachment_a');perform dblink_disconnect('attachment_b');
exception when others then if 'attachment_a'=any(dblink_get_connections())then perform dblink_disconnect('attachment_a');end if;if 'attachment_b'=any(dblink_get_connections())then perform dblink_disconnect('attachment_b');end if;raise;end$$;
select 'PASS:13 real attachment races cover competing heads, exact retries, closure, content/access metadata, both command kinds, invisible reservations and private-to-published visibility' as result;
begin;update rm_private.sso_settings set require_sso=false;commit;

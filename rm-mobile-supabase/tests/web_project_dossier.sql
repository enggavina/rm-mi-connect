-- TEST DATABASE ONLY: append-only comments and private two-phase attachments.
\set ON_ERROR_STOP on
begin;
create function pg_temp.ds_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.ds_key(h text,n int) returns uuid language sql immutable as $$
 select (h||'f100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.ds_actor(n int,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.ds_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.ds_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.ds.actor',n::text,true); end $$;
create function pg_temp.ds_call(op text,p jsonb,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.ds.actor'),64,'f1'),rid,op,p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role; return r;
 exception when others then reset role; raise; end $$;
create function pg_temp.ds_reject(op text,p jsonb,wanted text,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns void language plpgsql as $$ declare actual text; begin
 begin perform pg_temp.ds_call(op,p,rid,cap); exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm; end;
 raise exception 'FAIL: dossier unexpectedly succeeded'; end $$;
create function pg_temp.ds_comment(project_n int default 1,allocation_n int default 11,event text default 'Important project note') returns jsonb language sql as $$
 select jsonb_build_object('projeto_id',p.id,'celula_projeto_id',a.id,'expected_project_updated_at',p.updated_at,'expected_allocation_updated_at',a.updated_at,'evento',event)
 from public.rm_projetos p cross join public.rm_celulas_projeto a where p.id=pg_temp.ds_key('5',project_n) and a.id=pg_temp.ds_key('6',allocation_n); $$;
create function pg_temp.ds_reserve(n int default 1,project_n int default 1) returns jsonb language sql as $$
 select jsonb_build_object('upload_id',pg_temp.ds_key('c',n),'projeto_id',p.id,'expected_project_updated_at',p.updated_at,
 'nome','  Name of attachment '||n||'  ','descricao','  Internal description  ','filename','technical.pdf','mime_type','application/pdf','byte_size',19,
 'sha256',repeat('a',64),'data_vencimento','2026-11-03T12:00:00Z','status','No prazo') from public.rm_projetos p where p.id=pg_temp.ds_key('5',project_n); $$;
create function pg_temp.ds_finish(n int default 1,project_n int default 1) returns jsonb language sql immutable as $$
 select jsonb_build_object('upload_id',pg_temp.ds_key('c',n),'projeto_id',pg_temp.ds_key('5',project_n)); $$;
create function pg_temp.ds_file(n int) returns void language plpgsql as $$ begin
 insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
 select pg_temp.ds_key('e',n),'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)
 from rm_private.project_attachment_uploads where id=pg_temp.ds_key('c',n);
end $$;
do $$ declare n int; begin for n in 1..5 loop
 insert into auth.users(id) values(pg_temp.ds_key('1',n));
 insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.ds_key('2',n),pg_temp.ds_key('1',n),'Dossier actor '||n,
  case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' when n=5 then 'cliente' else 'padr_o' end,
  case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
 insert into auth.sessions(id,user_id) values(pg_temp.ds_key('3',n),pg_temp.ds_key('1',n));
 insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(pg_temp.ds_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.ds_key('9',n),pg_temp.ds_key('2',n),pg_temp.ds_key('1',n),true,pg_temp.ds_key('2',1),clock_timestamp());
 if n in(1,2,3) then perform public.rm_sso_session_put_v1(lpad(n::text,64,'f1'),pg_temp.ds_key('8',n),pg_temp.ds_key('3',n),'opaque-dossier-fixture-'||n,clock_timestamp()+interval '45 minutes'); end if;
 end loop; end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero,status_pcp,data_real_de_entrega)
 select pg_temp.ds_key('5',n),'DOSSIER-29-'||n,case when n=3 then 'cancelado'::public.rm_status_pcp_enum when n=4 then 'finalizando_para_faturar' end,
 case when n=5 then clock_timestamp() end from generate_series(1,6) n;
insert into public.rm_celulas(id,nome) values(pg_temp.ds_key('4',1),'Dossier cell'),(pg_temp.ds_key('4',2),'Hidden dossier cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
 select pg_temp.ds_key('6',n*10+1),pg_temp.ds_key('5',n),pg_temp.ds_key('4',1),'pendente',true from generate_series(1,6) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
 values(pg_temp.ds_key('6',12),pg_temp.ds_key('5',1),pg_temp.ds_key('4',2),'pendente',false);
insert into public.rm_docs(id,projeto_id,nome,arquivo_url,descricao)
 values(pg_temp.ds_key('b',1),pg_temp.ds_key('5',1),'Legacy attachment','https://example.cdn.bubble.io/legacy.pdf','Legacy editable');
insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
 values(pg_temp.ds_key('e',99),'rm-documentos',pg_temp.ds_key('1',1)::text||'/legacy.pdf','{"size":19,"mimetype":"application/pdf"}',null);
select pg_temp.ds_actor(1);

-- Existing legacy data and effective privacy boundaries remain independent.
select pg_temp.ds_check(not has_table_privilege('anon','rm_private.project_attachment_uploads','select')
 and not has_table_privilege('authenticated','rm_private.project_attachment_uploads','select')
 and not has_table_privilege('service_role','rm_private.project_attachment_uploads','select'),'reservation journal never exposed to clients or Storage service');
select pg_temp.ds_check(not has_function_privilege('authenticated','rm_private.guard_project_attachment_doc_v1()','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute'),'private writers cannot be called directly');
select pg_temp.ds_check(not has_function_privilege('anon','public.rm_web_mutate_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('service_role','public.rm_web_mutate_v1(uuid,text,jsonb)','execute'),'web envelope remains JWT-only');
set local role authenticated;
select pg_temp.ds_check((select count(*)=1 from storage.objects where id=pg_temp.ds_key('e',99)),'legacy document object is still readable');
update storage.objects set metadata=metadata||'{"legacy_preserved":true}' where id=pg_temp.ds_key('e',99);
reset role;
select pg_temp.ds_check((select(metadata->>'legacy_preserved')::boolean from storage.objects where id=pg_temp.ds_key('e',99)),'legacy own-prefix update remains allowed');
update public.rm_docs set descricao='Still editable' where id=pg_temp.ds_key('b',1);

-- Comments use the existing history with exact target, author and receipt.
do $$ declare p jsonb:=pg_temp.ds_comment(1,11,'  Preserve this note  '); r jsonb; snapshot jsonb; begin
 r:=pg_temp.ds_call('add_project_comment',p,pg_temp.ds_key('f',1));
 perform pg_temp.ds_check(r->>'id'=pg_temp.ds_key('f',1)::text and r->'record'->>'evento'='Preserve this note'
  and r->'record'->>'cadastrado_por_id'=pg_temp.ds_key('2',1)::text,'server author and stable comment ID/text');
 select to_jsonb(c) into snapshot from public.rm_comentarios c where id=pg_temp.ds_key('f',1);
 r:=pg_temp.ds_call('add_project_comment',p,pg_temp.ds_key('f',1));
 perform pg_temp.ds_check((r->>'idempotent_replay')::boolean and (select to_jsonb(c)=snapshot from public.rm_comentarios c where id=pg_temp.ds_key('f',1)),'comment exact replay preserves record');
 perform pg_temp.ds_check((select count(*)=1 from public.rm_sync_outbox where record_id=pg_temp.ds_key('f',1)),'one compatible comment outbox event');
 perform pg_temp.ds_reject('add_project_comment',p||'{"evento":"changed intention"}','23505',pg_temp.ds_key('f',1));
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment(1,21),'22023');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment()||'{"cadastrado_por_id":"2f100000-0000-4000-8000-000000000002"}','22023');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment()||'{"evento":"   "}','22023');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment()||jsonb_build_object('evento',repeat('x',10001)),'22023');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment()||'{"expected_project_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment()||'{"expected_allocation_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment()||'{"expected_project_updated_at":"infinity"}','22023');
 perform pg_temp.ds_call('add_project_comment',pg_temp.ds_comment(1,12,'Hidden but active work'),pg_temp.ds_key('f',2));
 perform pg_temp.ds_check((select not visibilidade from public.rm_celulas_projeto where id=pg_temp.ds_key('6',12)),'hidden work accepts comments without visibility change');
end $$;
do $$ declare s jsonb; p jsonb; n int; begin
 for n in 3..5 loop perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment(n,n*10+1),'22023'); end loop;
 s:=public.rm_web_cell_availability_snapshot_v1(pg_temp.ds_key('5',6),pg_temp.ds_key('6',61));
 p:=jsonb_build_object('action','retire','projeto_id',pg_temp.ds_key('5',6),'celula_projeto_id',pg_temp.ds_key('6',61),
 'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
 perform pg_temp.ds_call('manage_cell_availability',p,gen_random_uuid(),'em.planning.manage');
 perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment(6,61),'PT409');
end $$;

-- Reservation never creates a public attachment or a visible pending file.
do $$ declare p jsonb:=pg_temp.ds_reserve(); r jsonb; before_count int; begin
 select count(*) into before_count from public.rm_docs;
 r:=pg_temp.ds_call('reserve_project_attachment',p,pg_temp.ds_key('d',1));
 perform pg_temp.ds_check(r->>'id'=pg_temp.ds_key('c',1)::text and r->'record'->>'path'='web-dossier/'||pg_temp.ds_key('5',1)::text||'/'||pg_temp.ds_key('c',1)::text||'.pdf','server-generated exact path');
 perform pg_temp.ds_check((select count(*)=before_count from public.rm_docs),'reservation has no partial public document');
 r:=pg_temp.ds_call('reserve_project_attachment',p,pg_temp.ds_key('d',1));
 perform pg_temp.ds_check((r->>'idempotent_replay')::boolean and (select count(*)=1 from rm_private.project_attachment_uploads where id=pg_temp.ds_key('c',1)),'reservation replay no duplicates');
 perform pg_temp.ds_reject('reserve_project_attachment',p,'23505');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"nome":"different"}','23505',pg_temp.ds_key('d',1));
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'22023');
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'PT503',pg_temp.ds_key('c',1));
 perform pg_temp.ds_file(1);
 insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
  select pg_temp.ds_key('e',100),'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)
  from rm_private.project_attachment_uploads where id=pg_temp.ds_key('c',1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'PT409',pg_temp.ds_key('c',1));
 delete from storage.objects where id=pg_temp.ds_key('e',100);
 set local role authenticated;
 perform pg_temp.ds_check((select count(*)=0 from storage.objects where id=pg_temp.ds_key('e',1)),'pending upload hidden from existing permissive Storage read');
 begin insert into storage.objects(bucket_id,name) values('rm-documentos','web-dossier/arbitrary.pdf');
  raise exception 'FAIL: authenticated created new reserved object'; exception when insufficient_privilege then null; end;
 update storage.objects set user_metadata='{"sha256":"changed"}' where id=pg_temp.ds_key('e',1);
 reset role;
 perform pg_temp.ds_check((select user_metadata->>'sha256'=repeat('a',64) from storage.objects where id=pg_temp.ds_key('e',1)),'authenticated cannot update pending object');
end $$;

do $$ declare n int; p jsonb; begin
 for n in 3..5 loop perform pg_temp.ds_reject('reserve_project_attachment',pg_temp.ds_reserve(20+n,n),'22023'); end loop;
 p:=pg_temp.ds_reserve(2);
 perform pg_temp.ds_reject('reserve_project_attachment',p,'22023',pg_temp.ds_key('c',2));
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"byte_size":0}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"byte_size":20971521}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"byte_size":1.5}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"mime_type":"application/javascript"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"sha256":"not-a-sha"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"filename":"../escape.pdf"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"nome":"   "}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||jsonb_build_object('nome',repeat('x',201)),'22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||jsonb_build_object('descricao',repeat('x',2001)),'22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"descricao":false}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"filename":"bad\\file.pdf"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"status":"Automatic"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"data_vencimento":"infinity"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"data_vencimento":"2026-02-30T12:00:00Z"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"arquivo_url":"https://attacker.invalid/file"}','22023');
 perform pg_temp.ds_reject('reserve_project_attachment',p||'{"expected_project_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.ds_reject('reserve_project_attachment',p,'22023',gen_random_uuid(),'em.documents.read');
end $$;

-- The trusted uploader's metadata must match; failure leaves no public record.
do $$ declare r jsonb; snap jsonb; begin
 update storage.objects set metadata='{"size":"bad","mimetype":"application/pdf"}' where id=pg_temp.ds_key('e',1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'PT409',pg_temp.ds_key('c',1));
 update storage.objects set metadata='{"size":20,"mimetype":"application/pdf"}' where id=pg_temp.ds_key('e',1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'PT409',pg_temp.ds_key('c',1));
 update storage.objects set metadata='{"size":19,"mimetype":"image/jpeg"}' where id=pg_temp.ds_key('e',1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'PT409',pg_temp.ds_key('c',1));
 update storage.objects set metadata='{"size":19,"mimetype":"application/pdf"}',user_metadata='{"sha256":"wrong"}' where id=pg_temp.ds_key('e',1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'PT409',pg_temp.ds_key('c',1));
 perform pg_temp.ds_check(not exists(select 1 from public.rm_docs where id=pg_temp.ds_key('c',1)) and (select finalized_doc_id is null from rm_private.project_attachment_uploads where id=pg_temp.ds_key('c',1)),'mismatched file never partially finalizes');
 update storage.objects set user_metadata=jsonb_build_object('sha256',repeat('a',64)) where id=pg_temp.ds_key('e',1);
 perform pg_temp.ds_actor(2);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'42501',pg_temp.ds_key('c',1));
 perform pg_temp.ds_actor(1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(1,2),'P0002',pg_temp.ds_key('c',1));
 -- A harmless metadata change after reserve does not rewrite project data or
 -- force a second upload; the current project must still be open.
 update public.rm_projetos set nome='Changed after file reservation' where id=pg_temp.ds_key('5',1);
 r:=pg_temp.ds_call('finalize_project_attachment',pg_temp.ds_finish(),pg_temp.ds_key('c',1));
 perform pg_temp.ds_check(r->>'id'=pg_temp.ds_key('c',1)::text and r->'record'->>'status'='No prazo' and r->'record'->>'nome'='Name of attachment 1'
  and (r->'record'->>'visivel_cliente')::boolean=false,'final document identity, original metadata and internal visibility');
 perform pg_temp.ds_check((select created_by=pg_temp.ds_key('2',1) and arquivo_url='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/'||pg_temp.ds_key('5',1)::text||'/'||id::text||'.pdf'
  and tipo_arquivo='application/pdf' and descricao='Internal description' and data_vencimento='2026-11-03T12:00:00Z'::timestamptz from public.rm_docs where id=pg_temp.ds_key('c',1)),'server author, fixed authenticated URL and exact expiry');
 select to_jsonb(d) into snap from public.rm_docs d where id=pg_temp.ds_key('c',1);
 r:=pg_temp.ds_call('finalize_project_attachment',pg_temp.ds_finish(),pg_temp.ds_key('c',1));
 perform pg_temp.ds_check((r->>'idempotent_replay')::boolean and (select to_jsonb(d)=snap from public.rm_docs d where id=pg_temp.ds_key('c',1)),'final replay preserves file record and timestamp');
 set local role authenticated;
 perform pg_temp.ds_check((select count(*)=1 from storage.objects where id=pg_temp.ds_key('e',1)),'only finalized file visible under existing private read');
 update storage.objects set user_metadata='{"sha256":"changed"}' where id=pg_temp.ds_key('e',1);
 begin delete from storage.objects where id=pg_temp.ds_key('e',1); raise exception 'FAIL: authenticated deleted finalized file'; exception when insufficient_privilege then null; end;
 reset role;
 perform pg_temp.ds_check((select user_metadata->>'sha256'=repeat('a',64) from storage.objects where id=pg_temp.ds_key('e',1)),'published file remains immutable to authenticated UPDATE');
 begin update public.rm_docs set arquivo_url='https://example.cdn.bubble.io/replaced' where id=pg_temp.ds_key('c',1); raise exception 'FAIL: ETL changed published file'; exception when invalid_parameter_value then null; end;
 begin update public.rm_docs set projeto_id=pg_temp.ds_key('5',2) where id=pg_temp.ds_key('c',1); raise exception 'FAIL: moved published doc'; exception when invalid_parameter_value then null; end;
 begin update public.rm_docs set nome=nome where id=pg_temp.ds_key('c',1); raise exception 'FAIL: touched immutable timestamp'; exception when invalid_parameter_value then null; end;
 begin delete from public.rm_docs where id=pg_temp.ds_key('c',1); raise exception 'FAIL: deleted published document'; exception when invalid_parameter_value then null; end;
 perform pg_temp.ds_check((select to_jsonb(d)=snap from public.rm_docs d where id=pg_temp.ds_key('c',1)),'all protected metadata stays byte-identical');
end $$;

do $$ declare n int; begin
 for n in 1..3 loop
  perform pg_temp.ds_actor(n); set local role authenticated;
  perform pg_temp.ds_check((select count(*)=1 from public.rm_docs where id=pg_temp.ds_key('c',1))
   and (select count(*)=1 from storage.objects where id=pg_temp.ds_key('e',1)),'internal admin/operator/auditor reads finalized document and file');
  reset role;
 end loop;
 perform pg_temp.ds_actor(5); set local role authenticated;
 perform pg_temp.ds_check((select count(*)=0 from public.rm_docs where id=pg_temp.ds_key('c',1))
  and (select count(*)=0 from storage.objects where id=pg_temp.ds_key('e',1)),'direct customer Auth JWT cannot read a new internal attachment or its object');
 perform pg_temp.ds_check((select count(*)=1 from public.rm_docs where id=pg_temp.ds_key('b',1))
  and (select count(*)=1 from storage.objects where id=pg_temp.ds_key('e',99)),'legacy customer read behavior stays unchanged for legacy rows and objects');
 reset role; perform pg_temp.ds_actor(1);
end $$;

-- Other supported types and optional metadata, without changing storage limits.
do $$ declare n int; p jsonb; r jsonb; begin
 for n in 2..3 loop
 p:=pg_temp.ds_reserve(n)||jsonb_build_object('mime_type',case when n=2 then 'image/jpeg' else 'image/png' end,'filename','inspection-image',
 'byte_size',20971520,'descricao',null,'data_vencimento',null,'status','Vencido');
 r:=pg_temp.ds_call('reserve_project_attachment',p,pg_temp.ds_key('d',n)); perform pg_temp.ds_file(n);
 r:=pg_temp.ds_call('finalize_project_attachment',pg_temp.ds_finish(n),pg_temp.ds_key('c',n));
 perform pg_temp.ds_check(r->'record'->>'status'='Vencido' and r->'record'->'data_vencimento'='null'::jsonb and r->'record'->'descricao'='null'::jsonb,'explicit status is independent of absent expiry');
 end loop;
end $$;

-- Current authorization is evaluated before every old or new receipt.
do $$ declare p jsonb; r jsonb; begin
 perform pg_temp.ds_actor(2); r:=pg_temp.ds_call('add_project_comment',pg_temp.ds_comment(1,11,'Standard writer'),pg_temp.ds_key('f',3));
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'23505',pg_temp.ds_key('c',1));
 perform pg_temp.ds_actor(3); perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment(),'42501');
 perform pg_temp.ds_actor(4); perform pg_temp.ds_reject('add_project_comment',pg_temp.ds_comment(),'42501');
 perform pg_temp.ds_actor(1);
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.ds_key('1',1),'totp','verified');
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'42501',pg_temp.ds_key('c',1));
 perform pg_temp.ds_actor(1,'aal2'); r:=pg_temp.ds_call('finalize_project_attachment',pg_temp.ds_finish(),pg_temp.ds_key('c',1));
 perform pg_temp.ds_check((r->>'idempotent_replay')::boolean,'MFA2 exact replay accepted');
 update rm_private.sso_identity_bindings set enabled=false where id=pg_temp.ds_key('8',1);
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(),'42501',pg_temp.ds_key('c',1));
 update rm_private.sso_identity_bindings set enabled=true where id=pg_temp.ds_key('8',1);
 -- Replays precede closure, but no new note/reservation/finalization is allowed.
 p:=pg_temp.ds_reserve(4); perform pg_temp.ds_call('reserve_project_attachment',p,pg_temp.ds_key('d',4)); perform pg_temp.ds_file(4);
 update public.rm_projetos set status_pcp='cancelado' where id=pg_temp.ds_key('5',1);
 r:=pg_temp.ds_call('reserve_project_attachment',p,pg_temp.ds_key('d',4)); perform pg_temp.ds_check((r->>'idempotent_replay')::boolean,'reserve receipt still confirms after closure');
 r:=pg_temp.ds_call('finalize_project_attachment',pg_temp.ds_finish(),pg_temp.ds_key('c',1)); perform pg_temp.ds_check((r->>'idempotent_replay')::boolean,'completed attachment confirms after closure');
 perform pg_temp.ds_reject('finalize_project_attachment',pg_temp.ds_finish(4),'22023',pg_temp.ds_key('c',4));
 perform pg_temp.ds_check((select finalized_doc_id is null from rm_private.project_attachment_uploads where id=pg_temp.ds_key('c',4)),'closed project leaves uploaded reservation available for explicit reconciliation');
end $$;
select 'PASS:029 comments preserve author/target/history/offline receipts; private reservation/upload/finalization, file guards, permissions, MIME/size/hash, immutable publication and closed-context recovery' as result;
rollback;

-- Real independent transactions: no controller waits on locks it owns itself.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_dossier;
create function rm_test_dossier.key(h text,n int) returns uuid language sql immutable as $$
 select (h||'f200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function rm_test_dossier.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values(rm_test_dossier.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_dossier.key('2',1),rm_test_dossier.key('1',1),'Dossier concurrent writer','administrador');
insert into auth.sessions(id,user_id) values(rm_test_dossier.key('3',1),rm_test_dossier.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_dossier.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_dossier.key('9',1),rm_test_dossier.key('2',1),rm_test_dossier.key('1',1),true,rm_test_dossier.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('f2',32),rm_test_dossier.key('8',1),rm_test_dossier.key('3',1),'opaque-dossier-local-races',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero) select rm_test_dossier.key('5',n),'DOSSIER-RACE-29-'||n from generate_series(1,9) n;
insert into public.rm_celulas(id,nome) select rm_test_dossier.key('4',n),'Dossier race cell '||n from generate_series(1,9) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,posicao,indice)
 select rm_test_dossier.key('6',n),rm_test_dossier.key('5',n),rm_test_dossier.key('4',n),'pendente',false,37,12 from generate_series(1,9) n;
create function rm_test_dossier.reserve(n int) returns jsonb language sql as $$
 select jsonb_build_object('upload_id',rm_test_dossier.key('c',n),'projeto_id',p.id,'expected_project_updated_at',p.updated_at,
 'nome','Concurrent private file '||n,'descricao',null,'filename','concurrent.pdf','mime_type','application/pdf','byte_size',19,
 'sha256',repeat('d',64),'data_vencimento',null,'status','No prazo') from public.rm_projetos p where p.id=rm_test_dossier.key('5',n); $$;
create function rm_test_dossier.run(op text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_dossier.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_dossier.key('3',1),'aal','aal1')::text,true);
 if op='read_published' then
  set local role authenticated;
  select jsonb_build_object('documents',(select count(*) from public.rm_docs where id=(p->>'upload_id')::uuid),
   'objects',(select count(*) from storage.objects where bucket_id='rm-documentos' and name=p->>'path')) into r;
  reset role;
 else
  perform public.rm_sso_action_permit_v1(repeat('f2',32),rid,op,p,case when op='manage_cell_availability' then 'em.planning.manage' else 'em.projects.manage' end);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role;
 end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state,'message',sqlerrm); end $$;
-- Pre-existing immutable uploaded bytes for the completion/closure races.
do $$ declare n int; r jsonb; begin
 for n in select x from unnest(array[5,6,7,9]) x loop
  r:=rm_test_dossier.run('reserve_project_attachment',rm_test_dossier.key('d',n),rm_test_dossier.reserve(n));
  perform rm_test_dossier.check(r->>'sqlstate'='00000','concurrent reservation fixture valid');
  insert into storage.objects(bucket_id,name,metadata,user_metadata)
   select 'rm-documentos',object_path,jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)
   from rm_private.project_attachment_uploads where id=rm_test_dossier.key('c',n);
 end loop;
end $$;
commit;

do $$ declare scenario int; s jsonb; p_comment jsonb; p_retire jsonb; p_close jsonb; p_finish jsonb; p_reserve jsonb;
 first_op text; second_op text; first_p jsonb; second_p jsonb; first_id uuid; second_id uuid;
 a jsonb; b jsonb; visible jsonb; pid_a int; pid_b int; waited int; expected text; snap jsonb; begin
 perform set_config('request.jwt.claim.sub',rm_test_dossier.key('1',1)::text,true);
 perform dblink_connect('dossier_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('dossier_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('dossier_a','select pg_backend_pid()') as t(pid int);
 select pid into pid_b from dblink('dossier_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..9 loop
  s:=public.rm_web_cell_availability_snapshot_v1(rm_test_dossier.key('5',scenario),rm_test_dossier.key('6',scenario));
  p_comment:=jsonb_build_object('projeto_id',rm_test_dossier.key('5',scenario),'celula_projeto_id',rm_test_dossier.key('6',scenario),
   'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','evento','Real concurrent project comment');
  p_retire:=jsonb_build_object('action','retire','projeto_id',rm_test_dossier.key('5',scenario),'celula_projeto_id',rm_test_dossier.key('6',scenario),
   'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
  p_close:=jsonb_build_object('id',rm_test_dossier.key('5',scenario),'expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('status_pcp','cancelado'));
  p_finish:=jsonb_build_object('projeto_id',rm_test_dossier.key('5',scenario),'upload_id',rm_test_dossier.key('c',scenario));
  p_reserve:=rm_test_dossier.reserve(scenario);
  if scenario=1 then first_op:='add_project_comment'; first_p:=p_comment; second_op:='manage_cell_availability'; second_p:=p_retire;
  elsif scenario=2 then first_op:='manage_cell_availability'; first_p:=p_retire; second_op:='add_project_comment'; second_p:=p_comment;
  elsif scenario=3 then first_op:='reserve_project_attachment'; first_p:=p_reserve; second_op:='save_project'; second_p:=p_close;
  elsif scenario=4 then first_op:='save_project'; first_p:=p_close; second_op:='reserve_project_attachment'; second_p:=p_reserve;
  elsif scenario=5 then first_op:='finalize_project_attachment'; first_p:=p_finish; second_op:='save_project'; second_p:=p_close;
  elsif scenario=6 then first_op:='save_project'; first_p:=p_close; second_op:='finalize_project_attachment'; second_p:=p_finish;
  elsif scenario=7 then first_op:='finalize_project_attachment'; first_p:=p_finish; second_op:=first_op; second_p:=first_p;
  elsif scenario=8 then first_op:='reserve_project_attachment'; first_p:=p_reserve; second_op:=first_op; second_p:=first_p;
  else first_op:='finalize_project_attachment'; first_p:=p_finish; second_op:='read_published';
   second_p:=p_finish||jsonb_build_object('path',(select object_path from rm_private.project_attachment_uploads where id=rm_test_dossier.key('c',scenario)));
  end if;
  first_id:=case when first_op='finalize_project_attachment' then rm_test_dossier.key('c',scenario) when first_op='reserve_project_attachment' then rm_test_dossier.key('d',scenario) else gen_random_uuid() end;
  second_id:=case when scenario in(7,8) then first_id when second_op='finalize_project_attachment' then rm_test_dossier.key('c',scenario) when second_op='reserve_project_attachment' then rm_test_dossier.key('d',scenario) else gen_random_uuid() end;
  perform dblink_send_query('dossier_a',format('select rm_test_dossier.run(%L,%L,%L::jsonb,1.0)',first_op,first_id,first_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: dossier race%s first writer did not hold',scenario; end if; perform pg_sleep(0.01); end loop;
  perform dblink_send_query('dossier_b',format('select rm_test_dossier.run(%L,%L,%L::jsonb,0)',second_op,second_id,second_p::text));
  if scenario=9 then
   select r into b from dblink_get_result('dossier_b') as t(r jsonb); perform r from dblink_get_result('dossier_b') as t(r jsonb);
   perform rm_test_dossier.check(b->>'sqlstate'='00000' and b->'result'->>'documents'='0' and b->'result'->>'objects'='0','uncommitted publication remains unreadable');
   perform rm_test_dossier.check(exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep'),'private read really overlaps uncommitted finalization');
  else
   waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
    waited:=waited+1; if waited>150 then raise exception 'FAIL: dossier race%s second writer did not contend',scenario; end if; perform pg_sleep(0.005); end loop;
  end if;
  select r into a from dblink_get_result('dossier_a') as t(r jsonb); perform r from dblink_get_result('dossier_a') as t(r jsonb);
  if scenario<>9 then select r into b from dblink_get_result('dossier_b') as t(r jsonb); perform r from dblink_get_result('dossier_b') as t(r jsonb); end if;
  expected:=case when scenario in(1,2,4) then 'PT409' when scenario=6 then '22023' else '00000' end;
  perform rm_test_dossier.check(a->>'sqlstate'='00000',format('first dossier race%s: %s',scenario,a));
  perform rm_test_dossier.check(b->>'sqlstate'=expected,format('second dossier race%s: %s',scenario,b));
  if scenario=1 then perform rm_test_dossier.check((select not retirada from public.rm_celulas_projeto where id=rm_test_dossier.key('6',1))
   and (select count(*)=1 from public.rm_comentarios where projeto_id=rm_test_dossier.key('5',1)),'comment first blocks retirement without deleting history'); end if;
  if scenario=2 then perform rm_test_dossier.check((select retirada from public.rm_celulas_projeto where id=rm_test_dossier.key('6',2))
   and not exists(select 1 from public.rm_comentarios where projeto_id=rm_test_dossier.key('5',2)),'retirement first rejects a new comment'); end if;
  if scenario=4 then perform rm_test_dossier.check(not exists(select 1 from rm_private.project_attachment_uploads where id=rm_test_dossier.key('c',4)),'closure wins without partial reservation'); end if;
  if scenario=5 then perform rm_test_dossier.check((select status_pcp='cancelado' from public.rm_projetos where id=rm_test_dossier.key('5',5))
   and (select count(*)=1 from public.rm_docs where id=rm_test_dossier.key('c',5)),'finalization first keeps completed history when project closes'); end if;
  if scenario=6 then perform rm_test_dossier.check(not exists(select 1 from public.rm_docs where id=rm_test_dossier.key('c',6))
   and (select finalized_doc_id is null from rm_private.project_attachment_uploads where id=rm_test_dossier.key('c',6)),'closure first leaves pending bytes and reservation intact'); end if;
  if scenario in(7,8) then perform rm_test_dossier.check((b->'result'->>'idempotent_replay')::boolean,'same concurrent UUID returns exact completed receipt'); end if;
  if scenario=7 then perform rm_test_dossier.check((select count(*)=1 from public.rm_docs where id=rm_test_dossier.key('c',7))
   and (select count(*)=1 from rm_private.web_mutation_receipts where client_submission_id=rm_test_dossier.key('c',7)),'only one document and final receipt'); end if;
  if scenario=8 then perform rm_test_dossier.check((select count(*)=1 from rm_private.project_attachment_uploads where id=rm_test_dossier.key('c',8)),'only one concurrent reservation'); end if;
  if scenario=9 then
   select r into visible from dblink('dossier_b',format('select rm_test_dossier.run(%L,%L,%L::jsonb,0)','read_published',gen_random_uuid(),second_p::text)) as t(r jsonb);
   perform rm_test_dossier.check(visible->'result'->>'documents'='1' and visible->'result'->>'objects'='1','publication becomes visible only after commit');
   select to_jsonb(d) into snap from public.rm_docs d where id=rm_test_dossier.key('c',9);
   begin update public.rm_docs set descricao='late old ETL writer' where id=rm_test_dossier.key('c',9); raise exception 'FAIL: late raw writer overwrote publication'; exception when invalid_parameter_value then null; end;
   perform rm_test_dossier.check((select to_jsonb(d)=snap from public.rm_docs d where id=rm_test_dossier.key('c',9)),'late raw write never changes published metadata');
  end if;
 end loop;
 perform dblink_disconnect('dossier_a'); perform dblink_disconnect('dossier_b');
exception when others then if 'dossier_a'=any(dblink_get_connections()) then perform dblink_disconnect('dossier_a'); end if;
 if 'dossier_b'=any(dblink_get_connections()) then perform dblink_disconnect('dossier_b'); end if; raise; end $$;
select 'PASS:9 real dossier races cover comment/retirement, reservation/finalization/closure in both orders, same reservation/final UUID and pending-to-published visibility with immutable metadata' as result;
-- Committed fixtures live only in the disposable cluster, removed by the runner.
begin; update rm_private.sso_settings set require_sso=false; commit;

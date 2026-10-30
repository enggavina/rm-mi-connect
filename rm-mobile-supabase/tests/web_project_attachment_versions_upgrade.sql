-- TEST DATABASE ONLY: exact 032 -> 033 upgrade with previously warmed envelopes.
\set ON_ERROR_STOP on
\if :{?rm_migration_033_path}
\else
\echo 'Run the isolated SQL runner: migration033 path is required.'
\quit 3
\endif
select set_config('rm.test.migration_033_path',:'rm_migration_033_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create temporary table attachment_upgrade_snapshots(name text primary key,rows bigint,hash text);
create temporary table attachment_upgrade_policies(name text primary key,definition jsonb);
create temporary table attachment_upgrade_functions(id oid primary key,definition text,acl aclitem[]);
insert into auth.users(id) values('1ab33000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2ab33000-0000-4000-8000-000000000001','1ab33000-0000-4000-8000-000000000001','Attachment upgrade actor','administrador');
select set_config('request.jwt.claim.sub','1ab33000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into public.rm_projetos(id,numero) values('5ab33000-0000-4000-8000-000000000001','ATTACHMENT-UPGRADE-33');
insert into public.rm_celulas(id,nome) values('aab33000-0000-4000-8000-000000000001','Attachment upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id) values('bab33000-0000-4000-8000-000000000001','5ab33000-0000-4000-8000-000000000001','aab33000-0000-4000-8000-000000000001');
create temporary table attachment_upgrade_intents(key text primary key,payload jsonb);
do $$ declare payload jsonb; begin
 payload:=jsonb_build_object('projeto_id','5ab33000-0000-4000-8000-000000000001','upload_id','cab33000-0000-4000-8000-000000000001',
 'expected_project_updated_at',(select updated_at from public.rm_projetos where id='5ab33000-0000-4000-8000-000000000001'),
 'nome','Original internal file','descricao',null,'filename','original.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo');
 insert into attachment_upgrade_intents values('reserve',payload);
 set local role authenticated;
 perform public.rm_web_mutate_v1('fab33000-0000-4000-8000-000000000001','reserve_project_attachment',payload);
 reset role;
 insert into storage.objects(bucket_id,name,metadata,user_metadata) values('rm-documentos','web-dossier/5ab33000-0000-4000-8000-000000000001/cab33000-0000-4000-8000-000000000001.pdf',
 '{"size":5,"mimetype":"application/pdf"}',jsonb_build_object('sha256',repeat('a',64)));
 payload:='{"projeto_id":"5ab33000-0000-4000-8000-000000000001","upload_id":"cab33000-0000-4000-8000-000000000001"}';
 insert into attachment_upgrade_intents values('finalize',payload);
 set local role authenticated;
 perform public.rm_web_mutate_v1('cab33000-0000-4000-8000-000000000001','finalize_project_attachment',payload);
 reset role;
 payload:=jsonb_build_object('projeto_id','5ab33000-0000-4000-8000-000000000001','celula_projeto_id','bab33000-0000-4000-8000-000000000001',
 'expected_project_updated_at',(select updated_at from public.rm_projetos where id='5ab33000-0000-4000-8000-000000000001'),
 'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id='bab33000-0000-4000-8000-000000000001'),'evento','Preserved original comment');
 insert into attachment_upgrade_intents values('comment',payload);
 set local role authenticated;
 perform public.rm_web_mutate_v1('fab33000-0000-4000-8000-000000000002','add_project_comment',payload);
 reset role;
end $$;
do $$ declare t record; n bigint; h text; begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r'
 and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into attachment_upgrade_snapshots values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 if (select count(*) from attachment_upgrade_snapshots)<>75 then raise exception 'FAIL: expected73 old RM tables plus2 Storage tables'; end if;
 insert into attachment_upgrade_policies select schemaname||'.'||tablename||'.'||policyname,to_jsonb(p) from pg_policies p where schemaname in('storage','public');
 insert into attachment_upgrade_functions select p.oid,pg_get_functiondef(p.oid),p.proacl from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname in('public','rm_private') and(ns.nspname='rm_private' or p.proname like 'rm\_%' escape '\')
 and p.proname not in('web_mutate_core_v1','rm_sso_action_permit_v1');
end $$;
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_033_path')); begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'FAIL: unexpected033 source wrappers'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end $$;
do $$ declare t record; n bigint; h text; s jsonb; payload jsonb; r jsonb; begin
 for t in select * from attachment_upgrade_snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL:033 installation changed old rows: %',t.name; end if;
 end loop;
 if exists(select 1 from rm_private.project_attachment_versions) then raise exception 'FAIL: invented attachment version history'; end if;
 for t in select * from attachment_upgrade_policies loop
  if not exists(select 1 from pg_policies p where p.schemaname||'.'||p.tablename||'.'||p.policyname=t.name and to_jsonb(p)=t.definition) then raise exception 'FAIL: old policy changed'; end if;
 end loop;
 for t in select * from attachment_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and pg_get_functiondef(p.oid)=t.definition and p.proacl is not distinct from t.acl) then raise exception 'FAIL: unrelated function changed: %',t.id::regprocedure; end if;
 end loop;
 select i.payload into payload from attachment_upgrade_intents i where key='reserve';
 set local role authenticated;r:=public.rm_web_mutate_v1('fab33000-0000-4000-8000-000000000001','reserve_project_attachment',payload);reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old reserve receipt'; end if;
 select i.payload into payload from attachment_upgrade_intents i where key='finalize';
 set local role authenticated;r:=public.rm_web_mutate_v1('cab33000-0000-4000-8000-000000000001','finalize_project_attachment',payload);reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old publication receipt'; end if;
 select i.payload into payload from attachment_upgrade_intents i where key='comment';
 set local role authenticated;r:=public.rm_web_mutate_v1('fab33000-0000-4000-8000-000000000002','add_project_comment',payload);reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old comment receipt'; end if;
 s:=public.rm_web_project_attachment_snapshot_v1('5ab33000-0000-4000-8000-000000000001','cab33000-0000-4000-8000-000000000001',1);
 if not(s->>'can_replace')::boolean or s->'series'->>'head_revision'<>'1' then raise exception 'FAIL: old immutable attachment lost virtual base version'; end if;
 payload:=jsonb_build_object('upload_id','cab33000-0000-4000-8000-000000000002','projeto_id','5ab33000-0000-4000-8000-000000000001','source_attachment_id','cab33000-0000-4000-8000-000000000001',
 'expected_project_updated_at',s->'project'->>'updated_at','expected_attachment_updated_at',s->'attachment'->>'updated_at','expected_context_version',s->>'context_version',
 'nome','Updated file','descricao',null,'filename','new.pdf','mime_type','application/pdf','byte_size',5,'sha256',repeat('b',64),'data_vencimento',null,'status','No prazo','motivo','Verified upgrade','confirm_change',true);
 set local role authenticated;r:=public.rm_web_mutate_v1('fab33000-0000-4000-8000-000000000003','reserve_project_attachment_version',payload);reset role;
 if r->'record'->>'revision'<>'2' then raise exception 'FAIL: warmed dispatcher bypassed033'; end if;
 if(select count(*) from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private'))<>74 then raise exception 'FAIL: unexpected033 schema'; end if;
end $$;
rollback;
\ir ../migrations/033_rm_web_project_attachment_versions.sql
select 'PASS:033 preserves73 old RM tables, Storage, policies, unrelated functions and warmed publication/comment receipts' as result;

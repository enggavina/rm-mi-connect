-- TEST DATABASE ONLY: 029 -> 030 adds readers/indexes, never rewrites history.
\set ON_ERROR_STOP on
\if :{?rm_migration_030_path}
\else
\echo 'Run the isolated SQL runner: absolute migration030 path is required.'
\quit 3
\endif
select set_config('rm.test.migration_030_path',:'rm_migration_030_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create temporary table search_upgrade_snapshots(name text primary key,rows bigint,hash text);
create temporary table search_upgrade_policies(name text primary key,definition jsonb);
create temporary table search_upgrade_functions(id oid primary key,definition text,acl aclitem[]);
insert into auth.users(id) values('1fa00000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2fa00000-0000-4000-8000-000000000001','1fa00000-0000-4000-8000-000000000001','Dossier search upgrade actor','administrador');
select set_config('request.jwt.claim.sub','1fa00000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('search-upgrade-mobile','sha256'),'1fa00000-0000-4000-8000-000000000001','2fa00000-0000-4000-8000-000000000001','2fa00000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into public.rm_projetos(id,numero) values('5fa00000-0000-4000-8000-000000000001','DOSSIER-SEARCH-UPGRADE-30');
insert into public.rm_celulas(id,nome) values('4fa00000-0000-4000-8000-000000000001','Original recipient');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,posicao,indice)
 values('6fa00000-0000-4000-8000-000000000001','5fa00000-0000-4000-8000-000000000001','4fa00000-0000-4000-8000-000000000001',false,41,19);
insert into public.rm_tablet_celula_users(celula_id,identidade_id) values('4fa00000-0000-4000-8000-000000000001','2fa00000-0000-4000-8000-000000000001');
insert into public.rm_documentos(id,projeto_id,nome,arquivo_url,created_by) values
 ('bfa00000-0000-4000-8000-000000000001','5fa00000-0000-4000-8000-000000000001','Original generated document','https://example.cdn.bubble.io/original.pdf','2fa00000-0000-4000-8000-000000000001');
do $$ declare p jsonb; n int; begin
 set local role authenticated;
 perform public.rm_mobile_mutate_v1('ffa00000-0000-4000-8000-000000000001','rm_add_cell_comment_v1',
  '{"p_celula_projeto_id":"6fa00000-0000-4000-8000-000000000001","p_comentario":"Preserved mobile comment and receipt"}','search-upgrade-mobile');
 p:=jsonb_build_object('projeto_id','5fa00000-0000-4000-8000-000000000001','celula_projeto_id','6fa00000-0000-4000-8000-000000000001',
  'expected_project_updated_at',(select updated_at from public.rm_projetos where id='5fa00000-0000-4000-8000-000000000001'),
  'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id='6fa00000-0000-4000-8000-000000000001'),'evento','Preserved web comment and receipt');
 perform public.rm_web_mutate_v1('ffa00000-0000-4000-8000-000000000002','add_project_comment',p);
 for n in 1..2 loop
  p:=jsonb_build_object('upload_id',('cfa00000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'projeto_id','5fa00000-0000-4000-8000-000000000001',
   'expected_project_updated_at',(select updated_at from public.rm_projetos where id='5fa00000-0000-4000-8000-000000000001'),
   'nome','Pre030 upload '||n,'descricao',null,'filename','original.pdf','mime_type','application/pdf','byte_size',19,'sha256',repeat('b',64),'data_vencimento',null,'status','No prazo');
  perform public.rm_web_mutate_v1(('efa00000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'reserve_project_attachment',p);
 end loop;
 reset role;
 insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
 select ('dfa00000-0000-4000-8000-'||lpad(row_number() over(order by id)::text,12,'0'))::uuid,'rm-documentos',object_path,
  jsonb_build_object('size',byte_size,'mimetype',mime_type),jsonb_build_object('sha256',sha256)
 from rm_private.project_attachment_uploads where projeto_id='5fa00000-0000-4000-8000-000000000001';
 set local role authenticated;
 perform public.rm_web_mutate_v1('cfa00000-0000-4000-8000-000000000001','finalize_project_attachment',
  '{"projeto_id":"5fa00000-0000-4000-8000-000000000001","upload_id":"cfa00000-0000-4000-8000-000000000001"}');
 reset role;
end $$;
do $$ declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
 where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private'
  or ns.nspname='storage' and c.relname in('buckets','objects')) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into search_upgrade_snapshots values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 if (select count(*) from search_upgrade_snapshots)<>73 then raise exception 'FAIL: expected71 old RM tables plus2 Storage tables'; end if;
 insert into search_upgrade_policies select schemaname||'.'||tablename||'.'||policyname,to_jsonb(p) from pg_policies p where schemaname in('storage','public');
 insert into search_upgrade_functions select p.oid,pg_get_functiondef(p.oid),p.proacl from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='rm_private' or ns.nspname='public' and p.proname like 'rm\_%' escape '\';
end $$;
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_030_path'));begin
 if (select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1
  or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'FAIL: unexpected030 source transaction wrappers'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end $$;
do $$ declare t record;n bigint;h text;r jsonb;p jsonb;begin
 for t in select * from search_upgrade_snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL:030 installation changed old rows: %',t.name; end if;
 end loop;
 for t in select * from search_upgrade_policies loop
  if not exists(select 1 from pg_policies pol where pol.schemaname||'.'||pol.tablename||'.'||pol.policyname=t.name and to_jsonb(pol)=t.definition)
   then raise exception 'FAIL: old policy changed: %',t.name; end if;
 end loop;
 for t in select * from search_upgrade_functions loop
  if not exists(select 1 from pg_proc x where x.oid=t.id and pg_get_functiondef(x.oid)=t.definition and x.proacl is not distinct from t.acl)
   then raise exception 'FAIL: old function or grants changed: %',t.id; end if;
 end loop;
 set local role authenticated;
 r:=public.rm_web_project_comments_v1('5fa00000-0000-4000-8000-000000000001');
 if(r->>'total')::int<>2 then raise exception 'FAIL: old web/mobile comment history unavailable';end if;
 r:=public.rm_web_project_documents_v1('5fa00000-0000-4000-8000-000000000001');
 if(r->>'total')::int<>2 or exists(select 1 from jsonb_array_elements(r->'items') x where x->>'id'='cfa00000-0000-4000-8000-000000000002')
 then raise exception 'FAIL: private pending upload leaked or old/generated/finalized documents changed';end if;
 reset role;
 for t in select * from rm_private.web_mutation_receipts where auth_user_id='1fa00000-0000-4000-8000-000000000001' loop
  set local role authenticated;r:=public.rm_web_mutate_v1(t.client_submission_id,t.operation,t.payload);reset role;
  if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old web receipt %',t.operation;end if;
 end loop;
 select params into p from rm_private.mobile_mutation_receipts where client_submission_id='ffa00000-0000-4000-8000-000000000001';
 set local role authenticated;r:=public.rm_mobile_mutate_v1('ffa00000-0000-4000-8000-000000000001','rm_add_cell_comment_v1',p,'search-upgrade-mobile');reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed mobile receipt';end if;
end $$;
rollback;
\ir ../migrations/030_rm_web_project_dossier_search.sql
select 'PASS:030 preserves71 RM tables plus Storage, every old policy/function/grant, pending/private artifacts and warmed web/mobile receipts' as result;

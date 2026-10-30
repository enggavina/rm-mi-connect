-- TEST DATABASE ONLY: exact 031 -> 032 source with warmed legacy writers.
\set ON_ERROR_STOP on
\if :{?rm_migration_032_path}
\else
\echo 'Run the isolated SQL runner: absolute migration031 path is required.'
\quit 3
\endif
select set_config('rm.test.migration_032_path',:'rm_migration_032_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create temporary table comment_revision_upgrade_snapshots(name text primary key,rows bigint,hash text);
create temporary table comment_revision_upgrade_policies(name text primary key,definition jsonb);
create temporary table comment_revision_upgrade_functions(id oid primary key,definition text,acl aclitem[]);
insert into auth.users(id) values('1fb31000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2fb31000-0000-4000-8000-000000000001','1fb31000-0000-4000-8000-000000000001','Equipment upgrade actor','administrador');
select set_config('request.jwt.claim.sub','1fb31000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('equipment-upgrade-mobile','sha256'),'1fb31000-0000-4000-8000-000000000001','2fb31000-0000-4000-8000-000000000001','2fb31000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into public.rm_clientes(id,nome) values('4fb31000-0000-4000-8000-000000000001','Equipment upgrade client');
insert into public.rm_projetos(id,numero,cliente_id) values('5fb31000-0000-4000-8000-000000000001','EQUIPMENT-UPGRADE-31','4fb31000-0000-4000-8000-000000000001');
insert into public.rm_equipamentos(id,projeto_id,descricao,potencia,fp,numero_cabos,desmontar_para_orcar,bubble_id,sync_source)
 values('6fb31000-0000-4000-8000-000000000001','5fb31000-0000-4000-8000-000000000001','Legacy exact description','["55 kW","75 kW"]',1.23000000000000000001,-7,'sim','legacy-equipment-upgrade','bubble');
update public.rm_projetos set equipamento_id='6fb31000-0000-4000-8000-000000000001' where id='5fb31000-0000-4000-8000-000000000001';
-- Compile and exercise the existing core and the receipt update path before DDL.
do $$ declare p jsonb; begin
 p:=jsonb_build_object('projeto_id','5fb31000-0000-4000-8000-000000000001','expected_updated_at',
 (select updated_at from public.rm_projetos where id='5fb31000-0000-4000-8000-000000000001'),'numero','EQUIPMENT-UPGRADE-31','nome','Original web name',
 'cliente_id','4fb31000-0000-4000-8000-000000000001','tipo_equipamento_id',null,'status_pcp',null,'data_prevista_de_entrega',null,'data_real_de_entrega',null,'eventualidades',null);
 -- Warm via an existing additive dossier command, whose exact payload is stable.
 insert into public.rm_celulas(id,nome) values('afb31000-0000-4000-8000-000000000001','Equipment upgrade cell');
 insert into public.rm_celulas_projeto(id,projeto_id,celula_id) values('bfb31000-0000-4000-8000-000000000001','5fb31000-0000-4000-8000-000000000001','afb31000-0000-4000-8000-000000000001');
 p:=jsonb_build_object('projeto_id','5fb31000-0000-4000-8000-000000000001','celula_projeto_id','bfb31000-0000-4000-8000-000000000001',
 'expected_project_updated_at',(select updated_at from public.rm_projetos where id='5fb31000-0000-4000-8000-000000000001'),
 'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id='bfb31000-0000-4000-8000-000000000001'),'evento','Original legacy web comment');
 set local role authenticated;
 perform public.rm_web_mutate_v1('ffb31000-0000-4000-8000-000000000001','add_project_comment',p);
 perform public.rm_mobile_mutate_v1('ffb31000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',
 '{"p_projeto_id":"5fb31000-0000-4000-8000-000000000001","p_cliente_id":"4fb31000-0000-4000-8000-000000000001","p_equipamento":{"descricao":"Legacy exact description"}}','equipment-upgrade-mobile');
 reset role;
end $$;
do $$ declare t record; n bigint; h text; begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r'
 and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into comment_revision_upgrade_snapshots values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 if (select count(*) from comment_revision_upgrade_snapshots)<>74 then raise exception 'FAIL: expected72 old RM tables plus2 Storage tables'; end if;
 insert into comment_revision_upgrade_policies select schemaname||'.'||tablename||'.'||policyname,to_jsonb(p) from pg_policies p where schemaname in('storage','public');
 insert into comment_revision_upgrade_functions select p.oid,pg_get_functiondef(p.oid),p.proacl from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname in('public','rm_private') and (ns.nspname='rm_private' or p.proname like 'rm\_%' escape '\')
 and p.proname not in('web_mutate_core_v1','rm_sso_action_permit_v1');
end $$;
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_032_path')); begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1
 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'FAIL: unexpected032 source wrappers'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n',''); source:=regexp_replace(source,'(?m)^commit;\s*$',''); execute source;
end $$;
do $$ declare t record; n bigint; h text; p jsonb; s jsonb; r jsonb; begin
 for t in select * from comment_revision_upgrade_snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL:032 installation changed old rows: %',t.name; end if;
 end loop;
 if exists(select 1 from rm_private.project_comment_revisions) then raise exception 'FAIL: invented equipment edit history'; end if;
 for t in select * from comment_revision_upgrade_policies loop
  if not exists(select 1 from pg_policies pol where pol.schemaname||'.'||pol.tablename||'.'||pol.policyname=t.name and to_jsonb(pol)=t.definition)
   then raise exception 'FAIL: old policy changed %',t.name; end if;
 end loop;
 for t in select * from comment_revision_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and pg_get_functiondef(p.oid)=t.definition and p.proacl is not distinct from t.acl)
   then raise exception 'FAIL: unrelated function changed %',t.id::regprocedure; end if;
 end loop;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='ffb31000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('ffb31000-0000-4000-8000-000000000001','add_project_comment',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed web receipt'; end if;
 select params into p from rm_private.mobile_mutation_receipts where client_submission_id='ffb31000-0000-4000-8000-000000000002';
 set local role authenticated; r:=public.rm_mobile_mutate_v1('ffb31000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',p,'equipment-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed mobile receipt'; end if;
 s:=public.rm_web_project_comment_snapshot_v1('5fb31000-0000-4000-8000-000000000001','ffb31000-0000-4000-8000-000000000001',1);
 p:=jsonb_build_object('projeto_id',s->'project'->>'id','comentario_id',s->'comment'->>'id',
 'expected_project_updated_at',s->'project'->>'updated_at','expected_comment_updated_at',s->'comment'->>'updated_at',
 'expected_context_version',s->>'context_version','confirm_change',true,'evento','New032 corrected comment','motivo','Verified upgrade');
 set local role authenticated; r:=public.rm_web_mutate_v1('ffb31000-0000-4000-8000-000000000003','edit_project_comment',p); reset role;
 if r->>'id'<>'ffb31000-0000-4000-8000-000000000001' then raise exception 'FAIL: warmed dispatcher bypassed032'; end if;
 select params into p from rm_private.mobile_mutation_receipts where client_submission_id='ffb31000-0000-4000-8000-000000000002';
 set local role authenticated; r:=public.rm_mobile_mutate_v1('ffb31000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',p,'equipment-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: completed receiving receipt after new equipment edit'; end if;
 if(select count(*) from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private'))<>73 then raise exception 'FAIL: unexpected032 schema'; end if;
end $$;
rollback;
\ir ../migrations/032_rm_web_project_comment_revisions.sql
select 'PASS:032 preserves72 old RM tables, Storage, all policies, unrelated functions and warmed web/mobile receipts' as result;

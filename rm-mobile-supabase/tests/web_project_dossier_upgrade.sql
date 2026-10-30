-- TEST DATABASE ONLY: additive 028 -> 029 with warmed web/mobile receipts.
\set ON_ERROR_STOP on
\if :{?rm_migration_029_path}
\else
\echo 'Run the isolated SQL runner: absolute migration029 path is required.'
\quit 3
\endif
select set_config('rm.test.migration_029_path',:'rm_migration_029_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create temporary table dossier_upgrade_snapshots(name text primary key,rows bigint,hash text);
create temporary table dossier_upgrade_policies(name text primary key,definition jsonb);
insert into auth.users(id) values('1e900000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2e900000-0000-4000-8000-000000000001','1e900000-0000-4000-8000-000000000001','Dossier upgrade actor','administrador');
select set_config('request.jwt.claim.sub','1e900000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('dossier-upgrade-mobile','sha256'),'1e900000-0000-4000-8000-000000000001','2e900000-0000-4000-8000-000000000001','2e900000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into public.rm_projetos(id,numero) values('5e900000-0000-4000-8000-000000000001','DOSSIER-UPGRADE-29');
insert into public.rm_celulas(id,nome) values('4e900000-0000-4000-8000-000000000001','Warm dossier recipient');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,posicao,indice)
 values('6e900000-0000-4000-8000-000000000001','5e900000-0000-4000-8000-000000000001','4e900000-0000-4000-8000-000000000001',false,41,19);
insert into public.rm_tablet_celula_users(celula_id,identidade_id) values('4e900000-0000-4000-8000-000000000001','2e900000-0000-4000-8000-000000000001');
insert into public.rm_docs(id,projeto_id,nome,arquivo_url,status,data_vencimento)
 values('be900000-0000-4000-8000-000000000001','5e900000-0000-4000-8000-000000000001','Legacy project file','https://example.cdn.bubble.io/legacy-upgrade.pdf','Legacy free text','2026-10-20T08:45:01.123456Z');
insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
 values('ee900000-0000-4000-8000-000000000001','rm-documentos','1e900000-0000-4000-8000-000000000001/legacy-upgrade.pdf','{"size":5,"mimetype":"application/pdf"}','{"original":"preserved"}');
do $$ declare s jsonb; p jsonb; begin
 s:=public.rm_web_cell_availability_snapshot_v1('5e900000-0000-4000-8000-000000000001','6e900000-0000-4000-8000-000000000001');
 p:=jsonb_build_object('action','set_visibility','projeto_id',s->'project'->>'id','celula_projeto_id',s->'allocation'->>'id',
 'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','visibilidade',false,'confirm_change',true);
 set local role authenticated;
 perform public.rm_web_mutate_v1('fe900000-0000-4000-8000-000000000001','manage_cell_availability',p);
 perform public.rm_mobile_mutate_v1('fe900000-0000-4000-8000-000000000002','rm_add_cell_comment_v1',
 '{"p_celula_projeto_id":"6e900000-0000-4000-8000-000000000001","p_comentario":"Keep original mobile history and receipt"}','dossier-upgrade-mobile');
 reset role;
end $$;
do $$ declare t record; n bigint; h text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind='r' and (((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private')
 or (n.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into dossier_upgrade_snapshots values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 if (select count(*) from dossier_upgrade_snapshots)<>72 then raise exception 'FAIL: expected70 old RM tables plus2 Storage tables'; end if;
 insert into dossier_upgrade_policies select schemaname||'.'||tablename||'.'||policyname,to_jsonb(p) from pg_policies p where schemaname in('storage','public');
end $$;
-- Execute the exact new source within this disposable fixture transaction, then
-- roll everything back rather than bypassing protected allocation/doc DELETE.
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_029_path')); begin
 if (select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1
  or (select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'FAIL: unexpected029 source transaction wrappers'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');
 source:=regexp_replace(source,'(?m)^commit;\s*$','');
 execute source;
end $$;
do $$ declare t record; n bigint; h text; p jsonb; r jsonb; begin
 for t in select * from dossier_upgrade_snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL:029 installation changed old rows: %',t.name; end if;
 end loop;
 if exists(select 1 from rm_private.project_attachment_uploads) then raise exception 'FAIL: invented uploads or attachment history'; end if;
 for t in select * from dossier_upgrade_policies loop
  if not exists(select 1 from pg_policies pol where pol.schemaname||'.'||pol.tablename||'.'||pol.policyname=t.name and to_jsonb(pol)=t.definition)
   then raise exception 'FAIL: old read/write policy changed: %',t.name; end if;
 end loop;
 if (select count(*) from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r'
  and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private'))<>71 then raise exception 'FAIL: unexpected029 schema'; end if;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fe900000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fe900000-0000-4000-8000-000000000001','manage_cell_availability',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old web receipt'; end if;
 select params into p from rm_private.mobile_mutation_receipts where client_submission_id='fe900000-0000-4000-8000-000000000002';
 set local role authenticated; r:=public.rm_mobile_mutate_v1('fe900000-0000-4000-8000-000000000002','rm_add_cell_comment_v1',p,'dossier-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old mobile receipt'; end if;
 p:=jsonb_build_object('projeto_id','5e900000-0000-4000-8000-000000000001','celula_projeto_id','6e900000-0000-4000-8000-000000000001',
  'expected_project_updated_at',(select updated_at from public.rm_projetos where id='5e900000-0000-4000-8000-000000000001'),
  'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id='6e900000-0000-4000-8000-000000000001'),'evento','New web comment without reclassifying mobile history');
 set local role authenticated; r:=public.rm_web_mutate_v1('fe900000-0000-4000-8000-000000000003','add_project_comment',p); reset role;
 if r->>'id'<>'fe900000-0000-4000-8000-000000000003' then raise exception 'FAIL: warmed dispatcher bypassed029'; end if;
 update public.rm_projetos set status_pcp='cancelado' where id='5e900000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fe900000-0000-4000-8000-000000000003','add_project_comment',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: closed project blocked completed comment receipt'; end if;
 select params into p from rm_private.mobile_mutation_receipts where client_submission_id='fe900000-0000-4000-8000-000000000002';
 set local role authenticated; r:=public.rm_mobile_mutate_v1('fe900000-0000-4000-8000-000000000002','rm_add_cell_comment_v1',p,'dossier-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: completed offline receipt changed'; end if;
end $$;
rollback;
\ir ../migrations/029_rm_web_project_dossier.sql
select 'PASS:029 preserves70 old RM tables plus Storage, all legacy policies and warmed web/mobile receipts; no upload/doc data fabricated' as result;

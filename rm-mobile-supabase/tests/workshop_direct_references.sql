\set ON_ERROR_STOP on
begin;
create function pg_temp.wr_id(n int) returns uuid language sql immutable as $$select ('05500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.wr_check(v boolean,msg text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.wr_deny(statement text,state text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlstate=state then return;end if;raise;end;
 raise exception 'FAIL: operation accepted: %',statement;end$$;
insert into public.rm_projetos(id,nome) values(pg_temp.wr_id(11),'LOCAL BMA project');
insert into public.rm_celulas(id,nome) values(pg_temp.wr_id(12),'LOCAL BMA cell');
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"05500000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05500000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05500000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into public.rm_projetos(id,nome) select pg_temp.wr_id(n),'LOCAL later project' from unnest(array[21,31,41]) n;
insert into public.rm_celulas(id,nome) select pg_temp.wr_id(n),'LOCAL later cell' from unnest(array[22,32,42]) n;
insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.wr_id(21),pg_temp.wr_id(2));
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wr_id(22),pg_temp.wr_id(2));
insert into auth.users(id) values(pg_temp.wr_id(90));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.wr_id(91),pg_temp.wr_id(90),'LOCAL references administrator','administrador','ativo');
insert into public.rm_forms(id,titulo) values(pg_temp.wr_id(50),'LOCAL shared legacy form');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id) values(pg_temp.wr_id(51),pg_temp.wr_id(11),pg_temp.wr_id(12)),(pg_temp.wr_id(52),pg_temp.wr_id(21),pg_temp.wr_id(22));
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id) values(pg_temp.wr_id(53),pg_temp.wr_id(11),pg_temp.wr_id(12),pg_temp.wr_id(50));
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id) values(pg_temp.wr_id(54),pg_temp.wr_id(11),pg_temp.wr_id(51),pg_temp.wr_id(12),pg_temp.wr_id(12));
insert into public.rm_logs_aprovacao(id,projeto_id,celula_id,status_aprovacao) values(pg_temp.wr_id(55),pg_temp.wr_id(11),pg_temp.wr_id(12),'nulo');

-- Every configured public table rejects the crossed pair BEFORE FK checks.
-- Positive controls use all original constraints and are rolled back locally.
do $$declare item record;statement text;begin
 for item in select * from(values
  ('rm_celulas_projeto','projeto_id,celula_id','$1,$2'),
  ('rm_fotos','projeto_id,celula_id','$1,$2'),
  ('rm_comentarios','projeto_id,celula_id,evento','$1,$2,''LOCAL reference'''),
  ('rm_registros_formulario','projeto_id,celula_id,form_id','$1,$2,$3'),
  ('rm_logs_aprovacao','projeto_id,celula_id,status_aprovacao','$1,$2,''nulo'''),
  ('rm_aprovacoes_registro','projeto_id,celula_id,registro_formulario_id','$1,$2,$4'),
  ('rm_form_reviewer_assignments','projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id','$1,$2,$5,$3,$6'),
  ('rm_web_stage_decisions','projeto_id,celula_id,celula_projeto_id,aprovacao_etapa_id,actor_id,acao,status_novo,log_id,client_submission_id','$1,$2,$5,$7,$6,''liberar'',''nulo'',$8,gen_random_uuid()')
 ) v(tbl,cols,vals) loop
  statement:=format('insert into public.%I(%s) values(%s)',item.tbl,item.cols,item.vals);
  begin
   execute statement using pg_temp.wr_id(11),pg_temp.wr_id(22),pg_temp.wr_id(50),pg_temp.wr_id(53),pg_temp.wr_id(51),pg_temp.wr_id(91),pg_temp.wr_id(54),pg_temp.wr_id(55);
   raise exception 'FAIL: cross-office insert in % accepted',item.tbl;
  exception when sqlstate 'PT409' then null;
   when sqlstate '22023' then
    -- Existing allocation-context guards execute first on these two tables.
    if item.tbl not in('rm_form_reviewer_assignments','rm_web_stage_decisions') then raise;end if;
  end;
  if item.tbl<>'rm_celulas_projeto' then begin
   execute statement using pg_temp.wr_id(11),pg_temp.wr_id(12),pg_temp.wr_id(50),pg_temp.wr_id(53),pg_temp.wr_id(51),pg_temp.wr_id(91),pg_temp.wr_id(54),pg_temp.wr_id(55);
   raise exception using errcode='Z0001',message='Rollback successful control';
  exception when sqlstate 'Z0001' then null;end;end if;
 end loop;
end$$;
select pg_temp.wr_deny('insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id,celula_destino_id) values(pg_temp.wr_id(11),pg_temp.wr_id(12),pg_temp.wr_id(22))','PT409');
select pg_temp.wr_deny('insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id,celula_destino_id) values(pg_temp.wr_id(11),pg_temp.wr_id(22),pg_temp.wr_id(12))','PT409');
select pg_temp.wr_deny('update public.rm_celulas_projeto set celula_id=pg_temp.wr_id(22) where id=pg_temp.wr_id(51)','22023');
insert into public.rm_comentarios(id,projeto_id,celula_id,evento) values(pg_temp.wr_id(60),pg_temp.wr_id(11),pg_temp.wr_id(12),'LOCAL original pair');
select pg_temp.wr_deny('update public.rm_comentarios set celula_id=pg_temp.wr_id(22) where id=pg_temp.wr_id(60)','PT409');

-- Neither INSERT nor later classification may silently infer an office.
insert into public.rm_celulas_projeto(projeto_id,celula_id) values(pg_temp.wr_id(31),pg_temp.wr_id(12));
insert into public.rm_comentarios(projeto_id,celula_id,evento) values(pg_temp.wr_id(11),pg_temp.wr_id(32),'LOCAL unknown cell'),(pg_temp.wr_id(41),pg_temp.wr_id(42),'LOCAL unknown roots');
select pg_temp.wr_check(not exists(select 1 from rm_private.workshop_project_ownership where id=pg_temp.wr_id(31)) and not exists(select 1 from rm_private.workshop_cell_ownership where cell_id=pg_temp.wr_id(32)),'unknown references remain unclassified');
select pg_temp.wr_check((rm_private.workshop_reference_readiness_v1()->>'pending')::bigint>=3,'pending references reported honestly');
select pg_temp.wr_deny('insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.wr_id(31),pg_temp.wr_id(2))','PT409');
select pg_temp.wr_deny('insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wr_id(32),pg_temp.wr_id(2))','PT409');
select pg_temp.wr_check(not exists(select 1 from rm_private.workshop_object_origins where object_id in(pg_temp.wr_id(31),pg_temp.wr_id(32))),'failed classification rolls back its origin metadata');
insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.wr_id(31),pg_temp.wr_id(1)),(pg_temp.wr_id(41),pg_temp.wr_id(2));
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wr_id(32),pg_temp.wr_id(1));
select pg_temp.wr_deny('insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wr_id(42),pg_temp.wr_id(1))','PT409');
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wr_id(42),pg_temp.wr_id(2));
-- Existing nullable/template meanings remain, without ownership assignment.
insert into public.rm_fotos(celula_id) values(pg_temp.wr_id(22));
insert into public.rm_comentarios(projeto_id,evento) values(pg_temp.wr_id(11),'LOCAL project comment');

update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub',pg_temp.wr_id(90)::text,true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
set local role authenticated;
-- The current API owns writes; do not invent table grants just for this test.
select pg_temp.wr_deny('insert into public.rm_comentarios(projeto_id,celula_id) values(pg_temp.wr_id(11),pg_temp.wr_id(22))','42501');
do $$declare snapshot jsonb;result jsonb;begin
 result:=public.rm_web_mutate_v1(pg_temp.wr_id(92),'add_project_comment',jsonb_build_object('projeto_id',pg_temp.wr_id(11),
  'celula_projeto_id',pg_temp.wr_id(51),'evento','LOCAL authenticated API comment',
  'expected_project_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.wr_id(11)),
  'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.wr_id(51))));
 if result->'record'->>'comment_id'<>pg_temp.wr_id(92)::text then raise exception 'FAIL: authenticated comment API failed';end if;
 snapshot:=public.rm_web_project_delete_snapshot_v1(pg_temp.wr_id(11));
 if snapshot->>'can_delete'<>'true' then raise exception 'FAIL: direct reference guards block existing deletion';end if;
 result:=public.rm_web_mutate_v1(pg_temp.wr_id(99),'delete_project',jsonb_build_object('id',pg_temp.wr_id(11),
  'expected_updated_at',snapshot->'project'->>'updated_at','expected_context_version',snapshot->>'context_version',
  'confirm_delete',true,'justificativa','LOCAL guarded project deletion'));
 if result->'record'->>'deleted'<>'true' then raise exception 'FAIL: authenticated deletion failed';end if;
end$$;
reset role;
delete from rm_private.workshop_project_ownership where id=pg_temp.wr_id(21);
select pg_temp.wr_deny('insert into public.rm_comentarios(projeto_id,celula_id) values(pg_temp.wr_id(21),pg_temp.wr_id(22))','PT410');
update public.rm_celulas_projeto set observacao='LOCAL unchanged reference remains editable' where id=pg_temp.wr_id(52);
select pg_temp.wr_check((rm_private.workshop_reference_readiness_v1()->>'conflicts')::bigint=0,'no classified cross-office pair');
select pg_temp.wr_check(not (rm_private.workshop_reference_readiness_v1()->>'isolation_active')::boolean,'direct integrity is not complete isolation');
do $$declare role_name text;fn regprocedure;begin
 for fn in select p.oid::regprocedure from pg_proc p where p.pronamespace='rm_private'::regnamespace and p.proname in(
  'workshop_reference_relations_v1','workshop_reference_pair_v1','workshop_guard_reference_v1','workshop_guard_root_references_v1','workshop_reference_readiness_v1') loop
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_function_privilege(role_name,fn,'EXECUTE') then raise exception 'FAIL: private guard exposed';end if;
  end loop;
 end loop;
end$$;
rollback;
\echo PASS: direct workshop references, all tables, source/destination, classification, unknown roots, authenticated writes and offline retirement.

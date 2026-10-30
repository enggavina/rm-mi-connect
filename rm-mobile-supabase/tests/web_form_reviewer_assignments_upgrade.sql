-- TEST DATABASE ONLY: 025 -> 026 preserves all 67 old tables and warms callers.
\set ON_ERROR_STOP on
begin;
create schema rm_test_reviewer_upgrade;
create table rm_test_reviewer_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1c800000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2c800000-0000-4000-8000-000000000001','1c800000-0000-4000-8000-000000000001','Reviewer upgrade planner','administrador');
insert into public.rm_users(id,nome) values('2c800000-0000-4000-8000-000000000002','Real linked reviewer');
insert into public.rm_projetos(id,numero) values('5c800000-0000-4000-8000-000000000001','REVIEWER-UPGRADE-26');
insert into public.rm_celulas(id,nome) values('4c800000-0000-4000-8000-000000000001','Reviewer upgrade cell');
insert into public.rm_forms(id,titulo) values('ac800000-0000-4000-8000-000000000001','Reviewer upgrade form');
insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) values('bc800000-0000-4000-8000-000000000001','ac800000-0000-4000-8000-000000000001','Original question','texto_curto',true);
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids) values('6c800000-0000-4000-8000-000000000001','5c800000-0000-4000-8000-000000000001','4c800000-0000-4000-8000-000000000001',array['ac800000-0000-4000-8000-000000000001']::uuid[]);
insert into public.rm_tablet_celula_users(celula_id,identidade_id) values('4c800000-0000-4000-8000-000000000001','2c800000-0000-4000-8000-000000000002');
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id) values('cc800000-0000-4000-8000-000000000001','5c800000-0000-4000-8000-000000000001','4c800000-0000-4000-8000-000000000001','ac800000-0000-4000-8000-000000000001');
insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta) values('dc800000-0000-4000-8000-000000000001','cc800000-0000-4000-8000-000000000001','bc800000-0000-4000-8000-000000000001','Original answer');
select set_config('request.jwt.claim.sub','1c800000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('reviewer-upgrade-mobile','sha256'),'1c800000-0000-4000-8000-000000000001','2c800000-0000-4000-8000-000000000001','2c800000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
do $$ declare p jsonb; begin
 p:=jsonb_build_object('registro_formulario_id','cc800000-0000-4000-8000-000000000001','expected_updated_at',(select updated_at from public.rm_registros_formulario where id='cc800000-0000-4000-8000-000000000001'),
  'decision','return','parecer','Original return','resposta_ids',jsonb_build_array('dc800000-0000-4000-8000-000000000001'));
 set local role authenticated; perform public.rm_web_mutate_v1('fc800000-0000-4000-8000-000000000001','review_form',p);
 perform public.rm_mobile_mutate_v1('fc800000-0000-4000-8000-000000000002','rm_submit_form_revision_v1',
  '{"p_registro_formulario_id":"cc800000-0000-4000-8000-000000000001","p_respostas_corrigidas":[{"questao_id":"bc800000-0000-4000-8000-000000000001","resposta":"Old correction"}]}','reviewer-upgrade-mobile');
 perform public.rm_mobile_mutate_v1('fc800000-0000-4000-8000-000000000003','rm_submit_form_inspection_v1',
  '{"p_projeto_id":"5c800000-0000-4000-8000-000000000001","p_celula_id":"4c800000-0000-4000-8000-000000000001","p_form_id":"ac800000-0000-4000-8000-000000000001","p_respostas":[{"questao_id":"bc800000-0000-4000-8000-000000000001","resposta":"Old offline"}]}','reviewer-upgrade-mobile'); reset role;
end $$;
do $$ declare t record; total bigint; digest text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname) into total,digest;
  insert into rm_test_reviewer_upgrade.snapshots values(t.nspname||'.'||t.relname,total,digest);
 end loop;
 if (select count(*) from rm_test_reviewer_upgrade.snapshots)<>67 then raise exception 'FAIL: expected all 67 preexisting RM/private tables'; end if;
 if to_regprocedure('rm_private.web_mutate_operational_photos_core_v1(uuid,text,jsonb)') is not null then raise exception 'FAIL: predecessor name occupied'; end if;
end $$;
commit;
\ir ../migrations/026_rm_web_form_reviewer_assignments.sql
begin;
do $$ declare t record; total bigint; digest text; p jsonb; r jsonb; s jsonb; form_snapshot jsonb; old_rows jsonb; begin
 for t in select * from rm_test_reviewer_upgrade.snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name) into total,digest;
  if total<>t.rows or digest<>t.hash then raise exception 'FAIL:026 installation changed existing rows: %',t.name; end if;
 end loop;
 if exists(select 1 from public.rm_form_reviewer_assignments) then raise exception 'FAIL:026 invented historical designation'; end if;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fc800000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fc800000-0000-4000-8000-000000000001','review_form',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: old warm review receipt'; end if;
 s:=public.rm_web_form_reviewer_assignments_snapshot_v1('5c800000-0000-4000-8000-000000000001','6c800000-0000-4000-8000-000000000001',true); form_snapshot:=s->'forms'->0;
 p:=jsonb_build_object('projeto_id',s->'project'->>'id','celula_projeto_id',s->'allocation'->>'id','form_id',form_snapshot->>'id','avaliador_user_id','2c800000-0000-4000-8000-000000000002',
  'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',form_snapshot->>'context_version','confirm_replace',true);
 set local role authenticated; r:=public.rm_web_mutate_v1('fc800000-0000-4000-8000-000000000004','assign_form_reviewer',p); reset role;
 if r->>'operation'<>'assign_form_reviewer' or jsonb_array_length(r->'record'->'records_updated_ids')<>2 then raise exception 'FAIL: warm web wrapper missed new assignment dispatcher'; end if;
 select jsonb_agg(to_jsonb(q) order by id) into old_rows from public.rm_registros_formulario q where projeto_id='5c800000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fc800000-0000-4000-8000-000000000004','assign_form_reviewer',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: new warm assignment replay'; end if;
 set local role authenticated;
 r:=public.rm_mobile_mutate_v1('fc800000-0000-4000-8000-000000000003','rm_submit_form_inspection_v1',
  '{"p_projeto_id":"5c800000-0000-4000-8000-000000000001","p_celula_id":"4c800000-0000-4000-8000-000000000001","p_form_id":"ac800000-0000-4000-8000-000000000001","p_respostas":[{"questao_id":"bc800000-0000-4000-8000-000000000001","resposta":"Old offline"}]}','reviewer-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean or old_rows is distinct from (select jsonb_agg(to_jsonb(q) order by id) from public.rm_registros_formulario q where projeto_id='5c800000-0000-4000-8000-000000000001') then raise exception 'FAIL: old offline receipt reapplied designation'; end if;
 set local role authenticated;
 r:=public.rm_mobile_mutate_v1('fc800000-0000-4000-8000-000000000005','rm_submit_form_inspection_v1',
  '{"p_projeto_id":"5c800000-0000-4000-8000-000000000001","p_celula_id":"4c800000-0000-4000-8000-000000000001","p_form_id":"ac800000-0000-4000-8000-000000000001","p_respostas":[{"questao_id":"bc800000-0000-4000-8000-000000000001","resposta":"New offline"}]}','reviewer-upgrade-mobile'); reset role;
 if not exists(select 1 from public.rm_registros_formulario where id=(r->>'registro_formulario_id')::uuid and avaliador_user_id='2c800000-0000-4000-8000-000000000002') then raise exception 'FAIL: warm inspection missed inherited evaluator'; end if;
 p:=jsonb_build_object('registro_formulario_id','cc800000-0000-4000-8000-000000000001','expected_updated_at',(select updated_at from public.rm_registros_formulario where id='cc800000-0000-4000-8000-000000000001'),
  'decision','return','parecer','New return','resposta_ids',jsonb_build_array('dc800000-0000-4000-8000-000000000001'));
 set local role authenticated; perform public.rm_web_mutate_v1('fc800000-0000-4000-8000-000000000006','review_form',p);
 perform public.rm_mobile_mutate_v1('fc800000-0000-4000-8000-000000000007','rm_submit_form_revision_v1',
  '{"p_registro_formulario_id":"cc800000-0000-4000-8000-000000000001","p_respostas_corrigidas":[{"questao_id":"bc800000-0000-4000-8000-000000000001","resposta":"New correction"}]}','reviewer-upgrade-mobile'); reset role;
 if not exists(select 1 from public.rm_registros_formulario where id='cc800000-0000-4000-8000-000000000001' and status='em_an_lise' and avaliador_user_id='2c800000-0000-4000-8000-000000000001') then raise exception 'FAIL: warm revision/review semantics changed'; end if;
end $$;
rollback;
begin;
delete from rm_private.mobile_mutation_receipts where auth_user_id='1c800000-0000-4000-8000-000000000001';
delete from rm_private.web_mutation_receipts where auth_user_id='1c800000-0000-4000-8000-000000000001';
delete from rm_private.operator_delegations where auth_user_id='1c800000-0000-4000-8000-000000000001';
delete from public.rm_aprovacoes_registro where projeto_id='5c800000-0000-4000-8000-000000000001';
delete from public.rm_respostas where registro_formulario_id in(select id from public.rm_registros_formulario where projeto_id='5c800000-0000-4000-8000-000000000001');
delete from public.rm_registros_formulario where projeto_id='5c800000-0000-4000-8000-000000000001';
delete from public.rm_celulas_projeto where projeto_id='5c800000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5c800000-0000-4000-8000-000000000001';
delete from public.rm_numeracoes where form_id='ac800000-0000-4000-8000-000000000001';
delete from public.rm_questoes where id='bc800000-0000-4000-8000-000000000001';
delete from public.rm_forms where id='ac800000-0000-4000-8000-000000000001';
delete from public.rm_tablet_celula_users where celula_id='4c800000-0000-4000-8000-000000000001';
delete from public.rm_celulas where id='4c800000-0000-4000-8000-000000000001';
delete from public.rm_users where id in('2c800000-0000-4000-8000-000000000001','2c800000-0000-4000-8000-000000000002');
delete from auth.users where id='1c800000-0000-4000-8000-000000000001';
drop schema rm_test_reviewer_upgrade cascade;
commit;
select 'PASS:026 preserves all67 old table snapshots, leaves new assignment table empty, retains exact old receipts and routes warmed web/mobile callers through assignment/inheritance/review/correction' as result;

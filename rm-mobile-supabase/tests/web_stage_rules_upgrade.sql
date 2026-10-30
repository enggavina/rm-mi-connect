-- TEST DATABASE ONLY: preserve68 complete old tables and warm old callers.
\set ON_ERROR_STOP on
begin;
create schema rm_test_stage_rules_upgrade;
create table rm_test_stage_rules_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1d800000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2d800000-0000-4000-8000-000000000001','1d800000-0000-4000-8000-000000000001','Stage rules upgrade actor','administrador');
select set_config('request.jwt.claim.sub','1d800000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('stage-rules-upgrade-mobile','sha256'),'1d800000-0000-4000-8000-000000000001','2d800000-0000-4000-8000-000000000001','2d800000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into public.rm_projetos(id,numero) values('5d800000-0000-4000-8000-000000000001','STAGE-RULE-UPGRADE-27');
insert into public.rm_celulas(id,nome) values('4d800000-0000-4000-8000-000000000001','Warm origin'),('4d800000-0000-4000-8000-000000000002','Warm destination');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) values('6d800000-0000-4000-8000-000000000001','5d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000001','em_dia'),
 ('6d800000-0000-4000-8000-000000000002','5d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000002','pendente');
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov)
 values('cd800000-0000-4000-8000-000000000001','5d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000002','em_dia',true);
do $$ declare p jsonb; r jsonb; reverse_id uuid; begin
 p:=jsonb_build_object('aprovacao_etapa_id','CD800000-0000-4000-8000-000000000001','expected_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id='cd800000-0000-4000-8000-000000000001'),
  'expected_cell_updated_at',(select updated_at from public.rm_celulas_projeto where id='6d800000-0000-4000-8000-000000000001'),'acao','liberar','observacao',null);
 set local role authenticated; perform public.rm_web_mutate_v1('fd800000-0000-4000-8000-000000000001','transition_stage_approval',p); reset role;
 select id into reverse_id from public.rm_aprovacoes_etapas where projeto_id='5d800000-0000-4000-8000-000000000001' and status_cel_proj='retornado';
 set local role authenticated; perform public.rm_mobile_mutate_v1('fd800000-0000-4000-8000-000000000002','rm_transition_stage_approval_v1',jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','aprovar'),'stage-rules-upgrade-mobile'); reset role;
end $$;
-- Before027 deletion was possible. Keep real completed receipts, remove their
-- fixture rows now, and prove replay and ID reservation after the new guard.
delete from public.rm_web_stage_decisions where projeto_id='5d800000-0000-4000-8000-000000000001';
delete from public.rm_logs_aprovacao where projeto_id='5d800000-0000-4000-8000-000000000001';
delete from public.rm_sync_outbox where payload->>'projeto_id'='5d800000-0000-4000-8000-000000000001';
delete from public.rm_aprovacoes_etapas where projeto_id='5d800000-0000-4000-8000-000000000001';
delete from public.rm_celulas_projeto where projeto_id='5d800000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5d800000-0000-4000-8000-000000000001';
delete from public.rm_celulas where id in('4d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000002');
do $$ declare t record; n bigint; h text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname) into n,h;
  insert into rm_test_stage_rules_upgrade.snapshots values(t.nspname||'.'||t.relname,n,h);
 end loop;
 if (select count(*) from rm_test_stage_rules_upgrade.snapshots)<>68 then raise exception 'FAIL: expected all68 existing tables'; end if;
end $$;
commit;
\ir ../migrations/027_rm_web_stage_rules.sql
begin;
do $$ declare t record; n bigint; h text; p jsonb; r jsonb; s jsonb; begin
 for t in select * from rm_test_stage_rules_upgrade.snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL:027 installation changed old rows: %',t.name; end if;
 end loop;
 if exists(select 1 from rm_private.stage_rule_events) then raise exception 'FAIL: invented journal/history'; end if;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fd800000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fd800000-0000-4000-8000-000000000001','transition_stage_approval',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old web receipt'; end if;
 select params into p from rm_private.mobile_mutation_receipts where client_submission_id='fd800000-0000-4000-8000-000000000002';
 set local role authenticated; r:=public.rm_mobile_mutate_v1('fd800000-0000-4000-8000-000000000002','rm_transition_stage_approval_v1',p,'stage-rules-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old mobile receipt'; end if;
 insert into public.rm_projetos(id,numero) values('5d800000-0000-4000-8000-000000000001','NEW-CONTEXT-27');
 insert into public.rm_celulas(id,nome) values('4d800000-0000-4000-8000-000000000001','New origin'),('4d800000-0000-4000-8000-000000000002','New destination');
 insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) values('6d800000-0000-4000-8000-000000000001','5d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000001','em_dia'),
  ('6d800000-0000-4000-8000-000000000002','5d800000-0000-4000-8000-000000000001','4d800000-0000-4000-8000-000000000002','pendente');
 insert into public.rm_tablet_celula_users(celula_id,identidade_id) values('4d800000-0000-4000-8000-000000000001','2d800000-0000-4000-8000-000000000001'),('4d800000-0000-4000-8000-000000000002','2d800000-0000-4000-8000-000000000001');
 s:=public.rm_web_stage_rules_snapshot_v1('5d800000-0000-4000-8000-000000000001','6d800000-0000-4000-8000-000000000001',true);
 p:=jsonb_build_object('action','create','id','cd800000-0000-4000-8000-000000000001','projeto_id',s->'project'->>'id','celula_projeto_id',s->'allocation'->>'id','expected_project_updated_at',s->'project'->>'updated_at',
  'expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_rules_version',s->>'rules_version','config',jsonb_build_object('celula_destino_id','4d800000-0000-4000-8000-000000000002','status_cel_proj','em_dia',
  'bloquear_avanco_sem_aprov',true,'aprovadores_ids',jsonb_build_array('2d800000-0000-4000-8000-000000000001'),'aprovadores_retorno_ids',jsonb_build_array('2d800000-0000-4000-8000-000000000001')));
 begin set local role authenticated; perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_stage_rules',p); raise exception 'FAIL: reused historical ID'; exception when invalid_parameter_value then reset role; end;
 p:=p||'{"id":"ed800000-0000-4000-8000-000000000001"}';
 set local role authenticated; r:=public.rm_web_mutate_v1('fd800000-0000-4000-8000-000000000003','manage_stage_rules',p); reset role;
 if r->>'id'<>'ed800000-0000-4000-8000-000000000001' then raise exception 'FAIL: warmed wrapper missed new command'; end if;
 set local role authenticated; r:=public.rm_web_mutate_v1('fd800000-0000-4000-8000-000000000003','manage_stage_rules',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: new command replay'; end if;
 set local role authenticated; r:=public.rm_mobile_mutate_v1('fd800000-0000-4000-8000-000000000004','rm_transition_stage_approval_v1','{"p_aprovacao_etapa_id":"ed800000-0000-4000-8000-000000000001","p_acao":"liberar"}','stage-rules-upgrade-mobile'); reset role;
 if (select count(*) from rm_private.stage_rule_events where action='use')<>2 then raise exception 'FAIL: warmed primitive missed irreversible use journal'; end if;
end $$;
rollback;
begin;
delete from rm_private.web_mutation_receipts where auth_user_id='1d800000-0000-4000-8000-000000000001';
delete from rm_private.mobile_mutation_receipts where auth_user_id='1d800000-0000-4000-8000-000000000001';
delete from rm_private.operator_delegations where auth_user_id='1d800000-0000-4000-8000-000000000001';
delete from public.rm_users where id='2d800000-0000-4000-8000-000000000001';
delete from auth.users where id='1d800000-0000-4000-8000-000000000001';
drop schema rm_test_stage_rules_upgrade cascade;
commit;
select 'PASS:027 preserves68 complete snapshots, creates empty journal, warmed web/mobile callers retain old receipts, reserve historical IDs and reach immutable configuration/use journal' as result;

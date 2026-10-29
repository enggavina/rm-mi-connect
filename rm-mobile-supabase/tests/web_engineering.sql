\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.call_engineering(rid uuid,op text,p jsonb,cap text default 'em.engineering.manage') returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform public.rm_sso_action_permit_v1(repeat('8',64),rid,op,p,cap);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.reject_engineering(op text,p jsonb,wanted text,cap text default 'em.engineering.manage') returns void language plpgsql as $$
declare actual text; begin
  begin perform pg_temp.call_engineering(gen_random_uuid(),op,p,cap);
  exception when others then get stacked diagnostics actual=returned_sqlstate;
    if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
  end; raise exception 'FAIL: engineering request unexpectedly succeeded';
end $$;
create function pg_temp.matrix_payload(changes jsonb) returns jsonb language sql as $$
  select jsonb_build_object('id','68000000-0000-4000-8000-000000000001','celula_id','48000000-0000-4000-8000-000000000001',
    'tipo_equipamento_id','58000000-0000-4000-8000-000000000001','expected_updated_at',
    (select updated_at from public.rm_celula_tipos_equipamento where id='68000000-0000-4000-8000-000000000001'),'changes',changes);
$$;
insert into auth.users(id) values('18000000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('28000000-0000-4000-8000-000000000001','18000000-0000-4000-8000-000000000001','Engineering admin fixture','administrador');
insert into public.rm_users(id,nome,perfil) values
 ('28000000-0000-4000-8000-000000000002','Origin approver fixture','padr_o'),
 ('28000000-0000-4000-8000-000000000003','Return approver fixture','padr_o');
insert into auth.sessions(id,user_id) values('38000000-0000-4000-8000-000000000001','18000000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('88000000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','98000000-0000-4000-8000-000000000001',
 '28000000-0000-4000-8000-000000000001','18000000-0000-4000-8000-000000000001',true,'28000000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('8',64),'88000000-0000-4000-8000-000000000001','38000000-0000-4000-8000-000000000001',
 'opaque-engineering-fixture-session',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','18000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"38000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select set_config('rm.test.engineering.outbox',(select count(*)::text from public.rm_sync_outbox),true);
insert into public.rm_celulas(id,nome) values
 ('48000000-0000-4000-8000-000000000001','Engineering origin'),('48000000-0000-4000-8000-000000000002','Engineering destination'),
 ('48000000-0000-4000-8000-000000000003','Engineering manual');
insert into public.rm_tipos_equipamento(id,nome) values('58000000-0000-4000-8000-000000000001','Engineering type');
insert into public.rm_tablet_celula_users(celula_id,identidade_id) values
 ('48000000-0000-4000-8000-000000000001','28000000-0000-4000-8000-000000000002'),
 ('48000000-0000-4000-8000-000000000002','28000000-0000-4000-8000-000000000003');
insert into public.rm_forms(id,titulo) values('78000000-0000-4000-8000-000000000001','Engineering form A'),('78000000-0000-4000-8000-000000000002','Engineering form B');
insert into public.rm_projetos(id,nome,tipo_equipamento_id) values('d8000000-0000-4000-8000-000000000009','Concurrent allocation fixture','58000000-0000-4000-8000-000000000001');

-- Concurrent real shared pair lock prevents a template creation before any
-- parent/child row is written; locks apply even when the pair does not yet exist.
create extension dblink;
do $lock_test$ begin
  perform dblink_connect('engineering_lock','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user='||current_user);
  perform dblink_exec('engineering_lock','begin');
  perform dblink_exec('engineering_lock',$remote$do $$ begin perform pg_advisory_xact_lock_shared(hashtextextended('48000000-0000-4000-8000-000000000001:58000000-0000-4000-8000-000000000001',18)); end $$;$remote$);
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload('{"visibilidade":true}'),'55P03');
  perform pg_temp.check(not exists(select 1 from public.rm_celula_tipos_equipamento where id='68000000-0000-4000-8000-000000000001'),'concurrent allocation lock blocks complete save before creation');
  perform dblink_exec('engineering_lock','rollback');
  perform dblink_exec('engineering_lock','begin');
  perform dblink_exec('engineering_lock',$remote$do $$ begin perform pg_advisory_xact_lock(hashtextextended('48000000-0000-4000-8000-000000000003:58000000-0000-4000-8000-000000000001',18)); end $$;$remote$);
  perform pg_temp.reject_engineering('plan_cell',jsonb_build_object('projeto_id','d8000000-0000-4000-8000-000000000009',
    'celula_id','48000000-0000-4000-8000-000000000003','expected_updated_at',null,'changes','{}'::jsonb),'55P03','em.planning.manage');
  perform pg_temp.check(not exists(select 1 from public.rm_celulas_projeto where projeto_id='d8000000-0000-4000-8000-000000000009'),'exclusive engineering writer prevents partial allocation');
  perform dblink_exec('engineering_lock','rollback'); perform dblink_disconnect('engineering_lock');
exception when others then
  if 'engineering_lock'=any(dblink_get_connections()) then perform dblink_exec('engineering_lock','rollback'); perform dblink_disconnect('engineering_lock'); end if; raise;
end $lock_test$;

-- Title scope and snapshots. No arbitrary URL/template/operational fields.
do $$ declare p jsonb; r jsonb; id uuid:='a8000000-0000-4000-8000-000000000001'; rid uuid:=gen_random_uuid(); begin
  p:=jsonb_build_object('id',id,'expected_updated_at',null,'changes',jsonb_build_object('titulo','  Registered title  ','celula_id','48000000-0000-4000-8000-000000000001','numero',2));
  r:=pg_temp.call_engineering(rid,'save_photo_title',p);
  perform pg_temp.check(r->'record'->>'titulo'='Registered title' and r->'record'->>'celula_nome'='Engineering origin','scoped title creation');
  perform pg_temp.check((pg_temp.call_engineering(rid,'save_photo_title',p)->>'idempotent_replay')::bool,'title replay');
  perform pg_temp.reject_engineering('save_photo_title',jsonb_build_object('id',id,'expected_updated_at',r->>'updated_at','changes',jsonb_build_object('celula_id',null)),'22023');
  perform pg_temp.reject_engineering('save_photo_title',jsonb_build_object('id',gen_random_uuid(),'expected_updated_at',null,'changes',jsonb_build_object('titulo','Missing scope')),'22023');
  perform pg_temp.reject_engineering('save_photo_title',jsonb_build_object('id',gen_random_uuid(),'expected_updated_at',null,'changes',jsonb_build_object('titulo',E'\t\n','celula_id',null)),'22023');
  perform pg_temp.call_engineering(gen_random_uuid(),'save_photo_title',jsonb_build_object('id','a8000000-0000-4000-8000-000000000002','expected_updated_at',null,
    'changes',jsonb_build_object('titulo','Global title','celula_id',null,'numero',null)));
  insert into public.rm_cadastro_fotos(id,titulo,celula_nome) values('a8000000-0000-4000-8000-000000000003','Whitespace global fixture',E'\t\n');
  perform pg_temp.call_engineering(gen_random_uuid(),'save_photo_title',jsonb_build_object('id','a8000000-0000-4000-8000-000000000003',
    'expected_updated_at',(select updated_at from public.rm_cadastro_fotos where rm_cadastro_fotos.id='a8000000-0000-4000-8000-000000000003'),
    'changes',jsonb_build_object('celula_id',null,'titulo','Normalized global title')));
  insert into public.rm_cadastro_fotos(id,titulo,celula_nome) values('a8000000-0000-4000-8000-000000000004','Unchanged whitespace global fixture',E'\t\n');
end $$;

select set_config('rm.test.engineering.photo',jsonb_build_object('id','b8000000-0000-4000-8000-000000000001',
  'cadastro_foto_id','a8000000-0000-4000-8000-000000000001','numero',1,'descricao',null)::text,true);
select set_config('rm.test.engineering.stage',jsonb_build_object('id','c8000000-0000-4000-8000-000000000001',
  'celula_destino_id','48000000-0000-4000-8000-000000000002','status_cel_proj','finalizado','bloquear_avanco_sem_aprov',true,
  'aprovadores_ids',jsonb_build_array('28000000-0000-4000-8000-000000000002'),
  'aprovadores_retorno_ids',jsonb_build_array('28000000-0000-4000-8000-000000000003'))::text,true);

do $$ declare p jsonb; r jsonb; snapshot jsonb; rid uuid:=gen_random_uuid(); old_version timestamptz; begin
  p:=pg_temp.matrix_payload(jsonb_build_object('ativo',true,'visibilidade',false,'numero_fotos',99,'form_ids',jsonb_build_array('78000000-0000-4000-8000-000000000001'),
    'photos',jsonb_build_array(current_setting('rm.test.engineering.photo')::jsonb),'stages',jsonb_build_array(current_setting('rm.test.engineering.stage')::jsonb)));
  r:=pg_temp.call_engineering(rid,'save_engineering',p); snapshot:=r->'snapshot';
  perform pg_temp.check(snapshot->'matrix'->>'numero_fotos'='99' and jsonb_array_length(snapshot->'photos')=1,'counter independent from actual photo slots');
  perform pg_temp.check(snapshot->'photos'->0->>'titulo'='Registered title' and jsonb_array_length(snapshot->'stages')=1,'atomic child models saved');
  perform pg_temp.check((pg_temp.call_engineering(rid,'save_engineering',p)->>'idempotent_replay')::bool,'matrix replay');
  perform pg_temp.reject_engineering('save_engineering',p,'PT409');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload('{"projeto_id":null}'),'22023');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload('{"form_ids":["78000000-0000-4000-8000-000000000001","78000000-0000-4000-8000-000000000001"]}'),'22023');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('photos',jsonb_build_array(current_setting('rm.test.engineering.photo')::jsonb||'{"numero":0}'))),'22023');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('photos',jsonb_build_array(current_setting('rm.test.engineering.photo')::jsonb||'{"numero":1.5}'))),'22023');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('stages',jsonb_build_array(current_setting('rm.test.engineering.stage')::jsonb||'{"status_cel_proj":"retornado"}'))),'22023');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('stages',jsonb_build_array(current_setting('rm.test.engineering.stage')::jsonb||'{"aprovadores_ids":[]}'))),'22023');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('stages',jsonb_build_array(current_setting('rm.test.engineering.stage')::jsonb||'{"aprovadores_ids":["28000000-0000-4000-8000-000000000003"]}'))),'22023');
  select updated_at into old_version from public.rm_celula_tipos_equipamento where id='68000000-0000-4000-8000-000000000001';
  update public.rm_fotos set descricao='Technical import update',tag='legacy-report-tag' where id='b8000000-0000-4000-8000-000000000001';
  perform pg_temp.check((select updated_at>old_version from public.rm_celula_tipos_equipamento where id='68000000-0000-4000-8000-000000000001'),'technical model edit advances parent version');
  snapshot:=public.rm_web_engineering_snapshot_v1('68000000-0000-4000-8000-000000000001');
  perform pg_temp.check(snapshot->'photos'->0->>'descricao'='Technical import update' and snapshot->'matrix'->>'updated_at' is not null,'single-statement snapshot includes child edit and version');
end $$;

-- New plan_cell copies active templates. Subsequent engineering edits/retirement
-- never rewrite existing allocations, photo titles, submitted forms or approvals.
insert into public.rm_projetos(id,nome,tipo_equipamento_id) values
 ('d8000000-0000-4000-8000-000000000001','Engineering project A','58000000-0000-4000-8000-000000000001'),
 ('d8000000-0000-4000-8000-000000000002','Engineering project B','58000000-0000-4000-8000-000000000001');
insert into public.rm_projetos(id,nome) values('d8000000-0000-4000-8000-000000000003','Manual project without equipment type');
do $$ declare p jsonb; r jsonb; initial jsonb; allocation uuid; before_version timestamptz; begin
  p:=jsonb_build_object('projeto_id','d8000000-0000-4000-8000-000000000001','celula_id','48000000-0000-4000-8000-000000000001','expected_updated_at',null,'changes','{}'::jsonb);
  r:=pg_temp.call_engineering(gen_random_uuid(),'plan_cell',p,'em.planning.manage'); allocation:=(r->>'id')::uuid; initial:=r->'record';
  perform pg_temp.check(initial->'forms_ids'='["78000000-0000-4000-8000-000000000001"]'::jsonb and initial->>'visibilidade'='false','new allocation inherits forms and initial visibility');
  perform pg_temp.check((select count(*)=1 from public.rm_fotos where projeto_id='d8000000-0000-4000-8000-000000000001' and cadastro_foto_id='a8000000-0000-4000-8000-000000000001'),'new allocation copies title catalog ID and snapshot');
  perform pg_temp.check((select tag='legacy-report-tag' and identificador_foto_key is null from public.rm_fotos
    where projeto_id='d8000000-0000-4000-8000-000000000001'),'new allocation preserves report tag without inventing photo identifier');
  select updated_at into before_version from public.rm_celula_tipos_equipamento where id='68000000-0000-4000-8000-000000000001';
  update public.rm_fotos set legenda='Runtime capture fixture' where projeto_id='d8000000-0000-4000-8000-000000000001';
  perform pg_temp.check((select updated_at=before_version from public.rm_celula_tipos_equipamento where id='68000000-0000-4000-8000-000000000001'),'runtime photo edit does not bump template version');
  perform pg_temp.call_engineering(gen_random_uuid(),'save_engineering',pg_temp.matrix_payload('{"form_ids":[],"photos":[],"stages":[],"ativo":false}'));
  perform pg_temp.check((select to_jsonb(cp)=initial from public.rm_celulas_projeto cp where id=allocation),'existing allocation byte-for-byte preserved');
  perform pg_temp.check((select not lixeira and titulo='Registered title' from public.rm_fotos where projeto_id='d8000000-0000-4000-8000-000000000001'),'existing photo slot not retired');
  perform pg_temp.check((select ativo from public.rm_aprovacoes_etapas where projeto_id='d8000000-0000-4000-8000-000000000001'),'existing approval not retired');
  perform pg_temp.check(exists(select 1 from public.rm_celula_form_tipos_equipamento where celula_tipo_equipamento_id='68000000-0000-4000-8000-000000000001' and not ativo),'removed form relationship retained inactive');
  perform pg_temp.reject_engineering('plan_cell',jsonb_set(p,'{projeto_id}','"d8000000-0000-4000-8000-000000000002"'),'22023','em.planning.manage');
  r:=public.rm_materialize_project_cells_v1('d8000000-0000-4000-8000-000000000002');
  perform pg_temp.check(r->>'celulas_materializadas'='0','general materialization skips inactive relationship');
  perform pg_temp.call_engineering(gen_random_uuid(),'save_engineering',pg_temp.matrix_payload('{"ativo":true,"visibilidade":true,"form_ids":["78000000-0000-4000-8000-000000000002"]}'));
  r:=public.rm_materialize_project_cells_v1('d8000000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp()+interval '1 day');
  perform pg_temp.check(r->>'celulas_materializadas'='0' and (select to_jsonb(cp)=initial from public.rm_celulas_projeto cp where id=allocation),'general materializer never overwrites existing cells');
  r:=pg_temp.call_engineering(gen_random_uuid(),'plan_cell',jsonb_set(p,'{projeto_id}','"d8000000-0000-4000-8000-000000000002"'),'em.planning.manage');
  perform pg_temp.check(r->'record'->'forms_ids'='["78000000-0000-4000-8000-000000000002"]'::jsonb and not exists(
    select 1 from public.rm_fotos where projeto_id='d8000000-0000-4000-8000-000000000002'),'future allocation only sees active models');
  perform pg_temp.call_engineering(gen_random_uuid(),'plan_cell',jsonb_set(p,'{celula_id}','"48000000-0000-4000-8000-000000000003"'),'em.planning.manage');
  perform pg_temp.call_engineering(gen_random_uuid(),'plan_cell',jsonb_set(p,'{projeto_id}','"d8000000-0000-4000-8000-000000000003"'),'em.planning.manage');
end $$;

-- Legacy null/negative number, no catalog and incomplete/singular approval can
-- survive untouched, but changing them requires explicit valid reconfiguration.
insert into public.rm_fotos(id,celula_id,celula_tipo_equipamento_id,titulo,numero,identificador_foto_key)
 values('b8000000-0000-4000-8000-000000000009','48000000-0000-4000-8000-000000000001','68000000-0000-4000-8000-000000000001','Legacy title fixture',-3,'legacy-identifier');
insert into public.rm_aprovacoes_etapas(id,celula_tipo_equipamento_id,celula_origem_id,aprovador_id)
 values('c8000000-0000-4000-8000-000000000009','68000000-0000-4000-8000-000000000001','48000000-0000-4000-8000-000000000001','28000000-0000-4000-8000-000000000002');
do $$ declare photo jsonb; stage jsonb; snap jsonb; r jsonb; begin
  photo:=jsonb_build_object('id','b8000000-0000-4000-8000-000000000009','cadastro_foto_id',null,'numero',-3,'descricao',null);
  stage:=jsonb_build_object('id','c8000000-0000-4000-8000-000000000009','celula_destino_id',null,'status_cel_proj',null,
    'bloquear_avanco_sem_aprov',false,'aprovadores_ids','[]'::jsonb,'aprovadores_retorno_ids','[]'::jsonb);
  r:=pg_temp.call_engineering(gen_random_uuid(),'save_engineering',pg_temp.matrix_payload(jsonb_build_object('photos',jsonb_build_array(photo),'stages',jsonb_build_array(stage))));
  perform pg_temp.check(r->'snapshot'->'photos'->0->>'identificador_foto_key'='legacy-identifier','legacy photo metadata untouched');
  perform pg_temp.check(r->'snapshot'->'stages'->0->>'aprovador_id'='28000000-0000-4000-8000-000000000002','legacy singular approver preserved');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('photos',jsonb_build_array(photo||'{"descricao":"Changed"}'))),'22023');
  stage:=current_setting('rm.test.engineering.stage')::jsonb||'{"id":"c8000000-0000-4000-8000-000000000009"}';
  r:=pg_temp.call_engineering(gen_random_uuid(),'save_engineering',pg_temp.matrix_payload(jsonb_build_object('stages',jsonb_build_array(stage))));
  perform pg_temp.check(r->'snapshot'->'stages'->0->'aprovador_id'='null'::jsonb,'explicit reconfiguration clears hidden singular approver');
  perform pg_temp.reject_engineering('save_engineering',pg_temp.matrix_payload(jsonb_build_object('photos',jsonb_build_array(photo||jsonb_build_object('id',
    (select id from public.rm_fotos where projeto_id='d8000000-0000-4000-8000-000000000001' limit 1))))),'42501');
  perform pg_temp.call_engineering(gen_random_uuid(),'save_photo_title',jsonb_build_object('id','a8000000-0000-4000-8000-000000000001',
    'expected_updated_at',(select updated_at from public.rm_cadastro_fotos where id='a8000000-0000-4000-8000-000000000001'),'changes',jsonb_build_object('titulo','New catalog title')));
  perform pg_temp.check((select titulo='Registered title' from public.rm_fotos where projeto_id='d8000000-0000-4000-8000-000000000001'),'catalog title edit never rewrites project snapshot');
  r:=pg_temp.call_engineering(gen_random_uuid(),'save_engineering',pg_temp.matrix_payload(jsonb_build_object('photos',jsonb_build_array(photo,
    jsonb_build_object('id',gen_random_uuid(),'cadastro_foto_id','a8000000-0000-4000-8000-000000000004','numero',3,'descricao',null)))));
  perform pg_temp.check(jsonb_array_length(r->'snapshot'->'photos')=2,'whitespace-only legacy catalog scope is global for photo selection');
end $$;

do $$ declare p jsonb:=pg_temp.matrix_payload('{"numero_fotos":2}'); rid uuid:=gen_random_uuid(); begin
  perform pg_temp.reject_engineering('save_engineering',p,'22023','em.catalogs.manage');
  update public.rm_users set perfil='auditor' where auth_user_id=auth.uid(); perform pg_temp.reject_engineering('save_engineering',p,'42501');
  update public.rm_users set perfil='administrador' where auth_user_id=auth.uid();
  perform pg_temp.call_engineering(rid,'save_engineering',p);
  insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
  begin perform pg_temp.call_engineering(rid,'save_engineering',p); raise exception 'FAIL: AAL1 replay'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"session_id":"38000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
  perform pg_temp.check((pg_temp.call_engineering(rid,'save_engineering',p)->>'idempotent_replay')::bool,'AAL2 replay');
end $$;
set local role authenticated;
select pg_temp.check(public.rm_web_engineering_snapshot_v1('68000000-0000-4000-8000-000000000001')->'matrix'->>'id'='68000000-0000-4000-8000-000000000001','snapshot authenticated RLS read');
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
select pg_temp.check(public.rm_web_engineering_snapshot_v1('68000000-0000-4000-8000-000000000001') is null,'snapshot requires active RM RLS identity');
reset role;
select pg_temp.check((select not prosecdef and provolatile='s' from pg_proc where oid='public.rm_web_engineering_snapshot_v1(uuid)'::regprocedure),'snapshot stable security invoker');
select pg_temp.check(not has_function_privilege('anon','public.rm_web_engineering_snapshot_v1(uuid)','execute')
 and not has_function_privilege('service_role','public.rm_web_engineering_snapshot_v1(uuid)','execute'),'snapshot not public/service entry');
select pg_temp.check(not has_function_privilege('authenticated','rm_private.engineering_pair_lock(uuid,uuid,boolean)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute'),'helpers not bypassable');
select pg_temp.check((select count(*)::text from public.rm_sync_outbox)=current_setting('rm.test.engineering.outbox'),'engineering never queues outbound work');
select 'PASS: engineering aggregate, template snapshots, retirement, concurrency, legacy preservation, RLS/SSO/MFA' as result;
rollback;

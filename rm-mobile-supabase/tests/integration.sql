\set ON_ERROR_STOP on
-- Run against an isolated database after bootstrap.sql and migrations 001..010.
-- All fixture data and mutations are rolled back, including bridge events.
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,matricula,nome,perfil) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','tablet','Tablet 1','administrador'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','tablet2','Tablet 2','mobile'),
 ('20000000-0000-4000-8000-000000000003',null,'123','Operador de teste','mobile'),
 ('20000000-0000-4000-8000-000000000004',null,'456','Outro operador','mobile');
insert into rm_private.user_credentials(user_id,palavra_chave_hash) values
 ('20000000-0000-4000-8000-000000000003',extensions.crypt('test-only-password',extensions.gen_salt('bf',4))),
 ('20000000-0000-4000-8000-000000000004',extensions.crypt('test-only-password',extensions.gen_salt('bf',4)));
insert into public.rm_celulas(id,nome) values
 ('30000000-0000-4000-8000-000000000001','Peritagem'),
 ('30000000-0000-4000-8000-000000000002','Célula de outro operador');
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003'),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000004');
insert into public.rm_clientes(id,nome) values('40000000-0000-4000-8000-000000000001','Cliente teste');
insert into public.rm_tipos_equipamento(id,nome) values('50000000-0000-4000-8000-000000000001','Motor');
insert into public.rm_projetos(id,numero,created_by_user_id) values
 ('d0000000-0000-4000-8000-000000000001','INACCESSIBLE','20000000-0000-4000-8000-000000000002');
insert into public.rm_forms(id,titulo) values('60000000-0000-4000-8000-000000000001','Inspeção');
insert into public.rm_questoes(id,form_id,indice,enunciado,tipo,obrigatorio) values
 ('70000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001',1.5,'Medição','numero',true),
 ('70000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001',2,'Observação','texto_curto',false),
 ('70000000-0000-4000-8000-000000000003','60000000-0000-4000-8000-000000000001',3,'Seleção','escolha__nica',true);
insert into public.rm_itens_questoes(id,questao_id,descricao) values
 ('80000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000003','Conforme'),
 ('80000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000003','Não conforme');
update public.rm_itens_questoes set indice=1.5 where id='80000000-0000-4000-8000-000000000001';
select pg_temp.check((select indice=1.5 from public.rm_itens_questoes where id='80000000-0000-4000-8000-000000000001'),'fractional option index preserved');
update public.rm_forms set bubble_id='test-form-fractional' where id='60000000-0000-4000-8000-000000000001';
select public.rm_apply_bubble_webhook_v1('Questoes','test-question-fractional',
  '{"Form":"test-form-fractional","Indice":3.5,"Enunciado":"Fractional import","Tipo":"texto_curto"}'::jsonb);
select pg_temp.check((select indice=3.5 from public.rm_questoes where bubble_id='test-question-fractional'),'legacy inbound ETL preserves fractional index');
delete from public.rm_questoes where bubble_id='test-question-fractional';
select pg_temp.check(not has_function_privilege('anon','public.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text)','EXECUTE'),'anonymous auth revoked');
select pg_temp.check(not has_function_privilege('authenticated','public.rm_submit_form_inspection_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb)','EXECUTE'),'legacy mutation bypass revoked');
select pg_temp.check(not has_function_privilege('authenticated','rm_private.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text)','EXECUTE'),'private auth inaccessible');
select pg_temp.check(not has_function_privilege('anon','public.rm_operator_context_v1(text)','EXECUTE'),'anonymous operator context denied');
select pg_temp.check(not has_function_privilege('authenticated','rm_private.operator_context(uuid)','EXECUTE'),'arbitrary operator context denied');
select pg_temp.check(not exists(
  select 1 from unnest(array['rm_clientes','rm_users','rm_tipos_equipamento','rm_celulas',
    'rm_tablet_celula_users','rm_celula_tipos_equipamento','rm_celula_form_tipos_equipamento',
    'rm_forms','rm_questoes','rm_itens_questoes','rm_projetos','rm_equipamentos',
    'rm_celulas_projeto','rm_fotos','rm_registros_formulario','rm_respostas','rm_aprovacoes_etapas']) t
  where not exists(select 1 from pg_publication_tables p where p.pubname='supabase_realtime' and p.schemaname='public' and p.tablename=t)
),'all mobile catalogs published to Realtime');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ declare a jsonb; begin
  a:=public.rm_authenticate_operator_v1('123','test-only-password');
  perform pg_temp.check((a->>'authenticated')::boolean,'operator login');
  perform pg_temp.check(length(a->>'operator_token')=64,'opaque token');
  perform pg_temp.check(a->>'cell_access_policy_version'='2','permission policy version');
  perform pg_temp.check(jsonb_array_length(a->'celulas_vinculadas')=1 and a->'celulas_vinculadas'->0->>'celula_id'='30000000-0000-4000-8000-000000000001','operator does not inherit tablet administrator cells');
  perform set_config('rm.test.token',a->>'operator_token',true);
  a:=public.rm_authenticate_operator_v1('456','test-only-password');
  perform pg_temp.check(jsonb_array_length(a->'celulas_vinculadas')=1 and a->'celulas_vinculadas'->0->>'celula_id'='30000000-0000-4000-8000-000000000002','second operator sees only their registered cell');
  perform pg_temp.check((select count(*)=2 from public.rm_tablet_celula_users where
    (celula_id='30000000-0000-4000-8000-000000000001' and identidade_id='20000000-0000-4000-8000-000000000003') or
    (celula_id='30000000-0000-4000-8000-000000000002' and identidade_id='20000000-0000-4000-8000-000000000004')),'operator switching never rewrites registered assignments');
  a:=public.rm_operator_context_v1(current_setting('rm.test.token'));
  perform pg_temp.check(jsonb_array_length(a->'celulas_vinculadas')=1 and a->>'operador_id'='20000000-0000-4000-8000-000000000003','context refresh stays bound to delegated actor');
  perform pg_temp.check((select count(*) from public.rm_clientes)>0,'RLS catalogs readable by linked account');
end $$;

-- Ownership policies permit stable uploads and reject another device's prefix.
insert into storage.objects(bucket_id,name) values('rm-fotos','10000000-0000-4000-8000-000000000001/test.jpg');
do $$ begin
  begin
    insert into storage.objects(bucket_id,name) values('rm-fotos','10000000-0000-4000-8000-000000000002/test.jpg');
    raise exception 'FAIL: cross-device storage upload accepted';
  exception when insufficient_privilege then null; end;
end $$;

do $$ declare p jsonb; first_result jsonb; replay jsonb; begin
  p:=jsonb_build_object('p_operador_id','20000000-0000-4000-8000-000000000003',
    'p_cliente_id','40000000-0000-4000-8000-000000000001','p_tipo_equipamento_id','50000000-0000-4000-8000-000000000001',
    'p_numero_projeto','TEST-001','p_equipamento',jsonb_build_object('fabricante','Teste'));
  first_result:=public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',p,current_setting('rm.test.token'));
  replay:=public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check(replay->>'projeto_id'=first_result->>'projeto_id' and (replay->>'idempotent_replay')::boolean,'receiving replay');
  perform pg_temp.check((select count(*)=1 from public.rm_projetos where numero='TEST-001'),'no duplicate receiving');
  perform set_config('rm.test.project',first_result->>'projeto_id',true);
  begin
    perform public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',
      p||jsonb_build_object('p_numero_projeto','DIFFERENT'),current_setting('rm.test.token'));
    raise exception 'FAIL: different payload reused idempotency key';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_recebimento_v1',
      p||jsonb_build_object('p_operador_id','20000000-0000-4000-8000-000000000002'),current_setting('rm.test.token'));
    raise exception 'FAIL: actor spoofing accepted';
  exception when insufficient_privilege then null; end;
  p:=p||jsonb_build_object('p_projeto_id',first_result->>'projeto_id','p_qrcode_value','https://example.invalid/projeto/TEST-001',
    'p_equipamento',jsonb_build_object('fabricante','Corrigido','numero_serie','ABC-123','fp',''));
  replay:=public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000004','rm_submit_recebimento_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check(replay->>'projeto_id'=first_result->>'projeto_id' and (replay->>'updated_existing')::boolean,'QR receiving updates existing project');
  perform pg_temp.check((select count(*)=1 from public.rm_projetos where numero='TEST-001'),'QR receiving does not duplicate project');
  perform pg_temp.check((select numero_serie='ABC-123' and fabricante='Corrigido' and fp is null from public.rm_equipamentos where projeto_id=(first_result->>'projeto_id')::uuid),'QR receiving updates equipment');
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_recebimento_v1',
      p||jsonb_build_object('p_projeto_id','d0000000-0000-4000-8000-000000000001'),current_setting('rm.test.token'));
    raise exception 'FAIL: receiving edited inaccessible project';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.rm_celulas_projeto(projeto_id,celula_id,forms_ids,visibilidade) values
 (current_setting('rm.test.project')::uuid,'30000000-0000-4000-8000-000000000001',array['60000000-0000-4000-8000-000000000001']::uuid[],true),
 (current_setting('rm.test.project')::uuid,'30000000-0000-4000-8000-000000000002',array['60000000-0000-4000-8000-000000000001']::uuid[],true);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id) values
 ('a0000000-0000-4000-8000-000000000001',current_setting('rm.test.project')::uuid,'30000000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ declare p jsonb; result jsonb; begin
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_inspection_v1',
      jsonb_build_object('p_projeto_id',current_setting('rm.test.project'),'p_celula_id','30000000-0000-4000-8000-000000000002',
        'p_form_id','60000000-0000-4000-8000-000000000001','p_respostas','[]'::jsonb),current_setting('rm.test.token'));
    raise exception 'FAIL: operator inherited another operator cell through administrator tablet';
  exception when insufficient_privilege then null; end;
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_record_cell_photo_v1',
      jsonb_build_object('p_projeto_id',current_setting('rm.test.project'),'p_celula_id','30000000-0000-4000-8000-000000000002',
        'p_foto_url','https://example.invalid/test.jpg'),current_setting('rm.test.token'));
    raise exception 'FAIL: photo accepted in another operator cell';
  exception when insufficient_privilege then null; end;
  p:=jsonb_build_object('p_projeto_id',current_setting('rm.test.project'),'p_celula_id','30000000-0000-4000-8000-000000000001',
    'p_form_id','60000000-0000-4000-8000-000000000001','p_respostas','[]'::jsonb);
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_inspection_v1',p,current_setting('rm.test.token'));
    raise exception 'FAIL: missing required answers accepted';
  exception when invalid_parameter_value then null; end;
  p:=p||jsonb_build_object('p_respostas',jsonb_build_array(
    jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000001','resposta','2,5'),
    jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000002','resposta','Remover durante revisão'),
    jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000003','resposta','Conforme',
      'itens',jsonb_build_array('Conforme'),'itens_questoes_ids',jsonb_build_array('80000000-0000-4000-8000-000000000001'))));
  result:=public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000002','rm_submit_form_inspection_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check(result->>'codigo_text'='0001','atomic form sequence');
  perform pg_temp.check((select indice=1.5 from public.rm_respostas where registro_formulario_id=(result->>'registro_formulario_id')::uuid
    and questao_id='70000000-0000-4000-8000-000000000001'),'mobile submission preserves fractional question index');
  perform set_config('rm.test.record',result->>'registro_formulario_id',true);
  perform public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000002','rm_submit_form_inspection_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check((select count(*)=3 from public.rm_respostas where registro_formulario_id=(result->>'registro_formulario_id')::uuid),'form replay has no duplicate answers');
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',
      jsonb_build_object('p_aprovacao_etapa_id','a0000000-0000-4000-8000-000000000001','p_acao','aprovar'),current_setting('rm.test.token'));
    raise exception 'FAIL: unqualified operator approved a stage';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.rm_registros_formulario set status='direcionado' where id=current_setting('rm.test.record')::uuid;
update public.rm_respostas set revisar=true where registro_formulario_id=current_setting('rm.test.record')::uuid
  and questao_id in ('70000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000003');
set local role authenticated;
do $$ declare p jsonb; result jsonb; begin
  p:=jsonb_build_object('p_registro_formulario_id',current_setting('rm.test.record'),'p_respostas_corrigidas',jsonb_build_array(
    jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000001','resposta','3.5'),
    jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000002','resposta',null),
    jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000003','resposta','Não conforme','itens',jsonb_build_array('Não conforme'),
      'itens_questoes_ids',jsonb_build_array('80000000-0000-4000-8000-000000000002'))));
  result:=public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000003','rm_submit_form_revision_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check(result->>'novo_status'='em_an_lise','revision returns to analysis');
  perform pg_temp.check((select indice=1.5 and resposta='3.5' from public.rm_respostas where registro_formulario_id=current_setting('rm.test.record')::uuid
    and questao_id='70000000-0000-4000-8000-000000000001'),'revision preserves fractional question index');
  perform pg_temp.check((select resposta is null from public.rm_respostas where registro_formulario_id=current_setting('rm.test.record')::uuid
    and questao_id='70000000-0000-4000-8000-000000000002'),'explicit null clears optional text');
  perform pg_temp.check((select itens_questoes_ids=array['80000000-0000-4000-8000-000000000002']::uuid[] from public.rm_respostas
    where registro_formulario_id=current_setting('rm.test.record')::uuid and questao_id='70000000-0000-4000-8000-000000000003'),'revision updates selection IDs');
  result:=public.rm_mobile_mutate_v1('90000000-0000-4000-8000-000000000003','rm_submit_form_revision_v1',p,current_setting('rm.test.token'));
  perform pg_temp.check((result->>'idempotent_replay')::boolean,'revision retry succeeds after status changed');
end $$;

-- The same token cannot be replayed by another authenticated device.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin
  begin
    perform public.rm_operator_context_v1(current_setting('rm.test.token'));
    raise exception 'FAIL: another device refreshed operator context';
  exception when invalid_authorization_specification then null; end;
  begin
    perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_recebimento_v1','{}',current_setting('rm.test.token'));
    raise exception 'FAIL: token accepted by wrong device';
  exception when invalid_authorization_specification then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
-- Permission refresh sees registration changes without changing the offline expiry.
reset role;
delete from public.rm_tablet_celula_users where identidade_id='20000000-0000-4000-8000-000000000003';
update public.rm_users set perfil='administrador' where id='20000000-0000-4000-8000-000000000004';
set local role authenticated;
do $$ declare a jsonb; begin
  a:=public.rm_operator_context_v1(current_setting('rm.test.token'));
  perform pg_temp.check(jsonb_array_length(a->'celulas_vinculadas')=0,'context refresh observes removed assignment');
  a:=public.rm_authenticate_operator_v1('456','test-only-password');
  perform pg_temp.check(a->>'perfil'='administrador' and jsonb_array_length(a->'celulas_vinculadas')=2,'operator administrator retains administrative access');
end $$;

do $$ declare a jsonb; begin
  for i in 1..5 loop
    a:=public.rm_authenticate_operator_v1('123','wrong-password');
    perform pg_temp.check(a->>'authenticated'='false','failed login does not authenticate');
  end loop;
  a:=public.rm_authenticate_operator_v1('123','test-only-password');
  perform pg_temp.check((a->>'retry_after_seconds')::integer>0,'online lockout persists across failed login responses');
end $$;
reset role;

-- Date/time ranges and paired photos use server definitions, including optional pairs.
insert into public.rm_forms(id,titulo) values('60000000-0000-4000-8000-000000000002','Tipos especiais');
insert into public.rm_questoes(id,form_id,indice,enunciado,tipo,subtipo,obrigatorio) values
 ('70000000-0000-4000-8000-000000000004','60000000-0000-4000-8000-000000000002',1,'Horário de execução','hora','intervalo_de_hor_rios',true),
 ('70000000-0000-4000-8000-000000000005','60000000-0000-4000-8000-000000000002',2,'Antes/depois','foto_antes_depois',null,false);
do $$ declare a jsonb; begin
  a:=jsonb_build_array(jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000004','hora','2026-10-27T10:00:00Z'));
  begin
    perform rm_private.validate_form_answers('60000000-0000-4000-8000-000000000002',a);
    raise exception 'FAIL: incomplete time range accepted';
  exception when invalid_parameter_value then null; end;
  a:=jsonb_build_array(jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000004',
    'hora','2026-10-27T10:00:00Z','date_inicio','2026-10-27T10:00:00Z','data_fim','2026-10-27T09:00:00Z'));
  begin
    perform rm_private.validate_form_answers('60000000-0000-4000-8000-000000000002',a);
    raise exception 'FAIL: backwards time range accepted';
  exception when invalid_parameter_value then null; end;
  a:=jsonb_build_array(jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000004',
    'hora','2026-10-27T10:00:00Z','date_inicio','2026-10-27T10:00:00Z','data_fim','2026-10-27T11:00:00Z'));
  perform rm_private.validate_form_answers('60000000-0000-4000-8000-000000000002',a);
  begin
    perform rm_private.validate_form_answers('60000000-0000-4000-8000-000000000002',a||jsonb_build_array(
      jsonb_build_object('questao_id','70000000-0000-4000-8000-000000000005','fotos_urls',jsonb_build_array('https://example.invalid/before.jpg'))));
    raise exception 'FAIL: incomplete optional photo pair accepted';
  exception when invalid_parameter_value then null; end;
end $$;

-- Claim ownership, retry backoff, lease expiry recovery and monotonic checkpoints.
delete from public.rm_sync_outbox;
insert into public.rm_sync_outbox(target_system,entity_type,operation,record_id,payload)
  values('bubble_data_api','test','create',gen_random_uuid(),'{}');
set local role service_role;
do $$ declare row public.rm_sync_outbox%rowtype; other_count integer; begin
  perform pg_temp.check(public.rm_acquire_bridge_lease_v1('b0000000-0000-4000-8000-000000000001'),'acquire bridge lease');
  perform pg_temp.check(not public.rm_acquire_bridge_lease_v1('b0000000-0000-4000-8000-000000000002'),'overlapping bridge excluded');
  select * into row from public.rm_claim_sync_events_v1('b0000000-0000-4000-8000-000000000001',1);
  perform pg_temp.check(row.attempts=1 and row.status='processing','claim increments attempt atomically');
  select count(*) into other_count from public.rm_claim_sync_events_v1('b0000000-0000-4000-8000-000000000002',1);
  perform pg_temp.check(other_count=0,'claimed row cannot be claimed twice');
  perform pg_temp.check(not public.rm_finish_sync_event_v1(row.id,'b0000000-0000-4000-8000-000000000002'),'wrong owner cannot finish');
  perform pg_temp.check(public.rm_finish_sync_event_v1(row.id,'b0000000-0000-4000-8000-000000000001','Transient error'),'owner can record failure');
  perform pg_temp.check((select status='failed' and next_retry_at>clock_timestamp() from public.rm_sync_outbox where id=row.id),'backoff persists');
  update public.rm_sync_outbox set status='processing',lease_until=clock_timestamp()-interval '1 minute',claimed_by='b0000000-0000-4000-8000-000000000001' where id=row.id;
  select * into row from public.rm_claim_sync_events_v1('b0000000-0000-4000-8000-000000000002',1);
  perform pg_temp.check(row.attempts=2,'crashed lease reclaimed');
  perform pg_temp.check(public.rm_finish_sync_event_v1(row.id,'b0000000-0000-4000-8000-000000000002'),'reclaimed event finishes');
  perform public.rm_advance_bridge_checkpoint_v1('test','2026-10-27T12:00:00Z');
  perform public.rm_advance_bridge_checkpoint_v1('test','2026-10-26T12:00:00Z');
  perform pg_temp.check((select cursor_at='2026-10-27T12:00:00Z'::timestamptz from public.rm_bridge_checkpoints where endpoint='test'),'checkpoint never moves backwards');
  perform pg_temp.check(public.rm_advance_form_sequence_v1('60000000-0000-4000-8000-000000000001',100)=100,'legacy sequence advances');
  perform pg_temp.check(public.rm_advance_form_sequence_v1('60000000-0000-4000-8000-000000000001',5)=100,'legacy sequence never moves backwards');
end $$;
reset role;
select 'PASS: delegation, RLS, media ownership, idempotency, validation, revisions, throttling, worker recovery' as result;
rollback;

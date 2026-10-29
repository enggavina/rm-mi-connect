\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values
 ('14000000-0000-4000-8000-000000000001'),('14000000-0000-4000-8000-000000000002'),
 ('14000000-0000-4000-8000-000000000003'),('14000000-0000-4000-8000-000000000004');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('24000000-0000-4000-8000-000000000001','14000000-0000-4000-8000-000000000001','Admin fixture','administrador'),
 ('24000000-0000-4000-8000-000000000002','14000000-0000-4000-8000-000000000002','PCP fixture','padr_o'),
 ('24000000-0000-4000-8000-000000000003','14000000-0000-4000-8000-000000000003','Operator fixture','mobile'),
 ('24000000-0000-4000-8000-000000000004','14000000-0000-4000-8000-000000000004','Null role fixture',null);
insert into public.rm_clientes(id,nome) values('44000000-0000-4000-8000-000000000001','Client fixture');
insert into public.rm_tipos_equipamento(id,nome) values('54000000-0000-4000-8000-000000000001','Equipment fixture');
insert into public.rm_celulas(id,nome) values
 ('34000000-0000-4000-8000-000000000001','Cell A'),('34000000-0000-4000-8000-000000000002','Cell B');
insert into public.rm_forms(id,titulo,ativo) values
 ('64000000-0000-4000-8000-000000000001','Form A',true),('64000000-0000-4000-8000-000000000002','Inactive',false);
insert into public.rm_questoes(id,form_id,enunciado,tipo,indice) values
 ('74000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','Question','texto_curto',1.5),
 ('74000000-0000-4000-8000-000000000002','64000000-0000-4000-8000-000000000001','Heading','subt_tulo',2);
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id,visibilidade) values
 ('84000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000001','54000000-0000-4000-8000-000000000001',true);
insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id) values
 ('84000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001');
insert into public.rm_fotos(celula_tipo_equipamento_id,titulo,categoria_foto) values
 ('84000000-0000-4000-8000-000000000001','Required template photo','obrigat_ria');
insert into public.rm_aprovacoes_etapas(celula_tipo_equipamento_id,celula_origem_id,celula_destino_id,status_cel_proj) values
 ('84000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000002','em_dia');
set local role authenticated;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000001',true);
do $$ declare payload jsonb; r jsonb; v timestamptz; begin
  payload := jsonb_build_object('id','94000000-0000-4000-8000-000000000001','expected_updated_at',null,
    'changes',jsonb_build_object('numero','QA-014','nome','Fixture project','cliente_id','44000000-0000-4000-8000-000000000001',
    'tipo_equipamento_id','54000000-0000-4000-8000-000000000001'));
  r := public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000001','save_project',payload);
  perform pg_temp.check(r->'record'->>'created_by_user_id'='24000000-0000-4000-8000-000000000001','actor derives Auth');
  perform pg_temp.check(not (r->>'idempotent_replay')::boolean,'initial result');
  perform pg_temp.check((public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000001','save_project',payload)->>'idempotent_replay')::boolean,'replay ignores now-stale create version');
  begin
    perform public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000001','save_project',jsonb_set(payload,'{changes,nome}','"Other"'));
    raise exception 'FAIL: idempotency conflict accepted'; exception when unique_violation then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',payload);
    raise exception 'FAIL: stale create accepted'; exception when sqlstate 'PT409' then null; end;
  v := (r->>'updated_at')::timestamptz;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',r->>'id','expected_updated_at',v,'changes',jsonb_build_object('created_by_user_id','24000000-0000-4000-8000-000000000003')));
    raise exception 'FAIL: actor spoof accepted'; exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',r->>'id','expected_updated_at',v,'changes',jsonb_build_object('status_pcp','wrong')));
    raise exception 'FAIL: invalid enum accepted'; exception when invalid_text_representation then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',r->>'id','expected_updated_at',v,'changes',jsonb_build_object('cliente_id',gen_random_uuid())));
    raise exception 'FAIL: invalid FK accepted'; exception when foreign_key_violation then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',r->>'id','expected_updated_at',v,'changes',jsonb_build_object('status_pcp','finalizando_para_faturar')));
    raise exception 'FAIL: incomplete project completed'; exception when invalid_parameter_value then null; end;
  perform set_config('rm.test.web_version',v::text,true);
end $$;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000003',true);
do $$ begin
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',gen_random_uuid(),'expected_updated_at',null,'changes',jsonb_build_object('nome','Unauthorized')));
    raise exception 'FAIL: mobile profile wrote project'; exception when insufficient_privilege then null; end;
  begin
    update public.rm_projetos set nome='Bypass' where id='94000000-0000-4000-8000-000000000001';
    raise exception 'FAIL: direct table write permitted'; exception when insufficient_privilege then null; end;
  begin
    perform count(*) from rm_private.web_mutation_receipts;
    raise exception 'FAIL: private audit readable'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000004',true);
do $$ begin
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',gen_random_uuid(),'expected_updated_at',null,'changes',jsonb_build_object('nome','Unauthorized')));
    raise exception 'FAIL: null role wrote project'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000002',true);
do $$ declare p jsonb; r jsonb; v timestamptz; begin
  p:=jsonb_build_object('projeto_id','94000000-0000-4000-8000-000000000001','celula_id','34000000-0000-4000-8000-000000000001',
    'expected_updated_at',null,'changes',jsonb_build_object('data_inicio','2026-11-01T10:00:00Z','data_limite','2026-11-02T10:00:00Z','horas_previstas',2.5));
  r:=public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000002','plan_cell',p);
  perform pg_temp.check(r->'record'->>'modified_by_id'='24000000-0000-4000-8000-000000000002','PCP planning actor');
  perform pg_temp.check(jsonb_array_length(r->'record'->'forms_ids')=1,'template forms cloned');
  perform pg_temp.check((select count(*)=1 from public.rm_fotos where projeto_id='94000000-0000-4000-8000-000000000001'),'template photo cloned once');
  perform pg_temp.check((select count(*)=1 from public.rm_aprovacoes_etapas where projeto_id='94000000-0000-4000-8000-000000000001'),'approval cloned');
  perform public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000002','plan_cell',p);
  perform pg_temp.check((select count(*)=1 from public.rm_fotos where projeto_id='94000000-0000-4000-8000-000000000001'),'replay no duplicate slots');
  v:=(r->>'updated_at')::timestamptz;
  p:=jsonb_set(p,'{expected_updated_at}',to_jsonb(v));
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_set(p,'{changes}','{"bloqueada":"sim"}'));
    raise exception 'FAIL: block without reason'; exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_set(p,'{changes}','{"data_limite":"2026-10-01T00:00:00Z"}'));
    raise exception 'FAIL: negative date interval'; exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_set(p,'{changes}','{"forms_ids":["64000000-0000-4000-8000-000000000002"]}'));
    raise exception 'FAIL: inactive form added'; exception when invalid_parameter_value then null; end;
  r:=public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_set(p,'{changes}','{"observacao":"Plan","visibilidade":false}'));
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_set(p,'{changes}','{"observacao":"Stale"}'));
    raise exception 'FAIL: stale planning overwrote newer version'; exception when sqlstate 'PT409' then null; end;
  perform set_config('rm.test.web_cell',r->>'id',true);
  perform set_config('rm.test.web_cell_version',r->>'updated_at',true);
  perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_build_object(
    'projeto_id','94000000-0000-4000-8000-000000000001','celula_id','34000000-0000-4000-8000-000000000002',
    'expected_updated_at',null,'changes',jsonb_build_object('visibilidade',true)));
  perform pg_temp.check((select observacao='Plan' and not visibilidade and horas_previstas=2.5
    and data_limite='2026-11-02T10:00:00Z'::timestamptz and updated_at=(current_setting('rm.test.web_cell_version'))::timestamptz
    from public.rm_celulas_projeto where id=(current_setting('rm.test.web_cell'))::uuid),'new allocation leaves existing planning and version intact');
end $$;
reset role;
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,avaliador_user_id,identidade_user_id) values
 ('b4000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000003','24000000-0000-4000-8000-000000000003');
insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta) values
 ('c4000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','74000000-0000-4000-8000-000000000001','Original');
insert into public.rm_respostas(id,registro_formulario_id,questao_id,bubble_id,resposta,sync_source) values
 ('c4000000-0000-4000-8000-000000000002','b4000000-0000-4000-8000-000000000001',null,'orphan-web-fixture','Historical answer','bubble');
set local role authenticated;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000002',true);
do $$ declare p jsonb; v timestamptz; begin
  select updated_at into v from public.rm_registros_formulario where id='b4000000-0000-4000-8000-000000000001';
  p:=jsonb_build_object('registro_formulario_id','b4000000-0000-4000-8000-000000000001','expected_updated_at',v,'decision','approve','parecer','Checked','resposta_ids','[]'::jsonb);
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'review_form',p);
    raise exception 'FAIL: PCP without reviewer assignment approved'; exception when insufficient_privilege then null; end;
  perform set_config('rm.test.web_review_payload',p::text,true);
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_build_object('projeto_id','94000000-0000-4000-8000-000000000001','celula_id','34000000-0000-4000-8000-000000000001',
      'expected_updated_at',current_setting('rm.test.web_cell_version'),'changes','{"forms_ids":[]}'::jsonb));
    raise exception 'FAIL: submitted form unlinked'; exception when invalid_parameter_value then null; end;
end $$;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000003',true);
do $$ declare p jsonb; r jsonb; begin
  p:=jsonb_set(current_setting('rm.test.web_review_payload')::jsonb,'{decision}','"return"');
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'review_form',jsonb_set(p,'{resposta_ids}','["c4000000-0000-4000-8000-000000000002"]'));
    raise exception 'FAIL: orphan returned for correction'; exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'review_form',jsonb_set(p,'{resposta_ids}',jsonb_build_array(gen_random_uuid())));
    raise exception 'FAIL: unknown answer returned'; exception when invalid_parameter_value then null; end;
  p:=jsonb_set(p,'{resposta_ids}','["c4000000-0000-4000-8000-000000000001"]');
  r:=public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000003','review_form',p);
  perform pg_temp.check(r->'record'->>'status'='direcionado','return drives existing mobile revision');
  perform pg_temp.check(r->'record'->>'identidade_user_id'='24000000-0000-4000-8000-000000000003','review preserves original author');
  perform pg_temp.check((select revisar and resposta='Original' from public.rm_respostas where id='c4000000-0000-4000-8000-000000000001'),'only flag changed');
  perform pg_temp.check((select not revisar and resposta='Historical answer' from public.rm_respostas where id='c4000000-0000-4000-8000-000000000002'),'orphan untouched');
  perform public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000003','review_form',p);
  perform pg_temp.check((select count(*)=1 from public.rm_aprovacoes_registro where registro_formulario_id='b4000000-0000-4000-8000-000000000001'),'review replay no duplicate history');
end $$;
reset role;
-- Exercise the actual mobile correction implementation after web return.
select public.rm_submit_form_revision_v1('b4000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000003',
 '[{"questao_id":"74000000-0000-4000-8000-000000000001","resposta":"Corrected"}]');
set local role authenticated;
select set_config('request.jwt.claim.sub','14000000-0000-4000-8000-000000000001',true);
do $$ declare p jsonb; r jsonb; v timestamptz; begin
  select updated_at into v from public.rm_registros_formulario where id='b4000000-0000-4000-8000-000000000001';
  p:=jsonb_set(current_setting('rm.test.web_review_payload')::jsonb,'{expected_updated_at}',to_jsonb(v));
  r:=public.rm_web_mutate_v1(gen_random_uuid(),'review_form',p);
  perform pg_temp.check(r->'record'->>'status'='aprovado','admin approves corrected form');
  perform pg_temp.check((select count(*)=2 from public.rm_aprovacoes_registro where registro_formulario_id='b4000000-0000-4000-8000-000000000001'),'both decisions audited');
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'review_form',p);
    raise exception 'FAIL: stale approval accepted'; exception when sqlstate 'PT409' then null; end;
end $$;
reset role;
-- A concurrent operational write must invalidate the web project's old version.
update public.rm_projetos set eventualidades='Operational update' where id='94000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id','94000000-0000-4000-8000-000000000001',
      'expected_updated_at',current_setting('rm.test.web_version'),'changes',jsonb_build_object('eventualidades','Stale browser')));
    raise exception 'FAIL: stale web overwrote operational update'; exception when sqlstate 'PT409' then null; end;
  perform pg_temp.check((select eventualidades='Operational update' from public.rm_projetos where id='94000000-0000-4000-8000-000000000001'),'operational write retained');
end $$;
reset role;
insert into auth.mfa_factors(user_id,factor_type,status) values
 ('14000000-0000-4000-8000-000000000001','totp','verified');
set local role authenticated;
do $$ declare p jsonb; r jsonb; begin
  p:=jsonb_build_object('id','94000000-0000-4000-8000-000000000002','expected_updated_at',null,
    'changes',jsonb_build_object('nome','MFA fixture'));
  perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
  begin
    perform public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000004','save_project',p);
    raise exception 'FAIL: verified TOTP allowed AAL1'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000004','save_project',p);
    raise exception 'FAIL: verified TOTP allowed missing AAL'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"aal":"aal2"}',true);
  r:=public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000004','save_project',p);
  perform pg_temp.check(r->>'id'='94000000-0000-4000-8000-000000000002','verified TOTP allows AAL2');
  perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
  begin
    perform public.rm_web_mutate_v1('a4000000-0000-4000-8000-000000000004','save_project',p);
    raise exception 'FAIL: AAL1 bypassed MFA through idempotent replay'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.rm_users set status='inativo' where id='24000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',gen_random_uuid(),'expected_updated_at',null,'changes',jsonb_build_object('nome','Disabled admin')));
    raise exception 'FAIL: inactive admin writes'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.check(not has_function_privilege('anon','public.rm_web_mutate_v1(uuid,text,jsonb)','EXECUTE'),'anonymous RPC denied');
select pg_temp.check((select count(*)=7 from rm_private.web_mutation_receipts),'only successful unique mutations have receipts');
select 'PASS: web actor permissions, idempotency, optimistic versions, materialization and mobile review compatibility' as result;
rollback;

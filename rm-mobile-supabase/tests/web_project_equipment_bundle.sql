\set ON_ERROR_STOP on
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create function pg_temp.check_bundle(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values ('1fe36000-0000-4000-8000-000000000001'),('1fe36000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 ('2fe36000-0000-4000-8000-000000000001','1fe36000-0000-4000-8000-000000000001','Bundle admin fixture','administrador','ativo'),
 ('2fe36000-0000-4000-8000-000000000002','1fe36000-0000-4000-8000-000000000002','Bundle mobile fixture','mobile','ativo');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1fe36000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
do $$ declare pid uuid:='5fe36000-0000-4000-8000-000000000001'; eid uuid:='6fe36000-0000-4000-8000-000000000001';
 payload jsonb; result jsonb; snap jsonb; v text; begin
 payload:=jsonb_build_object('id',pid,'expected_updated_at',null,'changes',jsonb_build_object('nome','Bundle fixture'),
  'equipment',jsonb_build_object('id',eid,'expected_updated_at',null,'expected_context_version',null,'changes',jsonb_build_object('fabricante','Fabricante teste','descricao','Motor teste')));
 result:=public.rm_web_mutate_v1('afe36000-0000-4000-8000-000000000001','save_project_with_equipment',payload);
 perform pg_temp.check_bundle(result->>'id'=pid::text and result->'record'->>'equipamento_id'=eid::text,'project and equipment linked');
 perform pg_temp.check_bundle((select count(*)=1 from public.rm_equipamentos where id=eid and projeto_id=pid and descricao='Motor teste'),'equipment stored once');
 perform pg_temp.check_bundle((select descricao_equipamento is null from public.rm_projetos where id=pid),'technical description not duplicated');
 result:=public.rm_web_mutate_v1('afe36000-0000-4000-8000-000000000001','save_project_with_equipment',payload);
 perform pg_temp.check_bundle((result->>'idempotent_replay')::boolean,'replay does not recreate equipment');
 snap:=public.rm_web_project_equipment_snapshot_v1(pid); v:=snap->'project'->>'updated_at';
 payload:=jsonb_build_object('id',pid,'expected_updated_at',v,'changes','{}'::jsonb,
  'equipment',jsonb_build_object('id',eid,'expected_updated_at',snap->'equipment'->>'updated_at','expected_context_version',snap->>'context_version','changes',jsonb_build_object('modelo','Modelo teste')));
 result:=public.rm_web_mutate_v1('afe36000-0000-4000-8000-000000000002','save_project_with_equipment',payload);
 perform pg_temp.check_bundle(result->>'updated_at'=v,'equipment-only edit preserves project version');
 perform pg_temp.check_bundle((select modelo='Modelo teste' from public.rm_equipamentos where id=eid),'equipment-only edit saved');
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',payload);
  raise exception 'FAIL: stale equipment edit succeeded';
 exception when sqlstate 'PT409' then null; end;
 snap:=public.rm_web_project_equipment_snapshot_v1(pid);
 payload:=jsonb_build_object('id',pid,'expected_updated_at',snap->'project'->>'updated_at','changes',jsonb_build_object('nome','Projeto atualizado'),
  'equipment',jsonb_build_object('id',eid,'expected_updated_at',snap->'equipment'->>'updated_at','expected_context_version',snap->>'context_version','changes','{}'::jsonb));
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',jsonb_set(payload,'{changes}',jsonb_build_object('descricao_equipamento','Duplicação')));
  raise exception 'FAIL: project equipment description accepted';
 exception when invalid_parameter_value then null; end;
 result:=public.rm_web_mutate_v1('afe36000-0000-4000-8000-000000000003','save_project_with_equipment',payload);
 perform pg_temp.check_bundle((select nome='Projeto atualizado' from public.rm_projetos where id=pid),'project-only edit works');
 perform pg_temp.check_bundle((select modelo='Modelo teste' from public.rm_equipamentos where id=eid),'project-only preserves equipment');
 -- A failing equipment edit rolls back the project inserted in the same action.
 payload:=jsonb_build_object('id','5fe36000-0000-4000-8000-000000000002','expected_updated_at',null,'changes',jsonb_build_object('nome','Must rollback'),
  'equipment',jsonb_build_object('id','6fe36000-0000-4000-8000-000000000002','expected_updated_at',null,'expected_context_version',null,'changes',jsonb_build_object('potencia',jsonb_build_array('bad'))));
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',payload); raise exception 'FAIL: invalid equipment accepted';
 exception when invalid_parameter_value then null; end;
 perform pg_temp.check_bundle(not exists(select 1 from public.rm_projetos where id='5fe36000-0000-4000-8000-000000000002'),'failed equipment rolls back project');
 -- Existing legacy project with no equipment gets one linked record.
 result:=public.rm_web_mutate_v1('afe36000-0000-4000-8000-000000000004','save_project',jsonb_build_object('id','5fe36000-0000-4000-8000-000000000003','expected_updated_at',null,'changes',jsonb_build_object('nome','Legacy')));
 snap:=public.rm_web_project_equipment_snapshot_v1('5fe36000-0000-4000-8000-000000000003');
 payload:=jsonb_build_object('id','5fe36000-0000-4000-8000-000000000003','expected_updated_at',snap->'project'->>'updated_at','changes','{}'::jsonb,
  'equipment',jsonb_build_object('id','6fe36000-0000-4000-8000-000000000003','expected_updated_at',null,'expected_context_version',snap->>'context_version','changes',jsonb_build_object('numero_serie','SERIE')));
 result:=public.rm_web_mutate_v1('afe36000-0000-4000-8000-000000000005','save_project_with_equipment',payload);
 perform pg_temp.check_bundle(result->'record'->>'equipamento_id'='6fe36000-0000-4000-8000-000000000003','missing legacy equipment linked');
end $$;
reset role;
update public.rm_projetos set equipamento_id=null where id='5fe36000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare s jsonb; payload jsonb; begin
 s:=public.rm_web_project_equipment_snapshot_v1('5fe36000-0000-4000-8000-000000000001');
 perform pg_temp.check_bundle(s->>'binding_state'='unlinked','test established ambiguous legacy binding');
 payload:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('nome','Should not write'),
  'equipment',jsonb_build_object('id','6fe36000-0000-4000-8000-000000000001','expected_updated_at',null,'expected_context_version',s->>'context_version','changes','{}'::jsonb));
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',payload); raise exception 'FAIL: ambiguous binding accepted';
 exception when sqlstate 'PT409' then null; end;
 perform pg_temp.check_bundle((select nome='Projeto atualizado' from public.rm_projetos where id='5fe36000-0000-4000-8000-000000000001'),'ambiguous binding leaves project unchanged');
end $$;
select set_config('request.jwt.claim.sub','1fe36000-0000-4000-8000-000000000002',true);
do $$ begin begin
 perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment','{}'::jsonb);
 raise exception 'FAIL: unauthorized role succeeded';
 exception when insufficient_privilege then null; end; end $$;
reset role;
insert into auth.sessions(id,user_id) values('3fe36000-0000-4000-8000-000000000001','1fe36000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('8fe36000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9fe36000-0000-4000-8000-000000000001',
 '2fe36000-0000-4000-8000-000000000001','1fe36000-0000-4000-8000-000000000001',true,'2fe36000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('9',64),'8fe36000-0000-4000-8000-000000000001','3fe36000-0000-4000-8000-000000000001','opaque-bundle-sso-fixture',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','1fe36000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"3fe36000-0000-4000-8000-000000000001","aal":"aal1"}',true);
do $$ declare p jsonb:=jsonb_build_object('id','5fe36000-0000-4000-8000-000000000004','expected_updated_at',null,
 'changes',jsonb_build_object('nome','SSO fixture'),'equipment',jsonb_build_object('id','6fe36000-0000-4000-8000-000000000004',
 'expected_updated_at',null,'expected_context_version',null,'changes',jsonb_build_object('fabricante','Fixture')));
 rid uuid:='afe36000-0000-4000-8000-000000000006'; result jsonb; begin
 set local role authenticated;
 begin perform public.rm_web_mutate_v1(rid,'save_project_with_equipment',p); raise exception 'FAIL: missing SSO permit accepted';
 exception when insufficient_privilege then null; end;
 reset role;
 begin perform public.rm_sso_action_permit_v1(repeat('9',64),rid,'save_project_with_equipment',p,'em.projects.read');
 raise exception 'FAIL: wrong SSO capability accepted'; exception when invalid_parameter_value then null; end;
 perform public.rm_sso_action_permit_v1(repeat('9',64),rid,'save_project_with_equipment',p,'em.projects.manage');
 set local role authenticated;
 begin perform public.rm_web_mutate_v1(rid,'save_project_with_equipment',jsonb_set(p,'{changes,nome}','"Outro"'));
 raise exception 'FAIL: mismatched SSO payload accepted'; exception when insufficient_privilege then null; end;
 result:=public.rm_web_mutate_v1(rid,'save_project_with_equipment',p);
 perform pg_temp.check_bundle((result->'record' ?& array['id','equipamento_id']) and not (result->'record' ? 'arquivo_nota_fiscal_url'),'SSO output is minimal');
 begin perform public.rm_web_mutate_v1(rid,'save_project_with_equipment',p); raise exception 'FAIL: replay without fresh permit accepted';
 exception when insufficient_privilege then null; end;
 reset role;
 perform public.rm_sso_action_permit_v1(repeat('9',64),rid,'save_project_with_equipment',p,'em.projects.manage');
 set local role authenticated; result:=public.rm_web_mutate_v1(rid,'save_project_with_equipment',p);
 perform pg_temp.check_bundle((result->>'idempotent_replay')::boolean,'SSO replay with fresh permit');
 reset role;
end $$;
rollback;

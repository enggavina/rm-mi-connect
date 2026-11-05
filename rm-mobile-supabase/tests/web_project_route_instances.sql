\set ON_ERROR_STOP on
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required'; end if; end $$;
create function pg_temp.route_check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('10370000-0000-4000-8000-000000000001'),('10370000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 ('20370000-0000-4000-8000-000000000001','10370000-0000-4000-8000-000000000001','Route admin fixture','administrador','ativo'),
 ('20370000-0000-4000-8000-000000000002','10370000-0000-4000-8000-000000000002','Route mobile fixture','mobile','ativo');
insert into public.rm_celulas(id,nome,ordem) values
 ('40370000-0000-4000-8000-000000000001','Route A',1),('40370000-0000-4000-8000-000000000002','Route B',2),('40370000-0000-4000-8000-000000000003','Route X',3);
insert into public.rm_tipos_equipamento(id,nome,sigla) values('50370000-0000-4000-8000-000000000001','Motor route','M'),('50370000-0000-4000-8000-000000000002','Empty route','E');
insert into public.rm_forms(id,titulo) values('70370000-0000-4000-8000-000000000001','Route form A'),('70370000-0000-4000-8000-000000000002','Route form B');
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id,visibilidade) values
 ('60370000-0000-4000-8000-000000000001','40370000-0000-4000-8000-000000000001','50370000-0000-4000-8000-000000000001',true),
 ('60370000-0000-4000-8000-000000000002','40370000-0000-4000-8000-000000000002','50370000-0000-4000-8000-000000000001',false);
insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id) values('60370000-0000-4000-8000-000000000001','70370000-0000-4000-8000-000000000001');
insert into public.rm_cadastro_fotos(id,titulo) values('80370000-0000-4000-8000-000000000001','Frontal fixture');
insert into public.rm_fotos(id,celula_id,celula_tipo_equipamento_id,cadastro_foto_id,categoria_foto,titulo,descricao,legenda,tag,numero,foto_url,selecao_relatorio) values
 ('90370000-0000-4000-8000-000000000001','40370000-0000-4000-8000-000000000001','60370000-0000-4000-8000-000000000001','80370000-0000-4000-8000-000000000001','obrigat_ria',null,'Instruction fixture','Caption fixture','frontal',2,'https://invalid.example/never-clone.jpg',true);
insert into public.rm_aprovacoes_etapas(id,celula_tipo_equipamento_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids) values
 ('a0370000-0000-4000-8000-000000000001','60370000-0000-4000-8000-000000000001','40370000-0000-4000-8000-000000000001','40370000-0000-4000-8000-000000000002','finalizado',true,array['20370000-0000-4000-8000-000000000001']::uuid[],array['20370000-0000-4000-8000-000000000002']::uuid[]);
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','10370000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create function pg_temp.route_payload(pid uuid,eid uuid,tid uuid) returns jsonb language sql as $$
 select jsonb_build_object('id',pid,'expected_updated_at',null,'changes',jsonb_build_object('nome','Route fixture'),
 'equipment',jsonb_build_object('id',eid,'tipo_equipamento_id',tid,'expected_updated_at',null,'expected_context_version',null,'changes',jsonb_build_object('descricao','Route motor')));
$$;
set local role authenticated;
do $$ declare p jsonb; r jsonb; s jsonb; a uuid; rid uuid:='d0370000-0000-4000-8000-000000000001'; before_ids uuid[]; begin
 -- Old web creation entry points are closed at the server boundary. These
 -- requests must leave no project, equipment, route or receipt behind.
 p:=pg_temp.route_payload('b0370000-0000-4000-8000-00000000000c','c0370000-0000-4000-8000-00000000000c','50370000-0000-4000-8000-000000000001') #- '{equipment,tipo_equipamento_id}';
 begin perform public.rm_web_mutate_v1('d0370000-0000-4000-8000-00000000000c','save_project_with_equipment',p);raise exception 'FAIL: fresh untyped bundle accepted';exception when sqlstate 'PT423' then null;end;
 begin perform public.rm_web_mutate_v1('d0370000-0000-4000-8000-00000000000d','save_project',jsonb_build_object('id','b0370000-0000-4000-8000-00000000000d','expected_updated_at',null,'changes',jsonb_build_object('nome','Must not create without equipment')));raise exception 'FAIL: fresh project-only create accepted';exception when sqlstate 'PT423' then null;end;
 perform pg_temp.route_check(not exists(select 1 from public.rm_projetos where id in('b0370000-0000-4000-8000-00000000000c','b0370000-0000-4000-8000-00000000000d'))
  and not exists(select 1 from public.rm_equipamentos where id='c0370000-0000-4000-8000-00000000000c'),'fresh legacy entry points have no partial rows');
 p:=pg_temp.route_payload('b0370000-0000-4000-8000-000000000001','c0370000-0000-4000-8000-000000000001','50370000-0000-4000-8000-000000000001');
 r:=public.rm_web_mutate_v1(rid,'save_project_with_equipment',p);
 perform pg_temp.route_check((select equipamento_id='c0370000-0000-4000-8000-000000000001' and tipo_equipamento_id is null from public.rm_projetos where id='b0370000-0000-4000-8000-000000000001'),'project links equipment without redundant type writes');
 perform pg_temp.route_check((select projeto_id='b0370000-0000-4000-8000-000000000001' and tipo_equipamento_id='50370000-0000-4000-8000-000000000001' from public.rm_equipamentos where id='c0370000-0000-4000-8000-000000000001'),'canonical equipment type stored');
 perform pg_temp.route_check((select created_by_user_id='20370000-0000-4000-8000-000000000001' from public.rm_projetos where id='b0370000-0000-4000-8000-000000000001'),'fresh creation derives author from authenticated actor');
 perform pg_temp.route_check((select count(*)=2 from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000001'),'all active model cells cloned');
 select id into a from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000001' and celula_id='40370000-0000-4000-8000-000000000001';
 perform pg_temp.route_check(a<>'60370000-0000-4000-8000-000000000001' and (select forms_ids=array['70370000-0000-4000-8000-000000000001']::uuid[] and indice=1 and visibilidade from public.rm_celulas_projeto where id=a),'allocation owns its identity, order, visibility and form links');
 perform pg_temp.route_check((select count(*)=1 from public.rm_fotos where projeto_id='b0370000-0000-4000-8000-000000000001' and id<>'90370000-0000-4000-8000-000000000001' and celula_projeto_id=a and tag='frontal' and descricao='Instruction fixture' and legenda='Caption fixture' and foto_url is null and not selecao_relatorio),'photo configuration copied without captures or report selections');
 perform pg_temp.route_check((select count(*)=1 from public.rm_aprovacoes_etapas where projeto_id='b0370000-0000-4000-8000-000000000001' and id<>'a0370000-0000-4000-8000-000000000001' and celula_projeto_id=a and status='nulo' and bloquear_avanco_sem_aprov and aprovadores_ids=array['20370000-0000-4000-8000-000000000001']::uuid[] and aprovadores_retorno_ids=array['20370000-0000-4000-8000-000000000002']::uuid[]),'approval configuration and approvers cloned independently');
 select array_agg(id order by id) into before_ids from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000001';
 r:=public.rm_web_mutate_v1(rid,'save_project_with_equipment',p);
 perform pg_temp.route_check((r->>'idempotent_replay')::boolean and before_ids=(select array_agg(id order by id) from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000001'),'duplicate submission preserves clone identities');
 s:=public.rm_web_project_equipment_snapshot_v1('b0370000-0000-4000-8000-000000000001');
 perform pg_temp.route_check((s->>'has_project_route')::boolean and not (s->>'can_change_type')::boolean and (s->>'type_mismatch')::boolean,'route evidence and backward-compatible raw mismatch flag');
 s:=public.rm_web_project_route_snapshot_v1('b0370000-0000-4000-8000-000000000001');
 perform pg_temp.route_check((s->>'initialized_from_type')::boolean and s->>'source_type_id'='50370000-0000-4000-8000-000000000001' and jsonb_array_length(s->'items')=2,'project route snapshot displays own allocations and source evidence');
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000002','c0370000-0000-4000-8000-000000000002','50370000-0000-4000-8000-000000000001'));
 -- Change A's form links and delay through the existing planning gateway.
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_build_object('projeto_id','b0370000-0000-4000-8000-000000000001','celula_id','40370000-0000-4000-8000-000000000001','expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=a),'changes',jsonb_build_object('forms_ids',jsonb_build_array('70370000-0000-4000-8000-000000000002'),'motivo_atraso','Delay fixture')));
 perform pg_temp.route_check((select motivo_atraso='Delay fixture' from public.rm_celulas_projeto where id=a),'cell delay saved on allocation');
 perform pg_temp.route_check((select forms_ids=array['70370000-0000-4000-8000-000000000001']::uuid[] from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000002' and celula_id='40370000-0000-4000-8000-000000000001'),'project B not affected by project A edit');
 s:=public.rm_web_project_equipment_snapshot_v1('b0370000-0000-4000-8000-000000000001');
 p:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','changes','{}'::jsonb,'equipment',jsonb_build_object('id',s->'equipment'->>'id','tipo_equipamento_id','50370000-0000-4000-8000-000000000002','expected_updated_at',s->'equipment'->>'updated_at','expected_context_version',s->>'context_version','changes','{}'::jsonb));
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',p); raise exception 'FAIL: route overwritten by type change'; exception when invalid_parameter_value then null; end;
 -- Explicit null/unknown type and malformed payload never leave partial rows.
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000003','c0370000-0000-4000-8000-000000000003',null)); raise exception 'FAIL: missing new type accepted'; exception when invalid_parameter_value then null; end;
 perform pg_temp.route_check(not exists(select 1 from public.rm_projetos where id='b0370000-0000-4000-8000-000000000003'),'missing type rolls back project');
end $$;
reset role;
do $$ begin
 perform pg_temp.route_check(not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id in('d0370000-0000-4000-8000-00000000000c','d0370000-0000-4000-8000-00000000000d'))
  and not exists(select 1 from rm_private.project_route_instances where projeto_id in('b0370000-0000-4000-8000-00000000000c','b0370000-0000-4000-8000-00000000000d')),'rejected fresh legacy commands consume no receipts or route markers');
 perform pg_temp.route_check((select count(*)=1 from public.rm_celula_form_tipos_equipamento where celula_tipo_equipamento_id='60370000-0000-4000-8000-000000000001' and form_id='70370000-0000-4000-8000-000000000001' and ativo),'project form edit leaves template unchanged');
end $$;
-- Future template mutations never refresh either existing route.
update public.rm_celula_form_tipos_equipamento set ativo=false where celula_tipo_equipamento_id='60370000-0000-4000-8000-000000000001';
update public.rm_fotos set titulo='Changed template photo' where id='90370000-0000-4000-8000-000000000001';
update public.rm_cadastro_fotos set titulo='Renamed catalog title' where id='80370000-0000-4000-8000-000000000001';
update public.rm_aprovacoes_etapas set bloquear_avanco_sem_aprov=false where id='a0370000-0000-4000-8000-000000000001';
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id) values('60370000-0000-4000-8000-000000000003','40370000-0000-4000-8000-000000000003','50370000-0000-4000-8000-000000000001');
insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id) values('60370000-0000-4000-8000-000000000003','70370000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ declare r jsonb; s jsonb; p jsonb; begin
 perform pg_temp.route_check((select count(*)=2 from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000002'),'new template cell not propagated');
 perform pg_temp.route_check((select titulo='Frontal fixture' from public.rm_fotos where projeto_id='b0370000-0000-4000-8000-000000000002'),'legacy catalog fallback frozen before later template/catalog title edits');
 perform pg_temp.route_check((select bloquear_avanco_sem_aprov from public.rm_aprovacoes_etapas where projeto_id='b0370000-0000-4000-8000-000000000002'),'template rule edit not propagated');
 -- New cell in an existing project is an explicit project exception, not a
 -- late dynamic copy of the model that happens to exist now.
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell','{"projeto_id":"b0370000-0000-4000-8000-000000000001","celula_id":"40370000-0000-4000-8000-000000000003","expected_updated_at":null,"changes":{}}');
 perform pg_temp.route_check((select forms_ids='{}'::uuid[] from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000001' and celula_id='40370000-0000-4000-8000-000000000003'),'later allocation does not read latest template');
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000004','c0370000-0000-4000-8000-000000000004','50370000-0000-4000-8000-000000000001'));
 perform pg_temp.route_check((select count(*)=3 from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000004'),'future project gets current template');
 -- An empty model is a valid independent route and still gets a one-time marker.
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000005','c0370000-0000-4000-8000-000000000005','50370000-0000-4000-8000-000000000002'));
 s:=public.rm_web_project_route_snapshot_v1('b0370000-0000-4000-8000-000000000005');
 perform pg_temp.route_check((s->>'initialized_from_type')::boolean and s->>'total'='0','empty model initialization is durable');
 -- Canonical equipment type drives receipt filters even though the legacy
 -- project column was intentionally never written.
 s:=public.rm_web_receivings_v1('without_type','',1,100);
 perform pg_temp.route_check(not exists(select 1 from jsonb_array_elements(s->'items') x where x->>'id' like 'b0370000-%'),'receiving without-type filter excludes canonical classified projects');
 -- No privilege on private snapshots or internal clone commands.
 begin perform origin_snapshot from rm_private.project_route_instances; raise exception 'FAIL: private snapshot readable'; exception when insufficient_privilege then null; end;
 begin perform rm_private.initialize_project_route_v1('b0370000-0000-4000-8000-000000000005','20370000-0000-4000-8000-000000000001',gen_random_uuid()); raise exception 'FAIL: private clone callable'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ declare r jsonb; begin
 r:=public.rm_materialize_project_cells_v1('b0370000-0000-4000-8000-000000000002');
 perform pg_temp.route_check(r->>'celulas_materializadas'='0','service materialization cannot refresh initialized route');
end $$;
-- The model's exact displayed ordering is frozen into instance ordinals,
-- including tied positions, secondary indices and null positions.
insert into public.rm_tipos_equipamento(id,nome) values('50370000-0000-4000-8000-000000000003','Ordering type');
insert into public.rm_celulas(id,nome,ordem,indice) values
 ('40370000-0000-4000-8000-000000000004','Tied order second',8,2),
 ('40370000-0000-4000-8000-000000000005','Tied order first',8,1),
 ('40370000-0000-4000-8000-000000000006','Null order last',null,0);
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id) values
 ('60370000-0000-4000-8000-000000000004','40370000-0000-4000-8000-000000000004','50370000-0000-4000-8000-000000000003'),
 ('60370000-0000-4000-8000-000000000005','40370000-0000-4000-8000-000000000005','50370000-0000-4000-8000-000000000003'),
 ('60370000-0000-4000-8000-000000000006','40370000-0000-4000-8000-000000000006','50370000-0000-4000-8000-000000000003');
-- Legacy project/equipment whose type already matches: no-op technical edits
-- must still get binding protection when the route is first initialized.
insert into public.rm_projetos(id,nome,tipo_equipamento_id) values
 ('b0370000-0000-4000-8000-000000000009','Legacy pretyped','50370000-0000-4000-8000-000000000001'),
 ('b0370000-0000-4000-8000-00000000000a','Legacy without equipment',null);
insert into public.rm_equipamentos(id,projeto_id,tipo_equipamento_id) values('c0370000-0000-4000-8000-000000000009','b0370000-0000-4000-8000-000000000009','50370000-0000-4000-8000-000000000002');
update public.rm_projetos set equipamento_id='c0370000-0000-4000-8000-000000000009' where id='b0370000-0000-4000-8000-000000000009';
set local role authenticated;
do $$ declare r jsonb;s jsonb;p jsonb;begin
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000008','c0370000-0000-4000-8000-000000000008','50370000-0000-4000-8000-000000000003'));
 perform pg_temp.route_check((select array_agg(celula_id order by indice)=array['40370000-0000-4000-8000-000000000005','40370000-0000-4000-8000-000000000004','40370000-0000-4000-8000-000000000006']::uuid[] from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000008'),'tied/null model ordering freezes deterministically');
 s:=public.rm_web_project_equipment_snapshot_v1('b0370000-0000-4000-8000-000000000009');
 p:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','changes','{}'::jsonb,'equipment',jsonb_build_object('id',s->'equipment'->>'id','tipo_equipamento_id','50370000-0000-4000-8000-000000000002','expected_updated_at',s->'equipment'->>'updated_at','expected_context_version',s->>'context_version','changes','{}'::jsonb));
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',p);
 perform pg_temp.route_check((public.rm_web_project_route_snapshot_v1('b0370000-0000-4000-8000-000000000009')->>'initialized_from_type')::boolean,'legacy pretyped equipment gains independent route without rewriting old project type');
 s:=public.rm_web_project_equipment_snapshot_v1('b0370000-0000-4000-8000-00000000000a');
 perform pg_temp.route_check(s->>'binding_state'='missing' and (s->>'can_change_type')::boolean,'missing legacy equipment permits explicit classification');
 p:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','changes','{}'::jsonb,'equipment',jsonb_build_object('id','c0370000-0000-4000-8000-00000000000a','tipo_equipamento_id','50370000-0000-4000-8000-000000000002','expected_updated_at',null,'expected_context_version',s->>'context_version','changes','{}'::jsonb));
 r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',p);
 perform pg_temp.route_check((public.rm_web_project_route_snapshot_v1('b0370000-0000-4000-8000-00000000000a')->>'initialized_from_type')::boolean,'legacy project without equipment is completed atomically');
end $$;
reset role;
do $$ begin
 begin update public.rm_equipamentos set tipo_equipamento_id='50370000-0000-4000-8000-000000000001' where id='c0370000-0000-4000-8000-000000000009';raise exception 'FAIL: direct type drift after no-op initialization';exception when sqlstate 'PT409' then null;end;
 begin update public.rm_equipamentos set projeto_id=null where id='c0370000-0000-4000-8000-000000000009';raise exception 'FAIL: direct equipment rebind';exception when sqlstate 'PT409' then null;end;
 begin update public.rm_projetos set equipamento_id=null where id='b0370000-0000-4000-8000-000000000009';raise exception 'FAIL: direct project rebind';exception when sqlstate 'PT409' then null;end;
 begin insert into public.rm_projetos(id,nome,equipamento_id) values('b0370000-0000-4000-8000-00000000000b','Must not share equipment','c0370000-0000-4000-8000-000000000009');raise exception 'FAIL: inverse project insertion shares protected equipment';exception when sqlstate 'PT409' then null;end;
end $$;
update public.rm_celulas set ordem=100 where id='40370000-0000-4000-8000-000000000005';
do $$ begin perform pg_temp.route_check((select celula_id='40370000-0000-4000-8000-000000000005' from public.rm_celulas_projeto where projeto_id='b0370000-0000-4000-8000-000000000008' and indice=1),'global cell reorder does not change project route');end $$;
-- Invalid destination causes the entire typed create to roll back.
update public.rm_celula_tipos_equipamento set ativo=false where id='60370000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000006','c0370000-0000-4000-8000-000000000006','50370000-0000-4000-8000-000000000001')); raise exception 'FAIL: partial route accepted'; exception when sqlstate 'PT422' then null; end;
 perform pg_temp.route_check(not exists(select 1 from public.rm_projetos where id='b0370000-0000-4000-8000-000000000006') and not exists(select 1 from public.rm_equipamentos where id='c0370000-0000-4000-8000-000000000006'),'invalid model rolls back project/equipment/route');
end $$;
reset role;
select set_config('request.jwt.claim.sub','10370000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$ begin begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_with_equipment',pg_temp.route_payload('b0370000-0000-4000-8000-000000000007','c0370000-0000-4000-8000-000000000007','50370000-0000-4000-8000-000000000002')); raise exception 'FAIL: unauthorized type/clone'; exception when insufficient_privilege then null; end; end $$;
reset role;
rollback;

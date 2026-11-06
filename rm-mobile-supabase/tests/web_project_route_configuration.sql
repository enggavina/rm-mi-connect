\set ON_ERROR_STOP on
begin;
create function pg_temp.rc_id(h text,n int) returns uuid language sql immutable as $$select(h||'d400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.rc_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.rc_payload(action text,n int,forms uuid[] default null) returns jsonb language sql as $$
 with s as(select public.rm_web_project_route_cell_snapshot_v1(pg_temp.rc_id('5',case when n=11 then 2 else 1 end),pg_temp.rc_id('6',n),true) v)
 select jsonb_build_object('action',action,'projeto_id',v->'project'->>'id','celula_projeto_id',v->'allocation'->>'id','expected_project_updated_at',v->'project'->>'updated_at',
  'expected_allocation_updated_at',v->'allocation'->>'updated_at','expected_context_version',v->>'context_version','confirm_change',true)||case when action='forms' then jsonb_build_object('forms_ids',forms) else '{}'::jsonb end from s;
$$;
insert into auth.users(id) values(pg_temp.rc_id('1',1)),(pg_temp.rc_id('1',2));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.rc_id('2',1),pg_temp.rc_id('1',1),'Route configuration planner','administrador','ativo'),(pg_temp.rc_id('2',2),pg_temp.rc_id('1',2),'Route configuration auditor','auditor','ativo');
insert into public.rm_projetos(id,nome) values(pg_temp.rc_id('5',1),'Route config A'),(pg_temp.rc_id('5',2),'Route config B');
insert into public.rm_celulas(id,nome) select pg_temp.rc_id('4',n),'Route configuration cell '||n from generate_series(1,4) n;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) select pg_temp.rc_id('4',n),pg_temp.rc_id('2',1),pg_temp.rc_id('2',1) from generate_series(1,4)n;
insert into public.rm_forms(id,titulo,ativo) select pg_temp.rc_id('7',n),'Route form '||n,true from generate_series(1,3) n;
insert into public.rm_questoes(id,form_id,enunciado,tipo) values(pg_temp.rc_id('a',1),pg_temp.rc_id('7',1),'Partial answer','texto_curto'),(pg_temp.rc_id('a',2),pg_temp.rc_id('7',2),'Draft answer','texto_curto');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids,indice,visibilidade)
 select pg_temp.rc_id('6',n),pg_temp.rc_id('5',1),pg_temp.rc_id('4',n),case when n=1 then array[pg_temp.rc_id('7',1),pg_temp.rc_id('7',2)] when n=2 then array[pg_temp.rc_id('7',1)] else '{}'::uuid[] end,n,true from generate_series(1,4) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids,indice,visibilidade) values(pg_temp.rc_id('6',11),pg_temp.rc_id('5',2),pg_temp.rc_id('4',1),array[pg_temp.rc_id('7',1)],1,true);
insert into public.rm_cadastro_fotos(id,titulo) select pg_temp.rc_id('8',n),'Route photo title '||n from generate_series(1,4) n;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,cadastro_foto_id,titulo,categoria_foto,numero,foto_url) values
 (pg_temp.rc_id('9',1),pg_temp.rc_id('5',1),pg_temp.rc_id('4',1),pg_temp.rc_id('6',1),pg_temp.rc_id('8',1),'Route photo title 1','obrigat_ria',1,null),
 (pg_temp.rc_id('9',2),pg_temp.rc_id('5',1),pg_temp.rc_id('4',1),pg_temp.rc_id('6',1),pg_temp.rc_id('8',2),'Route photo title 2','obrigat_ria',2,'https://invalid.example/preserved-capture.jpg'),
 (pg_temp.rc_id('9',3),pg_temp.rc_id('5',1),pg_temp.rc_id('4',2),pg_temp.rc_id('6',2),pg_temp.rc_id('8',3),'Route photo title 3','obrigat_ria',1,null);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status,status_cel_proj) values
 (pg_temp.rc_id('c',1),pg_temp.rc_id('5',1),pg_temp.rc_id('6',2),pg_temp.rc_id('4',2),pg_temp.rc_id('4',3),'nulo','em_dia'),
 (pg_temp.rc_id('c',2),pg_temp.rc_id('5',1),pg_temp.rc_id('6',1),pg_temp.rc_id('4',1),pg_temp.rc_id('4',4),'aprovado','em_dia'),
 (pg_temp.rc_id('c',3),pg_temp.rc_id('5',1),pg_temp.rc_id('6',1),pg_temp.rc_id('4',1),pg_temp.rc_id('4',3),'nulo','em_dia');
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,preenchido,status) values(pg_temp.rc_id('b',1),pg_temp.rc_id('5',1),pg_temp.rc_id('4',1),pg_temp.rc_id('7',1),false,'em_an_lise');
insert into public.rm_respostas(registro_formulario_id,questao_id,resposta) values(pg_temp.rc_id('b',1),pg_temp.rc_id('a',1),'Partial persisted response');
insert into public.rm_form_reviewer_assignments(projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id) values(pg_temp.rc_id('5',1),pg_temp.rc_id('4',2),pg_temp.rc_id('6',2),pg_temp.rc_id('7',1),pg_temp.rc_id('2',1));
create function pg_temp.rc_fail_cleanup() returns trigger language plpgsql as $$begin
 if new.id=pg_temp.rc_id('6',2) and new.retirada and current_setting('rm.test.fail_route_cleanup',true)='on' then raise exception 'Synthetic local cleanup failure';end if;return new;end$$;
create trigger zz_local_rc_failure before update on public.rm_celulas_projeto for each row execute function pg_temp.rc_fail_cleanup();
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub',pg_temp.rc_id('1',1)::text,true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
do $$declare s jsonb;p jsonb;r jsonb;rid uuid:=pg_temp.rc_id('e',1);begin
 s:=public.rm_web_project_route_cell_snapshot_v1(pg_temp.rc_id('5',1),pg_temp.rc_id('6',1),true);
 perform pg_temp.rc_check((s->>'can_edit_forms')::boolean and not(s->>'can_remove_cell')::boolean,'used photo/approval does not block unused form configuration');
 perform pg_temp.rc_check(exists(select 1 from jsonb_array_elements(s->'forms') f where f->>'id'=pg_temp.rc_id('7',1)::text and not(f->>'can_remove')::boolean),'partially answered form protected');
 p:=pg_temp.rc_payload('forms',1,array[pg_temp.rc_id('7',1)]);r:=public.rm_web_mutate_v1(rid,'manage_project_route_cell',p);
 perform pg_temp.rc_check((select forms_ids=array[pg_temp.rc_id('7',1)] from public.rm_celulas_projeto where id=pg_temp.rc_id('6',1)),'only unused form removed');
 perform pg_temp.rc_check((public.rm_web_mutate_v1(rid,'manage_project_route_cell',p)->>'idempotent_replay')::boolean,'form command replays exact result');
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_project_route_cell',pg_temp.rc_payload('forms',1,'{}'));raise exception 'FAIL: partially used form removed';exception when sqlstate 'PT409' or invalid_parameter_value then null;end;
 perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_project_route_cell',pg_temp.rc_payload('forms',1,array[pg_temp.rc_id('7',1),pg_temp.rc_id('7',2)]));
end$$;
reset role;
insert into public.rm_respostas_temp(id,projeto_id,form_id,questao_id,operador_user_id,resposta) values(pg_temp.rc_id('f',1),pg_temp.rc_id('5',1),pg_temp.rc_id('7',2),pg_temp.rc_id('a',2),pg_temp.rc_id('2',1),'Draft without registration');
set local role authenticated;
do $$begin
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_project_route_cell',pg_temp.rc_payload('forms',1,array[pg_temp.rc_id('7',1)]));raise exception 'FAIL: draft form removed';exception when sqlstate 'PT409' then null;end;
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',jsonb_build_object('projeto_id',pg_temp.rc_id('5',1),'celula_id',pg_temp.rc_id('4',1),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.rc_id('6',1)),'changes',jsonb_build_object('forms_ids',jsonb_build_array(pg_temp.rc_id('7',1)))));raise exception 'FAIL: legacy plan entry removed draft form';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
delete from public.rm_respostas_temp where id=pg_temp.rc_id('f',1);
set local role authenticated;
do $$declare s jsonb;p jsonb;r jsonb;begin
 s:=public.rm_web_operational_photos_snapshot_v1(pg_temp.rc_id('5',1),pg_temp.rc_id('6',1),true);
 p:=jsonb_build_object('action','replace','projeto_id',pg_temp.rc_id('5',1),'celula_projeto_id',pg_temp.rc_id('6',1),'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_photos_version',s->>'photos_version',
  'foto_id',pg_temp.rc_id('9',1),'expected_foto_updated_at',(select updated_at from public.rm_fotos where id=pg_temp.rc_id('9',1)),'new_id',pg_temp.rc_id('9',4),'cadastro_foto_id',pg_temp.rc_id('8',4),'numero',3,'descricao','New instruction','tag','new tag','confirm_change',true);
 r:=public.rm_web_mutate_v1(pg_temp.rc_id('e',2),'manage_operational_photos',p);
 perform pg_temp.rc_check((select lixeira from public.rm_fotos where id=pg_temp.rc_id('9',1)) and(select not lixeira and titulo='Route photo title 4' and descricao='New instruction' and foto_url is null from public.rm_fotos where id=pg_temp.rc_id('9',4)),'replacement owns new identity; original slot retired');
 perform pg_temp.rc_check((public.rm_web_mutate_v1(pg_temp.rc_id('e',2),'manage_operational_photos',p)->>'idempotent_replay')::boolean,'photo replacement replay');
 s:=public.rm_web_operational_photos_snapshot_v1(pg_temp.rc_id('5',1),pg_temp.rc_id('6',1),true);
 p:=p||jsonb_build_object('foto_id',pg_temp.rc_id('9',2),'expected_foto_updated_at',(select updated_at from public.rm_fotos where id=pg_temp.rc_id('9',2)),'new_id',pg_temp.rc_id('9',5),'expected_photos_version',s->>'photos_version');
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_operational_photos',p);raise exception 'FAIL: captured photo replaced';exception when sqlstate 'PT409' then null;end;
 s:=public.rm_web_stage_rules_snapshot_v1(pg_temp.rc_id('5',1),pg_temp.rc_id('6',1),true);
 p:=jsonb_build_object('action','replace','projeto_id',pg_temp.rc_id('5',1),'celula_projeto_id',pg_temp.rc_id('6',1),'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_rules_version',s->>'rules_version','etapa_id',pg_temp.rc_id('c',3),'expected_etapa_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=pg_temp.rc_id('c',3)),'replacement_id',pg_temp.rc_id('c',4),'confirm_change',true,
  'config',jsonb_build_object('celula_destino_id',pg_temp.rc_id('4',3),'status_cel_proj','em_dia','bloquear_avanco_sem_aprov',false,'aprovadores_ids',jsonb_build_array(pg_temp.rc_id('2',1)),'aprovadores_retorno_ids',jsonb_build_array(pg_temp.rc_id('2',1))));
 perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_stage_rules',p);
 perform pg_temp.rc_check((select not ativo from public.rm_aprovacoes_etapas where id=pg_temp.rc_id('c',3)) and(select ativo and not configuracao_utilizada from public.rm_aprovacoes_etapas where id=pg_temp.rc_id('c',4)),'unused approval remains editable despite another used approval, partial form and captured photo');
end$$;
reset role;
do $$begin
 begin update public.rm_fotos set foto_url=null where id=pg_temp.rc_id('9',2);raise exception 'FAIL: capture erased to unlock configuration';exception when sqlstate 'PT409' then null;end;
 begin update public.rm_fotos set titulo='Wrong new title' where id=pg_temp.rc_id('9',2);raise exception 'FAIL: captured photo title changed';exception when sqlstate 'PT409' then null;end;
 update public.rm_fotos set tag='Non destructive metadata' where id=pg_temp.rc_id('9',2);
 update public.rm_aprovacoes_etapas set status='nulo',aprovado_por_id=null,data_aprovacao=null,configuracao_utilizada=false where id=pg_temp.rc_id('c',2);
 perform pg_temp.rc_check((select configuracao_utilizada from public.rm_aprovacoes_etapas where id=pg_temp.rc_id('c',2)),'live decision reset cannot erase usage');
 begin update public.rm_aprovacoes_etapas set ativo=false where id=pg_temp.rc_id('c',2);raise exception 'FAIL: used approval disabled after live state reset';exception when sqlstate 'PT409' then null;end;
end$$;
set local role authenticated;
do $$declare s jsonb;p jsonb;r jsonb;rid uuid:=pg_temp.rc_id('e',3);begin
 s:=public.rm_web_project_route_snapshot_v1(pg_temp.rc_id('5',1));
 perform pg_temp.rc_check(exists(select 1 from jsonb_array_elements(s->'items') x where x->>'id'=pg_temp.rc_id('6',1)::text and not(x->>'can_reorder')::boolean),'used approval origin anchored');
 perform pg_temp.rc_check(exists(select 1 from jsonb_array_elements(s->'items') x where x->>'id'=pg_temp.rc_id('6',4)::text and not(x->>'can_reorder')::boolean),'used approval destination anchored');
 p:=jsonb_build_object('projeto_id',pg_temp.rc_id('5',1),'expected_project_updated_at',s->'project'->>'updated_at','expected_route_version',s->>'route_version','items',jsonb_build_array(
  jsonb_build_object('id',pg_temp.rc_id('6',1),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.rc_id('6',1))),jsonb_build_object('id',pg_temp.rc_id('6',3),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.rc_id('6',3))),
  jsonb_build_object('id',pg_temp.rc_id('6',2),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.rc_id('6',2))),jsonb_build_object('id',pg_temp.rc_id('6',4),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.rc_id('6',4)))));
 perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_route',p);
 s:=public.rm_web_project_route_snapshot_v1(pg_temp.rc_id('5',1));
 p:=p||jsonb_build_object('expected_route_version',s->>'route_version','items',jsonb_build_array(jsonb_build_object('id',pg_temp.rc_id('6',3)),jsonb_build_object('id',pg_temp.rc_id('6',1)),jsonb_build_object('id',pg_temp.rc_id('6',2)),jsonb_build_object('id',pg_temp.rc_id('6',4))));
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project_route',p);raise exception 'FAIL: approval sequence moved';exception when sqlstate 'PT409' then null;end;
 p:=pg_temp.rc_payload('remove',2);
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_project_route_cell',p||jsonb_build_object('confirm_change',false));raise exception 'FAIL: cell removed without confirmation';exception when invalid_parameter_value then null;end;
 perform set_config('rm.test.fail_route_cleanup','on',true);
 begin perform public.rm_web_mutate_v1(pg_temp.rc_id('e',20),'manage_project_route_cell',p);raise exception 'FAIL: fixture did not fail';exception when raise_exception then if sqlerrm<>'Synthetic local cleanup failure' then raise;end if;end;
 perform set_config('rm.test.fail_route_cleanup','off',true);
 perform pg_temp.rc_check((select not retirada and cardinality(forms_ids)=1 from public.rm_celulas_projeto where id=pg_temp.rc_id('6',2)) and(select not lixeira from public.rm_fotos where id=pg_temp.rc_id('9',3)) and(select ativo from public.rm_aprovacoes_etapas where id=pg_temp.rc_id('c',1)) and exists(select 1 from public.rm_form_reviewer_assignments where celula_projeto_id=pg_temp.rc_id('6',2)),'failure after child cleanup rolls the entire action back');
 r:=public.rm_web_mutate_v1(rid,'manage_project_route_cell',p);
 perform pg_temp.rc_check((select retirada and not visibilidade and cardinality(forms_ids)=0 from public.rm_celulas_projeto where id=pg_temp.rc_id('6',2)),'cell removed from active route without losing recovery identity');
 perform pg_temp.rc_check((select lixeira from public.rm_fotos where id=pg_temp.rc_id('9',3)) and(select not ativo from public.rm_aprovacoes_etapas where id=pg_temp.rc_id('c',1)),'unused photo/rule configuration removed');
 perform pg_temp.rc_check(not exists(select 1 from public.rm_form_reviewer_assignments where celula_projeto_id=pg_temp.rc_id('6',2)),'unused reviewer designation removed');
 perform pg_temp.rc_check((public.rm_web_mutate_v1(rid,'manage_project_route_cell',p)->>'idempotent_replay')::boolean,'cell removal replay');
 perform pg_temp.rc_check((select forms_ids=array[pg_temp.rc_id('7',1)] and not retirada from public.rm_celulas_projeto where id=pg_temp.rc_id('6',11)),'other project untouched');
 perform pg_temp.rc_check(exists(select 1 from public.rm_forms where id=pg_temp.rc_id('7',1)) and exists(select 1 from public.rm_celulas where id=pg_temp.rc_id('4',2)),'global entities preserved');
 perform pg_temp.rc_check((public.rm_web_project_audit_v1(pg_temp.rc_id('5',1),'cells')->>'total')::int>0 and(public.rm_web_project_audit_v1(pg_temp.rc_id('5',1),'operations')->>'total')::int>=5,'configuration changes projected into existing history');
end$$;
reset role;
select pg_temp.rc_check(not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=pg_temp.rc_id('e',20)),'failed cleanup leaves no receipt');
do $$begin
 begin perform public.rm_record_cell_photo_v1(pg_temp.rc_id('2',1),pg_temp.rc_id('9',3),pg_temp.rc_id('5',1),pg_temp.rc_id('4',2),pg_temp.rc_id('6',2),'https://invalid.example/late-offline.jpg',null,null,'obrigat_ria');raise exception 'FAIL: stale capture silently applied after removal';exception when sqlstate 'PT409' then null;end;
end$$;
-- Legacy arrays have no FK to the form catalog: an unresolved identity must
-- remain visible for reconciliation rather than becoming a removable row.
update public.rm_celulas_projeto set forms_ids=array[pg_temp.rc_id('7',1),pg_temp.rc_id('7',999)] where id=pg_temp.rc_id('6',11);
set local role authenticated;
do $$declare s jsonb;begin
 s:=public.rm_web_project_route_cell_snapshot_v1(pg_temp.rc_id('5',2),pg_temp.rc_id('6',11),true);
 perform pg_temp.rc_check(not(s->>'complete')::boolean and not(s->>'can_edit_forms')::boolean and not(s->>'can_remove_cell')::boolean,'unresolved legacy form prevents incomplete cleanup');
 perform pg_temp.rc_check(jsonb_array_length(s->'allocation'->'forms_ids')=2 and s->>'forms_reason' is not null and s->>'remove_reason' is not null,'unresolved identity and reconciliation reasons preserved');
end$$;
reset role;
update public.rm_celulas_projeto set forms_ids=array[pg_temp.rc_id('7',1)] where id=pg_temp.rc_id('6',11);
select set_config('request.jwt.claim.sub',pg_temp.rc_id('1',2)::text,true);
set local role authenticated;
do $$begin
 begin perform public.rm_web_mutate_v1(gen_random_uuid(),'manage_project_route_cell',pg_temp.rc_payload('forms',11,'{}'));raise exception 'FAIL: auditor edited configuration';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: 040 granular resources, immutable replacement, draft protection, anchored sequence, retired configuration cleanup, replay and isolation' result;

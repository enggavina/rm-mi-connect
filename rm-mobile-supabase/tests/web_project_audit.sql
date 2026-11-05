\set ON_ERROR_STOP on
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create function pg_temp.audit_check(v boolean,msg text) returns void language plpgsql as $$
 begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('1fe38000-0000-4000-8000-000000000001'),('1fe38000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 ('2fe38000-0000-4000-8000-000000000001','1fe38000-0000-4000-8000-000000000001','Audit admin fixture','administrador','ativo'),
 ('2fe38000-0000-4000-8000-000000000002','1fe38000-0000-4000-8000-000000000002','Audit tablet fixture','mobile','ativo');
insert into public.rm_celulas(id,nome) values('4fe38000-0000-4000-8000-000000000001','Audit cell fixture');
insert into public.rm_projetos(id,nome) values('5fe38000-0000-4000-8000-000000000001','Audit A fixture'),('5fe38000-0000-4000-8000-000000000002','Audit B fixture');
insert into public.rm_forms(id,titulo) values('6fe38000-0000-4000-8000-000000000001','Audit form fixture');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1fe38000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
do $$ declare r jsonb; s jsonb; audit jsonb; payload jsonb; a uuid; begin
 r:=public.rm_web_mutate_v1('afe38000-0000-4000-8000-000000000001','plan_cell',jsonb_build_object(
  'projeto_id','5fe38000-0000-4000-8000-000000000001','celula_id','4fe38000-0000-4000-8000-000000000001','expected_updated_at',null,
  'changes',jsonb_build_object('data_limite','2026-11-10T15:00:00Z','responsavel_id','2fe38000-0000-4000-8000-000000000001',
   'forms_ids',jsonb_build_array('6fe38000-0000-4000-8000-000000000001'),'observacao','Nota literal de planejamento')));
 a:=(r->>'id')::uuid;
 r:=public.rm_web_mutate_v1('afe38000-0000-4000-8000-000000000002','plan_cell',jsonb_build_object(
  'projeto_id','5fe38000-0000-4000-8000-000000000001','celula_id','4fe38000-0000-4000-8000-000000000001','expected_updated_at',r->>'updated_at',
  'changes',jsonb_build_object('data_limite','2026-11-18T15:00:00Z')));
 audit:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells');
 perform pg_temp.audit_check((audit->>'total')::int=2,'allocation create and update each projected once');
 perform pg_temp.audit_check(exists(select 1 from jsonb_array_elements(audit->'items') e cross join lateral jsonb_array_elements(e->'changes') c
  where e->>'action'='allocation_changed' and c->>'field'='data_limite' and (c->>'before')::timestamptz='2026-11-10T15:00:00Z'::timestamptz
   and (c->>'after')::timestamptz='2026-11-18T15:00:00Z'::timestamptz and e->>'actor_name'='Audit admin fixture'),'exact prior and new deadline with actor');
 perform pg_temp.audit_check(not exists(select 1 from jsonb_array_elements(audit->'items') e where e->>'projeto_id'<>'5fe38000-0000-4000-8000-000000000001'),'strict project scope');
 perform pg_temp.audit_check(public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000002','cells')->>'total'='0','project B untouched');
 r:=public.rm_web_mutate_v1('afe38000-0000-4000-8000-000000000003','plan_cell',jsonb_build_object(
  'projeto_id','5fe38000-0000-4000-8000-000000000002','celula_id','4fe38000-0000-4000-8000-000000000001','expected_updated_at',null,'changes','{}'::jsonb));
 s:=public.rm_web_cell_queue_snapshot_v1('4fe38000-0000-4000-8000-000000000001');
 payload:=jsonb_build_object('celula_id','4fe38000-0000-4000-8000-000000000001','expected_queue_version',s->>'queue_version','apply_order',true,
  'items',(select jsonb_agg(jsonb_build_object('id',i->>'id','expected_updated_at',i->>'updated_at','prioridade','alta') order by n desc)
   from jsonb_array_elements(s->'items') with ordinality x(i,n)));
 r:=public.rm_web_mutate_v1('afe38000-0000-4000-8000-000000000004','save_cell_queue',payload);
 audit:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells');
 perform pg_temp.audit_check((audit->>'total')::int=3,'multi-project queue appears once per matching allocation');
 perform pg_temp.audit_check((select count(*)=1 from jsonb_array_elements(audit->'items') e where e->>'action'='queue_changed' and e->>'entity_id'=a::text),'queue row identity retained');
 r:=public.rm_web_mutate_v1('afe38000-0000-4000-8000-000000000004','save_cell_queue',payload);
 perform pg_temp.audit_check((r->>'idempotent_replay')::boolean and public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells')->>'total'='3','replay creates no duplicate audit');
 audit:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','operations');
 perform pg_temp.audit_check((audit->>'total')::int=1 and audit->'items'->0->>'action'='form_links_changed','form links projected from allocation journal only');
end $$;
reset role;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,titulo,categoria_foto,foto_url) select
 '7fe38000-0000-4000-8000-000000000001',projeto_id,celula_id,id,'Audit photo fixture','complementar','https://private.invalid/audit-secret-photo'
 from public.rm_celulas_projeto where projeto_id='5fe38000-0000-4000-8000-000000000001';
insert into public.rm_comentarios(projeto_id,evento,cadastrado_por_id) values('5fe38000-0000-4000-8000-000000000001','AUDIT_COMMENT_MUST_STAY_SEPARATE','2fe38000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ declare r jsonb; audit jsonb; payload jsonb; begin
 payload:=(select jsonb_build_object('projeto_id',projeto_id,'foto_id',id,'expected_updated_at',updated_at,'selected',true) from public.rm_fotos where id='7fe38000-0000-4000-8000-000000000001');
 r:=public.rm_web_mutate_v1('afe38000-0000-4000-8000-000000000005','set_project_photo_selection',payload);
 audit:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','operations');
 perform pg_temp.audit_check((audit->>'total')::int=2,'photo selection recorded');
 perform pg_temp.audit_check(audit::text not like '%private.invalid%' and audit::text not like '%AUDIT_COMMENT%' and audit::text not like '%auth_user_id%' and audit::text not like '%payload%','DTO excludes URLs, credentials and comments');
 perform pg_temp.audit_check(public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','operations',1,array['forms'])->>'total'='1','topic filtering restricts before count and paging');
 perform pg_temp.audit_check(public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','operations',1,'{}')->>'total'='0','no topic grants means no operational records');
 perform pg_temp.audit_check(public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells',999)->>'page'='1','bounded pagination clamps empty tail');
 perform pg_temp.audit_check(public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000099','cells') is null,'missing legacy project is null');
 begin perform public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','comments'); raise exception 'FAIL: invalid kind'; exception when invalid_parameter_value then null; end;
 begin perform public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','operations',1,array['private']); raise exception 'FAIL: invalid topic'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
-- No old-state evidence is invented for a mobile receipt, and the authenticated
-- tablet is not credited as the delegated operator stored in that receipt.
insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result) values
 ('bfe38000-0000-4000-8000-000000000001','1fe38000-0000-4000-8000-000000000002','2fe38000-0000-4000-8000-000000000001','rm_record_cell_photo_v1',
  '{"p_projeto_id":"5fe38000-0000-4000-8000-000000000001","p_foto_url":"https://private.invalid/never-expose"}',
  '{"foto_id":"7fe38000-0000-4000-8000-000000000001"}');
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id)
 select '8fe38000-0000-4000-8000-000000000001',projeto_id,id,celula_id from public.rm_celulas_projeto where projeto_id='5fe38000-0000-4000-8000-000000000001';
insert into public.rm_logs_aprovacao(id,projeto_id,celula_id,aprovador_id,status_aprovacao)
 values('9fe38000-0000-4000-8000-000000000001','5fe38000-0000-4000-8000-000000000001','4fe38000-0000-4000-8000-000000000001','2fe38000-0000-4000-8000-000000000001','aprovado');
insert into public.rm_web_stage_decisions(aprovacao_etapa_id,projeto_id,celula_id,celula_projeto_id,actor_id,acao,status_anterior,status_novo,log_id,client_submission_id)
 select '8fe38000-0000-4000-8000-000000000001',projeto_id,celula_id,id,'2fe38000-0000-4000-8000-000000000001','aprovar','nulo','aprovado',
 '9fe38000-0000-4000-8000-000000000001','afe38000-0000-4000-8000-000000000006' from public.rm_celulas_projeto where projeto_id='5fe38000-0000-4000-8000-000000000001';
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,identidade_user_id) values
 ('cfe38000-0000-4000-8000-000000000001','5fe38000-0000-4000-8000-000000000001','4fe38000-0000-4000-8000-000000000001','6fe38000-0000-4000-8000-000000000001','2fe38000-0000-4000-8000-000000000001');
insert into public.rm_aprovacoes_registro(registro_formulario_id,projeto_id,celula_id,form_id,status,parecer)
 values('cfe38000-0000-4000-8000-000000000001','5fe38000-0000-4000-8000-000000000001','4fe38000-0000-4000-8000-000000000001','6fe38000-0000-4000-8000-000000000001','aprovado','Justificativa histórica preservada');
insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result) values
 ('bfe38000-0000-4000-8000-000000000002','1fe38000-0000-4000-8000-000000000002','2fe38000-0000-4000-8000-000000000001','rm_submit_form_revision_v1',
  '{"p_registro_formulario_id":"cfe38000-0000-4000-8000-000000000001","p_respostas_corrigidas":[{"resposta":"PRIVATE_ANSWER_MUST_NOT_LEAK"}]}',
  '{"registro_formulario_id":"cfe38000-0000-4000-8000-000000000001","novo_status":"em_an_lise","respostas_corrigidas":1}');
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values
 ('4fe38000-0000-4000-8000-000000000001','2fe38000-0000-4000-8000-000000000002','2fe38000-0000-4000-8000-000000000001'),
 ('4fe38000-0000-4000-8000-000000000001','2fe38000-0000-4000-8000-000000000002','2fe38000-0000-4000-8000-000000000002');
set local role authenticated;
do $$ declare audit jsonb; second_page jsonb; s jsonb; f jsonb; allocation_id uuid; result jsonb; reviewer uuid; n int; begin
 select id into allocation_id from public.rm_celulas_projeto where projeto_id='5fe38000-0000-4000-8000-000000000001';
 foreach reviewer in array array['2fe38000-0000-4000-8000-000000000001'::uuid,'2fe38000-0000-4000-8000-000000000002'::uuid] loop
  s:=public.rm_web_form_reviewer_assignments_snapshot_v1('5fe38000-0000-4000-8000-000000000001',allocation_id,true);
  select value into f from jsonb_array_elements(s->'forms') where value->>'id'='6fe38000-0000-4000-8000-000000000001';
  result:=public.rm_web_mutate_v1(gen_random_uuid(),'assign_form_reviewer',jsonb_build_object('projeto_id','5fe38000-0000-4000-8000-000000000001',
   'celula_projeto_id',allocation_id,'form_id','6fe38000-0000-4000-8000-000000000001','avaliador_user_id',reviewer,
   'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at',
   'expected_context_version',f->>'context_version','confirm_replace',true));
 end loop;
 audit:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','operations');
 perform pg_temp.audit_check(exists(select 1 from jsonb_array_elements(audit->'items') i where i->>'source'='mobile'
  and i->>'actor_id'='2fe38000-0000-4000-8000-000000000001' and not(i->>'prior_evidence')::boolean),'delegated actor and unavailable old state retained');
 perform pg_temp.audit_check((select count(*)=1 from jsonb_array_elements(audit->'items') i where i->>'action'='stage_aprovar'),'decision log and web decision projected exactly once');
 perform pg_temp.audit_check(exists(select 1 from jsonb_array_elements(audit->'items') i where i->>'action'='form_corrected')
  and audit::text not like '%PRIVATE_ANSWER_MUST_NOT_LEAK%','form revision action without answer values');
 perform pg_temp.audit_check(exists(select 1 from jsonb_array_elements(audit->'items') i where i->>'action'='form_reviewed'
  and i->>'reason'='Justificativa histórica preservada' and i->'actor_id'='null'::jsonb),'historical justification retained without inventing actor');
 perform pg_temp.audit_check(exists(select 1 from jsonb_array_elements(audit->'items') i cross join lateral jsonb_array_elements(i->'changes') c
  where i->>'action'='form_reviewer_changed' and (i->>'prior_evidence')::boolean and c->>'field'='avaliador_user_id'
   and c->>'before'='2fe38000-0000-4000-8000-000000000001' and c->>'after'='2fe38000-0000-4000-8000-000000000002'),'nested assignment snapshot retains exact prior default reviewer');
 perform pg_temp.audit_check(exists(select 1 from jsonb_array_elements(audit->'items') i cross join lateral jsonb_array_elements(i->'changes') c
  where i->>'action'='form_record_reviewer_changed' and i->>'entity_id'='cfe38000-0000-4000-8000-000000000001'
   and c->>'field'='avaliador_user_id' and c->>'before'='2fe38000-0000-4000-8000-000000000001' and c->>'after'='2fe38000-0000-4000-8000-000000000002'),'record-level reviewer effects retain their own before state');
 for n in 1..27 loop
  result:=public.rm_web_mutate_v1(gen_random_uuid(),'plan_cell',(select jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,
   'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Pagination fixture '||n)) from public.rm_celulas_projeto where id=allocation_id));
 end loop;
 audit:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells',1);
 second_page:=public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells',999);
 perform pg_temp.audit_check(audit->>'total'='30' and jsonb_array_length(audit->'items')=25
  and second_page->>'page'='2' and jsonb_array_length(second_page->'items')=5,'count, first page and clamped final page are exact');
 perform pg_temp.audit_check(not exists(select 1 from jsonb_array_elements(audit->'items') a cross join jsonb_array_elements(second_page->'items') b
  where a->>'id'=b->>'id'),'stable pages never duplicate journal entries');
end $$;
select set_config('request.jwt.claim.sub','1fe38000-0000-4000-8000-000000000002',true);
do $$ begin begin perform public.rm_web_project_audit_v1('5fe38000-0000-4000-8000-000000000001','cells');
 raise exception 'FAIL: mobile gained private audit reads'; exception when insufficient_privilege then null; end; end $$;
reset role;
select pg_temp.audit_check(not has_function_privilege('anon','public.rm_web_project_audit_v1(uuid,text,integer,text[])','execute'),'anonymous denied');
select pg_temp.audit_check(not has_function_privilege('authenticated','rm_private.project_audit_events_v1(uuid,text,text[])','execute'),'private journal helper inaccessible');
select pg_temp.audit_check(not has_table_privilege('authenticated','rm_private.web_mutation_receipts','select'),'private receipts still inaccessible');
rollback;
\echo Project audit projection tests passed

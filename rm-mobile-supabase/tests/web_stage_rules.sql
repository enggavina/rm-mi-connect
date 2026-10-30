\set ON_ERROR_STOP on
begin;
create function pg_temp.sr_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.sr_key(h text,n int) returns uuid language sql immutable as $$ select (h||'d600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.sr_actor(n int,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.sr_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.sr_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.sr.actor',n::text,true); end $$;
create function pg_temp.sr_config(n int default 1) returns jsonb language sql as $$ select jsonb_build_object(
 'celula_destino_id',pg_temp.sr_key('4',n*10+2),'status_cel_proj','em_dia','bloquear_avanco_sem_aprov',true,
 'aprovadores_ids',jsonb_build_array(pg_temp.sr_key('2',5)),'aprovadores_retorno_ids',jsonb_build_array(pg_temp.sr_key('2',6))); $$;
create function pg_temp.sr_payload(action text,pn int default 1,target uuid default null,new_id uuid default null) returns jsonb language sql as $$
 with s as(select public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',pn),pg_temp.sr_key('6',pn*10+1),true) r)
 select jsonb_build_object('action',action,'projeto_id',pg_temp.sr_key('5',pn),'celula_projeto_id',pg_temp.sr_key('6',pn*10+1),
  'expected_project_updated_at',r->'project'->>'updated_at','expected_allocation_updated_at',r->'allocation'->>'updated_at','expected_rules_version',r->>'rules_version')||
 case when action='create' then jsonb_build_object('id',coalesce(new_id,gen_random_uuid()),'config',pg_temp.sr_config(pn)) else
  jsonb_build_object('etapa_id',coalesce(target,pg_temp.sr_key('c',pn)),'expected_etapa_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=coalesce(target,pg_temp.sr_key('c',pn))),'confirm_change',true)||
  case when action='replace' then jsonb_build_object('replacement_id',coalesce(new_id,gen_random_uuid()),'config',pg_temp.sr_config(pn)) else '{}'::jsonb end end from s;
$$;
create function pg_temp.sr_call(rid uuid,p jsonb,cap text default 'em.planning.manage') returns jsonb language plpgsql as $$ declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.sr.actor'),64,'d6'),rid,'manage_stage_rules',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'manage_stage_rules',p); reset role; return r;
 exception when others then reset role; raise; end $$;
create function pg_temp.sr_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$ declare actual text; begin
 begin perform pg_temp.sr_call(gen_random_uuid(),p,cap); exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm; end;
 raise exception 'FAIL: stage rule unexpectedly succeeded'; end $$;
do $$ declare n int; begin for n in 1..4 loop
 insert into auth.users(id) values(pg_temp.sr_key('1',n));
 insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.sr_key('2',n),pg_temp.sr_key('1',n),'Stage rule actor '||n,
  case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
  case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
 insert into auth.sessions(id,user_id) values(pg_temp.sr_key('3',n),pg_temp.sr_key('1',n));
 if n<>4 then
  insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.sr_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.sr_key('9',n),pg_temp.sr_key('2',n),pg_temp.sr_key('1',n),true,pg_temp.sr_key('2',1),clock_timestamp());
  perform public.rm_sso_session_put_v1(lpad(n::text,64,'d6'),pg_temp.sr_key('8',n),pg_temp.sr_key('3',n),'opaque-stage-rule-fixture-'||n,clock_timestamp()+interval '45 minutes');
 end if; end loop; end $$;
insert into public.rm_users(id,nome,matricula) values(pg_temp.sr_key('2',5),'Origin identity','RULE5'),(pg_temp.sr_key('2',6),'Destination identity','RULE6'),(pg_temp.sr_key('2',7),'Tablet only','RULE7');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero,status_pcp) select pg_temp.sr_key('5',n),'STAGE-RULE-27-'||n,case when n=12 then 'cancelado'::public.rm_status_pcp_enum end from generate_series(1,12) n;
insert into public.rm_celulas(id,nome) select pg_temp.sr_key('4',n*10+k),'Rule cell '||n||'-'||k from generate_series(1,12) n cross join generate_series(1,2) k;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,indice,posicao,observacao)
 select pg_temp.sr_key('6',n*10+k),pg_temp.sr_key('5',n),pg_temp.sr_key('4',n*10+k),
  case when k=1 and n=10 then 'finalizado'::public.rm_status_cel_proj_enum when k=1 and n=11 then 'n_a' else 'em_dia' end,true,9,17,'Preserve work'
 from generate_series(1,12) n cross join generate_series(1,2) k where not(n=9 and k=2);
insert into public.rm_tablet_celula_users(id,celula_id,identidade_id,usuario_id)
 select pg_temp.sr_key('7',n*10+k),pg_temp.sr_key('4',n*10+k),pg_temp.sr_key('2',case when k=1 then 5 else 6 end),pg_temp.sr_key('2',7)
 from generate_series(1,12) n cross join generate_series(1,2) k;
insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(pg_temp.sr_key('4',11),pg_temp.sr_key('2',5));
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,ativo,bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids,created_at)
 select pg_temp.sr_key('c',n),pg_temp.sr_key('5',n),case when n=9 then null else pg_temp.sr_key('6',n*10+1) end,
  pg_temp.sr_key('4',n*10+1),pg_temp.sr_key('4',n*10+2),case when n=10 then 'finalizado'::public.rm_status_cel_proj_enum else 'em_dia' end,n<>8,true,
  array[pg_temp.sr_key('2',5)],array[pg_temp.sr_key('2',6)],case when n=3 then clock_timestamp()-interval '1 day' else clock_timestamp() end from generate_series(1,12) n;
update public.rm_aprovacoes_etapas set status='aprovado',aprovado_por_id=pg_temp.sr_key('2',5),data_aprovacao=clock_timestamp() where id=pg_temp.sr_key('c',2);
insert into public.rm_logs_aprovacao(projeto_id,celula_id,status_aprovacao,data_aprovacao) values
 (pg_temp.sr_key('5',3),pg_temp.sr_key('4',31),'aprovado',clock_timestamp()),
 (pg_temp.sr_key('5',4),pg_temp.sr_key('4',41),'aprovado',clock_timestamp()-interval '1 day');
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj)
 values(pg_temp.sr_key('e',5),pg_temp.sr_key('5',5),pg_temp.sr_key('4',52),pg_temp.sr_key('4',51),'retornado');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('stage-rule-mobile-fixture','sha256'),pg_temp.sr_key('1',1),pg_temp.sr_key('2',1),pg_temp.sr_key('2',1),clock_timestamp()+interval '1 day');
select pg_temp.sr_actor(1);
set local role authenticated;
do $$ declare s jsonb:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true); begin
 perform pg_temp.sr_check((s->>'total')::int=1 and (s->>'selected_total')::int=1 and (s->>'complete')::boolean,'selected and whole project totals are explicit');
 perform pg_temp.sr_check((s->>'eligible_total')::int=2 and jsonb_array_length(s->'eligible_users')=2 and jsonb_array_length(s->'statuses')=9,'choices dedup active identities and exclude return status');
 perform pg_temp.sr_check(not exists(select 1 from jsonb_array_elements(s->'eligible_users') u where u->>'id' in(pg_temp.sr_key('2',1)::text,pg_temp.sr_key('2',7)::text)),'tablet account and administrator bypass create no eligibility');
 perform pg_temp.sr_check(s::text !~ '"(email|auth_user_id|token|bubble_id|sync_source|payload|actor_id|client_submission_id)"','minimum DTO excludes envelopes/credentials');
 perform pg_temp.sr_check((s->'rules'->0->>'can_edit')::boolean,'unused rule can be replaced');
 perform pg_temp.sr_check((public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',10),pg_temp.sr_key('6',101),true)->'rules'->0->>'can_edit')::boolean,'origin finalized may await a configured finalization release');
 perform pg_temp.sr_check(public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',2),pg_temp.sr_key('6',11),true) is null,'cross-project allocation is null');
 perform pg_temp.sr_check(public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),false)->'eligible_users'='[]','viewer request redacts choices');
end $$;
reset role;
do $$ declare p jsonb:=pg_temp.sr_payload('create'); r jsonb; rid uuid:=gen_random_uuid(); old_rule jsonb; old_allocations jsonb; new_id uuid:=pg_temp.sr_key('f',1); next_id uuid:=pg_temp.sr_key('f',2); n int; before_outbox bigint; before_journal bigint; begin
 perform pg_temp.sr_reject(p,'22023','em.approvals.decide');
 perform pg_temp.sr_reject(p||'{"actor_id":"2d600000-0000-4000-8000-000000000001"}','22023');
 perform pg_temp.sr_reject(p||'{"confirm_change":true}','22023');
 perform pg_temp.sr_reject(p||'{"expected_rules_version":"bad"}','22023');
 perform pg_temp.sr_reject(p||'{"expected_project_updated_at":"infinity"}','22023');
 perform pg_temp.sr_reject(p||jsonb_build_object('celula_projeto_id',pg_temp.sr_key('6',21)),'P0002');
 perform pg_temp.sr_reject(jsonb_set(p,'{config,aprovadores_ids}','[]'),'22023');
 perform pg_temp.sr_reject(jsonb_set(p,'{config,status_cel_proj}','"retornado"'),'22023');
 perform pg_temp.sr_reject(jsonb_set(p,'{config,aprovadores_ids}',jsonb_build_array(pg_temp.sr_key('2',7))),'22023');
 perform pg_temp.sr_reject(jsonb_set(p,'{config,celula_destino_id}',to_jsonb(pg_temp.sr_key('4',22))),'22023');
 perform pg_temp.sr_reject(p,'22023'); -- existing equal effective configuration
 for n in 2..5 loop if n<>4 then perform pg_temp.sr_reject(pg_temp.sr_payload('replace',n),'22023'); end if; end loop;
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire',4)); perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore',4));
 perform pg_temp.sr_reject(pg_temp.sr_payload('retire',11),'22023'); perform pg_temp.sr_reject(pg_temp.sr_payload('retire',12),'22023');
 perform pg_temp.sr_reject(pg_temp.sr_payload('retire')-'confirm_change','22023'); perform pg_temp.sr_reject(pg_temp.sr_payload('retire')||'{"confirm_change":false}','22023');
 select jsonb_agg(to_jsonb(a) order by id) into old_allocations from public.rm_celulas_projeto a where projeto_id=pg_temp.sr_key('5',1);
 select to_jsonb(a) into old_rule from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('c',1);
 select count(*) into before_outbox from public.rm_sync_outbox;
 p:=jsonb_set(pg_temp.sr_payload('replace',1,null,new_id),'{config,bloquear_avanco_sem_aprov}','false');
 r:=pg_temp.sr_call(rid,p);
 perform pg_temp.sr_check(r->>'id'=new_id::text and r->'record'->'changed_ids'=jsonb_build_array(pg_temp.sr_key('c',1),new_id),'replacement is an exact old/new transition');
 perform pg_temp.sr_check((select not a.ativo and to_jsonb(a)-array['ativo','updated_at','sync_source']=old_rule-array['ativo','updated_at','sync_source'] from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('c',1)),'old immutable configuration, markers and ID are preserved');
 perform pg_temp.sr_check((select jsonb_agg(to_jsonb(a) order by id)=old_allocations from public.rm_celulas_projeto a where projeto_id=pg_temp.sr_key('5',1)) and (select count(*)=before_outbox from public.rm_sync_outbox),'editor changes no allocation state/visibility/queue or outbound effects');
 perform pg_temp.sr_check((pg_temp.sr_call(rid,p)->>'idempotent_replay')::boolean,'exact replay precedes stale config hash');
 perform pg_temp.sr_reject(pg_temp.sr_payload('restore'),'22023');
 p:=jsonb_set(pg_temp.sr_payload('replace',1,new_id,next_id),'{config,status_cel_proj}','"pendente"');
 perform pg_temp.sr_call(gen_random_uuid(),p); perform pg_temp.sr_reject(pg_temp.sr_payload('restore'),'22023');
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire',1,next_id));
 r:=pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore'));
 perform pg_temp.sr_check(r->'record'->'changed_ids'=jsonb_build_array(pg_temp.sr_key('c',1)) and (select ativo from public.rm_aprovacoes_etapas where id=pg_temp.sr_key('c',1)),'restoration traverses full family after successor withdrawal');
 select to_jsonb(a) into old_rule from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('c',1); select count(*) into before_journal from rm_private.stage_rule_events;
 r:=pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore'));
 perform pg_temp.sr_check(r->'record'->'changed_ids'='[]' and (select to_jsonb(a)=old_rule from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('c',1)) and (select count(*)=before_journal from rm_private.stage_rule_events),'no-op preserves rule/journal and adds only receipt');
 begin update public.rm_aprovacoes_etapas set bloquear_avanco_sem_aprov=false where id=pg_temp.sr_key('c',1); raise exception 'FAIL: raw config update'; exception when invalid_parameter_value then null; end;
 begin delete from public.rm_aprovacoes_etapas where id=pg_temp.sr_key('c',4); raise exception 'FAIL: legacy pending hard-delete'; exception when invalid_parameter_value then null; end;
end $$;
do $$ declare p jsonb; rid uuid:=gen_random_uuid(); r jsonb; text_error text; reverse_id uuid; s jsonb; begin
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire',7));
 p:=jsonb_build_object('p_aprovacao_etapa_id',pg_temp.sr_key('c',7),'p_acao','liberar');
 begin set local role authenticated; perform public.rm_mobile_mutate_v1(rid,'rm_transition_stage_approval_v1',p,'stage-rule-mobile-fixture'); raise exception 'FAIL: delayed retired decision'; exception when sqlstate 'PT409' then get stacked diagnostics text_error=message_text; reset role; end;
 perform pg_temp.sr_check(text_error like '%mesma configuração%' and not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=rid),'retired pending envelope fails clearly without a receipt');
 set local role authenticated;
 perform pg_temp.sr_check(public.rm_web_stage_approval_snapshot_v1(pg_temp.sr_key('c',7))->'available_actions'='[]','retired detail is consultation');
 perform pg_temp.sr_check((public.rm_web_stage_approvals_v1(pg_temp.sr_key('5',7),null,'all')->>'total')::int=0,'normal queue ignores retired tombstone');
 perform pg_temp.sr_check(exists(select 1 from public.rm_aprovacoes_etapas where id=pg_temp.sr_key('c',7) and not ativo),'pull/RLS still returns retired row for SQLite'); reset role;
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore',7));
 set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_transition_stage_approval_v1',p,'stage-rule-mobile-fixture'); reset role;
 perform pg_temp.sr_check(r->>'aprovacao_etapa_id'=pg_temp.sr_key('c',7)::text and (select count(*)=2 from rm_private.stage_rule_events where projeto_id=pg_temp.sr_key('5',7) and action='use'),'same UUID after restore records every affected stage without inventing decisions');
 reverse_id:=(r->'affected_approval_ids'->>0)::uuid;
 set local role authenticated; perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.sr_key('6',72),'p_status','retornado'),'stage-rule-mobile-fixture');
 perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','retornar','p_observacao','Return real equipment'),'stage-rule-mobile-fixture');
 r:=public.rm_mobile_mutate_v1(rid,'rm_transition_stage_approval_v1',p,'stage-rule-mobile-fixture'); reset role;
 perform pg_temp.sr_check((r->>'idempotent_replay')::boolean and (select status='nulo' and aprovado_por_id is null and data_aprovacao is null from public.rm_aprovacoes_etapas where id=pg_temp.sr_key('c',7)),'old completed receipt replays while return resets current markers');
 s:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',7),pg_temp.sr_key('6',71),true);
 perform pg_temp.sr_check((s->'rules'->0->>'used')::boolean and not(s->'rules'->0->>'can_edit')::boolean,'irreversible usage journal survives Nulo reset');
 perform pg_temp.sr_reject(pg_temp.sr_payload('retire',7),'22023');
end $$;
do $$ declare original_return jsonb; p jsonb; s jsonb; begin
 select to_jsonb(a) into original_return from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('e',5);
 p:=jsonb_set(pg_temp.sr_payload('create',5,null,pg_temp.sr_key('f',5)),'{config,status_cel_proj}','"pendente"');
 perform pg_temp.sr_call(gen_random_uuid(),p);
 s:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',5),pg_temp.sr_key('6',51),true);
 perform pg_temp.sr_check((select (x->>'managed_birth')::boolean and (x->>'can_edit')::boolean and not(x->>'used')::boolean
  from jsonb_array_elements(s->'rules') x where x->>'id'=pg_temp.sr_key('f',5)::text),'new unused gate is manageable despite an old return on the same path');
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire',5,pg_temp.sr_key('f',5)));
 perform pg_temp.sr_check((select to_jsonb(a)=original_return from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('e',5))
  and not exists(select 1 from rm_private.stage_rule_events where projeto_id=pg_temp.sr_key('5',5) and action='use'),'withdrawing new unused rule neither changes old return nor invents use');
end $$;
-- Restoration is a fresh activation, never an excuse to reopen a completed or
-- absent destination. Restore the original context before retrying its same ID.
do $$ declare s jsonb; begin
 update public.rm_celulas_projeto set status='finalizado' where id=pg_temp.sr_key('6',82);
 s:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',8),pg_temp.sr_key('6',81),true);
 perform pg_temp.sr_check(not(s->'rules'->0->>'can_restore')::boolean,'terminal destination prevents restoring old rule');
 perform pg_temp.sr_reject(pg_temp.sr_payload('restore',8),'22023');
 update public.rm_celulas_projeto set status='pendente' where id=pg_temp.sr_key('6',82);
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore',8));
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire',9));
 perform pg_temp.sr_check(not exists(select 1 from public.rm_celulas_projeto where id=pg_temp.sr_key('6',92)),
  'legacy destination was never allocated; no hard-delete is needed to construct absence');
 perform pg_temp.sr_reject(pg_temp.sr_payload('restore',9),'22023');
 insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) values(pg_temp.sr_key('6',92),pg_temp.sr_key('5',9),pg_temp.sr_key('4',92),'pendente');
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore',9));
 perform pg_temp.sr_check((select ativo and celula_projeto_id is null from public.rm_aprovacoes_etapas where id=pg_temp.sr_key('c',9)),'compatible destination restores same legacy ID without changing null allocation link');
end $$;
do $$ declare r jsonb; reverse_id uuid; old_inverse jsonb; old_approved jsonb; begin
 insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,ativo,bloquear_avanco_sem_aprov)
  values(pg_temp.sr_key('a',6),pg_temp.sr_key('5',6),pg_temp.sr_key('4',61),pg_temp.sr_key('4',62),'pendente',false,true),
   (pg_temp.sr_key('e',6),pg_temp.sr_key('5',6),pg_temp.sr_key('4',62),pg_temp.sr_key('4',61),'retornado',false,false);
 insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,ativo,status,aprovado_por_id,data_aprovacao)
  values(pg_temp.sr_key('a',66),pg_temp.sr_key('5',6),pg_temp.sr_key('4',61),pg_temp.sr_key('4',62),'atrasado',false,'aprovado',pg_temp.sr_key('2',5),'2020-01-01T00:00:00Z');
 select to_jsonb(a) into old_inverse from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('e',6);
 select to_jsonb(a) into old_approved from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('a',66);
 set local role authenticated;
 r:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',jsonb_build_object('p_aprovacao_etapa_id',pg_temp.sr_key('c',6),'p_acao','liberar'),'stage-rule-mobile-fixture'); reset role;
 reverse_id:=(r->'affected_approval_ids'->>0)::uuid;
 perform pg_temp.sr_check(reverse_id<>pg_temp.sr_key('e',6) and (select to_jsonb(a)=old_inverse from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('e',6)),'reverse lookup skips retired return without silently restoring or editing it');
 perform pg_temp.sr_check((select status='para_execu__o' and visibilidade from public.rm_celulas_projeto where id=pg_temp.sr_key('6',62))
  and (select not visibilidade from public.rm_celulas_projeto where id=pg_temp.sr_key('6',61)),'retired blocker neither blocks destination nor keeps origin pending');
 set local role authenticated;
 perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.sr_key('6',62),'p_status','retornado'),'stage-rule-mobile-fixture');
 perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_transition_stage_approval_v1',jsonb_build_object('p_aprovacao_etapa_id',reverse_id,'p_acao','retornar','p_observacao','Only active rules participate'),'stage-rule-mobile-fixture'); reset role;
 perform pg_temp.sr_check((select to_jsonb(a)=old_approved from public.rm_aprovacoes_etapas a where id=pg_temp.sr_key('a',66))
  and (select not visibilidade from public.rm_celulas_projeto where id=pg_temp.sr_key('6',62)),'return never resets retired approval markers and ignores retired pending inverse for visibility');
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire',8));
 set local role authenticated; perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.sr_key('6',81),'p_status','finalizado'),'stage-rule-mobile-fixture'); reset role;
 perform pg_temp.sr_check((select not visibilidade from public.rm_celulas_projeto where id=pg_temp.sr_key('6',81)),'finalization considers only active rules');
end $$;
do $$ declare p jsonb:=pg_temp.sr_payload('restore'); rid uuid:=gen_random_uuid(); begin
 perform pg_temp.sr_call(rid,p);
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'manage_stage_rules',p); raise exception 'FAIL: permitless replay'; exception when insufficient_privilege then reset role; end;
 begin perform pg_temp.sr_call(rid,p||'{"confirm_change":false}'); raise exception 'FAIL: changed receipt payload'; exception when unique_violation then null; end;
 perform pg_temp.sr_actor(2); begin perform pg_temp.sr_call(rid,p); raise exception 'FAIL: another actor replay'; exception when unique_violation then null; end;
 perform pg_temp.sr_actor(1); insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.sr_call(rid,p); raise exception 'FAIL: MFA replay'; exception when insufficient_privilege then null; end;
 perform pg_temp.sr_actor(1,'aal2'); perform pg_temp.sr_check((pg_temp.sr_call(rid,p)->>'idempotent_replay')::boolean,'fresh MFA checked on exact replay');
 delete from auth.mfa_factors where user_id=auth.uid(); perform pg_temp.sr_actor(1);
 p:=pg_temp.sr_payload('restore'); update public.rm_users set nome='Changed current eligibility' where id=pg_temp.sr_key('2',5); perform pg_temp.sr_reject(p,'PT409');
 p:=pg_temp.sr_payload('restore'); update public.rm_tablet_celula_users set slug='Changed membership revision' where id=pg_temp.sr_key('7',11); perform pg_temp.sr_reject(p,'PT409');
 p:=pg_temp.sr_payload('restore'); update public.rm_celulas set nome='Changed origin context' where id=pg_temp.sr_key('4',11); perform pg_temp.sr_reject(p,'PT409');
 perform pg_temp.sr_check(not has_table_privilege('authenticated','rm_private.stage_rule_events','SELECT') and not has_table_privilege('service_role','rm_private.stage_rule_events','INSERT')
  and not has_function_privilege('authenticated','rm_private.stage_rule_config_v1(public.rm_aprovacoes_etapas)','EXECUTE'),'no private journal/envelope selection or raw audit write grants');
end $$;
savepoint cap_rules;
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id) select pg_temp.sr_key('a',n),pg_temp.sr_key('5',1),pg_temp.sr_key('4',11) from generate_series(100,1096) n;
do $$ declare s jsonb:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true); begin
 perform pg_temp.sr_check((s->>'total')::int=1000 and (s->>'complete')::boolean and (select not(x->>'can_edit')::boolean and (x->>'can_retire')::boolean from jsonb_array_elements(s->'rules') x where x->>'id'=pg_temp.sr_key('c',1)::text),'limit1000 permits withdrawal/restoration but not another version');
 perform pg_temp.sr_reject(pg_temp.sr_payload('create'),'22023'); perform pg_temp.sr_reject(pg_temp.sr_payload('replace'),'22023');
 perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('retire')); perform pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore'));
end $$;
insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id) values(pg_temp.sr_key('5',1),pg_temp.sr_key('4',11));
do $$ declare s jsonb:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true); begin
 perform pg_temp.sr_check(not(s->>'complete')::boolean and s->'rules'='[]','project-rule overflow never returns a partial editable collection'); perform pg_temp.sr_reject(pg_temp.sr_payload('retire'),'22023'); end $$;
rollback to cap_rules;
savepoint cap_allocations;
insert into public.rm_celulas(id,nome) select pg_temp.sr_key('4',n),'Overflow rule cell '||n from generate_series(1000,1998) n;
insert into public.rm_celulas_projeto(projeto_id,celula_id) select pg_temp.sr_key('5',1),pg_temp.sr_key('4',n) from generate_series(1000,1998) n;
do $$ declare s jsonb:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true); begin
 perform pg_temp.sr_check(not(s->>'allocations_complete')::boolean and s->'rules'='[]','allocation overflow never hides dependency scope'); perform pg_temp.sr_reject(pg_temp.sr_payload('retire'),'22023'); end $$;
rollback to cap_allocations;
savepoint cap_identities;
insert into public.rm_users(id,nome) select pg_temp.sr_key('2',n),'Overflow rule identity '||n from generate_series(100,1098) n;
insert into public.rm_tablet_celula_users(celula_id,identidade_id) select pg_temp.sr_key('4',11),pg_temp.sr_key('2',n) from generate_series(100,1098) n;
do $$ declare s jsonb:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true); begin
 perform pg_temp.sr_check(not(s->>'eligible_complete')::boolean and s->'eligible_users'='[]' and (select bool_and(not(x->>'can_retire')::boolean) from jsonb_array_elements(s->'rules') x),'identity overflow keeps consultation but fails closed'); perform pg_temp.sr_reject(pg_temp.sr_payload('retire'),'22023'); end $$;
rollback to cap_identities;
savepoint cap_memberships;
insert into public.rm_tablet_celula_users(celula_id,identidade_id) select pg_temp.sr_key('4',11),pg_temp.sr_key('2',5) from generate_series(1,4998);
do $$ declare s jsonb:=public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true); begin
 perform pg_temp.sr_check(not(s->>'memberships_complete')::boolean and s->'eligible_users'='[]' and s->'destinations'='[]','membership overflow is explicit even with few unique candidates'); perform pg_temp.sr_reject(pg_temp.sr_payload('retire'),'22023'); end $$;
rollback to cap_memberships;
select pg_temp.sr_actor(2);
select pg_temp.sr_check((pg_temp.sr_call(gen_random_uuid(),pg_temp.sr_payload('restore'))->>'operation')='manage_stage_rules','planning writer need not have approval-decision authority');
select pg_temp.sr_actor(3);
set local role authenticated;
select pg_temp.sr_check(public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true)->'eligible_users'='[]','auditor receives no choices');
reset role;
select pg_temp.sr_reject(pg_temp.sr_payload('restore'),'42501');
select pg_temp.sr_actor(4);
select pg_temp.sr_reject(pg_temp.sr_payload('restore'),'42501');
set local role authenticated;
select pg_temp.sr_check(public.rm_web_stage_rules_snapshot_v1(pg_temp.sr_key('5',1),pg_temp.sr_key('6',11),true) is null,'inactive user has no snapshot');
reset role;
select pg_temp.sr_actor(1);
do $$ declare p jsonb:=pg_temp.sr_payload('restore'); rid uuid:=gen_random_uuid(); begin
 perform public.rm_sso_action_permit_v1(lpad('1',64,'d6'),rid,'manage_stage_rules',p,'em.planning.manage');
 update rm_private.sso_action_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=rid;
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'manage_stage_rules',p); raise exception 'FAIL: expired permit'; exception when insufficient_privilege then reset role; end;
 update rm_private.sso_sessions set expires_at=clock_timestamp()-interval '1 second' where hash=lpad('1',64,'d6'); perform pg_temp.sr_reject(p,'42501'); end $$;
rollback;
select 'PASS: immutable stage configuration, guarded lineage/restore, conservative use/legacy proof, no fake pairs, tombstones and delayed offline receipt recovery' as result;

begin;
create extension if not exists dblink with schema public;
create schema rm_test_stage_rules;
create function rm_test_stage_rules.check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function rm_test_stage_rules.key(h text,n int) returns uuid language sql immutable as $$ select (h||'d700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
insert into auth.users(id) values(rm_test_stage_rules.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_stage_rules.key('2',1),rm_test_stage_rules.key('1',1),'Stage-rule concurrent actor','administrador');
insert into public.rm_users(id,nome) select rm_test_stage_rules.key('2',n*10+k),'Concurrent rule identity '||n||'-'||k from generate_series(1,20) n cross join generate_series(1,2) k;
insert into auth.sessions(id,user_id) values(rm_test_stage_rules.key('3',1),rm_test_stage_rules.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_stage_rules.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_stage_rules.key('9',1),rm_test_stage_rules.key('2',1),rm_test_stage_rules.key('1',1),true,rm_test_stage_rules.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('d7',32),rm_test_stage_rules.key('8',1),rm_test_stage_rules.key('3',1),'opaque-local-stage-rule-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('stage-rule-mobile-races','sha256'),rm_test_stage_rules.key('1',1),rm_test_stage_rules.key('2',1),rm_test_stage_rules.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero) select rm_test_stage_rules.key('5',n),'STAGE-RULE-RACE-27-'||n from generate_series(1,20) n;
insert into public.rm_celulas(id,nome) select rm_test_stage_rules.key('4',n*10+k),'Rule race cell '||n||'-'||k from generate_series(1,20) n cross join generate_series(1,2) k;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) select rm_test_stage_rules.key('6',n*10+k),rm_test_stage_rules.key('5',n),rm_test_stage_rules.key('4',n*10+k),'em_dia' from generate_series(1,20) n cross join generate_series(1,2) k;
insert into public.rm_tablet_celula_users(id,celula_id,identidade_id) select rm_test_stage_rules.key('7',n*10+k),rm_test_stage_rules.key('4',n*10+k),rm_test_stage_rules.key('2',n*10+k) from generate_series(1,20) n cross join generate_series(1,2) k;
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids,ativo)
 select rm_test_stage_rules.key('c',n),rm_test_stage_rules.key('5',n),rm_test_stage_rules.key('6',n*10+1),rm_test_stage_rules.key('4',n*10+1),rm_test_stage_rules.key('4',n*10+2),'em_dia',true,
  array[rm_test_stage_rules.key('2',n*10+1)],array[rm_test_stage_rules.key('2',n*10+2)],n not in(15,16,18) from generate_series(1,20) n;
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids)
 values(rm_test_stage_rules.key('e',18),rm_test_stage_rules.key('5',18),rm_test_stage_rules.key('6',181),rm_test_stage_rules.key('4',181),rm_test_stage_rules.key('4',182),'em_dia',false,array[rm_test_stage_rules.key('2',181)],array[rm_test_stage_rules.key('2',182)]);
insert into rm_private.stage_rule_events(projeto_id,etapa_id,related_etapa_id,actor_id,action) values
 (rm_test_stage_rules.key('5',18),rm_test_stage_rules.key('c',18),null,rm_test_stage_rules.key('2',1),'create'),
 (rm_test_stage_rules.key('5',18),rm_test_stage_rules.key('e',18),rm_test_stage_rules.key('c',18),rm_test_stage_rules.key('2',1),'replace');
create function rm_test_stage_rules.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_stage_rules.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_stage_rules.key('3',1),'aal','aal1')::text,true);
 if mode in('editor','web') then
  perform public.rm_sso_action_permit_v1(repeat('d7',32),rid,case when mode='editor' then 'manage_stage_rules' else 'transition_stage_approval' end,p,case when mode='editor' then 'em.planning.manage' else 'em.approvals.decide' end);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,case when mode='editor' then 'manage_stage_rules' else 'transition_stage_approval' end,p); reset role;
 elsif mode in('mobile','status') then
  set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,case when mode='mobile' then 'rm_transition_stage_approval_v1' else 'rm_update_cell_status_v1' end,p,'stage-rule-mobile-races'); reset role;
 elsif mode='revoke_user' then update public.rm_users set status='inativo' where id=(p->>'id')::uuid;
 elsif mode='revoke_tcu' then delete from public.rm_tablet_celula_users where id=(p->>'id')::uuid;
 elsif mode='insert' then insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id) values((p->>'projeto_id')::uuid,(p->>'celula_id')::uuid);
 elsif mode='config' then update public.rm_aprovacoes_etapas set bloquear_avanco_sem_aprov=false where id=(p->>'id')::uuid;
 elsif mode='dest' then update public.rm_celulas_projeto set status='finalizado' where id=(p->>'id')::uuid;
 elsif mode='rename' then update public.rm_celulas set nome='Changed rule roster context' where id=(p->>'id')::uuid;
 elsif mode='close' then perform pg_advisory_xact_lock(hashtextextended(p->>'id',11)); update public.rm_projetos set status_pcp='cancelado' where id=(p->>'id')::uuid;
 else raise exception 'Unknown stage-rule race'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state,'message',sqlerrm); end $$;
commit;
do $$ declare scenario int; s jsonb; p jsonb; other_p jsonb; first_p jsonb; second_p jsonb; config jsonb; action text; target uuid;
 first_mode text; second_mode text; first_id uuid; second_id uuid; a jsonb; b jsonb; pid_a int; pid_b int; waited int; expected_state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_stage_rules.key('1',1)::text,true);
 perform dblink_connect('stage_rule_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('stage_rule_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('stage_rule_a','select pg_backend_pid()') as t(pid int); select pid into pid_b from dblink('stage_rule_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..20 loop
  s:=public.rm_web_stage_rules_snapshot_v1(rm_test_stage_rules.key('5',scenario),rm_test_stage_rules.key('6',scenario*10+1),true);
  action:=case when scenario in(1,2,7) then 'retire' when scenario in(3,4,8,17,18) then 'replace' when scenario in(15,16) then 'restore' else 'create' end;
  target:=case when scenario=18 then rm_test_stage_rules.key('e',18) else rm_test_stage_rules.key('c',scenario) end;
  p:=jsonb_build_object('action',action,'projeto_id',rm_test_stage_rules.key('5',scenario),'celula_projeto_id',rm_test_stage_rules.key('6',scenario*10+1),'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_rules_version',s->>'rules_version');
  config:=jsonb_build_object('celula_destino_id',rm_test_stage_rules.key('4',scenario*10+2),'status_cel_proj','pendente','bloquear_avanco_sem_aprov',true,'aprovadores_ids',jsonb_build_array(rm_test_stage_rules.key('2',scenario*10+1)),'aprovadores_retorno_ids',jsonb_build_array(rm_test_stage_rules.key('2',scenario*10+2)));
  if action='create' then p:=p||jsonb_build_object('id',rm_test_stage_rules.key('f',scenario),'config',config);
  else p:=p||jsonb_build_object('etapa_id',target,'expected_etapa_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=target),'confirm_change',true);
   if action='replace' then p:=p||jsonb_build_object('replacement_id',rm_test_stage_rules.key('f',scenario),'config',config); end if;
  end if;
  first_mode:='editor'; second_mode:='editor'; other_p:=p;
  if scenario in(1,2,3,4,15) then
   other_p:=jsonb_build_object('p_aprovacao_etapa_id',target,'p_acao','liberar'); first_mode:=case when scenario in(2,4) then 'mobile' else 'editor' end; second_mode:=case when first_mode='mobile' then 'editor' else 'mobile' end;
  elsif scenario in(7,8) then
   other_p:=jsonb_build_object('aprovacao_etapa_id',target,'expected_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=target),'expected_cell_updated_at',s->'allocation'->>'updated_at','acao','liberar','observacao',null);
   first_mode:=case when scenario=7 then 'editor' else 'web' end; second_mode:=case when scenario=7 then 'web' else 'editor' end;
  elsif scenario in(9,10) then other_p:=jsonb_build_object('p_celula_projeto_id',rm_test_stage_rules.key('6',scenario*10+1),'p_status','atrasado'); first_mode:=case when scenario=9 then 'editor' else 'status' end; second_mode:=case when scenario=9 then 'status' else 'editor' end;
  elsif scenario=11 then other_p:=jsonb_build_object('id',rm_test_stage_rules.key('2',scenario*10+1)); first_mode:='revoke_user';
  elsif scenario=12 then other_p:=jsonb_build_object('id',rm_test_stage_rules.key('7',scenario*10+1)); second_mode:='revoke_tcu';
  elsif scenario=13 then other_p:=jsonb_build_object('projeto_id',rm_test_stage_rules.key('5',scenario),'celula_id',rm_test_stage_rules.key('4',scenario*10+1)); first_mode:='insert';
  elsif scenario=14 then other_p:=jsonb_build_object('id',target); second_mode:='config';
  elsif scenario=16 then other_p:=jsonb_build_object('id',rm_test_stage_rules.key('6',scenario*10+2)); first_mode:='dest';
  elsif scenario=17 then other_p:=jsonb_build_object('id',rm_test_stage_rules.key('4',scenario*10+1)); first_mode:='rename';
  elsif scenario=18 then other_p:=p||jsonb_build_object('action','restore','etapa_id',rm_test_stage_rules.key('c',18),'expected_etapa_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=rm_test_stage_rules.key('c',18))); other_p:=other_p-array['config','replacement_id'];
  elsif scenario in(19,20) then other_p:=jsonb_build_object('id',rm_test_stage_rules.key('5',scenario)); first_mode:=case when scenario=19 then 'close' else 'editor' end; second_mode:=case when scenario=19 then 'editor' else 'close' end;
  end if;
  first_p:=case when first_mode='editor' then p else other_p end; second_p:=case when second_mode='editor' then case when scenario=18 then other_p else p end else other_p end;
  if scenario=5 then second_p:=jsonb_set(second_p,'{id}',to_jsonb(rm_test_stage_rules.key('f',100+scenario))); end if;
  first_id:=gen_random_uuid(); second_id:=case when scenario=6 then first_id else gen_random_uuid() end;
  perform dblink_send_query('stage_rule_a',format('select rm_test_stage_rules.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,first_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first stage-rule race % did not hold',scenario; end if; perform pg_sleep(0.01); end loop;
  perform dblink_send_query('stage_rule_b',format('select rm_test_stage_rules.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>150 then raise exception 'FAIL: second stage-rule race % did not contend',scenario; end if; perform pg_sleep(0.005); end loop;
  select r into a from dblink_get_result('stage_rule_a') as t(r jsonb); perform r from dblink_get_result('stage_rule_a') as t(r jsonb);
  select r into b from dblink_get_result('stage_rule_b') as t(r jsonb); perform r from dblink_get_result('stage_rule_b') as t(r jsonb);
  expected_state:=case when scenario in(6,9,12,15,20) then '00000' when scenario=14 then '22023' else 'PT409' end;
  perform rm_test_stage_rules.check(a->>'sqlstate'='00000',format('first stage-rule race %s: %s',scenario,a));
  perform rm_test_stage_rules.check(b->>'sqlstate'=expected_state,format('second stage-rule race %s: %s',scenario,b));
  if scenario=6 then perform rm_test_stage_rules.check((b->'result'->>'idempotent_replay')::boolean,'same protocol creates one rule and replays receipt'); end if;
  if scenario in(1,3) then perform rm_test_stage_rules.check((select not ativo and status='nulo' from public.rm_aprovacoes_etapas where id=target) and b->>'message' like '%tentativa offline foi preservada%','retirement or replacement first cannot reinterpret a queued old decision'); end if;
  if scenario in(2,4,8,15) then perform rm_test_stage_rules.check((select ativo and status='aprovado' from public.rm_aprovacoes_etapas where id=target),'winning decision preserves used original ID'); end if;
  if scenario=14 then perform rm_test_stage_rules.check((select bloquear_avanco_sem_aprov from public.rm_aprovacoes_etapas where id=target),'technical config mutation is forbidden rather than silently stale'); end if;
 end loop;
 perform dblink_disconnect('stage_rule_a'); perform dblink_disconnect('stage_rule_b');
exception when others then if 'stage_rule_a'=any(dblink_get_connections()) then perform dblink_disconnect('stage_rule_a'); end if;
 if 'stage_rule_b'=any(dblink_get_connections()) then perform dblink_disconnect('stage_rule_b'); end if; raise; end $$;
select 'PASS:20 real stage-rule races cover editor/decisions/mobile in both orders, retry, status, revocation, FK insertion, immutable config, restore, family and closure' as result;

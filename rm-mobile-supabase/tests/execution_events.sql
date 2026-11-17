\set ON_ERROR_STOP on
begin;
create function pg_temp.ex_id(h text,n int) returns uuid language sql immutable as $$select(h||'ae51000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.ex_check(value boolean,message text) returns void language plpgsql as $$begin if value is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
create function pg_temp.ex_actor(n int,aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.ex_id('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.ex_id('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.execution.actor',n::text,true);
end$$;
create function pg_temp.ex_params(s int,a int,k text,prev uuid default null,op int default 5) returns jsonb language sql as $$
 select jsonb_build_object('p_session_id',pg_temp.ex_id('7',s),'p_allocation_id',pg_temp.ex_id('6',a),'p_previous_event_id',prev,
  'p_kind',k,'p_occurred_at','2026-11-16T10:11:12.123456+00:00','p_pause_reason',case when k='pause' then 'material' else null end,
  'p_note',null,'p_effort_minutes',case when k='finish' then 120 else null end,'p_operador_id',pg_temp.ex_id('2',op));
$$;
create function pg_temp.ex_mobile(rid uuid,p jsonb,token text default 'execution-token-5') returns jsonb language plpgsql as $$declare result jsonb;begin
 set local role authenticated;result:=public.rm_mobile_mutate_v1(rid,'rm_record_execution_event_v1',p,token);reset role;return result;
 exception when others then reset role;raise;
end$$;
create function pg_temp.ex_mobile_reject(p jsonb,wanted text,token text default 'execution-token-5') returns void language plpgsql as $$declare actual text;begin
 begin perform pg_temp.ex_mobile(gen_random_uuid(),p,token);exception when others then get stacked diagnostics actual=returned_sqlstate;
 if actual=wanted then return;end if;raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: invalid mobile event succeeded, wanted %',wanted;
end$$;
create function pg_temp.ex_review(s int,action text default 'confirm_finished') returns jsonb language sql as $$
 select jsonb_build_object('session_id',pg_temp.ex_id('7',s),'expected_version',rm_private.execution_session_version_v1(pg_temp.ex_id('7',s)),
 'action',action,'reported_finished_at',case when action='confirm_finished' then clock_timestamp()-interval '1 minute' else null end,
 'effort_minutes',case when action='confirm_finished' then 90 else null end,'note','Explicit management reconciliation','reason','Validated against workshop evidence');
$$;
create function pg_temp.ex_web(rid uuid,p jsonb,operation text default 'review_execution_session',cap text default 'em.planning.manage') returns jsonb language plpgsql as $$declare result jsonb;begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.execution.actor'),64,'a51'),rid,operation,p,cap);
 set local role authenticated;result:=public.rm_web_mutate_v1(rid,operation,p);reset role;return result;
 exception when others then reset role;raise;
end$$;
create function pg_temp.ex_web_reject(p jsonb,wanted text) returns void language plpgsql as $$declare actual text;begin
 begin perform pg_temp.ex_web(gen_random_uuid(),p);exception when others then get stacked diagnostics actual=returned_sqlstate;
 if actual=wanted then return;end if;raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: invalid management review succeeded, wanted %',wanted;
end$$;
do $$declare n int;begin
 for n in 1..6 loop
  insert into auth.users(id) values(pg_temp.ex_id('1',n));
  insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.ex_id('2',n),case when n<=4 then pg_temp.ex_id('1',n) else null end,
   'Execution fixture '||n,case when n=4 then 'auditor'::public.rm_perfil_usuario_enum when n=3 then 'padr_o' when n>=5 then 'mobile' else 'administrador' end,'ativo');
  insert into auth.sessions(id,user_id) values(pg_temp.ex_id('3',n),pg_temp.ex_id('1',n));
  if n between 2 and 4 then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
    values(pg_temp.ex_id('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.ex_id('9',n),pg_temp.ex_id('2',n),pg_temp.ex_id('1',n),true,pg_temp.ex_id('2',2),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'a51'),pg_temp.ex_id('8',n),pg_temp.ex_id('3',n),'opaque-execution-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end$$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select pg_temp.ex_id('4',n),'Execution cell '||n from generate_series(1,3)n;
insert into public.rm_projetos(id,numero) select pg_temp.ex_id('5',n),'EXECUTION51-'||n from generate_series(1,3)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite,horas_realizadas)
 select pg_temp.ex_id('6',n),pg_temp.ex_id('5',n),pg_temp.ex_id('4',n),'em_dia',true,'2026-11-16T08:12:34.123456Z','2026-11-30T15:00:00Z',null from generate_series(1,3)n;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id)
 select pg_temp.ex_id('4',c),pg_temp.ex_id('2',1),pg_temp.ex_id('2',o) from generate_series(1,2)c cross join generate_series(5,6)o;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 select extensions.digest('execution-token-'||n,'sha256'),pg_temp.ex_id('1',1),pg_temp.ex_id('2',1),pg_temp.ex_id('2',n),clock_timestamp()+interval '1 day' from generate_series(5,6)n;
select pg_temp.ex_actor(1);
do $$declare r jsonb;payload jsonb;rid uuid:=pg_temp.ex_id('a',1);next_id uuid;before_rows jsonb;snap jsonb;begin
 perform pg_temp.ex_mobile_reject(pg_temp.ex_params(1,1,'start')||jsonb_build_object('p_operador_id',pg_temp.ex_id('2',6)),'42501');
 perform pg_temp.ex_mobile_reject(pg_temp.ex_params(1,3,'start'),'42501');
 perform pg_temp.ex_mobile_reject(pg_temp.ex_params(1,1,'start')||'{"p_occurred_at":"infinity"}','22023');
 perform pg_temp.ex_mobile_reject(pg_temp.ex_params(1,1,'start')||'{"p_effort_minutes":1}','22023');
 perform pg_temp.ex_mobile_reject(pg_temp.ex_params(1,1,'pause')||'{"p_pause_reason":"outro"}','22023');
 payload:=pg_temp.ex_params(1,1,'start');r:=pg_temp.ex_mobile(rid,payload);
 perform pg_temp.ex_check(r->>'disposition'='accepted','valid start accepted');
 perform pg_temp.ex_check(rm_private.execution_session_summary_v1(pg_temp.ex_id('7',1))->>'can_record'='true','open session context allows normal recording');
 update public.rm_celulas_projeto set bloqueada='sim' where id=pg_temp.ex_id('6',1);
 set local role authenticated;
 snap:=public.rm_mobile_execution_snapshot_v1('execution-token-5',pg_temp.ex_id('6',2));reset role;
 perform pg_temp.ex_check(snap->'allocation'->>'id'=pg_temp.ex_id('6',2)::text and snap->'running_session'->>'allocation_id'=pg_temp.ex_id('6',1)::text
  and snap->'running_session'->>'can_record'='false','foreign running session carries its own blocked recording context');
 update public.rm_celulas_projeto set bloqueada='n_o' where id=pg_temp.ex_id('6',1);
 perform pg_temp.ex_check(rm_private.execution_session_summary_v1(pg_temp.ex_id('7',1))->>'can_record'='true','unblocking restores recording metadata without changing evidence');
 perform set_config('lock_timeout','2345ms',true);
 perform pg_temp.ex_check(pg_temp.ex_mobile(rid,payload)->>'idempotent_replay'='true','frozen mobile retry idempotent');
 perform pg_temp.ex_check(current_setting('lock_timeout')='2345ms','execution retry restores caller lock timeout');
 set local role authenticated;
 perform public.rm_mobile_mutate_v1(pg_temp.ex_id('c',1),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.ex_id('6',1),'p_status','em_dia','p_operador_id',pg_temp.ex_id('2',5)),'execution-token-5');reset role;
 perform pg_temp.ex_check(current_setting('lock_timeout')='2345ms','legacy mobile RPC keeps caller lock timeout');
 perform set_config('lock_timeout','0',true);
 begin perform pg_temp.ex_mobile(rid,payload||'{"p_note":"altered"}');raise exception 'FAIL changed frozen mobile payload';exception when invalid_parameter_value then null;end;
 perform set_config('rm.test.execution.original',payload::text,true);
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',2),pg_temp.ex_params(2,2,'start'));
 perform pg_temp.ex_check(current_setting('lock_timeout')='0','new execution receipt restores caller lock timeout');
 perform pg_temp.ex_check(r->>'disposition'='review' and r->>'review_reason'='operator_already_running','second-device start preserved for review');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',3),pg_temp.ex_params(2,2,'pause',pg_temp.ex_id('a',2)));
 perform pg_temp.ex_check(r->>'disposition'='review','dependent conflicted event drains as evidence');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',4),pg_temp.ex_params(1,1,'pause',rid));
 perform pg_temp.ex_check(r->>'disposition'='accepted','pause releases canonical running claim');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',5),pg_temp.ex_params(3,2,'start'));
 perform pg_temp.ex_check(r->>'disposition'='accepted','paused work permits another allocation');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',6),pg_temp.ex_params(3,2,'finish',pg_temp.ex_id('a',5)));
 perform pg_temp.ex_check(r->>'disposition'='accepted' and rm_private.execution_session_summary_v1(pg_temp.ex_id('7',3))->>'confirmed_minutes'='120','effort only explicitly declared at finish');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',7),pg_temp.ex_params(1,1,'resume',pg_temp.ex_id('a',4)));
 perform pg_temp.ex_check(r->>'disposition'='accepted','resume uses canonical predecessor');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',8),pg_temp.ex_params(1,1,'pause',pg_temp.ex_id('a',1)));
 perform pg_temp.ex_check(r->>'disposition'='review' and r->>'review_reason'='previous_event_mismatch','forked predecessor preserved without changing canonical state');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',9),pg_temp.ex_params(1,1,'finish',pg_temp.ex_id('a',8)));
 perform pg_temp.ex_check(r->>'disposition'='review' and(select state='running' and last_event_id=pg_temp.ex_id('a',7) from rm_private.execution_sessions where id=pg_temp.ex_id('7',1)),'conflict tail does not falsely finish canonical session');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',10),pg_temp.ex_params(6,1,'start',null,6),'execution-token-6');
 perform pg_temp.ex_check(r->>'disposition'='accepted','different operators can work on one allocation');
 perform pg_temp.ex_mobile_reject(pg_temp.ex_params(1,1,'finish',pg_temp.ex_id('a',9),6),'42501','execution-token-6');
 set local role authenticated;
 snap:=public.rm_mobile_execution_snapshot_v1('execution-token-5',pg_temp.ex_id('6',1));reset role;
 perform pg_temp.ex_check(snap->'session'->>'operator_id'=pg_temp.ex_id('2',5)::text and jsonb_array_length(snap->'events')=5,'personal mobile timeline excludes another operator');
 perform pg_temp.ex_check(jsonb_array_length(snap->'review_sessions')=1 and snap->'session'->>'needs_review'='true','personal review evidence is visible');
 delete from public.rm_tablet_celula_users where identidade_id=pg_temp.ex_id('2',5) and celula_id=pg_temp.ex_id('4',1);
 begin perform pg_temp.ex_mobile(rid,payload);raise exception 'FAIL revoked access replay';exception when insufficient_privilege then null;end;
 insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values(pg_temp.ex_id('4',1),pg_temp.ex_id('2',1),pg_temp.ex_id('2',5));
 update rm_private.operator_delegations set expires_at=clock_timestamp()-interval '1 minute' where operator_id=pg_temp.ex_id('2',5);
 begin perform pg_temp.ex_mobile(rid,payload);raise exception 'FAIL expired delegation replay';exception when invalid_authorization_specification then null;end;
 update rm_private.operator_delegations set expires_at=clock_timestamp()+interval '1 day' where operator_id=pg_temp.ex_id('2',5);
 update public.rm_celulas_projeto set visibilidade=false where id=pg_temp.ex_id('6',2);
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',11),pg_temp.ex_params(8,2,'start'));
 perform pg_temp.ex_check(r->>'disposition'='review' and r->>'review_reason'='allocation_changed','hidden allocation evidence is preserved for review');
 perform pg_temp.ex_check(not exists(select 1 from public.rm_celulas_projeto where id in(pg_temp.ex_id('6',1),pg_temp.ex_id('6',2)) and(status<>'em_dia' or horas_realizadas is not null)),'execution never rewrites operational status or legacy hours');
 update public.rm_celulas_projeto set visibilidade=true where id=pg_temp.ex_id('6',2);
end$$;

select pg_temp.ex_actor(2);
do $$declare payload jsonb;rid uuid:=pg_temp.ex_id('b',1);r jsonb;snap jsonb;ctx jsonb;begin
 payload:=pg_temp.ex_review(1);perform set_config('rm.test.execution.review',payload::text,true);
 set local role authenticated;
 begin perform public.rm_web_mutate_v1(rid,'review_execution_session',payload);raise exception 'FAIL missing SSO permit';exception when insufficient_privilege then null;end;reset role;
 r:=pg_temp.ex_web(rid,payload);
 perform pg_temp.ex_check(r->'record'->>'review_id' is not null and rm_private.execution_session_summary_v1(pg_temp.ex_id('7',1))->>'confirmed_minutes'='90','manager explicitly reconciles effort');
 perform pg_temp.ex_check(pg_temp.ex_web(rid,payload)->>'idempotent_replay'='true','review frozen retry is idempotent');
 perform pg_temp.ex_web_reject(payload,'PT409');
 perform pg_temp.ex_web_reject(pg_temp.ex_review(2)||'{"effort_minutes":1.5}','22023');
 perform pg_temp.ex_web_reject(pg_temp.ex_review(2)||'{"action":"void"}','22023');
 perform pg_temp.ex_web_reject(pg_temp.ex_review(2)||'{"actor_id":"forged"}','22023');
 perform pg_temp.ex_web_reject(pg_temp.ex_review(2)||jsonb_build_object('reported_finished_at',clock_timestamp()+interval '1 day'),'22023');
 set local role authenticated;
 snap:=public.rm_web_execution_snapshot_v1(jsonb_build_object('project_id',null,'cell_id',null,'session_id',pg_temp.ex_id('7',1),'include_closed',false));reset role;
 perform pg_temp.ex_check(snap->>'complete'='true' and snap->'detail'->'session'->>'effort_source'='manager','web detail shows separate confirmed effort source');
 perform pg_temp.ex_check(jsonb_array_length(snap->'detail'->'events')=5 and jsonb_array_length(snap->'detail'->'reviews')=1,'original conflicted events survive management review');
 begin update rm_private.execution_events set note='overwrite' where id=pg_temp.ex_id('a',1);raise exception 'FAIL mutable event';exception when insufficient_privilege then null;end;
 begin update rm_private.execution_reviews set reason='overwrite' where session_id=pg_temp.ex_id('7',1);raise exception 'FAIL mutable review';exception when insufficient_privilege then null;end;
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.ex_id('1',2),'totp','verified');
 perform pg_temp.ex_web_reject(pg_temp.ex_review(2),'42501');
 perform pg_temp.ex_actor(2,'aal2');perform pg_temp.ex_web(gen_random_uuid(),pg_temp.ex_review(2,'void'));
 perform pg_temp.ex_check(rm_private.execution_session_summary_v1(pg_temp.ex_id('7',2))->>'state'='void' and rm_private.execution_session_summary_v1(pg_temp.ex_id('7',2))->'confirmed_minutes'='null','void preserves source and excludes effort');
end$$;
select pg_temp.ex_actor(1);
do $$declare r jsonb;snap jsonb;begin
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',12),pg_temp.ex_params(1,1,'finish',pg_temp.ex_id('a',9)));
 perform pg_temp.ex_check(r->>'disposition'='review' and(select state='finished' and needs_review from rm_private.execution_sessions where id=pg_temp.ex_id('7',1)),'late events after review preserve finished state and reopen evidence review');
 r:=pg_temp.ex_mobile(pg_temp.ex_id('a',13),pg_temp.ex_params(9,2,'start')||jsonb_build_object('p_occurred_at',clock_timestamp()+interval '1 day'));
 perform pg_temp.ex_check(r->>'disposition'='accepted' and rm_private.execution_session_summary_v1(pg_temp.ex_id('7',9))->>'clock_warning'='true','future device time retained and flagged without inferred duration');
 perform pg_temp.ex_mobile(pg_temp.ex_id('a',14),pg_temp.ex_params(9,2,'finish',pg_temp.ex_id('a',13))||'{"p_effort_minutes":null}');
 perform pg_temp.ex_check(rm_private.execution_session_summary_v1(pg_temp.ex_id('7',9))->'confirmed_minutes'='null','missing explicit effort remains unknown, never zero');
end$$;
select pg_temp.ex_actor(3);
select pg_temp.ex_web(gen_random_uuid(),pg_temp.ex_review(8,'void'));
select pg_temp.ex_actor(1);
select pg_temp.ex_mobile(pg_temp.ex_id('a',15),pg_temp.ex_params(10,2,'start'));
select pg_temp.ex_actor(2,'aal2');
select pg_temp.ex_web(gen_random_uuid(),pg_temp.ex_review(10,'void'));
update public.rm_projetos set status_pcp='cancelado' where id=pg_temp.ex_id('5',2);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_web_execution_snapshot_v1('{"project_id":null,"cell_id":null,"session_id":null,"include_closed":false}');
 perform pg_temp.ex_check(exists(select 1 from jsonb_array_elements(r->'allocations') a where a->>'id'=pg_temp.ex_id('6',2)::text),'unreviewed clock evidence keeps a closed project allocation in the board');
 perform pg_temp.ex_check(exists(select 1 from jsonb_array_elements(r->'sessions') s where s->>'id'=pg_temp.ex_id('7',9)::text),'unreviewed clock evidence survives a newer terminal session');
 perform pg_temp.ex_check(exists(select 1 from jsonb_array_elements(r->'sessions') s where s->>'id'=pg_temp.ex_id('7',9)::text and s->>'can_record'='false'),'closed project has explicit non-recordable context in retained summary');
end$$;
reset role;
select pg_temp.ex_web(gen_random_uuid(),pg_temp.ex_review(9));
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_web_execution_snapshot_v1('{"project_id":null,"cell_id":null,"session_id":null,"include_closed":false}');
 perform pg_temp.ex_check(not exists(select 1 from jsonb_array_elements(r->'allocations') a where a->>'id'=pg_temp.ex_id('6',2)::text),'management reconciliation resolves clock attention without rewriting original events');
 r:=public.rm_web_execution_snapshot_v1(jsonb_build_object('project_id',null,'cell_id',null,'session_id',pg_temp.ex_id('7',9),'include_closed',false));
 perform pg_temp.ex_check(r->'detail'->'session'->>'clock_warning'='true' and r->'detail'->'session'->>'has_review'='true','raw clock warning remains in explicit historical detail');
end$$;
reset role;
select pg_temp.ex_actor(4);
select pg_temp.ex_web_reject(pg_temp.ex_review(6),'42501');
set local role authenticated;
select pg_temp.ex_check((public.rm_web_execution_snapshot_v1('{"project_id":null,"cell_id":null,"session_id":null,"include_closed":false}')->>'complete')::boolean,'auditor can consult execution evidence');
do $$begin
 begin delete from rm_private.execution_events;raise exception 'FAIL direct evidence delete';exception when insufficient_privilege then null;end;
 begin update rm_private.execution_sessions set state='finished';raise exception 'FAIL direct projection write';exception when insufficient_privilege then null;end;
end$$;
reset role;
select pg_temp.ex_actor(2,'aal2');
do $$declare ctx jsonb;payload jsonb;snapshot jsonb;begin
 ctx:=public.rm_web_project_delete_snapshot_v1(pg_temp.ex_id('5',1));
 perform pg_temp.ex_check(exists(select 1 from rm_private.project_delete_scope_v1(pg_temp.ex_id('5',1)) where table_name='execution_events' and cardinality(ids)>0),'explicit project deletion owns execution evidence');
 payload:=jsonb_build_object('id',pg_temp.ex_id('5',1),'expected_updated_at',ctx->'project'->>'updated_at','expected_context_version',ctx->>'context_version','confirm_delete',true,'justificativa','Delete isolated execution project');
 perform pg_temp.ex_web(gen_random_uuid(),payload,'delete_project','em.projects.manage');
 perform pg_temp.ex_check(not exists(select 1 from rm_private.execution_sessions where allocation_id=pg_temp.ex_id('6',1)) and exists(select 1 from rm_private.execution_sessions where allocation_id=pg_temp.ex_id('6',2)),'project deletion removes only owned execution, preserves other projects');
 begin perform pg_temp.ex_web(pg_temp.ex_id('b',1),current_setting('rm.test.execution.review')::jsonb);raise exception 'FAIL review tombstone';exception when sqlstate 'PT410' then null;end;
 perform pg_temp.ex_actor(1);
 begin perform pg_temp.ex_mobile(pg_temp.ex_id('a',1),current_setting('rm.test.execution.original')::jsonb);raise exception 'FAIL mobile tombstone';exception when sqlstate 'PT410' then null;end;
 begin perform pg_temp.ex_mobile(pg_temp.ex_id('a',1),current_setting('rm.test.execution.original')::jsonb||'{"p_note":"changed"}');raise exception 'FAIL changed tombstone';exception when invalid_parameter_value then null;end;
end$$;
rollback;
select 'PASS: execution preserves immutable evidence, offline conflict tails, actors/grants, canonical claims, explicit effort, reviews, clock warnings, SSO/MFA and owned tombstones' result;

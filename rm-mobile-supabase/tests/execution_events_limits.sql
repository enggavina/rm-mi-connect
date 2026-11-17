\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create function pg_temp.el_id(h text,n int) returns uuid language sql immutable as $$select(h||'df05100-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.el_check(value boolean,message text) returns void language plpgsql as $$begin if value is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
insert into auth.users(id) values(pg_temp.el_id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.el_id('2',1),pg_temp.el_id('1',1),'Execution limits reader','administrador','ativo');
insert into public.rm_projetos(id,numero) values(pg_temp.el_id('5',1),'EXECUTION LIMITS');
insert into public.rm_celulas(id,nome) select pg_temp.el_id('4',n),'Execution limits cell '||n from generate_series(1,2001)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade) select pg_temp.el_id('6',n),pg_temp.el_id('5',1),pg_temp.el_id('4',n),'em_dia',true from generate_series(1,2001)n;
select set_config('request.jwt.claim.sub',pg_temp.el_id('1',1)::text,true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_web_execution_snapshot_v1(jsonb_build_object('project_id',pg_temp.el_id('5',1),'cell_id',null,'session_id',null,'include_closed',true));
 perform pg_temp.el_check(r->>'complete'='false' and r->>'total'='2001' and r->'allocations'='[]' and r->'sessions'='[]' and r->'detail'='null','allocation bound returns no partial board');
end$$;
reset role;
insert into rm_private.execution_sessions(id,allocation_id,operator_id,state,needs_review)
 select pg_temp.el_id('7',n),pg_temp.el_id('6',1),pg_temp.el_id('2',1),'review',true from generate_series(1,4001)n;
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_web_execution_snapshot_v1(jsonb_build_object('project_id',pg_temp.el_id('5',1),'cell_id',pg_temp.el_id('4',1),'session_id',null,'include_closed',true));
 perform pg_temp.el_check(r->>'complete'='false' and r->>'total'='1' and r->'allocations'='[]' and r->'sessions'='[]','session bound returns no partial board');
end$$;
reset role;
delete from rm_private.execution_sessions where operator_id=pg_temp.el_id('2',1) and id<>pg_temp.el_id('7',1);
insert into rm_private.execution_events(id,session_id,previous_event_id,kind,occurred_at,pause_reason,note,disposition,operator_id,tablet_user_id,auth_user_id)
 select pg_temp.el_id('e',n),pg_temp.el_id('7',1),case when n=1 then null else pg_temp.el_id('e',n-1) end,
 case when n=1 then 'start' when n%2=0 then 'pause' else 'resume' end,clock_timestamp()-interval '1 day'+n*interval '1 second',case when n%2=0 then 'material' else null end,
 repeat(chr(128512),1000),'accepted',pg_temp.el_id('2',1),pg_temp.el_id('2',1),pg_temp.el_id('1',1) from generate_series(1,201)n;
insert into rm_private.execution_reviews(id,session_id,action,reported_finished_at,effort_minutes,note,reason,actor_id)
 select pg_temp.el_id('f',n),pg_temp.el_id('7',1),'confirm_finished',clock_timestamp(),0,repeat(chr(128512),1000),repeat(chr(128512),2000),pg_temp.el_id('2',1) from generate_series(1,101)n;
update rm_private.execution_sessions set state='finished',needs_review=false,last_event_id=pg_temp.el_id('e',201),last_received_event_id=pg_temp.el_id('e',201) where id=pg_temp.el_id('7',1);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('execution-limits-mobile','sha256'),pg_temp.el_id('1',1),pg_temp.el_id('2',1),pg_temp.el_id('2',1),clock_timestamp()+interval '1 day');
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_mobile_execution_snapshot_v1('execution-limits-mobile',pg_temp.el_id('6',1));
 perform pg_temp.el_check(r->>'events_total'='201' and r->>'events_complete'='false' and jsonb_array_length(r->'events')<=200,'mobile timeline remains explicitly bounded with full count');
 perform pg_temp.el_check(r->>'reviews_total'='101' and r->>'reviews_complete'='false' and jsonb_array_length(r->'reviews')<=100,'mobile review history remains explicitly bounded with full count');
 perform pg_temp.el_check(octet_length(r::text)<=2097152 and r->'session'->>'last_event_id'=pg_temp.el_id('e',201)::text,'UTF4 budget fallback retains authoritative canonical predecessor and version');
 r:=public.rm_web_execution_snapshot_v1(jsonb_build_object('project_id',pg_temp.el_id('5',1),'cell_id',pg_temp.el_id('4',1),'session_id',pg_temp.el_id('7',1),'include_closed',true));
 perform pg_temp.el_check(r->>'complete'='true' and r->'detail'->>'events_complete'='false' and r->'detail'->>'reviews_complete'='false','complete board distinguishes independently bounded detail');
 perform pg_temp.el_check(jsonb_array_length(r->'detail'->'events')=200 and jsonb_array_length(r->'detail'->'reviews')=100,'web budget can retain last200/100 UTF4 records');
 r:=public.rm_mobile_mutate_v1(pg_temp.el_id('a',1),'rm_record_execution_event_v1',jsonb_build_object('p_session_id',pg_temp.el_id('7',5000),'p_allocation_id',pg_temp.el_id('6',1),
  'p_previous_event_id',null,'p_kind','start','p_occurred_at',clock_timestamp(),'p_pause_reason',null,'p_note',null,'p_effort_minutes',null,'p_operador_id',pg_temp.el_id('2',1)),'execution-limits-mobile');
 perform pg_temp.el_check(r->>'disposition'='accepted','large historical detail does not block a new valid execution command');
end$$;
reset role;
update public.rm_users set nome=repeat('x',11000000) where id=pg_temp.el_id('2',1);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_web_execution_snapshot_v1(jsonb_build_object('project_id',pg_temp.el_id('5',1),'cell_id',pg_temp.el_id('4',1),'session_id',null,'include_closed',true));
 perform pg_temp.el_check(r->>'complete'='false' and r->'allocations'='[]' and r->'sessions'='[]','oversized metadata never escapes as a partial board');
 begin perform public.rm_mobile_execution_snapshot_v1('execution-limits-mobile',pg_temp.el_id('6',1));raise exception 'FAIL oversized mobile detail';exception when sqlstate 'PT413' then null;end;
end$$;
reset role;
rollback;
select 'PASS: execution limits preserve complete boards at 2000/4000/10MiB, explicit last200/100 histories, canonical predecessor and mobile2MiB budget' result;

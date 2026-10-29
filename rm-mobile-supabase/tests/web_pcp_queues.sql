\set ON_ERROR_STOP on
begin;
create function pg_temp.pcp_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.pcp_key(h text,n integer) returns uuid language sql immutable as $$
  select (h||'d000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.pcp_actor(n integer,aal text default 'aal1') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',pg_temp.pcp_key('1',n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.pcp_key('3',n),'aal',aal)::text,true);
  perform set_config('rm.test.pcp.actor',n::text,true);
end $$;
create function pg_temp.pcp_payload(n integer default 1,reorder boolean default false) returns jsonb language sql as $$
  with s as (select public.rm_web_cell_queue_snapshot_v1(pg_temp.pcp_key('4',n)) r)
  select jsonb_build_object('celula_id',pg_temp.pcp_key('4',n),'expected_queue_version',r->>'queue_version','apply_order',reorder,
    'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i->>'id','expected_updated_at',i->>'updated_at',
      'prioridade',i->'prioridade') order by ordinality),'[]'::jsonb) from jsonb_array_elements(r->'items') with ordinality x(i,ordinality))) from s;
$$;
create function pg_temp.pcp_call(rid uuid,p jsonb,cap text default 'em.planning.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.pcp.actor'),64,'e'),rid,'save_cell_queue',p,cap);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,'save_cell_queue',p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.pcp_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$
declare actual text; begin
  begin perform pg_temp.pcp_call(gen_random_uuid(),p,cap);
  exception when others then get stacked diagnostics actual=returned_sqlstate;
    if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
  end; raise exception 'FAIL: queue save unexpectedly succeeded (expected %)',wanted;
end $$;
do $$ declare n integer; begin
  for n in 1..6 loop
    insert into auth.users(id) values(pg_temp.pcp_key('1',n));
    if n<>5 then
      insert into public.rm_users(id,auth_user_id,nome,perfil,status)
      values(pg_temp.pcp_key('2',n),pg_temp.pcp_key('1',n),'PCP fixture '||n,
        case when n in(1,6) then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
        case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
    end if;
    insert into auth.sessions(id,user_id) values(pg_temp.pcp_key('3',n),pg_temp.pcp_key('1',n));
    if n not in(4,5) then
      insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
      values(pg_temp.pcp_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.pcp_key('9',n),
        pg_temp.pcp_key('2',n),pg_temp.pcp_key('1',n),true,pg_temp.pcp_key('2',1),clock_timestamp());
      perform public.rm_sso_session_put_v1(lpad(n::text,64,'e'),pg_temp.pcp_key('8',n),pg_temp.pcp_key('3',n),'opaque-pcp-fixture-'||n,clock_timestamp()+interval '45 minutes');
    end if;
  end loop;
end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) values
 (pg_temp.pcp_key('4',1),'PCP priority cell'),(pg_temp.pcp_key('4',2),'PCP receiving cell'),(pg_temp.pcp_key('4',3),'PCP unknown load');
insert into public.rm_clientes(id,nome) values(pg_temp.pcp_key('c',1),'PCP-QA-21 customer');
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.pcp_key('b',1),'PCP-QA-21 type');
insert into public.rm_projetos(id,numero,nome,cliente_id,tipo_equipamento_id,chegada_do_equipamento)
 select pg_temp.pcp_key('5',n),'PCP-QA-21-'||n,'PCP-QA-21 equipment '||n,pg_temp.pcp_key('c',1),
   case when n in(8,9,12) then null else pg_temp.pcp_key('b',1) end,
   case when n in(10,12) then null else '2026-10-29T10:00:00Z'::timestamptz end
 from generate_series(1,12) n;
update public.rm_projetos set status_pcp='cancelado' where id=pg_temp.pcp_key('5',4);
update public.rm_projetos set data_real_de_entrega='2026-10-29T10:00:00Z' where id=pg_temp.pcp_key('5',5);
update public.rm_projetos set numero=null where id=pg_temp.pcp_key('5',11);
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,numero_projeto,cliente_nome_export,tipo_equipamento_nome_export,
 status,visibilidade,prioridade,posicao,indice,horas_previstas,data_inicio,data_limite,responsavel_id,bloqueada,motivo_bloqueio)
 select pg_temp.pcp_key('6',n),pg_temp.pcp_key('5',n),pg_temp.pcp_key('4',case when n in(9,10,11) then 2 else 1 end),
   'PCP-QA-21-'||n,'PCP export customer','PCP export type',
   case when n=6 then 'finalizado'::public.rm_status_cel_proj_enum when n=7 then 'n_a' else 'em_dia' end,
   n<>2,case when n=1 then 'baixa'::public.rm_prioridade_cel_enum when n=2 then 'alta' else null end,
   case when n=1 then 3 when n=2 then null when n=3 then 0 else n end,case when n=2 then 8 else 77 end,
   case when n=2 then 2.5 when n=3 then 0 else null end,'2026-10-28T10:00:00Z','2026-10-28T18:00:00Z',
   pg_temp.pcp_key('2',2),case when n=3 then 'sim'::public.rm_sim_nao_enum else 'n_o' end,
   case when n=3 then 'PCP test blocked' else null end
 from generate_series(1,11) n where n not in(8);
-- Date-only planning deadlines are inclusive in the office timezone. UTC
-- midnight of the same calendar date is still the previous day in Sao Paulo.
update public.rm_celulas_projeto set data_limite=case
  when id=pg_temp.pcp_key('6',1) then (((statement_timestamp() at time zone 'America/Sao_Paulo')::date+time '12:00') at time zone 'America/Sao_Paulo')
  when id=pg_temp.pcp_key('6',2) then ((((statement_timestamp() at time zone 'America/Sao_Paulo')::date-1)+time '23:59') at time zone 'America/Sao_Paulo')
  else (((statement_timestamp() at time zone 'America/Sao_Paulo')::date)::timestamp at time zone 'UTC') end
where id in(pg_temp.pcp_key('6',1),pg_temp.pcp_key('6',2),pg_temp.pcp_key('6',3));
select pg_temp.pcp_actor(1);
set local role authenticated;
do $$ declare s jsonb; load jsonb; receiving jsonb; begin
  s:=public.rm_web_cell_queue_snapshot_v1(pg_temp.pcp_key('4',1));
  perform pg_temp.pcp_check((s->>'total')::int=3 and (s->>'complete')::boolean,'queue excludes closed projects and completed allocations, includes hidden');
  perform pg_temp.pcp_check(s->'items'->0->>'id'=pg_temp.pcp_key('6',3)::text
    and s->'items'->2->>'id'=pg_temp.pcp_key('6',2)::text,'mobile position/index fallback with deterministic UUID tie-break');
  perform pg_temp.pcp_check(s->'items'->1->>'cliente_nome_export'='PCP export customer'
    and s::text !~ 'bubble_id|auth_user|sync_source|arquivo|email|token|url','planning snapshot exports only safe allocation context');
  perform pg_temp.pcp_check(s->>'queue_version'~'^[0-9a-f]{64}$','opaque queue SHA256');
  perform pg_temp.pcp_check(public.rm_web_cell_queue_snapshot_v1(gen_random_uuid()) is null,'unknown cell snapshot is null');
  load:=public.rm_web_planning_load_v1();
  select i into load from jsonb_array_elements(load->'cells') i where i->>'id'=pg_temp.pcp_key('4',1)::text;
  perform pg_temp.pcp_check((load->>'open_allocations')::int=3 and (load->>'visible_allocations')::int=2
    and (load->>'hidden_allocations')::int=1 and (load->>'blocked_allocations')::int=1,'load uses exactly the queue scope');
  perform pg_temp.pcp_check((load->>'estimated_allocations')::int=2 and (load->>'unestimated_allocations')::int=1
    and load->>'planned_hours'='2.50','explicit zero remains an estimate and decimal sums stay text');
  perform pg_temp.pcp_check((load->>'overdue_allocations')::int=2,'today is inclusive while yesterday and the UTC/Sao Paulo boundary are overdue');
  select i into load from jsonb_array_elements(public.rm_web_planning_load_v1()->'cells') i where i->>'id'=pg_temp.pcp_key('4',3)::text;
  perform pg_temp.pcp_check(load->'planned_hours'='null'::jsonb and (load->>'open_allocations')::int=0,'no estimates is unknown, not manufactured zero capacity');
  receiving:=public.rm_web_receivings_v1('all','PCP-QA-21',1,2);
  perform pg_temp.pcp_check((receiving->>'total')::int=4 and jsonb_array_length(receiving->'items')=2,'receiving list has true pagination and excludes complete project with historic arrival absent');
  perform pg_temp.pcp_check((public.rm_web_receivings_v1('legacy_type_locked','PCP-QA-21',1,25)->>'total')::int=1,'missing type with allocated cells stays explicit legacy review');
  perform pg_temp.pcp_check((public.rm_web_receivings_v1('awaiting_arrival','PCP-QA-21',1,25)->>'total')::int=1,'arrival filter is only within the receiving readiness base');
  perform pg_temp.pcp_check(receiving->'summary'=public.rm_web_receivings_v1('without_number','no matches',2,1)->'summary','summary describes full active base before filters and overlapping reasons are not summed');
  perform pg_temp.pcp_check(receiving::text !~ 'arquivo_url|arquivo_nota|auth_user|bubble_id|sync_source|email|token','receiving DTO contains no file URLs or private data');
end $$;
reset role;

do $$ declare p jsonb; no_op jsonb; before_rows jsonb; after_rows jsonb; r jsonb; rid uuid:=gen_random_uuid(); begin
  p:=pg_temp.pcp_payload();
  perform pg_temp.pcp_reject(p,'22023','em.projects.manage');
  perform pg_temp.pcp_reject(p||'{"actor_id":"2d000000-0000-4000-8000-000000000001"}','22023');
  perform pg_temp.pcp_reject(p-'apply_order','22023');
  perform pg_temp.pcp_reject(jsonb_set(p,'{items,0,prioridade}','"urgent"'),'22023');
  perform pg_temp.pcp_reject(jsonb_set(p,'{items,0,expected_updated_at}','"infinity"'),'22023');
  perform pg_temp.pcp_reject(jsonb_set(p,'{items,0,expected_updated_at}','"2000-01-01T00:00:00Z"'),'PT409');
  perform pg_temp.pcp_reject(p||jsonb_build_object('items',jsonb_build_array(p->'items'->0,p->'items'->0,p->'items'->2)),'22023');
  perform pg_temp.pcp_reject(p||jsonb_build_object('items',jsonb_build_array(p->'items'->2,p->'items'->1,p->'items'->0)),'22023');
  perform pg_temp.pcp_reject(p||jsonb_build_object('items',jsonb_build_array(p->'items'->0,p->'items'->1)),'PT409');
  perform pg_temp.pcp_reject(p||jsonb_build_object('items',(select jsonb_agg(p->'items'->0) from generate_series(1,2001))),'22023');
  select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.rm_celulas_projeto a where celula_id=pg_temp.pcp_key('4',1);
  no_op:=pg_temp.pcp_call(gen_random_uuid(),p);
  select jsonb_agg(to_jsonb(a) order by id) into after_rows from public.rm_celulas_projeto a where celula_id=pg_temp.pcp_key('4',1);
  perform pg_temp.pcp_check(before_rows=after_rows and no_op->'record'->'changed_ids'='[]','no-op preserves every allocation byte including timestamps');
  -- Priority-only save does not normalize existing sparse/null positions and
  -- does not touch the two allocations whose priority did not change.
  p:=jsonb_set(p,'{items,1,prioridade}','"muito_alta"');
  r:=pg_temp.pcp_call(rid,p);
  perform pg_temp.pcp_check(jsonb_array_length(r->'record'->'changed_ids')=1,'only edited priority row changes');
  perform pg_temp.pcp_check((select posicao=3 and indice=77 and prioridade='muito_alta' and modified_by_id=pg_temp.pcp_key('2',1)
    from public.rm_celulas_projeto where id=pg_temp.pcp_key('6',1)),'priority-only saves preserve position/index and derive actor');
  perform pg_temp.pcp_check((select to_jsonb(a)=before_rows->0 from public.rm_celulas_projeto a where id=pg_temp.pcp_key('6',1)) is false,'edited row receives a new revision');
  perform pg_temp.pcp_check((select to_jsonb(a)=before_rows->1 from public.rm_celulas_projeto a where id=pg_temp.pcp_key('6',2)),'unedited row with NULL position is untouched');
  perform pg_temp.pcp_check((pg_temp.pcp_call(rid,p)->>'idempotent_replay')::boolean,'exact replay succeeds before stale queue version checks');
  begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'save_cell_queue',p); raise exception 'FAIL: permitless replay';
  exception when insufficient_privilege then reset role; end;
  begin perform pg_temp.pcp_call(rid,jsonb_set(p,'{items,1,prioridade}','"baixa"')); raise exception 'FAIL: changed payload replay';
  exception when unique_violation then null; end;
  perform pg_temp.pcp_actor(6);
  begin perform pg_temp.pcp_call(rid,p); raise exception 'FAIL: changed actor replay'; exception when unique_violation then null; end;
  perform pg_temp.pcp_actor(1);
  insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
  begin perform pg_temp.pcp_call(rid,p); raise exception 'FAIL: AAL1 replay'; exception when insufficient_privilege then null; end;
  perform pg_temp.pcp_actor(1,'aal2');
  perform pg_temp.pcp_check((pg_temp.pcp_call(rid,p)->>'idempotent_replay')::boolean,'verified TOTP enforces AAL2 even for retry');
  delete from auth.mfa_factors where user_id=auth.uid();
  perform pg_temp.pcp_actor(1);
  p:=pg_temp.pcp_payload();
  select jsonb_agg(to_jsonb(a)-array['prioridade','posicao','updated_at','modified_by_id','replanejada_em','replanejada_por_id','sync_source'] order by id)
    into before_rows from public.rm_celulas_projeto a where celula_id=pg_temp.pcp_key('4',1);
  p:=p||jsonb_build_object('apply_order',true,'items',jsonb_build_array(p->'items'->2,p->'items'->1,p->'items'->0));
  r:=pg_temp.pcp_call(gen_random_uuid(),p);
  perform pg_temp.pcp_check((select array_agg(id order by posicao) from public.rm_celulas_projeto where id=any(array[pg_temp.pcp_key('6',1),pg_temp.pcp_key('6',2),pg_temp.pcp_key('6',3)]))
    =array[pg_temp.pcp_key('6',2),pg_temp.pcp_key('6',1),pg_temp.pcp_key('6',3)],'explicit reorder sets only the selected full queue order');
  select jsonb_agg(to_jsonb(a)-array['prioridade','posicao','updated_at','modified_by_id','replanejada_em','replanejada_por_id','sync_source'] order by id)
    into after_rows from public.rm_celulas_projeto a where celula_id=pg_temp.pcp_key('4',1);
  perform pg_temp.pcp_check(before_rows=after_rows,'order save preserves forms/status/deadlines/visibility/index/other rows');
  p:=pg_temp.pcp_payload();
  update public.rm_projetos set nome='Changed related project' where id=pg_temp.pcp_key('5',1);
  perform pg_temp.pcp_reject(p,'PT409');
end $$;

-- An oversized real read never exposes an editable partial queue. Submitting
-- 2,000 otherwise valid members cannot replace a queue that has 2,001 members.
insert into public.rm_celulas(id,nome) values(pg_temp.pcp_key('4',4),'PCP overflow fixture');
insert into public.rm_projetos(id,numero)
 select pg_temp.pcp_key('5',n),'PCP-OVERFLOW-21-'||n from generate_series(10001,12001) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,posicao)
 select pg_temp.pcp_key('6',n),pg_temp.pcp_key('5',n),pg_temp.pcp_key('4',4),'em_dia',true,n-10000
 from generate_series(10001,12001) n;
do $$ declare s jsonb; p jsonb; begin
 set local role authenticated;
 s:=public.rm_web_cell_queue_snapshot_v1(pg_temp.pcp_key('4',4));
 reset role;
 perform pg_temp.pcp_check((s->>'total')::integer=2001 and not (s->>'complete')::boolean
  and s->'items'='[]'::jsonb and s->>'queue_version'~'^[0-9a-f]{64}$','overflow read is explicit and returns no editable partial members');
 select jsonb_build_object('celula_id',pg_temp.pcp_key('4',4),'expected_queue_version',s->>'queue_version',
  'apply_order',true,'items',jsonb_agg(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'prioridade',a.prioridade) order by a.id))
 into p from (select * from public.rm_celulas_projeto where celula_id=pg_temp.pcp_key('4',4) order by id limit 2000) a;
 perform pg_temp.pcp_reject(p,'PT409');
 perform pg_temp.pcp_check((select count(*)=2001 and bool_and(prioridade is null) and min(posicao)=1 and max(posicao)=2001
  from public.rm_celulas_projeto where celula_id=pg_temp.pcp_key('4',4)),'partial overflow submission preserves all original members and positions');
end $$;

select pg_temp.pcp_actor(2);
select pg_temp.pcp_check((pg_temp.pcp_call(gen_random_uuid(),pg_temp.pcp_payload())->>'operation')='save_cell_queue','standard PCP profile can plan without operator/cell ACL invention');
select pg_temp.pcp_actor(3);
select pg_temp.pcp_check(public.rm_web_cell_queue_snapshot_v1(pg_temp.pcp_key('4',1)) is not null,'auditor can consult queue');
select pg_temp.pcp_reject(pg_temp.pcp_payload(),'42501');
select pg_temp.pcp_actor(4);
set local role authenticated;
select pg_temp.pcp_check(public.rm_web_cell_queue_snapshot_v1(pg_temp.pcp_key('4',1)) is null,'inactive RM user cannot read snapshot');
select pg_temp.pcp_check(public.rm_web_planning_load_v1()->'cells'='[]','inactive RM user cannot read load');
reset role;
select pg_temp.pcp_actor(5);
set local role authenticated;
select pg_temp.pcp_check(public.rm_web_cell_queue_snapshot_v1(pg_temp.pcp_key('4',1)) is null,'unbound Auth user cannot read snapshot');
reset role;
select pg_temp.pcp_check(not has_function_privilege('anon','public.rm_web_cell_queue_snapshot_v1(uuid)','execute')
 and not has_function_privilege('service_role','public.rm_web_receivings_v1(text,text,integer,integer)','execute')
 and not has_function_privilege('authenticated','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_stage_core_v1(uuid,text,jsonb)','execute'),'private mutations and anonymous reads remain closed');
select pg_temp.pcp_check(bool_and(not prosecdef and provolatile='s'),'all three reads are stable invoker')
 from pg_proc where oid in('public.rm_web_cell_queue_snapshot_v1(uuid)'::regprocedure,
 'public.rm_web_planning_load_v1()'::regprocedure,'public.rm_web_receivings_v1(text,text,integer,integer)'::regprocedure);
rollback;
select 'PASS: PCP queue scope/exports, exact priority/order separation, no-op, readiness/load, SSO/MFA and retry' as result;

-- Committed fixtures belong only to the disposable local PostgreSQL database.
-- Two real backends contend on row/advisory locks, including FK insert phantoms.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_pcp;
create function rm_test_pcp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function rm_test_pcp.key(h text,n integer) returns uuid language sql immutable as $$
 select (h||'f000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
insert into auth.users(id) values(rm_test_pcp.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values(rm_test_pcp.key('2',1),rm_test_pcp.key('1',1),'Concurrent PCP planner','administrador');
insert into auth.sessions(id,user_id) values(rm_test_pcp.key('3',1),rm_test_pcp.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_pcp.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_pcp.key('9',1),
  rm_test_pcp.key('2',1),rm_test_pcp.key('1',1),true,rm_test_pcp.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('f',64),rm_test_pcp.key('8',1),rm_test_pcp.key('3',1),'opaque-fixture-pcp-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('pcp-local-mobile-fixture','sha256'),rm_test_pcp.key('1',1),rm_test_pcp.key('2',1),rm_test_pcp.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_tipos_equipamento(id,nome) values(rm_test_pcp.key('b',1),'PCP concurrent motor');
insert into public.rm_celulas(id,nome) select rm_test_pcp.key('4',n),'PCP race '||n from generate_series(1,8) n;
insert into public.rm_projetos(id,numero,tipo_equipamento_id,status_pcp)
 select rm_test_pcp.key('5',n*10+k),'PCP-RACE-'||n||'-'||k,rm_test_pcp.key('b',1),
  case when n=4 and k=2 then 'cancelado'::public.rm_status_pcp_enum else 'aguardando_recebimento_equipamento' end
 from generate_series(1,8) n cross join generate_series(1,2) k;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,posicao,prioridade)
 select rm_test_pcp.key('6',n*10+1),rm_test_pcp.key('5',n*10+1),rm_test_pcp.key('4',n),'em_dia',true,7,'baixa'
 from generate_series(1,8) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,posicao,prioridade)
 values(rm_test_pcp.key('6',42),rm_test_pcp.key('5',42),rm_test_pcp.key('4',4),'em_dia',false,18,'media');
insert into public.rm_celula_tipos_equipamento(celula_id,tipo_equipamento_id,visibilidade)
 values(rm_test_pcp.key('4',5),rm_test_pcp.key('b',1),true),
 (rm_test_pcp.key('4',6),rm_test_pcp.key('b',1),false);
create function rm_test_pcp.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare result jsonb; state text; capability text; operation text;
begin
 perform set_config('request.jwt.claim.sub',rm_test_pcp.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_pcp.key('3',1),'aal','aal1')::text,true);
 if mode in('queue','plan','project') then
  operation:=case mode when 'queue' then 'save_cell_queue' when 'plan' then 'plan_cell' else 'save_project' end;
  capability:=case when mode='project' then 'em.projects.manage' else 'em.planning.manage' end;
  perform public.rm_sso_action_permit_v1(repeat('f',64),rid,operation,p,capability);
  set local role authenticated; result:=public.rm_web_mutate_v1(rid,operation,p); reset role;
 elsif mode='materialize' then
  set local role service_role;
  result:=public.rm_materialize_project_cells_v1((p->>'id')::uuid);
  reset role;
 elsif mode='mobile' then
  set local role authenticated;
  result:=public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',p,'pcp-local-mobile-fixture');
  reset role;
 else raise exception 'Unknown local race mode'; end if;
 perform pg_sleep(hold_seconds);
 return jsonb_build_object('sqlstate','00000','result',result);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate;
 return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end $$;
commit;

do $$ declare scenario integer; cell_id uuid; existing_project uuid; candidate_project uuid;
  snapshot jsonb; queue_payload jsonb; other_payload jsonb; first_payload jsonb; second_payload jsonb;
  first_mode text; second_mode text; first_id uuid; second_id uuid; initial_total integer;
  a jsonb; b jsonb; pid_a integer; pid_b integer; waited integer;
begin
 perform dblink_connect('pcp_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('pcp_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('pcp_a','select pg_backend_pid()') as t(pid integer);
 select pid into pid_b from dblink('pcp_b','select pg_backend_pid()') as t(pid integer);
 for scenario in 1..8 loop
  cell_id:=rm_test_pcp.key('4',scenario); existing_project:=rm_test_pcp.key('5',scenario*10+1);
  candidate_project:=rm_test_pcp.key('5',scenario*10+2);
  snapshot:=public.rm_web_cell_queue_snapshot_v1(cell_id); initial_total:=(snapshot->>'total')::integer;
  select jsonb_build_object('celula_id',cell_id,'expected_queue_version',snapshot->>'queue_version','apply_order',false,
    'items',jsonb_agg(jsonb_build_object('id',i->>'id','expected_updated_at',i->>'updated_at','prioridade','alta') order by ordinality))
   into queue_payload from jsonb_array_elements(snapshot->'items') with ordinality x(i,ordinality);
  if scenario in(1,2) then
   other_payload:=jsonb_build_object('projeto_id',candidate_project,'celula_id',cell_id,'expected_updated_at',null,
    'changes',jsonb_build_object('observacao','Concurrent new allocation'));
   first_mode:=case scenario when 1 then 'plan' else 'queue' end;
   second_mode:=case scenario when 1 then 'queue' else 'plan' end;
  elsif scenario in(3,4) then
   select jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'changes',
    jsonb_build_object('status_pcp',case scenario when 3 then 'cancelado' else 'aguardando_recebimento_equipamento' end))
    into other_payload from public.rm_projetos p where p.id=case scenario when 3 then existing_project else candidate_project end;
   first_mode:='project'; second_mode:='queue';
  elsif scenario in(5,6) then
   other_payload:=jsonb_build_object('id',candidate_project);
   first_mode:=case scenario when 5 then 'materialize' else 'queue' end;
   second_mode:=case scenario when 5 then 'queue' else 'materialize' end;
  elsif scenario=7 then
   other_payload:=jsonb_build_object('p_celula_projeto_id',rm_test_pcp.key('6',71),'p_status','retornado');
   first_mode:='mobile'; second_mode:='queue';
  else first_mode:='queue'; second_mode:='queue'; other_payload:=queue_payload; end if;
  first_payload:=case when first_mode='queue' then queue_payload else other_payload end;
  second_payload:=case when second_mode='queue' then queue_payload else other_payload end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=8 then first_id else gen_random_uuid() end;
  perform dblink_send_query('pcp_a',format('select rm_test_pcp.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,first_payload::text));
  waited:=0;
  loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: PCP A scenario % did not hold; %',scenario,first_mode; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('pcp_b',format('select rm_test_pcp.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  waited:=0;
  loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>150 then raise exception 'FAIL: PCP B scenario % did not contend',scenario; end if; perform pg_sleep(0.005);
  end loop;
  select r into a from dblink_get_result('pcp_a') as t(r jsonb); perform r from dblink_get_result('pcp_a') as t(r jsonb);
  select r into b from dblink_get_result('pcp_b') as t(r jsonb); perform r from dblink_get_result('pcp_b') as t(r jsonb);
  perform rm_test_pcp.check(a->>'sqlstate'='00000',format('first scenario %s succeeds: %s',scenario,a));
  perform rm_test_pcp.check(b->>'sqlstate'=case when scenario in(1,3,4,5,7) then 'PT409' else '00000' end,
   format('second scenario %s observes membership/revision or serializes after: %s',scenario,b));
  if scenario in(1,2,5,6) then
   perform rm_test_pcp.check((select count(*) from public.rm_celulas_projeto where celula_id=cell_id and projeto_id=candidate_project)=1,
    format('new allocation scenario %s is preserved exactly once',scenario));
   perform rm_test_pcp.check((public.rm_web_cell_queue_snapshot_v1(cell_id)->>'total')::integer=initial_total+1,
    format('new member scenario %s participates in next snapshot',scenario));
  end if;
  if scenario in(2,6) then
   perform rm_test_pcp.check((select posicao is null and prioridade is null from public.rm_celulas_projeto
    where celula_id=cell_id and projeto_id=candidate_project),'new member after queue save keeps its own untouched defaults');
  end if;
  if scenario=3 then perform rm_test_pcp.check((public.rm_web_cell_queue_snapshot_v1(cell_id)->>'total')::integer=0,'closure removes the member without stale priority write'); end if;
  if scenario=4 then perform rm_test_pcp.check((public.rm_web_cell_queue_snapshot_v1(cell_id)->>'total')::integer=2,'reopening closed project invalidates full membership'); end if;
  if scenario=7 then perform rm_test_pcp.check((select status='retornado' and prioridade='baixa' from public.rm_celulas_projeto where id=rm_test_pcp.key('6',71)),'mobile revision wins without losing its state'); end if;
  if scenario=8 then
   perform rm_test_pcp.check((b->'result'->>'idempotent_replay')::boolean,'same UUID concurrent call replays the first committed result');
   perform rm_test_pcp.check((select count(*) from rm_private.web_mutation_receipts where client_submission_id=first_id)=1,'one receipt for concurrent replay');
  end if;
 end loop;
 perform dblink_disconnect('pcp_a'); perform dblink_disconnect('pcp_b');
exception when others then
 if 'pcp_a'=any(dblink_get_connections()) then perform dblink_disconnect('pcp_a'); end if;
 if 'pcp_b'=any(dblink_get_connections()) then perform dblink_disconnect('pcp_b'); end if; raise;
end $$;
select 'PASS: real PCP concurrency covers allocation insert and materialization both directions, closure/reopening, mobile revision and simultaneous replay' as result;

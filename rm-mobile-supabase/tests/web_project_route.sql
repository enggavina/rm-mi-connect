\set ON_ERROR_STOP on
begin;
create function pg_temp.route_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.route_key(h text,n integer) returns uuid language sql immutable as $$
 select (h||'a400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.route_actor(n int,aal text default 'aal1') returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',pg_temp.route_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.route_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.route.actor',n::text,true);
end $$;
create function pg_temp.route_payload(n int default 1) returns jsonb language sql as $$
 with s as(select public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',n)) r)
 select jsonb_build_object('projeto_id',r->'project'->>'id','expected_project_updated_at',r->'project'->>'updated_at',
  'expected_route_version',r->>'route_version','items',(select jsonb_agg(jsonb_build_object('id',i->>'id',
   'expected_updated_at',i->>'updated_at') order by ordinality) from jsonb_array_elements(r->'items') with ordinality x(i,ordinality))) from s;
$$;
create function pg_temp.route_call(rid uuid,p jsonb,cap text default 'em.planning.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.route.actor'),64,'a4'),rid,'save_project_route',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'save_project_route',p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.route_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$
declare actual text; begin
 begin perform pg_temp.route_call(gen_random_uuid(),p,cap);
 exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
 end; raise exception 'FAIL: route save succeeded (expected %)',wanted;
end $$;
do $$ declare n int; begin
 for n in 1..6 loop
  insert into auth.users(id) values(pg_temp.route_key('1',n));
  if n<>5 then insert into public.rm_users(id,auth_user_id,nome,perfil,status)
   values(pg_temp.route_key('2',n),pg_temp.route_key('1',n),'Route fixture '||n,
    case when n in(1,6) then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
    case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end); end if;
  insert into auth.sessions(id,user_id) values(pg_temp.route_key('3',n),pg_temp.route_key('1',n));
  if n not in(4,5) then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.route_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.route_key('9',n),
    pg_temp.route_key('2',n),pg_temp.route_key('1',n),true,pg_temp.route_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'a4'),pg_temp.route_key('8',n),pg_temp.route_key('3',n),
    'opaque-local-route-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select pg_temp.route_key('4',n),'Route cell '||n from generate_series(1,6) n;
insert into public.rm_projetos(id,numero,status_pcp,data_real_de_entrega)
 select pg_temp.route_key('5',n),'ROUTE-24-'||n,
  case when n=2 then 'cancelado'::public.rm_status_pcp_enum when n=6 then 'finalizando_para_faturar' else null end,
  case when n=7 then clock_timestamp() end from generate_series(1,7) n;
insert into public.rm_forms(id,titulo) values(pg_temp.route_key('b',1),'Preserved route form');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,indice,posicao,prioridade,forms_ids,
 data_inicio,data_limite,observacao,sync_source)
 select pg_temp.route_key('6',n),pg_temp.route_key('5',1),pg_temp.route_key('4',n),
  case when n=1 then 'finalizado'::public.rm_status_cel_proj_enum when n=3 then 'n_a' else 'em_dia' end,n<>4,
  case when n=1 then 1 when n in(2,3) then 3 when n=5 then -8 else null end,n*7,'alta',array[pg_temp.route_key('b',1)],
  '2026-10-20T10:00:00Z','2026-11-20T10:00:00Z','Operational note','bubble' from generate_series(1,5) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,indice)
 values(pg_temp.route_key('6',6),pg_temp.route_key('5',3),pg_temp.route_key('4',1),87),
 (pg_temp.route_key('6',7),pg_temp.route_key('5',2),pg_temp.route_key('4',1),8);
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,foto_url,selecao_relatorio)
 values(pg_temp.route_key('c',1),pg_temp.route_key('5',1),pg_temp.route_key('4',1),pg_temp.route_key('6',1),'https://example.invalid/route.jpg',true);
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,preenchido)
 values(pg_temp.route_key('d',1),pg_temp.route_key('5',1),pg_temp.route_key('4',1),pg_temp.route_key('b',1),true);
select pg_temp.route_actor(1);
set local role authenticated;
do $$ declare s jsonb; begin
 s:=public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',1));
 perform pg_temp.route_check((s->>'total')::int=5 and (s->>'complete')::boolean,'route includes completed, N/A and hidden allocations');
 perform pg_temp.route_check(s->'items'->0->>'id'=pg_temp.route_key('6',5)::text and s->'items'->4->>'id'=pg_temp.route_key('6',4)::text,
  'negative/sparse/duplicate/null legacy indices are read without normalization');
 perform pg_temp.route_check(s->'items'->2->>'id'=pg_temp.route_key('6',2)::text and s->'items'->3->>'id'=pg_temp.route_key('6',3)::text,'equal indices break ties by UUID');
 perform pg_temp.route_check(s::text !~ 'foto_url|forms_ids|arquivo|bubble_id|auth_user|sync_source|modified_by|token|email|posicao|prioridade','snapshot is minimum route DTO');
 perform pg_temp.route_check((public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',5))->>'total')::int=0,'empty project snapshot is complete');
 perform pg_temp.route_check(public.rm_web_project_route_snapshot_v1(gen_random_uuid()) is null,'missing project is null');
 perform pg_temp.route_check((public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',2))->'project'->>'closed')::boolean
  and (public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',6))->'project'->>'closed')::boolean
  and (public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',7))->'project'->>'closed')::boolean,'all existing closure conditions remain explicit');
end $$;
reset role;
do $$ declare p jsonb:=pg_temp.route_payload(); r jsonb; rid uuid:=gen_random_uuid(); before_rows jsonb; after_rows jsonb; child_photo jsonb; child_record jsonb; begin
 perform pg_temp.route_reject(p,'22023','em.projects.manage');
 perform pg_temp.route_reject(p||'{"actor_id":"2a400000-0000-4000-8000-000000000002"}','22023');
 perform pg_temp.route_reject(p-'expected_project_updated_at','22023');
 perform pg_temp.route_reject(jsonb_set(p,'{expected_project_updated_at}','"infinity"'),'22023');
 perform pg_temp.route_reject(jsonb_set(p,'{expected_project_updated_at}','"2026-10-29"'),'22023');
 perform pg_temp.route_reject(jsonb_set(p,'{expected_route_version}','"invalid"'),'22023');
 perform pg_temp.route_reject(jsonb_set(p,'{items,0,expected_updated_at}','null'),'22023');
 perform pg_temp.route_reject(jsonb_set(p,'{items,0,expected_updated_at}','"2000-01-01T00:00:00Z"'),'PT409');
 perform pg_temp.route_reject(p||jsonb_build_object('projeto_id',gen_random_uuid()),'P0002');
 perform pg_temp.route_reject(jsonb_set(p,'{items,0,indice}','1'),'22023');
 perform pg_temp.route_reject(jsonb_set(p,'{items,0,posicao}','1'),'22023');
 perform pg_temp.route_reject(p||'{"items":[]}','22023');
 perform pg_temp.route_reject(p||jsonb_build_object('items',(p->'items')-0),'PT409');
 perform pg_temp.route_reject(jsonb_set(p,'{items,0}',p->'items'->1),'22023');
 perform pg_temp.route_reject(jsonb_set(p,'{items,0,id}',to_jsonb(pg_temp.route_key('6',6))),'22023');
 perform pg_temp.route_reject(pg_temp.route_payload(2),'22023');
 select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.rm_celulas_projeto a where projeto_id=pg_temp.route_key('5',1);
 select to_jsonb(f) into child_photo from public.rm_fotos f where id=pg_temp.route_key('c',1);
 select to_jsonb(f) into child_record from public.rm_registros_formulario f where id=pg_temp.route_key('d',1);
 p:=p||jsonb_build_object('items',jsonb_build_array(p->'items'->1,p->'items'->0,p->'items'->2,p->'items'->3,p->'items'->4));
 r:=pg_temp.route_call(rid,p);
 select jsonb_agg(to_jsonb(a) order by id) into after_rows from public.rm_celulas_projeto a where projeto_id=pg_temp.route_key('5',1);
 perform pg_temp.route_check(jsonb_array_length(r->'record'->'changed_ids')=3,'only changed indices are written');
 perform pg_temp.route_check(before_rows->0=after_rows->0 and before_rows->1=after_rows->1,'already correct indices preserve complete rows including timestamps/authorship');
 perform pg_temp.route_check((select array_agg(id order by indice) from public.rm_celulas_projeto where projeto_id=pg_temp.route_key('5',1))=
  array[pg_temp.route_key('6',1),pg_temp.route_key('6',5),pg_temp.route_key('6',2),pg_temp.route_key('6',3),pg_temp.route_key('6',4)],'explicit complete permutation is persisted');
 perform pg_temp.route_check((select jsonb_agg(i-array['indice','modified_by_id','replanejada_em','replanejada_por_id','sync_source','updated_at'] order by i->>'id') from jsonb_array_elements(before_rows) i)=
  (select jsonb_agg(i-array['indice','modified_by_id','replanejada_em','replanejada_por_id','sync_source','updated_at'] order by i->>'id') from jsonb_array_elements(after_rows) i),
  'route does not alter priority/queue/status/visibility/forms/deadlines or other operational fields');
 perform pg_temp.route_check((select to_jsonb(f)=child_photo from public.rm_fotos f where id=pg_temp.route_key('c',1))
  and (select to_jsonb(f)=child_record from public.rm_registros_formulario f where id=pg_temp.route_key('d',1)),'photos and responses remain untouched');
 perform pg_temp.route_check((pg_temp.route_call(rid,p)->>'idempotent_replay')::boolean,'replay precedes stale route version checks with fresh permit');
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'save_project_route',p); raise exception 'FAIL: permitless replay'; exception when insufficient_privilege then reset role; end;
 begin perform pg_temp.route_call(rid,jsonb_set(p,'{items,0}',p->'items'->1)); raise exception 'FAIL: changed payload replay'; exception when unique_violation then null; end;
 perform pg_temp.route_actor(6); begin perform pg_temp.route_call(rid,p); raise exception 'FAIL: other actor replay'; exception when unique_violation then null; end;
 perform pg_temp.route_actor(1); insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.route_call(rid,p); raise exception 'FAIL: MFA replay'; exception when insufficient_privilege then null; end;
 perform pg_temp.route_actor(1,'aal2'); perform pg_temp.route_check((pg_temp.route_call(rid,p)->>'idempotent_replay')::boolean,'MFA rechecked on exact replay');
 delete from auth.mfa_factors where user_id=auth.uid(); perform pg_temp.route_actor(1);
 r:=pg_temp.route_call(gen_random_uuid(),pg_temp.route_payload());
 perform pg_temp.route_check(r->'record'->'changed_ids'='[]' and (select jsonb_agg(to_jsonb(a) order by id) from public.rm_celulas_projeto a where projeto_id=pg_temp.route_key('5',1))=after_rows,'no-op preserves every row and revision');
 p:=pg_temp.route_payload(); update public.rm_projetos set nome='Concurrent changed name' where id=pg_temp.route_key('5',1); perform pg_temp.route_reject(p,'PT409');
 p:=pg_temp.route_payload(); update public.rm_celulas_projeto set observacao='Concurrent operational update' where id=pg_temp.route_key('6',3); perform pg_temp.route_reject(p,'PT409');
 p:=pg_temp.route_payload(); update public.rm_celulas set nome='Changed route label' where id=pg_temp.route_key('4',1); perform pg_temp.route_reject(p,'PT409');
end $$;
select pg_temp.route_actor(2);
select pg_temp.route_check((pg_temp.route_call(gen_random_uuid(),pg_temp.route_payload())->>'operation')='save_project_route','standard profile may plan a project route');
select pg_temp.route_actor(3);
select pg_temp.route_reject(pg_temp.route_payload(),'42501');
select pg_temp.route_actor(4);
select pg_temp.route_reject(pg_temp.route_payload(),'42501');
set local role authenticated;
select pg_temp.route_check(public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',1)) is null,'inactive account cannot read a route through RLS');
reset role;
select pg_temp.route_actor(5);
select pg_temp.route_reject(pg_temp.route_payload(),'42501');
set local role authenticated;
select pg_temp.route_check(public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',1)) is null,'unbound Auth account cannot read a route through RLS');
reset role;
select pg_temp.route_actor(1);
do $$ declare p jsonb:=pg_temp.route_payload(); rid uuid:=gen_random_uuid(); begin
 perform public.rm_sso_action_permit_v1(lpad('1',64,'a4'),rid,'save_project_route',p,'em.planning.manage');
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',gen_random_uuid(),'aal','aal1')::text,true);
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'save_project_route',p);
  raise exception 'FAIL: route Auth session mismatch'; exception when insufficient_privilege then reset role; end;
 perform pg_temp.route_actor(1);
 update rm_private.sso_action_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=rid;
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'save_project_route',p);
  raise exception 'FAIL: route expired permit'; exception when insufficient_privilege then reset role; end;
 update rm_private.sso_sessions set expires_at=clock_timestamp()-interval '1 second' where hash=lpad('1',64,'a4');
 perform pg_temp.route_reject(p,'42501');
 update rm_private.sso_sessions set expires_at=clock_timestamp()+interval '45 minutes' where hash=lpad('1',64,'a4');
 update rm_private.sso_identity_bindings set enabled=false where id=pg_temp.route_key('8',1);
 perform pg_temp.route_reject(p,'42501');
 update rm_private.sso_identity_bindings set enabled=true where id=pg_temp.route_key('8',1);
end $$;
-- A real overflow never returns an editable partial route.
insert into public.rm_celulas(id,nome) select pg_temp.route_key('4',n),'Route overflow '||n from generate_series(10001,12001) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,indice)
 select pg_temp.route_key('6',n),pg_temp.route_key('5',4),pg_temp.route_key('4',n),n-10000 from generate_series(10001,12001) n;
do $$ declare s jsonb; p jsonb; begin
 s:=public.rm_web_project_route_snapshot_v1(pg_temp.route_key('5',4));
 perform pg_temp.route_check(not (s->>'complete')::boolean and (s->>'total')::int=2001 and s->'items'='[]','overflow DTO is explicit and contains no partial editable route');
 select jsonb_build_object('projeto_id',pg_temp.route_key('5',4),'expected_project_updated_at',s->'project'->>'updated_at',
  'expected_route_version',s->>'route_version','items',jsonb_agg(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at) order by a.id))
  into p from(select * from public.rm_celulas_projeto where projeto_id=pg_temp.route_key('5',4) order by id limit 2000) a;
 perform pg_temp.route_reject(p,'PT409');
 perform pg_temp.route_check((select count(*)=2001 and min(indice)=1 and max(indice)=2001 from public.rm_celulas_projeto where projeto_id=pg_temp.route_key('5',4)),'overflow preserves every original member and index');
end $$;
select pg_temp.route_check(not has_function_privilege('anon','public.rm_web_project_route_snapshot_v1(uuid)','execute')
 and not has_function_privilege('service_role','public.rm_web_project_route_snapshot_v1(uuid)','execute')
 and not has_function_privilege('authenticated','rm_private.web_mutate_photo_title_core_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute'),'read and private dispatcher privileges stay scoped');
select pg_temp.route_check(not prosecdef and provolatile='s','snapshot is stable invoker') from pg_proc where oid='public.rm_web_project_route_snapshot_v1(uuid)'::regprocedure;
rollback;
select 'PASS: project route snapshot, strict full permutation, sparse/null indices, unrelated fields, no-op, closed scope, SSO/MFA/replay and overflow' as result;

begin;
create extension if not exists dblink with schema public;
create schema rm_test_route;
create function rm_test_route.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function rm_test_route.key(h text,n int) returns uuid language sql immutable as $$
 select (h||'a500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
insert into auth.users(id) values(rm_test_route.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_route.key('2',1),rm_test_route.key('1',1),'Route concurrent planner','administrador');
insert into auth.sessions(id,user_id) values(rm_test_route.key('3',1),rm_test_route.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_route.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_route.key('9',1),
  rm_test_route.key('2',1),rm_test_route.key('1',1),true,rm_test_route.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('a5',32),rm_test_route.key('8',1),rm_test_route.key('3',1),'opaque-local-route-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('route-local-mobile-fixture','sha256'),rm_test_route.key('1',1),rm_test_route.key('2',1),rm_test_route.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_tipos_equipamento(id,nome) select rm_test_route.key('b',n),'Route type '||n from generate_series(1,14) n;
insert into public.rm_celulas(id,nome) select rm_test_route.key('4',n*10+k),'Route race cell '||n||'-'||k from generate_series(1,14) n cross join generate_series(1,3) k;
insert into public.rm_projetos(id,numero,tipo_equipamento_id)
 select rm_test_route.key('5',n),'ROUTE-RACE-24-'||n,rm_test_route.key('b',n) from generate_series(1,14) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,indice,posicao,prioridade)
 select rm_test_route.key('6',n*10+k),rm_test_route.key('5',n),rm_test_route.key('4',n*10+k),'em_dia',k=1,
  case when k=1 then 9 end,k*7,'baixa' from generate_series(1,14) n cross join generate_series(1,2) k;
insert into public.rm_celula_tipos_equipamento(celula_id,tipo_equipamento_id,visibilidade)
 select rm_test_route.key('4',n*10+3),rm_test_route.key('b',n),true from generate_series(1,14) n;
create function rm_test_route.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare result jsonb; state text; capability text; operation text; begin
 perform set_config('request.jwt.claim.sub',rm_test_route.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_route.key('3',1),'aal','aal1')::text,true);
 if mode in('route','queue','plan','project') then
  operation:=case mode when 'route' then 'save_project_route' when 'queue' then 'save_cell_queue' when 'plan' then 'plan_cell' else 'save_project' end;
  capability:=case when mode='project' then 'em.projects.manage' else 'em.planning.manage' end;
  perform public.rm_sso_action_permit_v1(repeat('a5',32),rid,operation,p,capability);
  set local role authenticated; result:=public.rm_web_mutate_v1(rid,operation,p); reset role;
 elsif mode='mobile' then
  set local role authenticated; result:=public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',p,'route-local-mobile-fixture'); reset role;
 elsif mode='materialize' then
  set local role service_role; result:=public.rm_materialize_project_cells_v1((p->>'id')::uuid); reset role;
 elsif mode='insert' then
  insert into public.rm_celulas_projeto(projeto_id,celula_id,observacao) values((p->>'projeto_id')::uuid,(p->>'celula_id')::uuid,'raw FK writer');
 else raise exception 'Unknown local route mode'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',result);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate;
 return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end $$;
commit;
do $$ declare scenario int; project_id uuid; cell_id uuid; s jsonb; route_payload jsonb; other_payload jsonb;
 first_payload jsonb; second_payload jsonb; first_mode text; second_mode text; first_id uuid; second_id uuid;
 a jsonb; b jsonb; pid_a int; pid_b int; waited int; begin
 perform dblink_connect('route_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('route_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('route_a','select pg_backend_pid()') as t(pid integer);
 select pid into pid_b from dblink('route_b','select pg_backend_pid()') as t(pid integer);
 for scenario in 1..14 loop
  project_id:=rm_test_route.key('5',scenario); cell_id:=rm_test_route.key('4',scenario*10+1);
  s:=public.rm_web_project_route_snapshot_v1(project_id);
  select jsonb_build_object('projeto_id',project_id,'expected_project_updated_at',s->'project'->>'updated_at',
   'expected_route_version',s->>'route_version','items',jsonb_agg(jsonb_build_object('id',i->>'id','expected_updated_at',i->>'updated_at') order by ordinality desc))
   into route_payload from jsonb_array_elements(s->'items') with ordinality x(i,ordinality);
  first_mode:='route'; second_mode:='route'; other_payload:=route_payload;
  if scenario in(3,4) then
   other_payload:=jsonb_build_object('p_celula_projeto_id',rm_test_route.key('6',scenario*10+1),'p_status','retornado');
   first_mode:=case when scenario=3 then 'mobile' else 'route' end; second_mode:=case when scenario=3 then 'route' else 'mobile' end;
  elsif scenario in(5,6,13,14) then
   other_payload:=jsonb_build_object('projeto_id',project_id,'celula_id',rm_test_route.key('4',scenario*10+3),'expected_updated_at',null,'changes',jsonb_build_object('observacao','New route cell'));
   first_mode:=case when scenario=5 then 'plan' when scenario=13 then 'insert' else 'route' end;
   second_mode:=case when scenario=6 then 'plan' when scenario=14 then 'insert' else 'route' end;
  elsif scenario in(7,8) then
   s:=public.rm_web_cell_queue_snapshot_v1(cell_id);
   other_payload:=jsonb_build_object('celula_id',cell_id,'expected_queue_version',s->>'queue_version','apply_order',true,
    'items',jsonb_build_array(jsonb_build_object('id',s->'items'->0->>'id','expected_updated_at',s->'items'->0->>'updated_at','prioridade','alta')));
   first_mode:=case when scenario=7 then 'queue' else 'route' end; second_mode:=case when scenario=7 then 'route' else 'queue' end;
  elsif scenario in(9,10) then
   other_payload:=jsonb_build_object('id',project_id); first_mode:=case when scenario=9 then 'materialize' else 'route' end;
   second_mode:=case when scenario=9 then 'route' else 'materialize' end;
  elsif scenario in(11,12) then
   other_payload:=jsonb_build_object('id',project_id,'expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('status_pcp','cancelado'));
   first_mode:=case when scenario=11 then 'project' else 'route' end; second_mode:=case when scenario=11 then 'route' else 'project' end;
  end if;
  first_payload:=case when first_mode='route' then route_payload else other_payload end;
  second_payload:=case when second_mode='route' then route_payload else other_payload end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=2 then first_id else gen_random_uuid() end;
  perform dblink_send_query('route_a',format('select rm_test_route.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,first_payload::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first route scenario % did not hold: %',scenario,first_mode; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('route_b',format('select rm_test_route.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>150 then raise exception 'FAIL: second route scenario % did not contend: %',scenario,second_mode; end if; perform pg_sleep(0.005);
  end loop;
  select r into a from dblink_get_result('route_a') as t(r jsonb); perform r from dblink_get_result('route_a') as t(r jsonb);
  select r into b from dblink_get_result('route_b') as t(r jsonb); perform r from dblink_get_result('route_b') as t(r jsonb);
  perform rm_test_route.check(a->>'sqlstate'='00000',format('first route scenario %s succeeds: %s',scenario,a));
  perform rm_test_route.check(b->>'sqlstate'=case when scenario in(1,3,5,7,8,9,11,13) then 'PT409' else '00000' end,
   format('second route scenario %s detects stale state or serializes: %s',scenario,b));
  if scenario=2 then perform rm_test_route.check((b->'result'->>'idempotent_replay')::boolean and (select count(*)=1 from rm_private.web_mutation_receipts where client_submission_id=first_id),'same UUID has one receipt and replays'); end if;
  if scenario in(3,4) then perform rm_test_route.check((select status='retornado' from public.rm_celulas_projeto where id=rm_test_route.key('6',scenario*10+1)),'mobile execution survives route ordering'); end if;
  if scenario in(5,6,9,10,13,14) then
   perform rm_test_route.check((select count(*)=3 from public.rm_celulas_projeto where projeto_id=project_id),'new allocation is preserved exactly once');
   if scenario in(6,10,14) then perform rm_test_route.check((select indice is null from public.rm_celulas_projeto where projeto_id=project_id and celula_id=rm_test_route.key('4',scenario*10+3)),'allocation after save keeps its own route default'); end if;
  end if;
  if scenario=7 then perform rm_test_route.check((select posicao=1 and prioridade='alta' and indice=9 from public.rm_celulas_projeto where id=rm_test_route.key('6',71)),'queue writer wins without route changing position/priority'); end if;
  if scenario=8 then perform rm_test_route.check((select posicao=7 and prioridade='baixa' and indice=2 from public.rm_celulas_projeto where id=rm_test_route.key('6',81)),'route writer preserves queue fields and stale queue is rejected'); end if;
  if scenario in(11,12) then perform rm_test_route.check((select status_pcp='cancelado' from public.rm_projetos where id=project_id),'project closure remains intact'); end if;
 end loop;
 perform dblink_disconnect('route_a'); perform dblink_disconnect('route_b');
exception when others then
 if 'route_a'=any(dblink_get_connections()) then perform dblink_disconnect('route_a'); end if;
 if 'route_b'=any(dblink_get_connections()) then perform dblink_disconnect('route_b'); end if; raise;
end $$;
select 'PASS: 14 real route races cover same UUID, mobile/queue/planning/materialization both directions, project closure and raw FK insertions' as result;

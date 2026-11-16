\set ON_ERROR_STOP on
begin;
create function pg_temp.gc_key(h text,n int) returns uuid language sql immutable as $$select(h||'a490000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.gc_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.gc_actor(n int,aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.gc_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.gc_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.calendar.actor',n::text,true);
end$$;
create function pg_temp.gc_settings(n int default 1,cal jsonb default '{"weekdays":[1,2,3,4,5],"exceptions":[]}',marks jsonb default '[]') returns jsonb language sql as $$
 select jsonb_build_object('projeto_id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id),'calendar',cal,'milestones',marks,'reason','Configurar calendario do projeto') from public.rm_projetos p where p.id=pg_temp.gc_key('5',n);
$$;
create function pg_temp.gc_plan(n int default 1,changes jsonb default '{"data_limite":"2026-11-13"}') returns jsonb language sql as $$
 select jsonb_build_object('reason','Ajustar prazo no calendario','projects',jsonb_build_array(jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id))),
 'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',changes))) from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id where a.id=pg_temp.gc_key('6',n);
$$;
create function pg_temp.gc_call(rid uuid,p jsonb,op text default 'save_gantt_settings',cap text default 'em.planning.manage') returns jsonb language plpgsql as $$declare r jsonb;begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.calendar.actor'),64,'a49'),rid,op,p,cap);
 set local role authenticated;r:=public.rm_web_mutate_v1(rid,op,p);reset role;return r;
 exception when others then reset role;raise;
end$$;
create function pg_temp.gc_reject(p jsonb,wanted text,op text default 'save_gantt_settings',cap text default 'em.planning.manage') returns void language plpgsql as $$declare actual text;begin
 begin perform pg_temp.gc_call(gen_random_uuid(),p,op,cap);exception when others then get stacked diagnostics actual=returned_sqlstate;
 if actual=wanted then return;end if;raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: invalid calendar command succeeded, wanted %',wanted;
end$$;
do $$declare n int;begin
 for n in 1..4 loop
  insert into auth.users(id) values(pg_temp.gc_key('1',n));
  insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.gc_key('2',n),pg_temp.gc_key('1',n),'Calendar fixture '||n,case when n=3 then 'auditor'::public.rm_perfil_usuario_enum when n=2 then 'padr_o' else 'administrador' end,case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
  insert into auth.sessions(id,user_id) values(pg_temp.gc_key('3',n),pg_temp.gc_key('1',n));
  if n<>4 then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values(pg_temp.gc_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.gc_key('9',n),pg_temp.gc_key('2',n),pg_temp.gc_key('1',n),true,pg_temp.gc_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'a49'),pg_temp.gc_key('8',n),pg_temp.gc_key('3',n),'opaque-calendar-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end$$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select pg_temp.gc_key('4',n),'Calendar cell '||n from generate_series(1,3)n;
insert into public.rm_projetos(id,numero,status_pcp) select pg_temp.gc_key('5',n),'CALENDAR49-'||n,case when n=3 then 'cancelado'::public.rm_status_pcp_enum else null end from generate_series(1,3)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite,observacao)
 values(pg_temp.gc_key('6',1),pg_temp.gc_key('5',1),pg_temp.gc_key('4',1),'em_dia',true,'2026-11-09T08:12:34.123456Z','2026-11-13T15:00:00Z','Preserve timestamp'),
 (pg_temp.gc_key('6',2),pg_temp.gc_key('5',1),pg_temp.gc_key('4',2),'em_dia',true,'2026-11-14T15:00:00Z','2026-11-17T15:00:00Z','Existing Saturday'),
 (pg_temp.gc_key('6',3),pg_temp.gc_key('5',2),pg_temp.gc_key('4',3),'em_dia',true,'2026-11-09T15:00:00Z','2026-11-10T15:00:00Z','Other project');
select pg_temp.gc_actor(1);

do $$declare p jsonb;r jsonb;rid uuid;ver text;before_rows jsonb;before_count int;marks jsonb;old_plan jsonb;old_id uuid;begin
 -- A default/no-op save neither materializes settings nor invalidates old drafts.
 ver:=rm_private.web_gantt_project_version_v1(pg_temp.gc_key('5',1));
 perform pg_temp.gc_check(ver=rm_private.web_gantt_project_version_before_calendar_v1(pg_temp.gc_key('5',1)),'absence retains the exact previous hash');
 p:=pg_temp.gc_settings(1,'{"weekdays":[7,6,5,4,3,2,1],"exceptions":[]}');r:=pg_temp.gc_call(gen_random_uuid(),p);
 perform pg_temp.gc_check(r->'record'->>'settings_changed'='false' and not exists(select 1 from rm_private.gantt_project_settings where projeto_id=pg_temp.gc_key('5',1)) and ver=rm_private.web_gantt_project_version_v1(pg_temp.gc_key('5',1)),'default no-op preserves plan version');
 old_plan:=pg_temp.gc_plan(1,'{"data_limite":"2026-11-14"}');old_id:=gen_random_uuid();perform pg_temp.gc_call(old_id,old_plan,'save_gantt_plan');
 select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.rm_celulas_projeto a;
 marks:=jsonb_build_array(jsonb_build_object('id',pg_temp.gc_key('7',2),'label','  Entrega  ','date','2026-11-30'),jsonb_build_object('id',pg_temp.gc_key('7',1),'label','Inspecao','date','2026-11-20'));
 p:=pg_temp.gc_settings(1,'{"weekdays":[5,3,1,4,2],"exceptions":[{"date":"2026-11-16","working":false,"label":"  Parada  "}]}',marks);rid:=gen_random_uuid();r:=pg_temp.gc_call(rid,p);
 perform pg_temp.gc_check(r->'record'->>'settings_changed'='true' and (select calendar->'weekdays'='[1,2,3,4,5]' and calendar->'exceptions'->0->>'label'='Parada' and milestones->0->>'label'='Inspecao' from rm_private.gantt_project_settings where projeto_id=pg_temp.gc_key('5',1)),'canonical settings and sorted milestones persist');
 perform pg_temp.gc_check((select jsonb_agg(to_jsonb(a) order by id)=before_rows from public.rm_celulas_projeto a),'settings never replan or rewrite legacy off-days');
 perform pg_temp.gc_check(ver<>rm_private.web_gantt_project_version_v1(pg_temp.gc_key('5',1)),'settings affect project version');
 ver:=rm_private.web_gantt_project_version_v1(pg_temp.gc_key('5',1));
 r:=pg_temp.gc_call(gen_random_uuid(),pg_temp.gc_settings(1,p->'calendar',marks));
 perform pg_temp.gc_check(r->'record'->>'settings_changed'='false' and ver=rm_private.web_gantt_project_version_v1(pg_temp.gc_key('5',1)),'canonical existing-settings no-op preserves revision');
 perform pg_temp.gc_check((pg_temp.gc_call(rid,p)->>'idempotent_replay')::boolean,'settings exact replay');
 perform pg_temp.gc_check((pg_temp.gc_call(old_id,old_plan,'save_gantt_plan')->>'idempotent_replay')::boolean,'old planning replay is preserved after calendar change');
 begin perform pg_temp.gc_call(rid,p||'{"reason":"Changed reason"}');raise exception 'FAIL reused submission';exception when unique_violation then null;end;
 begin set local role authenticated;perform public.rm_web_mutate_v1(rid,'save_gantt_settings',p);raise exception 'FAIL missing permit';exception when insufficient_privilege then reset role;end;
 insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.gc_call(rid,p);raise exception 'FAIL replay missing MFA';exception when insufficient_privilege then null;end;
 perform pg_temp.gc_actor(1,'aal2');perform pg_temp.gc_check((pg_temp.gc_call(rid,p)->>'idempotent_replay')::boolean,'MFA checked before replay');delete from auth.mfa_factors where user_id=auth.uid();perform pg_temp.gc_actor(1);
 p:=pg_temp.gc_settings();ver:=rm_private.web_gantt_project_version_v1(pg_temp.gc_key('5',1));update public.rm_celulas_projeto set observacao='Mobile change' where id=pg_temp.gc_key('6',2);perform pg_temp.gc_reject(p,'PT409');
 p:=pg_temp.gc_settings();perform pg_temp.gc_reject(jsonb_set(p,'{expected_updated_at}','"2020-01-01T00:00:00Z"'),'PT409');
 perform pg_temp.gc_reject(pg_temp.gc_settings(3),'22023');
 -- Strict types, uniqueness, ISO dates and bounded arrays.
 perform pg_temp.gc_reject(p,'22023','save_gantt_settings','em.projects.manage');
 perform pg_temp.gc_reject(p||'{"actor_id":"bad"}','22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,weekdays}','[1,1]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,weekdays}','["1"]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,weekdays}','[]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,weekdays}','[0,8]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,weekdays}','[1.5]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}','[{"date":"2026-02-30","working":false,"label":"x"}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}','[{"date":"1899-12-31","working":false,"label":"x"}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}','[{"date":"2201-01-01","working":false,"label":"x"}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}','[{"date":"2026-11-15","working":"false","label":"x"}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}','[{"date":"2026-11-15","working":false,"label":" "}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}','[{"date":"2026-11-15","working":false,"label":"x"},{"date":"2026-11-15","working":true,"label":"y"}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{milestones}',marks||marks),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{milestones}','[{"id":"bad","label":"x","date":"2026-11-15"}]'),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{milestones}',jsonb_build_array(jsonb_build_object('id',pg_temp.gc_key('7',1),'label',repeat('x',121),'date','2026-11-15'))),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{calendar,exceptions}',(select jsonb_agg(jsonb_build_object('date',to_char('2024-01-01'::date+n,'YYYY-MM-DD'),'working',false,'label','x')) from generate_series(0,366)n)),'22023');
 perform pg_temp.gc_reject(jsonb_set(p,'{milestones}',(select jsonb_agg(jsonb_build_object('id',pg_temp.gc_key('7',n),'date','2026-11-15','label','x')) from generate_series(1,101)n)),'22023');
 perform pg_temp.gc_reject(p||jsonb_build_object('reason',repeat('x',2097152)),'PT413');
 -- Off-day checks are atomic and affect changed date fields only.
 p:=pg_temp.gc_plan(1,'{"data_limite":"2026-11-15"}');select count(*) into before_count from rm_private.web_mutation_receipts;select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.rm_celulas_projeto a;
 perform pg_temp.gc_reject(p,'PT409','save_gantt_plan');
 perform pg_temp.gc_check(before_count=(select count(*) from rm_private.web_mutation_receipts) and(select jsonb_agg(to_jsonb(a) order by id)=before_rows from public.rm_celulas_projeto a),'postvalidation rolls back child and parent receipts and dates');
 r:=pg_temp.gc_call(gen_random_uuid(),pg_temp.gc_plan(1,'{"data_limite":"2026-11-14"}'),'save_gantt_plan');perform pg_temp.gc_check(r->'record'->'changed_ids'='[]','same legacy off-day value is a no-op');
 r:=pg_temp.gc_call(gen_random_uuid(),pg_temp.gc_plan(2,'{"data_limite":"2026-11-18"}'),'save_gantt_plan');perform pg_temp.gc_check(r->'record'->'changed_ids'=jsonb_build_array(pg_temp.gc_key('6',2)),'untouched legacy off-day start does not block another field');
 p:=pg_temp.gc_plan(1,'{"data_limite":"2026-11-13"}');perform pg_temp.gc_call(gen_random_uuid(),p,'save_gantt_plan');
 -- Calendar exceptions override weekdays. Lag counts working days after the first successor day.
 perform pg_temp.gc_check(rm_private.gantt_successor_day_v1('2026-11-13',0,'{"weekdays":[1,2,3,4,5],"exceptions":[{"date":"2026-11-16","working":false,"label":"Stop"}]}')='2026-11-17','FS skips weekend and holiday');
 perform pg_temp.gc_check(rm_private.gantt_successor_day_v1('2026-11-13',1,'{"weekdays":[1,2,3,4,5],"exceptions":[{"date":"2026-11-16","working":false,"label":"Stop"}]}')='2026-11-18','FS working lag');
 p:=pg_temp.gc_plan(2,'{"data_inicio":"2026-11-16"}');perform pg_temp.gc_reject(p,'PT409','save_gantt_plan');
 p:=pg_temp.gc_plan(2,'{"data_inicio":"2026-11-17"}');p:=p||jsonb_build_object('dependencies',jsonb_build_object('projeto_id',pg_temp.gc_key('5',1),'links',jsonb_build_array(jsonb_build_object('predecessor_id',pg_temp.gc_key('6',1),'successor_id',pg_temp.gc_key('6',2),'lag_days',1))));
 perform pg_temp.gc_reject(p,'PT409','save_gantt_plan');
 p:=jsonb_set(p,'{items,0,changes,data_inicio}','"2026-11-18"');perform pg_temp.gc_call(gen_random_uuid(),p,'save_gantt_plan');
 p:=pg_temp.gc_settings(1,'{"weekdays":[1,2,3,4,5],"exceptions":[{"date":"2026-11-14","working":true,"label":"Extra"},{"date":"2028-02-29","working":false,"label":"Leap"}]}',marks);perform pg_temp.gc_call(gen_random_uuid(),p);
 perform pg_temp.gc_call(gen_random_uuid(),pg_temp.gc_plan(1,'{"data_limite":"2026-11-14"}'),'save_gantt_plan');
 -- Settings may expose a conflict but never silently move the schedule.
 p:=pg_temp.gc_settings(1,'{"weekdays":[1],"exceptions":[]}',marks);perform pg_temp.gc_call(gen_random_uuid(),p);
 p:=pg_temp.gc_plan();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('baseline',jsonb_build_object('projeto_id',pg_temp.gc_key('5',1),'label','Date-only reference'));r:=pg_temp.gc_call(gen_random_uuid(),p,'save_gantt_plan');
 perform pg_temp.gc_check(r->'record'->>'baseline_id' is not null,'baseline retains historical dates despite new calendar conflicts');
 perform pg_temp.gc_check(exists(select 1 from rm_private.project_delete_scope_v1(pg_temp.gc_key('5',1)) where table_name='gantt_project_settings' and cardinality(ids)=1),'settings participate in deletion closure');
end$$;

set local role authenticated;
do $$declare s jsonb;begin
 s:=public.rm_web_gantt_snapshot_v1(jsonb_build_object('project_id',pg_temp.gc_key('5',1),'cell_id',null,'include_closed',true));
 perform pg_temp.gc_check(jsonb_array_length(s->'settings')=1 and s->'settings'->0->>'projeto_id'=pg_temp.gc_key('5',1)::text,'snapshot includes only relevant settings');
 perform pg_temp.gc_check((s->'settings'->0)-array['projeto_id','calendar','milestones','updated_at']='{}','snapshot settings excludes owner/internal IDs');
 begin perform rm_private.gantt_successor_day_v1('2026-11-13',0,'{}');raise exception 'FAIL helper execute';exception when insufficient_privilege then null;end;
 begin update rm_private.gantt_project_settings set milestones='[]';raise exception 'FAIL direct settings write';exception when insufficient_privilege then null;end;
end$$;
reset role;
select pg_temp.gc_actor(2);select pg_temp.gc_call(gen_random_uuid(),pg_temp.gc_settings(2));
select pg_temp.gc_actor(3);select pg_temp.gc_reject(pg_temp.gc_settings(),'42501');
set local role authenticated;
select pg_temp.gc_check((select count(*)=2 from rm_private.gantt_project_settings where projeto_id in(pg_temp.gc_key('5',1),pg_temp.gc_key('5',2))),'auditor reads allowed calendars');
reset role;
select pg_temp.gc_actor(1);
do $$declare context jsonb;p jsonb;r jsonb;rid uuid:=gen_random_uuid();begin
 context:=public.rm_web_project_delete_snapshot_v1(pg_temp.gc_key('5',2));
 p:=jsonb_build_object('id',pg_temp.gc_key('5',2),'expected_updated_at',context->'project'->>'updated_at','expected_context_version',context->>'context_version','confirm_delete',true,'justificativa','Delete isolated calendar fixture');
 perform pg_temp.gc_call(gen_random_uuid(),pg_temp.gc_settings(2,'{"weekdays":[1,2,3,4],"exceptions":[]}'));
 perform pg_temp.gc_reject(p,'PT409','delete_project','em.projects.manage');
 context:=public.rm_web_project_delete_snapshot_v1(pg_temp.gc_key('5',2));p:=jsonb_set(p,'{expected_context_version}',context->'context_version');
 r:=pg_temp.gc_call(rid,p,'delete_project','em.projects.manage');
 perform pg_temp.gc_check(r->'record'->>'deleted'='true' and not exists(select 1 from rm_private.gantt_project_settings where projeto_id=pg_temp.gc_key('5',2)),'confirmed project deletion removes private settings in leaf order');
 perform pg_temp.gc_check((pg_temp.gc_call(rid,p,'delete_project','em.projects.manage')->>'idempotent_replay')::boolean,'settings deletion preserves exact protocol replay');
end$$;
-- Even a selected project with settings returns no partial calendar/graph when
-- its route crosses the complete-read bound.
insert into public.rm_celulas(id,nome) select pg_temp.gc_key('4',n),'Calendar bound '||n from generate_series(10010,12010)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) select pg_temp.gc_key('6',n),pg_temp.gc_key('5',1),pg_temp.gc_key('4',n),'em_dia' from generate_series(10010,12010)n;
set local role authenticated;
do $$declare s jsonb;begin
 s:=public.rm_web_gantt_snapshot_v1(jsonb_build_object('project_id',pg_temp.gc_key('5',1),'cell_id',null,'include_closed',true));
 perform pg_temp.gc_check(s->>'complete'='false' and s->'settings'='[]' and s->'projects'='[]' and s->'items'='[]','overflow contains no partial settings or project rows');
end$$;
reset role;
select pg_temp.gc_actor(4);
set local role authenticated;
select pg_temp.gc_check(not exists(select 1 from rm_private.gantt_project_settings),'inactive reader receives no private settings');
reset role;
rollback;
select 'PASS: Gantt calendars validate SSO, roles, MFA, retries, strict data, legacy preservation, atomic working-day/FS enforcement and private snapshot' result;

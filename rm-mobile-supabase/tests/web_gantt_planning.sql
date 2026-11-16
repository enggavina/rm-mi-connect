\set ON_ERROR_STOP on
begin;
create function pg_temp.gt_key(h text,n integer) returns uuid language sql immutable as $$select(h||'a470000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.gt_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.gt_actor(n int,aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.gt_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.gt_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.gantt.actor',n::text,true);
end$$;
create function pg_temp.gt_snapshot(n int default 1) returns jsonb language sql as $$
 select public.rm_web_gantt_snapshot_v1(jsonb_build_object('project_id',pg_temp.gt_key('5',n),'cell_id',null,'include_closed',true));
$$;
create function pg_temp.gt_payload(n int default 1,changes jsonb default '{"data_limite":"2026-11-11"}') returns jsonb language sql as $$
 with a as(select * from public.rm_celulas_projeto where id=pg_temp.gt_key('6',n)),p as(select x.* from public.rm_projetos x join a on a.projeto_id=x.id)
 select jsonb_build_object('reason','Ajustar prazo do Gantt','projects',jsonb_build_array(jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id))),
  'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',changes))) from a,p;
$$;
create function pg_temp.gt_call(rid uuid,p jsonb,cap text default 'em.planning.manage',op text default 'save_gantt_plan') returns jsonb language plpgsql as $$
declare r jsonb;begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.gantt.actor'),64,'a47'),rid,op,p,cap);
 set local role authenticated;r:=public.rm_web_mutate_v1(rid,op,p);reset role;return r;
exception when others then reset role;raise;end$$;
create function pg_temp.gt_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$
declare actual text;begin
 begin perform pg_temp.gt_call(gen_random_uuid(),p,cap);exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return;end if;raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: invalid Gantt command succeeded, wanted %',wanted;
end$$;
create function pg_temp.gt_retire(ident uuid,retired boolean) returns void language plpgsql as $$
declare a public.rm_celulas_projeto%rowtype;begin
 select * into a from public.rm_celulas_projeto where id=ident;
 insert into rm_private.cell_availability_events(projeto_id,celula_projeto_id,actor_id,action,old_visibility,new_visibility,old_retired,new_retired,allocation_version,client_submission_id)
 values(a.projeto_id,a.id,pg_temp.gt_key('2',1),case when retired then 'retire' else 'restore' end,a.visibilidade,false,a.retirada,retired,a.updated_at,gen_random_uuid());
 update public.rm_celulas_projeto set retirada=retired,visibilidade=false where id=ident;
end$$;
do $$declare n int;begin
 for n in 1..6 loop
  insert into auth.users(id) values(pg_temp.gt_key('1',n));
  if n<>5 then insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.gt_key('2',n),pg_temp.gt_key('1',n),'Gantt fixture '||n,
   case when n in(1,6) then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
   case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);end if;
  insert into auth.sessions(id,user_id) values(pg_temp.gt_key('3',n),pg_temp.gt_key('1',n));
  if n not in(4,5) then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
    values(pg_temp.gt_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.gt_key('9',n),pg_temp.gt_key('2',n),pg_temp.gt_key('1',n),true,pg_temp.gt_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'a47'),pg_temp.gt_key('8',n),pg_temp.gt_key('3',n),'opaque-gantt-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end$$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select pg_temp.gt_key('4',n),'Gantt cell '||n from generate_series(1,4) n;
insert into public.rm_projetos(id,numero,status_pcp) select pg_temp.gt_key('5',n),'GANTT-47-'||n,case when n=3 then 'cancelado'::public.rm_status_pcp_enum else null end from generate_series(1,4) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,indice,posicao,prioridade,data_inicio,data_limite,observacao)
 select pg_temp.gt_key('6',n),pg_temp.gt_key('5',1),pg_temp.gt_key('4',n),case when n=4 then 'finalizado'::public.rm_status_cel_proj_enum else 'em_dia' end,n<>3,n,n*7,'alta',
  case when n=3 then null when n=2 then '2026-11-12T15:00:00Z'::timestamptz else '2026-11-10T08:12:34.123456Z'::timestamptz end,
  case when n=3 then null when n=2 then '2026-11-13T15:00:00Z'::timestamptz else '2026-11-11T15:00:00Z'::timestamptz end,'Preserved note' from generate_series(1,4) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) values(pg_temp.gt_key('6',5),pg_temp.gt_key('5',2),pg_temp.gt_key('4',1),'em_dia'),(pg_temp.gt_key('6',6),pg_temp.gt_key('5',3),pg_temp.gt_key('4',2),'em_dia');
select pg_temp.gt_actor(1);
set local role authenticated;
do $$declare s jsonb;begin
 s:=pg_temp.gt_snapshot();perform pg_temp.gt_check((s->>'total')::int=4 and(s->>'complete')::boolean,'project returns its whole route including finished and hidden');
 perform pg_temp.gt_check(s->'items'->3->>'can_edit'='false','finished allocation is read only');
 perform pg_temp.gt_check(s::text !~ 'foto_url|forms_ids|arquivo|bubble_id|auth_user|sync_source|email|token','minimal projection excludes sensitive unrelated fields');
 s:=public.rm_web_gantt_snapshot_v1('{"project_id":null,"cell_id":null,"include_closed":false}');perform pg_temp.gt_check((s->>'complete')::boolean and(select count(*)=4 from jsonb_array_elements(s->'items') x where x->>'projeto_id' in(pg_temp.gt_key('5',1)::text,pg_temp.gt_key('5',2)::text,pg_temp.gt_key('5',3)::text)) and not exists(select 1 from jsonb_array_elements(s->'items') x where x->>'id' in(pg_temp.gt_key('6',4)::text,pg_temp.gt_key('6',6)::text)),'general open population excludes finished and closed project');
 s:=public.rm_web_gantt_snapshot_v1(jsonb_build_object('project_id',null,'cell_id',pg_temp.gt_key('4',1),'include_closed',false));perform pg_temp.gt_check((s->>'total')::int=2 and jsonb_array_length(s->'cells')=1,'cell returns every matching open project');
 s:=pg_temp.gt_snapshot(4);perform pg_temp.gt_check((s->>'total')::int=0 and jsonb_array_length(s->'projects')=1,'empty selected project retains context');
 begin perform public.rm_web_gantt_snapshot_v1(jsonb_build_object('project_id',pg_temp.gt_key('5',1),'cell_id',null,'include_closed',false));raise exception 'FAIL project partial';exception when invalid_parameter_value then null;end;
 begin perform public.rm_web_gantt_snapshot_v1('{"project_id":null,"cell_id":null,"include_closed":false,"sql":"select secret"}');raise exception 'FAIL filters';exception when invalid_parameter_value then null;end;
end$$;
reset role;

do $$declare p jsonb;r jsonb;rid uuid:=gen_random_uuid();before_rows jsonb;after_rows jsonb;before_count int;link jsonb;old_version text;baseline_id uuid;baseline_items jsonb;base_payload jsonb;base_rid uuid;other jsonb;begin
 p:=pg_temp.gt_payload(1,'{"data_limite":"2026-11-14"}');
 perform pg_temp.gt_reject(p,'22023','em.projects.manage');
 perform pg_temp.gt_reject(p||'{"actor_id":"bad"}','22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{reason}','" "'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{projects,0,expected_updated_at}','"infinity"'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{projects,0,expected_plan_version}','"bad"'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{items,0,expected_updated_at}','"2020-01-01T00:00:00Z"'),'PT409');
 perform pg_temp.gt_reject(jsonb_set(p,'{items,0,changes}','{"status":"finalizado"}'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{items,0,changes}','{"data_inicio":"2026-02-30"}'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{items,0,changes}','{"data_inicio":"2026-11-10T15:00:00Z"}'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{items,0,changes}','{"data_inicio":"1900-01-01","data_limite":"2201-01-01"}'),'22023');
 perform pg_temp.gt_reject(p||jsonb_build_object('items',jsonb_build_array(p->'items'->0,p->'items'->0)),'22023');
 perform pg_temp.gt_reject(pg_temp.gt_payload(4),'22023');
 perform pg_temp.gt_reject(pg_temp.gt_payload(6),'22023');
 other:=pg_temp.gt_payload(5);perform pg_temp.gt_reject(p||jsonb_build_object('projects',(p->'projects')||(other->'projects')),'22023');
 perform pg_temp.gt_reject(p||jsonb_build_object('items',(p->'items')||(other->'items')),'22023');
 select to_jsonb(a) into before_rows from public.rm_celulas_projeto a where id=pg_temp.gt_key('6',1);
 r:=pg_temp.gt_call(rid,p);select to_jsonb(a) into after_rows from public.rm_celulas_projeto a where id=pg_temp.gt_key('6',1);
 perform pg_temp.gt_check(r->'record'->'changed_ids'=jsonb_build_array(pg_temp.gt_key('6',1)),'changed item IDs reported');
 perform pg_temp.gt_check((after_rows->>'data_limite')::timestamptz='2026-11-14T15:00:00Z'::timestamptz,'new dates use Sao Paulo noon');
 perform pg_temp.gt_check(before_rows->'data_inicio'=after_rows->'data_inicio','omitted timestamp preserves microseconds and original time');
 perform pg_temp.gt_check(before_rows-array['data_limite','updated_at','replanejada_em','replanejada_por_id','modified_by_id','sync_source']=after_rows-array['data_limite','updated_at','replanejada_em','replanejada_por_id','modified_by_id','sync_source'],'status sequence visibility forms and all unrelated data preserved');
 perform pg_temp.gt_check((pg_temp.gt_call(rid,p)->>'idempotent_replay')::boolean,'exact retry is idempotent');
 begin set local role authenticated;perform public.rm_web_mutate_v1(rid,'save_gantt_plan',p);raise exception 'FAIL permitless replay';exception when insufficient_privilege then reset role;end;
 begin perform pg_temp.gt_call(rid,jsonb_set(p,'{reason}','"Another reason"'));raise exception 'FAIL changed replay';exception when unique_violation then null;end;
 perform pg_temp.gt_actor(6);begin perform pg_temp.gt_call(rid,p);raise exception 'FAIL actor replay';exception when unique_violation then null;end;perform pg_temp.gt_actor(1);
 insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.gt_call(rid,p);raise exception 'FAIL MFA replay';exception when insufficient_privilege then null;end;
 perform pg_temp.gt_actor(1,'aal2');perform pg_temp.gt_check((pg_temp.gt_call(rid,p)->>'idempotent_replay')::boolean,'MFA checked on retry');delete from auth.mfa_factors where user_id=auth.uid();perform pg_temp.gt_actor(1);
 p:=pg_temp.gt_payload(1,'{"data_limite":"2026-11-14"}');r:=pg_temp.gt_call(gen_random_uuid(),p);
 perform pg_temp.gt_check(r->'record'->'changed_ids'='[]' and (select to_jsonb(a)=after_rows from public.rm_celulas_projeto a where id=pg_temp.gt_key('6',1)),'no-op preserves row and revision');
 p:=pg_temp.gt_payload();update public.rm_celulas_projeto set observacao='Off-screen update' where id=pg_temp.gt_key('6',3);perform pg_temp.gt_reject(p,'PT409');
 p:=pg_temp.gt_payload();update public.rm_projetos set nome='Changed project' where id=pg_temp.gt_key('5',1);perform pg_temp.gt_reject(p,'PT409');

 -- Two-item validation failure rolls back the first item's dates AND receipt.
 p:=pg_temp.gt_payload(1,'{"data_limite":"2026-11-15"}');p:=jsonb_set(p,'{items}',p->'items'||(pg_temp.gt_payload(2,'{"data_inicio":"2026-11-20"}') ->'items'));
 select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.rm_celulas_projeto a;select count(*) into before_count from rm_private.web_mutation_receipts;
 perform pg_temp.gt_reject(p,'22023');select jsonb_agg(to_jsonb(a) order by id) into after_rows from public.rm_celulas_projeto a;
 perform pg_temp.gt_check(before_rows=after_rows and before_count=(select count(*) from rm_private.web_mutation_receipts),'batch validation failure is atomic');

 -- The complete project version protects dates and links across cell scopes.
 link:=jsonb_build_object('predecessor_id',pg_temp.gt_key('6',1),'successor_id',pg_temp.gt_key('6',2),'lag_days',0);
 p:=pg_temp.gt_payload(1,'{"data_limite":"2026-11-11"}');p:=p||jsonb_build_object('dependencies',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'links',jsonb_build_array(link)));
 r:=pg_temp.gt_call(gen_random_uuid(),p);perform pg_temp.gt_check((r->'record'->>'links_changed')::boolean,'date and FS links publish together');
 perform pg_temp.gt_check(jsonb_array_length(pg_temp.gt_snapshot()->'links')=1,'project shows active dependency');
 p:=pg_temp.gt_payload(1,'{"data_limite":"2026-11-12"}');perform pg_temp.gt_reject(p,'PT409');
 p:=pg_temp.gt_payload(2,'{"data_inicio":"2026-11-11"}');perform pg_temp.gt_reject(p,'PT409');
 p:=pg_temp.gt_payload(2,'{"data_inicio":"2026-11-12"}');r:=pg_temp.gt_call(gen_random_uuid(),p);perform pg_temp.gt_check(r->'record'->'changed_ids'='[]','FS inclusive date exactly next day is allowed');
 p:=pg_temp.gt_payload();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('dependencies',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'links',jsonb_build_array(link)));
 perform pg_temp.gt_reject(jsonb_set(p,'{dependencies,links,0,successor_id}',to_jsonb(pg_temp.gt_key('6',1))),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{dependencies,links,0,successor_id}',to_jsonb(pg_temp.gt_key('6',5))),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{dependencies,links,0,lag_days}','-1'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{dependencies,links,0,lag_days}','1.5'),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{dependencies,links}',jsonb_build_array(link,link)),'22023');
 perform pg_temp.gt_reject(jsonb_set(p,'{dependencies,links}',jsonb_build_array(link,jsonb_build_object('predecessor_id',pg_temp.gt_key('6',2),'successor_id',pg_temp.gt_key('6',1),'lag_days',0))),'22023');
 r:=pg_temp.gt_call(gen_random_uuid(),p);perform pg_temp.gt_check(not(r->'record'->>'links_changed')::boolean,'no-op link set preserves plan');

 -- Baseline captures persisted complete project, cannot contain a draft.
 p:=pg_temp.gt_payload();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('baseline',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'label','Plano aprovado 1'));
 old_version:=rm_private.web_gantt_project_version_v1(pg_temp.gt_key('5',1));base_payload:=p;base_rid:=gen_random_uuid();r:=pg_temp.gt_call(base_rid,p);baseline_id:=(r->'record'->>'baseline_id')::uuid;
 perform pg_temp.gt_check(baseline_id is not null and jsonb_array_length(pg_temp.gt_snapshot()->'baseline'->'items')=4,'baseline includes all stored project stages');
 perform pg_temp.gt_check(old_version<>rm_private.web_gantt_project_version_v1(pg_temp.gt_key('5',1)),'baseline participates in plan version');
 select items into baseline_items from rm_private.gantt_baselines where id=baseline_id;
 begin update rm_private.gantt_baselines set label='Changed' where id=baseline_id;raise exception 'FAIL mutable baseline';exception when insufficient_privilege then null;end;
 begin delete from rm_private.gantt_baselines where id=baseline_id;raise exception 'FAIL deleted baseline';exception when insufficient_privilege then null;end;
 p:=pg_temp.gt_payload(3,'{"data_inicio":"2026-11-16","data_limite":"2026-11-17"}');r:=pg_temp.gt_call(gen_random_uuid(),p);
 perform pg_temp.gt_check((select items=baseline_items from rm_private.gantt_baselines where id=baseline_id),'new planning does not rewrite baseline');
 p:=pg_temp.gt_payload();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('baseline',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'label','Plano aprovado 2'));r:=pg_temp.gt_call(gen_random_uuid(),p);
 perform pg_temp.gt_check((select count(*)=2 from rm_private.gantt_baselines where projeto_id=pg_temp.gt_key('5',1)) and pg_temp.gt_snapshot()->'baseline'->>'label'='Plano aprovado 2','latest baseline displayed; history retained');
 r:=pg_temp.gt_call(base_rid,base_payload);perform pg_temp.gt_check((r->>'idempotent_replay')::boolean and(r->'record'->>'baseline_id')::uuid=baseline_id and(select count(*)=2 from rm_private.gantt_baselines where projeto_id=pg_temp.gt_key('5',1)),'baseline replay preserves original reference after a newer capture');

 -- Retirement hides linked endpoints without removing historical metadata.
 p:=pg_temp.gt_payload();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('dependencies',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'links',jsonb_build_array(link,jsonb_build_object('predecessor_id',pg_temp.gt_key('6',2),'successor_id',pg_temp.gt_key('6',3),'lag_days',0))));perform pg_temp.gt_call(gen_random_uuid(),p);
 old_version:=rm_private.web_gantt_project_version_v1(pg_temp.gt_key('5',1));perform pg_temp.gt_retire(pg_temp.gt_key('6',2),true);
 perform pg_temp.gt_check(jsonb_array_length(pg_temp.gt_snapshot()->'links')=0 and (select jsonb_array_length(links)=2 from rm_private.gantt_project_plans where projeto_id=pg_temp.gt_key('5',1)),'retired dependency hidden but preserved');
 perform pg_temp.gt_check(old_version<>rm_private.web_gantt_project_version_v1(pg_temp.gt_key('5',1)),'retirement invalidates plan');
 p:=pg_temp.gt_payload(3,'{"data_limite":"2026-11-18"}');perform pg_temp.gt_call(gen_random_uuid(),p);
 p:=pg_temp.gt_payload();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('dependencies',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'links',jsonb_build_array(jsonb_build_object('predecessor_id',pg_temp.gt_key('6',1),'successor_id',pg_temp.gt_key('6',3),'lag_days',0))));
 r:=pg_temp.gt_call(gen_random_uuid(),p);perform pg_temp.gt_check(jsonb_array_length(pg_temp.gt_snapshot()->'links')=1 and(select jsonb_array_length(links)=3 from rm_private.gantt_project_plans where projeto_id=pg_temp.gt_key('5',1)),'editing active dependencies retains hidden retired links');
 p:=pg_temp.gt_payload();p:=jsonb_set(p,'{items}','[]')||jsonb_build_object('dependencies',jsonb_build_object('projeto_id',pg_temp.gt_key('5',1),'links',jsonb_build_array(jsonb_build_object('predecessor_id',pg_temp.gt_key('6',3),'successor_id',pg_temp.gt_key('6',1),'lag_days',0))));perform pg_temp.gt_reject(p,'22023');
 perform pg_temp.gt_retire(pg_temp.gt_key('6',2),false);perform pg_temp.gt_check(jsonb_array_length(pg_temp.gt_snapshot()->'links')=3,'restoring same allocation restores acyclic dependency context after graph edits');

 -- General and cell views can publish one atomic batch across projects.
 p:=pg_temp.gt_payload(3,'{"data_limite":"2026-11-18"}');other:=pg_temp.gt_payload(5,'{"data_inicio":"2026-11-18","data_limite":"2026-11-20"}');
 p:=p||jsonb_build_object('projects',(p->'projects')||(other->'projects'),'items',(p->'items')||(other->'items'));rid:=gen_random_uuid();r:=pg_temp.gt_call(rid,p);
 perform pg_temp.gt_check(r->>'id'=rid::text and r->'projeto_id'='null' and r->'record'->'changed_ids'=jsonb_build_array(pg_temp.gt_key('6',5)),'multi-project batch has parent identity and reports actual changes');

 -- A deliberately occupied deterministic child ID cannot replay an unrelated
 -- plan_cell operation or partially apply the batch.
 rid:=gen_random_uuid();p:=pg_temp.gt_payload(5,'{"data_limite":"2026-11-21"}');
 other:=jsonb_build_object('projeto_id',pg_temp.gt_key('5',2),'celula_id',pg_temp.gt_key('4',1),'expected_updated_at',p->'items'->0->>'expected_updated_at','changes','{"data_limite":"2026-11-20T15:00:00Z"}'::jsonb);
 perform pg_temp.gt_call(md5('em-gantt-v1:'||rid::text||':'||pg_temp.gt_key('6',5)::text)::uuid,other,'em.planning.manage','plan_cell');
 p:=pg_temp.gt_payload(5,'{"data_limite":"2026-11-21"}');
 begin perform pg_temp.gt_call(rid,p);raise exception 'FAIL child UUID collision';exception when unique_violation then null;end;
 perform pg_temp.gt_check(not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=rid) and(select data_limite='2026-11-20T15:00:00Z'::timestamptz from public.rm_celulas_projeto where id=pg_temp.gt_key('6',5)),'child receipt collision rolls back the parent submission');
end$$;

select pg_temp.gt_actor(2);select pg_temp.gt_call(gen_random_uuid(),pg_temp.gt_payload(3,'{"data_limite":"2026-11-19"}'));
select pg_temp.gt_actor(3);select pg_temp.gt_reject(pg_temp.gt_payload(),'42501');
set local role authenticated;
select pg_temp.gt_check(not exists(select 1 from jsonb_array_elements(pg_temp.gt_snapshot()->'items') x where(x->>'can_edit')::boolean),'auditor gets read only items');
reset role;
select pg_temp.gt_actor(4);
set local role authenticated;
do $$begin begin perform pg_temp.gt_snapshot();raise exception 'FAIL inactive read';exception when insufficient_privilege then null;end;end$$;
reset role;
select pg_temp.gt_actor(1);
-- A scope which exceeds the cap must not return a plausible partial graph.
insert into public.rm_celulas(id,nome) select pg_temp.gt_key('4',n),'Gantt bound '||n from generate_series(10,2010)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) select pg_temp.gt_key('6',n),pg_temp.gt_key('5',4),pg_temp.gt_key('4',n),'em_dia' from generate_series(10,2010)n;
set local role authenticated;
do $$declare s jsonb;begin s:=pg_temp.gt_snapshot(4);perform pg_temp.gt_check(s->>'complete'='false' and(s->>'total')::int=2001 and s->'items'='[]' and s->'links'='[]' and s->'projects'='[]' and s->'cells'='[]' and s->'baseline'='null','overflow fails closed without partial rows or graph');end$$;
reset role;
do $$declare snapshot jsonb;payload jsonb;r jsonb;begin
 snapshot:=public.rm_web_project_delete_snapshot_v1(pg_temp.gt_key('5',1));
 perform pg_temp.gt_check(snapshot->'can_delete'='true','Gantt metadata is exclusively owned in delete closure');
 payload:=jsonb_build_object('id',pg_temp.gt_key('5',1),'expected_updated_at',snapshot->'project'->>'updated_at','expected_context_version',snapshot->>'context_version','confirm_delete',true,'justificativa','Delete local Gantt fixture');
 r:=pg_temp.gt_call(gen_random_uuid(),payload,'em.projects.manage','delete_project');
 perform pg_temp.gt_check(not exists(select 1 from rm_private.gantt_baselines where projeto_id=pg_temp.gt_key('5',1)) and not exists(select 1 from rm_private.gantt_project_plans where projeto_id=pg_temp.gt_key('5',1)),'confirmed project delete removes owned Gantt metadata');
end$$;
select pg_temp.gt_check(not has_function_privilege('anon','public.rm_web_gantt_snapshot_v1(jsonb)','EXECUTE') and not has_function_privilege('authenticated','rm_private.web_mutate_before_gantt_v1(uuid,text,jsonb)','EXECUTE'),'anonymous and bypass entry points denied');
select pg_temp.gt_check(not has_table_privilege('authenticated','rm_private.gantt_project_plans','INSERT') and not has_table_privilege('authenticated','rm_private.gantt_baselines','UPDATE'),'metadata has no direct DML grants');
rollback;
\echo 'Gantt planning contract passed'

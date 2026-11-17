\set ON_ERROR_STOP on
begin;
create function pg_temp.cp_key(h text,n int) returns uuid language sql immutable as $$select(h||'af05000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.cp_check(value boolean,message text) returns void language plpgsql as $$begin if value is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
create function pg_temp.cp_actor(n int,aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.cp_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.cp_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.capacity.actor',n::text,true);
end$$;
create function pg_temp.cp_resource(ident uuid default null) returns jsonb language sql as $$
 select case when ident is null then '{"id":null,"expected_version":null,"name":"Declared person","kind":"pessoa","active":true,"weekly_minutes":[480,480,480,480,480,0,0],"exceptions":[],"acknowledge_overload":false,"reason":"Declare capacity"}'::jsonb
 else jsonb_build_object('id',r.id,'expected_version',rm_private.capacity_resource_version_v1(r.id),'name',r.name,'kind',r.kind,'active',r.active,'weekly_minutes',r.weekly_minutes,'exceptions',r.exceptions,'acknowledge_overload',false,'reason','Edit capacity') end
 from (select 1) seed left join rm_private.capacity_resources r on r.id=ident;
$$;
create function pg_temp.cp_booking(ident uuid,n int,days jsonb default '[{"date":"2026-11-17","minutes":240}]') returns jsonb language sql as $$
 select jsonb_build_object('resource_id',ident,'expected_resource_version',rm_private.capacity_resource_version_v1(ident),'allocation_id',a.id,'expected_allocation_updated_at',a.updated_at,
 'expected_project_version',rm_private.web_gantt_project_version_v1(a.projeto_id),'days',days,'acknowledge_overload',false,'reason','Reserve declared resource') from public.rm_celulas_projeto a where a.id=pg_temp.cp_key('6',n);
$$;
create function pg_temp.cp_call(rid uuid,p jsonb,op text default 'save_capacity_resource',cap text default 'em.planning.manage') returns jsonb language plpgsql as $$declare result jsonb;begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.capacity.actor'),64,'a50'),rid,op,p,cap);
 set local role authenticated;result:=public.rm_web_mutate_v1(rid,op,p);reset role;return result;
 exception when others then reset role;raise;
end$$;
create function pg_temp.cp_reject(p jsonb,wanted text,op text default 'save_capacity_resource',cap text default 'em.planning.manage') returns void language plpgsql as $$declare actual text;begin
 begin perform pg_temp.cp_call(gen_random_uuid(),p,op,cap);exception when others then get stacked diagnostics actual=returned_sqlstate;
 if actual=wanted then return;end if;raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: invalid capacity command succeeded, wanted %',wanted;
end$$;
create function pg_temp.cp_retire(ident uuid,retired boolean) returns void language plpgsql as $$declare allocation public.rm_celulas_projeto%rowtype;begin
 select * into allocation from public.rm_celulas_projeto where id=ident;
 insert into rm_private.cell_availability_events(projeto_id,celula_projeto_id,actor_id,action,old_visibility,new_visibility,old_retired,new_retired,allocation_version,client_submission_id)
 values(allocation.projeto_id,allocation.id,pg_temp.cp_key('2',1),case when retired then 'retire' else 'restore' end,allocation.visibilidade,false,allocation.retirada,retired,allocation.updated_at,gen_random_uuid());
 update public.rm_celulas_projeto set retirada=retired,visibilidade=false where id=ident;
end$$;
do $$declare n int;begin
 for n in 1..4 loop
  insert into auth.users(id) values(pg_temp.cp_key('1',n));
  insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.cp_key('2',n),pg_temp.cp_key('1',n),'Capacity fixture '||n,case when n=3 then 'auditor'::public.rm_perfil_usuario_enum when n=2 then 'padr_o' else 'administrador' end,case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
  insert into auth.sessions(id,user_id) values(pg_temp.cp_key('3',n),pg_temp.cp_key('1',n));
  if n<>4 then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values(pg_temp.cp_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.cp_key('9',n),pg_temp.cp_key('2',n),pg_temp.cp_key('1',n),true,pg_temp.cp_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'a50'),pg_temp.cp_key('8',n),pg_temp.cp_key('3',n),'opaque-capacity-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end$$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select pg_temp.cp_key('4',n),'Capacity cell '||n from generate_series(1,2)n;
insert into public.rm_projetos(id,numero) select pg_temp.cp_key('5',n),'CAPACITY50-'||n from generate_series(1,2)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite)
 select pg_temp.cp_key('6',n),pg_temp.cp_key('5',n),pg_temp.cp_key('4',n),'em_dia',true,'2026-11-16T08:12:34.123456Z','2026-11-30T15:00:00Z' from generate_series(1,2)n;
select pg_temp.cp_actor(1);
do $$declare p jsonb;r jsonb;rid uuid:=gen_random_uuid();ident uuid;ver text;before_rows jsonb;before_count bigint;old_booking jsonb;old_id uuid;snapshot jsonb;begin
 p:=pg_temp.cp_resource();perform pg_temp.cp_reject(p,'22023','save_capacity_resource','em.projects.manage');
 perform pg_temp.cp_reject(p||'{"actor_id":"bad"}','22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{weekly_minutes}','[480]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{weekly_minutes}','[480,480,480,480,480,0,1441]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{weekly_minutes}','[480,480,480,480,480,0,1.5]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{weekly_minutes}','[480,480,480,480,480,0,"0"]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{exceptions}','[{"date":"2026-02-30","minutes":0,"label":"Stop"}]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{exceptions}','[{"date":"1899-12-31","minutes":0,"label":"Stop"}]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{exceptions}','[{"date":"2026-11-17","minutes":0,"label":" "}]'),'22023');
 perform pg_temp.cp_reject(jsonb_set(p,'{exceptions}','[{"date":"2026-11-17","minutes":0,"label":"Stop"},{"date":"2026-11-17","minutes":1,"label":"x"}]'),'22023');
 r:=pg_temp.cp_call(rid,p);ident:=(r->>'id')::uuid;
 perform set_config('rm.test.capacity.resource',ident::text,true);
 perform pg_temp.cp_check(r->'record'->>'resource_changed'='true' and r->'projeto_id'='null','resource created explicitly');
 perform pg_temp.cp_check((pg_temp.cp_call(rid,p)->>'idempotent_replay')::boolean,'exact resource retry');
 begin perform pg_temp.cp_call(rid,p||'{"reason":"Different reason"}');raise exception 'FAIL submission collision';exception when unique_violation then null;end;
 begin set local role authenticated;perform public.rm_web_mutate_v1(rid,'save_capacity_resource',p);raise exception 'FAIL no permit';exception when insufficient_privilege then reset role;end;
 insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.cp_call(rid,p);raise exception 'FAIL MFA replay';exception when insufficient_privilege then null;end;
 perform pg_temp.cp_actor(1,'aal2');perform pg_temp.cp_check((pg_temp.cp_call(rid,p)->>'idempotent_replay')::boolean,'MFA checked on retry');delete from auth.mfa_factors where user_id=auth.uid();perform pg_temp.cp_actor(1);
 ver:=rm_private.capacity_resource_version_v1(ident);r:=pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_resource(ident));
 perform pg_temp.cp_check(r->'record'->>'resource_changed'='false' and ver=rm_private.capacity_resource_version_v1(ident),'resource no-op preserves version');
 perform pg_temp.cp_reject(jsonb_set(pg_temp.cp_resource(ident),'{kind}','"maquina"'),'22023');
 perform pg_temp.cp_reject(jsonb_set(pg_temp.cp_resource(),'{name}','"  DECLARED PERSON  "'),'23505');
 old_booking:=pg_temp.cp_booking(ident,1);old_id:=gen_random_uuid();r:=pg_temp.cp_call(old_id,old_booking,'save_capacity_bookings');
 perform pg_temp.cp_check(r->'record'->>'changed_days'='1' and ver<>rm_private.capacity_resource_version_v1(ident),'booking changes shared resource version');
 perform pg_temp.cp_check((pg_temp.cp_call(old_id,old_booking,'save_capacity_bookings')->>'idempotent_replay')::boolean,'booking exact retry');
 ver:=rm_private.capacity_resource_version_v1(ident);r:=pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1),'save_capacity_bookings');
 perform pg_temp.cp_check(r->'record'->>'changed_days'='0' and ver=rm_private.capacity_resource_version_v1(ident),'booking no-op preserves version');
 p:=pg_temp.cp_booking(ident,2,'[{"date":"2026-11-17","minutes":300}]');select count(*) into before_count from rm_private.web_mutation_receipts;
 perform pg_temp.cp_reject(p,'PT409','save_capacity_bookings');perform pg_temp.cp_check(before_count=(select count(*) from rm_private.web_mutation_receipts),'rejected overload leaves no receipt');
 r:=pg_temp.cp_call(gen_random_uuid(),p||'{"acknowledge_overload":true}','save_capacity_bookings');
 perform pg_temp.cp_check((select sum(minutes)=540 from rm_private.capacity_bookings where resource_id=ident),'overload can be acknowledged across projects');
 perform pg_temp.cp_reject(p,'PT409','save_capacity_bookings');
 snapshot:=public.rm_web_capacity_snapshot_v1(jsonb_build_object('start','2026-11-16','days',7,'project_id',pg_temp.cp_key('5',1)));
 perform pg_temp.cp_check((select count(*)=2 from jsonb_array_elements(snapshot->'bookings') b where b->>'resource_id'=ident::text) and snapshot->'project_plan'->'projects'->0->>'id'=pg_temp.cp_key('5',1)::text,'selected project retains other projects resource demand');
 perform pg_temp.cp_check(snapshot->'bookings'->0?'allocation_updated_at' and snapshot::text !~ 'auth_user|updated_by|email|bubble_id','minimal snapshot and allocation edit version');
 perform pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,2,'[{"date":"2026-11-25","minutes":60}]'),'save_capacity_bookings');
 snapshot:=public.rm_web_capacity_snapshot_v1(jsonb_build_object('start','2026-11-16','days',7,'project_id',pg_temp.cp_key('5',1)));
 perform pg_temp.cp_check((select count(*)=2 from jsonb_array_elements(snapshot->'bookings') b where b->>'resource_id'=ident::text) and
  (select resource_item->'booked_days' from jsonb_array_elements(snapshot->'resources') resource_item where resource_item->>'id'=ident::text)='[{"date":"2026-11-17","minutes":540},{"date":"2026-11-25","minutes":60}]','all booked-day demand includes other projects and dates outside the selected window');
 p:=pg_temp.cp_resource(ident)||'{"active":false}';perform pg_temp.cp_reject(p,'PT409');perform pg_temp.cp_call(gen_random_uuid(),p||'{"acknowledge_overload":true}');
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-18","minutes":1}]'),'22023','save_capacity_bookings');
 -- Same stored positive value remains a no-op after deactivation and closure.
 update public.rm_projetos set status_pcp='cancelado' where id=pg_temp.cp_key('5',1);
 r:=pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1),'save_capacity_bookings');perform pg_temp.cp_check(r->'record'->>'changed_days'='0','legacy positive no-op allowed on closed project/inactive resource');
 r:=pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1,'[{"date":"2026-11-17","minutes":0}]'),'save_capacity_bookings');perform pg_temp.cp_check(r->'record'->>'changed_days'='1','zero releases booking from closed project/inactive resource');
 perform pg_temp.cp_check((pg_temp.cp_call(old_id,old_booking,'save_capacity_bookings')->>'idempotent_replay')::boolean and not exists(select 1 from rm_private.capacity_bookings where allocation_id=pg_temp.cp_key('6',1)),'frozen replay never resurrects a subsequently released booking');
 update public.rm_projetos set status_pcp='executando' where id=pg_temp.cp_key('5',1);
 perform pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_resource(ident)||'{"active":true,"acknowledge_overload":true}');
 p:=pg_temp.cp_resource(ident)||'{"exceptions":[{"date":"2026-11-25","minutes":0,"label":"Unavailable outside window"}]}';
 perform pg_temp.cp_reject(p,'PT409');perform pg_temp.cp_call(gen_random_uuid(),p||'{"acknowledge_overload":true}');
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-15","minutes":1}]'),'22023','save_capacity_bookings');
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-31","minutes":1}]'),'22023','save_capacity_bookings');
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-18","minutes":1},{"date":"2026-11-18","minutes":2}]'),'22023','save_capacity_bookings');
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-18","minutes":-1}]'),'22023','save_capacity_bookings');
 perform pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1,'[{"date":"2026-11-18","minutes":240}]'),'save_capacity_bookings');
 select jsonb_agg(to_jsonb(b) order by id) into before_rows from rm_private.capacity_bookings b;
 p:=pg_temp.cp_booking(ident,1,'[{"date":"2026-11-18","minutes":0},{"date":"2026-12-01","minutes":1}]');perform pg_temp.cp_reject(p,'22023','save_capacity_bookings');
 perform pg_temp.cp_check((select jsonb_agg(to_jsonb(b) order by id)=before_rows from rm_private.capacity_bookings b),'batch failure rolls back earlier explicit release');
 p:=pg_temp.cp_booking(ident,1);update public.rm_celulas_projeto set observacao='Queued mobile work' where id=pg_temp.cp_key('6',1);perform pg_temp.cp_reject(p,'PT409','save_capacity_bookings');
 -- Changing the Gantt calendar preserves reservations and diagnoses them in reads.
 insert into rm_private.gantt_project_settings(projeto_id,calendar,milestones,updated_by) values(pg_temp.cp_key('5',1),'{"weekdays":[1],"exceptions":[]}','[]',pg_temp.cp_key('2',1));
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-19","minutes":1}]'),'22023','save_capacity_bookings');
 perform pg_temp.cp_check((select jsonb_agg(to_jsonb(b) order by id)=before_rows from rm_private.capacity_bookings b),'calendar changes preserve bookings');
 snapshot:=public.rm_web_capacity_snapshot_v1(jsonb_build_object('start','2026-11-16','days',7,'project_id',pg_temp.cp_key('5',1)));
 perform pg_temp.cp_check(exists(select 1 from jsonb_array_elements(snapshot->'bookings') b where b->>'project_id'=pg_temp.cp_key('5',1)::text and b->>'project_working'='false'),'legacy calendar mismatch is visible');
 perform pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1,'[{"date":"2026-11-23","minutes":60}]'),'save_capacity_bookings');
 perform pg_temp.cp_retire(pg_temp.cp_key('6',1),true);
 r:=pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1,'[{"date":"2026-11-18","minutes":240}]'),'save_capacity_bookings');
 perform pg_temp.cp_check(r->'record'->>'changed_days'='0','retired off-calendar legacy positive remains an exact no-op');
 perform pg_temp.cp_reject(pg_temp.cp_booking(ident,1,'[{"date":"2026-11-23","minutes":120}]'),'22023','save_capacity_bookings');
 r:=pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_booking(ident,1,'[{"date":"2026-11-23","minutes":0}]'),'save_capacity_bookings');
 perform pg_temp.cp_check(r->'record'->>'changed_days'='1','retired allocations can explicitly release reservations');
 perform pg_temp.cp_retire(pg_temp.cp_key('6',1),false);
 perform pg_temp.cp_check(exists(select 1 from rm_private.project_delete_scope_v1(pg_temp.cp_key('5',1)) where table_name='capacity_bookings' and cardinality(ids)=1),'delete ownership includes reservations');
 snapshot:=public.rm_web_project_delete_snapshot_v1(pg_temp.cp_key('5',1));p:=jsonb_build_object('id',pg_temp.cp_key('5',1),'expected_updated_at',snapshot->'project'->>'updated_at','expected_context_version',snapshot->>'context_version','confirm_delete',true,'justificativa','Delete isolated capacity project');
 perform pg_temp.cp_call(gen_random_uuid(),p,'delete_project','em.projects.manage');
 perform pg_temp.cp_check(exists(select 1 from rm_private.capacity_resources where id=ident) and(select count(*)=2 from rm_private.capacity_bookings where resource_id=ident),'delete removes only owned bookings and preserves shared resource/other project');
 begin perform pg_temp.cp_call(old_id,old_booking,'save_capacity_bookings');raise exception 'FAIL deleted booking replay';exception when sqlstate 'PT410' then null;end;
 perform pg_temp.cp_check(not exists(select 1 from public.rm_projetos where id=pg_temp.cp_key('5',1)),'frozen booking retry reports reconciliation without resurrecting the project');
 begin perform pg_temp.cp_call(old_id,old_booking||'{"reason":"Changed after deletion"}','save_capacity_bookings');raise exception 'FAIL altered tombstone replay';exception when unique_violation then null;end;
 perform pg_temp.cp_reject(pg_temp.cp_resource()||jsonb_build_object('reason',repeat('x',2097152)),'PT413');
end$$;

select pg_temp.cp_actor(2);select pg_temp.cp_call(gen_random_uuid(),pg_temp.cp_resource()||'{"name":"Declared machine","kind":"maquina"}');
select pg_temp.cp_actor(3);select pg_temp.cp_reject(pg_temp.cp_resource(),'42501');
set local role authenticated;
select pg_temp.cp_check((select count(*)>=2 from rm_private.capacity_resources),'auditor can read declared capacity');
do $$begin
 begin update rm_private.capacity_resources set active=false;raise exception 'FAIL direct resource write';exception when insufficient_privilege then null;end;
 begin delete from rm_private.capacity_bookings;raise exception 'FAIL direct reservation write';exception when insufficient_privilege then null;end;
 begin perform public.rm_web_capacity_snapshot_v1('{"start":"2026-11-16","days":8,"project_id":null}');raise exception 'FAIL invalid window';exception when invalid_parameter_value then null;end;
end$$;
reset role;
select pg_temp.cp_actor(4);
set local role authenticated;
select pg_temp.cp_check(not exists(select 1 from rm_private.capacity_resources),'inactive readers receive no resources');
do $$begin begin perform public.rm_web_capacity_snapshot_v1('{"start":"2026-11-16","days":7,"project_id":null}');raise exception 'FAIL inactive snapshot';exception when insufficient_privilege then null;end;end$$;
reset role;
rollback;
select 'PASS: declared capacity enforces SSO/MFA/roles, exact retries, no-op versions, cross-project overload acknowledgement, explicit releases, strict data, atomic batches and owned deletion' result;

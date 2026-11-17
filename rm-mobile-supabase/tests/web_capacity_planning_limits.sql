\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create function pg_temp.cl_id(h text,n int) returns uuid language sql immutable as $$select(h||'df05000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.cl_check(value boolean,message text) returns void language plpgsql as $$begin if value is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
insert into auth.users(id) values(pg_temp.cl_id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.cl_id('2',1),pg_temp.cl_id('1',1),'Capacity limits planner','administrador','ativo');
insert into public.rm_projetos(id,numero) values(pg_temp.cl_id('5',1),'CAPACITY LIMITS');
insert into public.rm_celulas(id,nome) select pg_temp.cl_id('4',n),'Capacity limit cell '||n from generate_series(1,51)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,data_inicio,data_limite)
 select pg_temp.cl_id('6',n),pg_temp.cl_id('5',1),pg_temp.cl_id('4',n),'em_dia','2026-11-16','2026-11-30' from generate_series(1,51)n;
insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by)
 select pg_temp.cl_id('7',n),'Capacity bound resource '||n,'maquina',true,'[480,480,480,480,480,0,0]','[]',pg_temp.cl_id('2',1)
 from generate_series(1,200-(select count(*)::int from rm_private.capacity_resources))n;
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub',pg_temp.cl_id('1',1)::text,true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
do $$begin
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_capacity_resource','{"id":null,"expected_version":null,"name":"Beyond declared limit","kind":"pessoa","active":false,"weekly_minutes":[0,0,0,0,0,0,0],"exceptions":[],"acknowledge_overload":false,"reason":"Check declared resource cap"}');
  raise exception 'FAIL resource creation exceeded cap';
 exception when sqlstate 'PT413' then null;end;
end$$;
reset role;
insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by)
 values(pg_temp.cl_id('7',201),'Overflow resource','maquina',true,'[0,0,0,0,0,0,0]','[]',pg_temp.cl_id('2',1));
set local role authenticated;
do $$declare snapshot jsonb;begin
 snapshot:=public.rm_web_capacity_snapshot_v1('{"start":"2026-11-16","days":7,"project_id":null}');
 perform pg_temp.cl_check(snapshot->>'complete'='false' and snapshot->'totals'->>'resources'='201' and snapshot->'resources'='[]' and snapshot->'bookings'='[]' and snapshot->'project_plan'='null','resource overflow returns no partial plan');
end$$;
reset role;
delete from rm_private.capacity_resources where id=pg_temp.cl_id('7',201);

-- A wide history must be bounded even when its dates are outside the window.
insert into rm_private.capacity_bookings(resource_id,allocation_id,day,minutes,updated_by)
 select pg_temp.cl_id('7',1),pg_temp.cl_id('6',1),'1900-01-01'::date+n,1,pg_temp.cl_id('2',1) from generate_series(0,20000)n;
set local role authenticated;
do $$declare snapshot jsonb;begin
 snapshot:=public.rm_web_capacity_snapshot_v1('{"start":"2026-11-16","days":7,"project_id":null}');
 perform pg_temp.cl_check(snapshot->>'complete'='false' and snapshot->'resources'='[]' and snapshot->'bookings'='[]','all-history booked-day overflow is explicit');
end$$;
reset role;
delete from rm_private.capacity_bookings where allocation_id=pg_temp.cl_id('6',1);

-- The daily window has an independent complete-read bound.
insert into rm_private.capacity_bookings(resource_id,allocation_id,day,minutes,updated_by)
 select r.id,pg_temp.cl_id('6',n),'2026-12-16',1,pg_temp.cl_id('2',1) from rm_private.capacity_resources r cross join generate_series(1,51)n;
set local role authenticated;
do $$declare snapshot jsonb;begin
 snapshot:=public.rm_web_capacity_snapshot_v1('{"start":"2026-12-16","days":7,"project_id":null}');
 perform pg_temp.cl_check(snapshot->>'complete'='false' and (snapshot->'totals'->>'bookings')::int>10000 and snapshot->'resources'='[]' and snapshot->'bookings'='[]','window booking overflow returns exact totals and no partial demand');
end$$;
reset role;
delete from rm_private.capacity_bookings where allocation_id in(select pg_temp.cl_id('6',n) from generate_series(1,51)n);

-- Bound the encoded response independently from record counts.
update rm_private.capacity_resources set exceptions=(select jsonb_agg(jsonb_build_object('date',to_char('2024-01-01'::date+n,'YYYY-MM-DD'),'minutes',0,'label',repeat('x',120))) from generate_series(0,365)n);
set local role authenticated;
do $$declare snapshot jsonb;begin
 snapshot:=public.rm_web_capacity_snapshot_v1('{"start":"2026-11-16","days":7,"project_id":null}');
 perform pg_temp.cl_check(snapshot->>'complete'='false' and snapshot->'resources'='[]' and snapshot->'bookings'='[]' and snapshot->'project_plan'='null','ten MiB overflow returns no partial metadata');
 begin perform public.rm_web_capacity_snapshot_v1('{"start":"2200-12-25","days":28,"project_id":null}');raise exception 'FAIL date window outside range';exception when invalid_parameter_value then null;end;
end$$;
reset role;
rollback;
select 'PASS: capacity caps enforce declared resources, full-window bookings, all-history booked days, ten MiB encoding and date bounds without partial snapshots' result;

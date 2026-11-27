\set ON_ERROR_STOP on
begin;
create function pg_temp.enforcement_id(n int) returns uuid language sql immutable as $$
 select ('06800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"06800000-0000-4000-8000-000000000001","code":"BMA"},{"id":"06800000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"06800000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into rm_private.workshop_references(id,code,authority)
 values(pg_temp.enforcement_id(4),'QA-UNIT_4','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1');
do $checks$
begin
 begin
  insert into rm_private.workshop_references(id,code,authority)
   values(pg_temp.enforcement_id(5),'bad code','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1');
  raise exception 'FAIL: invalid authority code accepted';
 exception when check_violation then null;
 end;

 insert into public.rm_projetos(id,nome) values(pg_temp.enforcement_id(6),'Staged legacy project');
 set constraints workshop_new_project_origin immediate;
 delete from public.rm_projetos where id=pg_temp.enforcement_id(6);
 set constraints workshop_new_project_origin deferred;
 begin
  perform rm_private.activate_workshop_root_enforcement_v1();
  raise exception 'FAIL: activation accepted before the portal writer';
 exception when sqlstate 'PT409' then null;
 end;
 begin
  perform rm_private.activate_workshop_direct_root_enforcement_v1();
  raise exception 'FAIL: direct writer guard accepted before the portal writer';
 exception when sqlstate 'PT409' then null;
 end;

 update rm_private.sso_settings set require_sso=true;
 perform rm_private.activate_root_creation_v1(repeat('8',40),pg_temp.enforcement_id(8));
 begin
  insert into public.rm_celulas(id,nome) values(pg_temp.enforcement_id(9),'Pending root blocks activation');
  perform rm_private.activate_workshop_root_enforcement_v1();
  raise exception 'FAIL: activation accepted with pending roots';
 exception when sqlstate 'PT409' then null;
 end;
 begin
  perform rm_private.activate_workshop_root_enforcement_v1();
  raise exception 'FAIL: activation accepted without the pilot receiving proof';
 exception when sqlstate 'PT409' then
  if sqlerrm not like 'Conclua um recebimento da oficina piloto%' then raise;end if;
 end;
 perform rm_private.activate_workshop_direct_root_enforcement_v1();
 perform rm_private.activate_workshop_direct_root_enforcement_v1();
 if exists(select 1 from rm_private.workshop_root_enforcement where activated_at is not null) then
  raise exception 'FAIL: partial guard activated the mobile cutover';
 end if;
 grant select,insert,update on public.rm_projetos,public.rm_celulas to service_role;
 perform set_config('request.jwt.claim.sub',pg_temp.enforcement_id(8)::text,true);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 set local role service_role;

 begin
  insert into public.rm_projetos(id,nome) values(pg_temp.enforcement_id(10),'A direct path without ownership');
  set constraints workshop_new_project_origin immediate;
  raise exception 'FAIL: root reached transaction end without ownership';
 exception when sqlstate 'PT409' then null;
 end;
 begin
  insert into public.rm_celulas(id,nome) values(pg_temp.enforcement_id(11),'A direct cell without ownership');
  set constraints workshop_new_cell_origin immediate;
  raise exception 'FAIL: cell reached transaction end without ownership';
 exception when sqlstate 'PT409' then null;
 end;
 reset role;
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);

 insert into public.rm_projetos(id,nome) values(pg_temp.enforcement_id(12),'Fourth-office project fixture');
 insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.enforcement_id(12),pg_temp.enforcement_id(4));
 insert into public.rm_celulas(id,nome) values(pg_temp.enforcement_id(13),'Fourth-office cell fixture');
 insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.enforcement_id(13),pg_temp.enforcement_id(4));
 set constraints workshop_new_project_origin,workshop_new_cell_origin immediate;
 set local role service_role;
 insert into public.rm_celulas(id,nome) values(pg_temp.enforcement_id(13),'Updated fixture')
  on conflict(id) do update set nome=excluded.nome;
 reset role;
 if (select count(*) from rm_private.workshop_object_origins where workshop_id=pg_temp.enforcement_id(4))<>2
  or (select nome from public.rm_celulas where id=pg_temp.enforcement_id(13)) is distinct from 'Updated fixture'
  or exists(select 1 from unnest(array['anon','authenticated','service_role']) client
   where has_function_privilege(client,'rm_private.activate_workshop_direct_root_enforcement_v1()','execute'))
  or has_function_privilege('service_role','rm_private.activate_workshop_root_enforcement_v1()','execute')
  or has_function_privilege('authenticated','rm_private.activate_workshop_root_enforcement_v1()','execute') then
  raise exception 'FAIL: declared fourth office or private activation invalid';
 end if;
end
$checks$;
select 'PASS: staged root enforcement blocks direct privileged inserts, accepts atomic ownership and preserves existing upserts' result;
rollback;

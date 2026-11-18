\set ON_ERROR_STOP on
begin;
create function pg_temp.wc_id(n int) returns uuid language sql immutable as $$select ('05600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.wc_check(v boolean,msg text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.wc_deny(statement text,state text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlstate=state then return;end if;raise;end;
 raise exception 'FAIL: accepted: %',statement;end$$;
create function pg_temp.wc_policy() returns text language sql immutable as $$select 'f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff'::text$$;
insert into public.rm_projetos(id,nome) values(pg_temp.wc_id(11),'LOCAL catalog project');
insert into public.rm_celulas(id,nome) values(pg_temp.wc_id(12),'LOCAL catalog cell');
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"05600000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05600000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05600000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into public.rm_clientes(id,nome) values(pg_temp.wc_id(21),'LOCAL original client');
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.wc_id(22),'LOCAL original type');
insert into public.rm_forms(id,titulo,celulas_ids) values(pg_temp.wc_id(23),'LOCAL original form',array[pg_temp.wc_id(12)]);
update public.rm_projetos set cliente_id=pg_temp.wc_id(21),tipo_equipamento_id=pg_temp.wc_id(22) where id=pg_temp.wc_id(11);
create temporary table wc_original on commit drop as select jsonb_build_object('client',(select to_jsonb(x) from public.rm_clientes x where id=pg_temp.wc_id(21)),
 'type',(select to_jsonb(x) from public.rm_tipos_equipamento x where id=pg_temp.wc_id(22)),
 'form',(select to_jsonb(x) from public.rm_forms x where id=pg_temp.wc_id(23))) data;
create temporary table wc_counts on commit drop as select (select count(*) from public.rm_clientes) clients,
 (select count(*) from public.rm_tipos_equipamento) equipment_types,(select count(*) from public.rm_forms) form_models;
select pg_temp.wc_deny('select rm_private.workshop_catalog_adopt_bma_v1(''wrong'',1,1,1)','22023');
select pg_temp.wc_deny(format('select rm_private.workshop_catalog_adopt_bma_v1(pg_temp.wc_policy(),%s,%s,%s)',clients+1,equipment_types,form_models),'PT409') from wc_counts;
select rm_private.workshop_catalog_adopt_bma_v1(pg_temp.wc_policy(),clients,equipment_types,form_models) from wc_counts;
select pg_temp.wc_check((select count(*) from rm_private.workshop_catalog_ownership)=(select clients+equipment_types+form_models from wc_counts),'all three approved catalog kinds adopted at reviewed counts');
select pg_temp.wc_check((select data from wc_original)=jsonb_build_object('client',(select to_jsonb(x) from public.rm_clientes x where id=pg_temp.wc_id(21)),
 'type',(select to_jsonb(x) from public.rm_tipos_equipamento x where id=pg_temp.wc_id(22)),
 'form',(select to_jsonb(x) from public.rm_forms x where id=pg_temp.wc_id(23))),'original contents IDs and timestamps preserved');

insert into public.rm_clientes(id,nome) values(pg_temp.wc_id(31),'LOCAL independent client');
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.wc_id(32),'LOCAL independent type');
insert into public.rm_forms(id,titulo) values(pg_temp.wc_id(33),'LOCAL independent form');
select pg_temp.wc_check((rm_private.workshop_catalog_adopt_bma_v1(pg_temp.wc_policy(),clients,equipment_types,form_models)->>'replayed')::boolean,'exact retry acknowledges original batch') from wc_counts;
select pg_temp.wc_check(not exists(select 1 from rm_private.workshop_catalog_ownership where object_id in(pg_temp.wc_id(31),pg_temp.wc_id(32),pg_temp.wc_id(33))),'later catalog objects never default to BMA');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values
 ('client',pg_temp.wc_id(31),pg_temp.wc_id(2)),('equipment_type',pg_temp.wc_id(32),pg_temp.wc_id(2)),('form_model',pg_temp.wc_id(33),pg_temp.wc_id(2));
select pg_temp.wc_deny('update public.rm_projetos set cliente_id=pg_temp.wc_id(31) where id=pg_temp.wc_id(11)','PT409');
select pg_temp.wc_deny('update public.rm_projetos set tipo_equipamento_id=pg_temp.wc_id(32) where id=pg_temp.wc_id(11)','PT409');
select pg_temp.wc_deny('insert into public.rm_projetos(cliente_id,tipo_equipamento_id) values(pg_temp.wc_id(21),pg_temp.wc_id(32))','PT409');
select pg_temp.wc_deny('insert into public.rm_registros_formulario(projeto_id,celula_id,form_id) values(pg_temp.wc_id(11),pg_temp.wc_id(12),pg_temp.wc_id(33))','PT409');
select pg_temp.wc_deny('update public.rm_forms set celulas_ids=array[pg_temp.wc_id(12)] where id=pg_temp.wc_id(33)','PT409');
select pg_temp.wc_deny('insert into public.rm_celula_tipos_equipamento(celula_id,tipo_equipamento_id) values(pg_temp.wc_id(12),pg_temp.wc_id(32))','PT409');

-- Reverse classification must also validate existing references and arrays.
insert into public.rm_projetos(id,cliente_id) values(pg_temp.wc_id(51),pg_temp.wc_id(21));
select pg_temp.wc_deny('insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.wc_id(51),pg_temp.wc_id(2))','PT409');
select pg_temp.wc_check(not exists(select 1 from rm_private.workshop_object_origins where object_id=pg_temp.wc_id(51)),'failed reverse classification leaves no origin');
insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.wc_id(51),pg_temp.wc_id(1));
insert into public.rm_celulas(id,nome) values(pg_temp.wc_id(52),'LOCAL unclassified cell');
update public.rm_forms set celulas_ids=array[pg_temp.wc_id(52)] where id=pg_temp.wc_id(33);
select pg_temp.wc_deny('insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wc_id(52),pg_temp.wc_id(1))','PT409');
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.wc_id(52),pg_temp.wc_id(2));
insert into public.rm_forms(id,titulo) values(pg_temp.wc_id(63),'LOCAL later unknown form');
insert into public.rm_registros_formulario(projeto_id,celula_id,form_id) values(pg_temp.wc_id(11),pg_temp.wc_id(12),pg_temp.wc_id(63));
select pg_temp.wc_deny('insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values(''form_model'',pg_temp.wc_id(63),pg_temp.wc_id(2))','PT409');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('form_model',pg_temp.wc_id(63),pg_temp.wc_id(1));
select pg_temp.wc_deny('insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values(''client'',pg_temp.wc_id(999),pg_temp.wc_id(1))','23503');

-- Unused catalog deletion retains ownership, forbids late ID reuse and is
-- transactional; existing business contents are never copied or renamed.
savepoint before_catalog_delete;
delete from public.rm_tipos_equipamento where id=pg_temp.wc_id(32);
rollback to before_catalog_delete;
select pg_temp.wc_check(not exists(select 1 from rm_private.workshop_catalog_retirements where object_id=pg_temp.wc_id(32)),'rolled back deletion restores catalog state');
delete from public.rm_tipos_equipamento where id=pg_temp.wc_id(32);
select pg_temp.wc_check(exists(select 1 from rm_private.workshop_catalog_ownership where object_id=pg_temp.wc_id(32) and workshop_id=pg_temp.wc_id(2)),'deleted type keeps BRJ ownership');
select pg_temp.wc_deny('insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.wc_id(32),''LOCAL late duplicate'')','PT410');
select pg_temp.wc_deny('update public.rm_clientes set id=pg_temp.wc_id(999) where id=pg_temp.wc_id(31)','PT409');
do $$declare t text;role_name text;f regprocedure;begin
 foreach t in array array['workshop_catalog_adoption','workshop_catalog_ownership','workshop_catalog_retirements'] loop
  perform pg_temp.wc_deny('delete from rm_private.'||t,'42501');
  perform pg_temp.wc_deny('truncate rm_private.'||t||' cascade','42501');
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_table_privilege(role_name,'rm_private.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then raise exception 'FAIL: private catalog metadata exposed';end if;
  end loop;
 end loop;
 for f in select oid::regprocedure from pg_proc where pronamespace='rm_private'::regnamespace and proname like 'workshop_catalog_%' loop
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_function_privilege(role_name,f,'EXECUTE') then raise exception 'FAIL: catalog scope function exposed';end if;
  end loop;
 end loop;
end$$;
select pg_temp.wc_check((rm_private.workshop_catalog_readiness_v1()->>'conflicts')::bigint=0,'catalog direct references remain consistent');
select pg_temp.wc_check(not (rm_private.workshop_catalog_readiness_v1()->>'isolation_active')::boolean,'catalog ownership is not full authorization isolation');
rollback;
\echo PASS: independent catalog ownership, exact BMA adoption, preserved contents, no default, reverse guards, arrays, retirement and private privileges.

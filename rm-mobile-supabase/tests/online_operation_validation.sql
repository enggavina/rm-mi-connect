\set ON_ERROR_STOP on
begin;

create function pg_temp.ov_id(n int) returns uuid language sql immutable as $$
  select ('06210000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.ov_check(ok boolean, assertion text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %', assertion; end if;
end;
$$;
create function pg_temp.ov_deny(statement text, expected text) returns void language plpgsql as $$
begin
  begin execute statement; exception when others then if sqlstate = expected then return; end if; raise; end;
  raise exception 'FAIL: request unexpectedly accepted';
end;
$$;
create function pg_temp.ov_args(cell_id int default null, project_id int default null, page int default 1)
returns jsonb language sql immutable as $$
  select jsonb_build_object('cell_id',pg_temp.ov_id(cell_id),'project_id',pg_temp.ov_id(project_id),'page',page);
$$;
create function pg_temp.ov_context(office int default 1, approved boolean default true)
returns jsonb language sql volatile as $$
  select jsonb_build_object('version',2,'application','em','channel','web',
    'authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
    'workshop',jsonb_build_object('id',pg_temp.ov_id(office),'code',(array['BMA','BRJ','BBH','UNREGISTERED'])[office],
      'name','Oficina local','active',true,'revision',1,'updated_at',stamp),
    'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
      'subject',case when approved then 'a9e45880-1924-4b2d-a2b1-dc12fd029bff'::uuid else pg_temp.ov_id(110) end,'revision',1)),
    'issued_at',stamp,'expires_at',stamp + interval '5 minutes')
  from (select clock_timestamp() stamp) timing;
$$;
create function pg_temp.ov_mint(read_id uuid, args jsonb, office int default 1, approved boolean default true)
returns void language sql as $$
  select public.rm_sso_workshop_read_permit_v1(repeat(case when approved then '6' else '7' end,64),read_id,
    'operation_validation',args,pg_temp.ov_context(office,approved));
$$;
create function pg_temp.ov_call(args jsonb) returns jsonb language plpgsql as $$
declare request_id uuid := gen_random_uuid(); result jsonb;
begin
  set local role service_role;
  perform pg_temp.ov_mint(request_id,args);
  reset role;
  set local role authenticated;
  result := public.rm_web_workshop_read_v1(request_id,'operation_validation',args);
  reset role;
  perform pg_temp.ov_check(result->>'request_id'=request_id::text and result->>'resource'='operation_validation'
    and result->>'workshop_id'=pg_temp.ov_id(1)::text,'permit consumed only for exact query and office');
  return result->'data';
exception when others then reset role; raise;
end;
$$;

-- Exact policy identifiers are populated only with synthetic local accounts.
select rm_private.workshop_adopt_bma_roots_v1(
  '[{"id":"06210000-0000-4000-8000-000000000001","code":"BMA"},{"id":"06210000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"06210000-0000-4000-8000-000000000003","code":"BBH"}]',
  'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
  (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));

insert into auth.users(id) values(pg_temp.ov_id(101)),(pg_temp.ov_id(102));
insert into auth.sessions(id,user_id) values(pg_temp.ov_id(111),pg_temp.ov_id(101)),(pg_temp.ov_id(112),pg_temp.ov_id(102));
insert into public.rm_users(id,auth_user_id,nome,perfil,matricula) values
  ('2e70c7e9-3ed2-47fa-9860-9501aeac96cc',pg_temp.ov_id(101),'Administrador local autorizado','administrador','WEB-SOFTDEV05'),
  (pg_temp.ov_id(105),pg_temp.ov_id(102),'Administrador local sem validação','administrador','LOCAL-ADMIN'),
  ('23c4787b-eb5b-44ed-abbc-547e358e2f6f',null,'Operador local vinculado','administrador','05');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
  ('ae29e9a9-9c50-4d25-81eb-6a01202bc20a','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','a9e45880-1924-4b2d-a2b1-dc12fd029bff',
   '2e70c7e9-3ed2-47fa-9860-9501aeac96cc',pg_temp.ov_id(101),true,'2e70c7e9-3ed2-47fa-9860-9501aeac96cc',clock_timestamp()),
  (pg_temp.ov_id(109),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.ov_id(110),pg_temp.ov_id(105),pg_temp.ov_id(102),
   true,pg_temp.ov_id(105),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('6',64),'ae29e9a9-9c50-4d25-81eb-6a01202bc20a',pg_temp.ov_id(111),
  'opaque-local-validation-session',clock_timestamp()+interval '30 minutes');
select public.rm_sso_session_put_v1(repeat('7',64),pg_temp.ov_id(109),pg_temp.ov_id(112),
  'opaque-local-unapproved-session',clock_timestamp()+interval '30 minutes');

insert into public.rm_celulas(id,nome) values
  (pg_temp.ov_id(201),'Célula concedida'),(pg_temp.ov_id(202),'Célula da outra oficina'),
  (pg_temp.ov_id(203),'Célula sem classificação'),(pg_temp.ov_id(204),'Célula local sem concessão');
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values
  (pg_temp.ov_id(201),pg_temp.ov_id(1)),(pg_temp.ov_id(202),pg_temp.ov_id(2)),(pg_temp.ov_id(204),pg_temp.ov_id(1));
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values
  (pg_temp.ov_id(201),'2e70c7e9-3ed2-47fa-9860-9501aeac96cc','23c4787b-eb5b-44ed-abbc-547e358e2f6f'),
  (pg_temp.ov_id(202),'2e70c7e9-3ed2-47fa-9860-9501aeac96cc','23c4787b-eb5b-44ed-abbc-547e358e2f6f'),
  (pg_temp.ov_id(203),'2e70c7e9-3ed2-47fa-9860-9501aeac96cc','23c4787b-eb5b-44ed-abbc-547e358e2f6f');

insert into public.rm_projetos(id,numero,nome,data_real_de_entrega,arquivo_nota_fiscal_url)
  select pg_temp.ov_id(300+n),'OS-'||n,'Projeto local '||n,case when n=6 then clock_timestamp() end,'https://private.invalid/dados'
  from generate_series(1,7) n;
insert into rm_private.workshop_project_ownership(id,workshop_id)
  select pg_temp.ov_id(300+n),pg_temp.ov_id(case when n=2 then 2 else 1 end)
  from generate_series(1,7) n where n<>3;
insert into public.rm_forms(id,titulo,ativo) values
  (pg_temp.ov_id(401),'Modelo local ativo',true),(pg_temp.ov_id(402),'Modelo sem classificação',true),
  (pg_temp.ov_id(403),'Modelo local inativo',false);
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values
  ('form_model',pg_temp.ov_id(401),pg_temp.ov_id(1)),('form_model',pg_temp.ov_id(403),pg_temp.ov_id(1));
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,retirada,posicao,status,forms_ids)
  select pg_temp.ov_id(500+n),pg_temp.ov_id(300+n),pg_temp.ov_id(case n when 2 then 202 when 7 then 204 else 201 end),
    n not in (4,5),n=5,n,'em_dia',case when n=1 then array[pg_temp.ov_id(402),pg_temp.ov_id(401),pg_temp.ov_id(403)] else '{}' end
  from generate_series(1,7) n;

select set_config('request.jwt.claim.sub',pg_temp.ov_id(101)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.ov_id(111),'aal','aal1')::text,true);

do $$
declare r jsonb;
begin
  r := pg_temp.ov_call(pg_temp.ov_args());
  perform pg_temp.ov_check(r->>'kind'='cells' and jsonb_array_length(r->'items')=1
    and r->'items'->0->>'id'=pg_temp.ov_id(201)::text,'operational validation requires explicit grants even for an administrator');
  r := pg_temp.ov_call(pg_temp.ov_args(201));
  perform pg_temp.ov_check(r->>'kind'='projects' and (r->>'total')::int=1
    and (r->>'page_size')::int=25 and r->'items'->0->>'id'=pg_temp.ov_id(301)::text,
    'only active, visible, nonretired and classified projects are counted');
  r := pg_temp.ov_call(pg_temp.ov_args(201,null,2));
  perform pg_temp.ov_check((r->>'total')::int=1 and jsonb_array_length(r->'items')=0,'pagination counts scoped results');
  r := pg_temp.ov_call(pg_temp.ov_args(201,301));
  perform pg_temp.ov_check(r->>'kind'='project' and r->'project'->>'id'=pg_temp.ov_id(301)::text
    and jsonb_array_length(r->'forms')=1 and r->'forms'->0->>'id'=pg_temp.ov_id(401)::text
    and strpos(r::text,'private.invalid')=0,'same scoped project DTO and only active owned models');
  perform pg_temp.ov_check(pg_temp.ov_call(pg_temp.ov_args(202))='null'::jsonb
    and pg_temp.ov_call(pg_temp.ov_args(203))='null'::jsonb and pg_temp.ov_call(pg_temp.ov_args(204))='null'::jsonb
    and pg_temp.ov_call(pg_temp.ov_args(201,302))='null'::jsonb and pg_temp.ov_call(pg_temp.ov_args(201,303))='null'::jsonb,
    'cross-office, unknown and explicitly ungranted identifiers are all absent');
end;
$$;

set local role service_role;
select pg_temp.ov_deny($sql$select pg_temp.ov_mint(pg_temp.ov_id(601),pg_temp.ov_args(),2)$sql$,'42501');
select pg_temp.ov_deny($sql$select pg_temp.ov_mint(pg_temp.ov_id(601),pg_temp.ov_args(),4)$sql$,'42501');
select pg_temp.ov_deny($sql$select pg_temp.ov_mint(pg_temp.ov_id(601),pg_temp.ov_args(),1,false)$sql$,'42501');
select pg_temp.ov_mint(pg_temp.ov_id(601),pg_temp.ov_args());
select pg_temp.ov_mint(pg_temp.ov_id(602),pg_temp.ov_args());
reset role;

set local role authenticated;
select pg_temp.ov_deny($sql$select pg_temp.ov_mint(pg_temp.ov_id(603),pg_temp.ov_args())$sql$,'42501');
select pg_temp.ov_deny($sql$select public.rm_web_workshop_read_v1(pg_temp.ov_id(601),'operation_validation',pg_temp.ov_args(201))$sql$,'42501');
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.ov_id(112),'aal','aal1')::text,true);
select pg_temp.ov_deny($sql$select public.rm_web_workshop_read_v1(pg_temp.ov_id(601),'operation_validation',pg_temp.ov_args())$sql$,'42501');
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.ov_id(111),'aal','aal1')::text,true);
select pg_temp.ov_check((public.rm_web_workshop_read_v1(pg_temp.ov_id(601),'operation_validation',pg_temp.ov_args())->'data'->>'kind')='cells',
  'server-issued single-use permit works with the correct JWT session');
select pg_temp.ov_deny($sql$select public.rm_web_workshop_read_v1(pg_temp.ov_id(601),'operation_validation',pg_temp.ov_args())$sql$,'42501');
reset role;

select pg_temp.ov_deny($sql$select pg_temp.ov_call(pg_temp.ov_args() || '{"office":"BMA"}')$sql$,'22023');
select pg_temp.ov_deny($sql$select pg_temp.ov_call(pg_temp.ov_args(null,301))$sql$,'22023');
select pg_temp.ov_deny($sql$select pg_temp.ov_call(pg_temp.ov_args(null,null,10001))$sql$,'22023');

update public.rm_users set status='inativo' where id='23c4787b-eb5b-44ed-abbc-547e358e2f6f';
set local role authenticated;
select pg_temp.ov_deny($sql$select public.rm_web_workshop_read_v1(pg_temp.ov_id(602),'operation_validation',pg_temp.ov_args())$sql$,'42501');
reset role;
set local role service_role;
select pg_temp.ov_deny($sql$select pg_temp.ov_mint(pg_temp.ov_id(603),pg_temp.ov_args())$sql$,'42501');
reset role;
update public.rm_users set status='ativo' where id='23c4787b-eb5b-44ed-abbc-547e358e2f6f';
delete from public.rm_tablet_celula_users where celula_id=pg_temp.ov_id(201);
select pg_temp.ov_check(pg_temp.ov_call(pg_temp.ov_args())->'items'='[]'::jsonb,'removing an explicit cell grant immediately removes access');

select pg_temp.ov_check(
  not has_function_privilege('anon','public.rm_web_workshop_read_v1(uuid,text,jsonb)','EXECUTE')
  and has_function_privilege('authenticated','public.rm_web_workshop_read_v1(uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('authenticated','public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)','EXECUTE')
  and has_function_privilege('service_role','public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)','EXECUTE')
  and not has_function_privilege('authenticated','public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer)','EXECUTE')
  and has_function_privilege('service_role','public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer)','EXECUTE')
  and not has_function_privilege('service_role','rm_private.online_operation_projection_v1(uuid,uuid,uuid,uuid,integer,uuid[])','EXECUTE')
  and not has_function_privilege('authenticated','rm_private.online_operation_validation_v1(uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),
  'legacy RPC roles and public read permit topology stay unchanged');

rollback;
select 'PASS: named operation validation, explicit cells, safe projection, permit roles and revocation' result;

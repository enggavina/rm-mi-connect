\set ON_ERROR_STOP on
begin;

create function pg_temp.online_id(n int) returns uuid language sql immutable as $$
  select ('06110000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid;
$$;

create function pg_temp.online_check(ok boolean, assertion text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %', assertion; end if;
end;
$$;

create function pg_temp.online_context(n int) returns jsonb language sql stable as $$
  select jsonb_build_object('version',2,'application','em','channel','mobile',
    'authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
    'workshop',jsonb_build_object('id',pg_temp.online_id(n),'code',(array['BMA','BRJ','BBH'])[n],
      'name','Oficina local','active',true,'revision',1,'updated_at',stamp),
    'principals',jsonb_build_array(
      jsonb_build_object('kind','device','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1','subject',pg_temp.online_id(10+n),'revision',1),
      jsonb_build_object('kind','operator','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1','subject',pg_temp.online_id(40+n),'revision',1)),
    'issued_at',stamp,'expires_at',stamp + interval '5 minutes')
  from (select statement_timestamp() stamp) timing;
$$;

create function pg_temp.online_call(n int, cell int default null, project int default null, page int default 1)
returns jsonb language plpgsql as $$
declare reply jsonb;
begin
  set local role service_role;
  reply := public.rm_online_operation_read_v1(pg_temp.online_id(10+n),pg_temp.online_id(20+n),repeat(n::text,64),
    pg_temp.online_context(n),pg_temp.online_id(cell),pg_temp.online_id(project),page);
  reset role;
  return reply;
exception when others then reset role; raise;
end;
$$;

select rm_private.workshop_adopt_bma_roots_v1(
  '[{"id":"06110000-0000-4000-8000-000000000001","code":"BMA"},{"id":"06110000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"06110000-0000-4000-8000-000000000003","code":"BBH"}]',
  'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
  (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));

insert into auth.users(id) select pg_temp.online_id(10+n) from generate_series(1,3) n;
insert into auth.sessions(id,user_id) select pg_temp.online_id(20+n),pg_temp.online_id(10+n) from generate_series(1,3) n;
insert into public.rm_users(id,auth_user_id,nome,perfil)
  select pg_temp.online_id(30+n),pg_temp.online_id(10+n),'Tablet local '||n,'mobile' from generate_series(1,3) n;
insert into public.rm_users(id,nome,perfil)
  select pg_temp.online_id(40+n),'Operador local '||n,case when n=2 then 'administrador' else 'mobile' end::public.rm_perfil_usuario_enum
  from generate_series(1,3) n;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
  select extensions.digest(repeat(n::text,64),'sha256'),pg_temp.online_id(10+n),pg_temp.online_id(30+n),pg_temp.online_id(40+n),clock_timestamp()+interval '2 days'
  from generate_series(1,3) n;

insert into public.rm_celulas(id,nome) select pg_temp.online_id(100+n),'Célula local '||n from generate_series(1,5) n;
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id)
  select pg_temp.online_id(100+n),pg_temp.online_id(case when n<=3 then n else 1 end) from generate_series(1,4) n;
-- The BMA operator carries an old grant in BRJ and one on a cell with no proven owner.
-- Neither grant enlarges the result of the current Central context.
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values
  (pg_temp.online_id(101),pg_temp.online_id(31),pg_temp.online_id(41)),
  (pg_temp.online_id(102),pg_temp.online_id(31),pg_temp.online_id(41)),
  (pg_temp.online_id(103),pg_temp.online_id(33),pg_temp.online_id(43)),
  (pg_temp.online_id(105),pg_temp.online_id(31),pg_temp.online_id(41));

insert into public.rm_clientes(id,nome) values (pg_temp.online_id(301),'Cliente local'),(pg_temp.online_id(302),'Cliente pendente');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id)
  values ('client',pg_temp.online_id(301),pg_temp.online_id(1));
insert into public.rm_projetos(id,numero,nome,cliente_id,arquivo_nota_fiscal_url,data_real_de_entrega)
  select pg_temp.online_id(200+n),'OS-'||n,'Projeto local '||n,pg_temp.online_id(case when n=1 then 301 when n=5 then 302 end),
    'https://private.invalid/invoice',case when n=6 then clock_timestamp() end from generate_series(1,32) n;
insert into rm_private.workshop_project_ownership(id,workshop_id)
  select pg_temp.online_id(200+n),pg_temp.online_id(case when n in (2,3) then n else 1 end)
  from generate_series(1,32) n where n<>4;
insert into public.rm_equipamentos(id,projeto_id,descricao)
  values (pg_temp.online_id(351),pg_temp.online_id(201),'Bomba de teste');
update public.rm_projetos set equipamento_id=pg_temp.online_id(351) where id=pg_temp.online_id(201);

insert into public.rm_forms(id,titulo,ativo) values
  (pg_temp.online_id(401),'Formulário local',true),(pg_temp.online_id(402),'Formulário pendente',true),
  (pg_temp.online_id(403),'Formulário inativo',false);
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values
  ('form_model',pg_temp.online_id(401),pg_temp.online_id(1)),('form_model',pg_temp.online_id(403),pg_temp.online_id(1));

insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,retirada,posicao,status,forms_ids)
  select pg_temp.online_id(500+n),pg_temp.online_id(200+n),pg_temp.online_id(case when n in (2,3) then 100+n else 101 end),
    n not in(7,8),n=8,n,case when n=9 then 'retornado' else 'em_dia' end::public.rm_status_cel_proj_enum,
    case when n=1 then array[pg_temp.online_id(402),pg_temp.online_id(401),pg_temp.online_id(403)] else '{}' end
  from generate_series(1,32) n;

do $$
declare identity jsonb; result jsonb; n int; other int; context jsonb;
begin
  set local role service_role;
  identity := public.rm_online_operator_identity_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64));
  reset role;
  perform pg_temp.online_check(identity->>'device_subject'=pg_temp.online_id(11)::text
    and identity->>'operator_subject'=pg_temp.online_id(41)::text and identity->>'operator_name'='Operador local 1'
    and (identity->>'expires_at')::timestamptz <= clock_timestamp()+interval '24 hours','password account and identified operator are independent');

  for n in 1..3 loop
    result := pg_temp.online_call(n);
    perform pg_temp.online_check(result->>'kind'='cells' and jsonb_array_length(result->'items')=1
      and result->'items'->0->>'id'=pg_temp.online_id(100+n)::text,'each office gets its own available cell');
    result := pg_temp.online_call(n,100+n,200+n);
    perform pg_temp.online_check(result->>'kind'='project' and result->'project'->>'id'=pg_temp.online_id(200+n)::text,'each office opens its own project');
    for other in 1..3 loop
      if n<>other then
        perform pg_temp.online_check(pg_temp.online_call(n,100+other) is null
          and pg_temp.online_call(n,100+n,200+other) is null,'cross-office cell and project UUIDs are absent');
      end if;
    end loop;
  end loop;

  result := pg_temp.online_call(1,101);
  perform pg_temp.online_check(result->>'kind'='projects' and (result->>'page_size')::int=25
    and (result->>'total')::int=26 and jsonb_array_length(result->'items')=25
    and result->'items'->0->>'id'=pg_temp.online_id(209)::text,'only visible, nonretired, active and owned projects are counted; returns first');
  result := pg_temp.online_call(1,101,null,2);
  perform pg_temp.online_check((result->>'total')::int=26 and jsonb_array_length(result->'items')=1,'page 2 uses total after scoping');
  result := pg_temp.online_call(1,101,201);
  perform pg_temp.online_check(result->'project'->>'descricao'='Bomba de teste' and result->'project'->>'cliente'='Cliente local'
    and jsonb_array_length(result->'forms')=1 and result->'forms'->0->>'id'=pg_temp.online_id(401)::text
    and strpos(result::text,'private.invalid')=0,'details join only owned catalogs and redact media URLs');
  perform pg_temp.online_check(pg_temp.online_call(1,101,205)->'project'->>'cliente' is null,'unclassified client catalog entries are omitted');
  perform pg_temp.online_check(pg_temp.online_call(1,104) is null and pg_temp.online_call(1,105) is null
    and pg_temp.online_call(1,101,204) is null and pg_temp.online_call(1,null,201) is null
    and pg_temp.online_call(1,101,null,0) is null,'own office alone is insufficient without cell grants and project ownership');

  context := pg_temp.online_context(1);
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(22),repeat('1',64),
    context,null,null,1) is null,'mismatched session is refused');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('2',64),
    context,null,null,1) is null,'operator grant of a different tablet is refused');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),
    pg_temp.online_context(2),null,null,1) is null,'office context of a different identity is refused');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),
    jsonb_set(context,'{workshop,code}','"BRJ"'),null,null,1) is null,'workshop id and code both match the registered authority');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),
    jsonb_set(context,'{workshop,active}','false'),null,null,1) is null,'disabled office denies access');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),
    jsonb_set(context,'{issued_at}',to_jsonb(statement_timestamp()-interval '1 minute')),null,null,1) is null,'stale context denies access');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),
    jsonb_set(context,'{principals,1,kind}','"device"'),null,null,1) is null,'device and operator principal roles are fixed');
  perform pg_temp.online_check(public.rm_online_operation_read_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),
    jsonb_set(context,'{expires_at}','"not-a-date"'),null,null,1) is null,'malformed authority does not open a default scope');
end;
$$;

update rm_private.operator_delegations set revoked=true where operator_id=pg_temp.online_id(41);
select pg_temp.online_check(pg_temp.online_call(1) is null,'revoked operator grant is refused');
update public.rm_users set status='inativo' where id=pg_temp.online_id(42);
select pg_temp.online_check(pg_temp.online_call(2) is null,'inactive operator is refused');
delete from auth.sessions where id=pg_temp.online_id(23);
select pg_temp.online_check(pg_temp.online_call(3) is null,'revoked device session is refused');

select pg_temp.online_check(
  not has_function_privilege('anon','public.rm_online_operator_identity_v1(uuid,uuid,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.rm_online_operator_identity_v1(uuid,uuid,text)','EXECUTE')
  and not has_function_privilege('anon','public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer)','EXECUTE')
  and not has_function_privilege('authenticated','public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer)','EXECUTE')
  and has_function_privilege('service_role','public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer)','EXECUTE')
  and not has_function_privilege('service_role','rm_private.online_workshop_context_v1(jsonb,uuid,uuid)','EXECUTE'),
  'only the trusted server may invoke the new online RPCs');

rollback;
select 'PASS: online operation reads with three workshops, active cells and projects, fresh delegation, scoped catalogs and ACLs' result;

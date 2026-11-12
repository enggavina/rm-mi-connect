\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create function pg_temp.ex_id(n integer) returns uuid language sql immutable as $$select('ee430000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.ex_check(value boolean,message text) returns void language plpgsql as $$begin if value is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
create function pg_temp.ex_actor(user_id uuid,aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',coalesce(user_id::text,''),true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal',aal)::text,true);
end$$;
create function pg_temp.ex_read(cells uuid[],fields text[]) returns jsonb language plpgsql as $$declare result jsonb;begin
 set local role authenticated;result:=public.rm_web_planning_export_snapshot_v1(cells,fields);reset role;return result;
exception when others then reset role;raise;end$$;
create function pg_temp.ex_reject(cells uuid[],fields text[],expected text) returns void language plpgsql as $$declare state text;begin
 begin perform pg_temp.ex_read(cells,fields);raise exception 'FAIL: export unexpectedly accepted';exception when others then
  get stacked diagnostics state=returned_sqlstate;if state<>expected then raise exception 'FAIL: expected SQLSTATE %, got % (%)',expected,state,sqlerrm;end if;
 end;
end$$;
insert into auth.users(id) values(pg_temp.ex_id(1)),(pg_temp.ex_id(3)),(pg_temp.ex_id(5)),(pg_temp.ex_id(7)),(pg_temp.ex_id(9));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 (pg_temp.ex_id(2),pg_temp.ex_id(1),'Export administrator','administrador','ativo'),
 (pg_temp.ex_id(4),pg_temp.ex_id(3),'Export mobile','mobile','ativo'),
 (pg_temp.ex_id(6),pg_temp.ex_id(5),'Export auditor','auditor','ativo'),
 (pg_temp.ex_id(8),pg_temp.ex_id(7),'Export planner','padr_o','ativo'),
 (pg_temp.ex_id(22),pg_temp.ex_id(9),'Export inactive','administrador','inativo');
insert into public.rm_clientes(id,nome) values(pg_temp.ex_id(20),'Cliente atual');
insert into public.rm_tipos_equipamento(id,nome,sigla) values(pg_temp.ex_id(300),'Motor elétrico','MOTOR'),(pg_temp.ex_id(301),'Tipo legado do projeto','LEGADO');
insert into public.rm_celulas(id,nome) values(pg_temp.ex_id(10),'Montagem'),(pg_temp.ex_id(11),'Testes'),(pg_temp.ex_id(12),'Pintura não selecionada'),(pg_temp.ex_id(13),'Célula sem alocações'),(pg_temp.ex_id(14),'Célula de volume');
insert into public.rm_projetos(id,numero,nome,cliente_id,cliente_nome_exportacao,tipo_equipamento_id,gestor_responsavel_id,escopo_abreviado,status_pcp,data_real_de_entrega)
 select pg_temp.ex_id(100+n),'EXPORT-'||n,'Projeto '||n,pg_temp.ex_id(20),'Cliente antigo',pg_temp.ex_id(301),pg_temp.ex_id(2),'Escopo real',case when n=7 then 'cancelado'::public.rm_status_pcp_enum end,
 case when n=7 then '2026-11-10T12:00:00Z'::timestamptz end from generate_series(0,8)n;
insert into public.rm_equipamentos(id,projeto_id,tipo_equipamento_id,descricao,fabricante,modelo,numero_serie,potencia,placa_motor)
 values(pg_temp.ex_id(200),pg_temp.ex_id(100),pg_temp.ex_id(300),'Motor do equipamento','Fabricante real','Modelo real','0000123','75 kW','c___placa'),
 (pg_temp.ex_id(201),pg_temp.ex_id(103),pg_temp.ex_id(300),'Equipamento de outro projeto','Não exportar',null,null,null,null),
 (pg_temp.ex_id(202),pg_temp.ex_id(104),pg_temp.ex_id(300),'Equipamento compartilhado','Não exportar',null,null,null,null),
 (pg_temp.ex_id(203),pg_temp.ex_id(106),null,'Equipamento sem tipo','Fabricante sem tipo',null,null,null,null);
-- Simulate pre-existing inconsistent legacy links without changing production
-- guards. The complete fixture and trigger state are rolled back below.
alter table public.rm_projetos disable trigger user;
update public.rm_projetos set equipamento_id=case id
 when pg_temp.ex_id(100) then pg_temp.ex_id(200) when pg_temp.ex_id(102) then pg_temp.ex_id(201)
 when pg_temp.ex_id(104) then pg_temp.ex_id(202) when pg_temp.ex_id(105) then pg_temp.ex_id(202)
 when pg_temp.ex_id(106) then pg_temp.ex_id(203) end
 where id in(pg_temp.ex_id(100),pg_temp.ex_id(102),pg_temp.ex_id(104),pg_temp.ex_id(105),pg_temp.ex_id(106));
alter table public.rm_projetos enable trigger user;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,posicao,retirada,responsavel_id,horas_previstas,horas_realizadas,data_inicio,data_limite,observacao)
 values
 (pg_temp.ex_id(500),pg_temp.ex_id(100),pg_temp.ex_id(10),'aguardando_coleta',false,2,false,pg_temp.ex_id(8),3.25,1.5,'2026-11-12T12:00:00Z','2026-11-20T12:00:00Z','Observação real'),
 (pg_temp.ex_id(501),pg_temp.ex_id(100),pg_temp.ex_id(11),'coletado',true,1,false,pg_temp.ex_id(8),4,2,null,null,null),
 (pg_temp.ex_id(502),pg_temp.ex_id(101),pg_temp.ex_id(10),'pendente',true,3,false,null,null,null,null,null,null),
 (pg_temp.ex_id(503),pg_temp.ex_id(102),pg_temp.ex_id(10),'pendente',true,4,false,null,null,null,null,null,null),
 (pg_temp.ex_id(504),pg_temp.ex_id(104),pg_temp.ex_id(10),'pendente',true,5,false,null,null,null,null,null,null),
 (pg_temp.ex_id(505),pg_temp.ex_id(106),pg_temp.ex_id(10),'pendente',true,6,false,null,null,null,null,null,null),
 (pg_temp.ex_id(506),pg_temp.ex_id(107),pg_temp.ex_id(10),'finalizado',false,7,false,null,null,null,null,null,null),
 (pg_temp.ex_id(507),pg_temp.ex_id(101),pg_temp.ex_id(12),'pendente',true,1,false,null,null,null,null,null,null),
 (pg_temp.ex_id(508),pg_temp.ex_id(101),pg_temp.ex_id(11),'pendente',false,3,true,null,null,null,null,null,null);
select pg_temp.ex_actor(pg_temp.ex_id(1));
do $$declare result jsonb;first_values jsonb;begin
 result:=pg_temp.ex_read(array[pg_temp.ex_id(10)],array['project_number','cell_name','allocation_status','equipment_type','equipment_description','manufacturer','serial_number','power','motor_plate','client_name','project_manager','allocation_responsible','planned_hours','actual_hours','visible','allocation_start']);
 perform pg_temp.ex_check((result->>'complete')::boolean and result->>'row_count'='6' and jsonb_array_length(result->'cells')=1,'all current allocations exported, including hidden and closed');
 perform pg_temp.ex_check(result->'cells'->0->>'id'=pg_temp.ex_id(10)::text and result->'cells'->0->>'name'='Montagem','one sheet uses selected cell only');
 first_values:=result->'cells'->0->'rows'->0->'values';
 perform pg_temp.ex_check(first_values->>'project_number'='EXPORT-0' and first_values->>'cell_name'='Montagem','canonical project and cell labels');
 perform pg_temp.ex_check(first_values->>'allocation_status'='Aguardando coleta','new waiting-collection status is legible');
 perform pg_temp.ex_check(first_values->>'equipment_type'='MOTOR - Motor elétrico' and first_values->>'equipment_description'='Motor do equipamento','type comes from exact equipment relation, not project legacy type');
 perform pg_temp.ex_check(first_values->>'manufacturer'='Fabricante real' and first_values->>'serial_number'='0000123' and first_values->>'power'='75 kW','real equipment fields preserve text, units and leading zeros');
 perform pg_temp.ex_check(first_values->>'motor_plate'='C / placa' and first_values->>'client_name'='Cliente atual' and first_values->>'project_manager'='Export administrator' and first_values->>'allocation_responsible'='Export planner','readable relationship and option labels');
 perform pg_temp.ex_check(first_values->'planned_hours'='3.25'::jsonb and first_values->'actual_hours'='1.5'::jsonb and first_values->>'visible'='Não','allocation values and numeric types preserved');
 perform pg_temp.ex_check(first_values->>'allocation_start' is not null,'allocation date included');
 perform pg_temp.ex_check(result->'cells'->0->'rows'->1->'values'->'equipment_type'='null'::jsonb,'legacy project type is never substituted for missing equipment');
 perform pg_temp.ex_check(result->'cells'->0->'rows'->2->'values'->'equipment_type'='null'::jsonb and result->'cells'->0->'rows'->2->'values'->'manufacturer'='null'::jsonb,'wrong reverse equipment link exports empty values');
 perform pg_temp.ex_check(result->'cells'->0->'rows'->3->'values'->'equipment_description'='null'::jsonb,'shared equipment is not selected arbitrarily');
 perform pg_temp.ex_check(result->'cells'->0->'rows'->4->'values'->'equipment_type'='null'::jsonb and result->'cells'->0->'rows'->4->'values'->>'equipment_description'='Equipamento sem tipo','equipment without type stays readable without fallback');
 result:=pg_temp.ex_read(array[pg_temp.ex_id(11),pg_temp.ex_id(10)],array['allocation_status','project_number']);
 perform pg_temp.ex_check(result->>'row_count'='7' and jsonb_array_length(result->'cells')=2,'multiple cells preserve one row per allocation');
 perform pg_temp.ex_check(result->'cells'->0->>'id'=pg_temp.ex_id(11)::text and result->'cells'->1->>'id'=pg_temp.ex_id(10)::text,'selection order is preserved');
 perform pg_temp.ex_check(result->'cells'->0->'rows'->0->>'project_id'=result->'cells'->1->'rows'->0->>'project_id','same project is present in each of its selected cells');
 perform pg_temp.ex_check(result->'cells'->0->'rows'->0->'values'->>'allocation_status'='Coletado','collected status is legible');
 perform pg_temp.ex_check((select count(*)=2 from jsonb_object_keys(result->'cells'->0->'rows'->0->'values')) and result->'fields'='["allocation_status","project_number"]'::jsonb,'only selected fields are projected, in requested order');
 result:=pg_temp.ex_read(array[pg_temp.ex_id(13)],array['cell_name']);
 perform pg_temp.ex_check(result->>'row_count'='0' and jsonb_array_length(result->'cells')=1 and result->'cells'->0->'rows'='[]'::jsonb,'an empty selected cell still has an empty worksheet context');
end$$;
select pg_temp.ex_reject(null,array['project_number'],'22023');
select pg_temp.ex_reject('{}',array['project_number'],'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],'{}','22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number','project_number'],'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['unknown_field'],'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number',null],'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],null,'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array_fill('project_number'::text,array[44]),'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10),null],array['project_number'],'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(10),pg_temp.ex_id(10)],array['project_number'],'22023');
select pg_temp.ex_reject(array[pg_temp.ex_id(999)],array['project_number'],'42501');
select pg_temp.ex_reject(array(select pg_temp.ex_id(10000+n) from generate_series(1,201)n),array['project_number'],'22023');
select pg_temp.ex_reject(array[[pg_temp.ex_id(10)],[pg_temp.ex_id(11)]],array['project_number'],'22023');
select pg_temp.ex_actor(null);
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number'],'42501');
select pg_temp.ex_actor(pg_temp.ex_id(3));
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number'],'42501');
select pg_temp.ex_actor(pg_temp.ex_id(9));
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number'],'42501');
select pg_temp.ex_actor(pg_temp.ex_id(5));
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['project_number'])->>'row_count'='6','auditor can export data they may read');
select pg_temp.ex_actor(pg_temp.ex_id(7));
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['project_number'])->>'row_count'='6','planner can export data they may read');
select pg_temp.ex_actor(pg_temp.ex_id(1));
insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.ex_id(1),'totp','verified');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number'],'42501');
select pg_temp.ex_actor(pg_temp.ex_id(1),'aal2');
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['project_number'])->>'row_count'='6','current MFA context permits export');
select pg_temp.ex_check((select not prosecdef and provolatile='s' from pg_proc where oid='public.rm_web_planning_export_snapshot_v1(uuid[],text[])'::regprocedure),'snapshot stays stable security invoker');
select pg_temp.ex_check(has_function_privilege('authenticated','public.rm_web_planning_export_snapshot_v1(uuid[],text[])','EXECUTE') and not has_function_privilege('anon','public.rm_web_planning_export_snapshot_v1(uuid[],text[])','EXECUTE') and not has_function_privilege('service_role','public.rm_web_planning_export_snapshot_v1(uuid[],text[])','EXECUTE'),'only authenticated role receives public snapshot execution');
create policy export_test_hidden_cell on public.rm_celulas as restrictive for select to authenticated using(id<>'ee430000-0000-4000-8000-000000000011');
select pg_temp.ex_reject(array[pg_temp.ex_id(10),pg_temp.ex_id(11)],array['project_number'],'42501');
drop policy export_test_hidden_cell on public.rm_celulas;
create policy export_test_hidden_project on public.rm_projetos as restrictive for select to authenticated using(id<>'ee430000-0000-4000-8000-000000000100');
select pg_temp.ex_reject(array[pg_temp.ex_id(10)],array['project_number'],'42501');
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(12)],array['project_number'])->>'row_count'='1','RLS-hidden projects never leak through another selected cell');
drop policy export_test_hidden_project on public.rm_projetos;
create policy export_test_hidden_equipment on public.rm_equipamentos as restrictive for select to authenticated using(id<>'ee430000-0000-4000-8000-000000000200');
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['equipment_type','manufacturer'])->'cells'->0->'rows'->0->'values'='{"equipment_type":null,"manufacturer":null}'::jsonb,'equipment RLS cannot be bypassed by the export');
drop policy export_test_hidden_equipment on public.rm_equipamentos;
create policy export_test_hidden_type on public.rm_tipos_equipamento as restrictive for select to authenticated using(id<>'ee430000-0000-4000-8000-000000000300');
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['equipment_type'])->'cells'->0->'rows'->0->'values'->'equipment_type'='null'::jsonb,'equipment type RLS cannot be bypassed');
drop policy export_test_hidden_type on public.rm_tipos_equipamento;
create policy export_test_hidden_allocation on public.rm_celulas_projeto as restrictive for select to authenticated using(id<>'ee430000-0000-4000-8000-000000000500');
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['project_number'])->>'row_count'='5','allocation RLS omits unauthorized allocation rows');
drop policy export_test_hidden_allocation on public.rm_celulas_projeto;
-- A reference hidden by project RLS still makes an equipment link ambiguous.
create policy export_test_hidden_shared_reference on public.rm_projetos as restrictive for select to authenticated using(id<>'ee430000-0000-4000-8000-000000000105');
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(10)],array['equipment_description'])->'cells'->0->'rows'->3->'values'->'equipment_description'='null'::jsonb,'opaque shared-equipment proof is complete even when the other project is hidden');
drop policy export_test_hidden_shared_reference on public.rm_projetos;
do $$declare shared uuid[];begin
 set local role authenticated;shared:=rm_private.web_export_shared_equipment_v1(array['ee430000-0000-4000-8000-000000000200','ee430000-0000-4000-8000-000000000202']::uuid[]);reset role;
 perform pg_temp.ex_check(shared=array[pg_temp.ex_id(202)],'opaque proof returns only supplied ambiguous equipment IDs, never hidden project identities');
end$$;
-- Bulk fixtures intentionally skip application write triggers while seeding;
-- reads run with every application trigger enabled and real RLS afterwards.
alter table public.rm_projetos disable trigger user;
alter table public.rm_celulas_projeto disable trigger user;
insert into public.rm_projetos(id,numero) select pg_temp.ex_id(100000+n),'VOLUME-'||n from generate_series(1,1005)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) select pg_temp.ex_id(200000+n),pg_temp.ex_id(100000+n),pg_temp.ex_id(14),'pendente' from generate_series(1,1005)n;
alter table public.rm_celulas_projeto enable trigger user;
alter table public.rm_projetos enable trigger user;
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(14)],array['project_number'])->>'row_count'='1005','more than one thousand rows are returned without PostgREST-style truncation');
alter table public.rm_celulas_projeto disable trigger user;
update public.rm_celulas_projeto set observacao=repeat('A',21000) where celula_id=pg_temp.ex_id(14);
alter table public.rm_celulas_projeto enable trigger user;
select pg_temp.ex_reject(array[pg_temp.ex_id(14)],array['allocation_note'],'PT413');
alter table public.rm_celulas_projeto disable trigger user;
update public.rm_celulas_projeto set observacao=null where celula_id=pg_temp.ex_id(14);
alter table public.rm_projetos disable trigger user;
insert into public.rm_projetos(id,numero) select pg_temp.ex_id(100000+n),'VOLUME-'||n from generate_series(1006,20000)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) select pg_temp.ex_id(200000+n),pg_temp.ex_id(100000+n),pg_temp.ex_id(14),'pendente' from generate_series(1006,20000)n;
alter table public.rm_celulas_projeto enable trigger user;
alter table public.rm_projetos enable trigger user;
select pg_temp.ex_check(pg_temp.ex_read(array[pg_temp.ex_id(14)],array['project_number'])->>'row_count'='20000','the twenty-thousand-row limit is inclusive and never returns a partial success');
alter table public.rm_projetos disable trigger user;
alter table public.rm_celulas_projeto disable trigger user;
insert into public.rm_projetos(id,numero) values(pg_temp.ex_id(120001),'VOLUME-20001');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) values(pg_temp.ex_id(220001),pg_temp.ex_id(120001),pg_temp.ex_id(14),'pendente');
alter table public.rm_celulas_projeto enable trigger user;
alter table public.rm_projetos enable trigger user;
select pg_temp.ex_reject(array[pg_temp.ex_id(14)],array['project_number'],'PT413');
select pg_temp.ex_check((select status_pcp is null from public.rm_projetos where id=pg_temp.ex_id(100)),'reading cell statuses never changes project status');
rollback;
select 'PASS: planning export field/cell selection, exact equipment, legacy/shared/RLS/MFA authorization, new status labels, closed/hidden/retired semantics and bounded volume' result;

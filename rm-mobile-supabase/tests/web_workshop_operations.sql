\set ON_ERROR_STOP on
begin;

create function pg_temp.project_read_id(n int) returns uuid language sql immutable as $$
 select ('06010000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.project_read_check(v boolean,msg text) returns void language plpgsql as $$
begin
 if v is distinct from true then raise exception 'FAIL: %',msg;end if;
end$$;

create function pg_temp.project_read_deny(statement text,state text) returns void language plpgsql as $$
begin
 begin execute statement;exception when others then if sqlstate=state then return;end if;raise;end;
 raise exception 'FAIL: request unexpectedly accepted';
end$$;
create function pg_temp.project_read_context(office uuid) returns jsonb language sql as $$
 select jsonb_build_object(
 'version',2,'application','em','channel','web','authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
 'workshop',jsonb_build_object('id',office,'code',case when office=pg_temp.project_read_id(1) then 'BMA' else 'BRJ' end,
  'name','LOCAL office','active',true,'revision',1,'updated_at',stamp),
 'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
  'subject',pg_temp.project_read_id(14),'revision',1)),
 'issued_at',stamp,'expires_at',stamp+interval '5 minutes') from(select clock_timestamp() stamp)s;
$$;
create function pg_temp.project_read_mint(request_id uuid,resource text,args jsonb,office uuid) returns void language sql as $$
 select public.rm_sso_workshop_read_permit_v1(repeat('7',64),request_id,resource,args,pg_temp.project_read_context(office));
$$;
create function pg_temp.project_read_call(resource text,args jsonb,office uuid) returns jsonb language plpgsql as $$
declare request_id uuid:=gen_random_uuid();response jsonb;
begin
 perform pg_temp.project_read_mint(request_id,resource,args,office);
 set local role authenticated;
 response:=public.rm_web_workshop_read_v1(request_id,resource,args);
 reset role;
 perform pg_temp.project_read_check(response->>'request_id'=request_id::text
  and response->>'resource'=resource and response->>'workshop_id'=office::text,'response binds request, resource and office');
 return nullif(response->'data','null'::jsonb);
exception when others then reset role;raise;
end$$;

select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"06010000-0000-4000-8000-000000000001","code":"BMA"},{"id":"06010000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"06010000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',(select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));

insert into auth.users(id) values(pg_temp.project_read_id(11));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.project_read_id(12),pg_temp.project_read_id(11),'LOCAL operations reader','administrador');
insert into auth.sessions(id,user_id) values(pg_temp.project_read_id(13),pg_temp.project_read_id(11));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 (pg_temp.project_read_id(15),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.project_read_id(14),pg_temp.project_read_id(12),pg_temp.project_read_id(11),true,pg_temp.project_read_id(12),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('7',64),pg_temp.project_read_id(15),pg_temp.project_read_id(13),'opaque-local-operations-session',clock_timestamp()+interval '30 minutes');
select set_config('request.jwt.claim.sub',pg_temp.project_read_id(11)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.project_read_id(13),'aal','aal1')::text,true);

insert into public.rm_clientes(id,nome) values
 (pg_temp.project_read_id(201),'LOCAL BMA client'),(pg_temp.project_read_id(202),'LOCAL BRJ client'),(pg_temp.project_read_id(203),'LOCAL pending client');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values
 ('client',pg_temp.project_read_id(201),pg_temp.project_read_id(1)),('client',pg_temp.project_read_id(202),pg_temp.project_read_id(2));

insert into public.rm_projetos(id,numero,nome,cliente_id,arquivo_nota_fiscal_url)
 select pg_temp.project_read_id(100+n),'OS '||n,'LOCAL needle',pg_temp.project_read_id(case when n<=26 then 201 when n=27 then 202 else 203 end),
   case when n=1 then 'https://private.invalid/invoice' end from generate_series(1,28)n;
insert into rm_private.workshop_project_ownership(id,workshop_id)
 select pg_temp.project_read_id(100+n),pg_temp.project_read_id(case when n<=26 then 1 else 2 end) from generate_series(1,27)n;

insert into public.rm_celulas(id,nome) values
 (pg_temp.project_read_id(301),'LOCAL BMA cell'),(pg_temp.project_read_id(302),'LOCAL BRJ cell'),(pg_temp.project_read_id(303),'LOCAL pending cell');
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values
 (pg_temp.project_read_id(301),pg_temp.project_read_id(1)),(pg_temp.project_read_id(302),pg_temp.project_read_id(2));

insert into public.rm_forms(id,titulo) values
 (pg_temp.project_read_id(601),'LOCAL BMA form'),(pg_temp.project_read_id(602),'LOCAL BRJ form'),(pg_temp.project_read_id(603),'LOCAL pending form');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values
 ('form_model',pg_temp.project_read_id(601),pg_temp.project_read_id(1)),('form_model',pg_temp.project_read_id(602),pg_temp.project_read_id(2));
-- Model historical inconsistencies that predate the reference guards.
alter table public.rm_registros_formulario disable trigger workshop_catalog_reference_guard;
alter table public.rm_registros_formulario disable trigger workshop_direct_reference_guard;
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,numero_projeto_rm,descricao)
 select pg_temp.project_read_id(700+n),pg_temp.project_read_id(project_no),pg_temp.project_read_id(cell_no),
  pg_temp.project_read_id(form_no),'OS 0001','LOCAL review '||n
 from (values(1,101,301,601),(2,127,302,602),(3,101,302,601),(4,101,301,602),(5,101,null,601),
  (6,128,301,601),(7,101,301,603),(8,101,303,601)) r(n,project_no,cell_no,form_no);
alter table public.rm_registros_formulario enable trigger workshop_direct_reference_guard;
alter table public.rm_registros_formulario enable trigger workshop_catalog_reference_guard;

insert into public.rm_celulas_projeto(id,projeto_id,celula_id,numero_projeto,posicao,retirada) values
 (pg_temp.project_read_id(501),pg_temp.project_read_id(101),pg_temp.project_read_id(301),'LOCAL allocation 1',1,false),
 (pg_temp.project_read_id(502),pg_temp.project_read_id(102),pg_temp.project_read_id(301),'LOCAL allocation 2',2,true),
 (pg_temp.project_read_id(503),pg_temp.project_read_id(101),pg_temp.project_read_id(303),'LOCAL pending allocation',3,false),
 (pg_temp.project_read_id(504),pg_temp.project_read_id(127),pg_temp.project_read_id(302),'LOCAL BRJ allocation',4,false);

insert into public.rm_equipamentos(id,projeto_id,descricao) values
 (pg_temp.project_read_id(401),pg_temp.project_read_id(101),'LOCAL canonical equipment');
update public.rm_projetos set equipamento_id=pg_temp.project_read_id(401) where id=pg_temp.project_read_id(101);

insert into rm_private.gantt_project_plans(projeto_id,links,updated_by) values(
 pg_temp.project_read_id(101),jsonb_build_array(jsonb_build_object(
  'predecessor_id',pg_temp.project_read_id(501),'successor_id',pg_temp.project_read_id(503),'lag_days',1)),pg_temp.project_read_id(12));
insert into rm_private.gantt_baselines(projeto_id,label,items,created_by)
 select pg_temp.project_read_id(101),'LOCAL baseline',jsonb_agg(jsonb_build_object(
  'allocation_id',pg_temp.project_read_id(n),'data_inicio',null,'data_limite',null) order by n),pg_temp.project_read_id(12)
 from unnest(array[501,503]) n;

do $$
declare
  bma uuid:=pg_temp.project_read_id(1);
  brj uuid:=pg_temp.project_read_id(2);
  project_bma uuid:=pg_temp.project_read_id(101);
  list_args jsonb:='{"q":"NEEDLE","status":null,"client":null,"cell":null,"page":1,"planning":true}';
  detail_args jsonb:=jsonb_build_object('id',project_bma,'documents',false,'cells',false);
  planning_args jsonb:='{"q":"NEEDLE","status":null,"cell":null,"page":1,"project_details":true}';
  gantt_args jsonb:='{"project_id":null,"cell_id":null,"include_closed":false,"project_details":true,"can_manage":false}';
  v jsonb;
begin
  v:=pg_temp.project_read_call('receiving_list','{"q":"NEEDLE","reason":"without_type","page":1}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=26 and jsonb_array_length(v->'items')=25
   and (v->'items'->0->>'allocation_count')::int=1
   and not (v->'items'->0 ? 'arquivo_nota_fiscal_url'),'receivings count and page only proven own projects and cells');
  v:=pg_temp.project_read_call('receiving_list','{"q":"NEEDLE","reason":"without_type","page":2}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=26 and jsonb_array_length(v->'items')=1,'receiving page two carries the filtered total');
  v:=pg_temp.project_read_call('receiving_list','{"q":"NEEDLE","reason":"without_type","page":1}',brj);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->'items'->0->>'id')::uuid=pg_temp.project_read_id(127)
   and (v->'summary'->>'without_type')::int=1,'receiving summary includes only own projects before search');
  v:=pg_temp.project_read_call('receiving_list','{"q":"BMA client","reason":"all","page":1}',brj);
  perform pg_temp.project_read_check((v->>'total')::int=0,'other workshop customers are not searchable in receiving');
  perform pg_temp.project_read_deny(format('select pg_temp.project_read_call(''receiving_list'',%L,%L)',
   '{"q":"","reason":"all","page":1,"office":"BRJ"}',bma),'22023');

  v:=pg_temp.project_read_call('project_qr',jsonb_build_object('id',project_bma),bma);
  perform pg_temp.project_read_check((v->>'id')::uuid=project_bma and not(v?'arquivo_nota_fiscal_url'),'own QR exposes only identity fields');
  perform pg_temp.project_read_check(pg_temp.project_read_call('project_qr',jsonb_build_object('id',project_bma),brj) is null,
   'QR of another office is unavailable');
  v:=pg_temp.project_read_call('document_link',jsonb_build_object('id',project_bma,'source','invoice'),bma);
  perform pg_temp.project_read_check(v->>'file'='https://private.invalid/invoice','own invoice uses the existing file reference');
  perform pg_temp.project_read_check(pg_temp.project_read_call('document_link',jsonb_build_object('id',project_bma,'source','invoice'),brj) is null,
   'direct download of another office has no file location');

  v:=pg_temp.project_read_call('form_record_list','{"q":"OS 0001","status":"em_an_lise","page":1,"project_details":true}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=2 and jsonb_array_length(v->'rows')=2
   and (v->'forms'->0->>'id')::uuid=pg_temp.project_read_id(601)
   and (v->'projects'->0->>'id')::uuid=project_bma and not(v->'rows'->0?'parecer'),
   'form dashboard scopes search and totals before pagination, retaining historical records without a cell');
  v:=pg_temp.project_read_call('form_record_list','{"q":"OS 0001","status":null,"page":1,"project_details":false}',brj);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->'rows'->0->>'id')::uuid=pg_temp.project_read_id(702)
   and v->'projects'='[]'::jsonb,'duplicate OS search returns the BRJ record and omits optional project metadata');
  v:=pg_temp.project_read_call('form_record_project',jsonb_build_object('id',pg_temp.project_read_id(701)),bma);
  perform pg_temp.project_read_check((v->>'project_id')::uuid=project_bma and (v->>'form_id')::uuid=pg_temp.project_read_id(601)
   and (v->>'cell_id')::uuid=pg_temp.project_read_id(301),'own form detail identifies a consistent project, cell and model');
  perform pg_temp.project_read_check(pg_temp.project_read_call('form_record_project',jsonb_build_object('id',pg_temp.project_read_id(701)),brj) is null
   and pg_temp.project_read_call('form_record_project',jsonb_build_object('id',pg_temp.project_read_id(703)),bma) is null
   and pg_temp.project_read_call('form_record_project',jsonb_build_object('id',pg_temp.project_read_id(704)),bma) is null
   and pg_temp.project_read_call('form_record_project',jsonb_build_object('id',pg_temp.project_read_id(706)),bma) is null,
   'form URL omits other-office records and rejects inconsistent references');

  v:=pg_temp.project_read_call('project_list',list_args,bma);
  perform pg_temp.project_read_check((v->>'total')::int=26 and jsonb_array_length(v->'rows')=25
    and jsonb_array_length(v->'clients')=1 and jsonb_array_length(v->'cells')=1,'project counts and selectors are filtered before paging');
  v:=pg_temp.project_read_call('project_list',list_args||'{"page":2}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=26 and jsonb_array_length(v->'rows')=1,'page two reports the scoped total');
  v:=pg_temp.project_read_call('project_list',list_args,brj);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->'rows'->0->>'id')::uuid=pg_temp.project_read_id(127),'reciprocal workshop read excludes BMA and unclassified project');
  v:=pg_temp.project_read_call('project_list',list_args||jsonb_build_object('client',pg_temp.project_read_id(202)),bma);
  perform pg_temp.project_read_check((v->>'total')::int=0,'cross-workshop client filter returns no matches');
  v:=pg_temp.project_read_call('project_list',list_args||jsonb_build_object('cell',pg_temp.project_read_id(303)),bma);
  perform pg_temp.project_read_check((v->>'total')::int=0,'unclassified cell filter cannot discover its project');
  v:=pg_temp.project_read_call('project_list',list_args||jsonb_build_object('cell',pg_temp.project_read_id(301)),bma);
  perform pg_temp.project_read_check((v->>'total')::int=1 and v->'rows'->0->>'descricao_equipamento_exibicao'='LOCAL canonical equipment'
    and not (v->'rows'->0 ? 'arquivo_nota_fiscal_url'),'active cell filter, reverse equipment join and list redaction');

  v:=pg_temp.project_read_call('project_entry',detail_args,bma);
  perform pg_temp.project_read_check((v->'project'->>'id')::uuid=project_bma and v->'client'->>'nome'='LOCAL BMA client'
    and jsonb_array_length(v->'cells')=0 and not (v->'project' ? 'arquivo_nota_fiscal_url'),'project detail trims cell choices and private document URLs');
  v:=pg_temp.project_read_call('project_entry',detail_args||'{"documents":true,"cells":true}',bma);
  perform pg_temp.project_read_check(jsonb_array_length(v->'cells')=1 and v->'project'->>'arquivo_nota_fiscal_url'='https://private.invalid/invoice','authorized detail reveals only scoped cell choices');
  perform pg_temp.project_read_check(pg_temp.project_read_call('project_entry',detail_args,brj) is null
    and pg_temp.project_read_call('project_entry',detail_args||jsonb_build_object('id',pg_temp.project_read_id(128)),bma) is null,'cross-workshop and unclassified details are absent');

  v:=pg_temp.project_read_call('planning_list',planning_args,bma);
  perform pg_temp.project_read_check((v->>'total')::int=1 and jsonb_array_length(v->'projects')=26
    and (v->'rows'->0->>'id')::uuid=pg_temp.project_read_id(501) and jsonb_array_length(v->'cells')=1,'planning filters both parents and excludes retired allocations');
  v:=pg_temp.project_read_call('planning_list',planning_args||'{"q":"allocation 1","project_details":false}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=1 and jsonb_array_length(v->'projects')=0 and v->'rows'->0->'project'='null','planning-only search does not query project detail');
  v:=pg_temp.project_read_call('planning_list',planning_args||'{"project_details":false}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=0,'planning-only search cannot query hidden project names');

  v:=pg_temp.project_read_call('gantt_projects','{"q":"needle","page":2}',bma);
  perform pg_temp.project_read_check((v->>'total')::int=26 and jsonb_array_length(v->'items')=1,'Gantt selector counts only projects in the office');
  v:=pg_temp.project_read_call('gantt_cells','{}',bma);
  perform pg_temp.project_read_check(jsonb_array_length(v)=1 and (v->0->>'id')::uuid=pg_temp.project_read_id(301),'Gantt cell selector shows only proven office');
  v:=pg_temp.project_read_call('gantt_snapshot',gantt_args,bma);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->>'complete')::boolean
   and (v->'items'->0->>'id')::uuid=pg_temp.project_read_id(501)
   and (v->'items'->0->>'can_edit')::boolean=false,'general Gantt excludes other office, pending and retired allocations');
  v:=pg_temp.project_read_call('gantt_snapshot',gantt_args,brj);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->'items'->0->>'id')::uuid=pg_temp.project_read_id(504),'reciprocal general Gantt filter');
  v:=pg_temp.project_read_call('gantt_snapshot',gantt_args||jsonb_build_object('cell_id',pg_temp.project_read_id(301)),bma);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->'cells'->0->>'id')::uuid=pg_temp.project_read_id(301),'Gantt cell filter binds exact root');
  v:=pg_temp.project_read_call('gantt_snapshot',gantt_args||jsonb_build_object('project_id',project_bma,'include_closed',true),bma);
  perform pg_temp.project_read_check((v->>'total')::int=1 and (v->'projects'->0->>'id')::uuid=project_bma,'Gantt project restricts active allocations to classified cells');
  perform pg_temp.project_read_check(v->'links'='[]' and jsonb_array_length(v->'baseline'->'items')=1
   and (v->'baseline'->'items'->0->>'allocation_id')::uuid=pg_temp.project_read_id(501),
   'Gantt omits unclassified allocations from dependency links and baseline');
  perform pg_temp.project_read_check(v->'projects'->0->>'plan_version'=rm_private.web_gantt_project_version_v1(project_bma),
   'Gantt retains the exact plan revision');
  perform pg_temp.project_read_check(pg_temp.project_read_call('gantt_snapshot',gantt_args||jsonb_build_object('cell_id',pg_temp.project_read_id(302)),bma) is null
    and pg_temp.project_read_call('gantt_snapshot',gantt_args||jsonb_build_object('cell_id',pg_temp.project_read_id(303)),bma) is null,
    'foreign and pending Gantt cell IDs are indistinguishable');
  perform pg_temp.project_read_check(pg_temp.project_read_call('gantt_snapshot',gantt_args||jsonb_build_object('project_id',project_bma,'include_closed',true),brj) is null
    and pg_temp.project_read_call('gantt_snapshot',gantt_args||jsonb_build_object('project_id',pg_temp.project_read_id(128),'include_closed',true),bma) is null,
    'foreign and pending Gantt project IDs are indistinguishable');
  v:=pg_temp.project_read_call('gantt_snapshot',gantt_args||'{"project_details":false}',bma);
  perform pg_temp.project_read_check(v->'projects'->0->'nome'='null' and v->'projects'->0->'planned_start'='null','Gantt planning-only projection preserves project field restrictions');
end$$;

select pg_temp.project_read_mint(pg_temp.project_read_id(701),'gantt_cells','{}',pg_temp.project_read_id(1));
set local role authenticated;
select pg_temp.project_read_deny('select pg_temp.project_read_mint(gen_random_uuid(),''gantt_cells'',''{}'',pg_temp.project_read_id(1))','42501');
select pg_temp.project_read_deny('select public.rm_web_workshop_read_v1(pg_temp.project_read_id(701),''gantt_cells'',''{"office":"BRJ"}'')','42501');
select pg_temp.project_read_deny('select public.rm_web_workshop_read_v1(pg_temp.project_read_id(701),''gantt_projects'',''{}'')','42501');
select public.rm_web_workshop_read_v1(pg_temp.project_read_id(701),'gantt_cells','{}');
select pg_temp.project_read_deny('select public.rm_web_workshop_read_v1(pg_temp.project_read_id(701),''gantt_cells'',''{}'')','42501');
select pg_temp.project_read_check((public.rm_web_gantt_snapshot_v1('{"project_id":null,"cell_id":null,"include_closed":false}')->>'total')::int>=3,
 'legacy Gantt remains available to its previous authorized callers');
reset role;
select pg_temp.project_read_deny('select pg_temp.project_read_call(''gantt_cells'',''{"office":"BRJ"}'',pg_temp.project_read_id(1))','22023');
select pg_temp.project_read_deny('select pg_temp.project_read_call(''gantt_snapshot'',''{"project_id":null,"cell_id":null,"include_closed":false,"project_details":true,"can_manage":true}'',pg_temp.project_read_id(1))','22023');
select pg_temp.project_read_check(not has_function_privilege('authenticated','rm_private.workshop_project_read_data_v1(text,jsonb,uuid)','execute')
 and not has_function_privilege('authenticated','rm_private.workshop_gantt_snapshot_v1(jsonb,uuid)','execute')
 and not has_function_privilege('anon','public.rm_web_workshop_read_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('service_role','public.rm_web_workshop_read_v1(uuid,text,jsonb)','execute'),'readers cannot bypass the permit gateway');

select 'PASS: workshop operations readers, two offices and unclassified roots, list/pagination, planning and Gantt scopes, legacy compatibility and permit replay' result;

create function pg_temp.workshop_gantt_save(rid uuid,op text,changes jsonb,office uuid) returns jsonb language plpgsql as $$
declare saved jsonb;
begin
 perform public.rm_sso_gantt_workshop_permit_v1(repeat('7',64),rid,op,changes,pg_temp.project_read_context(office));
 set local role authenticated;
 saved:=public.rm_web_mutate_v1(rid,op,changes);
 reset role;
 return saved;
end $$;
select pg_temp.project_read_deny('select rm_private.activate_gantt_workshop_writes_v1()','PT409');
update rm_private.workshop_root_enforcement set activated_at=clock_timestamp(),activated_by=session_user where singleton;
update rm_private.sso_settings set require_sso=true;
select rm_private.activate_gantt_workshop_writes_v1();
do $edit$
declare
 bma uuid:=pg_temp.project_read_id(1);
 brj uuid:=pg_temp.project_read_id(2);
 project_brj uuid:=pg_temp.project_read_id(127);
 allocation_id uuid:=pg_temp.project_read_id(504);
 rid uuid:=pg_temp.project_read_id(704);
 filters jsonb:='{"project_id":null,"cell_id":null,"include_closed":false,"project_details":true,"can_manage":true}';
 p jsonb;
 reply jsonb;
begin
 reply:=pg_temp.project_read_call('gantt_snapshot',filters,brj);
 perform pg_temp.project_read_check((reply->'items'->0->>'can_edit')::boolean,'own fully classified Gantt row permits edits');
 reply:=pg_temp.project_read_call('gantt_snapshot',filters,bma);
 perform pg_temp.project_read_check(not (reply->'items'->0->>'can_edit')::boolean,'a project with a pending active cell is read-only');
 select jsonb_build_object('reason','Local change in schedule',
  'projects',jsonb_build_array(jsonb_build_object('id',x.id,'expected_updated_at',x.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(x.id))),
  'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',jsonb_build_object('data_limite','2026-11-30')))) into p
 from public.rm_projetos x join public.rm_celulas_projeto a on a.projeto_id=x.id where a.id=allocation_id;
 perform public.rm_sso_action_permit_v1(repeat('7',64),rid,'save_gantt_plan',p,'em.planning.manage');
 set local role authenticated;
 perform pg_temp.project_read_deny(format('select public.rm_web_mutate_v1(%L,''save_gantt_plan'',%L)',rid,p),'42501');
 reset role;
 perform pg_temp.project_read_deny(format('select pg_temp.workshop_gantt_save(%L,''save_gantt_plan'',%L,%L)',rid,p,bma),'42501');
 perform pg_temp.workshop_gantt_save(rid,'save_gantt_plan',p,brj);
 perform pg_temp.project_read_check((pg_temp.workshop_gantt_save(rid,'save_gantt_plan',p,brj)->>'idempotent_replay')::boolean,'write replay retains the same office');
 perform pg_temp.project_read_check((select (data_limite at time zone 'America/Sao_Paulo')::date='2026-11-30'::date from public.rm_celulas_projeto where id=allocation_id),'own schedule date stored');

 select jsonb_build_object('projeto_id',id,'expected_updated_at',updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(id),
  'calendar',jsonb_build_object('weekdays',jsonb_build_array(1,2,3,4,5),'exceptions','[]'::jsonb),
  'milestones','[]'::jsonb,'reason','Local calendar test') into p from public.rm_projetos where id=project_brj;
 perform pg_temp.project_read_deny(format('select pg_temp.workshop_gantt_save(%L,''save_gantt_settings'',%L,%L)',gen_random_uuid(),p,bma),'42501');
 perform pg_temp.workshop_gantt_save(gen_random_uuid(),'save_gantt_settings',p,brj);
 perform pg_temp.project_read_check(exists(select 1 from rm_private.gantt_project_settings where projeto_id=project_brj),'own schedule calendar stored');
end
$edit$;
select 'PASS: scoped Gantt dates, calendar, read-edit eligibility, legacy permit rejection and exact retry' result;

create function pg_temp.workshop_form_review(rid uuid,p jsonb,office uuid,actual jsonb default null)
returns jsonb language plpgsql as $$
declare result jsonb;
begin
 perform public.rm_sso_form_review_workshop_permit_v1(repeat('7',64),rid,'review_form',p,pg_temp.project_read_context(office));
 set local role authenticated;
 result:=public.rm_web_mutate_v1(rid,'review_form',coalesce(actual,p));
 reset role;
 return result;
exception when others then reset role;raise;
end$$;

select rm_private.activate_form_review_workshop_writes_v1();
insert into public.rm_questoes(id,form_id,enunciado,tipo) values
 (pg_temp.project_read_id(801),pg_temp.project_read_id(601),'LOCAL answer','texto_curto');
insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta) values
 (pg_temp.project_read_id(901),pg_temp.project_read_id(701),pg_temp.project_read_id(801),'LOCAL original answer');
do $$
declare
 bma uuid:=pg_temp.project_read_id(1);
 brj uuid:=pg_temp.project_read_id(2);
 registration uuid:=pg_temp.project_read_id(701);
 rid uuid:=gen_random_uuid();
 p jsonb;
 r jsonb;
begin
 select jsonb_build_object('registro_formulario_id',id,'expected_updated_at',updated_at,
  'decision','return','parecer','LOCAL revision needed','resposta_ids',jsonb_build_array(pg_temp.project_read_id(901))) into p
 from public.rm_registros_formulario where id=registration;
 perform public.rm_sso_action_permit_v1(repeat('7',64),rid,'review_form',p,'em.forms.review');
 set local role authenticated;
 perform pg_temp.project_read_deny(format('select public.rm_web_mutate_v1(%L,''review_form'',%L)',rid,p),'42501');
 reset role;
 perform pg_temp.project_read_deny(format('select pg_temp.workshop_form_review(%L,%L,%L)',rid,p,brj),'42501');
 perform pg_temp.project_read_deny(format('select pg_temp.workshop_form_review(%L,%L,%L,%L)',rid,p,bma,
  jsonb_set(p,'{parecer}','"LOCAL changed payload"')),'42501');
 r:=pg_temp.workshop_form_review(rid,p,bma);
 perform pg_temp.project_read_check(r->'record'->>'status'='direcionado','BMA may return its own answer for correction');
 perform pg_temp.project_read_check((pg_temp.workshop_form_review(rid,p,bma)->>'idempotent_replay')::boolean,
  'the same review protocol is a replay after a fresh office authorization');
 perform pg_temp.project_read_deny(format('select pg_temp.workshop_form_review(%L,%L,%L)',rid,p,brj),'42501');
 perform pg_temp.project_read_check((select count(*)=1 from public.rm_aprovacoes_registro where registro_formulario_id=registration)
  and (select revisar and resposta='LOCAL original answer' from public.rm_respostas where id=pg_temp.project_read_id(901)),
  'existing decision audit and operator answer are preserved');
end$$;
select 'PASS: scoped form decisions, review audit, own retry, foreign refusal and changed payload refusal' result;

update public.rm_projetos set chegada_do_equipamento=statement_timestamp()-interval '1 day',status_pcp='executando'
 where id in(pg_temp.project_read_id(101),pg_temp.project_read_id(127),pg_temp.project_read_id(128));
do $$
declare bma uuid:=pg_temp.project_read_id(1); brj uuid:=pg_temp.project_read_id(2); filters jsonb; v jsonb;
begin
 v:=pg_temp.project_read_call('workshop_twin','{}',bma);
 perform pg_temp.project_read_check(v->>'layout'='bma' and (v->>'project_count')::int=1 and (v->>'allocation_count')::int=1
  and (v->>'cell_count')::int=1 and (v->'projects'->0->>'id')::uuid=pg_temp.project_read_id(101)
  and (v->'cells'->0->>'id')::uuid=pg_temp.project_read_id(301),'BMA 3D data and counts use only its classified projects and cells');
 v:=pg_temp.project_read_call('workshop_twin','{}',brj);
 perform pg_temp.project_read_check(v->>'layout'='management' and (v->>'project_count')::int=1 and (v->>'allocation_count')::int=1
  and (v->>'cell_count')::int=1 and (v->'projects'->0->>'id')::uuid=pg_temp.project_read_id(127)
  and (v->'cells'->0->>'id')::uuid=pg_temp.project_read_id(302),'BRJ management uses its own counts without the BMA plant');
 filters:=jsonb_build_object('cell_ids',jsonb_build_array(pg_temp.project_read_id(301)),
  'fields',jsonb_build_array('project_number','client_name','cell_name'));
 v:=pg_temp.project_read_call('planning_export',filters,bma);
 perform pg_temp.project_read_check((v->>'row_count')::int=1 and (v->'cells'->0->>'id')::uuid=pg_temp.project_read_id(301)
  and v->'cells'->0->'rows'->0->'values'->>'client_name'='LOCAL BMA client','BMA spreadsheet input contains its own cell and customer');
 perform pg_temp.project_read_deny(format('select pg_temp.project_read_call(''planning_export'',%L,%L)',filters,brj),'42501');
 filters:=jsonb_set(filters,'{cell_ids}',jsonb_build_array(pg_temp.project_read_id(302)));
 v:=pg_temp.project_read_call('planning_export',filters,brj);
 perform pg_temp.project_read_check((v->>'row_count')::int=1 and (v->'cells'->0->>'id')::uuid=pg_temp.project_read_id(302)
  and v->'cells'->0->'rows'->0->'values'->>'client_name'='LOCAL BRJ client','BRJ spreadsheet input has its own projects even with an analogous query');
 perform pg_temp.project_read_deny(format('select pg_temp.project_read_call(''planning_export'',%L,%L)',filters,bma),'42501');
end$$;
select 'PASS: scoped workshop twin projections and planning export in two offices' result;

insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,foto_url,lixeira) values
 (pg_temp.project_read_id(951),pg_temp.project_read_id(101),pg_temp.project_read_id(301),pg_temp.project_read_id(501),'https://private.invalid/own-photo',false),
 (pg_temp.project_read_id(952),pg_temp.project_read_id(127),pg_temp.project_read_id(302),pg_temp.project_read_id(504),'https://private.invalid/foreign-photo',false),
 (pg_temp.project_read_id(953),pg_temp.project_read_id(101),null,null,'https://private.invalid/discarded-photo',true),
 (pg_temp.project_read_id(954),null,null,null,'https://private.invalid/template-photo',false),
 (pg_temp.project_read_id(955),pg_temp.project_read_id(101),pg_temp.project_read_id(303),pg_temp.project_read_id(503),'https://private.invalid/pending-photo',false);
update public.rm_respostas set fotos_urls=array['https://private.invalid/first','https://private.invalid/second'],
 assinatura_url='https://private.invalid/signature' where id=pg_temp.project_read_id(901);
do $$
declare bma uuid:=pg_temp.project_read_id(1); brj uuid:=pg_temp.project_read_id(2); p jsonb; r jsonb;
begin
 p:=jsonb_build_object('source','project_photo','id',pg_temp.project_read_id(951));
 r:=pg_temp.project_read_call('media_reference',p,bma);
 perform pg_temp.project_read_check(r->>'file'='https://private.invalid/own-photo','authorized project photo');
 perform pg_temp.project_read_check(pg_temp.project_read_call('media_reference',p,brj) is null,'foreign UUID does not disclose project media');
 for i in 952..955 loop
  perform pg_temp.project_read_check(pg_temp.project_read_call('media_reference',jsonb_set(p,'{id}',to_jsonb(pg_temp.project_read_id(i))),bma) is null,
   'foreign, discarded, template or pending media stays out of the project design');
 end loop;
 p:=jsonb_build_object('source','answer_photo','id',pg_temp.project_read_id(901),'index',1);
 r:=pg_temp.project_read_call('media_reference',p,bma);
 perform pg_temp.project_read_check(r->>'file'='https://private.invalid/second'
  and pg_temp.project_read_call('media_reference',p,brj) is null,'answer photos are indexed and scoped by the registration');
 perform pg_temp.project_read_check(pg_temp.project_read_call('media_reference',jsonb_set(p,'{index}','2'),bma) is null,'unknown photo index');
 p:=(p-'index')||'{"source":"answer_signature"}'::jsonb;
 r:=pg_temp.project_read_call('media_reference',p,bma);
 perform pg_temp.project_read_check(r->>'file'='https://private.invalid/signature'
  and pg_temp.project_read_call('media_reference',p,brj) is null,'signature is scoped by the registration');
end$$;
select 'PASS: scoped project photos, answer media, signature and direct foreign reference refusal' result;

update public.rm_celulas_projeto set visibilidade=true,data_limite=statement_timestamp()-interval '1 day',status='em_dia'
 where id in(pg_temp.project_read_id(501),pg_temp.project_read_id(503),pg_temp.project_read_id(504));
do $$
declare v jsonb;
begin
 v:=pg_temp.project_read_call('overview','{"projects":true,"forms":true,"planning":true,"documents":false}',pg_temp.project_read_id(1));
 perform pg_temp.project_read_check((v->'counts'->>'projects')::int=26 and (v->'counts'->>'awaitingReview')::int=1
  and (v->'counts'->>'overdueCells')::int=1 and v->'counts'->'documents'='null'::jsonb
  and jsonb_array_length(v->'recentProjects')=8 and (v->'overdue'->0->>'id')::uuid=pg_temp.project_read_id(501),
  'overview filters each count and task before its limit');
 v:=pg_temp.project_read_call('overview','{"projects":false,"forms":true,"planning":false,"documents":false}',pg_temp.project_read_id(2));
 perform pg_temp.project_read_check(v->'counts'->'projects'='null'::jsonb and v->'recentProjects'='[]'::jsonb
  and v->'overdue'='[]'::jsonb and (v->'counts'->>'awaitingReview')::int=1
  and (v->'recentRecords'->0->>'id')::uuid=pg_temp.project_read_id(702),'form-only overview returns only own pending record');
end$$;
select 'PASS: workshop overview counts, pending forms, deadlines and restricted capabilities' result;
rollback;

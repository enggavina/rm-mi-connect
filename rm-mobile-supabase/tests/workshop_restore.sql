\set ON_ERROR_STOP on
\if :seed
begin;
create schema em_fixture;
create function em_fixture.id(n integer) returns uuid language sql immutable as $$
 select ('07610000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$$;
select rm_private.workshop_adopt_bma_roots_v1(
 (select jsonb_agg(jsonb_build_object('id',em_fixture.id(n),'code',code)) from (values(1,'BMA'),(2,'BRJ'),(3,'BBH')) v(n,code)),
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into rm_private.workshop_references values(em_fixture.id(4),'QA-04','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1');

insert into auth.users(id) select em_fixture.id(10+n) from generate_series(1,4)n;
insert into auth.sessions(id,user_id) select em_fixture.id(20+n),em_fixture.id(10+n) from generate_series(1,4)n;
insert into public.rm_users(id,auth_user_id,nome,perfil)
 select em_fixture.id(30+n),em_fixture.id(10+n),'Gestor local '||n,'administrador' from generate_series(1,4)n;
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 select em_fixture.id(40+n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',em_fixture.id(50+n),
  em_fixture.id(30+n),em_fixture.id(10+n),true,em_fixture.id(30+n),clock_timestamp() from generate_series(1,4)n;

insert into public.rm_projetos(id,numero,nome,status_pcp,chegada_do_equipamento)
 select em_fixture.id(100+n),'QA-MESMA-OS','Projeto local '||n,'executando',clock_timestamp() from generate_series(1,4)n;
insert into rm_private.workshop_project_ownership(id,workshop_id)
 select em_fixture.id(100+n),em_fixture.id(n) from generate_series(1,4)n;
insert into public.rm_celulas(id,nome) select em_fixture.id(200+n),'Célula local '||n from generate_series(1,4)n;
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id)
 select em_fixture.id(200+n),em_fixture.id(n) from generate_series(1,4)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,retirada,visibilidade,data_inicio,data_limite,posicao,indice,horas_previstas)
 select em_fixture.id(300+n),em_fixture.id(100+n),em_fixture.id(200+n),false,true,clock_timestamp(),clock_timestamp()+interval '2 days',7,5,1.25*n
 from generate_series(1,4)n;
insert into rm_private.gantt_baselines(id,projeto_id,label,items,created_by)
 select em_fixture.id(800+n),a.projeto_id,'Linha de base local '||n,jsonb_build_array(jsonb_build_object('allocation_id',a.id,
  'data_inicio',a.data_inicio,'data_limite',a.data_limite)),em_fixture.id(30+n)
 from generate_series(1,4)n join public.rm_celulas_projeto a on a.id=em_fixture.id(300+n);
insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by,workshop_id)
 select em_fixture.id(810+n),'Bancada comum','maquina',true,'[480,480,480,480,480,480,480]','[]',em_fixture.id(30+n),em_fixture.id(n)
 from generate_series(1,4)n;
insert into rm_private.capacity_bookings(id,resource_id,allocation_id,day,minutes,updated_by)
 select em_fixture.id(820+n),em_fixture.id(810+n),em_fixture.id(300+n),(clock_timestamp() at time zone 'America/Sao_Paulo')::date+1,60*n,em_fixture.id(30+n)
 from generate_series(1,4)n;
insert into public.rm_forms(id,titulo) select em_fixture.id(400+n),'Modelo local '||n from generate_series(1,4)n;
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id)
 select 'form_model',em_fixture.id(400+n),em_fixture.id(n) from generate_series(1,4)n;
insert into public.rm_tipos_equipamento(id,nome)
 select em_fixture.id(1100+n),'Tipo em comum' from generate_series(1,4)n;
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id)
 select 'equipment_type',em_fixture.id(1100+n),em_fixture.id(n) from generate_series(1,4)n;
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id)
 select em_fixture.id(1110+n),em_fixture.id(200+n),em_fixture.id(1100+n) from generate_series(1,4)n;
insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id,ativo)
 select em_fixture.id(1110+n),em_fixture.id(400+n),true from generate_series(1,4)n;
insert into public.rm_cadastro_fotos(id,titulo,numero,celula_nome)
 select em_fixture.id(1120+n),'Frontal',3,c.nome from generate_series(1,4)n
 join public.rm_celulas c on c.id=em_fixture.id(200+n);
insert into rm_private.engineering_photo_title_scope(title_id,workshop_id,cell_id)
 select em_fixture.id(1120+n),em_fixture.id(n),em_fixture.id(200+n) from generate_series(2,4)n;
insert into public.rm_fotos(id,celula_id,celula_tipo_equipamento_id,categoria_foto,cadastro_foto_id,titulo,numero)
 select em_fixture.id(1130+n),em_fixture.id(200+n),em_fixture.id(1110+n),'obrigat_ria',em_fixture.id(1120+n),'Frontal',1
 from generate_series(1,4)n;
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,numero_projeto_rm)
 select em_fixture.id(500+n),em_fixture.id(100+n),em_fixture.id(200+n),em_fixture.id(400+n),'QA-MESMA-OS' from generate_series(1,4)n;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,foto_url)
 select em_fixture.id(600+n),em_fixture.id(100+n),em_fixture.id(200+n),em_fixture.id(300+n),
 'https://fixture.invalid/storage/v1/object/authenticated/rm-fotos/'||n||'/equipamento.png' from generate_series(1,4)n;
insert into storage.objects(id,bucket_id,name)
 select em_fixture.id(700+n),'rm-fotos',n||'/equipamento.png' from generate_series(1,4)n;
insert into auth.users(id) select em_fixture.id(710+n) from generate_series(1,4)n;
insert into auth.sessions(id,user_id) select em_fixture.id(720+n),em_fixture.id(710+n) from generate_series(1,4)n;
insert into public.rm_users(id,auth_user_id,nome,perfil)
 select em_fixture.id(730+n),em_fixture.id(710+n),'Dispositivo local '||n,'administrador' from generate_series(1,4)n;
insert into public.rm_users(id,nome,perfil) select em_fixture.id(740+n),'Operador local '||n,'mobile' from generate_series(1,4)n;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 select extensions.digest(repeat(chr(96+n),64),'sha256'),em_fixture.id(710+n),em_fixture.id(730+n),em_fixture.id(740+n),
  clock_timestamp()+interval '1 hour' from generate_series(1,4)n;
insert into public.rm_tablet_celula_users(celula_id,identidade_id)
 select em_fixture.id(200+n),em_fixture.id(740+n) from generate_series(1,4)n;
do $seed_execution$
declare event jsonb;
begin
 for office in 1..4 loop
  perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(720+office),'aal','aal1')::text,true);
  event:=public.rm_mobile_mutate_v1(em_fixture.id(980+office),'rm_record_execution_event_v1',jsonb_build_object(
   'p_session_id',em_fixture.id(970+office),'p_allocation_id',em_fixture.id(300+office),'p_operador_id',em_fixture.id(740+office),
   'p_kind','start','p_previous_event_id',null,'p_occurred_at',clock_timestamp(),'p_pause_reason',null,'p_note',null,'p_effort_minutes',null),
   repeat(chr(96+office),64));
  if event->>'disposition' is distinct from 'accepted' or not exists(select 1 from rm_private.execution_sessions
   where id=em_fixture.id(970+office) and state='running') then
   raise exception 'O contexto inicial de apontamento não foi criado.';
  end if;
 end loop;
end
$seed_execution$;
insert into rm_private.mobile_workshop_uploads(id,submission_id,workshop_id,project_id,operation,auth_user_id,operator_id,
 intent_sha256,kind,mime_type,byte_size,content_sha256,object_path,stored_at)
 select em_fixture.id(750+n),em_fixture.id(760+n),em_fixture.id(n),em_fixture.id(100+n),'rm_record_cell_photo_v1',
  em_fixture.id(710+n),em_fixture.id(740+n),repeat('8',64),'photo','image/png',octet_length(bytes),
  encode(sha256(bytes),'hex'),'mobile-oficina/'||em_fixture.id(n)||'/'||em_fixture.id(760+n)||'/'||em_fixture.id(750+n)||'.png',clock_timestamp()
 from generate_series(1,4)n cross join lateral (
  select decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+pZJcAAAAASUVORK5CYII=','base64')||set_byte('\x00'::bytea,0,n+4) bytes
 ) b;
insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
 select em_fixture.id(770+n),'rm-documentos',u.object_path,jsonb_build_object('size',u.byte_size,'mimetype',u.mime_type),
  jsonb_build_object('sha256',u.content_sha256) from generate_series(1,4)n join rm_private.mobile_workshop_uploads u on u.id=em_fixture.id(750+n);
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,foto_url)
 select em_fixture.id(780+n),u.project_id,em_fixture.id(200+n),em_fixture.id(300+n),
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||u.object_path
 from generate_series(1,4)n join rm_private.mobile_workshop_uploads u on u.id=em_fixture.id(750+n);
commit;
\endif

begin;
create function pg_temp.workshop_restore_sso(office integer) returns jsonb language plpgsql as $$
declare context jsonb; stamp timestamptz:=clock_timestamp();
 hash text:=repeat(office::text,64);
begin
 perform set_config('request.jwt.claim.sub',em_fixture.id(10+office)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(20+office),'aal','aal1')::text,true);
 perform public.rm_sso_session_put_v1(hash,em_fixture.id(40+office),em_fixture.id(20+office),'opaque-local-restore-session',stamp+interval '15 minutes');
 select jsonb_build_object('version',2,'application','em','channel','web','authority',authority,
  'workshop',jsonb_build_object('id',id,'code',code,'name',code,'active',true,'revision',1,'updated_at',stamp),
  'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer',authority,'subject',em_fixture.id(50+office),'revision',1)),
  'issued_at',stamp,'expires_at',stamp+interval '5 minutes') into strict context
 from rm_private.workshop_references where id=em_fixture.id(office);
 return context;
end$$;

create function pg_temp.workshop_restore_read(office integer,resource text,args jsonb) returns jsonb language plpgsql as $$
declare request_id uuid:=gen_random_uuid(); context jsonb:=pg_temp.workshop_restore_sso(office); value jsonb;
 hash text:=repeat(office::text,64);
begin
 perform public.rm_sso_workshop_read_permit_v1(hash,request_id,resource,args,context);
 set local role authenticated;
 value:=public.rm_web_workshop_read_v1(request_id,resource,args);
 reset role;
 if value->>'workshop_id' is distinct from em_fixture.id(office)::text or value->>'request_id' is distinct from request_id::text then
  raise exception 'Resposta da consulta divergiu da oficina local.';
 end if;
 return nullif(value->'data','null'::jsonb);
exception when others then reset role;raise;
end$$;

create function pg_temp.workshop_restore_planning_write(office integer,submission uuid,operation text,payload jsonb,scoped boolean default true)
returns jsonb language plpgsql as $$
declare context jsonb:=pg_temp.workshop_restore_sso(office); value jsonb;
 hash text:=repeat(office::text,64);
begin
 if scoped then perform public.rm_sso_gantt_workshop_permit_v1(hash,submission,operation,payload,context);
 else perform public.rm_sso_action_permit_v1(hash,submission,operation,payload,'em.planning.manage');end if;
 set local role authenticated;
 value:=public.rm_web_mutate_v1(submission,operation,payload);
 reset role;
 return value;
exception when others then reset role;raise;
end$$;

create function pg_temp.workshop_restore_engineering_write(office integer,submission uuid,operation text,payload jsonb,scoped boolean default true)
returns jsonb language plpgsql as $$
declare context jsonb:=pg_temp.workshop_restore_sso(office); value jsonb;
 hash text:=repeat(office::text,64);
begin
 if scoped then perform public.rm_sso_engineering_workshop_permit_v1(hash,submission,operation,payload,context);
 else perform public.rm_sso_action_permit_v1(hash,submission,operation,payload,'em.engineering.manage');end if;
 set local role authenticated;
 value:=public.rm_web_mutate_v1(submission,operation,payload);
 reset role;
 return value;
exception when others then reset role;raise;
end$$;

create function pg_temp.availability_payload(snapshot jsonb,action text,visible boolean default null) returns jsonb
language sql as $$
 select jsonb_build_object(
  'action',action,'projeto_id',snapshot->'project'->'id','celula_projeto_id',snapshot->'allocation'->'id',
  'expected_project_updated_at',snapshot->'project'->'updated_at','expected_allocation_updated_at',snapshot->'allocation'->'updated_at',
  'expected_context_version',snapshot->'context_version','confirm_change',true)
  ||case when action='set_visibility' then jsonb_build_object('visibilidade',visible) else '{}'::jsonb end;
$$;

create function pg_temp.queue_payload(snapshot jsonb,apply_order boolean) returns jsonb
language sql as $$
 select jsonb_build_object('celula_id',snapshot->'cell'->'id','expected_queue_version',snapshot->'queue_version','apply_order',apply_order,
  'items',(select jsonb_agg(jsonb_build_object('id',item->'id','expected_updated_at',item->'updated_at','prioridade','alta')
    order by case when apply_order then -n else n end)
   from jsonb_array_elements(snapshot->'items') with ordinality q(item,n)));
$$;

create function pg_temp.workshop_restore_native_context(office integer,actor_office integer) returns jsonb language plpgsql as $$
declare context jsonb; stamp timestamptz:=clock_timestamp();
begin
 select jsonb_build_object('version',2,'application','em','channel','mobile','authority',authority,
   'workshop',jsonb_build_object('id',id,'code',code,'name',code,'active',true,'revision',1,'updated_at',stamp),
   'principals',jsonb_build_array(jsonb_build_object('kind','device','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1',
    'subject',em_fixture.id(710+actor_office),'revision',1),jsonb_build_object('kind','operator','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1',
    'subject',em_fixture.id(740+actor_office),'revision',1)), 'issued_at',stamp,'expires_at',stamp+interval '5 minutes') into strict context
  from rm_private.workshop_references where id=em_fixture.id(office);
 return context;
end$$;

create function pg_temp.workshop_restore_native(office integer,urls text[],reachable boolean default true) returns jsonb language sql as $$
 select public.rm_mobile_workshop_media_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),
  case when reachable then pg_temp.workshop_restore_native_context(office,office) end,urls);
$$;

create function pg_temp.workshop_restore_execution_event(office integer,submission uuid,params jsonb,scoped boolean) returns jsonb
language plpgsql as $$
declare value jsonb; delegation text:=repeat(chr(96+office),64);
begin
 perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(720+office),'aal','aal1')::text,true);
 if scoped then perform public.rm_authorize_mobile_workshop_mutation_v1(em_fixture.id(710+office),em_fixture.id(720+office),delegation,
  pg_temp.workshop_restore_native_context(office,office),submission,'rm_record_execution_event_v1',params);end if;
 set local role authenticated;
 if scoped then value:=public.rm_mobile_workshop_mutate_v1(submission,'rm_record_execution_event_v1',params,delegation);
 else value:=public.rm_mobile_mutate_v1(submission,'rm_record_execution_event_v1',params,delegation);end if;
 reset role;
 return value;
exception when others then reset role;raise;
end$$;

do $$
declare value jsonb; project uuid; filters jsonb; own_file text; other_file text; gantt jsonb;
 capacity_filters jsonb:=jsonb_build_object('start',(clock_timestamp() at time zone 'America/Sao_Paulo')::date,'days',14,'project_id',null,'can_manage',true);
 resource uuid; resource_payload jsonb; booking_payload jsonb; submission uuid; changed jsonb; replay jsonb;
 cell_filters jsonb; cell_snapshot jsonb; cell_payload jsonb; operation text;
 queue_filters jsonb; queue_snapshot jsonb; queue_payload jsonb; planned_load jsonb;
 gantt_filters constant jsonb:='{"project_id":null,"cell_id":null,"include_closed":false,"project_details":true,"can_manage":false}';
begin
 update rm_private.sso_settings set require_sso=true where singleton;
 perform rm_private.activate_capacity_workshop_writes_v1();
 perform rm_private.activate_cell_availability_workshops_v1();
 perform rm_private.activate_queue_workshops_v1();
 if has_function_privilege('authenticated','public.rm_web_cell_queue_snapshot_v1(uuid)','execute')
  or has_function_privilege('authenticated','public.rm_web_planning_load_v1()','execute')
  or has_table_privilege('authenticated','rm_private.web_open_cell_allocations_v1','select') then
  raise exception 'A rota anterior ainda expõe fila ou carga fora da oficina.';
 end if;
 for office in 1..4 loop
  project:=em_fixture.id(100+office);
  value:=pg_temp.workshop_restore_read(office,'project_list',
   '{"q":"QA-MESMA-OS","status":null,"client":null,"cell":null,"page":1,"planning":true}');
  if (value->>'total')::int is distinct from 1 or (value->'rows'->0->>'id')::uuid is distinct from project then
   raise exception 'A busca pela mesma OS retornou projetos de outra oficina.';
  end if;
  value:=pg_temp.workshop_restore_read(office,'workshop_twin','{}');
  if (value->>'project_count')::int is distinct from 1 or (value->>'cell_count')::int is distinct from 1
   or (value->'projects'->0->>'id')::uuid is distinct from project
   or value->>'layout' is distinct from (case when office=1 then 'bma' else 'management' end) then
   raise exception 'A visão da oficina recuperada contém uma planta ou projeto incorreto.';
  end if;
  filters:=jsonb_build_object('cell_ids',jsonb_build_array(em_fixture.id(200+office)),
   'fields',jsonb_build_array('project_number','cell_name'));
  value:=pg_temp.workshop_restore_read(office,'planning_export',filters);
  if (value->>'row_count')::int is distinct from 1 or (value->'cells'->0->'rows'->0->>'project_id')::uuid is distinct from project then
   raise exception 'A exportação recuperada perdeu seu projeto.';
  end if;
  for gantt in select * from (values (gantt_filters), (gantt_filters||jsonb_build_object('cell_id',em_fixture.id(200+office))),
   (gantt_filters||jsonb_build_object('project_id',project,'include_closed',true))) v(filter) loop
   value:=pg_temp.workshop_restore_read(office,'gantt_snapshot',gantt);
   if (value->>'total')::int is distinct from 1 or (value->'items'->0->>'id')::uuid is distinct from em_fixture.id(300+office)
    or value->'items'->0->>'data_limite' is null or value->'items'->0->>'data_inicio' is null
    or (gantt->>'project_id' is not null and (value->'baseline'->>'id')::uuid is distinct from em_fixture.id(800+office)) then
    raise exception 'Uma das três visões do Gantt perdeu seu intervalo ou linha de base.';
   end if;
  end loop;
  value:=pg_temp.workshop_restore_read(office,'capacity_snapshot',capacity_filters||jsonb_build_object('project_id',project));
  if value->'totals' is distinct from '{"resources":1,"bookings":1}'::jsonb
   or value->'resources'->0->>'id' is distinct from em_fixture.id(810+office)::text
   or (value->'resources'->0->'booked_days'->0->>'minutes')::int is distinct from 60*office
   or value->'bookings'->0->>'project_id' is distinct from project::text
   or value->'project_plan'->'items'->0->>'can_edit' is distinct from 'true' then
   raise exception 'A restauração de capacidade misturou oficinas ou perdeu versões e reservas.';
  end if;
  resource_payload:='{"id":null,"expected_version":null,"name":"Torno local","kind":"maquina","active":true,"weekly_minutes":[480,480,480,480,480,480,480],"exceptions":[],"acknowledge_overload":false,"reason":"Teste local de capacidade"}';
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_capacity_resource',resource_payload,false);
   raise exception 'A gravação antiga contornou a confirmação da oficina.';
  exception when insufficient_privilege then null;
  end;
  submission:=gen_random_uuid();
  changed:=pg_temp.workshop_restore_planning_write(office,submission,'save_capacity_resource',resource_payload);
  replay:=pg_temp.workshop_restore_planning_write(office,submission,'save_capacity_resource',resource_payload);
  resource:=(changed->>'id')::uuid;
  if replay->>'id' is distinct from resource::text or replay->>'idempotent_replay' is distinct from 'true'
   or not exists(select 1 from rm_private.capacity_resources r where r.id=resource and r.workshop_id=em_fixture.id(office)) then
   raise exception 'A gravação de capacidade não preservou oficina e protocolo.';
  end if;
  select jsonb_build_object('resource_id',resource,'expected_resource_version',rm_private.capacity_resource_version_v1(resource),
   'allocation_id',a.id,'expected_allocation_updated_at',a.updated_at,'expected_project_version',rm_private.web_gantt_project_version_v1(a.projeto_id),
   'days',jsonb_build_array(jsonb_build_object('date',(capacity_filters->>'start')::date+1,'minutes',30)),
   'reason','Teste local de reserva','acknowledge_overload',false) into strict booking_payload
  from public.rm_celulas_projeto a where a.id=em_fixture.id(300+office);
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_capacity_bookings',
    jsonb_set(booking_payload,'{allocation_id}',to_jsonb(em_fixture.id(300+(office % 4)+1))));
   raise exception 'A gravação de capacidade reservou uma etapa estrangeira.';
  exception when insufficient_privilege then null;
  end;
  submission:=gen_random_uuid();
  changed:=pg_temp.workshop_restore_planning_write(office,submission,'save_capacity_bookings',booking_payload);
  replay:=pg_temp.workshop_restore_planning_write(office,submission,'save_capacity_bookings',booking_payload);
  if changed->'record'->>'changed_days' is distinct from '1' or replay->>'idempotent_replay' is distinct from 'true'
   or (select count(*) from rm_private.capacity_bookings b where b.resource_id=resource)<>1 then
   raise exception 'A reserva própria não manteve uma única gravação no reenvio.';
  end if;
  perform pg_temp.workshop_restore_sso(office);
  set local role authenticated;
  value:=public.rm_web_capacity_snapshot_v1(capacity_filters-'can_manage');
  reset role;
  if value->'totals' is distinct from '{"resources":0,"bookings":0}'::jsonb then raise exception 'A leitura antiga devolveu recursos isolados.';end if;
  cell_filters:=jsonb_build_object('project_id',project,'allocation_id',em_fixture.id(300+office));
  cell_snapshot:=pg_temp.workshop_restore_read(office,'cell_availability',cell_filters);
  if cell_snapshot->'allocation'->>'id' is distinct from em_fixture.id(300+office)::text
   or cell_snapshot->>'can_retire' is distinct from 'false' or cell_snapshot->>'retire_reason' is null then
   raise exception 'A disponibilidade perdeu a alocação própria ou evidências existentes.';
  end if;
  if has_function_privilege('authenticated','public.rm_web_cell_availability_snapshot_v1(uuid,uuid)','execute')
   or has_function_privilege('authenticated','rm_private.cell_availability_metadata_v1(uuid)','execute') then
   raise exception 'A consulta antiga de disponibilidade continua exposta.';
  end if;
  cell_payload:=pg_temp.availability_payload(cell_snapshot,'set_visibility',false);
  foreach operation in array array['manage_cell_availability','manage_project_route_cell'] loop
   begin
    perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),operation,cell_payload,false);
    raise exception 'Gravação antiga contornou a oficina para mudar a alocação.';
   exception when insufficient_privilege then null;
   end;
   begin
    perform pg_temp.workshop_restore_planning_write((office % 4)+1,gen_random_uuid(),operation,cell_payload);
    raise exception 'Gravação permitiu alterar alocação de outra oficina.';
   exception when insufficient_privilege then null;
   end;
  end loop;
  submission:=gen_random_uuid();
  changed:=pg_temp.workshop_restore_planning_write(office,submission,'manage_cell_availability',cell_payload);
  replay:=pg_temp.workshop_restore_planning_write(office,submission,'manage_cell_availability',cell_payload);
  value:=pg_temp.workshop_restore_read(office,'cell_availability',cell_filters);
  if changed->'record'->>'visibilidade' is distinct from 'false' or replay->>'idempotent_replay' is distinct from 'true'
   or value->>'in_queue' is distinct from 'true' or value->'allocation'->>'visibilidade' is distinct from 'false'
   or (select count(*) from rm_private.cell_availability_events e where e.client_submission_id=submission)<>1 then
   raise exception 'Ocultar a alocação não preservou fila, histórico ou protocolo.';
  end if;
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'manage_cell_availability',
   pg_temp.availability_payload(value,'set_visibility',true));
  value:=pg_temp.workshop_restore_read(office,'form_record_project',jsonb_build_object('id',em_fixture.id(500+office)));
  if (value->>'project_id')::uuid is distinct from project then raise exception 'Formulário próprio indisponível.';end if;
  value:=pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(600+office),'source','project_photo'));
  if not exists(select 1 from storage.objects o where o.id=em_fixture.id(700+office) and o.bucket_id='rm-fotos'
   and value->>'file'='https://fixture.invalid/storage/v1/object/authenticated/rm-fotos/'||o.name) then
   raise exception 'Referência de mídia e metadado de armazenamento divergentes.';
  end if;
  select foto_url into strict own_file from public.rm_fotos where id=em_fixture.id(780+office);
  value:=pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(780+office),'source','project_photo'));
  if value->>'file' is distinct from own_file or
   pg_temp.workshop_restore_native(office,array[own_file])->'files'->0->>'url' is distinct from own_file then
   raise exception 'A foto privada recuperada precisa estar disponível no portal e no Android.';
  end if;
  begin
   perform pg_temp.workshop_restore_native(office,array[own_file],false);
   raise exception 'A ausência de confirmação da Central autorizou uma foto.';
  exception when insufficient_privilege then null;
  end;
  delete from public.rm_tablet_celula_users where identidade_id=em_fixture.id(740+office);
  if pg_temp.workshop_restore_native(office,array[own_file])->'files' is distinct from '[]'::jsonb then
   raise exception 'O Android liberou um arquivo após retirar a célula do operador.';
  end if;
  insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(em_fixture.id(200+office),em_fixture.id(740+office));
  for foreign_office in 1..4 loop
   if foreign_office=office then continue;end if;
   if pg_temp.workshop_restore_read(office,'project_qr',jsonb_build_object('id',em_fixture.id(100+foreign_office))) is not null
    or pg_temp.workshop_restore_read(office,'form_record_project',jsonb_build_object('id',em_fixture.id(500+foreign_office))) is not null
    or pg_temp.workshop_restore_read(office,'gantt_snapshot',gantt_filters||jsonb_build_object('cell_id',em_fixture.id(200+foreign_office))) is not null
    or pg_temp.workshop_restore_read(office,'gantt_snapshot',gantt_filters||jsonb_build_object('project_id',em_fixture.id(100+foreign_office),'include_closed',true)) is not null
    or pg_temp.workshop_restore_read(office,'capacity_snapshot',capacity_filters||jsonb_build_object('project_id',em_fixture.id(100+foreign_office))) is not null
    or pg_temp.workshop_restore_read(office,'cell_availability',jsonb_build_object(
     'project_id',em_fixture.id(100+foreign_office),'allocation_id',em_fixture.id(300+foreign_office))) is not null
    or pg_temp.workshop_restore_read(office,'cell_queue',jsonb_build_object('cell_id',em_fixture.id(200+foreign_office))) is not null
    or pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(600+foreign_office),'source','project_photo')) is not null
    or pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(780+foreign_office),'source','project_photo')) is not null then
    raise exception 'Uma referência direta retornou dados de outra oficina.';
   end if;
   select foto_url into strict other_file from public.rm_fotos where id=em_fixture.id(780+foreign_office);
   value:=pg_temp.workshop_restore_native(office,array[own_file,other_file]);
   if jsonb_array_length(value->'files') is distinct from 1 or value->'files'->0->>'url' is distinct from own_file then
    raise exception 'O Android autorizou um arquivo estrangeiro.';
   end if;
   begin
    perform pg_temp.workshop_restore_read(office,'planning_export',jsonb_set(filters,'{cell_ids}',jsonb_build_array(em_fixture.id(200+foreign_office))));
    raise exception 'Uma célula estrangeira foi exportada.';
   exception when insufficient_privilege then null;
   end;
  end loop;

  -- An unused allocation can still be retired and restored with its original ID.
  insert into public.rm_projetos(id,nome,status_pcp) values(em_fixture.id(900+office),'Projeto local sem registros','executando');
  insert into rm_private.workshop_project_ownership(id,workshop_id) values(em_fixture.id(900+office),em_fixture.id(office));
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,posicao,indice)
   values(em_fixture.id(910+office),em_fixture.id(900+office),em_fixture.id(200+office),true,7,8);
  cell_filters:=jsonb_build_object('project_id',em_fixture.id(900+office),'allocation_id',em_fixture.id(910+office));
  value:=pg_temp.workshop_restore_read(office,'cell_availability',cell_filters);
  if value->>'can_retire' is distinct from 'true'
   or pg_temp.workshop_restore_read(office,'cell_availability',cell_filters||jsonb_build_object('project_id',project)) is not null then
   raise exception 'Disponibilidade não conferiu o par exato ou a retirada de alocação sem uso.';
  end if;
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'manage_cell_availability',pg_temp.availability_payload(value,'retire'));
  value:=pg_temp.workshop_restore_read(office,'cell_availability',cell_filters);
  if value->>'can_restore' is distinct from 'true' or value->>'in_queue' is distinct from 'false' then
   raise exception 'A alocação retirada ainda aparece na fila ou perdeu o caminho de restauração.';
  end if;
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'manage_cell_availability',pg_temp.availability_payload(value,'restore'));
  value:=pg_temp.workshop_restore_read(office,'cell_availability',cell_filters);
  if value->'allocation'->>'id' is distinct from em_fixture.id(910+office)::text
   or value->'allocation'->>'visibilidade' is distinct from 'false' or value->>'in_queue' is distinct from 'true' then
   raise exception 'A restauração da alocação deve preservar ID, fila e visibilidade explícita.';
  end if;

  queue_filters:=jsonb_build_object('cell_id',em_fixture.id(200+office));
  queue_snapshot:=pg_temp.workshop_restore_read(office,'cell_queue',queue_filters);
  planned_load:=pg_temp.workshop_restore_read(office,'planning_load','{}');
  value:=pg_temp.workshop_restore_read(office,'gantt_cells','{}');
  if queue_snapshot->>'total' is distinct from '2' or queue_snapshot->'items'->0->>'id' is distinct from em_fixture.id(300+office)::text
   or queue_snapshot->'items'->1->>'visibilidade' is distinct from 'false'
   or jsonb_array_length(planned_load->'cells') is distinct from 1
   or planned_load->'cells'->0->>'id' is distinct from em_fixture.id(200+office)::text
   or planned_load->'cells'->0->>'open_allocations' is distinct from '2'
   or planned_load->'cells'->0->>'hidden_allocations' is distinct from '1'
   or planned_load->'cells'->0->>'unestimated_allocations' is distinct from '1'
   or (planned_load->'cells'->0->>'planned_hours')::numeric is distinct from 1.25*office
   or jsonb_array_length(value) is distinct from 1 or value->0->>'id' is distinct from em_fixture.id(200+office)::text then
   raise exception 'Fila, seleção e carga divergiram da oficina ou perderam posições e horas.';
  end if;
  queue_payload:=pg_temp.queue_payload(queue_snapshot,false);
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_cell_queue',queue_payload,false);
   raise exception 'O gravador anterior contornou a autorização da oficina.';
  exception when insufficient_privilege then null;
  end;
  begin
   perform pg_temp.workshop_restore_planning_write((office % 4)+1,gen_random_uuid(),'save_cell_queue',queue_payload);
   raise exception 'Uma oficina estrangeira alterou a fila.';
  exception when insufficient_privilege then null;
  end;
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_cell_queue',
    jsonb_set(queue_payload,'{items,0,id}',to_jsonb(em_fixture.id(300+(office % 4)+1))));
   raise exception 'Uma alocação estrangeira entrou na fila autorizada.';
  exception when insufficient_privilege then null;
  end;
  submission:=gen_random_uuid();
  changed:=pg_temp.workshop_restore_planning_write(office,submission,'save_cell_queue',queue_payload);
  replay:=pg_temp.workshop_restore_planning_write(office,submission,'save_cell_queue',queue_payload);
  value:=pg_temp.workshop_restore_read(office,'cell_queue',queue_filters);
  if changed->'record'->>'queue_version' is distinct from value->>'queue_version'
   or value->>'queue_version'=queue_snapshot->>'queue_version'
   or replay->>'idempotent_replay' is distinct from 'true'
   or exists(select 1 from jsonb_array_elements(value->'items') row where row->>'posicao' is distinct from '7'
    or row->>'prioridade' is distinct from 'alta') then
   raise exception 'A atualização só de prioridades não preservou as posições duplicadas e o reenvio.';
  end if;
  queue_snapshot:=value;
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_cell_queue',queue_payload);
   raise exception 'Uma versão antiga da fila permitiu outra gravação.';
  exception when sqlstate 'PT409' then null;
  end;
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_cell_queue',pg_temp.queue_payload(queue_snapshot,true));
  value:=pg_temp.workshop_restore_read(office,'cell_queue',queue_filters);
  if value->'items'->0->>'id' is distinct from em_fixture.id(910+office)::text
   or value->'items'->0->>'posicao' is distinct from '1' or value->'items'->0->>'indice' is distinct from '8'
   or value->'items'->1->>'posicao' is distinct from '2' or value->'items'->1->>'indice' is distinct from '5' then
   raise exception 'A reordenação explícita não manteve o índice do roteiro.';
  end if;

  -- Legacy work without a classified project can arrive before the general cutover.
  -- It is excluded from totals and blocks reordering until its origin is confirmed.
  queue_payload:=pg_temp.queue_payload(value,true);
  begin
   insert into public.rm_projetos(id,nome,status_pcp) values(em_fixture.id(950+office),'Origem pendente local','executando');
   insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,horas_previstas)
    values(em_fixture.id(960+office),em_fixture.id(950+office),em_fixture.id(200+office),true,999);
   if pg_temp.workshop_restore_read(office,'cell_queue',queue_filters) is distinct from value
    or pg_temp.workshop_restore_read(office,'planning_load','{}')->'cells' is distinct from planned_load->'cells' then
    raise exception 'Trabalho sem origem entrou nos dados da oficina.';
   end if;
   begin
    perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_cell_queue',queue_payload);
    raise exception 'A fila foi reordenada com a origem de um trabalho pendente.';
   exception when sqlstate 'PT409' then null;
   end;
   raise exception using errcode='P0999',message='Rollback only for unclassified local fixture';
  exception when sqlstate 'P0999' then null;
  end;
 end loop;
end$$;

do $workshop_execution$
declare filters jsonb; native jsonb; portal jsonb; params jsonb; changed jsonb; retry jsonb; submission uuid; cell uuid;
begin
 perform rm_private.activate_execution_workshops_v1('web');
 perform rm_private.activate_execution_workshops_v1('mobile');
 if has_function_privilege('authenticated','public.rm_web_execution_snapshot_v1(jsonb)','execute')
  or has_function_privilege('authenticated','public.rm_mobile_execution_snapshot_v1(text,uuid)','execute')
  or has_function_privilege('authenticated','rm_private.execution_session_detail_v1(uuid)','execute')
  or has_table_privilege('authenticated','rm_private.execution_sessions','select')
  or has_table_privilege('authenticated','rm_private.execution_reviews','select')
  or has_table_privilege('authenticated','rm_private.execution_events','select') then
  raise exception 'Um contrato direto ainda expõe apontamentos sem o vínculo de oficina.';
 end if;
 for office in 1..4 loop
  filters:=jsonb_build_object('project_id',em_fixture.id(100+office),'cell_id',em_fixture.id(200+office),
   'session_id',em_fixture.id(970+office),'include_closed',false);
  portal:=pg_temp.workshop_restore_read(office,'execution_snapshot',filters);
  native:=public.rm_mobile_workshop_execution_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),
   pg_temp.workshop_restore_native_context(office,office),em_fixture.id(300+office));
  if portal->>'total' is distinct from '1' or portal->'detail'->'events'->0->>'id' is distinct from em_fixture.id(980+office)::text
   or native->>'workshop_id' is distinct from em_fixture.id(office)::text
   or native->'snapshot'->'running_session'->>'id' is distinct from em_fixture.id(970+office)::text then
   raise exception 'A restauração perdeu o apontamento ativo da própria oficina.';
  end if;
  for outsider in 1..4 loop
   if outsider=office then continue;end if;
   if pg_temp.workshop_restore_read(outsider,'execution_snapshot','{"project_id":null,"cell_id":null,"include_closed":true}'
    || jsonb_build_object('session_id',em_fixture.id(970+office))) is not null then
    raise exception 'Um apontamento estrangeiro apareceu na sessão de gestão.';
   end if;
   begin
    perform public.rm_mobile_workshop_execution_v1(em_fixture.id(710+outsider),em_fixture.id(720+outsider),repeat(chr(96+outsider),64),
     pg_temp.workshop_restore_native_context(outsider,outsider),em_fixture.id(300+office));
    raise exception 'Um apontamento estrangeiro apareceu no dispositivo.';
   exception when sqlstate 'P0002' then null;
   end;
  end loop;
  cell:=em_fixture.id(200+(office % 4)+1);
  insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(cell,em_fixture.id(740+office));
  native:=public.rm_mobile_workshop_execution_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),
   pg_temp.workshop_restore_native_context((office % 4)+1,office),em_fixture.id(300+(office % 4)+1));
  if native->'snapshot'->'running_session' is distinct from 'null'::jsonb then
   raise exception 'Uma transferência mostrou a sessão ativa da oficina anterior.';
  end if;
  delete from public.rm_tablet_celula_users where celula_id=cell and identidade_id=em_fixture.id(740+office);
  params:=jsonb_build_object('p_session_id',em_fixture.id(970+office),'p_allocation_id',em_fixture.id(300+office),
   'p_operador_id',em_fixture.id(740+office),'p_kind','pause','p_previous_event_id',em_fixture.id(980+office),
   'p_occurred_at',clock_timestamp(),'p_pause_reason','intervalo','p_note',null,'p_effort_minutes',null);
  begin
   perform pg_temp.workshop_restore_execution_event(office,gen_random_uuid(),params,false);
   raise exception 'O cliente legado gravou apontamento diretamente após o corte.';
  exception when insufficient_privilege then null;
  end;
  submission:=gen_random_uuid();
  changed:=pg_temp.workshop_restore_execution_event(office,submission,params,true);
  retry:=pg_temp.workshop_restore_execution_event(office,submission,params,true);
  if changed->>'disposition' is distinct from 'accepted' or retry->>'idempotent_replay' is distinct from 'true'
   or not exists(select 1 from rm_private.execution_sessions where id=em_fixture.id(970+office) and state='paused')
   or (select count(*) from rm_private.execution_events where session_id=em_fixture.id(970+office))<>2 then
   raise exception 'O protocolo de pausa reenviado não manteve a autoria e a gravação única.';
  end if;
  portal:=pg_temp.workshop_restore_read(office,'execution_snapshot',filters);
  params:=jsonb_build_object('session_id',em_fixture.id(970+office),'expected_version',portal->'detail'->'session'->'version',
   'action','confirm_finished','reported_finished_at',clock_timestamp(),'effort_minutes',30,'note','',
   'reason','Revisão transacional do ensaio local');
  begin
   perform pg_temp.workshop_restore_planning_write((office % 4)+1,gen_random_uuid(),'review_execution_session',params);
   raise exception 'Uma oficina estrangeira revisou um apontamento.';
  exception when insufficient_privilege then null;
  end;
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'review_execution_session',params,false);
   raise exception 'Um gravador sem contexto revisou um apontamento.';
  exception when insufficient_privilege then null;
  end;
  submission:=gen_random_uuid();
  perform pg_temp.workshop_restore_planning_write(office,submission,'review_execution_session',params);
  retry:=pg_temp.workshop_restore_planning_write(office,submission,'review_execution_session',params);
  portal:=pg_temp.workshop_restore_read(office,'execution_snapshot',filters);
  if retry->>'idempotent_replay' is distinct from 'true' or portal->'detail'->>'reviews_total' is distinct from '1'
   or portal->'detail'->'session'->>'confirmed_minutes' is distinct from '30' then
   raise exception 'O portal perdeu a revisão autorizada ou gravou o reenvio novamente.';
  end if;
 end loop;
end
$workshop_execution$;

do $workshop_engineering$
declare original jsonb; title jsonb; choices jsonb; payload jsonb; own_cell uuid; foreign_cell uuid;
 target uuid; protocol uuid; deletion jsonb;
begin
 begin
  perform rm_private.activate_engineering_workshops_v1(3);
  raise exception 'O corte aceitou um lote de títulos diferente do aprovado.';
 exception when sqlstate 'PT409' then null;
 end;
 perform rm_private.activate_engineering_workshops_v1(4);
 if has_function_privilege('authenticated','public.rm_web_engineering_snapshot_v1(uuid)','execute')
  or has_table_privilege('authenticated','rm_private.engineering_photo_title_scope','select') then
  raise exception 'A leitura direta ainda contorna o contexto atual da engenharia.';
 end if;
 for office in 1..4 loop
  own_cell:=em_fixture.id(200+office);
  choices:=pg_temp.workshop_restore_read(office,'engineering_choices','{"id":null}');
  if choices->'cells'->0->>'id' is distinct from own_cell::text
   or jsonb_array_length(choices->'cells')<>1
   or choices->'users'->0->>'id' is distinct from em_fixture.id(740+office)::text
   or jsonb_array_length(choices->'users')<>1
   or choices->'photoTitles'->0->>'celula_id' is distinct from own_cell::text then
   raise exception 'As opções de engenharia misturaram oficinas.';
  end if;
  original:=pg_temp.workshop_restore_read(office,'engineering_matrix',jsonb_build_object('type',em_fixture.id(1100+office)));
  if original->'rows'->0->>'id' is distinct from em_fixture.id(1110+office)::text
   or original->'rows'->0->>'form_count' is distinct from '1'
   or original->'rows'->0->>'photo_count' is distinct from '1' then
   raise exception 'A matriz perdeu os vínculos próprios após a restauração.';
  end if;
  for outsider in 1..4 loop
   if outsider=office then continue;end if;
   foreign_cell:=em_fixture.id(200+outsider);
   if pg_temp.workshop_restore_read(outsider,'engineering_entry',jsonb_build_object('id',em_fixture.id(1110+office))) is not null
    or pg_temp.workshop_restore_read(outsider,'photo_title_entry',jsonb_build_object('id',em_fixture.id(1120+office))) is not null
    or pg_temp.workshop_restore_read(office,'engineering_matrix',jsonb_build_object('type',em_fixture.id(1100+outsider)))->'rows' <> '[]'::jsonb
    or pg_temp.workshop_restore_read(office,'photo_title_list',jsonb_build_object('cell',foreign_cell,'q','frontal','page',1))->>'total'<>'0' then
    raise exception 'A pesquisa ou o link de engenharia expôs dados cruzados.';
   end if;
  end loop;
  title:=pg_temp.workshop_restore_read(office,'photo_title_entry',jsonb_build_object('id',em_fixture.id(1120+office)));
  payload:=jsonb_build_object('id',em_fixture.id(1120+office),'expected_updated_at',title->'updated_at','changes','{"numero":12}'::jsonb);
  begin
   perform pg_temp.workshop_restore_engineering_write((office % 4)+1,gen_random_uuid(),'save_photo_title',payload);
   raise exception 'Outra oficina alterou um título de foto.';
  exception when insufficient_privilege then null;
  end;
  begin
   perform pg_temp.workshop_restore_engineering_write(office,gen_random_uuid(),'save_photo_title',payload,false);
   raise exception 'Título editado sem autorização recente da oficina.';
  exception when insufficient_privilege then null;
  end;
  original:=pg_temp.workshop_restore_read(office,'engineering_entry',jsonb_build_object('id',em_fixture.id(1110+office)));
  payload:=jsonb_build_object('id',em_fixture.id(1110+office),'expected_updated_at',original->'matrix'->'updated_at',
   'celula_id',own_cell,'tipo_equipamento_id',em_fixture.id(1100+office),'changes',
   jsonb_build_object('form_ids',jsonb_build_array(em_fixture.id(400+(office % 4)+1))));
  begin
   perform pg_temp.workshop_restore_engineering_write(office,gen_random_uuid(),'save_engineering',payload);
   raise exception 'A configuração aceitou formulário de outra oficina.';
  exception when insufficient_privilege then null;
  end;
  payload:=jsonb_set(payload,'{changes}',jsonb_build_object('photos',jsonb_build_array(
   jsonb_build_object('id',gen_random_uuid(),'cadastro_foto_id',em_fixture.id(1120+(office % 4)+1),'numero',2,'descricao',null))));
  begin
   perform pg_temp.workshop_restore_engineering_write(office,gen_random_uuid(),'save_engineering',payload);
   raise exception 'A configuração aceitou título de outra oficina.';
  exception when insufficient_privilege then null;
  end;
  begin
   insert into public.rm_fotos(celula_id,celula_tipo_equipamento_id,categoria_foto,cadastro_foto_id,titulo,numero)
   values(own_cell,em_fixture.id(1110+office),'obrigat_ria',em_fixture.id(1120+(office % 4)+1),'Frontal',2);
   raise exception 'A gravação direta vinculou título de outra oficina.';
  exception when insufficient_privilege then null;
  end;
  payload:=jsonb_set(payload,'{changes}','{"visibilidade":true}');
  protocol:=gen_random_uuid();
  perform pg_temp.workshop_restore_engineering_write(office,protocol,'save_engineering',payload);
  if pg_temp.workshop_restore_engineering_write(office,protocol,'save_engineering',payload)->>'idempotent_replay' is distinct from 'true' then
   raise exception 'O reenvio da engenharia perdeu seu recibo.';
  end if;
  target:=gen_random_uuid();
  payload:=jsonb_build_object('id',target,'expected_updated_at',null,
    'changes',jsonb_build_object('titulo','Detalhe','celula_id',own_cell));
  title:=pg_temp.workshop_restore_engineering_write(office,gen_random_uuid(),'save_photo_title',payload);
  if not exists(select 1 from rm_private.engineering_photo_title_scope t where t.title_id=target and t.cell_id=own_cell
   and t.workshop_id=em_fixture.id(office)) then raise exception 'O título novo ficou sem origem durável.';end if;
  deletion:=jsonb_build_object('id',target,'expected_updated_at',title->'updated_at');
  protocol:=gen_random_uuid();
  perform pg_temp.workshop_restore_engineering_write(office,protocol,'delete_photo_title',deletion);
  if pg_temp.workshop_restore_engineering_write(office,protocol,'delete_photo_title',deletion)->>'idempotent_replay' is distinct from 'true'
   or pg_temp.workshop_restore_read(office,'photo_title_entry',jsonb_build_object('id',target)) is not null then
   raise exception 'A exclusão deixou um título visível ou perdeu o recibo.';
  end if;
  begin
   perform pg_temp.workshop_restore_engineering_write(office,gen_random_uuid(),'save_photo_title',payload);
   raise exception 'Um título encerrado teve sua identidade reutilizada.';
  exception when insufficient_privilege then null;
  end;
  update public.rm_celulas set nome='Célula renomeada '||office where id=own_cell;
  title:=pg_temp.workshop_restore_read(office,'photo_title_entry',jsonb_build_object('id',em_fixture.id(1120+office)));
  if title->>'celula_id' is distinct from own_cell::text or title->>'celula_nome' is distinct from 'Célula renomeada '||office then
   raise exception 'O nome antigo mudou o vínculo de um título existente.';
  end if;
 end loop;
end
$workshop_engineering$;

do $workshop_team$
declare params jsonb; roster jsonb; result jsonb; other_params jsonb; context jsonb; request_id uuid;
begin
 for office in 1..4 loop
  roster:=jsonb_build_array(jsonb_build_object('kind','corporate','subject',em_fixture.id(50+office)),
   jsonb_build_object('kind','operator','subject',em_fixture.id(740+office)));
  params:=jsonb_build_object('q','','page',1,'members',roster);
  result:=pg_temp.workshop_restore_read(office,'workshop_team',params);
  if result->>'total' is distinct from '2' or not (result->'rows' @> jsonb_build_array(
   jsonb_build_object('id',em_fixture.id(30+office)),jsonb_build_object('id',em_fixture.id(740+office))))
   or exists(select 1 from jsonb_array_elements(result->'rows') row where row ?| array['auth_user_id','email','foto_url','subject']) then
   raise exception 'A equipe perdeu o vínculo corporativo ou operacional ou retornou dados internos.';
  end if;
  for other in 1..4 loop
   if other=office then continue;end if;
   if pg_temp.workshop_restore_read(office,'workshop_team',params||jsonb_build_object('q','Operador local '||other))->>'total' is distinct from '0' then
    raise exception 'A busca contou operador de outra oficina.';
   end if;
  end loop;
  result:=pg_temp.workshop_restore_read(office,'workshop_team',params||'{"page":2}');
  if result->>'total' is distinct from '2' or result->'rows' is distinct from '[]'::jsonb then
   raise exception 'A paginação da equipe perdeu os totais filtrados.';
  end if;
  context:=pg_temp.workshop_restore_sso(office);
  request_id:=gen_random_uuid();
  perform public.rm_sso_workshop_read_permit_v1(repeat(office::text,64),request_id,'workshop_team',params,context);
  other_params:=params||jsonb_build_object('members',roster||jsonb_build_array(
   jsonb_build_object('kind','operator','subject',em_fixture.id(740+(office % 4)+1))));
  begin
   set local role authenticated;
   perform public.rm_web_workshop_read_v1(request_id,'workshop_team',other_params);
   raise exception 'A lista de pessoas foi alterada depois da verificação.';
  exception when insufficient_privilege then reset role;
  end;
  set local role authenticated;
  result:=public.rm_web_workshop_read_v1(request_id,'workshop_team',params);
  reset role;
  if result->'data'->>'total' is distinct from '2' then raise exception 'O protocolo íntegro não foi aceito.';end if;
  result:=pg_temp.workshop_restore_read(office,'workshop_team',params||jsonb_build_object('members',roster-1));
  if result->>'total' is distinct from '1' or not exists(select 1 from public.rm_tablet_celula_users
   where identidade_id=em_fixture.id(740+office) and celula_id=em_fixture.id(200+office)) then
   raise exception 'O vínculo revogado continuou na equipe ou alterou a permissão histórica da célula.';
  end if;
 end loop;
end
$workshop_team$;

create function pg_temp.workshop_assignment_write(office integer,submission uuid,operation text,payload jsonb,members jsonb,
 ttl interval default interval '10 seconds') returns jsonb language plpgsql as $$
declare context jsonb:=pg_temp.workshop_restore_sso(office); result jsonb; hash text:=repeat(office::text,64);
begin
 context:=jsonb_set(context,'{expires_at}',to_jsonb((context->>'issued_at')::timestamptz+ttl));
 if members is not null then
  perform public.rm_sso_assignment_workshop_permit_v1(hash,submission,operation,payload,context,members);
 end if;
 if operation='save_engineering' then
  perform public.rm_sso_engineering_workshop_permit_v1(hash,submission,operation,payload,context);
 else
  perform public.rm_sso_action_permit_v1(hash,submission,operation,payload,
   case when operation='save_project' then 'em.projects.manage' else 'em.planning.manage' end);
 end if;
 set local role authenticated;
 result:=public.rm_web_mutate_v1(submission,operation,payload);
 reset role;
 return result;
exception when others then reset role;raise;
end
$$;

do $assignments$
declare project uuid; allocation uuid; cell uuid; destination uuid; operator_id uuid; external_id uuid; model uuid;
 roster jsonb; other jsonb; args jsonb; editor jsonb; result jsonb; plan jsonb; manager jsonb; reviewer jsonb; stage jsonb; engineering jsonb;
 protocol uuid; rule_id uuid; note jsonb; rejected integer:=0;
begin
 perform rm_private.activate_workshop_assignments_v1();
 if has_function_privilege('authenticated','public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean)','execute')
  or has_function_privilege('authenticated','public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean)','execute')
  or has_function_privilege('authenticated','public.rm_sso_assignment_workshop_permit_v1(text,uuid,text,jsonb,jsonb,jsonb)','execute') then
  raise exception 'A leitura ou emissão direta de atribuições ficou acessível.';
 end if;
 for office in 1..4 loop
  project:=em_fixture.id(100+office);
  cell:=em_fixture.id(200+office);
  allocation:=em_fixture.id(300+office);
  destination:=em_fixture.id(1200+office);
  model:=em_fixture.id(400+office);
  operator_id:=em_fixture.id(740+office);
  external_id:=em_fixture.id(740+(office % 4)+1);
  roster:=jsonb_build_array(jsonb_build_object('kind','corporate','subject',em_fixture.id(50+office)),
   jsonb_build_object('kind','operator','subject',operator_id));
  insert into public.rm_celulas(id,nome) values(destination,'Destino local '||office);
  insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(destination,em_fixture.id(office));
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
   values(em_fixture.id(1210+office),project,destination,'em_dia',true);
  insert into public.rm_tablet_celula_users(celula_id,identidade_id)
   values(cell,external_id),(destination,operator_id),(destination,external_id);
  update public.rm_celulas_projeto set forms_ids=array[model],status='em_dia' where id=allocation;
  args:=jsonb_build_object('project',project,'allocation',allocation,'include',true,'members',roster);
  result:=pg_temp.workshop_restore_read(office,'assignment_people',jsonb_build_object('purpose','project','members',roster));
  if jsonb_array_length(result)<>2 or not result @> jsonb_build_array(jsonb_build_object('id',operator_id)) then
   raise exception 'O seletor de pessoas divergiu da equipe ativa.';
  end if;
  editor:=pg_temp.workshop_restore_read(office,'engineering_assignment_choices',
   jsonb_build_object('id',em_fixture.id(1110+office),'members',roster));
  if jsonb_array_length(editor->'users')<>1 or editor->'users'->0->>'id'<>operator_id::text
   or exists(select 1 from jsonb_array_elements(editor->'cellUserLinks') l where l->>'identidade_id'=external_id::text) then
   raise exception 'A engenharia retornou pessoa fora da equipe.';
  end if;
  for outsider in 1..4 loop
   if outsider=office then continue;end if;
   other:=args||jsonb_build_object('project',em_fixture.id(100+outsider),'allocation',em_fixture.id(300+outsider));
   if pg_temp.workshop_restore_read(office,'operational_reviewers',other) is not null
    or pg_temp.workshop_restore_read(office,'operational_stage_rules',other) is not null
    or pg_temp.workshop_restore_read(office,'engineering_assignment_choices',
     jsonb_build_object('id',em_fixture.id(1110+outsider),'members',roster)) is not null then
    raise exception 'Consulta de atribuição atravessou a oficina.';
   end if;
  end loop;
  result:=pg_temp.workshop_restore_read(office,'operational_reviewers',args);
  if result->>'eligible_total' is distinct from '1' or result->'eligible_users'->0->>'id' is distinct from operator_id::text
   or result->'forms'->0->>'id' is distinct from model::text or result->'forms'->0->>'can_assign' is distinct from 'true'
   or pg_temp.workshop_restore_read(office,'operational_reviewers',(args-'members')||'{"include":false}')->'eligible_users'<>'[]' then
   raise exception 'O histórico ou seletor de avaliadores não corresponde à oficina.';
  end if;
  reviewer:=jsonb_build_object('projeto_id',project,'celula_projeto_id',allocation,'form_id',model,'avaliador_user_id',operator_id,
   'expected_project_updated_at',result->'project'->'updated_at','expected_allocation_updated_at',result->'allocation'->'updated_at',
   'expected_context_version',result->'forms'->0->'context_version','confirm_replace',true);
  result:=pg_temp.workshop_restore_read(office,'operational_stage_rules',args);
  if result->>'eligible_total' is distinct from '1' or result->>'memberships_total' is distinct from '2'
   or result->'eligible_users'->0->>'id' is distinct from operator_id::text then
   raise exception 'A regra operacional retornou opções fora da equipe.';
  end if;
  rule_id:=gen_random_uuid();
  note:=jsonb_build_object('celula_destino_id',destination,'status_cel_proj','pendente','bloquear_avanco_sem_aprov',true,
   'aprovadores_ids',jsonb_build_array(operator_id),'aprovadores_retorno_ids',jsonb_build_array(operator_id));
  stage:=jsonb_build_object('action','create','id',rule_id,'projeto_id',project,'celula_projeto_id',allocation,
   'expected_project_updated_at',result->'project'->'updated_at','expected_allocation_updated_at',result->'allocation'->'updated_at',
   'expected_rules_version',result->'rules_version','config',note);
  engineering:=jsonb_build_object('id',em_fixture.id(1110+office),'celula_id',cell,'tipo_equipamento_id',em_fixture.id(1100+office),
   'expected_updated_at',(select updated_at from public.rm_celula_tipos_equipamento where id=em_fixture.id(1110+office)),
   'changes',jsonb_build_object('stages',jsonb_build_array(note||jsonb_build_object('id',gen_random_uuid()))));
  plan:=jsonb_build_object('projeto_id',project,'celula_id',cell,
   'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=allocation),
   'changes',jsonb_build_object('responsavel_id',operator_id));
  manager:=jsonb_build_object('id',project,'expected_updated_at',(select updated_at from public.rm_projetos where id=project),
   'changes',jsonb_build_object('gestor_responsavel_id',em_fixture.id(30+office)));

  for note in select value from jsonb_array_elements(jsonb_build_array(
   jsonb_build_object('operation','save_project','payload',jsonb_set(manager,'{changes,gestor_responsavel_id}',to_jsonb(em_fixture.id(30+(office % 4)+1)))),
   jsonb_build_object('operation','plan_cell','payload',jsonb_set(plan,'{changes,responsavel_id}',to_jsonb(external_id))),
   jsonb_build_object('operation','assign_form_reviewer','payload',jsonb_set(reviewer,'{avaliador_user_id}',to_jsonb(external_id))),
   jsonb_build_object('operation','manage_stage_rules','payload',jsonb_set(stage,'{config,aprovadores_retorno_ids}',jsonb_build_array(external_id))),
   jsonb_build_object('operation','save_engineering','payload',jsonb_set(engineering,'{changes,stages,0,aprovadores_ids}',jsonb_build_array(external_id)))
  )) loop
   begin
    perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),note->>'operation',note->'payload',roster);
    raise exception 'Foi possível atribuir uma pessoa de outra oficina.';
   exception when insufficient_privilege then
    if sqlerrm not like '%vínculo ativo%' then raise;end if;
    rejected:=rejected+1;
   end;
  end loop;
  begin
   perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),'plan_cell',plan,null);
   raise exception 'Uma atribuição passou sem confirmação atual da equipe.';
  exception when insufficient_privilege then
   if sqlerrm not like '%Confirmação da equipe%' then raise;end if;
  end;
  perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),'manage_stage_rules',stage,roster);
  result:=pg_temp.workshop_restore_read(office,'operational_stage_rules',args);
  if not (result->'rules' @> jsonb_build_array(jsonb_build_object('id',rule_id,'aprovadores_ids',jsonb_build_array(operator_id)))) then
   raise exception 'O aprovador da oficina não foi preservado na regra.';
  end if;
  perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),'assign_form_reviewer',reviewer,roster);
  result:=pg_temp.workshop_restore_read(office,'operational_reviewers',args||jsonb_build_object('members',roster-1));
  if result->'forms'->0->'assignment'->>'avaliador_user_id' is distinct from operator_id::text
   or result->'forms'->0->'assignment'->>'eligible' is distinct from 'false' then
   raise exception 'A saída do avaliador da oficina alterou o histórico ou a elegibilidade.';
  end if;
  protocol:=gen_random_uuid();
  perform pg_temp.workshop_assignment_write(office,protocol,'plan_cell',plan,roster);
  if pg_temp.workshop_assignment_write(office,protocol,'plan_cell',plan,roster-1)->>'idempotent_replay' is distinct from 'true'
   or not exists(select 1 from public.rm_celulas_projeto where id=allocation and responsavel_id=operator_id) then
   raise exception 'A atribuição ou repetição de protocolo alterou o responsável.';
  end if;
  perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),'save_engineering',engineering,roster);
  result:=pg_temp.workshop_restore_read(office,'engineering_assignment_choices',
   jsonb_build_object('id',em_fixture.id(1110+office),'members',roster-1));
  if result->'cellUserLinks'<>'[]' or result->'users'->0->>'id' is distinct from operator_id::text then
   raise exception 'A engenharia perdeu a pessoa histórica ou deixou selecioná-la novamente.';
  end if;
  manager:=jsonb_set(manager,'{expected_updated_at}',to_jsonb((select updated_at from public.rm_projetos where id=project)));
  perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),'save_project',manager,roster);
  if (select gestor_responsavel_id from public.rm_projetos where id=project) is distinct from em_fixture.id(30+office) then
   raise exception 'O gestor corporativo da própria oficina não foi atribuído.';
  end if;
 end loop;
 if rejected<>20 or exists(select 1 from rm_private.workshop_assignment_permits) then
  raise exception 'Os protocolos cruzados ou consumidos não foram isolados.';
 end if;
end
$assignments$;
rollback;
select 'PASS: four offices, Gantt, capacity, availability, queue, load, execution, media; 156 denied cross-office reads, 24 crossed writes, 8 denied reads after revocation or unavailable authority' result;
select 'PASS: engineering and photo titles in four offices; 48 denied cross-office reads, 16 crossed writes' result;
select 'PASS: current team in four offices; 12 denied cross-office searches, 4 rejected member substitutions' result;
select 'PASS: assignment selectors and writes in four offices; 36 denied cross-office reads and 20 denied foreign people assignments' result;

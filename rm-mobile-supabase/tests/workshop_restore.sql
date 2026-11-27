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
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,retirada,visibilidade,data_inicio,data_limite)
 select em_fixture.id(300+n),em_fixture.id(100+n),em_fixture.id(200+n),false,true,clock_timestamp(),clock_timestamp()+interval '2 days' from generate_series(1,4)n;
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

create function pg_temp.availability_payload(snapshot jsonb,action text,visible boolean default null) returns jsonb
language sql as $$
 select jsonb_build_object(
  'action',action,'projeto_id',snapshot->'project'->'id','celula_projeto_id',snapshot->'allocation'->'id',
  'expected_project_updated_at',snapshot->'project'->'updated_at','expected_allocation_updated_at',snapshot->'allocation'->'updated_at',
  'expected_context_version',snapshot->'context_version','confirm_change',true)
  ||case when action='set_visibility' then jsonb_build_object('visibilidade',visible) else '{}'::jsonb end;
$$;

create function pg_temp.workshop_restore_native(office integer,urls text[],reachable boolean default true) returns jsonb language plpgsql as $$
declare context jsonb; stamp timestamptz:=clock_timestamp();
begin
 if reachable then
  select jsonb_build_object('version',2,'application','em','channel','mobile','authority',authority,
   'workshop',jsonb_build_object('id',id,'code',code,'name',code,'active',true,'revision',1,'updated_at',stamp),
   'principals',jsonb_build_array(jsonb_build_object('kind','device','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1',
    'subject',em_fixture.id(710+office),'revision',1),jsonb_build_object('kind','operator','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1',
    'subject',em_fixture.id(740+office),'revision',1)), 'issued_at',stamp,'expires_at',stamp+interval '5 minutes') into strict context
  from rm_private.workshop_references where id=em_fixture.id(office);
 end if;
 return public.rm_mobile_workshop_media_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),context,urls);
end$$;

do $$
declare value jsonb; project uuid; filters jsonb; own_file text; other_file text; gantt jsonb;
 capacity_filters jsonb:=jsonb_build_object('start',(clock_timestamp() at time zone 'America/Sao_Paulo')::date,'days',14,'project_id',null,'can_manage',true);
 resource uuid; resource_payload jsonb; booking_payload jsonb; submission uuid; changed jsonb; replay jsonb;
 cell_filters jsonb; cell_snapshot jsonb; cell_payload jsonb; operation text;
 gantt_filters constant jsonb:='{"project_id":null,"cell_id":null,"include_closed":false,"project_details":true,"can_manage":false}';
begin
 update rm_private.sso_settings set require_sso=true where singleton;
 perform rm_private.activate_capacity_workshop_writes_v1();
 perform rm_private.activate_cell_availability_workshops_v1();
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
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade)
   values(em_fixture.id(910+office),em_fixture.id(900+office),em_fixture.id(200+office),true);
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
 end loop;
end$$;
rollback;
select 'PASS: four offices, three Gantt views, capacity, availability, own media; 120 denied cross-office reads, 12 crossed writes, 8 denied reads after revocation or unavailable authority' result;

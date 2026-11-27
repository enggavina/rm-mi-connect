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
create function pg_temp.workshop_restore_read(office integer,resource text,args jsonb) returns jsonb language plpgsql as $$
declare request_id uuid:=gen_random_uuid(); context jsonb; stamp timestamptz:=clock_timestamp(); value jsonb;
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
declare value jsonb; project uuid; filters jsonb; own_file text; other_file text;
begin
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
 end loop;
end$$;
rollback;
select 'PASS: four offices, own media in portal and Android, 72 denied cross-office checks, and 8 denied reads after revocation or unavailable authority' result;

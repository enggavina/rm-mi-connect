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
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,foto_url)
 select em_fixture.id(1450+n),em_fixture.id(100+n),em_fixture.id(200+n),em_fixture.id(300+n),
  'https://fixtures.cdn.bubble.io/oficina-'||n||'.png' from generate_series(1,4)n;
update public.rm_projetos set arquivo_nota_fiscal_url='https://fixtures.cdn.bubble.io/oficina-'||n||'.png'
 from generate_series(1,4)n where id=em_fixture.id(100+n);
insert into public.rm_questoes(id,form_id,enunciado,tipo)
 select em_fixture.id(1480+n),em_fixture.id(400+n),'Foto do acervo','foto' from generate_series(1,4)n;
insert into public.rm_respostas(id,registro_formulario_id,questao_id,fotos_urls)
 select em_fixture.id(1460+n),em_fixture.id(500+n),em_fixture.id(1480+n),array['https://fixtures.cdn.bubble.io/oficina-'||n||'.png']
 from generate_series(1,4)n;
do $archive_seed$
declare
 reference text;
 path text;
 bytes bytea;
 sha text;
 saved text;
 recovery jsonb;
 workshop uuid;
 project uuid;
 foreign_workshop uuid;
 foreign_project uuid;
begin
 for office in 1..4 loop
  workshop:=em_fixture.id(office);
  project:=em_fixture.id(100+office);
  foreign_workshop:=em_fixture.id((office%4)+1);
  foreign_project:=em_fixture.id(100+(office%4)+1);
  reference:='https://fixtures.cdn.bubble.io/oficina-'||office||'.png';
  path:='acervo-oficina/'||em_fixture.id(office)||'/'||encode(sha256(convert_to(reference,'UTF8')),'hex')||'.png';
  bytes:=decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+pZJcAAAAASUVORK5CYII=','base64')||set_byte('\x00'::bytea,0,12+office);
  sha:=encode(sha256(bytes),'hex');
  if jsonb_array_length(public.rm_workshop_archive_queue_v1(em_fixture.id(office),'bubble',em_fixture.id(100+office),null,20))<>1 then
   raise exception 'A mesma referência de foto, formulário e nota deve ser copiada uma vez.';
  end if;
  set local role service_role;
  recovery:=public.rm_workshop_archive_recovery_target_v1(workshop,project,encode(sha256(convert_to(reference,'UTF8')),'hex'));
  if recovery->>'reference' is distinct from reference or recovery->'existing' is distinct from 'null'::jsonb
   or public.rm_workshop_archive_recovery_target_v1(foreign_workshop,project,recovery->>'reference_sha256') is not null
   or public.rm_workshop_archive_recovery_target_v1(workshop,foreign_project,recovery->>'reference_sha256') is not null then
   raise exception 'A recuperação ficou sem a origem exata do projeto e da oficina.';
  end if;
  reset role;
  insert into storage.objects(id,bucket_id,name,metadata,user_metadata) values(em_fixture.id(1470+office),'rm-documentos',path,
   jsonb_build_object('size',octet_length(bytes),'mimetype','image/png'),jsonb_build_object('sha256',sha));
  begin
   perform public.rm_confirm_workshop_archive_v1(em_fixture.id(office),reference,repeat('0',64),'image/png',octet_length(bytes));
   raise exception 'Acervo aceitou conteúdo divergente.';
  exception when sqlstate 'PT409' then null;
  end;
  begin
   perform public.rm_confirm_workshop_archive_v1(em_fixture.id((office%4)+1),reference,sha,'image/png',octet_length(bytes));
   raise exception 'Acervo aceitou confirmar a referência de outra oficina.';
  exception when insufficient_privilege then null;
  end;
  set local role service_role;
  saved:=public.rm_confirm_workshop_archive_v1(workshop,reference,sha,'image/png',octet_length(bytes));
  if saved is distinct from path or public.rm_confirm_workshop_archive_v1(workshop,reference,sha,'image/png',octet_length(bytes)) is distinct from path
   or public.rm_workshop_archive_queue_v1(workshop,'bubble',project,null,20) is distinct from '[]'::jsonb then
   raise exception 'A confirmação repetida não conservou a cópia original.';
  end if;
  recovery:=public.rm_workshop_archive_recovery_target_v1(workshop,project,recovery->>'reference_sha256');
  if recovery->'existing' is distinct from jsonb_build_object('sha256',sha,'size',octet_length(bytes),'mime','image/png','path',path) then
   raise exception 'A consulta de recuperação perdeu o recibo já confirmado.';
  end if;
  reset role;
 end loop;
end
$archive_seed$;
select 'PASS: original PNG recovery is limited to its workshop and project and recognizes the immutable archive receipt' result;
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
insert into rm_private.mobile_workshop_uploads(id,submission_id,workshop_id,project_id,operation,auth_user_id,operator_id,
 intent_sha256,kind,mime_type,byte_size,content_sha256,object_path,stored_at)
 select em_fixture.id(1260+n),em_fixture.id(1250+n),em_fixture.id(n),null,'receiving_draft',em_fixture.id(710+n),em_fixture.id(740+n),
  repeat('9',64),'photo','image/png',octet_length(bytes),
  encode(sha256(bytes),'hex'),'mobile-oficina/'||em_fixture.id(n)||'/'||em_fixture.id(1250+n)||'/'||em_fixture.id(1260+n)||'.png',clock_timestamp()
 from generate_series(1,4)n cross join lateral (
  select decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+pZJcAAAAASUVORK5CYII=','base64')||set_byte('\x00'::bytea,0,n+8) bytes
 ) b;
insert into storage.objects(id,bucket_id,name,metadata,user_metadata)
 select em_fixture.id(1270+n),'rm-documentos',u.object_path,jsonb_build_object('size',u.byte_size,'mimetype',u.mime_type),
  jsonb_build_object('sha256',u.content_sha256) from generate_series(1,4)n join rm_private.mobile_workshop_uploads u on u.id=em_fixture.id(1260+n);
insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,payload,last_save_id)
 select u.submission_id,u.auth_user_id,u.operator_id,jsonb_build_object('id',u.submission_id,'version',2,'cliente','',
  'fotos',jsonb_build_array(jsonb_build_object('uri','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||u.object_path))),
  em_fixture.id(1280+n) from generate_series(1,4)n join rm_private.mobile_workshop_uploads u on u.id=em_fixture.id(1260+n);
insert into rm_private.receiving_draft_workshops(draft_id,workshop_id)
 select submission_id,workshop_id from rm_private.mobile_workshop_uploads where operation='receiving_draft';
insert into public.rm_users(id,nome,perfil) select em_fixture.id(1340+n),'Operador de recuperação '||n,'mobile' from generate_series(1,4)n;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 select extensions.digest(repeat('9'||n::text,32),'sha256'),em_fixture.id(710+n),em_fixture.id(730+n),em_fixture.id(1340+n),
  clock_timestamp()+interval '1 hour' from generate_series(1,4)n;
insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,last_save_id,payload,created_at,updated_at)
 select em_fixture.id(1350+n),em_fixture.id(710+n),em_fixture.id(1340+n),em_fixture.id(1360+n),
  jsonb_build_object('version',2,'id',em_fixture.id(1350+n),'step',0,'cliente','',
   'chegada',to_char(stamp at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'notaFiscal','','arquivoNotaFiscal','','descricaoEquipamento','','placaMotor','','eventualidades','','equipamento','{}'::jsonb,'fotos','[]'::jsonb),
  stamp,stamp from generate_series(1,4)n cross join (select clock_timestamp() stamp)s;
create function em_fixture.read_placeholder(actor_office int, current_office int) returns jsonb language plpgsql as $$
declare
 stamp timestamptz:=clock_timestamp();
 auth_id uuid:=em_fixture.id(710+actor_office);
 session_id uuid:=em_fixture.id(720+actor_office);
 request uuid:=gen_random_uuid();
 token text:=repeat('9'||actor_office::text,32);
 args jsonb:=jsonb_build_object('action','read','draftId',em_fixture.id(1350+actor_office));
 result jsonb;
 central jsonb;
begin
 select jsonb_build_object('version',2,'application','em','channel','mobile','authority',authority,
   'workshop',jsonb_build_object('id',id,'code',code,'name',code,'active',true,'revision',1,'updated_at',stamp),
   'principals',jsonb_build_array(
    jsonb_build_object('kind','device','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1','subject',auth_id,'revision',1),
    jsonb_build_object('kind','operator','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1','subject',em_fixture.id(1340+actor_office),'revision',1)),
   'issued_at',stamp,'expires_at',stamp+interval '1 minute') into strict central
 from rm_private.workshop_references where id=em_fixture.id(current_office);
 perform set_config('request.jwt.claim.sub',auth_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',session_id,'aal','aal1')::text,true);
 perform public.rm_authorize_receiving_draft_workshop_v1(auth_id,session_id,token,central,request,args);
 set local role authenticated;
 result:=public.rm_mobile_receiving_draft_workshop_v1(request,args,token);
 reset role;
 return result;
end $$;
do $seed_recovered_drafts$
begin
 for office in 1..4 loop
  if (em_fixture.read_placeholder(office,office)->>'id')::uuid is distinct from em_fixture.id(1350+office) then
   raise exception 'O rascunho legado vazio não foi recuperado.';
  end if;
 end loop;
end
$seed_recovered_drafts$;
commit;
\endif

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

begin;
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
  update public.rm_users set updated_at=clock_timestamp() where id=external_id;
  if pg_temp.workshop_restore_read(office,'operational_stage_rules',args) is distinct from result then
   raise exception 'Uma alteração da equipe de outra oficina mudou a versão ou as escolhas da regra.';
  end if;
  if pg_temp.workshop_restore_read(office,'operational_reviewers',args)->'forms'->0->'context_version' is distinct from reviewer->'expected_context_version' then
   raise exception 'Uma alteração da equipe de outra oficina mudou a versão dos avaliadores.';
  end if;
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
  protocol:=gen_random_uuid();
  perform pg_temp.workshop_assignment_write(office,protocol,'manage_stage_rules',stage,roster);
  result:=pg_temp.workshop_restore_read(office,'operational_stage_rules',args);
  if not (result->'rules' @> jsonb_build_array(jsonb_build_object('id',rule_id,'aprovadores_ids',jsonb_build_array(operator_id)))) then
   raise exception 'O aprovador da oficina não foi preservado na regra.';
  end if;
  editor:=pg_temp.workshop_restore_read(office,'operational_stage_rules',args||jsonb_build_object('members',roster-1));
  if editor->'eligible_users' is distinct from '[]'::jsonb or editor->>'rules_version' is not distinct from result->>'rules_version'
   or not editor->'rules' @> jsonb_build_array(jsonb_build_object('id',rule_id,
    'approvers',jsonb_build_array(jsonb_build_object('id',operator_id,'eligible',false))))
   or (pg_temp.workshop_assignment_write(office,protocol,'manage_stage_rules',stage,roster-1))->>'idempotent_replay' is distinct from 'true' then
   raise exception 'A saída do aprovador da oficina alterou o histórico ou o reenvio já registrado.';
  end if;
  note:=jsonb_build_object('action','retire','etapa_id',rule_id,'projeto_id',project,'celula_projeto_id',allocation,'confirm_change',true,
   'expected_project_updated_at',result->'project'->'updated_at','expected_allocation_updated_at',result->'allocation'->'updated_at',
   'expected_rules_version',result->'rules_version','expected_etapa_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=rule_id));
  begin
   perform pg_temp.workshop_assignment_write(office,gen_random_uuid(),'manage_stage_rules',note,roster-1);
   raise exception 'Uma edição nova passou com a versão anterior da equipe.';
  exception when sqlstate 'PT409' then null;
  end;
  result:=pg_temp.workshop_restore_read(office,'operational_reviewers',args);
  reviewer:=reviewer||jsonb_build_object(
   'expected_project_updated_at',result->'project'->'updated_at','expected_allocation_updated_at',result->'allocation'->'updated_at',
   'expected_context_version',result->'forms'->0->'context_version');
  protocol:=gen_random_uuid();
  editor:=pg_temp.workshop_assignment_write(office,protocol,'assign_form_reviewer',reviewer,roster);
  result:=pg_temp.workshop_restore_read(office,'operational_reviewers',args||jsonb_build_object('members',roster-1));
  if result->'forms'->0->'assignment'->>'avaliador_user_id' is distinct from operator_id::text
   or result->'forms'->0->'assignment'->>'eligible' is distinct from 'false'
   or result->'forms'->0->'context_version' is not distinct from editor->'record'->'context_version'
   or pg_temp.workshop_assignment_write(office,protocol,'assign_form_reviewer',reviewer,roster-1)->>'idempotent_replay' is distinct from 'true' then
   raise exception 'A saída do avaliador da oficina alterou o histórico, a elegibilidade ou o reenvio registrado.';
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

do $draft_media$
declare reference text; data jsonb; denied integer:=0;
begin
 for office in 1..4 loop
  select 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||object_path into strict reference
  from rm_private.mobile_workshop_uploads where id=em_fixture.id(1260+office) and project_id is null and stored_at is not null;
  data:=pg_temp.workshop_restore_native(office,array[reference]);
  if data->'files' is distinct from jsonb_build_array(jsonb_build_object('url',reference,'source','project_photo'))
   or rm_private.workshop_stored_media_owned_v1(reference,em_fixture.id(office),'project_photo') then
   raise exception 'A mídia do rascunho perdeu o vínculo ou foi publicada antes da abertura.';
  end if;
  for outsider in 1..4 loop
   if outsider=office then continue;end if;
   if pg_temp.workshop_restore_native(outsider,array[reference])->'files' is distinct from '[]'::jsonb then
    raise exception 'A mídia do rascunho apareceu em outra oficina.';
   end if;
   denied:=denied+1;
  end loop;
 end loop;
 if denied<>12 then raise exception 'Cobertura incompleta de mídias em rascunho.';end if;
end
$draft_media$;

do $archive_restore$
declare reference text; foreign_reference text; path text; snapshot jsonb;
begin
 for office in 1..4 loop
  reference:='https://fixtures.cdn.bubble.io/oficina-'||office||'.png';
  foreign_reference:='https://fixtures.cdn.bubble.io/oficina-'||((office%4)+1)||'.png';
  path:='acervo-oficina/'||em_fixture.id(office)||'/'||encode(sha256(convert_to(reference,'UTF8')),'hex')||'.png';
  snapshot:=pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(1450+office),'source','project_photo'));
  if snapshot is distinct from jsonb_build_object('id',em_fixture.id(1450+office),'file',reference,'archive_path',path)
   or pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(1460+office),'source','answer_photo','index',0))->>'archive_path' is distinct from path
   or pg_temp.workshop_restore_read(office,'document_link',jsonb_build_object('id',em_fixture.id(100+office),'source','invoice'))->>'archive_path' is distinct from path
   or pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(1450+(office%4)+1),'source','project_photo')) is not null
   or rm_private.workshop_archive_link_v1(reference,em_fixture.id((office%4)+1)) is distinct from '{}'::jsonb then
   raise exception 'A cópia restaurada precisa manter o mesmo arquivo e a oficina no portal.';
  end if;
  snapshot:=pg_temp.workshop_restore_native(office,array[reference,foreign_reference]);
  if jsonb_array_length(snapshot->'files') is distinct from 3 or exists(select 1 from jsonb_array_elements(snapshot->'files') f
   where f->>'url' is distinct from reference or f->>'archive_path' is distinct from path) then
   raise exception 'O Android precisa usar a chave antiga e liberar somente a cópia da própria oficina.';
  end if;
  set local role authenticated;
  if exists(select 1 from storage.objects o where o.bucket_id='rm-documentos' and o.name=path)
   or has_function_privilege('public.rm_confirm_workshop_archive_v1(uuid,text,text,text,integer)','execute')
   or has_function_privilege('public.rm_workshop_archive_queue_v1(uuid,text,uuid,text,integer)','execute') then
   raise exception 'Acervo privado acessível por fora da autorização.';
  end if;
  reset role;
 end loop;
end
$archive_restore$;
do $archive_word$
declare
 item uuid:=em_fixture.id(1490);
 office uuid:=em_fixture.id(1);
 reference constant text:='https://fixtures.cdn.bubble.io/oficina-1-word.docx';
 mime constant text:='application/vnd.openxmlformats-officedocument.wordprocessingml.document';
 path text:='acervo-oficina/'||office||'/'||encode(sha256(convert_to(reference,'UTF8')),'hex')||'.docx';
begin
 if not exists(select 1 from storage.buckets where id='rm-documentos' and not public and mime=any(allowed_mime_types)) then
  raise exception 'O armazenamento privado não aceita o tipo Word histórico.';
 end if;
 insert into public.rm_docs(id,projeto_id,nome,arquivo_url) values(item,em_fixture.id(101),'Anexo Word do ensaio',reference);
 insert into storage.objects(bucket_id,name,metadata,user_metadata) values('rm-documentos',path,
  jsonb_build_object('size',123,'mimetype',mime),jsonb_build_object('sha256',repeat('a',64)));
 if public.rm_confirm_workshop_archive_v1(office,reference,repeat('a',64),mime,123) is distinct from path
  or pg_temp.workshop_restore_read(1,'document_link',jsonb_build_object('id',item,'source','docs'))->>'archive_path' is distinct from path
  or pg_temp.workshop_restore_read(2,'document_link',jsonb_build_object('id',item,'source','docs')) is not null then
  raise exception 'O anexo Word não manteve o caminho privado ou permitiu consulta entre oficinas.';
 end if;
end
$archive_word$;
do $gantt_cutover$
declare
 pending_project uuid:=em_fixture.id(1290); pending_cell uuid:=em_fixture.id(1291);
 reset_project uuid:=em_fixture.id(1292); project uuid; first_cell uuid; second_cell uuid; plan jsonb; settings jsonb;
 first_row uuid; second_row uuid; snapshot jsonb; part jsonb; source jsonb; request_id uuid;
 customer uuid; receiving_id uuid; delegation text; args jsonb; receipt jsonb; anchor jsonb;
 output_acl constant text[]:=array['public.rm_web_planning_export_snapshot_v1(uuid[],text[])','public.rm_web_workshop_snapshot_v1()',
  'rm_private.web_export_shared_equipment_v1(uuid[])','rm_private.web_planning_export_allowed_v1()'];
 view_filters constant jsonb:='{"project_id":null,"cell_id":null,"include_closed":false,"project_details":true,"can_manage":true}';
begin
 begin
  perform rm_private.activate_workshop_output_cutover_v1();
  raise exception 'O corte das saídas iniciou antes da proteção do planejamento.';
 exception when sqlstate 'PT409' then null;
 end;
 update rm_private.sso_settings set require_sso=true where singleton;
 perform rm_private.activate_root_creation_v1(repeat('9',40),em_fixture.id(1299));
 insert into public.rm_projetos(id,nome) values(pending_project,'Recebimento legado local');
 insert into public.rm_celulas(id,nome) values(pending_cell,'Célula pendente local');
 begin
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id) values(em_fixture.id(1293),pending_project,em_fixture.id(201));
  perform rm_private.activate_gantt_workshop_cutover_v1();
  raise exception 'A ativação aceitou uma alocação com origem pendente.';
 exception when sqlstate 'PT409' then null;
 end;
 perform rm_private.activate_gantt_workshop_cutover_v1();
 perform rm_private.activate_gantt_workshop_cutover_v1();
 if exists(select 1 from unnest(output_acl) f where not has_function_privilege('authenticated',f,'execute')) then
  raise exception 'As saídas antigas foram retiradas antes da virada.';
 end if;
 perform rm_private.activate_workshop_output_cutover_v1();
 perform rm_private.activate_workshop_output_cutover_v1();
 if exists(select 1 from unnest(output_acl) f where has_function_privilege('authenticated',f,'execute'))
  or has_function_privilege('authenticated','rm_private.activate_workshop_output_cutover_v1()','execute')
  or has_function_privilege('service_role','rm_private.activate_workshop_output_cutover_v1()','execute') then
  raise exception 'As saídas antigas mantiveram acesso autenticado.';
 end if;
 if exists(select 1 from rm_private.workshop_root_enforcement where activated_at is not null)
  or exists(select 1 from unnest(array[
   'public.rm_web_gantt_snapshot_v1(jsonb)','rm_private.web_gantt_snapshot_before_calendar_v1(jsonb)',
   'rm_private.web_gantt_project_version_v1(uuid)','rm_private.web_gantt_project_version_before_calendar_v1(uuid)'
  ]) f where has_function_privilege('authenticated',f,'execute'))
  or exists(select 1 from unnest(array['rm_private.gantt_project_plans','rm_private.gantt_baselines','rm_private.gantt_project_settings']) t
   where has_table_privilege('authenticated',t,'select')) then
  raise exception 'A ativação não revogou as leituras antigas ou alterou os recebimentos legados.';
 end if;
 insert into public.rm_projetos(id,nome) values(reset_project,'Entrada legada durante transição');
 begin
  insert into public.rm_celulas_projeto(projeto_id,celula_id) values(reset_project,em_fixture.id(201));
  set constraints public.workshop_planning_project_origin immediate;
  raise exception 'Um novo projeto sem origem entrou no Gantt.';
 exception when foreign_key_violation then null;
 end;
 begin
  insert into public.rm_celulas_projeto(projeto_id,celula_id) values(em_fixture.id(101),pending_cell);
  set constraints public.workshop_planning_cell_origin immediate;
  raise exception 'Uma célula sem origem entrou no Gantt.';
 exception when foreign_key_violation then null;
 end;
 begin
  delete from rm_private.workshop_project_ownership where id=em_fixture.id(101);
  set constraints public.workshop_planning_project_origin immediate;
  raise exception 'Uma alocação ativa perdeu a origem de seu projeto.';
 exception when foreign_key_violation then null;
 end;
 -- A project and route may be inserted before the owner row, provided the
 -- classified root exists when the normal operation finishes.
 insert into public.rm_celulas_projeto(projeto_id,celula_id) values(reset_project,em_fixture.id(201));
 insert into rm_private.workshop_project_ownership(id,workshop_id) values(reset_project,em_fixture.id(1));
 set constraints public.workshop_planning_project_origin,public.workshop_planning_cell_origin immediate;
 set constraints public.workshop_planning_project_origin,public.workshop_planning_cell_origin deferred;

 for office in 1..4 loop
  first_cell:=em_fixture.id(200+office); second_cell:=em_fixture.id(1200+office);
  project:=em_fixture.id(100+office);
  update public.rm_projetos set arquivo_nota_fiscal_url='https://docs.fixture.invalid/nota-'||office||'.pdf' where id=project;
  part:=pg_temp.workshop_restore_read(office,'planning_export',jsonb_build_object('cell_ids',jsonb_build_array(first_cell),
   'fields',jsonb_build_array('project_number','cell_name')));
  if not (part->'cells'->0->'rows' @> jsonb_build_array(jsonb_build_object('project_id',project)))
   or (pg_temp.workshop_restore_read(office,'workshop_twin','{}')->'projects'->0->>'id')::uuid is distinct from project
   or (pg_temp.workshop_restore_read(office,'project_qr',jsonb_build_object('id',project))->>'id')::uuid is distinct from project
   or pg_temp.workshop_restore_read(office,'document_link',jsonb_build_object('id',project,'source','invoice'))->>'file'
    is distinct from ('https://docs.fixture.invalid/nota-'||office||'.pdf')
   or pg_temp.workshop_restore_read((office%4)+1,'document_link',jsonb_build_object('id',project,'source','invoice')) is not null then
   raise exception 'A retirada dos leitores antigos alterou a autorização de uma saída por oficina.';
  end if;
  customer:=em_fixture.id(1300+office); receiving_id:=em_fixture.id(1250+office);
  delegation:=repeat(chr(96+office),64);
  insert into public.rm_clientes(id,nome) values(customer,'Cliente local do recebimento de teste '||office);
  insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',customer,em_fixture.id(office));
  select payload||jsonb_build_object('cliente',customer) into source from rm_private.receiving_drafts where id=receiving_id;
  args:=jsonb_build_object('p_operador_id',em_fixture.id(740+office),'p_cliente_id',customer,'p_tipo_equipamento_id',em_fixture.id(1100+office),
   'p_chegada_equipamento','2026-12-01T12:00:00-03:00','p_descricao_equipamento','Motor local do Gantt '||office,
   'p_equipamento','{}'::jsonb,'p_receiving_draft_id',receiving_id,'p_receiving_draft_revision',1,'p_receiving_draft_snapshot',source);
  perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(720+office),'aal','aal1')::text,true);
  perform public.rm_authorize_mobile_receiving_workshop_v1(em_fixture.id(710+office),em_fixture.id(720+office),delegation,
   pg_temp.workshop_restore_native_context(office,office),receiving_id,'open',args);
  set local role authenticated;
  receipt:=public.rm_mobile_receiving_workshop_v1(receiving_id,'open',args,delegation);
  reset role;
  if receipt->'confirmacao' is distinct from jsonb_build_object('protocolo',receiving_id,'oficina_id',em_fixture.id(office),
   'fase','open','projeto_id',receipt->'projeto_id','equipamento_id',receipt->'equipamento_id') then
   raise exception 'A abertura não confirmou o protocolo persistido da oficina.';
  end if;
  project:=(receipt->>'projeto_id')::uuid;
  if not exists(select 1 from rm_private.receiving_workshop_protocols where submission_id=receiving_id
   and project_id=project and workshop_id=em_fixture.id(office) and opened_at is not null and completed_at is null)
   or not exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1() proof where proof.submission_id=receiving_id
    and proof.workshop_id=em_fixture.id(office) and proof.creation_phase='open' and not proof.completed) then
   raise exception 'A abertura não gravou o protocolo com a origem do projeto.';
  end if;
  if not (receipt->>'attachments_pending')::boolean or not (
   pg_temp.workshop_restore_read(office,'receiving_list',jsonb_build_object('reason','without_number','q','Motor local do Gantt '||office,'page',1))->'items'
    @> jsonb_build_array(jsonb_build_object('id',project))) then
   raise exception 'O recebimento aberto não apareceu na sua oficina.';
  end if;
  args:=jsonb_build_object('projeto_id',project,'celula_id',first_cell,'expected_updated_at',
   (select updated_at from public.rm_celulas_projeto where projeto_id=project and celula_id=first_cell),
   'changes',jsonb_build_object('data_inicio','2026-12-07T12:00:00-03:00','data_limite','2026-12-07T12:00:00-03:00'));
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'plan_cell',args,false);
   raise exception 'Uma alocação continuou aceitando o protocolo antigo.';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'plan_cell',args);
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'plan_cell',
   args||jsonb_build_object('celula_id',second_cell,'expected_updated_at',null,
    'changes',jsonb_build_object('data_inicio','2026-12-09T12:00:00-03:00','data_limite','2026-12-10T12:00:00-03:00')));
  set constraints public.workshop_planning_project_origin,public.workshop_planning_cell_origin immediate;
  set constraints public.workshop_planning_project_origin,public.workshop_planning_cell_origin deferred;
  select id into strict first_row from public.rm_celulas_projeto where projeto_id=project and celula_id=first_cell;
  select id into strict second_row from public.rm_celulas_projeto where projeto_id=project and celula_id=second_cell;
  snapshot:=pg_temp.workshop_restore_read(office,'gantt_snapshot',view_filters||jsonb_build_object('project_id',project,'include_closed',true));
  anchor:=snapshot->'projects'->0;
  plan:=jsonb_build_object('reason','Ajuste local no cronograma','projects',jsonb_build_array(jsonb_build_object('id',project,
   'expected_updated_at',anchor->'updated_at','expected_plan_version',anchor->'plan_version')),
   'items',(select jsonb_build_array(jsonb_build_object('id',id,'expected_updated_at',updated_at,'changes',jsonb_build_object('data_limite','2026-12-08')))
    from public.rm_celulas_projeto where id=first_row),'dependencies',jsonb_build_object('projeto_id',project,
    'links',jsonb_build_array(jsonb_build_object('predecessor_id',first_row,'successor_id',second_row,'lag_days',0))));
  if not (snapshot->'items' @> jsonb_build_array(jsonb_build_object('id',first_row,'can_edit',true)))
   or not (pg_temp.workshop_restore_read(office,'gantt_snapshot',view_filters||jsonb_build_object('cell_id',first_cell))->'items'
    @> jsonb_build_array(jsonb_build_object('id',first_row)))
   or not (pg_temp.workshop_restore_read(office,'gantt_snapshot',view_filters)->'items' @> jsonb_build_array(jsonb_build_object('id',first_row)))
   or pg_temp.workshop_restore_read((office % 4)+1,'gantt_snapshot',view_filters||jsonb_build_object('project_id',project,'include_closed',true)) is not null then
   raise exception 'As três visões divergiram da oficina do recebimento.';
  end if;
  begin
   perform pg_temp.workshop_restore_planning_write((office % 4)+1,gen_random_uuid(),'save_gantt_plan',plan);
   raise exception 'Uma oficina alterou o Gantt da outra.';
  exception when insufficient_privilege then null;
  end;
  request_id:=gen_random_uuid();
  perform pg_temp.workshop_restore_planning_write(office,request_id,'save_gantt_plan',plan);
  if (pg_temp.workshop_restore_planning_write(office,request_id,'save_gantt_plan',plan)->>'idempotent_replay')::boolean is distinct from true then
   raise exception 'O reenvio do Gantt não reconheceu o protocolo.';
  end if;
  settings:=jsonb_build_object('projeto_id',project,'expected_updated_at',(select updated_at from public.rm_projetos where id=project),
   'expected_plan_version',rm_private.web_gantt_project_version_v1(project),'reason','Calendário local da oficina',
   'calendar',jsonb_build_object('weekdays',jsonb_build_array(1,2,3,4,5),'exceptions','[]'::jsonb),'milestones','[]'::jsonb);
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_gantt_settings',settings);
  plan:=jsonb_build_object('reason','Referência local do plano','projects',jsonb_build_array(jsonb_build_object('id',project,
   'expected_updated_at',(select updated_at from public.rm_projetos where id=project),'expected_plan_version',rm_private.web_gantt_project_version_v1(project))),
   'items','[]'::jsonb,'baseline',jsonb_build_object('projeto_id',project,'label','Plano local da oficina'));
  perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'save_gantt_plan',plan);
  part:=pg_temp.workshop_restore_read(office,'gantt_snapshot',view_filters||jsonb_build_object('project_id',project,'include_closed',true));
  if part->'baseline'->>'label' is distinct from 'Plano local da oficina' or jsonb_array_length(part->'baseline'->'items')<>2
   or jsonb_array_length(part->'links')<>1 or jsonb_array_length(part->'settings')<>1
   or (select (data_limite at time zone 'America/Sao_Paulo')::date from public.rm_celulas_projeto where id=first_row) is distinct from '2026-12-08'::date then
   raise exception 'Prazo, dependência, calendário ou referência não foram salvos.';
  end if;
 end loop;
end
$gantt_cutover$;
do $recovered_drafts$
begin
 for office in 1..4 loop
  if not exists(select 1 from rm_private.receiving_draft_recoveries r
   join rm_private.receiving_draft_workshops w using(draft_id)
   join rm_private.receiving_drafts d on d.id=r.draft_id
   where r.draft_id=em_fixture.id(1350+office) and w.workshop_id=em_fixture.id(office)
    and r.original_payload_sha256=encode(sha256(convert_to(d.payload::text,'UTF8')),'hex')
    and r.original_revision=d.revision and r.auth_user_id=d.auth_user_id and r.operator_id=d.operator_id)
   or (em_fixture.read_placeholder(office,office)->>'id')::uuid is distinct from em_fixture.id(1350+office) then
   raise exception 'A restauração divergiu na origem, nos dados ou no autor do rascunho.';
  end if;
  begin
   perform em_fixture.read_placeholder(office,(office%4)+1);
   raise exception 'O rascunho recuperado foi aberto após trocar a oficina.';
  exception when insufficient_privilege then null;
  end;
 end loop;
end
$recovered_drafts$;
do $legacy_project_origins$
declare
 operator uuid; protocol uuid; client uuid; token text; context jsonb;
 args jsonb; raw jsonb; replay jsonb; project uuid;
begin
 for office in 1..4 loop
  operator:=em_fixture.id(1500+office);
  protocol:=em_fixture.id(1510+office);
  client:=em_fixture.id(1520+office);
  token:=repeat('4'||office::text,32);
  insert into public.rm_clientes(id,nome) values(client,'Cliente local anterior à classificação '||office);
  insert into public.rm_users(id,nome,perfil) values(operator,'Operador legado local '||office,'mobile');
  insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
   values(extensions.digest(token,'sha256'),em_fixture.id(710+office),em_fixture.id(730+office),operator,clock_timestamp()+interval '1 hour');
  context:=jsonb_set(pg_temp.workshop_restore_native_context(office,office),'{principals,1,subject}',to_jsonb(operator));
  perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(720+office),'aal','aal1')::text,true);
  args:=jsonb_build_object('p_operador_id',operator,'p_cliente_id',client,
   'p_chegada_equipamento','2026-11-24T12:00:00Z','p_descricao_equipamento','Chegada legada local '||office,
   'p_equipamento','{}'::jsonb,'p_fotos_recebimento','[]'::jsonb);
  set local role authenticated;
  raw:=public.rm_mobile_mutate_v1(protocol,'rm_submit_recebimento_v1',args,token);
  reset role;
  project:=(raw->>'projeto_id')::uuid;
  if exists(select 1 from rm_private.workshop_project_ownership where id=project) then
   raise exception 'O recebimento legado de teste nasceu com uma oficina indevida.';
  end if;
  insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',client,em_fixture.id(office));
  perform public.rm_authorize_mobile_receiving_workshop_v1(em_fixture.id(710+office),em_fixture.id(720+office),token,context,protocol,'complete',args);
  set local role authenticated;
  replay:=public.rm_mobile_receiving_workshop_v1(protocol,'complete',args,token);
  reset role;
  if replay->'confirmacao' is distinct from jsonb_build_object('protocolo',protocol,'oficina_id',em_fixture.id(office),
   'fase','complete','projeto_id',replay->'projeto_id','equipamento_id',replay->'equipamento_id') then
   raise exception 'O reenvio offline não confirmou a fase ou a oficina de origem.';
  end if;
  if (replay->>'projeto_id')::uuid is distinct from project or (replay->>'idempotent_replay')::boolean is distinct from true
   or not exists(select 1 from rm_private.receiving_project_recoveries where submission_id=protocol
    and project_id=project and operator_id=operator and workshop_id=em_fixture.id(office))
   or not exists(select 1 from rm_private.receiving_workshop_protocols where submission_id=protocol
    and project_id=project and operator_id=operator and workshop_id=em_fixture.id(office) and opened_at is null and completed_at is not null
    and creation_phase is null)
   or (rm_private.workshop_receiving_read_v1(jsonb_build_object('page',1,'q','Chegada legada local '||office,'reason','without_number'),
    em_fixture.id(office))->>'total')::int is distinct from 1
   or (rm_private.workshop_receiving_read_v1(jsonb_build_object('page',1,'q','Chegada legada local '||office,'reason','without_number'),
    em_fixture.id((office%4)+1))->>'total')::int is distinct from 0 then
   raise exception 'O reenvio legado divergiu da autoria, do projeto ou da oficina.';
  end if;
 end loop;
 if rm_private.workshop_receiving_pilot_ready_v1() then
  raise exception 'Rascunhos abertos e reenvios antigos não comprovam a conclusão do piloto.';
 end if;
end
$legacy_project_origins$;
create function pg_temp.workshop_restore_decide(office integer,submission uuid,operation text,payload jsonb,scoped boolean default true)
returns jsonb language plpgsql as $$
declare context jsonb:=pg_temp.workshop_restore_sso(office); value jsonb;
 hash text:=repeat(office::text,64);
begin
 if scoped then perform public.rm_sso_form_review_workshop_permit_v1(hash,submission,operation,payload,context);
 else perform public.rm_sso_action_permit_v1(hash,submission,operation,payload,
  case when operation='review_form' then 'em.forms.review' else 'em.approvals.decide' end);end if;
 set local role authenticated;
 value:=public.rm_web_mutate_v1(submission,operation,payload);
 reset role;
 return value;
exception when others then reset role;raise;
end$$;

do $review_cutover$
declare
 project uuid; cell uuid; allocation uuid; destination uuid; stage uuid; registration uuid;
 changes jsonb; params jsonb; output jsonb; submission uuid; operation text;
begin
 if (select activated_at is not null from rm_private.workshop_root_enforcement where singleton) then
  raise exception 'A revisão precisa ser ativável com entradas não alocadas ainda disponíveis.';
 end if;
 begin
  insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id)
   values(em_fixture.id(1510),em_fixture.id(101),em_fixture.id(202),em_fixture.id(401));
  perform rm_private.activate_workshop_review_cutover_v1();
  raise exception 'A ativação aceitou um formulário com origem cruzada.';
 exception when sqlstate 'PT409' then null;
 end;
 perform rm_private.activate_workshop_review_cutover_v1();
 if not exists(select 1 from rm_private.form_review_workshop_settings where singleton and enforced)
  or has_function_privilege('authenticated','public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer)','execute')
  or has_function_privilege('authenticated','public.rm_web_stage_approval_snapshot_v1(uuid)','execute')
  or has_table_privilege('authenticated','rm_private.web_stage_approval_context_v1','select') then
  raise exception 'A revisão ainda permite consulta ou decisão fora do contexto de oficina.';
 end if;
 set constraints public.workshop_review_stage_origin,public.workshop_review_form_origin immediate;
 -- A template can still be registered independently of a project.
 insert into public.rm_aprovacoes_etapas(id,celula_origem_id,ativo) values(em_fixture.id(1511),em_fixture.id(201),true);
 for office in 1..4 loop
  project:=em_fixture.id(100+office); cell:=em_fixture.id(200+office); allocation:=em_fixture.id(300+office);
  registration:=em_fixture.id(500+office); stage:=em_fixture.id(1530+office); destination:=em_fixture.id(1550+office);
  insert into public.rm_celulas(id,nome) values(destination,'Destino local da revisão '||office);
  insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(destination,em_fixture.id(office));
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
   values(em_fixture.id(1570+office),project,destination,'pendente',false);
  update public.rm_celulas_projeto set status='em_dia' where id=allocation;
  -- Keep the legacy missing allocation ID. The operational resolver still uses the project/cell pair.
  insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj)
   values(stage,project,cell,destination,'em_dia');
  update public.rm_registros_formulario set status='em_an_lise',preenchido=true where id=registration;
  begin
   insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,ativo)
    values(em_fixture.id(1590+office),project,cell,em_fixture.id(200+(office%4)+1),true);
   raise exception 'Uma etapa nova foi vinculada à célula de outra oficina.';
  exception when sqlstate 'PT409' then null;
  end;
  begin
   insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id)
    values(em_fixture.id(1600+office),project,cell,em_fixture.id(400+(office%4)+1));
   raise exception 'Uma revisão aceitou um modelo de outra oficina.';
  exception when sqlstate 'PT409' then null;
  end;
  output:=pg_temp.workshop_restore_read(office,'approval_entry',jsonb_build_object('id',stage));
  if output->'available_actions' is distinct from '["liberar"]'::jsonb or output->'stage'->'celula_projeto_id' is distinct from 'null'::jsonb then
   raise exception 'A consulta da etapa legada perdeu a ação operacional.';
  end if;
  select jsonb_build_object('review_form',jsonb_build_object('registro_formulario_id',r.id,'expected_updated_at',r.updated_at,
   'decision','return','parecer','Correção no ensaio isolado','resposta_ids',jsonb_build_array(em_fixture.id(1460+office))),
   'transition_stage_approval',jsonb_build_object('aprovacao_etapa_id',s.id,'expected_updated_at',s.updated_at,
   'expected_cell_updated_at',a.updated_at,'acao','liberar','observacao','Decisão no ensaio isolado')) into changes
   from public.rm_registros_formulario r,public.rm_aprovacoes_etapas s,public.rm_celulas_projeto a
   where r.id=registration and s.id=stage and a.id=allocation;
  foreach operation in array array['review_form','transition_stage_approval'] loop
   params:=changes->operation;
   submission:=gen_random_uuid();
   begin
    perform pg_temp.workshop_restore_decide(office,submission,operation,params,false);
    raise exception 'Uma autorização antiga permitiu decidir sem confirmar a oficina.';
   exception when insufficient_privilege then null;
   end;
   for foreign_office in 1..4 loop
    if office=foreign_office then continue;end if;
    begin
     perform pg_temp.workshop_restore_decide(foreign_office,submission,operation,params);
     raise exception 'A sessão de outra oficina conseguiu registrar uma decisão.';
    exception when insufficient_privilege then null;
    end;
   end loop;
   output:=pg_temp.workshop_restore_decide(office,submission,operation,params);
   if (case operation when 'review_form' then output->'record'->>'status' else output->'snapshot'->'stage'->>'status' end)
       is distinct from (case operation when 'review_form' then 'direcionado' else 'aprovado' end)
    or pg_temp.workshop_restore_decide(office,submission,operation,params)->>'idempotent_replay' is distinct from 'true' then
    raise exception 'A decisão autorizada ou sua retentativa não preservou o protocolo.';
   end if;
  end loop;
  if (select count(*) from public.rm_aprovacoes_registro a where a.registro_formulario_id=registration)<>1
   or (select count(*) from public.rm_web_stage_decisions d where d.aprovacao_etapa_id=stage)<>1 then
   raise exception 'A retentativa duplicou o histórico de decisão.';
  end if;
 end loop;
end
$review_cutover$;
do $receiving_read_cutover$
declare
 legacy_receiving constant text:='public.rm_web_receivings_v1(text,text,integer,integer)';
 filters constant jsonb:='{"reason":"without_number","q":"","page":1}';
 selection constant jsonb:='{"q":"","status":null,"client":null,"cell":null,"page":1,"planning":true}';
 overview constant jsonb:='{"projects":true,"forms":true,"planning":true,"documents":true}';
 project uuid; choices jsonb; entries jsonb; dashboard jsonb; twin jsonb;
begin
 if not has_function_privilege('authenticated',legacy_receiving,'execute') then
  raise exception 'A consulta antiga foi retirada antes da mudança do portal.';
 end if;
 begin
  perform rm_private.activate_workshop_receiving_read_cutover_v1();
  raise exception 'A ativação aceitou origens pendentes no acervo.';
 exception when sqlstate 'PT409' then null;
 end;
 insert into rm_private.workshop_project_ownership(id,workshop_id) values(em_fixture.id(1290),em_fixture.id(1));
 insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(em_fixture.id(1291),em_fixture.id(1));
 perform rm_private.activate_workshop_receiving_read_cutover_v1();
 perform rm_private.activate_workshop_receiving_read_cutover_v1();
 if has_function_privilege('authenticated',legacy_receiving,'execute')
  or has_function_privilege('anon',legacy_receiving,'execute')
  or has_function_privilege('service_role','rm_private.activate_workshop_receiving_read_cutover_v1()','execute')
  or (select activated_at is not null from rm_private.workshop_root_enforcement where singleton) then
  raise exception 'O corte não isolou a consulta ou alterou as entradas legadas.';
 end if;
 for office in 1..4 loop
  select project_id into strict project from rm_private.receiving_openings where client_submission_id=em_fixture.id(1250+office);
  choices:=pg_temp.workshop_restore_read(office,'project_list',selection);
  entries:=pg_temp.workshop_restore_read(office,'receiving_list',filters);
  dashboard:=pg_temp.workshop_restore_read(office,'overview',overview);
  twin:=pg_temp.workshop_restore_read(office,'workshop_twin','{}');
  if not choices->'rows' @> jsonb_build_array(jsonb_build_object('id',project))
   or not entries->'items' @> jsonb_build_array(jsonb_build_object('id',project))
   or (pg_temp.workshop_restore_read(office,'project_entry',
    jsonb_build_object('id',project,'documents',true,'cells',true))->'project'->>'id')::uuid is distinct from project
   or not dashboard->'recentProjects' @> jsonb_build_array(jsonb_build_object('id',project))
   or not twin->'cells' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(200+office))) then
   raise exception 'Uma consulta operacional perdeu os registros autorizados da própria oficina.';
  end if;
  for other in 1..4 loop
   if other=office then continue;end if;
   if pg_temp.workshop_restore_read(other,'project_entry',
    jsonb_build_object('id',project,'documents',true,'cells',true)) is not null
    or pg_temp.workshop_restore_read(other,'receiving_list',jsonb_build_object(
     'reason','without_number','q','Motor local do Gantt '||office,'page',1))->>'total' is distinct from '0'
    or pg_temp.workshop_restore_read(other,'project_list',selection)->'rows' @> jsonb_build_array(jsonb_build_object('id',project))
    or pg_temp.workshop_restore_read(other,'overview',overview)->'recentProjects' @> jsonb_build_array(jsonb_build_object('id',project))
    or pg_temp.workshop_restore_read(other,'workshop_twin','{}')->'cells' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(200+office))) then
    raise exception 'A consulta operacional expôs dados de outra oficina.';
   end if;
  end loop;
 end loop;
end
$receiving_read_cutover$;
create function pg_temp.workshop_restore_root_write(office integer,submission uuid,operation text,payload jsonb,scoped boolean default true)
returns jsonb language plpgsql as $$
declare context jsonb:=pg_temp.workshop_restore_sso(office); result jsonb; hash text:=repeat(office::text,64);
begin
 if scoped then perform public.rm_sso_root_creation_permit_v1(hash,submission,operation,payload,context);
 else perform public.rm_sso_action_permit_v1(hash,submission,operation,payload,
  case when operation='save_catalog' then 'em.catalogs.manage' else 'em.projects.manage' end);end if;
 set local role authenticated;
 result:=public.rm_web_mutate_v1(submission,operation,payload);
 reset role;
 return result;
exception when others then reset role;raise;
end
$$;

do $root_edit_cutover$
declare
 project uuid; equipment uuid; cell uuid; submission uuid;
 choices jsonb; forms jsonb; cells jsonb; context jsonb; params jsonb; result jsonb; operation text;
begin
 perform rm_private.activate_root_workshop_edits_v1();
 if (select activated_at is not null from rm_private.workshop_root_enforcement where singleton)
  or not (select edits_enforced from rm_private.root_creation_settings where singleton)
  or has_function_privilege('authenticated','public.rm_web_project_delete_snapshot_v1(uuid)','execute') then
  raise exception 'A ativação das edições mudou o contrato Android ou manteve a consulta antiga de exclusão.';
 end if;
 for office in 1..4 loop
  project:=em_fixture.id(1650+office); equipment:=em_fixture.id(1660+office); cell:=em_fixture.id(200+office);
  insert into public.rm_projetos(id,nome,status_pcp) values(project,'Edição local '||office,'executando');
  insert into rm_private.workshop_project_ownership(id,workshop_id) values(project,em_fixture.id(office));
  insert into public.rm_equipamentos(id,projeto_id,tipo_equipamento_id) values(equipment,project,em_fixture.id(1100+office));
  update public.rm_projetos set equipamento_id=equipment where id=project;
  choices:=pg_temp.workshop_restore_read(office,'root_edit_choices','{"scope":"project"}');
  forms:=pg_temp.workshop_restore_read(office,'root_edit_choices','{"scope":"planning"}');
  cells:=pg_temp.workshop_restore_read(office,'catalog_list','{"kind":"cells","q":"","page":1}');
  if not choices->'clients' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1300+office)))
   or not choices->'types' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1100+office)))
   or not forms->'forms' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(400+office)))
   or not cells->'rows' @> jsonb_build_array(jsonb_build_object('id',cell))
   or (pg_temp.workshop_restore_read(office,'catalog_entry',jsonb_build_object('kind','cells','id',cell))->>'id')::uuid is distinct from cell
   or (pg_temp.workshop_restore_read(office,'project_delete_context',jsonb_build_object('id',project))->'project'->>'id')::uuid is distinct from project then
   raise exception 'Um cadastro, seletor ou contexto autorizado ficou indisponível.';
  end if;
  for other in 1..4 loop
   if other=office then continue;end if;
   if choices->'clients' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1300+other)))
    or choices->'types' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1100+other)))
    or forms->'forms' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(400+other)))
    or cells->'rows' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(200+other)))
    or pg_temp.workshop_restore_read(other,'project_delete_context',jsonb_build_object('id',project)) is not null
    or pg_temp.workshop_restore_read(other,'catalog_entry',jsonb_build_object('kind','cells','id',cell)) is not null then
    raise exception 'Uma consulta de edição mostrou dados de outra oficina.';
   end if;
  end loop;
  foreach operation in array array['save_project','save_project_with_equipment','save_project_equipment','save_catalog','delete_project'] loop
   perform pg_temp.workshop_restore_sso(office);
   if operation='save_project' then
    select jsonb_build_object('id',id,'expected_updated_at',updated_at,'changes',jsonb_build_object('nome','Nome confirmado '||office))
     into params from public.rm_projetos where id=project;
   elsif operation='save_project_with_equipment' then
    context:=public.rm_web_project_equipment_snapshot_v1(project);
    params:=jsonb_build_object('id',project,'expected_updated_at',context->'project'->'updated_at',
     'changes',jsonb_build_object('escopo_abreviado','Escopo confirmado '||office),
     'equipment',jsonb_build_object('id',equipment,'expected_updated_at',context->'equipment'->'updated_at',
      'expected_context_version',context->'context_version','changes',jsonb_build_object('modelo','Modelo confirmado '||office)));
   elsif operation='save_project_equipment' then
    context:=public.rm_web_project_equipment_snapshot_v1(project);
    params:=jsonb_build_object('projeto_id',project,'equipamento_id',equipment,'confirm_change',true,
     'expected_project_updated_at',context->'project'->'updated_at','expected_equipment_updated_at',context->'equipment'->'updated_at',
     'expected_context_version',context->'context_version','changes',jsonb_build_object('fabricante','Fabricante confirmado '||office));
   elsif operation='save_catalog' then
    select jsonb_build_object('kind','cells','id',id,'expected_updated_at',updated_at,'changes',jsonb_build_object('nome','Célula confirmada '||office))
     into params from public.rm_celulas where id=cell;
   else
    context:=pg_temp.workshop_restore_read(office,'project_delete_context',jsonb_build_object('id',project));
    params:=jsonb_build_object('id',project,'expected_updated_at',context->'project'->'updated_at',
     'expected_context_version',context->'context_version','confirm_delete',true,'justificativa','Ensaio isolado da exclusão');
   end if;
   submission:=gen_random_uuid();
   begin
    perform pg_temp.workshop_restore_root_write(office,submission,operation,params,false);
    raise exception 'Uma gravação aceitou o protocolo antigo.';
   exception when insufficient_privilege then null;
   end;
   for other in 1..4 loop
    if other=office then continue;end if;
    begin
     perform pg_temp.workshop_restore_root_write(other,submission,operation,params);
     raise exception 'Uma gravação foi aceita em outra oficina.';
    exception when insufficient_privilege then null;
    end;
   end loop;
   result:=pg_temp.workshop_restore_root_write(office,submission,operation,params);
   if result->>'operation' is distinct from operation or result->>'idempotent_replay' is distinct from 'false'
    or pg_temp.workshop_restore_root_write(office,submission,operation,params)->>'idempotent_replay' is distinct from 'true' then
    raise exception 'A gravação autorizada ou sua retentativa perdeu o resultado.';
   end if;
  end loop;
  if exists(select 1 from public.rm_projetos where id=project)
   or not exists(select 1 from rm_private.workshop_origin_retirements where object_kind='project' and object_id=project)
   or (select nome from public.rm_celulas where id=cell) is distinct from ('Célula confirmada '||office) then
   raise exception 'A edição ou a exclusão perdeu os vínculos de origem.';
  end if;
 end loop;
end
$root_edit_cutover$;
do $dossier$
declare
 project uuid; allocation uuid; attachment uuid; replacement uuid; comment uuid; submission uuid; photo uuid;
 operation text; params jsonb; snapshot jsonb; result jsonb; reads jsonb; one record; slot uuid; file_reference text; object_path text;
 visible boolean;
begin
 perform rm_private.activate_workshop_project_dossier_v1();
 if not (select enforced from rm_private.workshop_dossier_settings where singleton) or exists(
  select 1 from unnest(array['public.rm_web_project_comments_v1(uuid,jsonb)','public.rm_web_project_documents_v1(uuid,jsonb)',
   'public.rm_web_project_equipment_snapshot_v1(uuid)','public.rm_web_project_route_snapshot_v1(uuid)',
   'rm_private.project_comment_revision_context_v1(uuid,uuid,integer)','rm_private.project_attachment_version_context_v1(uuid,uuid,integer)']) f
  where has_function_privilege('authenticated',f,'execute')) then
  raise exception 'O acesso antigo ao dossiê ainda está disponível.';
 end if;
 for office in 1..4 loop
  project:=em_fixture.id(100+office); allocation:=em_fixture.id(300+office); photo:=em_fixture.id(600+office);
  attachment:=gen_random_uuid(); replacement:=gen_random_uuid(); comment:=gen_random_uuid();
  update public.rm_celulas_projeto set visibilidade=true,bloqueada='n_o' where id=allocation;
  foreach operation in array array['add_project_comment','edit_project_comment','manage_project_documents','set_project_photo_selection',
   'reserve_project_attachment','finalize_project_attachment','reserve_project_attachment_version','finalize_project_attachment_version'] loop
   submission:=gen_random_uuid();
   params:=jsonb_build_object('projeto_id',project,'expected_project_updated_at',(select updated_at from public.rm_projetos where id=project));
   case operation
    when 'add_project_comment' then
     submission:=comment;
     params:=params||jsonb_build_object('celula_projeto_id',allocation,'evento','Comentário local '||office,
      'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id=allocation));
    when 'edit_project_comment' then
     snapshot:=pg_temp.workshop_restore_read(office,'project_comment',jsonb_build_object('p_project_id',project,'p_comment_id',comment,'p_history_page',1));
     params:=params||jsonb_build_object('comentario_id',comment,'expected_comment_updated_at',snapshot->'comment'->'updated_at',
      'expected_context_version',snapshot->'context_version','confirm_change',true,'evento','Correção local '||office,'motivo','Ensaio de oficina');
    when 'manage_project_documents' then
     params:=params||jsonb_build_object('action','create_folder','nome','Pasta da oficina '||office,'parent_id',null);
    when 'set_project_photo_selection' then
     params:=(params-'expected_project_updated_at')||jsonb_build_object('foto_id',photo,'selected',true,
      'expected_updated_at',(select updated_at from public.rm_fotos where id=photo));
    else
     slot:=case when operation like '%_version' then replacement else attachment end;
     if operation like 'reserve_%' then
      params:=params||jsonb_build_object('upload_id',slot,'nome','Anexo local '||office,'descricao',null,'filename','arquivo.pdf',
       'mime_type','application/pdf','byte_size',5,'sha256',repeat('a',64),'data_vencimento',null,'status','No prazo');
      if slot=replacement then
       snapshot:=pg_temp.workshop_restore_read(office,'project_attachment',
        jsonb_build_object('p_project_id',project,'p_attachment_id',attachment,'p_history_page',1));
       params:=params||jsonb_build_object('source_attachment_id',attachment,'expected_attachment_updated_at',snapshot->'attachment'->'updated_at',
        'expected_context_version',snapshot->'context_version','motivo','Nova versão no ensaio','confirm_change',true);
      end if;
     else
      submission:=slot;
      params:=(params-'expected_project_updated_at')||jsonb_build_object('upload_id',slot);
      insert into storage.objects(bucket_id,name,metadata,user_metadata)
       values('rm-documentos','web-dossier/'||project||'/'||slot||'.pdf','{"size":5,"mimetype":"application/pdf"}',jsonb_build_object('sha256',repeat('a',64)));
     end if;
   end case;
   begin
    perform pg_temp.workshop_restore_root_write(office,submission,operation,params,false);
    raise exception 'O dossiê aceitou uma gravação sem autorização da oficina.';
   exception when insufficient_privilege then null;
   end;
   for other in 1..4 loop
    if other=office then continue;end if;
    begin
     perform pg_temp.workshop_restore_root_write(other,submission,operation,params);
     raise exception 'O dossiê aceitou uma gravação de outra oficina.';
    exception when insufficient_privilege then null;
    end;
   end loop;
   result:=pg_temp.workshop_restore_root_write(office,submission,operation,params);
   if result->>'operation' is distinct from operation
    or pg_temp.workshop_restore_root_write(office,submission,operation,params)->>'idempotent_replay' is distinct from 'true' then
    raise exception 'O dossiê perdeu resultado, autor ou protocolo.';
   end if;
  end loop;
  reads:=jsonb_build_object('project_comments',jsonb_build_object('p_project_id',project,'p_filters','{}'::jsonb),
   'project_documents',jsonb_build_object('p_project_id',project,'p_filters','{}'::jsonb),
   'project_comment',jsonb_build_object('p_project_id',project,'p_comment_id',comment,'p_history_page',1),
   'project_attachment',jsonb_build_object('p_project_id',project,'p_attachment_id',replacement,'p_history_page',1),
   'project_audit',jsonb_build_object('p_project_id',project,'p_kind','operations','p_page',1,'p_topics','["photos"]'::jsonb),
   'project_equipment',jsonb_build_object('p_project_id',project),'project_route',jsonb_build_object('p_project_id',project));
  for one in select key,value from jsonb_each(reads) loop
   if pg_temp.workshop_restore_read(office,one.key,one.value) is null then raise exception 'O dossiê perdeu a consulta própria %',one.key;end if;
   for other in 1..4 loop
    if other<>office and pg_temp.workshop_restore_read(other,one.key,one.value) is not null then
     raise exception 'O dossiê apresentou consulta de outra oficina %',one.key;end if;
   end loop;
  end loop;
  if pg_temp.workshop_restore_read(office,'project_attachment',reads->'project_attachment')->'series'->>'head_revision' is distinct from '2'
   or pg_temp.workshop_restore_read(office,'project_comment',reads->'project_comment')->'history'->>'total' is distinct from '1'
   or not (pg_temp.workshop_restore_read(office,'project_audit',reads->'project_audit')->'items'
    @> jsonb_build_array(jsonb_build_object('entity_id',photo,'topic','photos'))) then
   raise exception 'O histórico perdeu a versão, a correção ou a trilha da foto.';
  end if;
  select arquivo_url into strict file_reference from public.rm_docs where id=replacement;
  object_path:='web-dossier/'||project||'/'||replacement||'.pdf';
  slot:=gen_random_uuid();
  insert into public.rm_docs(id,projeto_id,nome,arquivo_url) values(slot,em_fixture.id(100+(office%4)+1),'Referência cruzada local',file_reference);
  if pg_temp.workshop_restore_read(office,'document_link',jsonb_build_object('id',replacement,'source','docs'))->>'web_dossier_path' is distinct from object_path
   or pg_temp.workshop_restore_read((office%4)+1,'document_link',jsonb_build_object('id',slot,'source','docs')) is not null
   or not (pg_temp.workshop_restore_native(office,array[file_reference])->'files' @> jsonb_build_array(jsonb_build_object('url',file_reference)))
   or pg_temp.workshop_restore_native((office%4)+1,array[file_reference])->'files' <> '[]'::jsonb then
   raise exception 'O vínculo privado do anexo se perdeu ou permitiu um atalho entre oficinas.';
  end if;
  perform pg_temp.workshop_restore_sso(office);
  set local role authenticated;
  select exists(select 1 from storage.objects where bucket_id='rm-documentos' and name=object_path) into visible;
  reset role;
  if visible then raise exception 'O anexo voltou a aceitar leitura direta sem oficina.';end if;
 end loop;
end
$dossier$;
do $route_cell$
declare
 project uuid; allocation uuid; model uuid; submission uuid;
 args jsonb; snapshot jsonb; result jsonb; payload jsonb;
begin
 perform rm_private.activate_project_route_cell_workshop_v1();
 if has_function_privilege('authenticated','public.rm_web_project_route_cell_snapshot_v1(uuid,uuid,boolean)','execute') then
  raise exception 'A configuração antiga da célula continuou exposta.';
 end if;
 for office in 1..4 loop
  project:=em_fixture.id(1850+office);allocation:=em_fixture.id(1860+office);model:=em_fixture.id(400+office);
  insert into public.rm_projetos(id,nome,status_pcp) values(project,'Configuração local '||office,'executando');
  insert into rm_private.workshop_project_ownership(id,workshop_id) values(project,em_fixture.id(office));
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
   values(allocation,project,em_fixture.id(200+office),'pendente',true);
  args:=jsonb_build_object('project',project,'allocation',allocation,'include',true);
  snapshot:=pg_temp.workshop_restore_read(office,'project_route_cell',args);
  if snapshot->'allocation'->>'id' is distinct from allocation::text
   or snapshot->'forms'->0->>'id' is distinct from model::text or jsonb_array_length(snapshot->'forms')<>1
   or pg_temp.workshop_restore_read(office,'project_route_cell',jsonb_set(args,'{include}','false'))->'forms' is distinct from '[]'::jsonb then
   raise exception 'A configuração de célula perdeu o seletor próprio.';
  end if;
  for other in 1..4 loop
   if office=other then continue;end if;
   if pg_temp.workshop_restore_read(other,'project_route_cell',args) is not null then
    raise exception 'A configuração de uma célula apareceu em outra oficina.';
   end if;
  end loop;
  -- A mudança em outro catálogo não deve invalidar a configuração desta célula.
  update public.rm_forms set titulo=titulo||' revisado' where id=em_fixture.id(400+(office%4)+1);
  if pg_temp.workshop_restore_read(office,'project_route_cell',args) is distinct from snapshot then
   raise exception 'O catálogo de outra oficina alterou a versão desta célula.';
  end if;
  payload:=jsonb_build_object('projeto_id',project,'celula_projeto_id',allocation,'action','forms','confirm_change',true,
   'expected_project_updated_at',snapshot->'project'->'updated_at','expected_allocation_updated_at',snapshot->'allocation'->'updated_at',
   'expected_context_version',snapshot->>'context_version','forms_ids',jsonb_build_array(model));
  begin
   perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'manage_project_route_cell',
    jsonb_set(payload,'{forms_ids}',jsonb_build_array(em_fixture.id(400+(office%4)+1))));
   raise exception 'A configuração aceitou um formulário de outra oficina.';
  exception when insufficient_privilege then null;
  end;
  submission:=gen_random_uuid();
  result:=pg_temp.workshop_restore_planning_write(office,submission,'manage_project_route_cell',payload);
  snapshot:=pg_temp.workshop_restore_read(office,'project_route_cell',jsonb_set(args,'{include}','false'));
  if snapshot->'forms'->0->>'id' is distinct from model::text
   or snapshot->>'context_version' is distinct from result->'record'->>'context_version'
   or (pg_temp.workshop_restore_planning_write(office,submission,'manage_project_route_cell',payload))->>'idempotent_replay' is distinct from 'true' then
   raise exception 'O seletor, a gravação e sua retentativa divergiram.';
  end if;
 end loop;
end
$route_cell$;
do $photo_configuration$
declare
 project uuid; allocation uuid; cell uuid; title uuid; second_title uuid; original_photo uuid;
 replacement uuid; evidence uuid; submission uuid; args jsonb; snapshot jsonb; result jsonb; payload jsonb; item jsonb; action text;
begin
 perform rm_private.activate_operational_photo_workshop_v1();
 if has_function_privilege('authenticated','public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean)','execute') then
  raise exception 'A consulta antiga das fotos previstas continuou exposta.';
 end if;
 for office in 1..4 loop
  cell:=em_fixture.id(200+office); title:=em_fixture.id(1900+office); second_title:=em_fixture.id(1910+office);
  insert into public.rm_cadastro_fotos(id,titulo,celula_nome) values(title,'Título de preparação','Nome legado'),(second_title,'Título substituto','Nome legado');
  insert into rm_private.engineering_photo_title_scope(title_id,workshop_id,cell_id) values
   (title,em_fixture.id(office),cell),(second_title,em_fixture.id(office),cell);
 end loop;
 for office in 1..4 loop
  project:=em_fixture.id(1920+office);allocation:=em_fixture.id(1930+office);cell:=em_fixture.id(200+office);
  title:=em_fixture.id(1900+office);second_title:=em_fixture.id(1910+office); evidence:=em_fixture.id(1940+office);
  original_photo:=em_fixture.id(1950+office);replacement:=em_fixture.id(1960+office);
  insert into public.rm_projetos(id,nome,status_pcp) values(project,'Fotos previstas locais '||office,'executando');
  insert into rm_private.workshop_project_ownership(id,workshop_id) values(project,em_fixture.id(office));
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade) values(allocation,project,cell,'pendente',true);
  insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,foto_url)
   values(evidence,project,cell,allocation,'obrigat_ria','Evidência preservada','https://fixture.invalid/received.png');
  args:=jsonb_build_object('project',project,'allocation',allocation,'include',true);
  snapshot:=pg_temp.workshop_restore_read(office,'operational_photos',args);
  if not snapshot->'titles' @> jsonb_build_array(jsonb_build_object('id',title))
   or not snapshot->'photos' @> jsonb_build_array(jsonb_build_object('id',evidence,'captured',true,'can_replace',false,'can_retire',false))
   or pg_temp.workshop_restore_read(office,'operational_photos',jsonb_set(args,'{include}','false'))->'titles' is distinct from '[]'::jsonb then
   raise exception 'Título local explícito ou evidência histórica indisponível.';
  end if;
  for other in 1..4 loop
   if office=other then continue;end if;
   if pg_temp.workshop_restore_read(other,'operational_photos',args) is not null
    or snapshot->'titles' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1900+other))) then
    raise exception 'Fotos ou títulos de outra oficina apareceram no roteiro.';
   end if;
  end loop;
  update public.rm_cadastro_fotos set titulo=titulo||' revisado' where id=em_fixture.id(1900+(office%4)+1);
  if pg_temp.workshop_restore_read(office,'operational_photos',args) is distinct from snapshot then
   raise exception 'A revisão de um título estrangeiro afetou a configuração local.';
  end if;
  foreach action in array array['add','replace','tag','retire','restore'] loop
   payload:=jsonb_build_object('projeto_id',project,'celula_projeto_id',allocation,'action',action,
    'expected_project_updated_at',snapshot->'project'->'updated_at','expected_allocation_updated_at',snapshot->'allocation'->'updated_at',
    'expected_photos_version',snapshot->>'photos_version');
   if action='add' then payload:=payload||jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',original_photo,'cadastro_foto_id',title)));
   else
    select x into strict item from jsonb_array_elements(snapshot->'photos') x where x->>'id'=(case when action='replace' then original_photo else replacement end)::text;
    payload:=payload||jsonb_build_object('foto_id',item->'id','expected_foto_updated_at',item->'updated_at');
    if action='replace' then payload:=payload||jsonb_build_object('new_id',replacement,'cadastro_foto_id',second_title,'numero',10,'descricao',null,'tag',null,'confirm_change',true);
    elsif action='tag' then payload:=payload||jsonb_build_object('tag','Teste de isolamento');end if;
   end if;
   begin
    perform pg_temp.workshop_restore_planning_write((office%4)+1,gen_random_uuid(),'manage_operational_photos',payload);
    raise exception 'Uma alteração de foto passou com o contexto de outra oficina.';
   exception when insufficient_privilege then null;end;
   begin
    perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'manage_operational_photos',payload,false);
    raise exception 'A alteração de foto passou pelo protocolo sem oficina.';
   exception when insufficient_privilege then null;end;
   if action in('add','replace') then
    begin
     perform pg_temp.workshop_restore_planning_write(office,gen_random_uuid(),'manage_operational_photos',jsonb_set(payload,
      case when action='add' then '{items,0,cadastro_foto_id}'::text[] else '{cadastro_foto_id}'::text[] end,to_jsonb(em_fixture.id(1900+(office%4)+1))));
     raise exception 'Um título estrangeiro foi aceito na alocação.';
    exception when invalid_parameter_value then null;end;
   end if;
   submission:=gen_random_uuid();
   result:=pg_temp.workshop_restore_planning_write(office,submission,'manage_operational_photos',payload);
   snapshot:=pg_temp.workshop_restore_read(office,'operational_photos',args);
   if snapshot->>'photos_version' is distinct from result->'record'->>'photos_version'
    or (pg_temp.workshop_restore_planning_write(office,submission,'manage_operational_photos',payload))->>'idempotent_replay' is distinct from 'true' then
    raise exception 'Consulta, alteração e reenvio das fotos previstas divergiram.';
   end if;
  end loop;
  if not (select lixeira from public.rm_fotos where id=original_photo)
   or not exists(select 1 from public.rm_fotos where id=replacement and not lixeira and cadastro_foto_id=second_title and tag='Teste de isolamento')
   or not exists(select 1 from public.rm_fotos where id=evidence and not lixeira and foto_url='https://fixture.invalid/received.png') then
   raise exception 'O histórico da substituição ou o arquivo capturado se perdeu.';
  end if;
 end loop;
end
$photo_configuration$;
do $stage_proof$
declare args jsonb;
begin
 perform rm_private.activate_workshop_stage_proof_v1();
 if has_function_privilege('authenticated','rm_private.stage_rule_metadata_v1(uuid)','execute') then
  raise exception 'A prova antiga das aprovações ainda pode ser acessada diretamente.';
 end if;
 for office in 1..4 loop
  args:=jsonb_build_object('project',em_fixture.id(100+office),'allocation',em_fixture.id(300+office),'include',false);
  if pg_temp.workshop_restore_read(office,'operational_stage_rules',args)->'allocation'->>'id' is distinct from em_fixture.id(300+office)::text
   or pg_temp.workshop_restore_read(office,'project_route',jsonb_build_object('p_project_id',em_fixture.id(100+office))) is null
   or pg_temp.workshop_restore_read(office,'cell_availability',jsonb_build_object('project_id',em_fixture.id(100+office),
    'allocation_id',em_fixture.id(300+office))) is null then
   raise exception 'A prova privada comprometeu uma consulta autorizada do roteiro.';
  end if;
 end loop;
end
$stage_proof$;
do $reviewer_proof$
declare args jsonb; result jsonb;
begin
 perform rm_private.activate_workshop_form_reviewers_v1();
 if has_table_privilege('authenticated','public.rm_form_reviewer_assignments','select')
  or not has_table_privilege('service_role','public.rm_form_reviewer_assignments','select') then
  raise exception 'Acesso direto às atribuições divergiu do contrato.';
 end if;
 for office in 1..4 loop
  perform pg_temp.workshop_restore_sso(office);
  args:=jsonb_build_object('project',em_fixture.id(100+office),'allocation',em_fixture.id(300+office),'include',false);
  result:=pg_temp.workshop_restore_read(office,'operational_reviewers',args);
  if result->'forms'->0->'assignment'->>'avaliador_user_id' is distinct from em_fixture.id(740+office)::text
   or result->'eligible_users' is distinct from '[]'::jsonb or result->'forms'->0->>'action_reason' is not null then
   raise exception 'A consulta autorizada perdeu a atribuição histórica ou expôs escolhas.';
  end if;
 end loop;
end
$reviewer_proof$;
do $isolated_details$
declare
 project uuid;
 record_id uuid;
 project_args jsonb;
 record_args jsonb;
 value jsonb;
begin
 if has_function_privilege('authenticated','rm_private.workshop_project_detail_v1(jsonb,uuid)','execute')
  or has_function_privilege('service_role','rm_private.workshop_form_record_detail_v1(jsonb,uuid)','execute') then
  raise exception 'Consulta de detalhe disponível sem autorização por oficina.';
 end if;
 for office in 1..4 loop
  project:=em_fixture.id(100+office);
  record_id:=em_fixture.id(500+office);
  project_args:=jsonb_build_object('id',project,'planning',true,'forms',true,'photos',true,'history',true,'documents',true,
   'equipment',true,'dossier',true,'edit',false,'photo_page',1,'selected_only',false,'selected_first',true);
  record_args:=jsonb_build_object('id',record_id,'projects',true,'documents',true,'photos',true);
  value:=pg_temp.workshop_restore_read(office,'project_detail',project_args);
  if value->'project'->>'id' is distinct from project::text or value->>'hasAllocations' is distinct from 'true'
   or not value->'allocations' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(300+office),'projeto_id',project))
   or not value->'records' @> jsonb_build_array(jsonb_build_object('id',record_id))
   or not value->'forms' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(400+office)))
   or not value->'photos' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1450+office)))
   or exists(select 1 from jsonb_array_elements(value->'photos') p where p?'foto_url') then
   raise exception 'O dossiê perdeu vínculos autorizados ou expôs o endereço bruto da galeria.';
  end if;
  value:=pg_temp.workshop_restore_read(office,'project_detail',project_args||'{"planning":false,"forms":false,"photos":false,"history":false,"documents":false,"equipment":false,"edit":true}');
  if value->>'hasAllocations' is distinct from 'true' or value->'allocations' is distinct from '[]'
   or value->'records' is distinct from '[]' or value->>'photoTotal' is distinct from '0' or value->'project'?'arquivo_nota_fiscal_url' then
   raise exception 'O editor sem escopo de planejamento recebeu detalhes não autorizados.';
  end if;
  value:=pg_temp.workshop_restore_read(office,'form_record_detail',record_args);
  if value->'record'->>'id' is distinct from record_id::text or value->'project'->>'id' is distinct from project::text
   or not value->'questions' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1480+office),'form_id',em_fixture.id(400+office)))
   or not value->'answers' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1460+office),'registro_formulario_id',record_id)) then
   raise exception 'O formulário autorizado perdeu as respostas ou o modelo histórico.';
  end if;
  value:=pg_temp.workshop_restore_read(office,'form_record_detail',record_args||'{"projects":false,"documents":false,"photos":false}');
  if value->'project' is distinct from 'null'::jsonb
   or exists(select 1 from jsonb_array_elements(value->'answers') a where a?'fotos_urls' or a?'assinatura_url') then
   raise exception 'O formulário apresentou metadados fora do escopo autorizado.';
  end if;
  for other in 1..4 loop
   if office=other then continue;end if;
   if pg_temp.workshop_restore_read(other,'project_detail',project_args) is not null
    or pg_temp.workshop_restore_read(other,'form_record_detail',record_args) is not null then
     raise exception 'Consulta por identificador revelou dossiê ou formulário de outra oficina.';
   end if;
  end loop;
 end loop;
end
$isolated_details$;
do $legacy_storage$
declare
 device uuid;
 other_device uuid;
 reference text;
 signature_path text;
 copy_path text;
 evidence jsonb;
 result jsonb;
begin
 if has_function_privilege('authenticated','rm_private.assert_workshop_legacy_media_ready_v1(text)','execute')
  or has_function_privilege('service_role','rm_private.workshop_legacy_media_readiness_v1(text)','execute') then
  raise exception 'Controles do armazenamento legado disponíveis à aplicação.';
 end if;
 for office in 1..4 loop
  device:=em_fixture.id(710+office);
  other_device:=em_fixture.id(710+((office%4)+1));
  signature_path:=device::text||'/legacy.png';
  reference:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-assinaturas/'||signature_path;
  insert into storage.objects(bucket_id,name) values('rm-documentos',device::text||'/legacy.pdf'),('rm-assinaturas',signature_path);
  update public.rm_respostas set assinatura_url=reference where id=em_fixture.id(1460+office);
  perform set_config('request.jwt.claim.sub',device::text,true);
  set local role authenticated;
  if not exists(select 1 from storage.objects where bucket_id='rm-documentos' and name=device::text||'/legacy.pdf')
   or not exists(select 1 from storage.objects where bucket_id='rm-assinaturas' and name=signature_path)
   or exists(select 1 from storage.objects where bucket_id in('rm-documentos','rm-assinaturas')
    and name like other_device::text||'/legacy.%') then
   raise exception 'O cliente legado perdeu seus arquivos ou ganhou acesso ao arquivo de outro dispositivo.';
  end if;
  update storage.objects set user_metadata='{"legacy_retry":true}' where bucket_id='rm-assinaturas' and name=signature_path;
  if found then raise exception 'O dispositivo conseguiu substituir uma assinatura pública.';end if;
  begin
   insert into storage.objects(bucket_id,name) values('rm-assinaturas',device::text||'/new.png');
   raise exception 'O dispositivo conseguiu publicar uma nova assinatura.';
  exception when insufficient_privilege then null;
  end;
  reset role;
 end loop;
 begin
  perform rm_private.assert_workshop_legacy_media_ready_v1('rm-assinaturas');
  raise exception 'Armazenamento com assinaturas sem cópia foi fechado.';
 exception when sqlstate 'PT409' then null;
 end;
 for office in 1..4 loop
  signature_path:=em_fixture.id(710+office)::text||'/legacy.png';
  reference:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-assinaturas/'||signature_path;
  copy_path:='acervo-oficina/'||em_fixture.id(office)::text||'/'||encode(sha256(convert_to(reference,'UTF8')),'hex')||'.png';
  insert into storage.objects(bucket_id,name,metadata,user_metadata)
   values('rm-documentos',copy_path,'{"size":8,"mimetype":"image/png"}',jsonb_build_object('sha256',repeat('e',64)));
  if public.rm_confirm_workshop_archive_v1(em_fixture.id(office),reference,repeat('e',64),'image/png',8) is distinct from copy_path then
   raise exception 'As assinaturas copiadas não foram reconhecidas.';
  end if;
 end loop;
 perform rm_private.assert_workshop_legacy_media_ready_v1('rm-assinaturas');
 -- Emulate the result of the Storage API in the disposable test database.
 update storage.buckets set public=false where id='rm-assinaturas';
 evidence:=rm_private.workshop_legacy_media_readiness_v1('rm-assinaturas');
 if evidence->>'public' is distinct from 'false' or evidence->>'legacy_objects' is distinct from '4'
  or evidence->>'references' is distinct from '4' or evidence->>'verified_copies' is distinct from '4' then
  raise exception 'Mudança de visibilidade ocorreu sem preservar todas as assinaturas.';
 end if;
 for office in 1..4 loop
  device:=em_fixture.id(710+office);
  signature_path:=device::text||'/legacy.png';
  perform set_config('request.jwt.claim.sub',device::text,true);
  set local role authenticated;
  update storage.objects set user_metadata='{"legacy_retry":true}' where bucket_id='rm-assinaturas' and name=signature_path;
  if not found then raise exception 'O dispositivo perdeu a possibilidade de repetir o próprio envio privado.';end if;
  reset role;
  result:=pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(1460+office),'source','answer_signature'));
  if coalesce(result->>'archive_path','') not like 'acervo-oficina/'||em_fixture.id(office)::text||'/%'
   or pg_temp.workshop_restore_read((office%4)+1,'media_reference',jsonb_build_object('id',em_fixture.id(1460+office),'source','answer_signature')) is not null then
   raise exception 'Assinatura histórica perdeu o acesso autorizado ou foi disponibilizada a outra oficina.';
  end if;
 end loop;
 begin
  perform rm_private.assert_workshop_legacy_media_ready_v1('rm-fotos');
  raise exception 'Armazenamento com foto sem garantia de cópia foi fechado.';
 exception when sqlstate 'PT409' then null;
 end;
end
$legacy_storage$;
savepoint form_options_fixture;
do $form_options$
declare
 device uuid;
 session_id uuid;
 delegation text;
 context jsonb;
 full_page jsonb;
 delta_page jsonb;
 ids_page jsonb;
 detail jsonb;
 record_args jsonb;
begin
 if exists(select 1 from unnest(array['anon','authenticated','service_role']) actor(role)
  where has_table_privilege(role,'rm_private.workshop_form_options_v1','select')) then
  raise exception 'As alternativas ficaram acessíveis fora das consultas autorizadas.';
 end if;
 insert into public.rm_itens_questoes(id,form_id,questao_id,descricao,updated_at)
 select em_fixture.id(1530+n),null,em_fixture.id(1480+n),'Legada '||n,'2000-01-01T00:00:00Z'::timestamptz from generate_series(1,4)n
 union all select em_fixture.id(1540+n),em_fixture.id(400+n),em_fixture.id(1480+n),'Vinculada '||n,'2000-01-01T00:00:00Z' from generate_series(1,4)n
 union all select em_fixture.id(1550+n),em_fixture.id(400+(n%4)+1),em_fixture.id(1480+n),'Vínculo divergente '||n,'2000-01-01T00:00:00Z' from generate_series(1,4)n;
 for office in 1..4 loop
  device:=em_fixture.id(710+office); session_id:=em_fixture.id(720+office); delegation:=repeat(chr(96+office),64);
  context:=pg_temp.workshop_restore_native_context(office,office);
  full_page:=public.rm_mobile_workshop_catalog_v1(device,session_id,delegation,context,'rm_itens_questoes',null,null,false);
  delta_page:=public.rm_mobile_workshop_catalog_v1(device,session_id,delegation,context,'rm_itens_questoes',
   '2001-01-01T00:00:00Z',em_fixture.id(400+office),false);
  ids_page:=public.rm_mobile_workshop_catalog_v1(device,session_id,delegation,context,'rm_itens_questoes',null,null,true);
  if jsonb_array_length(full_page->'rows')<>2 or jsonb_array_length(ids_page->'rows')<>2
   or not full_page->'rows' @> jsonb_build_array(
    jsonb_build_object('id',em_fixture.id(1530+office),'form_id',em_fixture.id(400+office),'questao_id',em_fixture.id(1480+office)),
    jsonb_build_object('id',em_fixture.id(1540+office),'form_id',em_fixture.id(400+office),'questao_id',em_fixture.id(1480+office)))
   or not ids_page->'rows' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(1530+office)),
    jsonb_build_object('id',em_fixture.id(1540+office)))
   or jsonb_array_length(delta_page->'rows')<>1 or delta_page->'rows'->0->>'id' is distinct from em_fixture.id(1530+office)::text then
   raise exception 'O catálogo Android perdeu alternativas, ignorou a atualização incremental ou incluiu outra oficina.';
  end if;
  record_args:=jsonb_build_object('id',em_fixture.id(500+office),'projects',false,'documents',false,'photos',false);
  detail:=pg_temp.workshop_restore_read(office,'form_record_detail',record_args);
  if jsonb_array_length(detail->'items')<>2 or not detail->'items' @> jsonb_build_array(
   jsonb_build_object('id',em_fixture.id(1530+office),'form_id',em_fixture.id(400+office),'questao_id',em_fixture.id(1480+office)),
   jsonb_build_object('id',em_fixture.id(1540+office),'form_id',em_fixture.id(400+office),'questao_id',em_fixture.id(1480+office)))
   or pg_temp.workshop_restore_read((office%4)+1,'form_record_detail',record_args) is not null then
   raise exception 'O detalhe web perdeu alternativas ou aceitou uma consulta cruzada.';
  end if;
 end loop;
 if (select count(*) from public.rm_itens_questoes where form_id is null and updated_at='2000-01-01T00:00:00Z')<>4 then
  raise exception 'Os itens legados perderam a representação original.';
 end if;
end
$form_options$;
rollback to savepoint form_options_fixture;
release savepoint form_options_fixture;
savepoint legacy_catalog_fixture;
do $legacy_catalog$
declare
 bma_device uuid:=em_fixture.id(711);
 bma_session uuid:=em_fixture.id(721);
 own_cell uuid:=em_fixture.id(201);
 foreign_cell uuid:=em_fixture.id(202);
 own_choice uuid:=em_fixture.id(1561);
 foreign_choice uuid:=em_fixture.id(1562);
 visible_count bigint;
 resource text;
 result jsonb;
begin
 if has_function_privilege('service_role','rm_private.activate_workshop_legacy_bma_catalog_v1(uuid,uuid)','execute')
  or has_function_privilege('authenticated','rm_private.activate_workshop_legacy_bma_catalog_v1(uuid,uuid)','execute')
  or has_table_privilege('authenticated','rm_private.workshop_legacy_bma_catalog_rows','select') then
  raise exception 'Um cliente pode ativar ou consultar o inventário técnico do legado.';
 end if;
 begin
  perform rm_private.activate_workshop_legacy_bma_catalog_v1(bma_device,bma_session);
  raise exception 'O acesso legado foi ativado sem evidência da oficina.';
 exception when sqlstate 'PT409' then null; end;
 insert into public.rm_itens_questoes(id,questao_id,descricao) values
  (own_choice,em_fixture.id(1481),'Alternativa da BMA'),(foreign_choice,em_fixture.id(1482),'Alternativa de outra oficina');
 perform public.rm_observe_mobile_workshop_android_v1(bma_device,bma_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(1,1),'1.2.24',27);
 begin
  perform rm_private.activate_workshop_legacy_bma_catalog_v1(em_fixture.id(712),bma_session);
  raise exception 'Um dispositivo recebeu a permissão com a sessão de outro.';
 exception when sqlstate 'PT409' then null; end;
 perform rm_private.activate_workshop_legacy_bma_catalog_v1(bma_device,bma_session);
 perform rm_private.activate_workshop_legacy_bma_catalog_v1(bma_device,bma_session);
 if (select count(*) from pg_policy where polname='rm_legacy_bma_catalog_read' and not polpermissive and polcmd='r')<>12 then
  raise exception 'O recorte direto não foi aplicado a todos os catálogos.';
 end if;

 perform set_config('request.jwt.claim.sub',bma_device::text,true);
 set local role authenticated;
 if not exists(select 1 from public.rm_celulas where id=own_cell) or exists(select 1 from public.rm_celulas where id=foreign_cell)
  or not exists(select 1 from public.rm_itens_questoes where id=own_choice and form_id is null)
  or exists(select 1 from public.rm_itens_questoes where id=foreign_choice) then
  raise exception 'O dispositivo antigo recebeu catálogo estrangeiro ou perdeu seus dados da BMA.';
 end if;
 reset role;
 for office in 2..4 loop
  perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
  for resource in select c.relname from pg_policy p join pg_class c on c.oid=p.polrelid where p.polname='rm_legacy_bma_catalog_read' loop
   set local role authenticated;
   execute format('select count(*) from public.%I',resource) into visible_count;
   reset role;
   if visible_count<>0 then raise exception 'O acesso direto revelou catálogos a outro dispositivo.'; end if;
  end loop;
  result:=public.rm_mobile_workshop_catalog_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),
   pg_temp.workshop_restore_native_context(office,office),'rm_celulas',null,null,false);
  if not result->'rows' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(200+office)))
   or exists(select 1 from jsonb_array_elements(result->'rows') item
    where not rm_private.workshop_cell_owned_v1((item->>'id')::uuid,em_fixture.id(office))) then
   raise exception 'O Android autorizado pela Central perdeu o catálogo da própria oficina.';
  end if;
 end loop;
 perform public.rm_observe_mobile_workshop_android_v1(bma_device,bma_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(2,1),'1.2.24',27);
 delete from rm_private.workshop_android_observations where session_id=bma_session;
 perform set_config('request.jwt.claim.sub',bma_device::text,true);
 set local role authenticated;
 if exists(select 1 from public.rm_celulas) then raise exception 'O dispositivo readquiriu o acesso antigo após a transferência.'; end if;
 reset role;
end
$legacy_catalog$;
rollback to savepoint legacy_catalog_fixture;
release savepoint legacy_catalog_fixture;
savepoint legacy_operations_fixture;
do $legacy_operations$
declare
 device uuid:=em_fixture.id(711);
 device_session uuid:=em_fixture.id(721);
 operator_id uuid:=em_fixture.id(3601);
 customer uuid:=em_fixture.id(3602);
 protocol uuid:=em_fixture.id(3603);
 unknown_project uuid:=em_fixture.id(3604);
 unrelated_person uuid:=em_fixture.id(3605);
 own_project uuid:=em_fixture.id(101);
 other_project uuid:=em_fixture.id(102);
 own_answer uuid:=em_fixture.id(1461);
 other_answer uuid:=em_fixture.id(1462);
 device_profile uuid:=em_fixture.id(731);
 own_operator uuid:=em_fixture.id(3606);
 other_operator uuid:=em_fixture.id(3607);
 other_profile uuid;
 delegation text:=repeat('c1',32);
 opened jsonb;
 completed jsonb;
 base_args jsonb;
 opened_project uuid;
 completed_project uuid;
 equipment uuid;
 visible_count bigint;
 resource text;
 result jsonb;
begin
 if has_function_privilege('authenticated','rm_private.activate_workshop_legacy_bma_operations_v1()','execute')
  or has_function_privilege('service_role','rm_private.activate_workshop_legacy_bma_operations_v1()','execute')
  or has_table_privilege('authenticated','rm_private.workshop_legacy_bma_operation_rows','select')
  or has_table_privilege('authenticated','rm_private.workshop_legacy_bma_people_rows','select')
  or has_function_privilege('service_role','rm_private.activate_workshop_legacy_bma_people_v1()','execute')
  or has_function_privilege('authenticated','rm_private.activate_workshop_legacy_bma_people_v1()','execute') then
  raise exception 'O inventário operacional ou a ativação ficaram acessíveis ao cliente.';
 end if;
 begin
  perform rm_private.activate_workshop_legacy_bma_operations_v1();
  raise exception 'A ativação não exigiu a conta de dispositivo aprovada.';
 exception when sqlstate 'PT409' then null; end;
 begin
  perform rm_private.activate_workshop_legacy_bma_people_v1();
  raise exception 'A ativação de pessoas não exigiu o recorte das operações.';
 exception when sqlstate 'PT409' then null; end;
 perform public.rm_observe_mobile_workshop_android_v1(device,device_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(1,1),'1.2.24',27);
 perform rm_private.activate_workshop_legacy_bma_catalog_v1(device,device_session);
 perform rm_private.activate_workshop_legacy_bma_operations_v1();
 perform rm_private.activate_workshop_legacy_bma_operations_v1();
 perform rm_private.activate_workshop_legacy_bma_people_v1();
 perform rm_private.activate_workshop_legacy_bma_people_v1();
 if (select count(*) from pg_policy where polname='rm_legacy_bma_operations_read' and not polpermissive and polcmd='r')<>12 then
  raise exception 'O recorte direto não cobriu os dados operacionais.';
 end if;

 insert into public.rm_users(id,nome,perfil) values(operator_id,'Operador de recebimento legado local','mobile'),
  (unrelated_person,'Pessoa sem vínculo comprovado','mobile');
 -- The assignment fixtures also contain people with recorded memberships in more than one workshop.
 insert into public.rm_users(id,nome,perfil)
  select em_fixture.id(3605+n),'Pessoa com histórico em uma oficina '||n,'mobile' from generate_series(1,4)n;
 insert into public.rm_tablet_celula_users(celula_id,identidade_id)
  select em_fixture.id(200+n),em_fixture.id(3605+n) from generate_series(1,4)n;
 insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
  values(extensions.digest(delegation,'sha256'),device,em_fixture.id(731),operator_id,clock_timestamp()+interval '1 hour');
 insert into public.rm_clientes(id,nome) values(customer,'Cliente de recebimento legado local');
 insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',customer,em_fixture.id(1));
 insert into public.rm_projetos(id,numero,created_by_user_id) values(unknown_project,'Abertura sem protocolo',operator_id);
 base_args:=jsonb_build_object('p_operador_id',operator_id,'p_cliente_id',customer,'p_chegada_equipamento',clock_timestamp(),
  'p_descricao_equipamento','Recebimento de teste local','p_equipamento','{}'::jsonb,'p_fotos_recebimento','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',device::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',device_session,'aal','aal1')::text,true);
 set local role authenticated;
 if exists(select 1 from public.rm_users where id in(operator_id,unrelated_person,other_operator))
  or not exists(select 1 from public.rm_users where id=own_operator)
  or not exists(select 1 from public.rm_users where auth_user_id=device and status='ativo') then
  raise exception 'O cadastro de pessoas perdeu o perfil próprio ou a equipe comprovada, ou mostrou pessoas sem origem local.';
 end if;
 opened:=public.rm_mobile_open_receiving_v1(protocol,base_args||jsonb_build_object('p_receiving_draft_id',protocol,
  'p_receiving_draft_revision',0,'p_receiving_draft_snapshot',jsonb_build_object('id',protocol,'version',2,'submitted',false)),delegation);
 completed:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_recebimento_v1',base_args,delegation);
 opened_project:=(opened->>'projeto_id')::uuid;
 completed_project:=(completed->>'projeto_id')::uuid;
 equipment:=(opened->>'equipamento_id')::uuid;
 if not exists(select 1 from public.rm_projetos where id=own_project)
  or exists(select 1 from public.rm_projetos where id in(other_project,unknown_project))
  or not exists(select 1 from public.rm_respostas where id=own_answer)
  or exists(select 1 from public.rm_respostas where id=other_answer)
  or (select count(*) from public.rm_projetos where id in(opened_project,completed_project))<>2
  or not exists(select 1 from public.rm_equipamentos where id=equipment and projeto_id=opened_project)
  or not exists(select 1 from public.rm_users where id=operator_id) then
  raise exception 'O legado perdeu o recebimento autorizado ou mostrou dados externos ou sem protocolo.';
 end if;
 reset role;
 if exists(select 1 from rm_private.workshop_project_ownership where id in(opened_project,completed_project)) then
  raise exception 'A compatibilidade de leitura alterou a origem dos recebimentos.';
 end if;

 for office in 2..4 loop
  perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
  other_profile:=em_fixture.id(730+office);
  set local role authenticated;
  if (select array_agg(id) from public.rm_users) is distinct from array[other_profile] then
   raise exception 'A leitura de autenticação perdeu o perfil próprio ou mostrou outra pessoa.';
  end if;
  reset role;
  for resource in select c.relname from pg_policy p join pg_class c on c.oid=p.polrelid where p.polname='rm_legacy_bma_operations_read' loop
   set local role authenticated;
   execute format('select count(*) from public.%I',resource) into visible_count;
   reset role;
   if visible_count<>0 then raise exception 'Dados operacionais ficaram disponíveis por acesso direto de outra oficina.'; end if;
  end loop;
  result:=public.rm_mobile_workshop_catalog_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),
   pg_temp.workshop_restore_native_context(office,office),'rm_projetos',null,null,false);
  if not result->'rows' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(100+office)))
   or result->'rows' @> jsonb_build_array(jsonb_build_object('id',own_project)) then
   raise exception 'A consulta autorizada do Android perdeu o projeto local ou incluiu a BMA.';
  end if;
  result:=public.rm_mobile_workshop_catalog_v1(em_fixture.id(710+office),em_fixture.id(720+office),repeat(chr(96+office),64),
   pg_temp.workshop_restore_native_context(office,office),'rm_users',null,null,false);
  if not result->'rows' @> jsonb_build_array(jsonb_build_object('id',em_fixture.id(3605+office)))
   or result->'rows' @> jsonb_build_array(jsonb_build_object('id',own_operator)) then
   raise exception 'A consulta moderna perdeu o operador local ou incluiu o operador da BMA.';
  end if;
 end loop;

 perform set_config('request.jwt.claim.sub',device::text,true);
 perform public.rm_observe_mobile_workshop_android_v1(device,device_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(2,1),'1.2.24',27);
 set local role authenticated;
 if (select array_agg(id) from public.rm_users) is distinct from array[device_profile] then
  raise exception 'A transferência do dispositivo não encerrou o acesso legado a pessoas.';
 end if;
 reset role;
end
$legacy_operations$;
select 'PASS: only the verified legacy device can read proven BMA people, self profiles remain available, and other workshops use scoped catalogs' result;
rollback to savepoint legacy_operations_fixture;
release savepoint legacy_operations_fixture;
savepoint legacy_operator_reads_fixture;
do $legacy_operator_reads$
declare
 device uuid:=em_fixture.id(711);
 device_session uuid:=em_fixture.id(721);
 bma uuid:=em_fixture.id(1);
 bma_cell uuid:=em_fixture.id(201);
 foreign_cell uuid:=em_fixture.id(202);
 bma_allocation uuid:=em_fixture.id(301);
 foreign_allocation uuid:=em_fixture.id(302);
 bma_actor uuid:=em_fixture.id(3711);
 foreign_actor uuid:=em_fixture.id(3712);
 local_execution_actor uuid:=em_fixture.id(741);
 local_execution uuid:=em_fixture.id(970+1);
 expected_cells uuid[];
 context jsonb;
 refreshed jsonb;
 token text;
 native_token text;
 allowed_id uuid;
begin
 if has_function_privilege('authenticated','rm_private.activate_workshop_legacy_operator_reads_v1()','execute')
  or has_function_privilege('service_role','rm_private.activate_workshop_legacy_operator_reads_v1()','execute')
  or has_function_privilege('authenticated','rm_private.workshop_legacy_operator_office_v1(uuid)','execute')
  or has_table_privilege('authenticated','rm_private.workshop_legacy_operator_read_settings','select') then
  raise exception 'A ativação ou sua autoridade ficaram acessíveis ao cliente.';
 end if;
 begin
  perform rm_private.activate_workshop_legacy_operator_reads_v1();
  raise exception 'A ativação não exigiu o recorte de pessoas.';
 exception when sqlstate 'PT409' then null; end;
 perform public.rm_observe_mobile_workshop_android_v1(device,device_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(1,1),'1.2.24',27);
 perform rm_private.activate_workshop_legacy_bma_catalog_v1(device,device_session);
 perform rm_private.activate_workshop_legacy_bma_operations_v1();
 perform rm_private.activate_workshop_legacy_bma_people_v1();
 perform rm_private.activate_workshop_legacy_operator_reads_v1();
 perform rm_private.activate_workshop_legacy_operator_reads_v1();
 if has_function_privilege('authenticated','public.rm_user_has_element_permission(uuid,text)','execute')
  or has_function_privilege('anon','public.rm_user_has_element_permission(uuid,text)','execute')
  or not has_function_privilege('service_role','public.rm_user_has_element_permission(uuid,text)','execute')
  or has_function_privilege('authenticated','public.rm_mobile_execution_snapshot_v1(text,uuid)','execute') then
  raise exception 'A ativação ampliou a leitura de clientes ou removeu acesso interno.';
 end if;

 -- Exercise the case where the installation still supports legacy execution
 -- reads. The earlier matrix has already tested the permanent mobile cutover.
 grant execute on function public.rm_mobile_execution_snapshot_v1(text,uuid) to authenticated;
 insert into public.rm_users(id,nome,matricula,perfil) values
  (bma_actor,'Administrador local BMA','WORKSHOP-LOCAL-BMA','administrador'),
  (foreign_actor,'Administrador de outra oficina','WORKSHOP-LOCAL-BRJ','administrador');
 insert into rm_private.user_credentials(user_id,palavra_chave_hash)
  select u,extensions.crypt('isolated-fixture-password',extensions.gen_salt('bf',4)) from unnest(array[bma_actor,foreign_actor]) u;
 insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(bma_cell,bma_actor),(foreign_cell,foreign_actor);
 select array_agg(cell_id order by cell_id) into expected_cells from rm_private.workshop_cell_ownership where workshop_id=bma;

 perform set_config('request.jwt.claim.sub',device::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',device_session,'aal','aal1')::text,true);
 set local role authenticated;
 context:=public.rm_authenticate_operator_v1('WORKSHOP-LOCAL-BMA','isolated-fixture-password',p_celula_id=>bma_cell);
 token:=context->>'operator_token';
 if (context->>'authenticated')::boolean is distinct from true or context->>'operador_id'<>bma_actor::text or length(token)<>64
  or (select array_agg(cell order by cell) from (select (r->>'celula_id')::uuid cell from jsonb_array_elements(context->'celulas_vinculadas') r) ids)
    is distinct from expected_cells then
  raise exception 'A identificação não preservou o administrador e as células autorizadas da BMA.';
 end if;
 refreshed:=public.rm_operator_context_v1(token);
 if refreshed->'celulas_vinculadas' is distinct from context->'celulas_vinculadas'
  or refreshed->'token_expires_at' is distinct from context->'token_expires_at' then
  raise exception 'A renovação modificou a delegação ou o catálogo da oficina.';
 end if;
 begin
  perform public.rm_authenticate_operator_v1('WORKSHOP-LOCAL-BMA','isolated-fixture-password',p_celula_id=>foreign_cell);
  raise exception 'A identificação aceitou a indicação explícita de uma célula externa.';
 exception when insufficient_privilege then null; end;
 refreshed:=public.rm_authenticate_operator_v1('WORKSHOP-LOCAL-BRJ','isolated-fixture-password');
 if refreshed->>'operador_id'<>foreign_actor::text or refreshed->'celulas_vinculadas' is distinct from '[]'::jsonb
  or public.rm_operator_context_v1(refreshed->>'operator_token')->'celulas_vinculadas' is distinct from '[]'::jsonb then
  raise exception 'A conta do dispositivo legou um catálogo a outro operador sem vínculo comprovado.';
 end if;
 context:=public.rm_mobile_execution_snapshot_v1(repeat('a',64),bma_allocation);
 if context->'allocation'->>'id'<>bma_allocation::text or context->'session'->>'id'<>local_execution::text
  or context->>'operator_id'<>local_execution_actor::text then
  raise exception 'A consulta legada perdeu o apontamento autorizado da BMA.';
 end if;
 begin
  perform public.rm_mobile_execution_snapshot_v1(token,foreign_allocation);
  raise exception 'A consulta legada retornou apontamento de outra oficina.';
 exception when no_data_found then null; end;
 reset role;

 for office in 2..4 loop
  native_token:=repeat(chr(96+office),64);
  allowed_id:=em_fixture.id(200+office);
  perform set_config('request.jwt.claim.sub',em_fixture.id(710+office)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(720+office),'aal','aal1')::text,true);
  set local role authenticated;
  if public.rm_operator_context_v1(native_token)->'celulas_vinculadas' is distinct from '[]'::jsonb then
   raise exception 'A identificação direta retornou células a um dispositivo que precisa da Central.';
  end if;
  begin
   perform public.rm_mobile_execution_snapshot_v1(native_token,foreign_allocation);
   raise exception 'A consulta legada retornou apontamentos antes da confirmação da oficina.';
  exception when no_data_found then null; end;
  reset role;
  refreshed:=public.rm_mobile_workshop_catalog_v1(em_fixture.id(710+office),em_fixture.id(720+office),native_token,
   pg_temp.workshop_restore_native_context(office,office),'rm_celulas',null,null,false);
  if not refreshed->'rows' @> jsonb_build_array(jsonb_build_object('id',allowed_id))
   or refreshed->'rows' @> jsonb_build_array(jsonb_build_object('id',bma_cell)) then
   raise exception 'A consulta pela Central perdeu as células autorizadas da oficina.';
  end if;
 end loop;

 perform set_config('request.jwt.claim.sub',device::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',device_session,'aal','aal1')::text,true);
 perform public.rm_observe_mobile_workshop_android_v1(device,device_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(2,1),'1.2.24',27);
 set local role authenticated;
 if public.rm_operator_context_v1(token)->'celulas_vinculadas' is distinct from '[]'::jsonb then
  raise exception 'A transferência preservou o catálogo anterior na renovação.';
 end if;
 reset role;
end
$legacy_operator_reads$;
select 'PASS: legacy operator reads scope login, refresh and execution to the approved BMA device and preserve delegated identity' result;
rollback to savepoint legacy_operator_reads_fixture;
release savepoint legacy_operator_reads_fixture;
savepoint legacy_mobile_writes_fixture;
do $legacy_mobile_writes$
declare
 bma uuid:=em_fixture.id(1);
 device uuid:=em_fixture.id(711);
 device_session uuid:=em_fixture.id(721);
 device_profile uuid:=em_fixture.id(731);
 actor uuid:=gen_random_uuid();
 token text:=repeat('e1',32);
 client_id uuid:=gen_random_uuid();
 protocol uuid:=gen_random_uuid();
 draft_id uuid:=gen_random_uuid();
 submission uuid;
 open_args jsonb;
 write_args jsonb;
 saved jsonb;
 replayed jsonb;
 action record;
 own_stage uuid:=gen_random_uuid();
 foreign_stage uuid:=gen_random_uuid();
 bma_title uuid:=gen_random_uuid();
 foreign_title uuid:=em_fixture.id(1122);
 bma_project uuid:=em_fixture.id(101);
 bma_cell uuid:=em_fixture.id(201);
 bma_slot uuid:=em_fixture.id(301);
 foreign_slot uuid:=em_fixture.id(302);
 foreign_type uuid:=em_fixture.id(1102);
 modern_device uuid:=em_fixture.id(712);
 modern_session uuid:=em_fixture.id(722);
 modern_actor uuid:=em_fixture.id(742);
 modern_token text:=repeat('b',64);
 modern_context jsonb;
begin
 if has_function_privilege('authenticated','rm_private.activate_workshop_legacy_mobile_writes_v1()','execute')
  or has_function_privilege('authenticated','rm_private.require_mobile_mutation_workshop_v1(uuid,text,jsonb,jsonb,uuid,text)','execute')
  or has_table_privilege('authenticated','rm_private.workshop_legacy_mobile_write_settings','select') then
  raise exception 'A ativação ou a validação de gravações ficaram acessíveis ao cliente.';
 end if;
 begin
  perform rm_private.activate_workshop_legacy_mobile_writes_v1();
  raise exception 'A ativação não exigiu o recorte de identificação.';
 exception when sqlstate 'PT409' then null;end;
 perform public.rm_observe_mobile_workshop_android_v1(device,device_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(1,1),'1.2.24',27);
 perform rm_private.activate_workshop_legacy_bma_catalog_v1(device,device_session);
 perform rm_private.activate_workshop_legacy_bma_operations_v1();
 perform rm_private.activate_workshop_legacy_bma_people_v1();
 perform rm_private.activate_workshop_legacy_operator_reads_v1();
 perform rm_private.activate_workshop_legacy_mobile_writes_v1();
 perform rm_private.activate_workshop_legacy_mobile_writes_v1();
 -- This branch still supports the BMA legacy snapshot and its legacy writer.
 delete from rm_private.execution_workshop_enforcement where channel='mobile';
 insert into public.rm_users(id,nome,perfil) values(actor,'Operador compatível do ensaio','administrador');
 insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(bma_cell,actor);
 insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
  values(extensions.digest(token,'sha256'),device,device_profile,actor,clock_timestamp()+interval '1 hour');
 insert into public.rm_clientes(id,nome) values(client_id,'Cliente BMA do ensaio');
 insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',client_id,bma);
 insert into public.rm_cadastro_fotos(id,titulo,celula_nome) select bma_title,'Visão local',nome from public.rm_celulas where id=bma_cell;
 insert into rm_private.engineering_photo_title_scope(title_id,workshop_id,cell_id) values(bma_title,bma,bma_cell);
 insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_projeto_id)
  values(own_stage,bma_project,bma_cell,bma_slot),(foreign_stage,em_fixture.id(102),em_fixture.id(202),foreign_slot);
 perform set_config('request.jwt.claim.sub',device::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',device_session,'aal','aal1')::text,true);

 for action in select * from (values
  ('rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',bma_slot,'p_status','em_dia'),
   jsonb_build_object('p_celula_projeto_id',foreign_slot,'p_status','em_dia')),
  ('rm_add_cell_comment_v1',jsonb_build_object('p_celula_projeto_id',bma_slot,'p_comentario','Comentário do teste isolado'),
   jsonb_build_object('p_celula_projeto_id',foreign_slot,'p_comentario','Comentário em outra oficina')),
  ('rm_submit_form_inspection_v1',jsonb_build_object('p_projeto_id',bma_project,'p_celula_id',bma_cell,'p_form_id',em_fixture.id(401)),
   jsonb_build_object('p_projeto_id',em_fixture.id(102),'p_celula_id',em_fixture.id(202),'p_form_id',em_fixture.id(402))),
  ('rm_submit_form_revision_v1',jsonb_build_object('p_registro_formulario_id',em_fixture.id(501)),
   jsonb_build_object('p_registro_formulario_id',em_fixture.id(502))),
  ('rm_transition_stage_approval_v1',jsonb_build_object('p_aprovacao_etapa_id',own_stage,'p_acao','aprovar'),
   jsonb_build_object('p_aprovacao_etapa_id',foreign_stage,'p_acao','aprovar')),
  ('rm_record_cell_photo_v1',jsonb_build_object('p_projeto_id',bma_project,'p_celula_id',bma_cell,'p_celula_projeto_id',bma_slot,
    'p_foto_url','https://fixture.invalid/legacy-photo.png','p_cadastro_foto_id',bma_title),
   jsonb_build_object('p_projeto_id',bma_project,'p_celula_id',bma_cell,'p_celula_projeto_id',bma_slot,
    'p_foto_url','https://fixture.invalid/legacy-photo.png','p_cadastro_foto_id',foreign_title)),
  ('rm_record_execution_event_v1',jsonb_build_object('p_session_id',gen_random_uuid(),'p_allocation_id',bma_slot,'p_operador_id',actor,
    'p_previous_event_id',null,'p_kind','start','p_occurred_at',clock_timestamp(),'p_pause_reason',null,'p_note',null,'p_effort_minutes',null),
   jsonb_build_object('p_session_id',gen_random_uuid(),'p_allocation_id',foreign_slot,'p_operador_id',actor,
    'p_previous_event_id',null,'p_kind','start','p_occurred_at',clock_timestamp(),'p_pause_reason',null,'p_note',null,'p_effort_minutes',null))
 ) cases(rpc,writable,forbidden) loop
  perform rm_private.require_mobile_mutation_workshop_v1(gen_random_uuid(),action.rpc,action.writable,action.writable,actor,token);
  submission:=gen_random_uuid();
  set local role authenticated;
  begin
   perform public.rm_mobile_mutate_v1(submission,action.rpc,action.forbidden,token);
   raise exception 'A gravação legada % atravessou a oficina.',action.rpc;
  exception when insufficient_privilege then null;end;
  if action.rpc in('rm_add_cell_comment_v1','rm_record_cell_photo_v1','rm_record_execution_event_v1') then
   saved:=public.rm_mobile_mutate_v1(submission,action.rpc,action.writable,token);
   replayed:=public.rm_mobile_mutate_v1(submission,action.rpc,action.writable,token);
   if (action.rpc<>'rm_record_cell_photo_v1' and saved->>'projeto_id' is distinct from bma_project::text)
    or replayed->>'idempotent_replay' is distinct from 'true' or replayed-'idempotent_replay' is distinct from saved-'idempotent_replay' then
    raise exception 'A gravação legada % perdeu o protocolo ou projeto original.',action.rpc;
   end if;
  end if;
  reset role;
  if action.rpc='rm_record_cell_photo_v1' and not exists(select 1 from public.rm_fotos
   where id=(saved->>'foto_id')::uuid and projeto_id=bma_project and celula_id=bma_cell and titulo='Visão local') then
   raise exception 'A foto local perdeu o vínculo com o projeto ou o título da oficina.';
  end if;
  if action.rpc in('rm_add_cell_comment_v1','rm_record_cell_photo_v1','rm_record_execution_event_v1')
   and (select count(*) from rm_private.mobile_mutation_receipts where client_submission_id=submission and operator_id=actor)<>1 then
   raise exception 'O reenvio do protocolo deixou mais de um efeito ou perdeu a autoria.';
  end if;
 end loop;

 open_args:=jsonb_build_object('p_operador_id',actor,'p_cliente_id',client_id,'p_chegada_equipamento',clock_timestamp(),
  'p_descricao_equipamento','Recebimento do ensaio','p_equipamento','{}'::jsonb,'p_fotos_recebimento','[]'::jsonb,
  'p_receiving_draft_id',protocol,'p_receiving_draft_revision',0,'p_receiving_draft_snapshot',jsonb_build_object('id',protocol,'version',2,'submitted',false));
 set local role authenticated;
 begin
  perform public.rm_mobile_open_receiving_v1(gen_random_uuid(),open_args||jsonb_build_object('p_tipo_equipamento_id',foreign_type),token);
  raise exception 'A abertura legada aceitou tipo de outra oficina.';
 exception when insufficient_privilege then null;end;
 saved:=public.rm_mobile_open_receiving_v1(protocol,open_args,token);
 replayed:=public.rm_mobile_open_receiving_v1(protocol,open_args,token);
 if saved->>'projeto_id' is distinct from replayed->>'projeto_id' or replayed->>'idempotent_replay' is distinct from 'true' then
  raise exception 'O recebimento legado perdeu a abertura original.';
 end if;
 replayed:=public.rm_mobile_mutate_v1(protocol,'rm_submit_recebimento_v1',open_args,token);
 if saved->>'projeto_id' is distinct from replayed->>'projeto_id' then
  raise exception 'A conclusão legada não reutilizou o recebimento original.';
 end if;
 if public.rm_receiving_draft_v1(token,'save',draft_id,jsonb_build_object('id',draft_id,'version',2),0,gen_random_uuid())->>'id'
  is distinct from draft_id::text then raise exception 'O rascunho legítimo não foi gravado.';end if;
 reset role;

 perform set_config('request.jwt.claim.sub',modern_device::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',modern_session,'aal','aal1')::text,true);
 write_args:=jsonb_build_object('p_celula_projeto_id',foreign_slot,'p_comentario','Comentário autorizado na oficina local');
 modern_context:=pg_temp.workshop_restore_native_context(2,2);
 submission:=gen_random_uuid();
 set local role authenticated;
 begin
  perform public.rm_mobile_mutate_v1(submission,'rm_add_cell_comment_v1',write_args,modern_token);
  raise exception 'O dispositivo de outra oficina deixou de exigir a Central.';
 exception when insufficient_privilege then null;end;
 begin
  perform public.rm_receiving_draft_v1(modern_token,'read');
  raise exception 'O dispositivo de outra oficina abriu rascunho pelo serviço legado.';
 exception when insufficient_privilege then null;end;
 reset role;
 perform public.rm_authorize_mobile_workshop_mutation_v1(modern_device,modern_session,modern_token,modern_context,
  submission,'rm_add_cell_comment_v1',write_args);
 set local role authenticated;
 begin
  perform public.rm_mobile_mutate_v1(submission,'rm_add_cell_comment_v1',write_args,modern_token);
  raise exception 'A gravação direta consumiu uma autorização sem passar pelo serviço autorizado.';
 exception when insufficient_privilege then null;end;
 saved:=public.rm_mobile_workshop_mutate_v1(submission,'rm_add_cell_comment_v1',write_args,modern_token);
 reset role;
 if saved->>'projeto_id' is distinct from em_fixture.id(102)::text
  or exists(select 1 from rm_private.mobile_workshop_mutation_permits where submission_id=submission) then
  raise exception 'O serviço autorizado perdeu a gravação local ou não consumiu a autorização.';
 end if;
 perform public.rm_authorize_mobile_workshop_mutation_v1(modern_device,modern_session,modern_token,modern_context,
  submission,'rm_add_cell_comment_v1',write_args);
 set local role authenticated;
 replayed:=public.rm_mobile_workshop_mutate_v1(submission,'rm_add_cell_comment_v1',write_args,modern_token);
 reset role;
 if replayed->>'comentario_id' is distinct from saved->>'comentario_id' or replayed->>'idempotent_replay' is distinct from 'true' then
  raise exception 'O reenvio moderno duplicou a gravação original.';
 end if;

 client_id:=gen_random_uuid();
 submission:=gen_random_uuid();
 insert into public.rm_clientes(id,nome) values(client_id,'Cliente BRJ do ensaio');
 insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',client_id,em_fixture.id(2));
 write_args:=jsonb_build_object('p_operador_id',modern_actor,'p_cliente_id',client_id,'p_chegada_equipamento',clock_timestamp(),
  'p_descricao_equipamento','Conclusão offline do ensaio','p_equipamento','{}'::jsonb,'p_fotos_recebimento','[]'::jsonb);
 perform public.rm_authorize_mobile_receiving_workshop_v1(modern_device,modern_session,modern_token,
  pg_temp.workshop_restore_native_context(2,2),submission,'complete',write_args);
 set local role authenticated;
 saved:=public.rm_mobile_receiving_workshop_v1(submission,'complete',write_args,modern_token);
 reset role;
 if not exists(select 1 from rm_private.receiving_workshop_protocols p where p.submission_id=submission
   and p.project_id=(saved->>'projeto_id')::uuid and p.workshop_id=em_fixture.id(2) and p.creation_phase='complete') then
  raise exception 'A conclusão offline moderna perdeu a origem comprovada da oficina.';
 end if;
end
$legacy_mobile_writes$;
select 'PASS: scoped legacy mobile writes preserve BMA offline retries and require the verified gateway for other workshops' result;
rollback to savepoint legacy_mobile_writes_fixture;
release savepoint legacy_mobile_writes_fixture;
do $portal_read_cutover$
declare
 args jsonb; value jsonb; native_count bigint;
 project uuid; equipment uuid; canonical_type uuid; profile_id uuid;
 binding_issuer constant text:='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1';
begin
 project:=em_fixture.id(101);
 perform set_config('request.jwt.claim.sub',em_fixture.id(11)::text,true);
 set local role authenticated;
 if not exists(select 1 from public.rm_projetos where id=project) then
  raise exception 'Preparing the migration interrupted direct access before activation.';
 end if;
 reset role;
 perform set_config('request.jwt.claim.sub',em_fixture.id(711)::text,true);
 set local role authenticated;
 select count(*) into native_count from public.rm_projetos;
 reset role;
 if native_count=0 then raise exception 'No native legacy access to verify.';end if;

 insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled)
  values(em_fixture.id(2410),binding_issuer,em_fixture.id(2411),em_fixture.id(731),em_fixture.id(711),false);
 begin
  perform rm_private.activate_workshop_portal_reads_v1();
  raise exception 'Activation accepted a portal identity with Android history.';
 exception when sqlstate 'PT409' then null;end;
 delete from rm_private.sso_identity_bindings where id=em_fixture.id(2410);
 perform rm_private.activate_workshop_portal_reads_v1();
 perform rm_private.activate_workshop_portal_reads_v1();
 if (select count(*) from rm_private.workshop_portal_auth_users)<>4
  or has_function_privilege('authenticated','public.rm_web_capacity_snapshot_v1(jsonb)','execute')
  or has_function_privilege('authenticated','public.rm_web_form_source_snapshot_v1(uuid)','execute')
  or has_function_privilege('authenticated','public.rm_web_form_template_snapshot_v1(uuid)','execute') then
  raise exception 'The cutover left an old reader open or registered an unexpected identity.';
 end if;

 for office in 1..4 loop
  project:=em_fixture.id(100+office);
  equipment:=em_fixture.id(2420+office);
  canonical_type:=em_fixture.id(1100+office);
  profile_id:=em_fixture.id(30+office);
  insert into public.rm_equipamentos(id,projeto_id,tipo_equipamento_id) values(equipment,project,canonical_type)
   on conflict(projeto_id) do update set tipo_equipamento_id=excluded.tipo_equipamento_id returning id into equipment;
  update public.rm_projetos set equipamento_id=equipment where id=project;
  args:=jsonb_build_object('project',project,'equipment',equipment,'type',canonical_type);
  value:=pg_temp.workshop_restore_read(office,'project_equipment_type',args);
  if value is distinct from (select jsonb_build_object('id',id,'nome',nome,'sigla',sigla)
   from public.rm_tipos_equipamento where id=canonical_type)
   or pg_temp.workshop_restore_read(office,'project_equipment_type',args||jsonb_build_object('type',em_fixture.id(1100+(office%4)+1))) is not null
   or pg_temp.workshop_restore_read(office,'project_equipment_type',args||jsonb_build_object('equipment',em_fixture.id(2429))) is not null then
   raise exception 'The scoped reader lost the linked type or accepted a stale binding.';
  end if;
  for other in 1..4 loop
   if office<>other and pg_temp.workshop_restore_read(other,'project_equipment_type',args) is not null then
    raise exception 'The scoped type reader returned data from another office.';
   end if;
  end loop;
  begin
   perform pg_temp.workshop_restore_read(office,'project_equipment_type',args||'{"extra":true}');
   raise exception 'Unknown type lookup arguments were accepted.';
  exception when invalid_parameter_value then null;end;
  value:=pg_temp.workshop_restore_read(office,'form_record_detail',jsonb_build_object('id',em_fixture.id(500+office),
   'projects',true,'documents',true,'photos',true));
  if value->'record'->>'id' is distinct from em_fixture.id(500+office)::text then
   raise exception 'The cutover interrupted scoped form records.';
  end if;
  value:=pg_temp.workshop_restore_read(office,'template_form',jsonb_build_object('id',em_fixture.id(400+office)));
  if value->'form'->>'id' is distinct from em_fixture.id(400+office)::text then
   raise exception 'The cutover interrupted the scoped published form template.';
  end if;
  value:=pg_temp.workshop_restore_read(office,'capacity_snapshot',jsonb_build_object(
   'start',(clock_timestamp() at time zone 'America/Sao_Paulo')::date,'days',14,'project_id',project,'can_manage',false));
  if value is null then raise exception 'The cutover interrupted the scoped capacity view.';end if;
  set local role authenticated;
  if not rm_private.workshop_portal_gateway_required_v1()
   or exists(select 1 from public.rm_projetos) or exists(select 1 from public.rm_fotos)
   or exists(select 1 from public.rm_respostas) or exists(select 1 from public.rm_tipos_equipamento)
   or exists(select 1 from public.rm_users where id<>profile_id)
   or not exists(select 1 from public.rm_users where id=profile_id)
   or not exists(select 1 from public.rm_option_sets) then
   raise exception 'Raw business rows were available or the portal lost its profile or option labels.';
  end if;
  reset role;
 end loop;

 -- A removed binding must not unlock the legacy read path for an existing Auth ID.
 update rm_private.sso_identity_bindings set enabled=false where id=em_fixture.id(41);
 delete from rm_private.sso_identity_bindings where id=em_fixture.id(42);
 insert into auth.users(id) values(em_fixture.id(2431));
 insert into public.rm_users(id,auth_user_id,nome,perfil) values(em_fixture.id(2432),em_fixture.id(2431),'Gestor local posterior','administrador');
 insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled)
  values(em_fixture.id(2433),binding_issuer,em_fixture.id(2434),em_fixture.id(2432),em_fixture.id(2431),false);
 begin
  insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled)
   values(em_fixture.id(2410),binding_issuer,em_fixture.id(2411),em_fixture.id(731),em_fixture.id(711),false);
  raise exception 'A newly bound portal identity overlapped an Android device.';
 exception when sqlstate 'PT409' then null;end;
 perform set_config('request.jwt.claims','{}',true);
 foreach project in array array[em_fixture.id(11),em_fixture.id(12),em_fixture.id(2431)] loop
  perform set_config('request.jwt.claim.sub',project::text,true);
  set local role authenticated;
  if not rm_private.workshop_portal_gateway_required_v1() or exists(select 1 from public.rm_projetos) then
   raise exception 'A disabled, removed, or later binding allowed direct access.';
  end if;
  reset role;
 end loop;
 perform set_config('request.jwt.claim.sub',em_fixture.id(711)::text,true);
 set local role authenticated;
 if rm_private.workshop_portal_gateway_required_v1() or (select count(*) from public.rm_projetos)<>native_count then
  raise exception 'The cutover altered the prior device reading behavior.';
 end if;
 reset role;
end
$portal_read_cutover$;
do $draft_photo_archive$
declare
 device uuid; actor uuid; draft uuid; office_id uuid; ref text; original_path text; copy_path text; verified_copy text;
 context jsonb; delegation text; output jsonb; route_mode text;
begin
 if has_table_privilege('authenticated','rm_private.workshop_legacy_draft_photos','select')
 or has_table_privilege('service_role','rm_private.workshop_legacy_draft_photos','select') then
  raise exception 'A origem privada do rascunho ficou acessível diretamente.';
 end if;
 for office in 1..4 loop
  office_id:=em_fixture.id(office);
  device:=em_fixture.id(710+office); actor:=em_fixture.id(1340+office); draft:=em_fixture.id(1350+office);
  delegation:=repeat('9'||office::text,32);
  context:=jsonb_set(pg_temp.workshop_restore_native_context(office,office),'{principals,1,subject}',to_jsonb(actor));
  route_mode:=case when office%2=0 then 'authenticated' else 'public' end;
  original_path:=device::text||'/legacy-draft.jpg';
  ref:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/'||route_mode||'/rm-fotos/'||original_path;
  insert into storage.objects(bucket_id,name,owner_id) values('rm-fotos',original_path,em_fixture.id(710+(office%4)+1)::text);
  update rm_private.receiving_drafts set payload=jsonb_set(payload,'{fotos}',
   case when office%2=0 then jsonb_build_array(ref) else jsonb_build_array(jsonb_build_object('uri',ref)) end) where id=draft;
  if exists(select 1 from rm_private.workshop_archive_sources s where s.reference=ref)
   or public.rm_mobile_workshop_media_v1(device,em_fixture.id(720+office),delegation,context,array[ref])->'files'<>'[]' then
   raise exception 'O rascunho permitiu um objeto com proprietário diferente do dispositivo original.';
  end if;
  update storage.objects set owner_id=device::text where bucket_id='rm-fotos' and name=original_path;
  insert into rm_private.workshop_archive_files(workshop_id,reference_sha256,content_sha256,mime_type,byte_size,object_id,object_path)
   select em_fixture.id((office%4)+1),hashed,repeat('d',64),'image/jpeg',12,gen_random_uuid(),
    'acervo-oficina/'||em_fixture.id((office%4)+1)::text||'/'||hashed||'.jpg'
   from (select encode(sha256(convert_to(ref,'UTF8')),'hex') hashed) candidate;
  if exists(select 1 from rm_private.workshop_legacy_draft_photos s where s.reference=ref) then
   raise exception 'Uma foto com registro anterior em outra oficina foi aceita.';
  end if;
  delete from rm_private.workshop_archive_files where workshop_id=em_fixture.id((office%4)+1)
   and reference_sha256=encode(sha256(convert_to(ref,'UTF8')),'hex');
  if (select count(*) from rm_private.workshop_archive_sources s where s.reference=ref and s.workshop_id=office_id and s.project_id is null)<>1
   or exists(select 1 from rm_private.workshop_archive_sources s where s.reference=ref and s.workshop_id<>office_id)
   or rm_private.workshop_legacy_media_readiness_v1('rm-fotos')->>'pending_drafts' is distinct from '1' then
   raise exception 'A foto identificada entrou na oficina errada ou perdeu a pendência antes da cópia.';
  end if;
  copy_path:='acervo-oficina/'||office_id::text||'/'||encode(sha256(convert_to(ref,'UTF8')),'hex')||'.jpg';
  insert into storage.objects(bucket_id,name,metadata,user_metadata) values('rm-documentos',copy_path,
   '{"size":12,"mimetype":"image/jpeg"}',jsonb_build_object('sha256',repeat('d',64)));
  verified_copy:=public.rm_confirm_workshop_archive_v1(office_id,ref,repeat('d',64),'image/jpeg',12);
  if verified_copy is distinct from copy_path or rm_private.workshop_legacy_media_readiness_v1('rm-fotos')->>'pending_drafts' is distinct from '0' then
   raise exception 'O acervo privado do rascunho não foi reconhecido.';
  end if;
  -- Move only the disposable fixture bucket across both visibility states.
  update storage.buckets set public=false where id='rm-fotos';
  output:=public.rm_mobile_workshop_media_v1(device,em_fixture.id(720+office),delegation,context,array[ref]);
  if output->'files'<>jsonb_build_array(jsonb_build_object('url',ref,'source','project_photo','archive_path',copy_path))
   or pg_temp.workshop_restore_native(office,array[ref])->'files' is distinct from '[]'::jsonb
   or public.rm_mobile_workshop_media_v1(device,em_fixture.id(720+office),delegation,jsonb_set(
    pg_temp.workshop_restore_native_context((office%4)+1,office),'{principals,1,subject}',to_jsonb(actor)),array[ref])->'files'<>'[]' then
   raise exception 'A restauração perdeu a foto do operador original ou concedeu acesso cruzado.';
  end if;
  update storage.buckets set public=true where id='rm-fotos';
 end loop;
end
$draft_photo_archive$;
do $photo_recovery$
declare
 origin_id uuid; device uuid; origin_path text; backup_path text;
 sha text:=repeat('a',64); version text:='original-1';
 before_count integer; before_sources bigint; result jsonb;
begin
 if not has_function_privilege('service_role','public.rm_confirm_workshop_legacy_photo_recovery_v1(uuid,text,text)','execute')
  or exists(select 1 from unnest(array['anon','authenticated']) a(role) where
   has_function_privilege(role,'public.rm_workshop_legacy_photo_recovery_target_v1(uuid)','execute')
   or has_function_privilege(role,'public.rm_confirm_workshop_legacy_photo_recovery_v1(uuid,text,text)','execute'))
  or has_table_privilege('service_role','rm_private.workshop_legacy_photo_recovery','select') then
  raise exception 'A recuperação técnica concedeu acesso direto ou a um cliente comum.';
 end if;
 before_sources:=(select count(*) from rm_private.workshop_archive_sources);
 before_count:=(rm_private.workshop_legacy_media_readiness_v1('rm-fotos')->>'objects_without_verified_preservation')::integer;
 for office in 1..4 loop
  origin_id:=em_fixture.id(1500+office);
  device:=em_fixture.id(710+office);
  origin_path:=device::text||'/legacy-unassigned.jpg';
  backup_path:='recuperacao-fotos-legadas/'||origin_id::text||'/'||sha||'.jpg';
  insert into storage.objects(id,bucket_id,name,owner_id,version,metadata) values(origin_id,'rm-fotos',origin_path,
   em_fixture.id(710+(office%4)+1)::text,version,'{"size":12,"mimetype":"image/jpeg"}');
  if public.rm_workshop_legacy_photo_recovery_target_v1(origin_id) is not null then
   raise exception 'O arquivo de proprietário diferente entrou em recuperação.';
  end if;
  update storage.objects set owner_id=device::text where id=origin_id;
  if public.rm_workshop_legacy_photo_recovery_target_v1(origin_id)->>'path' is distinct from origin_path then
   raise exception 'O arquivo sem referência e com proprietário comprovado ficou de fora.';
  end if;

  insert into storage.objects(bucket_id,name,version,metadata,user_metadata) values('rm-documentos',backup_path,'copy-1',
   '{"size":11,"mimetype":"image/jpeg"}',jsonb_build_object('sha256',sha));
  begin
   perform public.rm_confirm_workshop_legacy_photo_recovery_v1(origin_id,version,sha);
   raise exception 'A cópia de tamanho divergente foi confirmada.';
  exception when sqlstate 'PT409' then null;
  end;
  update storage.objects set metadata=jsonb_set(metadata,'{size}','12') where name=backup_path;
  if public.rm_confirm_workshop_legacy_photo_recovery_v1(origin_id,version,sha) is distinct from backup_path
   or public.rm_confirm_workshop_legacy_photo_recovery_v1(origin_id,version,sha) is distinct from backup_path then
   raise exception 'A retentativa não recuperou o comprovante da mesma versão.';
  end if;
  if not exists(select 1 from rm_private.workshop_legacy_photo_recovery r where r.source_id=origin_id
   and r.owner_auth_user_id=device and r.source_path=origin_path) then
   raise exception 'A custódia não preservou o proprietário original.';
  end if;
  result:=rm_private.workshop_legacy_media_readiness_v1('rm-fotos');
  if (result->>'preserved_without_workshop')::integer<>office
   or (result->>'objects_without_verified_preservation')::integer<>before_count
   or result->>'objects_without_confirmed_reference'<> (before_count+office)::text then
   raise exception 'A cópia de recuperação entrou na contagem de arquivos com vínculo operacional.';
  end if;

  perform set_config('request.jwt.claim.sub',device::text,true);
  set local role authenticated;
  if exists(select 1 from storage.objects where name=backup_path) then
   raise exception 'O signatário técnico foi contornado pelo cliente autenticado.';
  end if;
  reset role;
  update storage.objects set version='copy-2' where name=backup_path;
  if exists(select 1 from rm_private.workshop_legacy_photos_preserved o where o.id=origin_id) then
   raise exception 'A mudança de versão da cópia não reabriu a pendência.';
  end if;
  update storage.objects set version='copy-1' where name=backup_path;
  update storage.objects set version='original-2' where id=origin_id;
  if (rm_private.workshop_legacy_media_readiness_v1('rm-fotos')->>'objects_without_verified_preservation')::integer<>before_count+1 then
   raise exception 'A mudança de versão do original não reabriu a pendência.';
  end if;
  update storage.objects set version='original-1' where id=origin_id;
  update rm_private.receiving_drafts set payload=payload||jsonb_build_object('test_relink',origin_path) where id=em_fixture.id(1350+office);
  if public.rm_workshop_legacy_photo_recovery_target_v1(origin_id) is not null
   or (rm_private.workshop_legacy_media_readiness_v1('rm-fotos')->>'objects_without_verified_preservation')::integer<>before_count+1 then
   raise exception 'A custódia encobriu uma referência operacional nova.';
  end if;
  update rm_private.receiving_drafts set payload=payload-'test_relink' where id=em_fixture.id(1350+office);
 end loop;
 if (select count(*) from rm_private.workshop_archive_sources)<>before_sources then
  raise exception 'Um arquivo de recuperação entrou no acervo de oficina.';
 end if;
end
$photo_recovery$;
savepoint photo_cutover_fixture;
do $photo_cutover$
declare
 bma_device uuid:=em_fixture.id(711);
 bma_session uuid:=em_fixture.id(721);
 device uuid;
 path text;
 reference text;
 copy_path text;
 archive_sha text:=repeat('b',64);
 previous_object_count bigint;
 output jsonb;
 original_args jsonb;
 saved jsonb;
 replay jsonb;
 submission uuid:=gen_random_uuid();
 signature_path text:=bma_device::text||'/'||gen_random_uuid()||'.png';
 signature_reference text:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-assinaturas/'||signature_path;
 photo_args jsonb;
begin
 if has_function_privilege('authenticated','rm_private.prepare_workshop_legacy_photo_cutover_v1()','execute')
  or has_function_privilege('service_role','rm_private.prepare_workshop_legacy_photo_cutover_v1()','execute')
  or has_function_privilege('anon','rm_private.workshop_legacy_photo_storage_allowed_v1()','execute') then
  raise exception 'A alteração de visibilidade ficou acessível pelo cliente.';
 end if;
 begin
  perform rm_private.prepare_workshop_legacy_photo_cutover_v1();
  raise exception 'A preparação não exigiu o recorte dos protocolos de gravação.';
 exception when sqlstate 'PT409' then null;end;
 perform public.rm_observe_mobile_workshop_android_v1(bma_device,bma_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(1,1),'1.2.24',27);
 perform rm_private.activate_workshop_legacy_bma_catalog_v1(bma_device,bma_session);
 perform rm_private.activate_workshop_legacy_bma_operations_v1();
 perform rm_private.activate_workshop_legacy_bma_people_v1();
 perform rm_private.activate_workshop_legacy_operator_reads_v1();
 perform rm_private.activate_workshop_legacy_mobile_writes_v1();
 begin
  perform rm_private.prepare_workshop_legacy_photo_cutover_v1();
  raise exception 'O corte foi preparado sem cópia verificada de todos os objetos.';
 exception when sqlstate 'PT409' then null;end;
 for office in 1..4 loop
  reference:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||office||'/equipamento.png';
  update public.rm_fotos set foto_url=reference where id=em_fixture.id(600+office);
  copy_path:='acervo-oficina/'||em_fixture.id(office)::text||'/'||encode(sha256(convert_to(reference,'UTF8')),'hex')||'.png';
  insert into storage.objects(bucket_id,name,metadata,user_metadata)
   values('rm-documentos',copy_path,'{"size":12,"mimetype":"image/png"}',jsonb_build_object('sha256',archive_sha));
  if public.rm_confirm_workshop_archive_v1(em_fixture.id(office),reference,archive_sha,'image/png',12) is distinct from copy_path then
   raise exception 'A cópia de projeto permaneceu pendente.';
  end if;
 end loop;
 select count(*) into previous_object_count from storage.objects where bucket_id='rm-fotos';
 perform rm_private.prepare_workshop_legacy_photo_cutover_v1();
 perform rm_private.prepare_workshop_legacy_photo_cutover_v1();
 perform set_config('request.jwt.claim.sub',bma_device::text,true);
 path:=bma_device::text||'/queued-photo.jpg';
 set local role authenticated;
 begin
  insert into storage.objects(bucket_id,name) values('rm-fotos',path);
  raise exception 'Uma foto nova entrou no bucket entre a auditoria e a troca de visibilidade.';
 exception when insufficient_privilege then null;end;
 reset role;

 -- Emulate only the isolated Storage API change. The original objects and
 -- the workshop archive remain at their own paths.
 update storage.buckets set public=false where id='rm-fotos';
 if (select count(*) from storage.objects where bucket_id='rm-fotos')<>previous_object_count then
  raise exception 'A mudança de visibilidade alterou o acervo original.';
 end if;
 set local role authenticated;
 insert into storage.objects(bucket_id,name) values('rm-fotos',path);
 update storage.objects set user_metadata='{"legacy_retry":true}' where bucket_id='rm-fotos' and name=path;
 if not found then raise exception 'O dispositivo aprovado perdeu a retentativa do próprio arquivo privado.';end if;
 reset role;

 for office in 1..4 loop
  device:=em_fixture.id(710+office);
  path:=device::text||'/legacy-draft.jpg';
  perform set_config('request.jwt.claim.sub',device::text,true);
  set local role authenticated;
  if exists(select 1 from storage.objects where bucket_id='rm-fotos' and name=path) is distinct from (office=1) then
   raise exception 'A leitura direta de fotos manteve acesso para outro dispositivo.';
  end if;
  if office<>1 then
   begin
    insert into storage.objects(bucket_id,name) values('rm-fotos',device::text||'/denied-photo.jpg');
    raise exception 'Uma oficina externa gravou no bucket privado legado.';
   exception when insufficient_privilege then null;end;
  end if;
  reset role;
  reference:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||office||'/equipamento.png';
  output:=pg_temp.workshop_restore_native(office,array[reference]);
  if output->'files'->0->>'url' is distinct from reference
   or coalesce(output->'files'->0->>'archive_path','') not like 'acervo-oficina/'||em_fixture.id(office)::text||'/%'
   or pg_temp.workshop_restore_native((office%4)+1,array[reference])->'files' is distinct from '[]'::jsonb then
   raise exception 'O Android perdeu a referência antiga ou a mostrou a outra oficina.';
  end if;
  -- The portal cutover fixture revoked the first two Microsoft identities.
  if office in(3,4) then
   output:=pg_temp.workshop_restore_read(office,'media_reference',jsonb_build_object('id',em_fixture.id(600+office),'source','project_photo'));
   if output->>'file' is distinct from reference or coalesce(output->>'archive_path','') not like 'acervo-oficina/'||em_fixture.id(office)::text||'/%'
    or pg_temp.workshop_restore_read(7-office,'media_reference',jsonb_build_object('id',em_fixture.id(600+office),'source','project_photo')) is not null then
    raise exception 'O portal perdeu a referência antiga ou a mostrou a outra oficina.';
   end if;
  end if;
 end loop;
 perform set_config('request.jwt.claim.sub',bma_device::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',bma_session,'aal','aal1')::text,true);
 path:=bma_device::text||'/'||gen_random_uuid()||'.jpg';
 reference:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||path;
 update storage.buckets set public=false where id='rm-assinaturas';
 original_args:=jsonb_build_object('p_projeto_id',em_fixture.id(101),'p_celula_id',em_fixture.id(201),
  'p_celula_projeto_id',em_fixture.id(301),'p_foto_url',reference,'p_titulo','Foto complementar','p_categoria_foto','complementar');
 set local role authenticated;
 insert into storage.objects(bucket_id,name,owner_id,version,metadata) values
  ('rm-fotos',path,bma_device::text,'legacy-jpeg','{"size":24,"mimetype":"image/jpeg"}'),
  ('rm-assinaturas',signature_path,bma_device::text,'legacy-png','{"size":24,"mimetype":"image/png"}');
 saved:=public.rm_mobile_mutate_v1(submission,'rm_record_cell_photo_v1',original_args,repeat('a',64));
 replay:=public.rm_mobile_mutate_v1(submission,'rm_record_cell_photo_v1',original_args,repeat('a',64));
 reset role;
 photo_args:=jsonb_build_object('id',saved->>'foto_id','source','project_photo');
 output:=rm_private.workshop_media_reference_v1(photo_args,em_fixture.id(1));
 if output->>'private_legacy_image_path' is distinct from path or output?'archive_path' or replay-'idempotent_replay' is distinct from saved-'idempotent_replay'
  or pg_temp.workshop_restore_native(1,array[reference])->'files'->0->>'url' is distinct from reference then
  raise exception 'O reenvio Android perdeu a foto privada no projeto ou na resposta ao portal.';
 end if;
 update public.rm_respostas set assinatura_url=signature_reference where id=em_fixture.id(1461);
 if rm_private.workshop_media_reference_v1(jsonb_build_object('id',em_fixture.id(1461),'source','answer_signature'),em_fixture.id(1))
  ->>'private_legacy_image_path' is distinct from signature_path then
  raise exception 'A assinatura privada da própria oficina não foi resolvida.';
 end if;
 for office in 2..4 loop
  if rm_private.workshop_media_reference_v1(photo_args,em_fixture.id(office)) is not null
   or pg_temp.workshop_restore_native(office,array[reference])->'files' is distinct from '[]'::jsonb then
   raise exception 'A foto privada da BMA apareceu em outra oficina.';
  end if;
 end loop;
 update public.rm_fotos set foto_url=reference where id=em_fixture.id(602);
 if rm_private.workshop_media_reference_v1(jsonb_build_object('id',em_fixture.id(602),'source','project_photo'),em_fixture.id(2))
  ->'file' is distinct from 'null'::jsonb or pg_temp.workshop_restore_native(2,array[reference])->'files' is distinct from '[]'::jsonb then
  raise exception 'Uma referência copiada conferiu leitura em outra oficina.';
 end if;
 update storage.objects set owner_id=em_fixture.id(712)::text where bucket_id='rm-fotos' and name=path;
 if rm_private.workshop_media_reference_v1(photo_args,em_fixture.id(1))?'private_legacy_image_path' then
  raise exception 'O portal aprovou um original com proprietário divergente.';
 end if;
 update storage.objects set owner_id=bma_device::text,metadata='{"size":24,"mimetype":"text/html"}' where bucket_id='rm-fotos' and name=path;
 if rm_private.workshop_media_reference_v1(photo_args,em_fixture.id(1))?'private_legacy_image_path' then
  raise exception 'O portal aprovou um arquivo com tipo divergente.';
 end if;
 update storage.objects set metadata='{"size":24,"mimetype":"image/jpeg"}' where bucket_id='rm-fotos' and name=path;
 perform public.rm_observe_mobile_workshop_android_v1(bma_device,bma_session,repeat('a',64),
  pg_temp.workshop_restore_native_context(2,1),'1.2.24',27);
 set local role authenticated;
 if exists(select 1 from storage.objects where bucket_id='rm-fotos') then
  raise exception 'O dispositivo transferido reteve acesso direto ao bucket antigo.';
 end if;
 reset role;
 if rm_private.workshop_media_reference_v1(photo_args,em_fixture.id(1))->>'private_legacy_image_path' is distinct from path then
  raise exception 'A transferência removeu o acesso da BMA à foto gravada antes da revogação.';
 end if;
 update storage.objects set updated_at=clock_timestamp()+interval '1 minute' where bucket_id='rm-fotos' and name=path;
 if rm_private.workshop_media_reference_v1(photo_args,em_fixture.id(1))?'private_legacy_image_path' then
  raise exception 'A versão do arquivo posterior à revogação recebeu acesso na BMA.';
 end if;
end
$photo_cutover$;
select 'PASS: legacy photo cutover preserves archived references, denies cross-workshop storage and supports approved private retries' result;
select 'PASS: legacy Android photo replay and private original reads preserve the same project and deny three foreign workshops' result;
rollback to savepoint photo_cutover_fixture;
release savepoint photo_cutover_fixture;
do $android_adoption$
declare
 device uuid; session_id uuid; delegation text; context jsonb; first_seen timestamptz;
begin
 if not has_function_privilege('service_role','public.rm_observe_mobile_workshop_android_v1(uuid,uuid,text,jsonb,text,integer)','execute')
  or exists(select 1 from unnest(array['anon','authenticated']) a(role) where
   has_function_privilege(role,'public.rm_observe_mobile_workshop_android_v1(uuid,uuid,text,jsonb,text,integer)','execute'))
  or has_table_privilege('service_role','rm_private.workshop_android_observations','select') then
  raise exception 'O registro de versões concedeu acesso direto ou ao aplicativo.';
 end if;
 for office in 1..4 loop
  device:=em_fixture.id(710+office); session_id:=em_fixture.id(720+office); delegation:=repeat(chr(96+office),64);
  context:=pg_temp.workshop_restore_native_context(office,office);
  begin
   perform public.rm_observe_mobile_workshop_android_v1(device,em_fixture.id(720+(office%4)+1),delegation,context,'1.2.24',27);
   raise exception 'Uma sessão estrangeira registrou versão.';
  exception when sqlstate '28000' then null;
  end;
  begin
   perform public.rm_observe_mobile_workshop_android_v1(device,session_id,delegation,jsonb_set(context,'{workshop,active}','false'),'1.2.24',27);
   raise exception 'Uma oficina suspensa registrou versão.';
  exception when sqlstate '42501' then null;
  end;
  perform public.rm_observe_mobile_workshop_android_v1(device,session_id,delegation,context,'1.2.24',27);
  select seen.observed_at into strict first_seen from rm_private.workshop_android_observations seen
   where seen.session_id=em_fixture.id(720+office) and seen.workshop_id=em_fixture.id(office)
    and seen.app_version='1.2.24' and seen.build_code=27;
  perform public.rm_observe_mobile_workshop_android_v1(device,session_id,delegation,context,'1.2.24',27);
  if not exists(select 1 from rm_private.workshop_android_observations seen where seen.session_id=em_fixture.id(720+office) and seen.observed_at=first_seen) then
   raise exception 'O mesmo aplicativo gravou uma observação repetida na mesma sessão.';
  end if;
  perform public.rm_observe_mobile_workshop_android_v1(device,session_id,delegation,context,'1.2.25',28);
  if not exists(select 1 from rm_private.workshop_android_observations seen where seen.session_id=em_fixture.id(720+office)
    and seen.workshop_id=em_fixture.id(office) and seen.observed_at>=first_seen and seen.build_code=28) then
   raise exception 'A sessão não registrou a troca de versão do aplicativo.';
  end if;
 end loop;
 if (select count(*) from rm_private.workshop_android_observations)<>4 then
  raise exception 'O indicador misturou as sessões de oficinas distintas.';
 end if;
end
$android_adoption$;
do $retired_direct_tables$
declare
 office integer;
 device uuid;
 local_cell uuid;
 draft_id uuid;
 draft_count bigint;
begin
 if exists(select 1 from unnest(array['anon','authenticated']) r(role)
  cross join unnest(array['public.rm_respostas_temp','public.rm_devices','public.rm_web_stage_decisions',
    'public.rm_project_document_locations','public.rm_equipes','public.rm_sync_outbox']) t(name)
  where has_table_privilege(role,name,'select,insert,update,delete,truncate,references,trigger')
   or has_any_column_privilege(role,name,'select,insert,update,references')) then
  raise exception 'Uma tabela retirada continua acessível diretamente por um cliente.';
 end if;
 if not has_table_privilege('service_role','public.rm_respostas_temp','select')
  or not has_table_privilege('service_role','public.rm_sync_outbox','select')
  or not has_table_privilege('authenticated','public.rm_celulas','select')
  or not has_table_privilege('authenticated','public.rm_fotos','select') then
  raise exception 'A retirada alcançou uma interface ainda suportada.';
 end if;
 select count(*) into draft_count from public.rm_respostas_temp;
 for office in 1..4 loop
  device:=em_fixture.id(710+office);
  local_cell:=em_fixture.id(200+office);
  draft_id:=em_fixture.id(1520+office);
  perform set_config('request.jwt.claim.sub',device::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',em_fixture.id(720+office),'aal','aal1')::text,true);
  set local role authenticated;
  perform id from public.rm_celulas where id=local_cell;
  if not found then raise exception 'A consulta de células ainda suportada deixou de retornar dados.'; end if;
  begin
   perform id from public.rm_respostas_temp;
   raise exception 'Um cliente conseguiu listar os rascunhos antigos.';
  exception when insufficient_privilege then null;
  end;
  begin
   insert into public.rm_respostas_temp(id) values(draft_id);
   raise exception 'Um cliente conseguiu escrever pela tabela de rascunhos antigos.';
  exception when insufficient_privilege then null;
  end;
  reset role;
 end loop;
 if (select count(*) from public.rm_respostas_temp)<>draft_count then
  raise exception 'A retirada das permissões alterou os rascunhos existentes.';
 end if;
end
$retired_direct_tables$;
rollback;

begin;
do $online_forms_by_workshop$
declare
 office integer;
 other integer;
 context jsonb;
 device uuid;
 device_session uuid;
 token text;
 model uuid;
 project uuid;
 cell uuid;
 other_model uuid;
 other_project uuid;
 other_cell uuid;
 question uuid;
 protocol uuid;
 version text;
 answers jsonb;
 saved jsonb;
 replay jsonb;
 record_id uuid;
 filters constant jsonb:='{"page":1,"project_details":true,"q":"QA-MESMA-OS","status":"em_an_lise"}';
begin
 for office in 1..4 loop
  context:=pg_temp.workshop_restore_native_context(office,office);
  device:=em_fixture.id(710+office);
  device_session:=em_fixture.id(720+office);
  token:=repeat(chr(96+office),64);
  model:=em_fixture.id(400+office);
  project:=em_fixture.id(100+office);
  cell:=em_fixture.id(200+office);
  question:=em_fixture.id(2900+office);
  protocol:=em_fixture.id(2910+office);
  update public.rm_celulas_projeto set forms_ids=array[model],status='em_dia' where id=em_fixture.id(300+office);
  insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) values(question,model,'Conferência local','texto_curto',true);
  answers:=jsonb_build_object(question::text,'Conferido pela própria oficina');
  set local role service_role;
  version:=public.rm_online_operation_form_entry_v1(device,device_session,token,context,cell,project,model)->'edition'->>'version';
  saved:=public.rm_online_operation_submit_form_v1(device,device_session,token,context,cell,project,model,protocol,version,answers);
  replay:=public.rm_online_operation_submit_form_v1(device,device_session,token,context,cell,project,model,protocol,version,answers);
  reset role;
  for other in 1..4 loop
   if other=office then continue;end if;
   other_cell:=em_fixture.id(200+other);
   other_project:=em_fixture.id(100+other);
   other_model:=em_fixture.id(400+other);
   begin
    set local role service_role;
    perform public.rm_online_operation_submit_form_v1(device,device_session,token,context,other_cell,other_project,other_model,protocol,version,answers);
    raise exception 'Formulário de outra oficina aceitou protocolo.';
   exception when insufficient_privilege then null;
   end;
  end loop;
  record_id:=(saved->>'registro_formulario_id')::uuid;
  if replay is distinct from saved||'{"idempotent_replay":true}'::jsonb
   or (select count(*) from public.rm_registros_formulario where client_submission_id=protocol)<>1
   or not exists(select 1 from public.rm_respostas where registro_formulario_id=record_id and questao_id=question)
   or not (rm_private.workshop_form_record_read_v1('form_record_list',filters,em_fixture.id(office))->'rows')
    @> jsonb_build_array(jsonb_build_object('id',record_id)) then
   raise exception 'A revisão da oficina não recebeu o único envio operacional.';
  end if;
  for other in 1..4 loop
   if other=office then continue;end if;
   if (rm_private.workshop_form_record_read_v1('form_record_list',filters,em_fixture.id(other))->'rows')
    @> jsonb_build_array(jsonb_build_object('id',record_id)) then
    raise exception 'A lista de revisão devolveu o formulário de outra oficina.';
   end if;
  end loop;
 end loop;
end
$online_forms_by_workshop$;
rollback;
select 'PASS: each of four workshops files and reviews one form by its own online protocol, while 12 crossed writes and 12 crossed review reads are denied' result;

begin;
do $offline_confirmations$
declare
 office int; other int; attempt int; action text; payload jsonb; protocol uuid; answer jsonb;
 device uuid; device_session uuid; actor uuid; token text; project uuid; cell uuid; allocation uuid;
 model uuid; question uuid; registration uuid; stage uuid; destination uuid;
 ack jsonb; original_ack jsonb; expected jsonb; lookup jsonb; displayed jsonb;
begin
 if exists(select 1 from unnest(array['anon','authenticated','service_role']) client_role(name) where
  has_function_privilege(client_role.name,'rm_private.workshop_android_protocol_v1(jsonb,uuid)','execute')
  or has_table_privilege(client_role.name,'rm_private.workshop_android_receipt_confirmations','select,insert,update')) then
  raise exception 'A conferência ficou acessível fora do leitor autorizado.';
 end if;
 for office in 1..4 loop
  device:=em_fixture.id(710+office); device_session:=em_fixture.id(720+office); actor:=em_fixture.id(740+office);
  token:=repeat(chr(96+office),64); project:=em_fixture.id(100+office); cell:=em_fixture.id(200+office);
  allocation:=em_fixture.id(300+office); model:=em_fixture.id(400+office); question:=em_fixture.id(2920+office);
  stage:=em_fixture.id(2930+office); destination:=em_fixture.id(2940+office);
  insert into public.rm_celulas(id,nome) values(destination,'Destino local '||office);
  insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(destination,em_fixture.id(office));
  insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
   values(em_fixture.id(2950+office),project,destination,'pendente',false);
  insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,celula_projeto_id,status_cel_proj,aprovador_id)
   values(stage,project,cell,destination,allocation,'em_dia',actor);
  update public.rm_celulas_projeto set forms_ids=array[model],status='em_dia' where id=allocation;
  insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) values(question,model,'Conferência local','texto_curto',true);
  perform set_config('request.jwt.claim.sub',device::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',device_session,'aal','aal1')::text,true);

  foreach action in array array['rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_record_cell_photo_v1',
   'rm_add_cell_comment_v1','rm_update_cell_status_v1','rm_record_execution_event_v1','rm_transition_stage_approval_v1'] loop
   protocol:=gen_random_uuid();
   answer:=jsonb_build_object('questao_id',question,'resposta','Conferência da fila');
   payload:=case action
    when 'rm_submit_form_inspection_v1' then jsonb_build_object('p_projeto_id',project,'p_celula_id',cell,
     'p_form_id',model,'p_respostas',jsonb_build_array(answer))
    when 'rm_submit_form_revision_v1' then jsonb_build_object('p_registro_formulario_id',registration,
     'p_respostas_corrigidas',jsonb_build_array(answer||'{"resposta":"Corrigido na fila"}'))
    when 'rm_record_cell_photo_v1' then jsonb_build_object('p_projeto_id',project,'p_celula_id',cell,'p_celula_projeto_id',allocation,
     'p_foto_url','https://fixture.invalid/queued.jpg','p_titulo','Conferência da fila','p_categoria_foto','complementar')
    when 'rm_add_cell_comment_v1' then jsonb_build_object('p_celula_projeto_id',allocation,'p_comentario','Comentário da fila')
    when 'rm_update_cell_status_v1' then jsonb_build_object('p_celula_projeto_id',allocation,'p_status','em_dia')
    when 'rm_record_execution_event_v1' then jsonb_build_object('p_session_id',em_fixture.id(970+office),'p_allocation_id',allocation,
     'p_operador_id',actor,'p_previous_event_id',em_fixture.id(980+office),'p_kind','pause','p_occurred_at',clock_timestamp(),
     'p_pause_reason','material','p_note',null,'p_effort_minutes',null)
    when 'rm_transition_stage_approval_v1' then jsonb_build_object('p_aprovacao_etapa_id',stage,'p_acao','liberar') end;
   expected:=jsonb_build_object('protocolo',protocol,'operacao',action,'dispositivo_id',device,'operador_id',actor,
    'oficina_id',em_fixture.id(office),'projeto_id',project);
   lookup:=jsonb_build_object('protocol',protocol,'forms',true,'photos',true,'approvals',true,'planning',true);
   for other in 1..4 loop
    if other=office then continue;end if;
    begin
     perform public.rm_authorize_mobile_workshop_mutation_v1(device,device_session,token,
      pg_temp.workshop_restore_native_context(other,office),protocol,action,payload);
     raise exception 'A fila obteve autorização cruzada para %.',action;
    exception when insufficient_privilege then null;end;
   end loop;
   for attempt in 1..2 loop
    perform public.rm_authorize_mobile_workshop_mutation_v1(device,device_session,token,
     pg_temp.workshop_restore_native_context(office,office),protocol,action,payload);
    set local role authenticated;
    ack:=public.rm_mobile_workshop_mutate_v1(protocol,action,payload,token);
    reset role;
    if ack->'confirmacao' is distinct from expected or (attempt=2 and ack is distinct from original_ack||'{"idempotent_replay":true}'::jsonb) then
     raise exception 'Confirmação divergente da fila para % na oficina %.',action,office;
    end if;
    displayed:=rm_private.workshop_android_protocol_v1(lookup,em_fixture.id(office));
    if not coalesce(displayed @> jsonb_build_object('phase','confirmed','project_id',project,'operation',action),false)
     or (displayed->>'last_retry_at' is not null) is distinct from (attempt=2) then
     raise exception 'A consulta não distinguiu confirmação e reenvio de %.',action;
    end if;
    original_ack:=ack;
   end loop;
   for other in 1..4 loop
    if other<>office and rm_private.workshop_android_protocol_v1(lookup,em_fixture.id(other)) is not null then
     raise exception 'A consulta do protocolo atravessou a oficina.';
    end if;
   end loop;
   if action<>'rm_add_cell_comment_v1' and rm_private.workshop_android_protocol_v1(
    lookup||'{"forms":false,"photos":false,"approvals":false,"planning":false}',em_fixture.id(office)) is not null then
    raise exception 'A consulta exibiu uma operação de módulo sem permissão.';
   end if;
   if office=3 and action='rm_submit_form_inspection_v1' then
    if pg_temp.workshop_restore_read(3,'android_protocol',lookup) is distinct from displayed
     or pg_temp.workshop_restore_read(4,'android_protocol',lookup) is not null then
     raise exception 'O leitor do portal perdeu o recorte do protocolo.';
    end if;
    perform set_config('request.jwt.claim.sub',device::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('session_id',device_session,'aal','aal1')::text,true);
   end if;
   if not exists(select 1 from rm_private.mobile_mutation_receipts r where r.client_submission_id=protocol
    and r.auth_user_id=device and r.operator_id=actor and r.rpc_name=action
    and r.result-'idempotent_replay'=ack-'idempotent_replay'-'confirmacao') then
    raise exception 'A fila perdeu o recibo original de %.',action;
   end if;
   if action='rm_submit_form_inspection_v1' then
    registration:=(ack->>'registro_formulario_id')::uuid;
    if displayed->>'form_record_id' is distinct from registration::text then raise exception 'A consulta perdeu o formulário original.';end if;
    update public.rm_registros_formulario set status='direcionado' where id=registration;
    update public.rm_respostas set revisar=true where registro_formulario_id=registration and questao_id=question;
   end if;
  end loop;
 end loop;
end
$offline_confirmations$;
rollback;
select 'PASS: seven offline operations confirm and replay the original receipt in each of four workshops' result;

select 'PASS: scoped legacy operational reads retain original receiving proofs, hide foreign and unverified rows, and preserve mobile gateways' result;
select 'PASS: legacy direct catalogs keep BMA data on its verified tablet, deny other tablets and revoke after a verified transfer' result;
select 'PASS: historical form options resolve through the authorized question, replay after the native cursor and reject mismatched forms in four workshops' result;
select 'PASS: retired direct access to legacy tables preserves drafts, supported Android queries and service grants in four workshops' result;
select 'PASS: Android version observations follow the authorized session and office, deny suspended offices and update without duplicates in four workshops' result;
select 'PASS: orphan legacy photo custody preserves owner and versions, remains private and excludes operational references in four workshops' result;
select 'PASS: legacy draft photos reach the verified archive only with original device, owner and office in four workshops' result;
select 'PASS: scoped equipment types and direct portal read cutover in four workshops; native reads preserved' result;
select 'PASS: four offices, Gantt, capacity, availability, queue, load, execution, media; 156 denied cross-office reads, 24 crossed writes, 8 denied reads after revocation or unavailable authority' result;
select 'PASS: engineering and photo titles in four offices; 48 denied cross-office reads, 16 crossed writes' result;
select 'PASS: current team in four offices; 12 denied cross-office searches, 4 rejected member substitutions' result;
select 'PASS: assignment selectors and writes in four offices; 36 denied cross-office reads and 20 denied foreign people assignments' result;
select 'PASS: four private draft attachments recover under their original identity; 12 denied cross-office draft media reads' result;
select 'PASS: Gantt cutover across four offices from intake through calendars, dependencies and baselines; deferred roots and legacy access checked' result;
select 'PASS: workshop output cutover retains scoped workbook, twin, QR and invoice in four offices' result;
select 'PASS: restored pristine receiving protocols retain their original revisions, payloads and office in four workshops' result;
select 'PASS: exact legacy receiving receipts become visible only in the verified workshop inbox in four offices' result;
select 'PASS: workshop receiving creation evidence distinguishes new openings from legacy replay in four workshops' result;
select 'PASS: restored archive copies authorize photos, form answers and invoices only in the original workshop' result;
select 'PASS: archived Word attachments use the same private read and reject a foreign workshop' result;
select 'PASS: review cutover preserves legacy actions and rejects foreign decisions in four workshops before the general root cutover' result;
select 'PASS: receiving and project reads are isolated with the overview and twin in four workshops after retiring legacy receiving reads' result;
select 'PASS: project and cell edits, equipment and deletion scopes hold in four workshops without closing mobile intake' result;
select 'PASS: project dossier reads and writes, versioned private files and exact replay isolated in four workshops' result;
select 'PASS: route cell form choices and versioned writes isolated in four workshops' result;
select 'PASS: operational photo titles, lifecycle and original evidence isolated in four workshops' result;
select 'PASS: stage proof stays private and only the current workshop roster contributes to approvals in four workshops' result;
select 'PASS: reviewer choices, versions and evidence isolated in four workshops' result;
select 'PASS: scoped project and form detail snapshots, gallery and related roles in four workshops' result;
select 'PASS: legacy owner storage access, verified copies and signature bucket cutover in four workshops' result;

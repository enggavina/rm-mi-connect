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

create function pg_temp.online_form(n int, cell int, project int, form int)
returns jsonb language plpgsql as $$
declare reply jsonb;
begin
  set local role service_role;
  reply := public.rm_online_operation_form_read_v1(pg_temp.online_id(10+n),pg_temp.online_id(20+n),repeat(n::text,64),
    pg_temp.online_context(n),pg_temp.online_id(cell),pg_temp.online_id(project),pg_temp.online_id(form));
  reset role;
  return reply;
exception when others then reset role; raise;
end;
$$;

create function pg_temp.online_submit(n int, cell int, project int, form int, protocol int, version text, answers jsonb)
returns jsonb language plpgsql as $$
declare reply jsonb;
begin
  set local role service_role;
  reply := public.rm_online_operation_submit_form_v1(pg_temp.online_id(10+n),pg_temp.online_id(20+n),repeat(n::text,64),
    pg_temp.online_context(n),pg_temp.online_id(cell),pg_temp.online_id(project),pg_temp.online_id(form),
    pg_temp.online_id(protocol),version,answers);
  reset role;
  return reply;
exception when others then reset role; raise;
end;
$$;

create function pg_temp.online_write_error(n int, cell int, project int, form int, protocol int, version text, answers jsonb, error_code text)
returns void language plpgsql as $$
begin
  begin
    perform pg_temp.online_submit(n,cell,project,form,protocol,version,answers);
  exception when others then
    if sqlstate=error_code then return; end if;
    raise;
  end;
  raise exception 'FAIL: write unexpectedly accepted, expected %',error_code;
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
  (pg_temp.online_id(403),'Formulário inativo',false),(pg_temp.online_id(404),'Formulário local sem vínculo',true),
  (pg_temp.online_id(405),'Formulário BRJ',true),(pg_temp.online_id(406),'Formulário BBH',true);
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values
  ('form_model',pg_temp.online_id(401),pg_temp.online_id(1)),('form_model',pg_temp.online_id(403),pg_temp.online_id(1)),
  ('form_model',pg_temp.online_id(404),pg_temp.online_id(1)),('form_model',pg_temp.online_id(405),pg_temp.online_id(2)),
  ('form_model',pg_temp.online_id(406),pg_temp.online_id(3));
insert into public.rm_questoes(id,form_id,indice,enunciado,subtitulo,tipo,obrigatorio) values
  (pg_temp.online_id(801),pg_temp.online_id(401),3,'Condição visual','Marque uma opção.','escolha__nica',true),
  (pg_temp.online_id(802),pg_temp.online_id(401),2,'Inspeção',null,'subt_tulo',false),
  (pg_temp.online_id(803),pg_temp.online_id(405),1,'Local BRJ',null,'texto_curto',false),
  (pg_temp.online_id(804),pg_temp.online_id(406),1,'Local BBH',null,'texto_curto',false);
insert into public.rm_itens_questoes(id,form_id,questao_id,indice,descricao) values
  (pg_temp.online_id(811),null,pg_temp.online_id(801),2,'Opção legada'),
  (pg_temp.online_id(812),pg_temp.online_id(401),pg_temp.online_id(801),1,'Conforme'),
  (pg_temp.online_id(813),pg_temp.online_id(405),pg_temp.online_id(801),3,'Opção de outra oficina');

insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade,retirada,posicao,status,forms_ids)
  select pg_temp.online_id(500+n),pg_temp.online_id(200+n),pg_temp.online_id(case when n in (2,3) then 100+n else 101 end),
    n not in(7,8),n=8,n,case when n=9 then 'retornado' else 'em_dia' end::public.rm_status_cel_proj_enum,
    case when n=1 then array[pg_temp.online_id(402),pg_temp.online_id(401),pg_temp.online_id(403),pg_temp.online_id(405)]
      when n in (2,3) then array[pg_temp.online_id(403+n)]
      when n=7 then array[pg_temp.online_id(401)] else '{}' end
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

  result := pg_temp.online_form(1,101,201,401);
  perform pg_temp.online_check(result->>'kind'='form' and result->'form'->>'id'=pg_temp.online_id(401)::text
    and result->'questions'->0->>'tipo'='subt_tulo' and result->'questions'->1->>'enunciado'='Condição visual'
    and result->'questions'->1->>'obrigatorio'='true' and jsonb_array_length(result->'questions')=2
    and jsonb_array_length(result->'questions'->1->'items')=2
    and result->'questions'->1->'items'->0->>'descricao'='Conforme'
    and result->'questions'->1->'items'->1->>'descricao'='Opção legada'
    and strpos(result::text,'private.invalid')=0,'authorized form projects ordered questions, safe options and no private URLs');
  perform pg_temp.online_check(pg_temp.online_form(2,102,202,405)->'questions'->0->>'enunciado'='Local BRJ'
    and pg_temp.online_form(3,103,203,406)->'questions'->0->>'enunciado'='Local BBH'
    and pg_temp.online_form(1,102,202,405) is null and pg_temp.online_form(3,102,202,405) is null,
    'form reads use current workshop for BRJ and BBH even when a cross-office cell grant exists');
  perform pg_temp.online_check(pg_temp.online_form(1,101,201,402) is null and pg_temp.online_form(1,101,201,403) is null
    and pg_temp.online_form(1,101,201,404) is null and pg_temp.online_form(1,101,201,405) is null
    and pg_temp.online_form(1,101,207,401) is null and pg_temp.online_form(1,101,205,401) is null
    and pg_temp.online_form(1,null,201,401) is null,
    'form requires active owned model linked to an active visible allocation in the exact cell and project');

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

insert into public.rm_questoes(id,form_id,indice,enunciado,tipo,subtipo,obrigatorio) values
  (pg_temp.online_id(820),pg_temp.online_id(401),4,'Observação','texto_longo',null,true),
  (pg_temp.online_id(821),pg_temp.online_id(401),4.5,'Potência','numero',null,true),
  (pg_temp.online_id(822),pg_temp.online_id(401),5,'Chegada','data',null,true),
  (pg_temp.online_id(823),pg_temp.online_id(401),6,'Período','data','intervalo_de_datas',true),
  (pg_temp.online_id(824),pg_temp.online_id(401),7,'Opcionais','lista_multi_sele__o',null,false),
  (pg_temp.online_id(825),pg_temp.online_id(401),8,'Foto de contexto','foto',null,false);
insert into public.rm_itens_questoes(id,form_id,questao_id,indice,descricao) values
  (pg_temp.online_id(826),pg_temp.online_id(401),pg_temp.online_id(824),1,'Mecânica'),
  (pg_temp.online_id(827),pg_temp.online_id(401),pg_temp.online_id(824),2,'Elétrica');
insert into public.rm_respostas_temp(id,projeto_id,form_id,questao_id,operador_user_id,resposta)
  values(pg_temp.online_id(828),pg_temp.online_id(201),pg_temp.online_id(401),pg_temp.online_id(820),pg_temp.online_id(41),'Rascunho anterior');

do $web_form$
declare
  selected jsonb; version text; retry jsonb; reply jsonb; payload jsonb; inspection_id uuid; current_version text;
begin
  selected := public.rm_online_operation_form_entry_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),pg_temp.online_context(1),
    pg_temp.online_id(101),pg_temp.online_id(201),pg_temp.online_id(401));
  version := selected->'edition'->>'version';
  perform pg_temp.online_check(version ~ '^[0-9a-f]{64}$' and selected->'edition'->'dateIntervals'=jsonb_build_array(pg_temp.online_id(823)),
    'editable BMA form carries a version and exact interval metadata');
  perform pg_temp.online_check(not (public.rm_online_operation_form_entry_v1(pg_temp.online_id(12),pg_temp.online_id(22),repeat('2',64),
    pg_temp.online_context(2),pg_temp.online_id(102),pg_temp.online_id(202),pg_temp.online_id(405)) ? 'edition'),
    'reader still works in other offices and never offers pilot submit there');
  payload := jsonb_build_object(pg_temp.online_id(801)::text,jsonb_build_array(pg_temp.online_id(812)),
    pg_temp.online_id(820)::text,'Inspeção concluída',pg_temp.online_id(821)::text,'25,5',
    pg_temp.online_id(822)::text,jsonb_build_object('inicio','2026-11-24'),
    pg_temp.online_id(823)::text,jsonb_build_object('inicio','2026-11-24','fim','2026-11-26'),
    pg_temp.online_id(824)::text,jsonb_build_array(pg_temp.online_id(827),pg_temp.online_id(826)));

  perform pg_temp.online_write_error(1,102,202,405,830,version,payload,'42501');
  perform pg_temp.online_write_error(1,101,201,405,830,version,payload,'42501');
  perform pg_temp.online_write_error(1,101,207,401,830,version,payload,'42501');
  perform pg_temp.online_write_error(2,102,202,405,830,version,payload,'42501');
  perform pg_temp.online_write_error(3,103,203,406,830,version,payload,'42501');
  perform pg_temp.online_write_error(1,101,201,401,830,repeat('0',64),payload,'PT412');
  perform pg_temp.online_write_error(1,101,201,401,830,version,payload-pg_temp.online_id(820)::text,'22023');
  perform pg_temp.online_write_error(1,101,201,401,830,version,
    payload||jsonb_build_object(pg_temp.online_id(825)::text,true),'PT422');
  perform pg_temp.online_write_error(1,101,201,401,830,version,
    payload||jsonb_build_object(pg_temp.online_id(803)::text,'Outra oficina'),'22023');
  perform pg_temp.online_write_error(1,101,201,401,830,version,
    payload||jsonb_build_object(pg_temp.online_id(801)::text,jsonb_build_array(pg_temp.online_id(813))),'22023');
  perform pg_temp.online_write_error(1,101,201,401,830,version,
    payload||jsonb_build_object(pg_temp.online_id(821)::text,'vinte'),'22023');
  perform pg_temp.online_write_error(1,101,201,401,830,version,
    payload||jsonb_build_object(pg_temp.online_id(822)::text,jsonb_build_object('inicio','2026-11-31')),'22008');
  perform pg_temp.online_check(not exists(select 1 from public.rm_registros_formulario where client_submission_id=pg_temp.online_id(830)),
    'all denied and invalid submissions are atomic');

  reply := pg_temp.online_submit(1,101,201,401,830,version,payload);
  inspection_id := (reply->>'registro_formulario_id')::uuid;
  retry := pg_temp.online_submit(1,101,201,401,830,version,payload);
  perform pg_temp.online_check(retry=reply||'{"idempotent_replay":true}'::jsonb
    and reply->>'respostas_gravadas'='6' and (select count(*) from public.rm_registros_formulario where client_submission_id=pg_temp.online_id(830))=1,
    'same request after lost response returns the same receipt and exactly one record');
  perform pg_temp.online_write_error(1,101,201,401,830,version,payload||jsonb_build_object(pg_temp.online_id(820)::text,'outro'),'PT409');
  perform pg_temp.online_check(exists(select 1 from public.rm_registros_formulario where id=inspection_id and status='em_an_lise'
    and preenchido and identidade_user_id=pg_temp.online_id(41) and responsavel_user_id=pg_temp.online_id(41)
    and created_by_user_id=pg_temp.online_id(31) and projeto_id=pg_temp.online_id(201)
    and form_id=pg_temp.online_id(401) and celula_id=pg_temp.online_id(101)),
    'review uses the shared record, project, device and operator attribution');
  perform pg_temp.online_check(exists(select 1 from public.rm_respostas where registro_formulario_id=inspection_id
    and questao_id=pg_temp.online_id(801) and enunciado='Condição visual' and itens=array['Conforme']
    and resposta='Conforme' and itens_questoes_ids=array[pg_temp.online_id(812)])
    and exists(select 1 from public.rm_respostas where registro_formulario_id=inspection_id
      and questao_id=pg_temp.online_id(821) and resposta='25,5' and indice=4.5)
    and exists(select 1 from public.rm_respostas where registro_formulario_id=inspection_id
      and questao_id=pg_temp.online_id(823) and date_inicio='2026-11-24T03:00:00Z' and data_fim='2026-11-26T03:00:00Z')
    and exists(select 1 from public.rm_respostas where registro_formulario_id=inspection_id
      and questao_id=pg_temp.online_id(824) and itens=array['Mecânica','Elétrica']),
    'portal receives template snapshots, fractional order, workshop dates and server choice labels');
  perform pg_temp.online_check(exists(select 1 from public.rm_respostas_temp where id=pg_temp.online_id(828))
    and not exists(select 1 from public.rm_sync_outbox where record_id=inspection_id and target_system='bubble_data_api'),
    'online filing preserves legacy drafts and does not enqueue Bubble');
  perform pg_temp.online_check(exists(select 1 from rm_private.project_audit_events_v1(pg_temp.online_id(201),'operations',array['forms'])
    where entity_id=inspection_id and source='web' and action='form_submitted' and actor_id=pg_temp.online_id(41)),
    'project activity records the operator and web origin');

  update public.rm_questoes set enunciado='Observação revisada' where id=pg_temp.online_id(820);
  perform pg_temp.online_write_error(1,101,201,401,831,version,payload,'PT412');
  perform pg_temp.online_check(pg_temp.online_submit(1,101,201,401,830,version,payload)=retry,
    'same completed protocol survives a later model change');
  update public.rm_questoes set obrigatorio=true where id=pg_temp.online_id(825);
  current_version := public.rm_online_operation_form_entry_v1(pg_temp.online_id(11),pg_temp.online_id(21),repeat('1',64),pg_temp.online_context(1),
    pg_temp.online_id(101),pg_temp.online_id(201),pg_temp.online_id(401))->'edition'->>'version';
  perform pg_temp.online_write_error(1,101,201,401,831,current_version,payload,'PT422');
end;$web_form$;

insert into auth.users(id) values(pg_temp.online_id(14));
insert into auth.sessions(id,user_id) values(pg_temp.online_id(24),pg_temp.online_id(14));
insert into public.rm_users(id,auth_user_id,nome,perfil)
  values(pg_temp.online_id(34),pg_temp.online_id(14),'Supervisor local BMA','administrador');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
  values(pg_temp.online_id(840),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.online_id(841),
    pg_temp.online_id(34),pg_temp.online_id(14),true,pg_temp.online_id(34),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('8',64),pg_temp.online_id(840),pg_temp.online_id(24),
  'opaque-local-review-session',clock_timestamp()+interval '30 minutes');
select set_config('request.jwt.claim.sub',pg_temp.online_id(14)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.online_id(24),'aal','aal1')::text,true);
set local role authenticated;
select pg_temp.online_check(exists(select 1 from public.rm_registros_formulario r join public.rm_respostas a on a.registro_formulario_id=r.id
  where r.client_submission_id=pg_temp.online_id(830) and r.status='em_an_lise' and a.resposta='Conforme'),
  'authenticated review list and answer reads see the new inspection');
reset role;

update rm_private.operator_delegations set revoked=true where operator_id=pg_temp.online_id(41);
select pg_temp.online_check(pg_temp.online_call(1) is null,'revoked operator grant is refused');
select pg_temp.online_check(pg_temp.online_form(1,101,201,401) is null,'revoked operator cannot use a saved form link');
select pg_temp.online_write_error(1,101,201,401,830,repeat('a',64),'{}','42501');
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
  and not has_function_privilege('anon','public.rm_online_operation_form_read_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.rm_online_operation_form_read_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid)','EXECUTE')
  and has_function_privilege('service_role','public.rm_online_operation_form_read_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid)','EXECUTE')
  and not has_function_privilege('service_role','rm_private.online_operation_form_v1(jsonb,uuid)','EXECUTE')
  and not has_function_privilege('anon','public.rm_online_operation_submit_form_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('authenticated','public.rm_online_operation_submit_form_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE')
  and has_function_privilege('service_role','public.rm_online_operation_submit_form_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('service_role','rm_private.submit_form_inspection_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb,boolean)','EXECUTE')
  and not has_function_privilege('service_role','rm_private.online_workshop_context_v1(jsonb,uuid,uuid)','EXECUTE'),
  'only the trusted server may invoke the new online RPCs');

rollback;
select 'PASS: online operation reads with three workshops, active cells and projects, fresh delegation, scoped catalogs and ACLs' result;

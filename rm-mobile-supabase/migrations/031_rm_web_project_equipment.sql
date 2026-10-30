-- Existing canonical equipment only. No backfill, binding repair or offline payload change.
begin;

create table rm_private.equipment_change_events (
 id uuid primary key default gen_random_uuid(),
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 equipamento_id uuid not null references public.rm_equipamentos(id) on delete restrict,
 auth_user_id uuid not null,
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 client_submission_id uuid not null unique,
 changed_fields text[] not null check(cardinality(changed_fields)>0),
 before_record jsonb not null,
 after_record jsonb not null,
 transaction_id bigint not null default txid_current(),
 created_at timestamptz not null default clock_timestamp()
);
create index equipment_change_events_equipment on rm_private.equipment_change_events(equipamento_id);
revoke all on rm_private.equipment_change_events from public,anon,authenticated,service_role;

-- Explicit projection excludes import metadata and the three retired receipt flags.
create function rm_private.project_equipment_record_v1(e public.rm_equipamentos) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select jsonb_build_object('id',e.id,'projeto_id',e.projeto_id,'tipo_equipamento_id',e.tipo_equipamento_id,'updated_at',e.updated_at,
 'placa_motor',e.placa_motor,'embarcacao',e.embarcacao,'fabricante',e.fabricante,'modelo',e.modelo,'numero_serie',e.numero_serie,
 'descricao',e.descricao,'certificado',e.certificado,'norma',e.norma,'potencia',e.potencia,'rotacao',e.rotacao,
 'tensao_estator',e.tensao_estator,'tipo_tensao',e.tipo_tensao,'corrente_estator',e.corrente_estator,'corrente_partida',e.corrente_partida,
 'frequencia',e.frequencia,'classe_isolamento',e.classe_isolamento,'grau_ip',e.grau_ip,'forma',e.forma,'regime',e.regime,
 'peso',e.peso,'ligacao',e.ligacao,'componentes',e.componentes,'fp',e.fp::text,'fs',e.fs::text,'numero_cabos',e.numero_cabos);
$$;
revoke all on function rm_private.project_equipment_record_v1(public.rm_equipamentos) from public,anon,authenticated,service_role;
grant execute on function rm_private.project_equipment_record_v1(public.rm_equipamentos) to authenticated;

create function public.rm_web_project_equipment_snapshot_v1(p_project_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare p public.rm_projetos%rowtype; e public.rm_equipamentos%rowtype; owned public.rm_equipamentos%rowtype;
 binding text; closed boolean; writable boolean; reverse_refs jsonb; context_version text; reason text;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501'; end if;
 select * into p from public.rm_projetos where id=p_project_id;
 if not found then return null; end if;
 select * into owned from public.rm_equipamentos where projeto_id=p.id;
 select * into e from public.rm_equipamentos where id=p.equipamento_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'updated_at',r.updated_at) order by r.id),'[]') into reverse_refs
  from public.rm_projetos r where r.equipamento_id=p.equipamento_id;
 binding:=case
  when p.equipamento_id is null and owned.id is null then 'missing'
  when p.equipamento_id is null then 'unlinked'
  when e.id is null or e.projeto_id is null then 'orphaned'
  when e.projeto_id<>p.id or owned.id is distinct from e.id then 'conflicting'
  when jsonb_array_length(reverse_refs)<>1 then 'shared'
  else 'linked' end;
 closed:=p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false);
 -- Operational eligibility; the BFF combines this with the current write capability.
 writable:=binding='linked' and not closed;
 reason:=case when binding<>'linked' then 'O vínculo do equipamento exige revisão administrativa antes da edição.'
  when closed then 'Projeto encerrado: somente consulta.'
  else null end;
 context_version:=encode(sha256(convert_to(jsonb_build_object('project',to_jsonb(p),'equipment_id',e.id,
  'equipment_version',e.updated_at,'equipment_owner',e.projeto_id,'owned_id',owned.id,'owned_version',owned.updated_at,
  'reverse_refs',reverse_refs,'binding',binding)::text,'UTF8')),'hex');
 return jsonb_build_object('project',jsonb_build_object('id',p.id,'numero',p.numero,'status_pcp',p.status_pcp,
  'data_real_de_entrega',p.data_real_de_entrega,'equipamento_id',p.equipamento_id,'tipo_equipamento_id',p.tipo_equipamento_id,'updated_at',p.updated_at,'closed',closed),
  'equipment',case when binding='linked' then rm_private.project_equipment_record_v1(e) else null end,
  'binding_state',binding,'can_edit',writable,'reason',reason,'context_version',context_version,
  'type_mismatch',binding='linked' and p.tipo_equipamento_id is distinct from e.tipo_equipamento_id);
end $$;
revoke all on function public.rm_web_project_equipment_snapshot_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_equipment_snapshot_v1(uuid) to authenticated;

-- Old mobile drafts have no equipment version. Once the web has changed a field,
-- differing later legacy/ETL writes must be reconciled, never silently applied.
-- No client flag or GUC can bypass this guard. Only the exact private journal
-- entry created by this transaction authorizes the web's intended update.
create function rm_private.guard_web_equipment_fields_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare fields text[]; k text; approved boolean:=false; old_json jsonb:=to_jsonb(old); new_json jsonb;
begin
 select array_agg(distinct f) into fields from rm_private.equipment_change_events a cross join unnest(a.changed_fields) f where a.equipamento_id=old.id;
 if fields is null then if tg_op='DELETE' then return old; else return new; end if; end if;
 if tg_op='DELETE' then raise exception 'Equipamento com edição técnica registrada: exclusão exige reconciliação.' using errcode='PT409'; end if;
 new_json:=to_jsonb(new);
 if new.id is distinct from old.id or new.projeto_id is distinct from old.projeto_id then
  raise exception 'O vínculo do equipamento editado exige reconciliação.' using errcode='PT409'; end if;
 select exists(select 1 from rm_private.equipment_change_events a where a.equipamento_id=old.id
  and a.transaction_id=txid_current() and a.before_record=old_json
  and not exists(select 1 from jsonb_object_keys(new_json) x where x not in('updated_at','sync_source') and
   (case when x=any(a.changed_fields) then new_json->x is distinct from a.after_record->x else new_json->x is distinct from old_json->x end))) into approved;
 if not approved then
  foreach k in array fields loop
   if new_json->k is distinct from old_json->k then
    raise exception 'Dados técnicos atualizados no portal. Revise o recebimento pendente sem substituir o envio original.' using errcode='PT409'; end if;
  end loop;
 end if;
 return new;
end $$;
revoke all on function rm_private.guard_web_equipment_fields_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_web_equipment before update or delete on public.rm_equipamentos
 for each row execute function rm_private.guard_web_equipment_fields_v1();

-- Called after project11/project-row locks, before any legacy receipt writes.
-- Validate every relevant web-managed equipment rather than repairing a pointer.
create function rm_private.assert_legacy_equipment_edit_v1(p_project uuid,p_params jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare p public.rm_projetos%rowtype; e public.rm_equipamentos%rowtype; incoming public.rm_equipamentos%rowtype;
 fields text[]; k text; patch jsonb; raw jsonb:=coalesce(p_params->'p_equipamento','{}');
begin
 select * into p from public.rm_projetos where id=p_project;
 for e in select x.* from public.rm_equipamentos x where (x.projeto_id=p_project or x.id=p.equipamento_id)
  and exists(select 1 from rm_private.equipment_change_events a where a.equipamento_id=x.id) order by x.id for update loop
  if e.projeto_id is distinct from p_project or p.equipamento_id is distinct from e.id
   or (select count(*) from public.rm_projetos r where r.equipamento_id=e.id)<>1 then
   raise exception 'O vínculo do equipamento editado exige reconciliação antes do recebimento.' using errcode='PT409'; end if;
  select array_agg(distinct f) into fields from rm_private.equipment_change_events a cross join unnest(a.changed_fields) f where a.equipamento_id=e.id;
  patch:='{}';
  foreach k in array fields loop
   if raw?k then
    patch:=patch||jsonb_build_object(k,case when raw->>k='' and k in('placa_motor','fp','fs','numero_cabos') then 'null'::jsonb else raw->k end);
   end if;
  end loop;
  incoming:=jsonb_populate_record(e,patch);
  foreach k in array fields loop
   if to_jsonb(incoming)->k is distinct from to_jsonb(e)->k then
    raise exception 'Dados técnicos atualizados no portal. Revise o recebimento pendente sem substituir o envio original.' using errcode='PT409'; end if;
  end loop;
 end loop;
end $$;
revoke all on function rm_private.assert_legacy_equipment_edit_v1(uuid,jsonb) from public,anon,authenticated,service_role;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_project_dossier_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype; p public.rm_projetos%rowtype;
 e public.rm_equipamentos%rowtype; proposed public.rm_equipamentos%rowtype; snapshot jsonb; changes jsonb; result jsonb;
 project_id uuid; equipment_id uuid; expected_project timestamptz; expected_equipment timestamptz; key text;
 journal_id uuid; assignments text; changed text[]:='{}'; old_json jsonb; proposed_json jsonb;
 text_fields constant text[]:=array['embarcacao','fabricante','modelo','numero_serie','descricao','certificado','norma','potencia','rotacao',
  'tensao_estator','tipo_tensao','corrente_estator','corrente_partida','frequencia','classe_isolamento','grau_ip','forma','regime','peso','ligacao','componentes'];
 allowed constant text[]:=array['projeto_id','equipamento_id','expected_project_updated_at','expected_equipment_updated_at','expected_context_version','confirm_change','changes'];
begin
 if p_operation is distinct from 'save_project_equipment' then
  return rm_private.web_mutate_project_dossier_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then
  raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string' or jsonb_typeof(p_payload->'equipamento_id') is distinct from 'string'
  or p_payload->'confirm_change' is distinct from 'true'::jsonb
  or jsonb_typeof(p_payload->'expected_project_updated_at') is distinct from 'string'
  or jsonb_typeof(p_payload->'expected_equipment_updated_at') is distinct from 'string'
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_equipment_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or jsonb_typeof(p_payload->'expected_context_version') is distinct from 'string' or p_payload->>'expected_context_version' !~ '^[a-f0-9]{64}$'
  or jsonb_typeof(p_payload->'changes') is distinct from 'object' or p_payload->'changes'='{}'::jsonb then
  raise exception 'Confirmação, contexto ou alterações inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; equipment_id:=(p_payload->>'equipamento_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_equipment:=(p_payload->>'expected_equipment_updated_at')::timestamptz;
 if not isfinite(expected_project) or not isfinite(expected_equipment) then raise exception 'Versões inválidas.' using errcode='22023'; end if;
 changes:=p_payload->'changes';
 for key in select jsonb_object_keys(changes) loop
  if not key=any(text_fields||array['placa_motor','fp','fs','numero_cabos']) then raise exception 'Campo técnico não permitido.' using errcode='22023'; end if;
  if jsonb_typeof(changes->key)='null' then continue; end if;
  if key=any(text_fields) then
   if jsonb_typeof(changes->key)<>'string' or length(changes->>key)>10000 then raise exception 'Texto técnico inválido: limite de 10000 caracteres por alteração.' using errcode='22023'; end if;
  elsif key='placa_motor' then
   if jsonb_typeof(changes->key)<>'string' or changes->>key not in('c___placa','s___placa') then raise exception 'Placa do motor inválida.' using errcode='22023'; end if;
  elsif key in('fp','fs') then
   if jsonb_typeof(changes->key)<>'string' or changes->>key !~ '^[-+]?\d{1,30}(\.\d{1,20})?$' then raise exception 'Valor decimal inválido.' using errcode='22023'; end if;
  else
   if jsonb_typeof(changes->key)<>'number' or changes->>key !~ '^[0-9]+$' or (changes->>key)::numeric>2147483647 then raise exception 'Número de cabos inválido.' using errcode='22023'; end if;
  end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into p from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 select * into e from public.rm_equipamentos where id=equipment_id for update;
 snapshot:=public.rm_web_project_equipment_snapshot_v1(project_id);
 if p.updated_at<>expected_project or e.id is null or e.updated_at<>expected_equipment
  or snapshot->>'context_version'<>p_payload->>'expected_context_version' or snapshot->>'binding_state'<>'linked'
  or p.equipamento_id is distinct from equipment_id then raise exception 'O projeto ou equipamento mudou. Atualize antes de salvar.' using errcode='PT409'; end if;
 if (snapshot->'project'->>'closed')::boolean then raise exception 'Projeto encerrado: somente consulta.' using errcode='22023'; end if;
 proposed:=jsonb_populate_record(e,changes); old_json:=to_jsonb(e); proposed_json:=to_jsonb(proposed);
 select coalesce(array_agg(k order by k),'{}') into changed from jsonb_object_keys(changes) k where old_json->k is distinct from proposed_json->k;
 if cardinality(changed)>0 then
  insert into rm_private.equipment_change_events(projeto_id,equipamento_id,auth_user_id,actor_id,client_submission_id,changed_fields,before_record,after_record)
   values(project_id,e.id,auth.uid(),actor.id,p_client_submission_id,changed,old_json,proposed_json) returning id into journal_id;
  select string_agg(format('%I=($1).%I',k,k),', ' order by k) into assignments from unnest(changed) k;
  execute format('update public.rm_equipamentos set %s,sync_source=''supabase'' where id=$2 returning *',assignments) into e using proposed,e.id;
  update rm_private.equipment_change_events set after_record=to_jsonb(e) where id=journal_id;
 end if;
 snapshot:=public.rm_web_project_equipment_snapshot_v1(project_id);
 result:=jsonb_build_object('operation',p_operation,'id',e.id,'projeto_id',project_id,'updated_at',e.updated_at,'idempotent_replay',false,
  'record',jsonb_build_object('projeto_id',project_id,'equipamento_id',e.id,'project_updated_at',p.updated_at,'changed_fields',to_jsonb(changed),'context_version',snapshot->>'context_version'));
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation='save_project_equipment' then raise exception 'Identificador, versão ou dados técnicos inválidos.' using errcode='22023'; end if; raise;
end $$;

-- Match all project writers: project11 BEFORE the project row lock. This only
-- serializes a new QR update; completed mobile receipts return before this path.
do $$ declare definition text; marker text:='  select * into pr from public.rm_projetos where id=p_project for update;'; begin
 definition:=pg_get_functiondef('rm_private.update_recebimento_v1(uuid,uuid,jsonb)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Unexpected receipt project lock'; end if;
 definition:=replace(definition,marker,'  perform pg_advisory_xact_lock(hashtextextended(p_project::text,11));'||chr(10)||marker);
 marker:='  update public.rm_projetos set numero=';
 if strpos(definition,marker)=0 then raise exception 'Unexpected receipt project write'; end if;
 execute replace(definition,marker,'  perform rm_private.assert_legacy_equipment_edit_v1(p_project,p_params);'||chr(10)||marker);
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
 'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
 'set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules','manage_cell_availability',
 'add_project_comment','reserve_project_attachment','finalize_project_attachment','save_project_equipment'));
do $$ declare definition text; marker text:='when ''finalize_project_attachment'' then ''em.projects.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Unexpected equipment permit map'; end if;
 execute replace(definition,marker,'when ''finalize_project_attachment'' then ''em.projects.manage'' when ''save_project_equipment'' then ''em.projects.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 execute pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_project_dossier_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

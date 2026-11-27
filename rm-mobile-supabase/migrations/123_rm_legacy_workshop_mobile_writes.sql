begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_legacy_mobile_write_settings (
 singleton boolean primary key check(singleton),
 activated_at timestamptz not null
);
alter table rm_private.workshop_legacy_mobile_write_settings enable row level security;
revoke all on rm_private.workshop_legacy_mobile_write_settings from public,anon,authenticated,service_role;

alter table rm_private.mobile_workshop_mutation_permits add column gateway_xid xid8;

create function rm_private.legacy_mobile_mutation_project_v1(p_rpc text,p_args jsonb,p_office uuid)
returns uuid language plpgsql stable set search_path='' as $$
declare
 photo_title_id uuid;
 target_cell uuid;
begin
 if p_rpc='rm_record_cell_photo_v1' and nullif(p_args->>'p_cadastro_foto_id','') is not null then
  photo_title_id:=(p_args->>'p_cadastro_foto_id')::uuid;
  if nullif(p_args->>'p_foto_id','') is null then
   target_cell:=(p_args->>'p_celula_id')::uuid;
  else
   select f.celula_id into target_cell from public.rm_fotos f where f.id=(p_args->>'p_foto_id')::uuid;
  end if;
  if not exists(select 1 from rm_private.engineering_photo_title_scope s where s.title_id=photo_title_id
   and s.workshop_id=p_office and (s.cell_id is null or s.cell_id=target_cell)) then return null;end if;
  p_args:=p_args-'p_cadastro_foto_id';
 end if;
 return rm_private.mobile_mutation_workshop_project_v1(p_rpc,p_args,p_office);
exception when invalid_text_representation then
 raise exception 'Título ou célula de foto inválidos.' using errcode='22023';
end
$$;

create function rm_private.require_mobile_mutation_workshop_v1(
 p_submission uuid,p_rpc text,p_args jsonb,p_params_for_receipt jsonb,p_operator uuid,p_token text
) returns void language plpgsql set search_path='' as $$
declare
 permit rm_private.mobile_workshop_mutation_permits%rowtype;
 office uuid;
 project uuid;
begin
 if not exists(select 1 from rm_private.workshop_legacy_mobile_write_settings where singleton) then return;end if;

 -- Only the exact original owner can receive the existing deletion response.
 -- It is a terminal error and returns no project data or business effects.
 if exists(select 1 from rm_private.mobile_mutation_receipts r where r.client_submission_id=p_submission
  and r.auth_user_id=auth.uid() and r.operator_id=p_operator and r.rpc_name=p_rpc
  and r.result->'resource_deleted'='true'::jsonb
  and r.params->>'original_sha256'=encode(sha256(convert_to(p_params_for_receipt::text,'UTF8')),'hex')) then return;end if;

 select * into permit from rm_private.mobile_workshop_mutation_permits a
 where a.submission_id=p_submission and a.rpc_name=p_rpc and a.expires_at>clock_timestamp();
 if found then
  if permit.gateway_xid is null or permit.gateway_xid is distinct from pg_current_xact_id_if_assigned()
   or permit.auth_user_id is distinct from auth.uid() or permit.auth_session_id::text is distinct from auth.jwt()->>'session_id'
   or permit.operator_id is distinct from p_operator or permit.operator_hash is distinct from extensions.digest(p_token,'sha256')
   or permit.payload_hash is distinct from extensions.digest(p_args::text,'sha256') then
   raise exception 'Confirme a oficina pelo serviço de sincronização. O protocolo continua preservado.' using errcode='42501';
  end if;
  -- The scoped gateway already locked and revalidated the project in this transaction.
  return;
 end if;

 office:=rm_private.workshop_legacy_operator_office_v1(p_operator);
 if office is null then
  raise exception 'Confirme a oficina antes de sincronizar. O protocolo continua preservado.' using errcode='42501';
 end if;
 project:=rm_private.legacy_mobile_mutation_project_v1(p_rpc,p_args,office);
 if project is null then raise exception 'Registro indisponível nesta oficina. O protocolo continua preservado.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(project::text,11));
 if rm_private.legacy_mobile_mutation_project_v1(p_rpc,p_args,office) is distinct from project then
  raise exception 'O registro mudou. Preserve o protocolo para conferência.' using errcode='42501';
 end if;
end
$$;

create function rm_private.require_legacy_receiving_workshop_v1(p_submission uuid,p_args jsonb,p_operator uuid)
returns void language plpgsql set search_path='' as $$
declare
 office uuid;
 client_id uuid;
 type_id uuid;
 target uuid;
 own_original uuid;
begin
 if not exists(select 1 from rm_private.workshop_legacy_mobile_write_settings where singleton) then return;end if;
 office:=rm_private.workshop_legacy_operator_office_v1(p_operator);
 if office is null then
  raise exception 'Confirme a oficina do recebimento. O protocolo continua preservado.' using errcode='42501';
 end if;
 client_id:=nullif(p_args->>'p_cliente_id','')::uuid;
 type_id:=nullif(p_args->>'p_tipo_equipamento_id','')::uuid;
 if (client_id is not null and not rm_private.workshop_read_owned_v1('client',client_id,office))
  or (type_id is not null and not rm_private.workshop_read_owned_v1('equipment_type',type_id,office)) then
  raise exception 'Cliente ou equipamento fora da oficina. O protocolo continua preservado.' using errcode='42501';
 end if;

 select o.project_id into own_original from rm_private.receiving_openings o where o.client_submission_id=p_submission
  and o.auth_user_id=auth.uid() and o.operator_id=p_operator;
 if not found then
  select (r.result->>'projeto_id')::uuid into own_original from rm_private.mobile_mutation_receipts r
   where r.client_submission_id=p_submission and r.auth_user_id=auth.uid() and r.operator_id=p_operator
    and r.rpc_name='rm_submit_recebimento_v1';
 end if;
 for target in select nullif(p_args->>'p_projeto_id','')::uuid union select own_original order by 1 loop
  if target is null then continue;end if;
  perform pg_advisory_xact_lock(hashtextextended(target::text,11));
  if not rm_private.workshop_project_owned_v1(target,office)
   and not (target is not distinct from own_original and (
    exists(select 1 from rm_private.workshop_legacy_bma_projects where id=target)
    or (not exists(select 1 from public.rm_projetos where id=target) and exists(
     select 1 from rm_private.workshop_object_origins where object_kind='project' and object_id=target and workshop_id=office)))) then
   raise exception 'Projeto indisponível nesta oficina. O protocolo continua preservado.' using errcode='42501';
  end if;
 end loop;
end
$$;
revoke all on function rm_private.legacy_mobile_mutation_project_v1(text,jsonb,uuid),
 rm_private.require_mobile_mutation_workshop_v1(uuid,text,jsonb,jsonb,uuid,text),
 rm_private.require_legacy_receiving_workshop_v1(uuid,jsonb,uuid) from public,anon,authenticated,service_role;

do $integrate$
declare
 ordinary text:=pg_get_functiondef('rm_private.mobile_mutate_before_execution_v1(uuid,text,jsonb,text)'::regprocedure);
 execution text:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 gateway text:=pg_get_functiondef('public.rm_mobile_workshop_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 receiving text:=pg_get_functiondef('rm_private.require_scoped_receiving_draft_submission_v1(uuid,text,jsonb,uuid,text)'::regprocedure);
 draft text:=pg_get_functiondef('rm_private.receiving_draft_store_v1(text,text,uuid,jsonb,bigint,uuid,boolean)'::regprocedure);
 ordinary_anchor constant text:='  if exists(select 1 from rm_private.receiving_openings where client_submission_id=p_client_submission_id) then';
 execution_anchor constant text:=' select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_client_submission_id;';
 gateway_anchor constant text:=' result:=public.rm_mobile_mutate_v1(p_client_submission_id,p_rpc_name,p_params,p_operator_token);';
 receiving_anchor constant text:='and not exists(select 1 from unnest(target_offices) office where office is distinct from legacy_office) then';
 draft_anchor constant text:=' if p_action=''read'' then';
begin
 if array_length(string_to_array(ordinary,ordinary_anchor),1) is distinct from 2
  or array_length(string_to_array(execution,execution_anchor),1) is distinct from 2
  or array_length(string_to_array(gateway,gateway_anchor),1) is distinct from 2
  or array_length(string_to_array(receiving,receiving_anchor),1) is distinct from 2
  or array_length(string_to_array(draft,draft_anchor),1) is distinct from 2 then raise exception 'Unexpected mobile write contract';end if;
 execute replace(ordinary,ordinary_anchor,$sql$
  if p_rpc_name is distinct from 'rm_submit_recebimento_v1' then
   perform rm_private.require_mobile_mutation_workshop_v1(p_client_submission_id,p_rpc_name,p_params,v_params,d.operator_id,p_operator_token);
  end if;
$sql$||ordinary_anchor);
 execute replace(execution,execution_anchor,$sql$
 perform rm_private.require_mobile_mutation_workshop_v1(p_client_submission_id,p_rpc_name,p_params,v_params,d.operator_id,p_operator_token);
$sql$||execution_anchor);
 execute replace(gateway,gateway_anchor,$sql$
 update rm_private.mobile_workshop_mutation_permits set gateway_xid=pg_current_xact_id()
  where submission_id=p_client_submission_id and rpc_name=p_rpc_name;
$sql$||gateway_anchor);
 execute replace(receiving,receiving_anchor,receiving_anchor||$sql$
  perform rm_private.require_legacy_receiving_workshop_v1(p_submission,p_params,p_operator);
$sql$);
 execute replace(draft,draft_anchor,$sql$
 if not p_scoped and exists(select 1 from rm_private.workshop_legacy_mobile_write_settings where singleton)
  and rm_private.workshop_legacy_operator_office_v1(d.operator_id) is null then
  raise exception 'Confirme a oficina para acessar o rascunho original.' using errcode='42501';
 end if;
$sql$||draft_anchor);
end
$integrate$;

create function rm_private.activate_workshop_legacy_mobile_writes_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop-legacy-bma-catalog',119));
 if not exists(select 1 from rm_private.workshop_legacy_operator_read_settings where singleton) then
  raise exception 'Ative o recorte da identificação antes das gravações legadas.' using errcode='PT409';
 end if;
 insert into rm_private.workshop_legacy_mobile_write_settings(singleton,activated_at)
  values(true,clock_timestamp()) on conflict(singleton) do nothing;
end
$$;
revoke all on function rm_private.activate_workshop_legacy_mobile_writes_v1() from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;

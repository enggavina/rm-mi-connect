-- A requested receiving becomes an effective project before its media uploads.
-- The original final command and all previously installed native clients survive.
begin;

-- This immutable protocol binding intentionally outlives project deletion, like
-- a receipt tombstone. It contains hashes/identities, never the receiving dossier.
create table rm_private.receiving_openings (
 client_submission_id uuid primary key,
 auth_user_id uuid not null references auth.users(id) on delete restrict,
 operator_id uuid not null references public.rm_users(id) on delete restrict,
 original_sha256 text not null check(original_sha256 ~ '^[0-9a-f]{64}$'),
 metadata_sha256 text not null check(metadata_sha256 ~ '^[0-9a-f]{64}$'),
 project_id uuid not null unique,
 equipment_id uuid not null unique,
 created_at timestamptz not null default clock_timestamp()
);
revoke all on rm_private.receiving_openings from public,anon,authenticated,service_role;

-- Replace only known media URL positions. All identifiers, titles, comments,
-- invoice numbers and other metadata remain part of the finalization identity.
create function rm_private.receiving_metadata_v1(p_value jsonb,p_key text default null) returns jsonb
language plpgsql immutable set search_path='' as $$
declare result jsonb; item record; child jsonb;
begin
 if jsonb_typeof(p_value)='string' and p_key in('foto_url','uri','arquivoNotaFiscal','p_arquivo_nota_fiscal_url','__legacy_photo') then
  return case when p_value='""'::jsonb then p_value else '"__receiving_media_url__"'::jsonb end;
 elsif jsonb_typeof(p_value)='object' then
  result:='{}';
  for item in select key,value from jsonb_each(p_value) loop result:=result||jsonb_build_object(item.key,rm_private.receiving_metadata_v1(item.value,item.key));end loop;
  return result;
 elsif jsonb_typeof(p_value)='array' then
  result:='[]';
  for child in select value from jsonb_array_elements(p_value) loop
   result:=result||jsonb_build_array(rm_private.receiving_metadata_v1(child,case when p_key='fotos' and jsonb_typeof(child)='string' then '__legacy_photo' else null end));
  end loop;
  return result;
 end if;
 return p_value;
end $$;
revoke all on function rm_private.receiving_metadata_v1(jsonb,text) from public,anon,authenticated,service_role;

create function rm_private.receiving_actor_v1(p_token text,p_params jsonb) returns rm_private.operator_delegations
language plpgsql security definer set search_path='' as $$
declare d rm_private.operator_delegations%rowtype;
begin
 select * into d from rm_private.operator_delegations where token_hash=extensions.digest(p_token,'sha256')
  and auth_user_id=auth.uid() and not revoked and expires_at>clock_timestamp();
 if not found or rm_private.current_rm_user_id() is distinct from d.tablet_user_id
  or not exists(select 1 from public.rm_users where id=d.operator_id and status='ativo') then
  raise exception 'Identifique novamente o operador responsável neste dispositivo.' using errcode='28000';end if;
 if p_params is null or jsonb_typeof(p_params)<>'object' or octet_length(p_params::text)>2097152 then
  raise exception 'Envelope de recebimento inválido.' using errcode='22023';end if;
 if nullif(p_params->>'p_operador_id','')::uuid is not null and (p_params->>'p_operador_id')::uuid<>d.operator_id then
  raise exception 'Identidade do recebimento divergente.' using errcode='42501';end if;
 return d;
end $$;
revoke all on function rm_private.receiving_actor_v1(text,jsonb) from public,anon,authenticated,service_role;

create function public.rm_mobile_open_receiving_v1(p_client_submission_id uuid,p_params jsonb,p_operator_token text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare d rm_private.operator_delegations%rowtype; opening rm_private.receiving_openings%rowtype;
 receipt rm_private.mobile_mutation_receipts%rowtype; draft rm_private.receiving_drafts%rowtype;
 pr public.rm_projetos%rowtype; params jsonb; snapshot jsonb; result jsonb; original_hash text; metadata_hash text;
 expected bigint; pending uuid; eq jsonb;
begin
 d:=rm_private.receiving_actor_v1(p_operator_token,p_params);
 if p_client_submission_id is null then raise exception 'Protocolo de recebimento obrigatório.' using errcode='22023';end if;
 params:=p_params-'p_operador_id'-'p_tablet_user_id'-'p_client_submission_id';
 original_hash:=encode(sha256(convert_to(params::text,'UTF8')),'hex');
 metadata_hash:=encode(sha256(convert_to(rm_private.receiving_metadata_v1(params)::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
 select * into opening from rm_private.receiving_openings where client_submission_id=p_client_submission_id;
 if found then
  if opening.auth_user_id<>auth.uid() or opening.operator_id<>d.operator_id or opening.original_sha256<>original_hash then
   raise exception 'Protocolo de abertura já utilizado com outro conteúdo.' using errcode='22023';end if;
  perform pg_advisory_xact_lock(hashtextextended(opening.project_id::text,11));
  if rm_private.project_deleted_v1(opening.project_id) or not exists(select 1 from public.rm_projetos where id=opening.project_id) then
   raise exception 'Projeto excluído explicitamente. O recebimento foi preservado para conferência.' using errcode='PT410';end if;
  select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_client_submission_id;
  return jsonb_build_object('projeto_id',opening.project_id,'equipamento_id',opening.equipment_id,'receiving_id',p_client_submission_id,
   'opening_created',receipt.client_submission_id is null,'attachments_pending',receipt.client_submission_id is null,'idempotent_replay',true);
 end if;
 select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>'rm_submit_recebimento_v1' then
   raise exception 'Protocolo de recebimento já utilizado.' using errcode='22023';end if;
  if receipt.result->'resource_deleted'='true'::jsonb then raise exception 'Projeto excluído explicitamente. Preserve o protocolo original.' using errcode='PT410';end if;
  if encode(sha256(convert_to(rm_private.receiving_metadata_v1(receipt.params)::text,'UTF8')),'hex')<>metadata_hash then
   raise exception 'Protocolo de recebimento já utilizado com outro conteúdo.' using errcode='22023';end if;
  return jsonb_build_object('projeto_id',receipt.result->'projeto_id','equipamento_id',receipt.result->'equipamento_id','receiving_id',p_client_submission_id,
   'opening_created',false,'attachments_pending',false,'idempotent_replay',true);
 end if;
 -- A QR check-in already has a visible project. Preserve its installed legacy
 -- finalization semantics, including its current project access checks.
 if nullif(params->>'p_projeto_id','') is not null then
  perform pg_advisory_xact_lock(hashtextextended(params->>'p_projeto_id',11));
  select * into pr from public.rm_projetos where id=(params->>'p_projeto_id')::uuid;
  if not found then raise exception 'Projeto do QR não encontrado.' using errcode='P0002';end if;
  if not exists(select 1 from public.rm_users where id=d.tablet_user_id and perfil='administrador') and pr.created_by_user_id is distinct from d.operator_id
   and not exists(select 1 from public.rm_celulas_projeto cp join public.rm_tablet_celula_users t on t.celula_id=cp.celula_id where cp.projeto_id=pr.id and t.usuario_id=d.tablet_user_id) then
   raise exception 'Projeto do QR não disponível neste dispositivo.' using errcode='42501';end if;
  if pr.equipamento_id is null then raise exception 'Confira o equipamento do projeto antes de enviar.' using errcode='PT409';end if;
  return jsonb_build_object('projeto_id',pr.id,'equipamento_id',pr.equipamento_id,'receiving_id',p_client_submission_id,
   'opening_created',false,'attachments_pending',true,'idempotent_replay',false);
 end if;
 snapshot:=params->'p_receiving_draft_snapshot'; expected:=(params->>'p_receiving_draft_revision')::bigint;
 pending:=nullif(params->>'p_receiving_draft_save_id','')::uuid;
 if (params->>'p_receiving_draft_id') is distinct from p_client_submission_id::text or expected is null or expected<0
  or jsonb_typeof(snapshot) is distinct from 'object' or octet_length(snapshot::text)>1048576
  or snapshot->>'id' is distinct from p_client_submission_id::text or snapshot->>'version' is distinct from '2'
  or coalesce(snapshot->>'submitted','false')<>'false' or nullif(params->>'p_cliente_id','') is null then
  raise exception 'Rascunho ou protocolo de abertura inválido.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||auth.uid()::text||':'||d.operator_id::text,45));
 select * into draft from rm_private.receiving_drafts where id=p_client_submission_id for update;
 if found then
  if draft.auth_user_id<>auth.uid() or draft.operator_id<>d.operator_id then raise exception 'Rascunho indisponível para este operador.' using errcode='42501';end if;
  if draft.state<>'draft' or (draft.revision<>expected and not(draft.revision=expected+1 and pending is not null and draft.last_save_id=pending)) then
   raise exception 'O rascunho mudou em outro dispositivo. Confira antes de solicitar abertura.' using errcode='PT409';end if;
 else
  if expected<>0 or exists(select 1 from rm_private.receiving_drafts rd where auth_user_id=auth.uid() and operator_id=d.operator_id and state='draft'
    and not exists(select 1 from rm_private.receiving_openings ro where ro.client_submission_id=rd.id)) then
   raise exception 'Há outro rascunho no banco. Confira antes de solicitar abertura.' using errcode='PT409';end if;
  -- No autosave is invented: several already submitted local protocols may
  -- obtain project bindings while their final commands retain the same FIFO.
 end if;
 eq:=coalesce(params->'p_equipamento','{}');
 if params?'p_descricao_equipamento' then eq:=eq||jsonb_build_object('descricao',params->>'p_descricao_equipamento');end if;
 result:=public.rm_submit_recebimento_v1(d.operator_id,(params->>'p_cliente_id')::uuid,nullif(params->>'p_tipo_equipamento_id','')::uuid,
  params->>'p_numero_projeto',params->>'p_nome_projeto',nullif(params->>'p_chegada_equipamento','')::timestamptz,
  params->>'p_contato',params->>'p_proprietario',params->>'p_eventualidades',eq,'[]');
 update public.rm_projetos set nota_fiscal=params->>'p_nota_fiscal' where id=(result->>'projeto_id')::uuid;
 insert into rm_private.receiving_openings(client_submission_id,auth_user_id,operator_id,original_sha256,metadata_sha256,project_id,equipment_id)
  values(p_client_submission_id,auth.uid(),d.operator_id,original_hash,metadata_hash,(result->>'projeto_id')::uuid,(result->>'equipamento_id')::uuid);
 return (result||jsonb_build_object('receiving_id',p_client_submission_id,'opening_created',true,'attachments_pending',true,'idempotent_replay',false))-'fotos_criadas';
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception 'Dados ou versão do recebimento inválidos.' using errcode='22023';
end $$;
revoke all on function public.rm_mobile_open_receiving_v1(uuid,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_open_receiving_v1(uuid,jsonb,text) to authenticated;

create function rm_private.finalize_receiving_opening_v1(p_submission uuid,p_params jsonb,p_token text) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare d rm_private.operator_delegations%rowtype; opening rm_private.receiving_openings%rowtype; receipt rm_private.mobile_mutation_receipts%rowtype;
 pr public.rm_projetos%rowtype; params jsonb; final_result jsonb; photo jsonb; count_photos int:=0; invoice text; snapshot jsonb;
begin
 d:=rm_private.receiving_actor_v1(p_token,p_params); params:=p_params-'p_operador_id'-'p_tablet_user_id'-'p_client_submission_id';
 perform pg_advisory_xact_lock(hashtextextended(p_submission::text,0));
 select * into opening from rm_private.receiving_openings where client_submission_id=p_submission;
 if not found or opening.auth_user_id<>auth.uid() or opening.operator_id<>d.operator_id then raise exception 'Abertura indisponível para este operador.' using errcode='42501';end if;
 if opening.metadata_sha256<>encode(sha256(convert_to(rm_private.receiving_metadata_v1(params)::text,'UTF8')),'hex') then
  raise exception 'Os dados do protocolo original de recebimento foram alterados.' using errcode='22023';end if;
 select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_submission;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>'rm_submit_recebimento_v1' then raise exception 'Protocolo já utilizado.' using errcode='22023';end if;
  if receipt.result->'resource_deleted'='true'::jsonb then
   if receipt.params->>'original_sha256'<>encode(sha256(convert_to(params::text,'UTF8')),'hex') then raise exception 'Protocolo já utilizado com outro conteúdo.' using errcode='22023';end if;
   raise exception 'Projeto excluído explicitamente. Preserve o protocolo original.' using errcode='PT410';end if;
  if receipt.params<>params then raise exception 'Protocolo já utilizado com outro conteúdo.' using errcode='22023';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||auth.uid()::text||':'||d.operator_id::text,45));
 perform pg_advisory_xact_lock(hashtextextended(opening.project_id::text,11));
 select * into pr from public.rm_projetos where id=opening.project_id for update;
 if not found or rm_private.project_deleted_v1(opening.project_id) then raise exception 'Projeto excluído explicitamente. Preserve o protocolo original.' using errcode='PT410';end if;
 if exists(select 1 from rm_private.receiving_drafts where id=p_submission and (auth_user_id<>auth.uid() or operator_id<>d.operator_id or state<>'draft')) then
  raise exception 'Rascunho indisponível para concluir este recebimento.' using errcode='PT409';end if;
 if jsonb_typeof(params->'p_fotos_recebimento') is distinct from 'array' or exists(select 1 from jsonb_array_elements(params->'p_fotos_recebimento') f where nullif(f->>'foto_url','') is null or f->>'foto_url' !~ '^https://') then
  raise exception 'Envie as fotos antes de concluir o recebimento.' using errcode='22023';end if;
 invoice:=nullif(params->>'p_arquivo_nota_fiscal_url','');
 if invoice is not null and invoice !~ '^https://' then raise exception 'Envie a nota fiscal antes de concluir o recebimento.' using errcode='22023';end if;
 for photo in select value from jsonb_array_elements(params->'p_fotos_recebimento') loop
  if not exists(select 1 from public.rm_fotos where projeto_id=pr.id and foto_url=photo->>'foto_url') then
   insert into public.rm_fotos(projeto_id,etapa,categoria_foto,tipo_recebimento,identificador_foto_key,titulo,descricao,legenda,foto_url,numero,numero_foto_complementar,created_by_user_id,modified_by_id,sync_source)
    values(pr.id,'recebimento',coalesce(nullif(photo->>'categoria_foto','')::public.rm_categoria_foto_enum,'obrigat_ria'),nullif(photo->>'tipo_recebimento','')::public.rm_tipo_foto_recebimento_enum,
     photo->>'identificador_foto_key',photo->>'titulo',photo->>'descricao',photo->>'legenda',photo->>'foto_url',nullif(photo->>'numero','')::int,nullif(photo->>'numero_foto_complementar','')::int,d.operator_id,d.operator_id,'supabase');
   count_photos:=count_photos+1;
  end if;
 end loop;
 if invoice is not null then
  if not exists(select 1 from public.rm_documentos where projeto_id=pr.id and arquivo_url=invoice) then
   insert into public.rm_documentos(projeto_id,nome,tipo_documento,arquivo_url,created_by) values(pr.id,'Nota fiscal do recebimento','Nota fiscal',invoice,d.operator_id);end if;
  -- A consolidated web invoice is never replaced by the older mobile snapshot.
  update public.rm_projetos set arquivo_nota_fiscal_url=invoice where id=pr.id and nullif(arquivo_nota_fiscal_url,'') is null;
 end if;
 final_result:=jsonb_build_object('projeto_id',pr.id,'equipamento_id',opening.equipment_id,'fotos_criadas',count_photos,'updated_existing',true,'idempotent_replay',false);
 snapshot:=params->'p_receiving_draft_snapshot';
 update rm_private.receiving_drafts set payload=snapshot,revision=revision+1,state='finalized',result=final_result,finalized_at=clock_timestamp(),updated_at=clock_timestamp() where id=p_submission;
 if not found then
  insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,payload,last_save_id,state,result,finalized_at)
   values(p_submission,auth.uid(),d.operator_id,snapshot,coalesce(nullif(params->>'p_receiving_draft_save_id','')::uuid,p_submission),'finalized',final_result,clock_timestamp());end if;
 insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result)
  values(p_submission,auth.uid(),d.operator_id,'rm_submit_recebimento_v1',params,final_result);
 return final_result;
end $$;
revoke all on function rm_private.finalize_receiving_opening_v1(uuid,jsonb,text) from public,anon,authenticated,service_role;

-- Preserve the public gateway and its delegated OID. Inspect the binding AFTER
-- the existing submission lock, so opening and legacy finalization cannot race
-- between an unlocked existence check and the installed receipt transaction.
do $$ declare definition text; needle text;begin
 definition:=pg_get_functiondef('rm_private.mobile_mutate_before_execution_v1(uuid,text,jsonb,text)'::regprocedure);
 needle:='  select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_client_submission_id;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected execution gateway boundary';end if;
 execute replace(definition,needle,$patch$  if exists(select 1 from rm_private.receiving_openings where client_submission_id=p_client_submission_id) then
    if p_rpc_name is distinct from 'rm_submit_recebimento_v1' then
      raise exception 'Este protocolo está reservado ao recebimento original.' using errcode='22023';end if;
    return rm_private.finalize_receiving_opening_v1(p_client_submission_id,p_params,p_operator_token);end if;
$patch$||needle);
 definition:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 needle:=' if receipt.client_submission_id is not null then';
 if strpos(definition,needle)=0 then raise exception 'Unexpected execution receipt boundary';end if;
 execute replace(definition,needle,$patch$ if exists(select 1 from rm_private.receiving_openings where client_submission_id=p_client_submission_id) then
  raise exception 'Este protocolo está reservado ao recebimento original.' using errcode='22023';end if;
$patch$||needle);
 definition:=pg_get_functiondef('public.rm_receiving_draft_v1(text,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 needle:='select * into item from rm_private.receiving_drafts where id=p_draft_id for update;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected receiving draft boundary';end if;
 execute replace(definition,needle,$patch$if exists(select 1 from rm_private.receiving_openings where client_submission_id=p_draft_id) then
  raise exception 'A abertura já foi solicitada. O protocolo e seus anexos foram preservados para envio.' using errcode='PT409';end if;
 select * into item from rm_private.receiving_drafts where id=p_draft_id for update;$patch$);
 -- Receiving captures without a cell/template are intake evidence, not a
 -- copied route. Classification can initialize the existing one-time snapshot.
 definition:=pg_get_functiondef('rm_private.project_route_state_v1(uuid)'::regprocedure);
 needle:='or exists(select 1 from public.rm_fotos f where f.projeto_id=p_project)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected project route evidence boundary';end if;
 execute replace(definition,needle,'or exists(select 1 from public.rm_fotos f where f.projeto_id=p_project and not coalesce(f.etapa=''recebimento'' and f.celula_id is null and f.celula_projeto_id is null and f.celula_tipo_equipamento_id is null,false))');
end $$;
notify pgrst,'reload schema';
commit;

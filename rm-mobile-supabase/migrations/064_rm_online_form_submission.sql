begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';

-- Share the existing inspection transaction. Only the native entry point
-- performs legacy draft cleanup and queues a Bubble delivery.
do $extract$
declare
  source text := pg_get_functiondef('public.rm_submit_form_inspection_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb)'::regprocedure);
  legacy_start text := '  -- 5. Remove rascunhos temporários';
  legacy_end text := '  return jsonb_build_object(';
  start_at integer;
  end_at integer;
begin
  start_at := strpos(source,legacy_start);
  end_at := start_at + strpos(substr(source,start_at),legacy_end) - 1;
  if start_at <= 0 or end_at <= start_at
    or array_length(string_to_array(source,'p_respostas jsonb DEFAULT ''[]''::jsonb)'),1) is distinct from 2
    or array_length(string_to_array(source,'FUNCTION public.rm_submit_form_inspection_v1('),1) is distinct from 2 then
    raise exception 'Unexpected inspection source';
  end if;
  source := substr(source,1,start_at-1) || '  if p_legacy_effects then' || chr(10)
    || substr(source,start_at,end_at-start_at) || '  end if;' || chr(10) || substr(source,end_at);
  source := replace(source,'FUNCTION public.rm_submit_form_inspection_v1(','FUNCTION rm_private.submit_form_inspection_core_v1(');
  execute replace(source,'p_respostas jsonb DEFAULT ''[]''::jsonb)','p_respostas jsonb DEFAULT ''[]''::jsonb, p_legacy_effects boolean DEFAULT true)');
end
$extract$;

revoke all on function rm_private.submit_form_inspection_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb,boolean)
  from public,anon,authenticated,service_role;

create or replace function public.rm_submit_form_inspection_v1(
  p_client_submission_id uuid, p_projeto_id uuid, p_celula_id uuid, p_form_id uuid, p_operador_id uuid,
  p_tablet_user_id uuid default null, p_tempo_de_vida integer default 0, p_respostas jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return rm_private.submit_form_inspection_core_v1(p_client_submission_id,p_projeto_id,p_celula_id,p_form_id,
    p_operador_id,p_tablet_user_id,p_tempo_de_vida,p_respostas,true);
end;
$$;

create function rm_private.online_form_edition_v1(p_form jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'version',encode(sha256(convert_to(jsonb_build_array(p_form->'form',p_form->'questions',m.details)::text,'UTF8')),'hex'),
    'dateIntervals',m.intervals)
  from (
    select coalesce(jsonb_agg(jsonb_build_array(q.id,q.subtipo,q.dimensoes,q.tag) order by q.id),'[]'::jsonb) details,
           coalesce(jsonb_agg(q.id order by q.id) filter (where q.tipo='data' and q.subtipo='intervalo_de_datas'),'[]'::jsonb) intervals
    from public.rm_questoes q where q.form_id=(p_form->'form'->>'id')::uuid
  ) m
  where p_form->>'kind'='form';
$$;

create function public.rm_online_operation_form_entry_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text, p_workshop_context jsonb,
  p_cell_id uuid, p_project_id uuid, p_form_id uuid
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare form jsonb;
begin
  form := public.rm_online_operation_form_read_v1(p_auth_user_id,p_session_id,p_operator_token,p_workshop_context,p_cell_id,p_project_id,p_form_id);
  -- The review queue for this pilot is in BMA. Other offices retain consultation.
  if form is null or p_workshop_context->'workshop'->>'code' is distinct from 'BMA' then return form; end if;
  return form || jsonb_build_object('edition',rm_private.online_form_edition_v1(form));
end;
$$;

-- Build the shared mobile inspection payload from typed web values and the
-- locked model. Choice labels, question snapshots and authors are server data.
create function rm_private.online_form_answers_v1(p_form uuid, p_answers jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  q public.rm_questoes%rowtype;
  value jsonb;
  answer jsonb;
  answers jsonb := '[]'::jsonb;
  options jsonb;
  labels jsonb;
  first_date text;
  last_date text;
  is_interval boolean;
begin
  if jsonb_typeof(p_answers) is distinct from 'object' or octet_length(p_answers::text) > 550000
    or p_answers = '{}'::jsonb then
    raise exception using errcode='22023',message='Respostas inválidas.';
  end if;
  if (select count(*) from jsonb_object_keys(p_answers)) > 1000 or exists(
    select 1 from jsonb_object_keys(p_answers) k
    where not exists(select 1 from public.rm_questoes r where r.form_id=p_form and r.id::text=k)
  ) then raise exception using errcode='22023',message='Questão inválida.'; end if;

  for q in select * from public.rm_questoes where form_id=p_form order by indice,id loop
    value := p_answers->q.id::text;
    if q.tipo not in ('texto_curto','texto_longo','numero','data','escolha__nica','lista_suspensa','caixas_de_sele__o','lista_multi_sele__o') then
      if value is not null or (q.obrigatorio and q.tipo<>'subt_tulo') then
        raise exception using errcode='PT422',message='Esta pergunta é preenchida no app mobile.';
      end if;
      continue;
    end if;
    if value is null then continue; end if;

    answer := jsonb_build_object('questao_id',q.id);
    if value='true'::jsonb then
      answer := answer || '{"resposta":"N/A","is_na":true}'::jsonb;
    elsif q.tipo in ('texto_curto','texto_longo','numero') and jsonb_typeof(value)='string'
      and char_length(value#>>'{}') between 1 and 4000 and btrim(value#>>'{}')<>'' and value#>>'{}'<>'N/A' then
      answer := answer || jsonb_build_object('resposta',value#>>'{}');
    elsif q.tipo='data' and jsonb_typeof(value)='object' then
      first_date := value->>'inicio';
      last_date := value->>'fim';
      is_interval := q.subtipo is not distinct from 'intervalo_de_datas';
      if (select array_agg(k order by k) from jsonb_object_keys(value) k) is distinct from
        (case when is_interval then array['fim','inicio'] else array['inicio'] end)
        or jsonb_typeof(value->'inicio') is distinct from 'string' or first_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        or (is_interval and (jsonb_typeof(value->'fim') is distinct from 'string' or last_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          or last_date::date<first_date::date)) then
        raise exception using errcode='22023',message='Data inválida.';
      end if;
      -- Dates are calendar days in the workshop timezone, as in the native UI.
      answer := answer || jsonb_build_object('date_inicio',first_date::date::timestamp at time zone 'America/Sao_Paulo',
        'data_fim',last_date::date::timestamp at time zone 'America/Sao_Paulo');
    elsif q.tipo in ('escolha__nica','lista_suspensa','caixas_de_sele__o','lista_multi_sele__o') and jsonb_typeof(value)='array' then
      select jsonb_agg(i.id order by i.indice,i.id),jsonb_agg(i.descricao order by i.indice,i.id) into options,labels
      from public.rm_itens_questoes i where i.questao_id=q.id and (i.form_id is null or i.form_id=q.form_id)
        and value ? i.id::text;
      if options is null or jsonb_array_length(options)<>jsonb_array_length(value)
        or (q.tipo in ('escolha__nica','lista_suspensa') and jsonb_array_length(options)<>1) then
        raise exception using errcode='22023',message='Opção inválida.';
      end if;
      answer := answer || jsonb_build_object('itens_questoes_ids',options,'itens',labels,
        'resposta',case when q.tipo in ('escolha__nica','lista_suspensa') then labels->>0 end);
    else
      raise exception using errcode='22023',message='Resposta incompatível com a pergunta.';
    end if;
    answers := answers || jsonb_build_array(answer);
  end loop;
  return rm_private.validate_form_answers(p_form,answers);
end;
$$;

create function public.rm_online_operation_submit_form_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text, p_workshop_context jsonb,
  p_cell_id uuid, p_project_id uuid, p_form_id uuid, p_protocol uuid, p_version text, p_answers jsonb
) returns jsonb language plpgsql security definer set search_path = '' set lock_timeout = '4s' as $$
declare
  delegation rm_private.operator_delegations%rowtype;
  identity record;
  office uuid;
  form jsonb;
  ready jsonb;
  intention jsonb;
  result jsonb;
  receipt rm_private.mobile_mutation_receipts%rowtype;
begin
  if p_protocol is null or p_cell_id is null or p_project_id is null or p_form_id is null
    or p_version is null or p_version !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_answers) is distinct from 'object'
    or octet_length(p_answers::text)>550000 then
    raise exception using errcode='22023',message='Envio inválido.';
  end if;
  select * into identity from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token);
  office := rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,identity.operator_subject);
  if office is null or p_workshop_context->'workshop'->>'code' is distinct from 'BMA' then
    raise exception using errcode='42501',message='Envio indisponível para esta oficina.';
  end if;
  form := rm_private.online_operation_projection_v1(identity.operator_subject,office,p_cell_id,p_project_id,1,null);
  if not coalesce((form->'forms') @> jsonb_build_array(jsonb_build_object('id',p_form_id)),false) then
    raise exception using errcode='42501',message='Formulário indisponível nesta célula.';
  end if;

  -- Match the native protocol/parent order, including concurrent retries.
  perform pg_advisory_xact_lock(hashtextextended(p_protocol::text,0));
  perform pg_advisory_xact_lock(hashtextextended(p_project_id::text,11));
  perform 1 from public.rm_projetos where id=p_project_id for update;
  perform 1 from public.rm_celulas_projeto where projeto_id=p_project_id and celula_id=p_cell_id for share;
  perform 1 from auth.sessions where id=p_session_id and user_id=p_auth_user_id for share;
  select * into delegation from rm_private.operator_delegations d
    where d.token_hash=extensions.digest(p_operator_token,'sha256') and d.auth_user_id=p_auth_user_id for share;
  perform 1 from public.rm_users where id in(delegation.tablet_user_id,delegation.operator_id) order by id for share;
  perform 1 from public.rm_tablet_celula_users where identidade_id=delegation.operator_id and celula_id=p_cell_id order by id for share;
  perform 1 from public.rm_forms where id=p_form_id for update;
  perform 1 from public.rm_questoes where form_id=p_form_id order by id for update;
  perform 1 from public.rm_itens_questoes i join public.rm_questoes q on q.id=i.questao_id
    where q.form_id=p_form_id order by i.id for share of i;

  select * into identity from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token);
  if identity.operator_subject is distinct from delegation.operator_id or identity.operator_subject is null
    or identity.expires_at<=clock_timestamp() then
    raise exception using errcode='28000',message='Identificação operacional expirada.';
  end if;
  if office is distinct from rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,delegation.operator_id)
    or (p_workshop_context->>'expires_at')::timestamptz<=clock_timestamp()
    or (p_workshop_context->>'issued_at')::timestamptz+interval '15 seconds'<=clock_timestamp() then
    raise exception using errcode='PT503',message='Confirme novamente a oficina e reenvie o mesmo protocolo.';
  end if;
  form := rm_private.online_operation_form_v1(
    rm_private.online_operation_projection_v1(delegation.operator_id,office,p_cell_id,p_project_id,1,null),p_form_id);
  if form is null then raise exception using errcode='42501',message='Formulário indisponível nesta célula.'; end if;

  intention := jsonb_build_object('origem_operacional_web',true,'workshop_id',office,'p_projeto_id',p_project_id,
    'p_celula_id',p_cell_id,'p_form_id',p_form_id,'version',p_version,'answers',p_answers);
  select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_protocol;
  if found then
    if receipt.auth_user_id is distinct from p_auth_user_id or receipt.operator_id is distinct from delegation.operator_id
      or receipt.rpc_name is distinct from 'rm_submit_form_inspection_v1' or receipt.params is distinct from intention
      or receipt.result is null then
      raise exception using errcode='PT409',message='Protocolo já utilizado.';
    end if;
    return receipt.result || '{"idempotent_replay":true}'::jsonb;
  end if;

  if rm_private.online_form_edition_v1(form)->>'version' is distinct from p_version then
    raise exception using errcode='PT412',message='O formulário foi alterado. Abra a versão atual.';
  end if;
  ready := rm_private.online_form_answers_v1(p_form_id,p_answers);
  if identity.expires_at<=clock_timestamp() or (p_workshop_context->>'expires_at')::timestamptz<=clock_timestamp()
    or (p_workshop_context->>'issued_at')::timestamptz+interval '15 seconds'<=clock_timestamp() then
    raise exception using errcode='PT503',message='Confirme novamente a oficina e reenvie o mesmo protocolo.';
  end if;
  result := rm_private.submit_form_inspection_core_v1(p_protocol,p_project_id,p_cell_id,p_form_id,
    delegation.operator_id,delegation.tablet_user_id,0,ready,false);
  if result->'idempotent_replay' is distinct from 'false'::jsonb then
    raise exception using errcode='PT409',message='Protocolo já utilizado.';
  end if;
  result := result || '{"origem_operacional_web":true}'::jsonb;
  insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result)
    values(p_protocol,p_auth_user_id,delegation.operator_id,'rm_submit_form_inspection_v1',intention,result);
  return result;
end;
$$;

revoke all on function rm_private.online_form_edition_v1(jsonb),rm_private.online_form_answers_v1(uuid,jsonb),
  public.rm_online_operation_form_entry_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid),
  public.rm_online_operation_submit_form_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid,uuid,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.rm_online_operation_form_entry_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid),
  public.rm_online_operation_submit_form_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid,uuid,text,jsonb) to service_role;

-- Existing project history identifies the web-origin receipt while preserving
-- the original event identifiers and source values for native records.
do $origin$
declare
  source text := pg_get_functiondef('rm_private.project_audit_events_v1(uuid,text,text[])'::regprocedure);
  event_key text := $sql$'mobile:'||m.client_submission_id||':form'$sql$;
  event_origin text := $sql$r.id,r.celula_id,a.id,m.operator_id,m.created_at,'mobile',false,$sql$;
  origin_expr text := $sql$case when m.result->'origem_operacional_web'='true'::jsonb then 'web' else 'mobile' end$sql$;
begin
  if array_length(string_to_array(source,event_key),1) is distinct from 2
    or array_length(string_to_array(source,event_origin),1) is distinct from 2 then
    raise exception 'Unexpected project audit source';
  end if;
  execute replace(replace(source,event_key,'('||origin_expr||')||'':''||m.client_submission_id||'':form'''),
    event_origin,'r.id,r.celula_id,a.id,m.operator_id,m.created_at,'||origin_expr||',false,');
end;
$origin$;

notify pgrst,'reload schema';
commit;

-- Additive hardening for the native client. Apply AFTER 001..005.
-- Legacy RPC signatures remain available to service_role; devices use the gateway.
begin;

create schema if not exists extensions;
-- 003 explicitly calls extensions.crypt. A fresh 001 may have installed it in public.
do $$ begin
  if exists (select 1 from pg_extension e join pg_namespace n on n.oid=e.extnamespace
             where e.extname='pgcrypto' and n.nspname <> 'extensions') then
    alter extension pgcrypto set schema extensions;
  end if;
end $$;

create table rm_private.operator_delegations (
  token_hash bytea primary key,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  tablet_user_id uuid not null references public.rm_users(id) on delete cascade,
  operator_id uuid not null references public.rm_users(id) on delete cascade,
  expires_at timestamptz not null,
  revoked boolean not null default false,
  created_at timestamptz not null default clock_timestamp()
);
create index on rm_private.operator_delegations(auth_user_id, operator_id);
create table rm_private.operator_login_limits (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  failures integer not null default 0,
  blocked_until timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);
create table rm_private.mobile_mutation_receipts (
  client_submission_id uuid primary key,
  auth_user_id uuid not null references auth.users(id),
  operator_id uuid not null references public.rm_users(id),
  rpc_name text not null,
  params jsonb not null,
  result jsonb,
  created_at timestamptz not null default clock_timestamp()
);
revoke all on all tables in schema rm_private from public, anon, authenticated;

-- Read identity is ALWAYS the linked authenticated device account. A client cannot
-- become a different operator by changing a request parameter or a custom claim.
create or replace function rm_private.current_rm_user_id() returns uuid
language sql stable security definer set search_path='' as $$
  select id from public.rm_users where auth_user_id=auth.uid() and status='ativo' limit 1;
$$;
grant usage on schema rm_private to authenticated;
grant execute on function rm_private.current_rm_user_id(), rm_private.is_rm_authenticated(),
  rm_private.is_rm_admin_or_pcp() to authenticated;

alter function public.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text) set schema rm_private;
create function public.rm_authenticate_operator_v1(
  p_matricula text, p_palavra_chave text, p_tablet_user_id uuid default null,
  p_celula_id uuid default null, p_ip text default null, p_local text default 'rm_mobile'
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_tablet uuid := rm_private.current_rm_user_id();
  v_limit rm_private.operator_login_limits%rowtype;
  v_result jsonb;
  v_token text;
  v_expires timestamptz := clock_timestamp() + interval '7 days';
begin
  if auth.uid() is null or v_tablet is null then
    raise exception 'Entre com uma conta ativa de supervisor/dispositivo.' using errcode='42501';
  end if;
  if p_tablet_user_id is not null and p_tablet_user_id<>v_tablet then
    raise exception 'Conta de dispositivo divergente.' using errcode='42501';
  end if;
  insert into rm_private.operator_login_limits(auth_user_id) values(auth.uid()) on conflict do nothing;
  select * into v_limit from rm_private.operator_login_limits where auth_user_id=auth.uid() for update;
  if v_limit.blocked_until > clock_timestamp() then
    return jsonb_build_object('authenticated',false,'error','Muitas tentativas. Aguarde para tentar novamente.',
      'retry_after_seconds',ceil(extract(epoch from v_limit.blocked_until-clock_timestamp())));
  end if;
  -- Catch legacy exceptions in a subtransaction so the throttle write is committed.
  begin
    v_result := rm_private.rm_authenticate_operator_v1(p_matricula,p_palavra_chave,v_tablet,p_celula_id,p_ip,p_local);
  exception when invalid_password or invalid_authorization_specification then
    update rm_private.operator_login_limits
      set failures=case when updated_at < clock_timestamp()-interval '15 minutes' then 1 else failures+1 end,
          blocked_until=case when failures>=4 and updated_at>=clock_timestamp()-interval '15 minutes'
            then clock_timestamp()+interval '15 minutes' else null end,
          updated_at=clock_timestamp()
      where auth_user_id=auth.uid();
    return jsonb_build_object('authenticated',false,'error','Matrícula ou palavra-chave inválida.');
  end;
  v_token := encode(extensions.gen_random_bytes(32),'hex');
  insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
    values(extensions.digest(v_token,'sha256'),auth.uid(),v_tablet,(v_result->>'operador_id')::uuid,v_expires);
  update rm_private.operator_login_limits set failures=0,blocked_until=null,updated_at=clock_timestamp()
    where auth_user_id=auth.uid();
  return v_result || jsonb_build_object('authenticated',true,'operator_token',v_token,'token_expires_at',v_expires);
end $$;

create function rm_private.assert_cell_access(p_tablet uuid,p_cell uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if p_cell is null or not exists (
    select 1 from public.rm_users u where u.id=p_tablet and u.status='ativo' and (
      u.perfil='administrador' or exists(select 1 from public.rm_tablet_celula_users t
                                       where t.usuario_id=p_tablet and t.celula_id=p_cell))) then
    raise exception 'Dispositivo sem vínculo com esta célula.' using errcode='42501';
  end if;
end $$;

-- Validate the server's definitions, never the types/required flags sent by a client.
create function rm_private.validate_form_answers(p_form uuid,p_answers jsonb,p_all boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.rm_questoes%rowtype; a jsonb; out_answers jsonb := '[]'; v_na boolean; v_present boolean;
begin
  if jsonb_typeof(p_answers)<>'array' then raise exception 'Respostas devem ser uma lista.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_answers) x
    left join public.rm_questoes definition on definition.id=(x->>'questao_id')::uuid and definition.form_id=p_form where definition.id is null) then
    raise exception 'Questão fora do formulário.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_answers) x group by x->>'questao_id' having count(*)>1) then
    raise exception 'Questão repetida no envio.' using errcode='22023';
  end if;
  for q in select * from public.rm_questoes where form_id=p_form order by indice loop
    select value into a from jsonb_array_elements(p_answers) where value->>'questao_id'=q.id::text;
    if a is null then
      if p_all and q.obrigatorio and q.tipo<>'subt_tulo' then
        raise exception 'Questão obrigatória sem resposta: %',q.enunciado using errcode='22023';
      end if;
      continue;
    end if;
    v_na := coalesce(a->>'is_na','false') in ('true','1') or a->>'resposta'='N/A';
    v_present := case q.tipo
      when 'subt_tulo' then true
      when 'foto' then coalesce(jsonb_array_length(a->'fotos_urls'),0)>0
      when 'foto_antes_depois' then coalesce(jsonb_array_length(a->'fotos_urls'),0)=2
      when 'assinatura' then nullif(btrim(a->>'assinatura_url'),'') is not null
      when 'data' then nullif(a->>'date_inicio','') is not null and
        (q.subtipo is distinct from 'intervalo_de_datas' or nullif(a->>'data_fim','') is not null)
      when 'hora' then nullif(a->>'hora','') is not null and
        (q.subtipo is distinct from 'intervalo_de_hor_rios' or
          (nullif(a->>'date_inicio','') is not null and nullif(a->>'data_fim','') is not null))
      when 'caixas_de_sele__o' then coalesce(jsonb_array_length(a->'itens'),0)>0
      when 'lista_multi_sele__o' then coalesce(jsonb_array_length(a->'itens'),0)>0
      else nullif(btrim(a->>'resposta'),'') is not null end;
    if q.obrigatorio and not coalesce(v_na,false) and not coalesce(v_present,false) then
      raise exception 'Questão obrigatória sem resposta: %',q.enunciado using errcode='22023';
    end if;
    if q.tipo='foto_antes_depois' and coalesce(jsonb_array_length(a->'fotos_urls'),0)>0
      and jsonb_array_length(a->'fotos_urls')<>2 then
      raise exception 'Informe exatamente uma foto antes e uma depois.' using errcode='22023';
    end if;
    if q.subtipo in ('intervalo_de_datas','intervalo_de_hor_rios') and
      (nullif(a->>'date_inicio','') is not null or nullif(a->>'data_fim','') is not null or nullif(a->>'hora','') is not null)
      and (nullif(a->>'date_inicio','') is null or nullif(a->>'data_fim','') is null) then
      raise exception 'Informe início e fim do intervalo.' using errcode='22023';
    end if;
    if q.tipo='numero' and nullif(a->>'resposta','') is not null and not coalesce(v_na,false)
      and replace(a->>'resposta',',','.') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then
      raise exception 'Número inválido: %',q.enunciado using errcode='22023';
    end if;
    if q.subtipo in ('intervalo_de_datas','intervalo_de_hor_rios') and
      nullif(a->>'data_fim','')::timestamptz < nullif(a->>'date_inicio','')::timestamptz then
      raise exception 'Fim do intervalo anterior ao início.' using errcode='22023';
    end if;
    if exists(select 1 from jsonb_array_elements_text(coalesce(a->'itens_questoes_ids','[]')) x
      where not exists(select 1 from public.rm_itens_questoes i where i.id=x::uuid and i.questao_id=q.id)) then
      raise exception 'Opção não pertence à questão.' using errcode='22023';
    end if;
    if exists(select 1 from jsonb_array_elements_text(coalesce(a->'fotos_urls','[]')) x
      where x !~ '^https://') or (nullif(a->>'assinatura_url','') is not null and a->>'assinatura_url' !~ '^https://') then
      raise exception 'Envie as mídias antes do formulário.' using errcode='22023';
    end if;
    a := a || jsonb_build_object('tipo',q.tipo,'indice',q.indice,'enunciado',q.enunciado,'tag',q.tag,'dimensoes',q.dimensoes);
    if v_na and nullif(a->>'resposta','') is null then a:=a||jsonb_build_object('resposta','N/A'); end if;
    out_answers := out_answers || jsonb_build_array(a);
  end loop;
  return out_answers;
end $$;

-- Revision must clear explicitly supplied nulls, update selection IDs and only
-- touch the answers returned by engineering. Legacy 003 used COALESCE (lost clears).
create or replace function public.rm_submit_form_revision_v1(
  p_registro_formulario_id uuid,p_operador_id uuid,p_respostas_corrigidas jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.rm_registros_formulario%rowtype; a jsonb; v_count integer:=0; v_pending integer;
begin
  select * into r from public.rm_registros_formulario where id=p_registro_formulario_id for update;
  if not found or r.status<>'direcionado' then raise exception 'Formulário não está em revisão.' using errcode='22023'; end if;
  p_respostas_corrigidas:=rm_private.validate_form_answers(r.form_id,p_respostas_corrigidas,false);
  for a in select value from jsonb_array_elements(p_respostas_corrigidas) loop
    update public.rm_respostas set
      resposta=case when a?'resposta' then a->>'resposta' else resposta end,
      itens=case when a?'itens' then array(select jsonb_array_elements_text(a->'itens')) else itens end,
      itens_questoes_ids=case when a?'itens_questoes_ids' then array(select jsonb_array_elements_text(a->'itens_questoes_ids'))::uuid[] else itens_questoes_ids end,
      fotos_urls=case when a?'fotos_urls' then array(select jsonb_array_elements_text(a->'fotos_urls')) else fotos_urls end,
      assinatura_url=case when a?'assinatura_url' then a->>'assinatura_url' else assinatura_url end,
      date_inicio=case when a?'date_inicio' then nullif(a->>'date_inicio','')::timestamptz else date_inicio end,
      data_fim=case when a?'data_fim' then nullif(a->>'data_fim','')::timestamptz else data_fim end,
      hora=case when a?'hora' then nullif(a->>'hora','')::timestamptz else hora end,
      revisar=false,sync_source='supabase'
    where registro_formulario_id=r.id and questao_id=(a->>'questao_id')::uuid and revisar=true;
    if not found then raise exception 'Resposta não foi devolvida para correção.' using errcode='22023'; end if;
    v_count:=v_count+1;
  end loop;
  select count(*) into v_pending from public.rm_respostas where registro_formulario_id=r.id and revisar;
  if v_pending=0 then update public.rm_registros_formulario set status='em_an_lise',revisado=true,
    data_revisao=clock_timestamp(),user_revisao_id=p_operador_id,sync_source='supabase' where id=r.id; end if;
  perform rm_private.enqueue_sync_event('bubble_data_api','Registro_Formulario_Revision','update',r.id,r.bubble_id,
    jsonb_build_object('registro_formulario_id',r.id,'operador_id',p_operador_id,'corrigidas',v_count,'pendentes_revisao',v_pending));
  return jsonb_build_object('registro_formulario_id',r.id,'respostas_corrigidas',v_count,
    'pendentes_revisao',v_pending,'novo_status',case when v_pending=0 then 'em_an_lise' else 'direcionado' end);
end $$;

-- Existing project QR check-in uses the same payload and a new optional project ID.
-- Only known equipment columns can be patched; identifiers and sync metadata are fixed.
create function rm_private.update_recebimento_v1(p_project uuid,p_operator uuid,p_params jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare pr public.rm_projetos%rowtype; eq uuid; eq_data jsonb; col text; f jsonb; photo_count integer:=0;
begin
  select * into pr from public.rm_projetos where id=p_project for update;
  if not found then raise exception 'Projeto do QR Code não encontrado.' using errcode='P0002'; end if;
  if nullif(btrim(p_params->>'p_numero_projeto'),'') is null then
    raise exception 'Número do projeto é obrigatório.' using errcode='22023'; end if;
  update public.rm_projetos set numero=btrim(p_params->>'p_numero_projeto'),
    nome=coalesce(nullif(btrim(p_params->>'p_nome_projeto'),''),nome),
    cliente_id=(p_params->>'p_cliente_id')::uuid,
    cliente_nome_exportacao=(select nome from public.rm_clientes where id=(p_params->>'p_cliente_id')::uuid),
    tipo_equipamento_id=(p_params->>'p_tipo_equipamento_id')::uuid,
    contato=case when p_params?'p_contato' then p_params->>'p_contato' else contato end,
    proprietario=case when p_params?'p_proprietario' then p_params->>'p_proprietario' else proprietario end,
    eventualidades=case when p_params?'p_eventualidades' then p_params->>'p_eventualidades' else eventualidades end,
    chegada_do_equipamento=coalesce(nullif(p_params->>'p_chegada_equipamento','')::timestamptz,chegada_do_equipamento,clock_timestamp()),
    sync_source='supabase'
  where id=p_project;
  select id into eq from public.rm_equipamentos where projeto_id=p_project order by created_at limit 1 for update;
  if not found then insert into public.rm_equipamentos(projeto_id,tipo_equipamento_id)
    values(p_project,(p_params->>'p_tipo_equipamento_id')::uuid) returning id into eq; end if;
  update public.rm_projetos set equipamento_id=eq where id=p_project;
  eq_data:=coalesce(p_params->'p_equipamento','{}');
  foreach col in array array['placa_motor','desmontar_para_orcar','ensaiar_antes_desmontar','teste_intermediario',
    'embarcacao','fabricante','modelo','numero_serie','descricao','certificado','norma','potencia','rotacao',
    'tensao_estator','tipo_tensao','corrente_estator','corrente_partida','frequencia','classe_isolamento',
    'grau_ip','forma','regime','peso','ligacao','componentes','fp','fs','numero_cabos'] loop
    if eq_data?col then
      if eq_data->>col='' and col in ('placa_motor','desmontar_para_orcar','ensaiar_antes_desmontar','teste_intermediario','fp','fs','numero_cabos') then
        eq_data:=jsonb_set(eq_data,array[col],'null');
      end if;
      execute format('update public.rm_equipamentos set %I=(jsonb_populate_record(null::public.rm_equipamentos,$1)).%I where id=$2',col,col)
        using jsonb_build_object(col,eq_data->col),eq;
    end if;
  end loop;
  update public.rm_equipamentos set tipo_equipamento_id=(p_params->>'p_tipo_equipamento_id')::uuid,sync_source='supabase' where id=eq;
  for f in select value from jsonb_array_elements(coalesce(p_params->'p_fotos_recebimento','[]')) loop
    if not exists(select 1 from public.rm_fotos where projeto_id=p_project and foto_url=f->>'foto_url') then
      insert into public.rm_fotos(projeto_id,etapa,categoria_foto,tipo_recebimento,identificador_foto_key,titulo,descricao,
        legenda,foto_url,numero,numero_foto_complementar,created_by_user_id,modified_by_id,sync_source)
      values(p_project,'recebimento',coalesce(nullif(f->>'categoria_foto','')::public.rm_categoria_foto_enum,'obrigat_ria'),
        nullif(f->>'tipo_recebimento','')::public.rm_tipo_foto_recebimento_enum,f->>'identificador_foto_key',
        f->>'titulo',f->>'descricao',f->>'legenda',f->>'foto_url',nullif(f->>'numero','')::integer,
        nullif(f->>'numero_foto_complementar','')::integer,p_operator,p_operator,'supabase');
      photo_count:=photo_count+1;
    end if;
  end loop;
  perform rm_private.enqueue_sync_event('bubble_data_api','Recebimento_Bundle','update',p_project,pr.bubble_id,
    jsonb_build_object('projeto_id',p_project,'equipamento_id',eq,'numero_projeto',p_params->>'p_numero_projeto'));
  perform rm_private.enqueue_sync_event('n8n_webhook','enviar_email_orcamento','trigger_webhook',p_project,pr.bubble_id,
    jsonb_build_object('webhook_url','https://n8n.miconnect.app.br/webhook/f3e0bb34-4090-49b0-a11d-2ed4fb7bd7ab',
      'body',jsonb_build_object('num_proj',p_params->>'p_numero_projeto',
        'cliente',(select nome from public.rm_clientes where id=(p_params->>'p_cliente_id')::uuid),
        'data',to_char(coalesce(nullif(p_params->>'p_chegada_equipamento','')::timestamptz,clock_timestamp()),'DD/MM/YYYY'),
        'responsavel',(select nome from public.rm_users where id=p_operator),
        'tipo_motor',(select nome from public.rm_tipos_equipamento where id=(p_params->>'p_tipo_equipamento_id')::uuid),
        'fabricante',eq_data->>'fabricante','potencia',eq_data->>'potencia','rpm',eq_data->>'rotacao','tensao',eq_data->>'tensao_estator')));
  return jsonb_build_object('projeto_id',p_project,'equipamento_id',eq,'fotos_criadas',photo_count,'updated_existing',true);
end $$;

create function public.rm_mobile_mutate_v1(
  p_client_submission_id uuid,p_rpc_name text,p_params jsonb,p_operator_token text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  d rm_private.operator_delegations%rowtype;
  receipt rm_private.mobile_mutation_receipts%rowtype;
  r public.rm_registros_formulario%rowtype;
  stage public.rm_aprovacoes_etapas%rowtype;
  photo public.rm_fotos%rowtype;
  op public.rm_users%rowtype;
  v_result jsonb; v_params jsonb; v_answers jsonb; v_cell uuid;
begin
  if p_client_submission_id is null or p_params is null or jsonb_typeof(p_params)<>'object' then
    raise exception 'Identificador de envio e parâmetros são obrigatórios.' using errcode='22023'; end if;
  select * into d from rm_private.operator_delegations where
    token_hash=extensions.digest(p_operator_token,'sha256') and auth_user_id=auth.uid() and not revoked;
  if not found or rm_private.current_rm_user_id() is distinct from d.tablet_user_id then
    raise exception 'Identifique novamente o operador neste dispositivo.' using errcode='28000'; end if;
  select * into op from public.rm_users where id=d.operator_id and status='ativo';
  if not found then raise exception 'Operador inativo.' using errcode='28000'; end if;
  if nullif(p_params->>'p_operador_id','')::uuid is not null and (p_params->>'p_operador_id')::uuid<>d.operator_id then
    raise exception 'Identidade do envio divergente.' using errcode='42501'; end if;
  v_params := p_params - 'p_operador_id' - 'p_tablet_user_id' - 'p_client_submission_id';
  -- Serialize concurrent retries before reading the receipt; no duplicate effects
  -- if the network dies between COMMIT and receipt delivery.
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
  select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_client_submission_id;
  if found then
    if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>p_rpc_name or receipt.params<>v_params then
      raise exception 'Identificador de envio já usado com outro conteúdo.' using errcode='22023'; end if;
    return receipt.result || jsonb_build_object('idempotent_replay',true);
  end if;
  if d.expires_at<=clock_timestamp() then raise exception 'Identificação expirada. Identifique o mesmo operador para sincronizar.' using errcode='28000'; end if;

  case p_rpc_name
  when 'rm_submit_recebimento_v1' then
    if nullif(p_params->>'p_cliente_id','') is null or nullif(p_params->>'p_tipo_equipamento_id','') is null then
      raise exception 'Cliente e tipo de equipamento são obrigatórios.' using errcode='22023'; end if;
    if exists(select 1 from jsonb_array_elements(coalesce(p_params->'p_fotos_recebimento','[]')) f where f->>'foto_url' !~ '^https://') then
      raise exception 'Envie as fotos antes do recebimento.' using errcode='22023'; end if;
    if nullif(p_params->>'p_projeto_id','') is not null then
      -- A shared tablet cannot edit arbitrary equipment by submitting a guessed QR.
      -- The creator can finish their own unplanned check-in before cells exist.
      if not exists(select 1 from public.rm_users where id=d.tablet_user_id and perfil='administrador')
        and not exists(select 1 from public.rm_projetos where id=(p_params->>'p_projeto_id')::uuid and created_by_user_id=d.operator_id)
        and not exists(select 1 from public.rm_celulas_projeto cp join public.rm_tablet_celula_users t on t.celula_id=cp.celula_id
          where cp.projeto_id=(p_params->>'p_projeto_id')::uuid and t.usuario_id=d.tablet_user_id) then
        raise exception 'Projeto do QR Code não está disponível neste dispositivo.' using errcode='42501';
      end if;
      v_result:=rm_private.update_recebimento_v1((p_params->>'p_projeto_id')::uuid,d.operator_id,p_params);
    else
      v_result:=public.rm_submit_recebimento_v1(d.operator_id,(p_params->>'p_cliente_id')::uuid,
        (p_params->>'p_tipo_equipamento_id')::uuid,p_params->>'p_numero_projeto',p_params->>'p_nome_projeto',
        nullif(p_params->>'p_chegada_equipamento','')::timestamptz,p_params->>'p_contato',p_params->>'p_proprietario',
        p_params->>'p_eventualidades',coalesce(p_params->'p_equipamento','{}'),coalesce(p_params->'p_fotos_recebimento','[]'));
    end if;
    if nullif(btrim(p_params->>'p_qrcode_value'),'') is not null then
      insert into public.rm_comentarios(projeto_id,cadastrado_por_id,evento,sync_source)
        values((v_result->>'projeto_id')::uuid,d.operator_id,'QR do recebimento: '||left(p_params->>'p_qrcode_value',1000),'supabase');
    end if;
  when 'rm_submit_form_inspection_v1' then
    v_cell:=(p_params->>'p_celula_id')::uuid;
    perform rm_private.assert_cell_access(d.tablet_user_id,v_cell);
    if not exists(select 1 from public.rm_forms where id=(p_params->>'p_form_id')::uuid and ativo) or
      not exists(select 1 from public.rm_celulas_projeto where projeto_id=(p_params->>'p_projeto_id')::uuid
        and celula_id=v_cell and (p_params->>'p_form_id')::uuid=any(forms_ids)) then
      raise exception 'Formulário não está vinculado à célula deste projeto.' using errcode='22023'; end if;
    v_answers:=rm_private.validate_form_answers((p_params->>'p_form_id')::uuid,coalesce(p_params->'p_respostas','[]'));
    v_result:=public.rm_submit_form_inspection_v1(p_client_submission_id,(p_params->>'p_projeto_id')::uuid,
      v_cell,(p_params->>'p_form_id')::uuid,d.operator_id,d.tablet_user_id,
      coalesce((p_params->>'p_tempo_de_vida')::integer,0),v_answers);
  when 'rm_submit_form_revision_v1' then
    select * into r from public.rm_registros_formulario where id=(p_params->>'p_registro_formulario_id')::uuid;
    if not found then raise exception 'Formulário não encontrado.' using errcode='P0002'; end if;
    perform rm_private.assert_cell_access(d.tablet_user_id,r.celula_id);
    v_result:=public.rm_submit_form_revision_v1(r.id,d.operator_id,coalesce(p_params->'p_respostas_corrigidas','[]'));
  when 'rm_record_cell_photo_v1' then
    if nullif(p_params->>'p_foto_id','') is not null then
      select * into photo from public.rm_fotos where id=(p_params->>'p_foto_id')::uuid;
      if not found or photo.projeto_id is null then raise exception 'Slot de projeto não encontrado.' using errcode='P0002'; end if;
      v_cell:=photo.celula_id;
    else
      v_cell:=(p_params->>'p_celula_id')::uuid;
      if not exists(select 1 from public.rm_celulas_projeto where projeto_id=(p_params->>'p_projeto_id')::uuid
        and celula_id=v_cell and (nullif(p_params->>'p_celula_projeto_id','') is null or id=(p_params->>'p_celula_projeto_id')::uuid)) then
        raise exception 'Célula de projeto não encontrada.' using errcode='P0002'; end if;
    end if;
    perform rm_private.assert_cell_access(d.tablet_user_id,v_cell);
    if coalesce(p_params->>'p_foto_url','') !~ '^https://' then raise exception 'Envie a foto antes de registrar.' using errcode='22023'; end if;
    v_result:=public.rm_record_cell_photo_v1(d.operator_id,nullif(p_params->>'p_foto_id','')::uuid,
      nullif(p_params->>'p_projeto_id','')::uuid,v_cell,nullif(p_params->>'p_celula_projeto_id','')::uuid,
      p_params->>'p_foto_url',p_params->>'p_legenda',p_params->>'p_titulo',
      coalesce(nullif(p_params->>'p_categoria_foto','')::public.rm_categoria_foto_enum,'complementar'));
  when 'rm_transition_stage_approval_v1' then
    select * into stage from public.rm_aprovacoes_etapas where id=(p_params->>'p_aprovacao_etapa_id')::uuid for update;
    if not found or stage.projeto_id is null then raise exception 'Etapa de projeto não encontrada.' using errcode='P0002'; end if;
    perform rm_private.assert_cell_access(d.tablet_user_id,stage.celula_origem_id);
    if not coalesce((op.perfil='administrador' or stage.aprovador_id=op.id or op.id=any(stage.aprovadores_ids)
      or (p_params->>'p_acao'='retornar' and op.id=any(stage.aprovadores_retorno_ids))
      or (stage.aprovador_id is null and cardinality(stage.aprovadores_ids)=0 and
        op.perfil_assinante && array['aprovador','aprovador_supervis_o']::public.rm_perfil_assinante_enum[])),false) then
      raise exception 'Operador sem permissão de aprovação nesta etapa.' using errcode='42501'; end if;
    if p_params->>'p_acao'='retornar' and nullif(btrim(p_params->>'p_observacao'),'') is null then
      raise exception 'Informe o motivo do retorno.' using errcode='22023'; end if;
    v_result:=public.rm_transition_stage_approval_v1(stage.id,d.operator_id,p_params->>'p_acao',p_params->>'p_observacao');
  else raise exception 'RPC não permitida para o aplicativo.' using errcode='42501';
  end case;
  insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result)
    values(p_client_submission_id,auth.uid(),d.operator_id,p_rpc_name,v_params,v_result);
  return v_result;
end $$;

-- Stop bypassing delegation/idempotency by calling the legacy SECURITY DEFINER RPCs.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('rm_submit_recebimento_v1','rm_materialize_project_cells_v1',
      'rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_transition_stage_approval_v1','rm_record_cell_photo_v1') loop
    execute format('revoke all on function %s from public, anon, authenticated',f.signature);
    execute format('grant execute on function %s to service_role',f.signature);
  end loop;
end $$;
revoke all on all functions in schema rm_private from public,anon,authenticated;
grant execute on function rm_private.current_rm_user_id(),rm_private.is_rm_authenticated(),rm_private.is_rm_admin_or_pcp() to authenticated;
revoke all on function public.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text),
  public.rm_mobile_mutate_v1(uuid,text,jsonb,text) from public,anon;
grant execute on function public.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text),
  public.rm_mobile_mutate_v1(uuid,text,jsonb,text) to authenticated;

-- RLS does not itself grant privileges. Explicit grants are needed on fresh projects.
grant select on public.rm_option_sets,public.rm_users,public.rm_clientes,public.rm_tipos_equipamento,
  public.rm_celulas,public.rm_tablet_celula_users,public.rm_celula_tipos_equipamento,
  public.rm_celula_form_tipos_equipamento,public.rm_forms,public.rm_questoes,public.rm_itens_questoes,
  public.rm_projetos,public.rm_equipamentos,public.rm_celulas_projeto,public.rm_fotos,
  public.rm_registros_formulario,public.rm_respostas,public.rm_aprovacoes_etapas to authenticated;
revoke insert,update,delete on public.rm_fotos,public.rm_registros_formulario,public.rm_respostas,
  public.rm_aprovacoes_etapas,public.rm_projetos,public.rm_equipamentos,public.rm_celulas_projeto from authenticated;

do $$ begin
  if to_regclass('storage.objects') is not null then
    execute $p$create policy rm_mobile_media_insert on storage.objects for insert to authenticated
      with check(bucket_id in ('rm-fotos','rm-assinaturas') and rm_private.is_rm_authenticated()
        and (storage.foldername(name))[1]=auth.uid()::text)$p$;
    execute $p$create policy rm_mobile_media_update on storage.objects for update to authenticated
      using(bucket_id in ('rm-fotos','rm-assinaturas') and rm_private.is_rm_authenticated()
        and (storage.foldername(name))[1]=auth.uid()::text)
      with check(bucket_id in ('rm-fotos','rm-assinaturas') and (storage.foldername(name))[1]=auth.uid()::text)$p$;
    execute $p$create policy rm_mobile_media_select on storage.objects for select to authenticated
      using(bucket_id in ('rm-fotos','rm-assinaturas') and rm_private.is_rm_authenticated())$p$;
  end if;
end $$;
commit;

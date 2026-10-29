-- Builder drafts never enter the mobile catalog. Publishing appends a complete
-- immutable form; adopting it in engineering is a separate explicit operation.
begin;

create table public.rm_form_template_families (
  id uuid primary key,
  created_by uuid not null references public.rm_users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);
create table public.rm_form_template_drafts (
  id uuid primary key,
  family_id uuid not null references public.rm_form_template_families(id) on delete restrict,
  kind text not null check(kind in ('new','copy','version')),
  state text not null default 'draft' check(state in ('draft','published')),
  source_form_id uuid references public.rm_forms(id) on delete restrict,
  source_version integer check(source_version>=1),
  content jsonb not null check(jsonb_typeof(content)='object' and octet_length(content::text)<=800000),
  source_snapshot jsonb not null check(jsonb_typeof(source_snapshot)='object'),
  published_form_id uuid unique references public.rm_forms(id) on delete restrict,
  created_by uuid not null references public.rm_users(id) on delete restrict,
  updated_by uuid not null references public.rm_users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check((kind='new' and source_form_id is null and source_version is null) or
    (kind in ('copy','version') and source_form_id is not null and source_version is not null)),
  check((state='draft' and published_form_id is null) or (state='published' and published_form_id is not null))
);
create table public.rm_form_template_versions (
  family_id uuid not null references public.rm_form_template_families(id) on delete restrict,
  version integer not null check(version>=1),
  form_id uuid not null unique references public.rm_forms(id) on delete restrict,
  draft_id uuid unique references public.rm_form_template_drafts(id) on delete restrict,
  legacy boolean not null,
  id_mapping jsonb not null default '{"questions":{},"items":{}}'::jsonb,
  published_by uuid not null references public.rm_users(id) on delete restrict,
  published_at timestamptz not null default clock_timestamp(),
  primary key(family_id,version),
  check((legacy and draft_id is null) or (not legacy and draft_id is not null))
);
create index rm_form_template_drafts_updated on public.rm_form_template_drafts(updated_at,id);
create index rm_form_template_drafts_family on public.rm_form_template_drafts(family_id,created_at,id);
create trigger rm_form_template_draft_touch before update on public.rm_form_template_drafts
  for each row execute function rm_private.touch_updated_at();
do $$ declare t text; begin
  foreach t in array array['rm_form_template_families','rm_form_template_drafts','rm_form_template_versions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated,service_role',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('create policy rm_form_builder_read on public.%I for select to authenticated using ((select rm_private.is_rm_authenticated()))',t);
  end loop;
end $$;

-- A single statement sees the complete source under one MVCC snapshot. Decimal
-- indices are text in the editor contract, never a lossy JSON/JS number.
create function public.rm_web_form_source_snapshot_v1(p_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object(
    'form',jsonb_build_object('id',f.id,'titulo',f.titulo,'descricao',f.descricao,'title',f.title,
      'description',f.description,'tipo',f.tipo,'ativo',f.ativo),
    'content',jsonb_build_object('titulo',f.titulo,'descricao',f.descricao,'title',f.title,'description',f.description,'tipo',f.tipo,
      'questions',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'indice',q.indice::text,'enunciado',q.enunciado,
        'title',q.title,'subtitulo',q.subtitulo,'tag',q.tag,'tipo',q.tipo,'subtipo',q.subtipo,'dimensoes',q.dimensoes,
        'obrigatorio',q.obrigatorio,'colaborador_filtro_perfil',q.colaborador_filtro_perfil,
        'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'indice',i.indice::text,'descricao',i.descricao,
          'description',i.description) order by i.indice,i.id) from public.rm_itens_questoes i where i.questao_id=q.id),'[]'::jsonb))
        order by q.indice,q.id) from public.rm_questoes q where q.form_id=f.id),'[]'::jsonb)),
    'source_snapshot',jsonb_build_object('usa_aprovacao',f.usa_aprovacao,'imagem_capa_url',f.imagem_capa_url,
      'celulas_ids',f.celulas_ids,'equipes_ids',f.equipes_ids),
    'version',coalesce(v.version,1),'family_id',v.family_id)
  from public.rm_forms f left join public.rm_form_template_versions v on v.form_id=f.id where f.id=p_id;
$$;
create function public.rm_web_form_template_snapshot_v1(p_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('draft',jsonb_build_object('id',d.id,'kind',d.kind,'state',d.state,'family_id',d.family_id,
    'source_form_id',d.source_form_id,'source_version',d.source_version,'content',d.content,'source_snapshot',d.source_snapshot,
    'created_at',d.created_at,'updated_at',d.updated_at,'published_form_id',d.published_form_id),
    'publication',case when v.form_id is not null then jsonb_build_object('form_id',v.form_id,'version',v.version,'id_mapping',v.id_mapping) end)
  from public.rm_form_template_drafts d left join public.rm_form_template_versions v on v.draft_id=d.id where d.id=p_id;
$$;
revoke all on function public.rm_web_form_source_snapshot_v1(uuid),public.rm_web_form_template_snapshot_v1(uuid) from public,anon,service_role;
grant execute on function public.rm_web_form_source_snapshot_v1(uuid),public.rm_web_form_template_snapshot_v1(uuid) to authenticated;

create function rm_private.validate_form_template_content(p_content jsonb,p_publish boolean) returns void
language plpgsql security definer set search_path='' as $$
declare q jsonb; i jsonb; field text; ids uuid[]:='{}'; item_count integer:=0; ident uuid; n numeric;
begin
  if p_content is null or jsonb_typeof(p_content)<>'object' or octet_length(p_content::text)>800000
    or not p_content ?& array['titulo','descricao','title','description','tipo','questions']
    or exists(select 1 from jsonb_object_keys(p_content) k where k not in ('titulo','descricao','title','description','tipo','questions'))
    or jsonb_typeof(p_content->'titulo')<>'string' or jsonb_typeof(p_content->'questions')<>'array'
    or jsonb_array_length(p_content->'questions')>1000 then
    raise exception 'Estrutura ou tamanho do formulário inválido.' using errcode='22023'; end if;
  foreach field in array array['descricao','title','description','tipo'] loop
    if jsonb_typeof(p_content->field) not in ('string','null') then raise exception 'Campo textual inválido: %',field using errcode='22023'; end if;
  end loop;
  perform (p_content->>'tipo')::public.rm_tipo_formulario_enum;
  if p_publish and (p_content->>'titulo' !~ '[^[:space:]]' or not exists(
    select 1 from jsonb_array_elements(p_content->'questions') x where x->>'tipo'<>'subt_tulo')) then
    raise exception 'Informe o título e pelo menos uma questão de preenchimento.' using errcode='22023'; end if;
  for q in select value from jsonb_array_elements(p_content->'questions') loop
    if jsonb_typeof(q)<>'object' or not q ?& array['id','indice','enunciado','title','subtitulo','tag','tipo','subtipo','dimensoes','obrigatorio','colaborador_filtro_perfil','items']
      or exists(select 1 from jsonb_object_keys(q) k where k not in ('id','indice','enunciado','title','subtitulo','tag','tipo','subtipo','dimensoes','obrigatorio','colaborador_filtro_perfil','items'))
      or jsonb_typeof(q->'id')<>'string' or jsonb_typeof(q->'indice')<>'string' or jsonb_typeof(q->'enunciado')<>'string'
      or jsonb_typeof(q->'tipo')<>'string' or jsonb_typeof(q->'obrigatorio')<>'boolean' or jsonb_typeof(q->'items')<>'array' then
      raise exception 'Estrutura de questão inválida.' using errcode='22023'; end if;
    ident:=(q->>'id')::uuid;
    if ident is null or ident=any(ids) then raise exception 'ID de questão/opção repetido.' using errcode='22023'; end if;
    ids:=array_append(ids,ident);
    if length(q->>'indice')>60 or q->>'indice' !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then
      raise exception 'Índice deve ser decimal sem expoente.' using errcode='22023'; end if;
    n:=(q->>'indice')::numeric;
    if abs(n)>1000000000 then raise exception 'Índice fora do intervalo permitido.' using errcode='22023'; end if;
    foreach field in array array['title','subtitulo','tag','subtipo','dimensoes','colaborador_filtro_perfil'] loop
      if jsonb_typeof(q->field) not in ('string','null') then raise exception 'Campo da questão inválido: %',field using errcode='22023'; end if;
    end loop;
    perform (q->>'tipo')::public.rm_tipo_questao_enum;
    perform (q->>'subtipo')::public.rm_subtipo_questao_enum;
    perform (q->>'dimensoes')::public.rm_dimensao_enum;
    perform (q->>'colaborador_filtro_perfil')::public.rm_perfil_usuario_enum;
    if p_publish and (q->>'enunciado' !~ '[^[:space:]]'
      or (q->>'subtipo'='intervalo_de_datas' and q->>'tipo'<>'data')
      or (q->>'subtipo'='intervalo_de_hor_rios' and q->>'tipo'<>'hora')
      or (q->>'dimensoes' is not null and q->>'tipo' not in ('texto_curto','texto_longo','numero'))
      or (q->>'colaborador_filtro_perfil' is not null and q->>'tipo'<>'colaborador')
      or (q->>'tipo' in ('escolha__nica','caixas_de_sele__o','lista_suspensa','lista_multi_sele__o') and jsonb_array_length(q->'items')=0)
      or (q->>'tipo' not in ('escolha__nica','caixas_de_sele__o','lista_suspensa','lista_multi_sele__o') and jsonb_array_length(q->'items')>0)) then
      raise exception 'Complete o enunciado, as opções e os campos compatíveis com o tipo da questão.' using errcode='22023'; end if;
    item_count:=item_count+jsonb_array_length(q->'items');
    if item_count>5000 then raise exception 'Limite de opções excedido.' using errcode='22023'; end if;
    for i in select value from jsonb_array_elements(q->'items') loop
      if jsonb_typeof(i)<>'object' or not i ?& array['id','indice','descricao','description']
        or exists(select 1 from jsonb_object_keys(i) k where k not in ('id','indice','descricao','description'))
        or jsonb_typeof(i->'id')<>'string' or jsonb_typeof(i->'indice')<>'string' or jsonb_typeof(i->'descricao')<>'string'
        or jsonb_typeof(i->'description') not in ('string','null') then raise exception 'Estrutura de opção inválida.' using errcode='22023'; end if;
      ident:=(i->>'id')::uuid;
      if ident is null or ident=any(ids) then raise exception 'ID de questão/opção repetido.' using errcode='22023'; end if;
      ids:=array_append(ids,ident);
      if length(i->>'indice')>60 or i->>'indice' !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then
        raise exception 'Índice deve ser decimal sem expoente.' using errcode='22023'; end if;
      n:=(i->>'indice')::numeric;
      if abs(n)>1000000000 or (p_publish and i->>'descricao' !~ '[^[:space:]]') then
        raise exception 'Complete a descrição e o índice da opção.' using errcode='22023'; end if;
    end loop;
    if p_publish and exists(select 1 from jsonb_array_elements(q->'items') x group by (x->>'indice')::double precision having count(*)>1) then
      raise exception 'Opções com índices iguais ou indistinguíveis no aplicativo.' using errcode='22023'; end if;
  end loop;
  if p_publish and exists(select 1 from jsonb_array_elements(p_content->'questions') x group by (x->>'indice')::double precision having count(*)>1) then
    raise exception 'Questões com índices iguais ou indistinguíveis no aplicativo.' using errcode='22023'; end if;
end $$;

-- Only forms produced by this builder are frozen. A legacy registration records
-- provenance, without silently imposing new ownership on the Bubble importer.
create function rm_private.protect_published_form_template() returns trigger
language plpgsql security definer set search_path='' as $$
declare form_ids uuid[]:='{}'; r jsonb;
begin
  if tg_op<>'INSERT' then
    r:=to_jsonb(old);
    if tg_table_name='rm_forms' then form_ids:=array_append(form_ids,(r->>'id')::uuid);
    elsif tg_table_name='rm_questoes' then form_ids:=array_append(form_ids,(r->>'form_id')::uuid);
    else
      form_ids:=array_append(form_ids,(r->>'form_id')::uuid);
      form_ids:=array_append(form_ids,(select form_id from public.rm_questoes where id=(r->>'questao_id')::uuid));
    end if;
  end if;
  if tg_op<>'DELETE' then
    r:=to_jsonb(new);
    if tg_table_name='rm_forms' then form_ids:=array_append(form_ids,(r->>'id')::uuid);
    elsif tg_table_name='rm_questoes' then form_ids:=array_append(form_ids,(r->>'form_id')::uuid);
    else
      form_ids:=array_append(form_ids,(r->>'form_id')::uuid);
      form_ids:=array_append(form_ids,(select form_id from public.rm_questoes where id=(r->>'questao_id')::uuid));
    end if;
  end if;
  if exists(select 1 from public.rm_form_template_versions where form_id=any(form_ids) and not legacy) then
    raise exception 'Versão publicada é imutável; crie uma nova versão.' using errcode='55000'; end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger rm_form_template_immutable before update or delete on public.rm_forms
  for each row execute function rm_private.protect_published_form_template();
create trigger rm_form_question_immutable before insert or update or delete on public.rm_questoes
  for each row execute function rm_private.protect_published_form_template();
create trigger rm_form_item_immutable before insert or update or delete on public.rm_itens_questoes
  for each row execute function rm_private.protect_published_form_template();

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_engineering_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  draft public.rm_form_template_drafts%rowtype; source jsonb; content jsonb; metadata jsonb; snapshot jsonb; result jsonb; before_record jsonb;
  ident uuid; source_id uuid; family uuid; source_version integer; kind text; expected timestamptz;
  q jsonb; i jsonb; questions jsonb:='[]'; items jsonb; question_id uuid; item_id uuid; form_id uuid; version integer;
  mapping jsonb:='{"questions":{},"items":{}}';
begin
  if p_operation is null or p_operation not in ('create_form_template','save_form_template','publish_form_template') then
    return rm_private.web_mutate_engineering_core_v1(p_client_submission_id,p_operation,p_payload); end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or actor.perfil is distinct from 'administrador' then raise exception 'Construtor restrito à administração.' using errcode='42501'; end if;
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
  if jsonb_typeof(p_payload->'id') is distinct from 'string' then raise exception 'Informe o UUID do rascunho.' using errcode='22023'; end if;
  ident:=(p_payload->>'id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended('form-draft:'||ident::text,19));
  if p_operation='create_form_template' then
    if not p_payload ?& array['id','source_form_id','kind'] or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('id','source_form_id','kind'))
      or jsonb_typeof(p_payload->'kind') is distinct from 'string' or p_payload->>'kind' not in ('new','copy','version')
      or jsonb_typeof(p_payload->'source_form_id') not in ('string','null') then raise exception 'Criação de rascunho inválida.' using errcode='22023'; end if;
    kind:=p_payload->>'kind'; source_id:=(p_payload->>'source_form_id')::uuid;
    if (kind='new') is distinct from (source_id is null) then raise exception 'Origem incompatível com o tipo de criação.' using errcode='22023'; end if;
    if exists(select 1 from public.rm_form_template_drafts where id=ident) then raise exception 'Rascunho já existe.' using errcode='23505'; end if;
    if source_id is null then
      content:='{"titulo":"","descricao":null,"title":null,"description":null,"tipo":null,"questions":[]}';
      metadata:='{"usa_aprovacao":true,"imagem_capa_url":null,"celulas_ids":[],"equipes_ids":[]}';
    else
      perform pg_advisory_xact_lock(hashtextextended('form-source:'||source_id::text,19));
      source:=public.rm_web_form_source_snapshot_v1(source_id);
      if source is null then raise exception 'Formulário de origem não encontrado.' using errcode='P0002'; end if;
      content:=source->'content'; metadata:=source->'source_snapshot'; source_version:=(source->>'version')::integer;
      -- Draft IDs are independent editor keys; publication generates fresh IDs again.
      for q in select value from jsonb_array_elements(content->'questions') loop
        items:='[]';
        for i in select value from jsonb_array_elements(q->'items') loop
          items:=items||jsonb_build_array(i||jsonb_build_object('id',gen_random_uuid()));
        end loop;
        questions:=questions||jsonb_build_array(q||jsonb_build_object('id',gen_random_uuid(),'items',items));
      end loop;
      content:=content||jsonb_build_object('questions',questions);
    end if;
    perform rm_private.validate_form_template_content(content,false);
    if kind='version' then
      family:=(source->>'family_id')::uuid;
      if family is null then
        family:=source_id;
        perform pg_advisory_xact_lock(hashtextextended('form-family:'||family::text,19));
        insert into public.rm_form_template_families(id,created_by) values(family,actor.id);
        insert into public.rm_form_template_versions(family_id,version,form_id,legacy,published_by)
          values(family,1,source_id,true,actor.id);
      end if;
    else
      family:=ident;
      insert into public.rm_form_template_families(id,created_by) values(family,actor.id);
    end if;
    insert into public.rm_form_template_drafts(id,family_id,kind,source_form_id,source_version,content,source_snapshot,created_by,updated_by)
      values(ident,family,kind,source_id,source_version,content,metadata,actor.id,actor.id) returning * into draft;
  else
    if not p_payload ?& array['id','expected_updated_at'] or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string'
      or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('id','expected_updated_at','content'))
      or (p_operation='save_form_template' and not p_payload?'content')
      or (p_operation='publish_form_template' and p_payload?'content') then raise exception 'Versão ou conteúdo do rascunho inválido.' using errcode='22023'; end if;
    expected:=(p_payload->>'expected_updated_at')::timestamptz;
    select * into draft from public.rm_form_template_drafts where id=ident for update;
    if not found then raise exception 'Rascunho não encontrado.' using errcode='P0002'; end if;
    before_record:=to_jsonb(draft);
    if draft.updated_at is distinct from expected then raise exception 'Rascunho alterado; recarregue antes de salvar.' using errcode='PT409'; end if;
    if draft.state<>'draft' then raise exception 'Rascunho já publicado; crie uma nova versão.' using errcode='22023'; end if;
    if p_operation='save_form_template' then
      perform rm_private.validate_form_template_content(p_payload->'content',false);
      update public.rm_form_template_drafts set content=p_payload->'content',updated_by=actor.id where id=ident returning * into draft;
    else
      perform rm_private.validate_form_template_content(draft.content,true);
      perform pg_advisory_xact_lock(hashtextextended('form-family:'||draft.family_id::text,19));
      select coalesce(max(v.version),0)+1 into version from public.rm_form_template_versions v where v.family_id=draft.family_id;
      content:=draft.content; metadata:=draft.source_snapshot; form_id:=gen_random_uuid();
      insert into public.rm_forms(id,titulo,title,descricao,description,tipo,ativo,usa_aprovacao,imagem_capa_url,celulas_ids,equipes_ids)
        values(form_id,content->>'titulo',content->>'title',content->>'descricao',content->>'description',(content->>'tipo')::public.rm_tipo_formulario_enum,
          true,(metadata->>'usa_aprovacao')::boolean,metadata->>'imagem_capa_url',
          array(select x::uuid from jsonb_array_elements_text(metadata->'celulas_ids') x),array(select x::uuid from jsonb_array_elements_text(metadata->'equipes_ids') x));
      for q in select value from jsonb_array_elements(content->'questions') loop
        question_id:=gen_random_uuid();
        mapping:=jsonb_set(mapping,array['questions',q->>'id'],to_jsonb(question_id::text));
        insert into public.rm_questoes(id,form_id,indice,enunciado,title,subtitulo,tag,tipo,subtipo,dimensoes,obrigatorio,colaborador_filtro_perfil)
          values(question_id,form_id,(q->>'indice')::numeric,q->>'enunciado',q->>'title',q->>'subtitulo',q->>'tag',
            (q->>'tipo')::public.rm_tipo_questao_enum,(q->>'subtipo')::public.rm_subtipo_questao_enum,(q->>'dimensoes')::public.rm_dimensao_enum,
            (q->>'obrigatorio')::boolean,(q->>'colaborador_filtro_perfil')::public.rm_perfil_usuario_enum);
        for i in select value from jsonb_array_elements(q->'items') loop
          item_id:=gen_random_uuid(); mapping:=jsonb_set(mapping,array['items',i->>'id'],to_jsonb(item_id::text));
          insert into public.rm_itens_questoes(id,form_id,questao_id,indice,descricao,description)
            values(item_id,form_id,question_id,(i->>'indice')::numeric,i->>'descricao',i->>'description');
        end loop;
      end loop;
      insert into public.rm_form_template_versions(family_id,version,form_id,draft_id,legacy,id_mapping,published_by)
        values(draft.family_id,version,form_id,draft.id,false,mapping,actor.id);
      update public.rm_form_template_drafts set state='published',published_form_id=form_id,updated_by=actor.id where id=ident returning * into draft;
    end if;
  end if;
  snapshot:=public.rm_web_form_template_snapshot_v1(ident);
  result:=jsonb_build_object('operation',p_operation,'id',ident,'projeto_id',null,'updated_at',draft.updated_at,
    'record',snapshot->'draft','snapshot',snapshot,'publication',snapshot->'publication','idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
  if p_operation in ('create_form_template','save_form_template','publish_form_template') then
    raise exception 'Identificador, enum, número ou data inválida.' using errcode='22023'; end if;
  raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
    'create_form_template','save_form_template','publish_form_template'));
do $$ declare definition text; needle text:='when ''save_photo_title'' then ''em.engineering.manage'' end;'; begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
  execute replace(definition,needle,'when ''save_photo_title'' then ''em.engineering.manage'' when ''create_form_template'' then ''em.form_templates.manage'' when ''save_form_template'' then ''em.form_templates.manage'' when ''publish_form_template'' then ''em.form_templates.manage'' end;');
  -- Invalidate cached PL/pgSQL references after renaming the previous core.
  execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.validate_form_template_content(jsonb,boolean),rm_private.protect_published_form_template(),
  rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_engineering_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

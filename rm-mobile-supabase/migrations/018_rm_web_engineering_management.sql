-- Engineering templates only. Existing project allocations and answers are not rewritten.
begin;
alter table public.rm_celula_tipos_equipamento add column ativo boolean not null default true;
alter table public.rm_celula_form_tipos_equipamento add column ativo boolean not null default true;
alter table public.rm_aprovacoes_etapas add column ativo boolean not null default true;
alter table public.rm_fotos add column cadastro_foto_id uuid references public.rm_cadastro_fotos(id) on delete restrict;

create function rm_private.engineering_pair_lock(p_cell uuid,p_type uuid,p_exclusive boolean) returns void
language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
begin
  if p_cell is null or p_type is null then raise exception 'Informe célula e tipo.' using errcode='22023'; end if;
  if p_exclusive then perform pg_advisory_xact_lock(hashtextextended(p_cell::text||':'||p_type::text,18));
  else perform pg_advisory_xact_lock_shared(hashtextextended(p_cell::text||':'||p_type::text,18)); end if;
end $$;

-- Technical imports participate in the same locking/version protocol through
-- triggers. Runtime project rows do not bump template versions.
create function rm_private.engineering_parent_lock_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
declare r record;
begin
  for r in select distinct c,t from (values
    (case when tg_op<>'INSERT' then old.celula_id end,case when tg_op<>'INSERT' then old.tipo_equipamento_id end),
    (case when tg_op<>'DELETE' then new.celula_id end,case when tg_op<>'DELETE' then new.tipo_equipamento_id end)) pairs(c,t)
    where c is not null and t is not null order by c,t loop
    perform rm_private.engineering_pair_lock(r.c,r.t,true);
  end loop;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger rm_engineering_parent_lock before insert or update or delete on public.rm_celula_tipos_equipamento
  for each row execute function rm_private.engineering_parent_lock_trigger();

create function rm_private.engineering_child_version_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
declare previous jsonb; current_row jsonb; parent_ids uuid[]:='{}'; r record;
begin
  if tg_op<>'INSERT' then previous:=to_jsonb(old); end if;
  if tg_op<>'DELETE' then current_row:=to_jsonb(new); end if;
  if previous is not null and (tg_table_name='rm_celula_form_tipos_equipamento' or
    (previous->>'projeto_id' is null and previous->>'celula_projeto_id' is null)) then
    parent_ids:=array_append(parent_ids,(previous->>'celula_tipo_equipamento_id')::uuid); end if;
  if current_row is not null and (tg_table_name='rm_celula_form_tipos_equipamento' or
    (current_row->>'projeto_id' is null and current_row->>'celula_projeto_id' is null)) then
    parent_ids:=array_append(parent_ids,(current_row->>'celula_tipo_equipamento_id')::uuid); end if;
  for r in select id,celula_id,tipo_equipamento_id from public.rm_celula_tipos_equipamento where id=any(parent_ids) order by celula_id,tipo_equipamento_id loop
    perform rm_private.engineering_pair_lock(r.celula_id,r.tipo_equipamento_id,true);
    update public.rm_celula_tipos_equipamento set updated_at=clock_timestamp() where id=r.id;
  end loop;
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger rm_engineering_forms_version after insert or update or delete on public.rm_celula_form_tipos_equipamento
  for each row execute function rm_private.engineering_child_version_trigger();
create trigger rm_engineering_photos_version after insert or update or delete on public.rm_fotos
  for each row execute function rm_private.engineering_child_version_trigger();
create trigger rm_engineering_stages_version after insert or update or delete on public.rm_aprovacoes_etapas
  for each row execute function rm_private.engineering_child_version_trigger();

create function public.rm_web_engineering_snapshot_v1(p_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select jsonb_build_object(
    'matrix',jsonb_build_object('id',m.id,'celula_id',m.celula_id,'tipo_equipamento_id',m.tipo_equipamento_id,
      'ativo',m.ativo,'visibilidade',m.visibilidade,'numero_fotos',m.numero_fotos,'updated_at',m.updated_at),
    'form_ids',coalesce((select jsonb_agg(f.form_id order by f.form_id) from public.rm_celula_form_tipos_equipamento f
      where f.celula_tipo_equipamento_id=m.id and f.ativo),'[]'::jsonb),
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'cadastro_foto_id',f.cadastro_foto_id,
      'numero',f.numero,'descricao',f.descricao,'titulo',f.titulo,'identificador_foto_key',f.identificador_foto_key,'categoria_foto',f.categoria_foto) order by f.numero nulls last,f.id)
      from public.rm_fotos f where f.celula_tipo_equipamento_id=m.id and f.projeto_id is null and f.celula_projeto_id is null and not f.lixeira),'[]'::jsonb),
    'stages',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'celula_origem_id',a.celula_origem_id,'celula_destino_id',a.celula_destino_id,
      'status_cel_proj',a.status_cel_proj,'bloquear_avanco_sem_aprov',a.bloquear_avanco_sem_aprov,
      'aprovadores_ids',a.aprovadores_ids,'aprovadores_retorno_ids',a.aprovadores_retorno_ids,'aprovador_id',a.aprovador_id) order by a.created_at,a.id)
      from public.rm_aprovacoes_etapas a where a.celula_tipo_equipamento_id=m.id and a.projeto_id is null and a.celula_projeto_id is null and a.ativo),'[]'::jsonb))
  from public.rm_celula_tipos_equipamento m where m.id=p_id;
$$;
revoke all on function public.rm_web_engineering_snapshot_v1(uuid) from public,anon,service_role;
grant execute on function public.rm_web_engineering_snapshot_v1(uuid) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_catalog_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  m public.rm_celula_tipos_equipamento%rowtype; title_row public.rm_cadastro_fotos%rowtype;
  photo public.rm_fotos%rowtype; stage public.rm_aprovacoes_etapas%rowtype;
  record_id uuid; cell_id uuid; type_id uuid; expected timestamptz; is_new boolean;
  changes jsonb; item jsonb; before_record jsonb; result jsonb; old_dto jsonb; new_dto jsonb;
  ids uuid[]; form_ids uuid[]; approvers uuid[]; return_approvers uuid[]; destination uuid;
  field text; title text; cell_name text; item_id uuid; catalog_id uuid; n numeric; stage_status public.rm_status_cel_proj_enum;
  scope_count integer; scope_id uuid;
begin
  if p_operation is null or p_operation not in ('save_engineering','save_photo_title') then
    return rm_private.web_mutate_catalog_core_v1(p_client_submission_id,p_operation,p_payload); end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or actor.perfil is distinct from 'administrador' then raise exception 'Engenharia restrita à administração.' using errcode='42501'; end if;
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
  if not p_payload ?& array['id','expected_updated_at','changes'] or exists(select 1 from jsonb_object_keys(p_payload) k
    where not k=any(case when p_operation='save_engineering' then array['id','expected_updated_at','changes','celula_id','tipo_equipamento_id']
      else array['id','expected_updated_at','changes'] end)) then raise exception 'Campos inválidos.' using errcode='22023'; end if;
  begin record_id:=(p_payload->>'id')::uuid; expected:=(p_payload->>'expected_updated_at')::timestamptz;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'Identificador ou versão inválidos.' using errcode='22023'; end;
  changes:=p_payload->'changes';
  if record_id is null or (expected is not null and not isfinite(expected)) or jsonb_typeof(changes)<>'object' or changes='{}'::jsonb then
    raise exception 'Alterações inválidas.' using errcode='22023'; end if;

  if p_operation='save_photo_title' then
    if exists(select 1 from jsonb_object_keys(changes) k where k not in ('titulo','numero','celula_id')) then raise exception 'Campo de título inválido.' using errcode='22023'; end if;
    -- Same master-data lock as 017, preserving cell rename/title scope atomicity.
    perform pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17));
    select * into title_row from public.rm_cadastro_fotos where id=record_id for update; is_new:=not found;
    if (is_new and expected is not null) or (not is_new and (expected is null or expected<>title_row.updated_at)) then
      raise exception 'Título alterado. Atualize antes de salvar.' using errcode='PT409'; end if;
    before_record:=case when is_new then null else to_jsonb(title_row) end;
    if is_new and not changes ?& array['titulo','celula_id'] then raise exception 'Informe título e escopo explícito.' using errcode='22023'; end if;
    if changes?'titulo' then
      if jsonb_typeof(changes->'titulo')<>'string' then raise exception 'Título inválido.' using errcode='22023'; end if;
      title:=regexp_replace(changes->>'titulo','^[[:space:]]+|[[:space:]]+$','','g');
      if title='' or length(title)>200 then raise exception 'Título deve conter de 1 a 200 caracteres.' using errcode='22023'; end if;
    else title:=title_row.titulo; end if;
    if changes?'numero' then
      if jsonb_typeof(changes->'numero') not in ('number','null') then raise exception 'Número inválido.' using errcode='22023'; end if;
      n:=(changes->>'numero')::numeric;
      if n<0 or n>1000 or n<>trunc(n) then raise exception 'Número deve ser inteiro entre 0 e 1000.' using errcode='22023'; end if;
    else n:=title_row.numero; end if;
    cell_name:=title_row.celula_nome;
    if changes?'celula_id' then
      cell_id:=(changes->>'celula_id')::uuid;
      if cell_id is not null then
        select nome into cell_name from public.rm_celulas where id=cell_id;
        if not found then raise exception 'Célula inexistente.' using errcode='22023'; end if;
        if (select count(*) from public.rm_celulas where rm_private.catalog_name_key(nome)=rm_private.catalog_name_key(cell_name))<>1 then
          raise exception 'Nome de célula ambíguo para o catálogo de títulos.' using errcode='22023'; end if;
      else cell_name:=null; end if;
      if not is_new then
        if nullif(rm_private.catalog_name_key(title_row.celula_nome),'') is null then
          if cell_id is not null then raise exception 'Escopo do título é imutável.' using errcode='22023'; end if;
        else
          select count(*),(array_agg(id))[1] into scope_count,scope_id from public.rm_celulas
            where rm_private.catalog_name_key(nome)=rm_private.catalog_name_key(title_row.celula_nome);
          if scope_count<>1 or cell_id is distinct from scope_id then raise exception 'Escopo do título é imutável ou ambíguo.' using errcode='22023'; end if;
        end if;
      end if;
    end if;
    if is_new then insert into public.rm_cadastro_fotos(id,titulo,numero,celula_nome) values(record_id,title,n::int,cell_name) returning * into title_row;
    else update public.rm_cadastro_fotos set titulo=title,numero=n::int,celula_nome=cell_name,sync_source='supabase' where id=record_id returning * into title_row; end if;
    result:=jsonb_build_object('record',jsonb_build_object('id',title_row.id,'titulo',title_row.titulo,'numero',title_row.numero,
      'celula_nome',title_row.celula_nome,'updated_at',title_row.updated_at),'updated_at',title_row.updated_at);
  else
    cell_id:=(p_payload->>'celula_id')::uuid; type_id:=(p_payload->>'tipo_equipamento_id')::uuid;
    if cell_id is null or type_id is null or exists(select 1 from jsonb_object_keys(changes) k
      where k not in ('ativo','visibilidade','numero_fotos','form_ids','photos','stages')) then raise exception 'Matriz inválida.' using errcode='22023'; end if;
    if changes?'photos' then
      -- Shared catalog lock before the pair lock: a concurrent 017 cell rename
      -- cannot hold the cell while waiting for a title row locked by this save.
      perform pg_advisory_xact_lock_shared(hashtextextended('rm.web.catalogs',17));
    end if;
    perform rm_private.engineering_pair_lock(cell_id,type_id,true);
    select * into m from public.rm_celula_tipos_equipamento where id=record_id for update; is_new:=not found;
    if (is_new and expected is not null) or (not is_new and (expected is null or expected<>m.updated_at)) then raise exception 'Matriz alterada. Atualize antes de salvar.' using errcode='PT409'; end if;
    if not is_new and (m.celula_id<>cell_id or m.tipo_equipamento_id<>type_id) then raise exception 'Célula e tipo são imutáveis.' using errcode='22023'; end if;
    if not exists(select 1 from public.rm_celulas where id=cell_id) or not exists(select 1 from public.rm_tipos_equipamento where id=type_id) then
      raise exception 'Célula ou tipo inexistente.' using errcode='22023'; end if;
    before_record:=case when is_new then null else public.rm_web_engineering_snapshot_v1(record_id) end;
    foreach field in array array['ativo','visibilidade'] loop
      if changes?field and jsonb_typeof(changes->field)<>'boolean' then raise exception 'Estado da matriz inválido.' using errcode='22023'; end if;
    end loop;
    if changes?'numero_fotos' then
      if jsonb_typeof(changes->'numero_fotos')<>'number' then raise exception 'Quantidade inválida.' using errcode='22023'; end if;
      n:=(changes->>'numero_fotos')::numeric;
      if n<0 or n>1000 or n<>trunc(n) then raise exception 'Quantidade deve ser inteira entre 0 e 1000.' using errcode='22023'; end if;
    end if;
    if is_new then
      insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id) values(record_id,cell_id,type_id) returning * into m;
    end if;
    update public.rm_celula_tipos_equipamento set ativo=case when changes?'ativo' then (changes->>'ativo')::bool else ativo end,
      visibilidade=case when changes?'visibilidade' then (changes->>'visibilidade')::bool else visibilidade end,
      numero_fotos=case when changes?'numero_fotos' then (changes->>'numero_fotos')::numeric::int else numero_fotos end,
      sync_source='supabase' where id=m.id;

    if changes?'form_ids' then
      if jsonb_typeof(changes->'form_ids')<>'array' or jsonb_array_length(changes->'form_ids')>200 then raise exception 'Lista de formulários inválida.' using errcode='22023'; end if;
      select coalesce(array_agg(value::uuid),'{}'::uuid[]) into form_ids from jsonb_array_elements_text(changes->'form_ids');
      if array_position(form_ids,null) is not null or cardinality(form_ids)<>(select count(distinct x) from unnest(form_ids) x)
        or exists(select 1 from unnest(form_ids) f left join public.rm_forms d on d.id=f where d.id is null or (not d.ativo and not exists(
          select 1 from public.rm_celula_form_tipos_equipamento cf where cf.celula_tipo_equipamento_id=m.id and cf.form_id=f and cf.ativo))) then
        raise exception 'Formulário inexistente, repetido ou inativo.' using errcode='22023'; end if;
      update public.rm_celula_form_tipos_equipamento set ativo=false,sync_source='supabase' where celula_tipo_equipamento_id=m.id and ativo and not form_id=any(form_ids);
      insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id,ativo)
        select m.id,f,true from unnest(form_ids) f on conflict(celula_tipo_equipamento_id,form_id) do update set ativo=true,sync_source='supabase'
        where not rm_celula_form_tipos_equipamento.ativo;
    end if;

    if changes?'photos' then
      if jsonb_typeof(changes->'photos')<>'array' or jsonb_array_length(changes->'photos')>1000 then raise exception 'Lista de fotos inválida.' using errcode='22023'; end if;
      ids:='{}';
      for item in select value from jsonb_array_elements(changes->'photos') loop
        if jsonb_typeof(item)<>'object' or not item ?& array['id','cadastro_foto_id','numero','descricao'] or exists(
          select 1 from jsonb_object_keys(item) k where k not in ('id','cadastro_foto_id','numero','descricao')) then raise exception 'Modelo de foto inválido.' using errcode='22023'; end if;
        item_id:=(item->>'id')::uuid; catalog_id:=(item->>'cadastro_foto_id')::uuid;
        if item_id is null or item_id=any(ids) then raise exception 'Foto repetida ou inválida.' using errcode='22023'; end if;
        ids:=array_append(ids,item_id);
        select * into photo from public.rm_fotos where id=item_id for update;
        if found and (photo.celula_tipo_equipamento_id is distinct from m.id or photo.projeto_id is not null or photo.celula_projeto_id is not null) then
          raise exception 'Foto não pertence a este modelo.' using errcode='42501'; end if;
        old_dto:=case when photo.id is null then null else jsonb_build_object('id',photo.id,'cadastro_foto_id',photo.cadastro_foto_id,'numero',photo.numero,'descricao',photo.descricao) end;
        if photo.id is not null and not photo.lixeira and item=old_dto then continue; end if;
        if jsonb_typeof(item->'numero')<>'number' or jsonb_typeof(item->'descricao') not in ('string','null') then raise exception 'Número ou descrição da foto inválidos.' using errcode='22023'; end if;
        n:=(item->>'numero')::numeric;
        if n<1 or n>1000 or n<>trunc(n) or length(item->>'descricao')>4000 then raise exception 'Número ou descrição da foto inválidos.' using errcode='22023'; end if;
        select * into title_row from public.rm_cadastro_fotos where id=catalog_id for share;
        if not found or (nullif(rm_private.catalog_name_key(title_row.celula_nome),'') is not null and rm_private.catalog_name_key(title_row.celula_nome)
          is distinct from (select rm_private.catalog_name_key(nome) from public.rm_celulas where id=cell_id)) then
          raise exception 'Selecione título cadastrado para esta célula ou global.' using errcode='22023'; end if;
        if photo.id is null then
          insert into public.rm_fotos(id,celula_id,celula_tipo_equipamento_id,categoria_foto,cadastro_foto_id,titulo,numero,descricao)
            values(item_id,cell_id,m.id,'obrigat_ria',catalog_id,title_row.titulo,n::int,item->>'descricao');
        else update public.rm_fotos set cadastro_foto_id=catalog_id,titulo=title_row.titulo,numero=n::int,descricao=item->>'descricao',
          celula_id=cell_id,categoria_foto='obrigat_ria',lixeira=false,sync_source='supabase' where id=item_id; end if;
      end loop;
      update public.rm_fotos set lixeira=true,sync_source='supabase' where celula_tipo_equipamento_id=m.id
        and projeto_id is null and celula_projeto_id is null and not lixeira and not id=any(ids);
    end if;

    if changes?'stages' then
      if jsonb_typeof(changes->'stages')<>'array' or jsonb_array_length(changes->'stages')>100 then raise exception 'Lista de etapas inválida.' using errcode='22023'; end if;
      ids:='{}';
      for item in select value from jsonb_array_elements(changes->'stages') loop
        if jsonb_typeof(item)<>'object' or not item ?& array['id','celula_destino_id','status_cel_proj','bloquear_avanco_sem_aprov','aprovadores_ids','aprovadores_retorno_ids']
          or exists(select 1 from jsonb_object_keys(item) k where k not in ('id','celula_destino_id','status_cel_proj','bloquear_avanco_sem_aprov','aprovadores_ids','aprovadores_retorno_ids')) then
          raise exception 'Etapa inválida.' using errcode='22023'; end if;
        item_id:=(item->>'id')::uuid;
        if item_id is null or item_id=any(ids) then raise exception 'Etapa repetida ou inválida.' using errcode='22023'; end if; ids:=array_append(ids,item_id);
        select * into stage from public.rm_aprovacoes_etapas where id=item_id for update;
        if found and (stage.celula_tipo_equipamento_id is distinct from m.id or stage.projeto_id is not null or stage.celula_projeto_id is not null) then
          raise exception 'Etapa não pertence a este modelo.' using errcode='42501'; end if;
        old_dto:=case when stage.id is null then null else jsonb_build_object('id',stage.id,'celula_destino_id',stage.celula_destino_id,
          'status_cel_proj',stage.status_cel_proj,'bloquear_avanco_sem_aprov',stage.bloquear_avanco_sem_aprov,
          'aprovadores_ids',stage.aprovadores_ids,'aprovadores_retorno_ids',stage.aprovadores_retorno_ids) end;
        if stage.id is not null and stage.ativo and item=old_dto then continue; end if;
        destination:=(item->>'celula_destino_id')::uuid; stage_status:=(item->>'status_cel_proj')::public.rm_status_cel_proj_enum;
        if destination is null or destination=cell_id or not exists(select 1 from public.rm_celulas where id=destination)
          or stage_status is null or stage_status='retornado' or jsonb_typeof(item->'bloquear_avanco_sem_aprov')<>'boolean'
          or jsonb_typeof(item->'aprovadores_ids')<>'array' or jsonb_typeof(item->'aprovadores_retorno_ids')<>'array' then
          raise exception 'Destino, status ou aprovadores inválidos.' using errcode='22023'; end if;
        select coalesce(array_agg(value::uuid),'{}') into approvers from jsonb_array_elements_text(item->'aprovadores_ids');
        select coalesce(array_agg(value::uuid),'{}') into return_approvers from jsonb_array_elements_text(item->'aprovadores_retorno_ids');
        if cardinality(approvers) not between 1 and 100 or cardinality(return_approvers) not between 1 and 100
          or cardinality(approvers)<>(select count(distinct u) from unnest(approvers) u)
          or cardinality(return_approvers)<>(select count(distinct u) from unnest(return_approvers) u)
          or exists(select 1 from (select unnest(approvers) u,cell_id c union all select unnest(return_approvers),destination) a
            where not exists(select 1 from public.rm_users u join public.rm_tablet_celula_users t on t.identidade_id=u.id
              where u.id=a.u and u.status='ativo' and t.celula_id=a.c)) then
          raise exception 'Aprovadores devem estar ativos e vinculados às células correspondentes.' using errcode='22023'; end if;
        if stage.id is null then
          insert into public.rm_aprovacoes_etapas(id,celula_tipo_equipamento_id,celula_origem_id,celula_destino_id,status_cel_proj,
            bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids,status,ativo)
            values(item_id,m.id,cell_id,destination,stage_status,(item->>'bloquear_avanco_sem_aprov')::bool,approvers,return_approvers,'nulo',true);
        else update public.rm_aprovacoes_etapas set celula_origem_id=cell_id,celula_destino_id=destination,status_cel_proj=stage_status,
          bloquear_avanco_sem_aprov=(item->>'bloquear_avanco_sem_aprov')::bool,aprovadores_ids=approvers,aprovadores_retorno_ids=return_approvers,
          aprovador_id=null,aprovado_por_id=null,data_aprovacao=null,status='nulo',ativo=true,sync_source='supabase' where id=item_id; end if;
      end loop;
      update public.rm_aprovacoes_etapas set ativo=false,sync_source='supabase' where celula_tipo_equipamento_id=m.id
        and projeto_id is null and celula_projeto_id is null and ativo and not id=any(ids);
    end if;
    new_dto:=public.rm_web_engineering_snapshot_v1(record_id);
    result:=jsonb_build_object('record',new_dto->'matrix','updated_at',new_dto->'matrix'->'updated_at','snapshot',new_dto);
  end if;
  result:=result||jsonb_build_object('operation',p_operation,'id',record_id,'projeto_id',null,'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range then
  if p_operation in ('save_engineering','save_photo_title') then
    raise exception 'Identificador, enum ou número inválido.' using errcode='22023'; end if;
  raise;
end $$;

create function rm_private.clone_engineering_children_v1(p_matrix uuid,p_project uuid,p_allocation uuid) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare m public.rm_celula_tipos_equipamento%rowtype; cp public.rm_celulas_projeto%rowtype; photos integer; stages integer;
begin
  select * into m from public.rm_celula_tipos_equipamento where id=p_matrix;
  if not found then return jsonb_build_object('photos',0,'stages',0); end if;
  perform rm_private.engineering_pair_lock(m.celula_id,m.tipo_equipamento_id,false);
  select * into m from public.rm_celula_tipos_equipamento where id=p_matrix;
  if not m.ativo then raise exception 'Habilite o vínculo de engenharia antes de alocar.' using errcode='22023'; end if;
  select * into cp from public.rm_celulas_projeto where id=p_allocation;
  if not found or cp.projeto_id<>p_project or cp.celula_id<>m.celula_id then raise exception 'Alocação divergente do modelo.' using errcode='22023'; end if;
  insert into public.rm_fotos(projeto_id,celula_id,celula_projeto_id,celula_tipo_equipamento_id,categoria_foto,
    identificador_foto_key,titulo,descricao,numero,cadastro_foto_id,tag,sync_source)
    select p_project,m.celula_id,p_allocation,m.id,coalesce(f.categoria_foto,'obrigat_ria'),
      f.identificador_foto_key,f.titulo,f.descricao,f.numero,f.cadastro_foto_id,f.tag,'supabase'
    from public.rm_fotos f where f.projeto_id is null and f.celula_projeto_id is null and f.celula_tipo_equipamento_id=m.id and not f.lixeira;
  get diagnostics photos=row_count;
  insert into public.rm_aprovacoes_etapas(projeto_id,celula_projeto_id,celula_tipo_equipamento_id,celula_origem_id,
    celula_destino_id,bloquear_avanco_sem_aprov,status,status_cel_proj,aprovador_id,aprovadores_ids,aprovadores_retorno_ids,sync_source)
    select p_project,p_allocation,m.id,a.celula_origem_id,a.celula_destino_id,a.bloquear_avanco_sem_aprov,
      'nulo',a.status_cel_proj,a.aprovador_id,a.aprovadores_ids,a.aprovadores_retorno_ids,'supabase'
    from public.rm_aprovacoes_etapas a where a.projeto_id is null and a.celula_projeto_id is null and a.celula_tipo_equipamento_id=m.id and a.ativo;
  get diagnostics stages=row_count;
  return jsonb_build_object('photos',photos,'stages',stages);
end $$;

-- Patch the original project core retained by 017. Existing allocations keep
-- their forms, deadlines, photo slots and approvals; only NEW allocations copy.
do $upgrade$ declare definition text; old_copy text; new_copy text;
begin
  definition:=pg_get_functiondef('rm_private.web_mutate_project_core_v1(uuid,text,jsonb)'::regprocedure);
  old_copy:=$old$    if is_new then
      select * into template from public.rm_celula_tipos_equipamento
        where celula_id=cell_id and tipo_equipamento_id=project.tipo_equipamento_id;
      select coalesce(array_agg(form_id),'{}'::uuid[]) into template_forms from public.rm_celula_form_tipos_equipamento
        where celula_tipo_equipamento_id=template.id;$old$;
  new_copy:=$new$    if is_new then
      if project.tipo_equipamento_id is not null then
        perform rm_private.engineering_pair_lock(cell_id,project.tipo_equipamento_id,false);
      end if;
      select * into template from public.rm_celula_tipos_equipamento
        where celula_id=cell_id and tipo_equipamento_id=project.tipo_equipamento_id;
      if template.id is not null and not template.ativo then
        raise exception 'Habilite o vínculo de engenharia antes de alocar.' using errcode='22023'; end if;
      select coalesce(array_agg(form_id order by form_id),'{}'::uuid[]) into template_forms from public.rm_celula_form_tipos_equipamento
        where celula_tipo_equipamento_id=template.id and ativo;$new$;
  if strpos(definition,old_copy)=0 then raise exception 'Unexpected project-core materialization prelude'; end if;
  definition:=replace(definition,old_copy,new_copy);
  old_copy:=$old$      insert into public.rm_fotos(projeto_id,celula_id,celula_projeto_id,celula_tipo_equipamento_id,categoria_foto,
        identificador_foto_key,titulo,descricao,numero,sync_source)
        select project_id,cell_id,cell.id,template.id,coalesce(f.categoria_foto,'obrigat_ria'),
          f.identificador_foto_key,f.titulo,f.descricao,f.numero,'supabase'
        from public.rm_fotos f where f.projeto_id is null and f.celula_tipo_equipamento_id=template.id and not f.lixeira;
      insert into public.rm_aprovacoes_etapas(projeto_id,celula_projeto_id,celula_tipo_equipamento_id,celula_origem_id,
        celula_destino_id,bloquear_avanco_sem_aprov,status,status_cel_proj,aprovador_id,aprovadores_ids,aprovadores_retorno_ids,sync_source)
        select project_id,cell.id,template.id,a.celula_origem_id,a.celula_destino_id,a.bloquear_avanco_sem_aprov,
          'nulo',a.status_cel_proj,a.aprovador_id,a.aprovadores_ids,a.aprovadores_retorno_ids,'supabase'
        from public.rm_aprovacoes_etapas a where a.projeto_id is null and a.celula_tipo_equipamento_id=template.id;$old$;
  if strpos(definition,old_copy)=0 then raise exception 'Unexpected project-core child cloning'; end if;
  execute replace(definition,old_copy,'      perform rm_private.clone_engineering_children_v1(template.id,project_id,cell.id);');
end $upgrade$;

-- Legacy service entry point now adds only missing allocations. Never UPSERT
-- existing project cells: templates are configuration for future instances.
create or replace function public.rm_materialize_project_cells_v1(p_projeto_id uuid,
  p_data_inicio timestamptz default clock_timestamp(),p_data_limite timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare pr public.rm_projetos%rowtype; candidate record; m public.rm_celula_tipos_equipamento%rowtype;
  allocation uuid; forms uuid[]; cloned jsonb; cell_count int:=0; photo_count int:=0; stage_count int:=0;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_projeto_id::text,11));
  select * into pr from public.rm_projetos where id=p_projeto_id for update;
  if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
  if pr.tipo_equipamento_id is null then raise exception 'Informe o tipo de equipamento.' using errcode='22023'; end if;
  for candidate in select c.celula_id from public.rm_celula_tipos_equipamento c
    where c.tipo_equipamento_id=pr.tipo_equipamento_id order by c.celula_id loop
    perform rm_private.engineering_pair_lock(candidate.celula_id,pr.tipo_equipamento_id,false);
    select * into m from public.rm_celula_tipos_equipamento where celula_id=candidate.celula_id and tipo_equipamento_id=pr.tipo_equipamento_id;
    if not found or not m.ativo then continue; end if;
    select coalesce(array_agg(form_id order by form_id),'{}'::uuid[]) into forms from public.rm_celula_form_tipos_equipamento
      where celula_tipo_equipamento_id=m.id and ativo;
    insert into public.rm_celulas_projeto(projeto_id,celula_id,numero_projeto,cliente_nome_export,escopo_abreviado,
      status_historico,visibilidade,indice,data_inicio,data_limite,forms_ids,sync_source)
      values(pr.id,m.celula_id,pr.numero,pr.cliente_nome_exportacao,pr.escopo_abreviado,
        array['pendente']::public.rm_status_cel_proj_enum[],coalesce(m.visibilidade,false),
        (select coalesce(ordem,indice) from public.rm_celulas where id=m.celula_id),p_data_inicio,p_data_limite,forms,'supabase')
      on conflict(projeto_id,celula_id) do nothing returning id into allocation;
    if allocation is null then continue; end if;
    cloned:=rm_private.clone_engineering_children_v1(m.id,pr.id,allocation);
    cell_count:=cell_count+1; photo_count:=photo_count+(cloned->>'photos')::int; stage_count:=stage_count+(cloned->>'stages')::int;
  end loop;
  return jsonb_build_object('projeto_id',pr.id,'celulas_materializadas',cell_count,'fotos_clonadas',photo_count,'aprovacoes_clonadas',stage_count);
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title'));
do $$ declare definition text; needle text:='when ''delete_catalog'' then ''em.catalogs.manage'' end;'; begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
  execute replace(definition,needle,'when ''delete_catalog'' then ''em.catalogs.manage'' when ''save_engineering'' then ''em.engineering.manage'' when ''save_photo_title'' then ''em.engineering.manage'' end;');
  execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.engineering_pair_lock(uuid,uuid,boolean),rm_private.engineering_parent_lock_trigger(),
  rm_private.engineering_child_version_trigger(),rm_private.clone_engineering_children_v1(uuid,uuid,uuid),
  rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_catalog_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.rm_materialize_project_cells_v1(uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.rm_materialize_project_cells_v1(uuid,timestamptz,timestamptz) to service_role;
revoke insert,update,delete on public.rm_celula_tipos_equipamento,public.rm_celula_form_tipos_equipamento,
  public.rm_aprovacoes_etapas,public.rm_fotos,public.rm_cadastro_fotos from anon,authenticated;
notify pgrst,'reload schema';
commit;

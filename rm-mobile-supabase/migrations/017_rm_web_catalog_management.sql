-- Web catalog management. No rows, grants in the Central or outbound work are created.
begin;

create function rm_private.catalog_name_key(p_name text) returns text
language sql immutable strict set search_path='' as $$
  select lower(btrim(regexp_replace(p_name,'[[:space:]]+',' ','g')));
$$;

-- Explicitly known legacy text references, in addition to all catalog FKs and
-- public RM uuid[] fields discovered below. Names in exports are conservative
-- deletion blockers: they are never silently rewritten as current master data.
create function rm_private.catalog_text_references(p_kind text)
returns table(table_name text,column_name text) language sql immutable set search_path='' as $$
  select t,c from (values
    ('clients','rm_projetos','cliente_nome_exportacao'),
    ('clients','rm_celulas_projeto','cliente_nome_export'),
    ('cells','rm_cadastro_fotos','celula_nome'),
    ('cells','rm_celulas_projeto','depende_de'),
    ('types','rm_celulas_projeto','tipo_equipamento_nome_export'),
    ('types','rm_precificacao_orcamentaria','tipo_equipamento'),
    ('types','rm_templates_word','tipo_equipamento')
  ) v(k,t,c) where k=p_kind;
$$;

-- Both functions remain private, with the 016 wrapper as the only client entry.
alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_project_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare
  actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  kind text; target_table text; target_oid regclass; record_id uuid; expected timestamptz;
  changes jsonb; before_row jsonb; after_row jsonb; result jsonb; related jsonb:='[]';
  old_name text; new_name text; names text[]; allowed text[]; item record; found_reference boolean;
  is_new boolean; changed_name boolean; field text; max_length integer; next_number bigint;
  photo_before jsonb; photo_after jsonb; photo_id uuid;
begin
  if p_operation is null or p_operation not in ('save_catalog','delete_catalog') then
    return rm_private.web_mutate_project_core_v1(p_client_submission_id,p_operation,p_payload);
  end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or actor.perfil is distinct from 'administrador' then
    raise exception 'Cadastro restrito à administração.' using errcode='42501'; end if;
  if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
    and (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
  if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Envio inválido.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
  select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
  if found then
    if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
      raise exception 'Identificador de envio já utilizado com outro conteúdo.' using errcode='23505'; end if;
    return receipt.result||jsonb_build_object('idempotent_replay',true);
  end if;
  if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(
    case when p_operation='save_catalog' then array['kind','id','expected_updated_at','changes']
      else array['kind','id','expected_updated_at'] end))
    or not p_payload ?& array['kind','id','expected_updated_at']
    or jsonb_typeof(p_payload->'kind')<>'string' or jsonb_typeof(p_payload->'id')<>'string'
    or jsonb_typeof(p_payload->'expected_updated_at') not in ('string','null') then
    raise exception 'Campos do cadastro inválidos.' using errcode='22023'; end if;
  kind:=p_payload->>'kind';
  target_table:=case kind when 'clients' then 'rm_clientes' when 'cells' then 'rm_celulas' when 'types' then 'rm_tipos_equipamento' end;
  if target_table is null then raise exception 'Tipo de cadastro inválido.' using errcode='22023'; end if;
  begin record_id:=(p_payload->>'id')::uuid; expected:=(p_payload->>'expected_updated_at')::timestamptz;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'Identificador ou versão inválidos.' using errcode='22023'; end;
  if record_id is null or (expected is not null and not isfinite(expected)) then
    raise exception 'Identificador ou versão inválidos.' using errcode='22023'; end if;
  target_oid:=('public.'||target_table)::regclass;

  -- Serialize master-data edits, including MAX+1 and name checks. Lock soft-link
  -- tables before the parent row, so concurrent array/text writers cannot pass
  -- the reference check. FK writers use PostgreSQL's parent key locks.
  perform pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17));
  begin
    execute format('lock table public.%I in share row exclusive mode nowait',target_table);
    if p_operation='delete_catalog' then
      for item in
        select distinct table_name from rm_private.catalog_text_references(kind)
        union select c.relname from pg_attribute a join pg_class c on c.oid=a.attrelid
          join pg_namespace n on n.oid=c.relnamespace
          where n.nspname='public' and c.relkind='r' and c.relname like 'rm\_%' escape '\'
            and a.attnum>0 and not a.attisdropped and a.atttypid='uuid[]'::regtype
        order by 1
      loop execute format('lock table public.%I in share row exclusive mode nowait',item.table_name); end loop;
    elsif kind='cells' and p_payload->'changes'?'nome' then
      lock table public.rm_cadastro_fotos in share row exclusive mode nowait;
    end if;
  exception when lock_not_available then
    -- Never wait while holding a partial set of table locks against a mobile
    -- transaction that acquires its operational tables in a different order.
    raise exception 'Cadastro em atualização. Atualize e tente novamente.' using errcode='PT409';
  end;
  execute format('select to_jsonb(t) from public.%I t where id=$1 for update',target_table) into before_row using record_id;
  is_new:=before_row is null;
  if (is_new and (expected is not null or p_operation='delete_catalog'))
    or (not is_new and (expected is null or expected<>(before_row->>'updated_at')::timestamptz)) then
    raise exception 'Cadastro alterado. Atualize antes de salvar.' using errcode='PT409'; end if;
  old_name:=before_row->>'nome';

  if p_operation='delete_catalog' then
    -- Include prior names recorded by this API, so renaming cannot bypass a
    -- legacy text reference. No sensitive/credential tables are inspected.
    select array_agg(distinct rm_private.catalog_name_key(name)) into names from (
      select old_name name union all select r.before_record->>'nome' from rm_private.web_mutation_receipts r
      where r.operation='save_catalog' and r.payload->>'kind'=kind and r.payload->>'id'=record_id::text
    ) aliases where name is not null;
    for item in
      select n.nspname,c.relname,a.attname from pg_constraint f
        join pg_class c on c.oid=f.conrelid join pg_namespace n on n.oid=c.relnamespace
        join pg_attribute a on a.attrelid=f.conrelid and a.attnum=f.conkey[1]
      where f.contype='f' and f.confrelid=target_oid and cardinality(f.conkey)=1
    loop
      execute format('select exists(select 1 from %I.%I where %I=$1)',item.nspname,item.relname,item.attname)
        into found_reference using record_id;
      if found_reference then raise exception 'Cadastro em uso; exclusão não permitida.' using errcode='23503'; end if;
    end loop;
    -- Fail closed if a future migration adds a compound FK not handled above.
    if exists(select 1 from pg_constraint where contype='f' and confrelid=target_oid and cardinality(conkey)<>1) then
      raise exception 'Cadastro possui referência que requer revisão.' using errcode='23503'; end if;
    for item in select c.relname,a.attname from pg_attribute a join pg_class c on c.oid=a.attrelid
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'
        and c.relname like 'rm\_%' escape '\' and a.attnum>0 and not a.attisdropped and a.atttypid='uuid[]'::regtype
    loop
      execute format('select exists(select 1 from public.%I where $1=any(%I))',item.relname,item.attname)
        into found_reference using record_id;
      if found_reference then raise exception 'Cadastro em uso; exclusão não permitida.' using errcode='23503'; end if;
    end loop;
    for item in select * from rm_private.catalog_text_references(kind) loop
      execute format('select exists(select 1 from public.%I where rm_private.catalog_name_key(%I)=any($1) or %I=$2 or %I=$3%s)',
        item.table_name,item.column_name,item.column_name,item.column_name,
        case when item.column_name='depende_de' then
          ' or exists(select 1 from unnest($1) n where strpos(rm_private.catalog_name_key(depende_de),n)>0)' else '' end)
        into found_reference using names,record_id::text,before_row->>'bubble_id';
      if found_reference then raise exception 'Cadastro em uso; exclusão não permitida.' using errcode='23503'; end if;
    end loop;
    execute format('delete from public.%I where id=$1',target_table) using record_id;
    after_row:=before_row;
  else
    changes:=p_payload->'changes';
    allowed:=case kind when 'clients' then array['nome','codigo','descricao']
      when 'cells' then array['nome','codigo','indice','ordem'] else array['nome','sigla'] end;
    if changes is null or jsonb_typeof(changes)<>'object' or changes='{}'::jsonb
      or exists(select 1 from jsonb_object_keys(changes) k where not k=any(allowed)) then
      raise exception 'Alterações de cadastro inválidas.' using errcode='22023'; end if;
    if is_new and not changes?'nome' then raise exception 'Informe o nome.' using errcode='22023'; end if;
    foreach field in array allowed loop
      if not changes?field then continue; end if;
      if field in ('indice','ordem') then
        if jsonb_typeof(changes->field) not in ('number','null') then
          raise exception 'Ordem e índice devem ser números.' using errcode='22023'; end if;
        if changes->field<>'null'::jsonb and ((changes->>field)::numeric<0 or (changes->>field)::numeric>1000000
          or (changes->>field)::numeric<>trunc((changes->>field)::numeric)) then
          raise exception 'Ordem e índice devem ser inteiros entre 0 e 1000000.' using errcode='22023'; end if;
      else
        if jsonb_typeof(changes->field) not in ('string','null') then
          raise exception 'Texto do cadastro inválido.' using errcode='22023'; end if;
        max_length:=case field when 'nome' then 200 when 'codigo' then 80 when 'sigla' then 30 else 4000 end;
        changes:=jsonb_set(changes,array[field],coalesce(to_jsonb(nullif(regexp_replace(changes->>field,'^[[:space:]]+|[[:space:]]+$','','g'),'')),'null'::jsonb));
        if length(changes->>field)>max_length then raise exception 'Texto excede o limite do campo.' using errcode='22023'; end if;
      end if;
    end loop;
    new_name:=case when changes?'nome' then changes->>'nome' else old_name end;
    if new_name is null or rm_private.catalog_name_key(new_name)='' then raise exception 'Informe o nome.' using errcode='22023'; end if;
    changed_name:=is_new or new_name is distinct from old_name;
    if changed_name then
      execute format('select exists(select 1 from public.%I where id<>$1 and rm_private.catalog_name_key(nome)=rm_private.catalog_name_key($2))',target_table)
        into found_reference using record_id,new_name;
      if found_reference then raise exception 'Já existe cadastro com esse nome.' using errcode='23505'; end if;
    end if;
    if kind='cells' and changed_name then
      if is_new or rm_private.catalog_name_key(new_name) is distinct from rm_private.catalog_name_key(old_name) then
        if exists(select 1 from public.rm_cadastro_fotos where rm_private.catalog_name_key(celula_nome)=rm_private.catalog_name_key(new_name)) then
          raise exception 'Nome possui vínculos de fotos sem associação inequívoca.' using errcode='23503'; end if;
      end if;
      if not is_new and exists(select 1 from public.rm_cadastro_fotos where rm_private.catalog_name_key(celula_nome)=rm_private.catalog_name_key(old_name)) then
        if exists(select 1 from public.rm_celulas where id<>record_id and rm_private.catalog_name_key(nome)=rm_private.catalog_name_key(old_name)) then
          raise exception 'Célula possui vínculos de fotos ambíguos.' using errcode='23503'; end if;
        for photo_id,photo_before in select id,to_jsonb(f) from public.rm_cadastro_fotos f
          where rm_private.catalog_name_key(celula_nome)=rm_private.catalog_name_key(old_name) order by id for update loop
          update public.rm_cadastro_fotos set celula_nome=new_name,sync_source='supabase' where id=photo_id returning to_jsonb(rm_cadastro_fotos) into photo_after;
          related:=related||jsonb_build_array(jsonb_build_object('table','rm_cadastro_fotos','id',photo_id,'before',photo_before,'after',photo_after));
        end loop;
      end if;
    end if;
    if kind='cells' and is_new then
      foreach field in array array['indice','ordem'] loop
        if not changes?field or changes->field='null'::jsonb then
          execute format('select greatest(coalesce(max(%I),0),0)::bigint+1 from public.rm_celulas',field) into next_number;
          if next_number>1000000 then raise exception 'Limite de ordenação atingido.' using errcode='22023'; end if;
          changes:=jsonb_set(changes,array[field],to_jsonb(next_number));
        end if;
      end loop;
    end if;
    if is_new then
      -- Only whitelisted columns are populated; database defaults remain intact.
      select string_agg(format('%I',k),',' order by k) as columns,string_agg(format('v.%I',k),',' order by k) as values
        into item from jsonb_object_keys(changes) k;
      execute format('insert into public.%I(id,%s) select $1,%s from jsonb_populate_record(null::public.%I,$2) v returning to_jsonb(%I)',
        target_table,item.columns,item.values,target_table,target_table) into after_row using record_id,changes;
    else
      select string_agg(format('%I=v.%I',k,k),',' order by k) as assignments into item from jsonb_object_keys(changes) k;
      execute format('update public.%I t set %s,sync_source=''supabase'' from jsonb_populate_record(null::public.%I,$2) v where t.id=$1 returning to_jsonb(t)',
        target_table,item.assignments,target_table) into after_row using record_id,changes;
    end if;
  end if;
  result:=jsonb_build_object('operation',p_operation,'id',record_id,'projeto_id',null,'updated_at',after_row->'updated_at',
    'record',after_row,'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,
      case when related='[]'::jsonb then before_row else before_row||jsonb_build_object('_related_changes',related) end);
  return result;
end $$;

-- Widen only the supported operations; retain session, payload hash, TTL, MFA
-- and single-use permit checks implemented by 016.
alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog'));
do $$ declare definition text; needle text:='when ''review_form'' then ''em.forms.review'' end;';
begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected SSO permit definition'; end if;
  execute replace(definition,needle,'when ''review_form'' then ''em.forms.review'' when ''save_catalog'' then ''em.catalogs.manage'' when ''delete_catalog'' then ''em.catalogs.manage'' end;');
end $$;
-- Recompile the existing public body explicitly. Sessions that used 016 before
-- this migration must discard any PL/pgSQL plan pointing to the renamed core.
do $$ begin execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure); end $$;
alter function public.rm_web_mutate_v1(uuid,text,jsonb) set lock_timeout='10s';
revoke all on function rm_private.catalog_name_key(text),rm_private.catalog_text_references(text),
  rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_project_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke insert,update,delete on public.rm_clientes,public.rm_celulas,public.rm_tipos_equipamento from anon,authenticated;
notify pgrst,'reload schema';
commit;

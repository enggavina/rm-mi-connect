begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_cell_operator_events (
  cell_id uuid not null,
  operator_id uuid not null,
  revision integer not null check(revision > 0),
  workshop_id uuid not null,
  actor_id uuid not null,
  grant_id uuid not null,
  enabled boolean not null,
  recorded_at timestamptz not null default clock_timestamp(),
  primary key (cell_id,operator_id,revision)
);
alter table rm_private.workshop_cell_operator_events enable row level security;
revoke all on rm_private.workshop_cell_operator_events from public,anon,authenticated,service_role;

create function public.rm_sso_cell_operators_v1(p_session_hash text,p_context jsonb,p_members jsonb,p_cell uuid,p_change jsonb default null)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $function$
declare
  authority_issuer constant text := 'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1';
  viewer uuid; actor uuid; session_expires timestamptz;
  office uuid; issued timestamptz; expires timestamptz; principal jsonb;
  operator uuid; desired boolean; expected_revision integer; latest rm_private.workshop_cell_operator_events;
  grant_row uuid;
begin
  select b.subject,u.id,s.expires_at into viewer,actor,session_expires
    from rm_private.sso_sessions s join rm_private.sso_identity_bindings b on b.id=s.binding_id
    join public.rm_users u on u.id=b.rm_user_id and u.auth_user_id=b.auth_user_id
    join auth.sessions a on a.id=s.local_session_id and a.user_id=b.auth_user_id
    where s.hash=p_session_hash and b.enabled and b.issuer=authority_issuer and u.status='ativo' and u.perfil='administrador'
    for share of b,s,u,a;
  if not found or session_expires<=clock_timestamp() then
    raise exception 'Sessão de administração indisponível.' using errcode='42501';
  end if;
  principal:=p_context->'principals'->0;
  if p_cell is null or p_context->'version' is distinct from '2'::jsonb
    or p_context->>'application' is distinct from 'em' or p_context->>'channel' is distinct from 'web'
    or p_context->>'authority' is distinct from authority_issuer or p_context->'workshop'->'active' is distinct from 'true'::jsonb
    or jsonb_typeof(p_context->'principals') is distinct from 'array' or jsonb_array_length(p_context->'principals')<>1
    or principal->>'kind' is distinct from 'corporate' or principal->>'issuer' is distinct from authority_issuer
    or principal->>'subject' is distinct from viewer::text then
    raise exception 'Contexto de oficina inválido.' using errcode='42501';
  end if;
  issued:=(p_context->>'issued_at')::timestamptz;
  expires:=(p_context->>'expires_at')::timestamptz;
  if issued is null or expires is null or abs(extract(epoch from clock_timestamp()-issued))>10
    or expires<=clock_timestamp() or expires<=issued or expires-issued>interval '20 seconds' then
    raise exception 'Contexto de oficina expirado.' using errcode='42501';
  end if;
  select w.id into office from rm_private.workshop_references w
    join rm_private.workshop_cell_ownership o on o.workshop_id=w.id and o.cell_id=p_cell
    where w.id=(p_context->'workshop'->>'id')::uuid and w.code=p_context->'workshop'->>'code'
      and w.authority=authority_issuer for share of w,o;
  if not found then raise exception 'Célula indisponível nesta oficina.' using errcode='42501'; end if;
  -- Reuse the team contract to reject malformed, duplicated or unrelated rosters.
  perform rm_private.workshop_assignment_ids_v1(p_members,viewer);
  if expires<=clock_timestamp() or session_expires<=clock_timestamp() then
    raise exception 'Contexto de oficina expirado.' using errcode='42501';
  end if;

  if p_change is not null then
    if p_change is distinct from jsonb_build_object('operator',p_change->'operator','enabled',p_change->'enabled','revision',p_change->'revision')
      or jsonb_typeof(p_change->'operator') is distinct from 'string'
      or jsonb_typeof(p_change->'enabled') is distinct from 'boolean'
      or jsonb_typeof(p_change->'revision') is distinct from 'number'
      or p_change->>'revision' !~ '^(0|[1-9][0-9]{0,9})$' then
      raise exception 'Confira o operador e o vínculo.' using errcode='22023';
    end if;
    operator:=(p_change->>'operator')::uuid;
    desired:=(p_change->>'enabled')::boolean;
    expected_revision:=(p_change->>'revision')::integer;
    -- Serialize even the first grant. After waiting, recheck the short-lived authority.
    perform pg_advisory_xact_lock(hashtextextended(p_cell::text||':'||operator::text,135));
    if expires<=clock_timestamp() or session_expires<=clock_timestamp() then
      raise exception 'Contexto de oficina expirado.' using errcode='42501';
    end if;
    select * into latest from rm_private.workshop_cell_operator_events
      where cell_id=p_cell and operator_id=operator order by revision desc limit 1;
    if latest.revision is not null and latest.workshop_id<>office then
      raise exception 'Vínculo indisponível nesta oficina.' using errcode='42501';
    end if;
    if expected_revision<>coalesce(latest.revision,0) then
      raise exception 'O vínculo mudou. Recarregue a célula.' using errcode='PT409';
    end if;
    if latest.enabled then
      select t.id into grant_row from public.rm_tablet_celula_users t
        where t.id=latest.grant_id and t.celula_id=p_cell and t.identidade_id=operator
          and t.bubble_id is null and t.tablet_id is null and t.usuario_id is null for update;
    end if;
    if desired then
      if not (p_members @> jsonb_build_array(jsonb_build_object('kind','operator','subject',operator))) then
        raise exception 'O operador precisa de vínculo ativo nesta oficina.' using errcode='42501';
      end if;
      perform 1 from public.rm_users where id=operator and status='ativo' and perfil<>'administrador'
        and nullif(btrim(matricula),'') is not null for share;
      if not found then raise exception 'Operador indisponível para esta célula.' using errcode='42501'; end if;
      if exists(select 1 from public.rm_tablet_celula_users where celula_id=p_cell and identidade_id=operator) then
        return jsonb_build_object('changed',false);
      end if;
      insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(p_cell,operator) returning id into grant_row;
    else
      if grant_row is null then return jsonb_build_object('changed',false); end if;
      delete from public.rm_tablet_celula_users where id=grant_row;
    end if;
    insert into rm_private.workshop_cell_operator_events(cell_id,operator_id,revision,workshop_id,actor_id,grant_id,enabled)
      values(p_cell,operator,expected_revision+1,office,actor,grant_row,desired);
    return jsonb_build_object('changed',true);
  end if;

  return (
    with roster as (
      select u.id,u.nome,u.matricula,u.perfil
      from jsonb_to_recordset(p_members) m(kind text,subject uuid) join public.rm_users u on u.id=m.subject
      where m.kind='operator' and u.status='ativo' and nullif(btrim(u.matricula),'') is not null
    ), events as (
      select distinct on (operator_id) operator_id,revision,grant_id,enabled
      from rm_private.workshop_cell_operator_events
      where cell_id=p_cell and workshop_id=office order by operator_id,revision desc
    ), resolved as (
      select coalesce(r.id,e.operator_id) as id, r.nome,r.matricula, r.id is not null as eligible,
        coalesce(r.perfil='administrador',false) as automatic,
        coalesce(e.revision,0) as revision,
        exists(select 1 from public.rm_tablet_celula_users t where t.celula_id=p_cell and t.identidade_id=e.operator_id
          and t.id=e.grant_id and t.bubble_id is null and t.tablet_id is null and t.usuario_id is null and e.enabled) as managed,
        exists(select 1 from public.rm_tablet_celula_users t where t.celula_id=p_cell and t.identidade_id=r.id
          and (t.id is distinct from e.grant_id or not e.enabled
            or t.bubble_id is not null or t.tablet_id is not null or t.usuario_id is not null)) as legacy
      from roster r full join events e on e.operator_id=r.id
    )
    select coalesce(jsonb_agg(to_jsonb(resolved) order by nome nulls last,id),'[]')
    from resolved where eligible or managed
  );
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
  raise exception 'Confira os dados do vínculo.' using errcode='22023';
end;
$function$;

revoke all on function public.rm_sso_cell_operators_v1(text,jsonb,jsonb,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_cell_operators_v1(text,jsonb,jsonb,uuid,jsonb) to service_role;
notify pgrst,'reload schema';
commit;

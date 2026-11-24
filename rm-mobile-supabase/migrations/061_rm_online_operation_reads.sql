-- Online operation reads are available only to the trusted application server.
-- The server verifies the password JWT and obtains the current context from Acessos.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';

create function rm_private.online_operator_identity_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text
) returns table(device_subject uuid, operator_subject uuid, operator_name text, expires_at timestamptz)
language sql stable set search_path = '' as $$
  select d.auth_user_id, o.id, o.nome,
    least(d.expires_at, d.created_at + interval '24 hours', session_expiry.expires_at)
  from rm_private.operator_delegations d
  join auth.sessions s on s.id = p_session_id and s.user_id = d.auth_user_id
  join public.rm_users t on t.id = d.tablet_user_id and t.auth_user_id = d.auth_user_id and t.status = 'ativo'
  join public.rm_users o on o.id = d.operator_id and o.status = 'ativo'
  cross join lateral (select (to_jsonb(s)->>'not_after')::timestamptz expires_at) session_expiry
  where d.auth_user_id = p_auth_user_id and not d.revoked
    and p_operator_token ~ '^[0-9a-f]{64}$' and d.token_hash = extensions.digest(p_operator_token, 'sha256')
    and least(d.expires_at, d.created_at + interval '24 hours', session_expiry.expires_at) > statement_timestamp()
    and (to_jsonb(s)->>'aal' = 'aal2' or not exists (
      select 1 from auth.mfa_factors f where f.user_id = d.auth_user_id and f.status = 'verified'
    ));
$$;

create function public.rm_online_operator_identity_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text
) returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(i)
  from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
$$;

create function rm_private.online_workshop_context_v1(p_context jsonb, p_device uuid, p_operator uuid)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  workshop jsonb;
  principal jsonb;
  issued timestamptz;
  expires timestamptz;
  office uuid;
  principal_index int;
begin
  if jsonb_typeof(p_context) is distinct from 'object' or octet_length(p_context::text) > 65536
    or (select array_agg(k order by k) from jsonb_object_keys(p_context) k) is distinct from
      array['application','authority','channel','expires_at','issued_at','principals','version','workshop']
    or p_context->'version' is distinct from '2'::jsonb or p_context->>'application' is distinct from 'em'
    or p_context->>'channel' is distinct from 'mobile'
    or p_context->>'authority' is distinct from 'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
    or jsonb_typeof(p_context->'workshop') is distinct from 'object'
    or jsonb_typeof(p_context->'principals') is distinct from 'array'
    or jsonb_typeof(p_context->'issued_at') is distinct from 'string'
    or jsonb_typeof(p_context->'expires_at') is distinct from 'string' then
    return null;
  end if;

  workshop := p_context->'workshop';
  if (select array_agg(k order by k) from jsonb_object_keys(workshop) k) is distinct from
      array['active','code','id','name','revision','updated_at']
    or workshop->'active' is distinct from 'true'::jsonb
    or jsonb_typeof(workshop->'name') is distinct from 'string'
    or length(workshop->>'name') not between 1 and 200 or workshop->>'name' <> btrim(workshop->>'name')
    or workshop->>'name' ~ '[[:cntrl:]]'
    or jsonb_typeof(workshop->'id') is distinct from 'string'
    or jsonb_typeof(workshop->'code') is distinct from 'string'
    or jsonb_typeof(workshop->'revision') is distinct from 'number'
    or workshop->>'revision' !~ '^[1-9][0-9]{0,15}$' or (workshop->>'revision')::numeric > 9007199254740991
    or jsonb_typeof(workshop->'updated_at') is distinct from 'string'
    or jsonb_array_length(p_context->'principals') <> 2 then
    return null;
  end if;
  for principal_index in 0..1 loop
    principal := p_context->'principals'->principal_index;
    if jsonb_typeof(principal) is distinct from 'object'
      or (select array_agg(k order by k) from jsonb_object_keys(principal) k) is distinct from
        array['issuer','kind','revision','subject']
      or principal->>'issuer' is distinct from 'https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1'
      or principal->>'kind' is distinct from (case principal_index when 0 then 'device' else 'operator' end)
      or principal->>'subject' is distinct from (case principal_index when 0 then p_device else p_operator end)::text
      or jsonb_typeof(principal->'revision') is distinct from 'number'
      or principal->>'revision' !~ '^[1-9][0-9]{0,15}$' or (principal->>'revision')::numeric > 9007199254740991 then
      return null;
    end if;
  end loop;

  issued := (p_context->>'issued_at')::timestamptz;
  expires := (p_context->>'expires_at')::timestamptz;
  if not isfinite(issued) or not isfinite(expires) or not isfinite((workshop->>'updated_at')::timestamptz)
    or abs(extract(epoch from statement_timestamp()-issued)) > 15 or expires <= statement_timestamp()
    or expires <= issued or expires > issued + interval '5 minutes' then
    return null;
  end if;
  select id into office from rm_private.workshop_references
  where id::text = workshop->>'id' and code = workshop->>'code' and authority = p_context->>'authority';
  return office;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
  return null;
end;
$$;

create function public.rm_online_operation_read_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text,
  p_workshop_context jsonb, p_cell_id uuid, p_project_id uuid, p_page integer
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  operator_id uuid;
  office_id uuid;
  cell jsonb;
  result jsonb;
begin
  select i.operator_subject into operator_id
  from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
  if operator_id is null or p_page is null or p_page not between 1 and 10000
    or (p_project_id is not null and p_cell_id is null) then
    return null;
  end if;
  office_id := rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,operator_id);
  if office_id is null then return null; end if;

  if p_cell_id is null then
    select jsonb_build_object('kind','cells','items',coalesce(
      jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome) order by coalesce(c.indice,c.ordem,0),c.nome,c.id),
      '[]'::jsonb
    )) into result
    from public.rm_celulas c join rm_private.workshop_cell_ownership o on o.cell_id = c.id and o.workshop_id = office_id
    where rm_private.operator_can_access_cell(operator_id,c.id);
    return result;
  end if;

  select jsonb_build_object('id',c.id,'nome',c.nome) into cell
  from public.rm_celulas c
  where c.id = p_cell_id and rm_private.workshop_cell_owned_v1(c.id,office_id)
    and rm_private.operator_can_access_cell(operator_id,c.id);
  if cell is null then return null; end if;

  with visible as materialized (
    select p.id, a.status = 'retornado' as returned, coalesce(a.posicao,a.indice,0) as position,
      a.forms_ids,
      jsonb_build_object('id',p.id,'numero',coalesce(nullif(p.numero,''),nullif(a.numero_projeto,'')),
        'nome',p.nome,'cliente',c.nome,'descricao',coalesce(nullif(p.descricao_equipamento,''),e.descricao),
        'status',a.status) as project
    from public.rm_celulas_projeto a
    join public.rm_projetos p on p.id = a.projeto_id
    join rm_private.workshop_project_ownership o on o.id = p.id and o.workshop_id = office_id
    left join public.rm_equipamentos e on e.projeto_id = p.id and e.id = p.equipamento_id
    left join public.rm_clientes c on c.id = p.cliente_id and rm_private.workshop_read_owned_v1('client',c.id,office_id)
    where a.celula_id = p_cell_id and a.visibilidade and not a.retirada
      and p.data_real_de_entrega is null
      and p.status_pcp is distinct from 'cancelado' and p.status_pcp is distinct from 'finalizando_para_faturar'
      and (p_project_id is null or p.id = p_project_id)
  ), page_rows as (
    select * from visible order by returned desc,position,id limit 25 offset (p_page-1)*25
  )
  select case when p_project_id is null then
    jsonb_build_object('kind','projects','cell',cell,'items',coalesce(
      (select jsonb_agg(project order by returned desc,position,id) from page_rows),'[]'::jsonb),
      'page',p_page,'page_size',25,'total',(select count(*) from visible))
  else (
    select jsonb_build_object('kind','project','cell',cell,'project',v.project,'forms',coalesce(
      (select jsonb_agg(jsonb_build_object('id',f.id,'titulo',f.titulo) order by array_position(v.forms_ids,f.id),f.id)
        from public.rm_forms f where f.id = any(v.forms_ids) and f.ativo
          and rm_private.workshop_read_visible_v1('form_model',f.id,office_id)), '[]'::jsonb))
    from visible v
  ) end into result;
  return result;
end;
$$;

revoke all on function rm_private.online_operator_identity_v1(uuid,uuid,text),
  rm_private.online_workshop_context_v1(jsonb,uuid,uuid), public.rm_online_operator_identity_v1(uuid,uuid,text),
  public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.rm_online_operator_identity_v1(uuid,uuid,text),
  public.rm_online_operation_read_v1(uuid,uuid,text,jsonb,uuid,uuid,integer) to service_role;
notify pgrst, 'reload schema';
commit;

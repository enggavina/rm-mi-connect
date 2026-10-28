-- The Bubble settings_rm registration binds Identidade to the operator and
-- Usuario to the shared login account. Login must never rewrite these grants.
begin;

create or replace function rm_private.operator_can_access_cell(p_operator uuid,p_cell uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.rm_users u join public.rm_celulas c on c.id=p_cell
    where u.id=p_operator and u.status='ativo' and (u.perfil='administrador' or
      exists(select 1 from public.rm_tablet_celula_users t where t.identidade_id=u.id and t.celula_id=c.id)));
$$;

create or replace function rm_private.operator_context(p_operator uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('operador_id',u.id,'bubble_id',u.bubble_id,'matricula',u.matricula,
    'nome',u.nome,'cargo',u.cargo,'perfil',u.perfil,'perfil_assinante',u.perfil_assinante,
    'equipe_id',u.equipe_id,'criar_form',u.criar_form,'cell_access_policy_version',2,
    'celulas_vinculadas',coalesce((select jsonb_agg(jsonb_build_object('celula_id',c.id,
      'bubble_id',c.bubble_id,'codigo',c.codigo,'nome',c.nome,'ordem',c.ordem)
      order by c.ordem nulls last,c.indice nulls last,c.id)
      from public.rm_celulas c where rm_private.operator_can_access_cell(u.id,c.id)),'[]'::jsonb))
  from public.rm_users u where u.id=p_operator and u.status='ativo';
$$;

-- Keep this internal signature for compatibility; p_tablet is the legacy name.
-- All gateway callers below now pass the authenticated OPERATOR ID.
create or replace function rm_private.assert_cell_access(p_tablet uuid,p_cell uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not rm_private.operator_can_access_cell(p_tablet,p_cell) then
    raise exception 'Operador sem permissão cadastrada para esta célula.' using errcode='42501';
  end if;
end $$;

create or replace function rm_private.rm_authenticate_operator_v1(
  p_matricula text,p_palavra_chave text,p_tablet_user_id uuid default null,
  p_celula_id uuid default null,p_ip text default null,p_local text default 'rm_mobile'
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_user public.rm_users%rowtype;
  v_cred rm_private.user_credentials%rowtype;
  v_password_ok boolean:=false;
begin
  if p_matricula is null or btrim(p_matricula)='' or p_palavra_chave is null or p_palavra_chave='' then
    raise exception 'Matrícula e palavra-chave são obrigatórias.' using errcode='28000';
  end if;
  select * into v_user from public.rm_users where lower(btrim(matricula))=lower(btrim(p_matricula)) limit 1;
  if not found or v_user.status<>'ativo' then
    raise exception 'Operador não encontrado ou inativo.' using errcode='28000';
  end if;
  select * into v_cred from rm_private.user_credentials where user_id=v_user.id;
  if found then
    if v_cred.palavra_chave_hash is not null then
      v_password_ok:=(v_cred.palavra_chave_hash=extensions.crypt(p_palavra_chave,v_cred.palavra_chave_hash));
    elsif v_cred.palavra_chave_legacy_plain is not null then
      v_password_ok:=(v_cred.palavra_chave_legacy_plain=p_palavra_chave);
      if v_password_ok then
        update rm_private.user_credentials set palavra_chave_hash=extensions.crypt(p_palavra_chave,extensions.gen_salt('bf',10)),
          palavra_chave_legacy_plain=null,updated_at=clock_timestamp() where user_id=v_user.id;
      end if;
    end if;
  end if;
  if not v_password_ok then raise exception 'Palavra-chave inválida.' using errcode='28P01'; end if;
  if p_celula_id is not null then perform rm_private.assert_cell_access(v_user.id,p_celula_id); end if;
  update public.rm_users set ultimo_acesso=clock_timestamp(),tentativas_login=0 where id=v_user.id;
  insert into public.rm_eventos_sistema(user_id,tipo,ip,local,sync_source) values(v_user.id,'identidade',p_ip,p_local,'supabase');
  return rm_private.operator_context(v_user.id)||jsonb_build_object('authenticated_at',clock_timestamp());
end $$;

-- Refresh permissions without accepting credentials or granting a new session.
create or replace function public.rm_operator_context_v1(p_operator_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d rm_private.operator_delegations%rowtype; result jsonb;
begin
  select * into d from rm_private.operator_delegations where
    token_hash=extensions.digest(p_operator_token,'sha256') and auth_user_id=auth.uid()
    and not revoked and expires_at>clock_timestamp();
  if not found or rm_private.current_rm_user_id() is distinct from d.tablet_user_id then
    raise exception 'Identifique novamente o operador neste dispositivo.' using errcode='28000';
  end if;
  result:=rm_private.operator_context(d.operator_id);
  if result is null then raise exception 'Operador inativo.' using errcode='28000'; end if;
  return result||jsonb_build_object('authenticated_at',d.created_at,'token_expires_at',d.expires_at);
end $$;

do $migration$
declare definition text;
begin
  definition:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,'assert_cell_access(d.tablet_user_id,')=0 then
    raise exception 'Unexpected gateway definition: missing legacy tablet access checks';
  end if;
  definition:=replace(definition,'assert_cell_access(d.tablet_user_id,','assert_cell_access(d.operator_id,');
  definition:=replace(definition,
    'where id=d.tablet_user_id and perfil=''administrador''',
    'where id=d.operator_id and perfil=''administrador''');
  definition:=replace(definition,
    't.usuario_id=d.tablet_user_id','t.identidade_id=d.operator_id');
  definition:=replace(definition,'Projeto do QR Code não está disponível neste dispositivo.',
    'Projeto do QR Code não está disponível para este operador.');
  execute definition;
end $migration$;

revoke all on function rm_private.operator_can_access_cell(uuid,uuid),rm_private.operator_context(uuid),
  rm_private.assert_cell_access(uuid,uuid),rm_private.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.rm_operator_context_v1(text) from public,anon;
grant execute on function public.rm_operator_context_v1(text) to authenticated;
notify pgrst, 'reload schema';
commit;

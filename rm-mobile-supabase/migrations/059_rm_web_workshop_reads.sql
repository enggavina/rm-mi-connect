-- Selected portal readers only. Legacy/mobile RLS and other consumers are unchanged.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create table rm_private.workshop_read_permits (
 read_id uuid primary key,session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 resource text not null check(resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices')),
 args_hash bytea not null,workshop_id uuid not null references rm_private.workshop_references(id),subject uuid not null,
 expires_at timestamptz not null,created_at timestamptz not null default clock_timestamp()
);
create index workshop_read_permits_session on rm_private.workshop_read_permits(session_hash);
alter table rm_private.workshop_read_permits enable row level security;
revoke all on rm_private.workshop_read_permits from public,anon,authenticated,service_role;

-- Exact 057 authority validator, without creating a mutation permission/receipt.
do $build$declare d text;marker text:=' -- The existing action permit';begin
 d:=pg_get_functiondef('public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 if strpos(d,marker)=0 or strpos(d,'p_operation not in(''save_catalog'',''delete_catalog'')')=0 then raise exception 'Unexpected 057 authority validator';end if;
 d:=left(d,strpos(d,marker)-1);
 d:=replace(d,'public.rm_sso_catalog_workshop_permit_v1(','public.rm_sso_workshop_read_permit_v1(');
 d:=replace(d,'p_submission_id','p_read_id');d:=replace(d,'p_operation','p_resource');d:=replace(d,'p_payload','p_args');
 d:=replace(d,'p_resource not in(''save_catalog'',''delete_catalog'')','p_resource not in(''catalog_list'',''catalog_entry'',''template_list'',''template_draft'',''template_form'',''template_choices'')');
 d:=replace(d,' or p_args->>''kind'' is null or p_args->>''kind'' not in(''clients'',''types'')',' or octet_length(p_args::text)>4096');
 d:=d||$tail$
 if not exists(select 1 from public.rm_users where id=binding.rm_user_id and auth_user_id=binding.auth_user_id and status='ativo' and perfil in('administrador','padr_o','auditor'))
  or not exists(select 1 from auth.sessions where id=sess.local_session_id and user_id=binding.auth_user_id) then raise exception using errcode='42501',message='Sessão de leitura indisponível.';end if;
 insert into rm_private.workshop_read_permits(read_id,session_hash,resource,args_hash,workshop_id,subject,expires_at)
  values(p_read_id,p_session_hash,p_resource,extensions.digest(p_args::text,'sha256'),office,binding.subject,least(expires,sess.expires_at,clock_timestamp()+interval '15 seconds'));
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception using errcode='22023',message='Contexto de leitura inválido.';
end;
$function$;
$tail$;
 execute d;
end$build$;
revoke all on function public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

create function rm_private.workshop_read_owned_v1(p_kind text,p_id uuid,p_office uuid) returns boolean language sql stable set search_path='' as $$
 select case when p_id is null or p_office is null then false
 when p_kind in('client','equipment_type','form_model') then exists(select 1 from rm_private.workshop_catalog_ownership o where o.object_kind=p_kind and o.object_id=p_id and o.workshop_id=p_office
  and not exists(select 1 from rm_private.workshop_catalog_retirements r where r.object_kind=p_kind and r.object_id=p_id))
 when p_kind in('family','draft') then exists(select 1 from rm_private.workshop_template_ownership o where o.object_kind=p_kind and o.object_id=p_id and o.workshop_id=p_office
  and not exists(select 1 from rm_private.workshop_template_retirements r where r.object_kind=p_kind and r.object_id=p_id)) else false end;
$$;
create function rm_private.workshop_read_visible_v1(p_kind text,p_id uuid,p_office uuid) returns boolean language sql stable set search_path='' as $$
 select rm_private.workshop_read_owned_v1(p_kind,p_id,p_office) and case p_kind
 when 'draft' then exists(select 1 from public.rm_form_template_drafts d where d.id=p_id
  and rm_private.workshop_read_owned_v1('family',d.family_id,p_office)
  and(d.source_form_id is null or rm_private.workshop_read_owned_v1('form_model',d.source_form_id,p_office))
  and(d.published_form_id is null or rm_private.workshop_read_owned_v1('form_model',d.published_form_id,p_office))
  and not exists(select 1 from public.rm_form_template_versions v where v.draft_id=d.id and(v.family_id<>d.family_id or v.form_id is distinct from d.published_form_id))
  and(d.state='draft' or exists(select 1 from public.rm_form_template_versions v where v.draft_id=d.id and v.form_id=d.published_form_id and v.family_id=d.family_id)))
 when 'form_model' then exists(select 1 from public.rm_forms f where f.id=p_id and not exists(select 1 from public.rm_form_template_versions v where v.form_id=f.id and
  (not rm_private.workshop_read_owned_v1('family',v.family_id,p_office) or(v.draft_id is not null and(not rm_private.workshop_read_owned_v1('draft',v.draft_id,p_office)
   or not exists(select 1 from public.rm_form_template_drafts d where d.id=v.draft_id and d.family_id=v.family_id and d.published_form_id=f.id and d.state='published'))))))
 when 'client' then exists(select 1 from public.rm_clientes where id=p_id)
 when 'equipment_type' then exists(select 1 from public.rm_tipos_equipamento where id=p_id) else false end;
$$;

create function rm_private.workshop_read_data_v1(p_resource text,p_args jsonb,p_office uuid) returns jsonb language plpgsql set search_path='' as $$
declare required text[];term text;page_no int;start_at int;kind text;ident uuid;result jsonb;snapshot jsonb;metadata jsonb;begin
 if p_args is null or jsonb_typeof(p_args)<>'object' or octet_length(p_args::text)>4096 then raise exception using errcode='22023',message='Filtros inválidos.';end if;
 required:=case p_resource when 'catalog_list' then array['kind','q','page'] when 'catalog_entry' then array['kind','id']
  when 'template_list' then array['q','state','page'] when 'template_draft' then array['id'] when 'template_form' then array['id'] when 'template_choices' then '{}'::text[] end;
 if required is null or not p_args ?& required or exists(select 1 from jsonb_object_keys(p_args) k where not k=any(required)) then raise exception using errcode='22023',message='Consulta inválida.';end if;
 if p_resource in('catalog_list','template_list') then
  if jsonb_typeof(p_args->'q') is distinct from 'string' or length(p_args->>'q')>100 or jsonb_typeof(p_args->'page') is distinct from 'number'
   or p_args->>'page' !~ '^[1-9][0-9]{0,4}$' then raise exception using errcode='22023',message='Página ou busca inválida.';end if;
  page_no:=(p_args->>'page')::int;if page_no>10000 then raise exception using errcode='22023',message='Página inválida.';end if;term:=lower(p_args->>'q');
 end if;
 if p_resource in('catalog_list','catalog_entry') then
  kind:=p_args->>'kind';if jsonb_typeof(p_args->'kind') is distinct from 'string' or kind not in('clients','types','forms') or p_resource='catalog_entry' and kind='forms' then raise exception using errcode='22023',message='Cadastro inválido.';end if;
 end if;
 if p_resource in('catalog_entry','template_draft','template_form') then
  if jsonb_typeof(p_args->'id') is distinct from 'string' then raise exception using errcode='22023',message='Identificador inválido.';end if;ident:=(p_args->>'id')::uuid;
 end if;
 if p_resource='catalog_list' then
  start_at:=(page_no-1)*50;
  with filtered as materialized(
   select c.id,c.nome sort_text,null::timestamptz sort_time,jsonb_build_object('id',c.id,'codigo',c.codigo,'nome',c.nome,'descricao',c.descricao,'updated_at',c.updated_at) row_json
    from public.rm_clientes c where kind='clients' and rm_private.workshop_read_visible_v1('client',c.id,p_office) and(term='' or strpos(lower(coalesce(c.nome,'')),term)>0 or strpos(lower(coalesce(c.codigo,'')),term)>0)
   union all select t.id,null,t.created_at,jsonb_build_object('id',t.id,'nome',t.nome,'sigla',t.sigla,'updated_at',t.updated_at)
    from public.rm_tipos_equipamento t where kind='types' and rm_private.workshop_read_visible_v1('equipment_type',t.id,p_office) and(term='' or strpos(lower(coalesce(t.nome,'')),term)>0 or strpos(lower(coalesce(t.sigla,'')),term)>0)
   union all select f.id,f.titulo,null,jsonb_build_object('id',f.id,'titulo',f.titulo,'title',f.title,'descricao',f.descricao,'tipo',f.tipo,'ativo',f.ativo,'usa_aprovacao',f.usa_aprovacao,'updated_at',f.updated_at)
    ||case when v.version is null then '{}'::jsonb else jsonb_build_object('titulo_modelo',f.titulo,'versao_modelo',v.version,'titulo',coalesce(f.titulo,'')||' · v'||v.version) end
    from public.rm_forms f left join public.rm_form_template_versions v on v.form_id=f.id where kind='forms' and rm_private.workshop_read_visible_v1('form_model',f.id,p_office)
     and(term='' or strpos(lower(coalesce(f.titulo,'')),term)>0 or strpos(lower(coalesce(f.descricao,'')),term)>0)
  ),selected as(select * from filtered order by sort_time,sort_text,id limit 50 offset start_at)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(row_json order by sort_time,sort_text,id) from selected),'[]'::jsonb),'total',(select count(*) from filtered),'page',page_no,'pageSize',50) into result;
 elsif p_resource='catalog_entry' then
  if kind='clients' then select jsonb_build_object('id',c.id,'codigo',c.codigo,'nome',c.nome,'descricao',c.descricao,'updated_at',c.updated_at) into result from public.rm_clientes c where c.id=ident and rm_private.workshop_read_visible_v1('client',c.id,p_office);
  else select jsonb_build_object('id',t.id,'nome',t.nome,'sigla',t.sigla,'updated_at',t.updated_at) into result from public.rm_tipos_equipamento t where t.id=ident and rm_private.workshop_read_visible_v1('equipment_type',t.id,p_office);end if;
 elsif p_resource='template_list' then
  if p_args->>'state' not in('all','draft','published') or jsonb_typeof(p_args->'state') is distinct from 'string' then raise exception using errcode='22023',message='Estado inválido.';end if;
  start_at:=(page_no-1)*25;
  with ds as materialized(select d.id,d.updated_at,jsonb_build_object('id',d.id,'kind',d.kind,'state',d.state,'family_id',d.family_id,'source_form_id',d.source_form_id,
   'source_version',d.source_version,'created_at',d.created_at,'updated_at',d.updated_at,'published_form_id',d.published_form_id,'titulo',d.content->>'titulo') row_json
   from public.rm_form_template_drafts d where rm_private.workshop_read_visible_v1('draft',d.id,p_office) and(p_args->>'state'='all' or d.state=p_args->>'state') and(term='' or strpos(lower(coalesce(d.content->>'titulo','')),term)>0)),
  fs as materialized(select f.id,f.titulo,jsonb_build_object('id',f.id,'titulo',f.titulo,'title',f.title,'descricao',f.descricao,'tipo',f.tipo,'ativo',f.ativo,'updated_at',f.updated_at,
   'version',coalesce(v.version,1),'family_id',v.family_id,'legacy',coalesce(v.legacy,true)) row_json
   from public.rm_forms f left join public.rm_form_template_versions v on v.form_id=f.id where rm_private.workshop_read_visible_v1('form_model',f.id,p_office)
    and(term='' or strpos(lower(coalesce(f.titulo,'')),term)>0 or strpos(lower(coalesce(f.title,'')),term)>0)),
  dp as(select * from ds order by updated_at desc,id limit 25 offset start_at),fp as(select * from fs order by titulo,id limit 25 offset start_at)
  select jsonb_build_object('drafts',coalesce((select jsonb_agg(row_json order by updated_at desc,id) from dp),'[]'::jsonb),
   'published',coalesce((select jsonb_agg(row_json order by titulo,id) from fp),'[]'::jsonb),'draftTotal',(select count(*) from ds),'publishedTotal',(select count(*) from fs),'page',page_no,'pageSize',25) into result;
 elsif p_resource in('template_draft','template_form') then
  if not rm_private.workshop_read_visible_v1(case p_resource when 'template_draft' then 'draft' else 'form_model' end,ident,p_office) then return null;end if;
  if p_resource='template_form' then
   if exists(select 1 from public.rm_questoes q join public.rm_itens_questoes i on i.questao_id=q.id where q.form_id=ident and i.form_id is not null and i.form_id<>ident) then return null;end if;
   snapshot:=public.rm_web_form_source_snapshot_v1(ident);metadata:=snapshot->'source_snapshot';
  else snapshot:=public.rm_web_form_template_snapshot_v1(ident);metadata:=snapshot->'draft'->'source_snapshot';end if;
  -- Association IDs/cover URLs are not required by the editor. Keep stored metadata intact.
  metadata:=jsonb_build_object('usa_aprovacao',metadata->'usa_aprovacao','has_cover',coalesce(length(btrim(metadata->>'imagem_capa_url'))>0,false),'links_redacted',true);
  result:=jsonb_set(snapshot,case p_resource when 'template_form' then array['source_snapshot'] else array['draft','source_snapshot'] end,metadata);
 elsif p_resource='template_choices' then
  select coalesce(jsonb_agg(jsonb_build_object('option_set_key',option_set_key,'option_key',option_key,'bubble_display',bubble_display,'sort_order',sort_order) order by sort_order,option_key),'[]'::jsonb)
   into result from public.rm_option_sets where option_set_key in('tipo_quest_o','dimensoes','subtipos','tipo_formulario','tipo_de_usu_rio');
 end if;
 return result;
end$$;

create function public.rm_web_workshop_read_v1(p_read_id uuid,p_resource text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare binding rm_private.sso_identity_bindings;sess rm_private.sso_sessions;permit rm_private.workshop_read_permits;actor public.rm_users;result jsonb;begin
 if auth.uid() is null or p_read_id is null then raise exception using errcode='42501',message='Confirme sua sessão para consultar.';end if;
 select * into binding from rm_private.sso_identity_bindings where auth_user_id=auth.uid() for share;
 if not found or not binding.enabled then raise exception using errcode='42501',message='Sessão de leitura indisponível.';end if;
 select * into permit from rm_private.workshop_read_permits where read_id=p_read_id;
 if not found then raise exception using errcode='42501',message='Confirmação de oficina indisponível.';end if;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 if not found or sess.binding_id<>binding.id or sess.expires_at<=clock_timestamp() or sess.local_session_id::text is distinct from auth.jwt()->>'session_id' then raise exception using errcode='42501',message='Sessão de leitura indisponível.';end if;
 perform 1 from auth.sessions where id=sess.local_session_id and user_id=binding.auth_user_id for key share;
 if not found then raise exception using errcode='42501',message='Sessão Auth indisponível.';end if;
 select * into actor from public.rm_users where id=binding.rm_user_id and auth_user_id=auth.uid() and status='ativo' and perfil in('administrador','padr_o','auditor') for share;
 if not found or p_resource='catalog_entry' and actor.perfil<>'administrador'
  or exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and auth.jwt()->>'aal' is distinct from 'aal2' then raise exception using errcode='42501',message='Identidade ou MFA de leitura indisponível.';end if;
 select * into permit from rm_private.workshop_read_permits where read_id=p_read_id for update;
 if not found or permit.session_hash<>sess.hash or permit.subject<>binding.subject or permit.resource is distinct from p_resource
  or permit.args_hash is distinct from extensions.digest(p_args::text,'sha256') or permit.expires_at<=clock_timestamp() then raise exception using errcode='42501',message='Confirmação de consulta ausente, expirada ou divergente.';end if;
 result:=rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id);
 if permit.expires_at<=clock_timestamp() or sess.expires_at<=clock_timestamp() then raise exception using errcode='42501',message='Confirmação de consulta expirou. Tente novamente.';end if;
 delete from rm_private.workshop_read_permits where read_id=p_read_id;
 return jsonb_build_object('request_id',p_read_id,'resource',p_resource,'workshop_id',permit.workshop_id,'data',result);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception using errcode='22023',message='Filtros de consulta inválidos.';
end$$;
revoke all on function rm_private.workshop_read_owned_v1(text,uuid,uuid),rm_private.workshop_read_visible_v1(text,uuid,uuid),rm_private.workshop_read_data_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function public.rm_web_workshop_read_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_workshop_read_v1(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;

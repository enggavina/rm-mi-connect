-- Targeted template writes and durable origins. Does not enable read/offline isolation.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';

create table rm_private.workshop_template_adoption (
 singleton boolean primary key default true check(singleton),
 workshop_id uuid not null references rm_private.workshop_references(id),
 declaration_sha256 text not null check(declaration_sha256='c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2'),
 families bigint not null check(families>=0),drafts bigint not null check(drafts>=0),
 recorded_at timestamptz not null default clock_timestamp(),database_actor text not null default session_user
);
create table rm_private.workshop_template_ownership (
 object_kind text not null check(object_kind in('family','draft')),object_id uuid not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 captured_at timestamptz not null default clock_timestamp(),database_actor text not null default session_user,
 primary key(object_kind,object_id)
);
create table rm_private.workshop_template_retirements (
 object_kind text not null,object_id uuid not null,
 retired_at timestamptz not null default clock_timestamp(),database_actor text not null default session_user,
 primary key(object_kind,object_id),foreign key(object_kind,object_id) references rm_private.workshop_template_ownership(object_kind,object_id)
);
create table rm_private.template_workshop_write_settings (
 singleton boolean primary key default true check(singleton),enforced boolean not null default false,
 runtime_sha text,deployment_id uuid,activated_at timestamptz,database_actor text,
 check(not enforced or(runtime_sha is not null and runtime_sha ~ '^[0-9a-f]{40}$' and deployment_id is not null and activated_at is not null and database_actor is not null))
);
insert into rm_private.template_workshop_write_settings(singleton) values(true);
create table rm_private.template_workshop_write_permits (
 submission_id uuid primary key,session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 operation text not null check(operation in('create_form_template','save_form_template','publish_form_template','delete_form_template')),
 payload_hash bytea not null,workshop_id uuid not null references rm_private.workshop_references(id),subject uuid not null,
 context jsonb not null,expires_at timestamptz not null,created_at timestamptz not null default clock_timestamp()
);
create index template_workshop_permits_session on rm_private.template_workshop_write_permits(session_hash);
do $$declare t text;begin
 foreach t in array array['workshop_template_adoption','workshop_template_ownership','workshop_template_retirements','template_workshop_write_settings','template_workshop_write_permits'] loop
  execute format('alter table rm_private.%I enable row level security',t);
  execute format('revoke all on rm_private.%I from public,anon,authenticated,service_role',t);
 end loop;
 foreach t in array array['workshop_template_adoption','workshop_template_ownership','workshop_template_retirements'] loop
  execute format('create trigger workshop_template_immutable before update or delete on rm_private.%I for each row execute function rm_private.workshop_origin_immutable_v1()',t);
  execute format('create trigger workshop_template_no_truncate before truncate on rm_private.%I for each statement execute function rm_private.workshop_origin_immutable_v1()',t);
 end loop;
end$$;

create function rm_private.workshop_template_scope_v1(p_kind text,p_id uuid) returns uuid language plpgsql set search_path='' as $$
declare office uuid;begin
 if p_id is null then return null;end if;
 if p_kind='form_model' then return rm_private.workshop_catalog_scope_v1(p_kind,p_id);end if;
 if p_kind not in('family','draft') or p_kind is null then raise exception using errcode='22023',message='Origem de modelo inválida.';end if;
 select workshop_id into office from rm_private.workshop_template_ownership where object_kind=p_kind and object_id=p_id;
 if exists(select 1 from rm_private.workshop_template_retirements where object_kind=p_kind and object_id=p_id) then
  raise exception using errcode='PT410',message='Origem do modelo encerrada. Preserve o protocolo para conferência.';end if;
 return office;
end$$;
create function rm_private.workshop_template_pair_v1(p_left_kind text,p_left_id uuid,p_right_kind text,p_right_id uuid)
returns void language plpgsql set search_path='' as $$
declare k text;l uuid;r uuid;begin
 if p_left_id is null or p_right_id is null then return;end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Reinicie a transação para conferir a oficina atual.';end if;
 for k in select distinct key from(values
  (case when p_left_kind='form_model' then 'em:workshop-catalog:v1:' else 'em:workshop-template:v1:' end||p_left_kind||':'||p_left_id),
  (case when p_right_kind='form_model' then 'em:workshop-catalog:v1:' else 'em:workshop-template:v1:' end||p_right_kind||':'||p_right_id))v(key) order by key loop
  if not pg_try_advisory_xact_lock_shared(hashtextextended(k,0)) then raise exception using errcode='PT409',message='Origem do modelo em conferência. Reenvie o mesmo protocolo.';end if;
 end loop;
 l:=rm_private.workshop_template_scope_v1(p_left_kind,p_left_id);r:=rm_private.workshop_template_scope_v1(p_right_kind,p_right_id);
 if l is not null and r is not null and l<>r then raise exception using errcode='PT409',message='Modelos de oficinas diferentes não podem ser vinculados.';end if;
end$$;
create function rm_private.workshop_template_edges_v1() returns table(left_kind text,left_id uuid,right_kind text,right_id uuid)
language sql stable set search_path='' as $$
 select distinct e.* from public.rm_form_template_drafts d cross join lateral(values
  ('family',d.family_id,'draft',d.id),('draft',d.id,'form_model',d.source_form_id),('draft',d.id,'form_model',d.published_form_id),
  ('family',d.family_id,'form_model',d.source_form_id),('family',d.family_id,'form_model',d.published_form_id))e(lk,li,rk,ri) where e.li is not null and e.ri is not null
 union select distinct e.* from public.rm_form_template_versions v cross join lateral(values
  ('family',v.family_id,'form_model',v.form_id),('family',v.family_id,'draft',v.draft_id),('draft',v.draft_id,'form_model',v.form_id))e(lk,li,rk,ri) where e.li is not null and e.ri is not null;
$$;
create function rm_private.workshop_template_check_v1(p_kind text,p_id uuid) returns void language plpgsql set search_path='' as $$
declare e record;begin
 for e in select * from rm_private.workshop_template_edges_v1() where left_kind=p_kind and left_id=p_id or right_kind=p_kind and right_id=p_id
  order by left_kind,left_id,right_kind,right_id loop
  perform rm_private.workshop_template_pair_v1(e.left_kind,e.left_id,e.right_kind,e.right_id);
 end loop;
end$$;
create function rm_private.workshop_template_guard_v1() returns trigger language plpgsql security definer set search_path='' as $$
declare kind text;ident uuid;tbl text;existing uuid;e record;old_payload jsonb;payload jsonb;begin
 if tg_table_schema='rm_private' and tg_table_name='workshop_catalog_ownership' and tg_op='INSERT' and tg_when='AFTER' then
  if new.object_kind='form_model' then perform rm_private.workshop_template_check_v1('form_model',new.object_id);end if;return new;
 elsif tg_table_schema='rm_private' and tg_table_name='workshop_template_ownership' and tg_op='INSERT' then
  if tg_when='AFTER' then perform rm_private.workshop_template_check_v1(new.object_kind,new.object_id);return new;end if;
  if current_setting('transaction_isolation') not in('read committed','read uncommitted') then raise exception using errcode='PT409',message='Reinicie a transação de classificação.';end if;
  kind:=new.object_kind;ident:=new.object_id;tbl:=case kind when 'draft' then 'rm_form_template_drafts' when 'family' then 'rm_form_template_families' end;
  if tbl is null then raise exception using errcode='22023',message='Origem de modelo inválida.';end if;
  if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-template:v1:'||kind||':'||ident,0)) then raise exception using errcode='PT409',message='Modelo em conferência.';end if;
  perform rm_private.workshop_template_scope_v1(kind,ident);
  execute format('select id from public.%I where id=$1 for key share nowait',tbl) into existing using ident;
  if existing is null then raise exception using errcode='23503',message='Modelo original não encontrado.';end if;return new;
 elsif tg_table_schema<>'public' or tg_table_name not in('rm_form_template_families','rm_form_template_drafts','rm_form_template_versions') then
  raise exception using errcode='42501',message='Origem do vínculo inválida.';
 end if;
 if tg_op='TRUNCATE' then raise exception using errcode='42501',message='Preserve as origens dos modelos.';end if;
 if tg_table_name in('rm_form_template_families','rm_form_template_drafts') then
  kind:=case tg_table_name when 'rm_form_template_families' then 'family' else 'draft' end;
  if tg_op<>'INSERT' then
   old_payload:=to_jsonb(old);ident:=(old_payload->>'id')::uuid;
   if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-template:v1:'||kind||':'||ident,0)) then raise exception using errcode='PT409',message='Modelo em conferência.';end if;
   if tg_op='UPDATE' and new.id<>ident and exists(select 1 from rm_private.workshop_template_ownership where object_kind=kind and object_id=ident) then
    raise exception using errcode='42501',message='Identidade de origem é imutável.';end if;
   if tg_op='DELETE' then
    insert into rm_private.workshop_template_retirements(object_kind,object_id) select kind,ident from rm_private.workshop_template_ownership
     where object_kind=kind and object_id=ident on conflict do nothing;return old;
   end if;
  end if;
  payload:=to_jsonb(new);ident:=(payload->>'id')::uuid;
  if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-template:v1:'||kind||':'||ident,0)) then raise exception using errcode='PT409',message='Modelo em conferência.';end if;
  perform rm_private.workshop_template_scope_v1(kind,ident);
 end if;
 if tg_table_name='rm_form_template_drafts' then
  for e in select * from(values
   ('family',new.family_id,'draft',new.id),('draft',new.id,'form_model',new.source_form_id),('draft',new.id,'form_model',new.published_form_id),
   ('family',new.family_id,'form_model',new.source_form_id),('family',new.family_id,'form_model',new.published_form_id))v(lk,li,rk,ri) loop
   perform rm_private.workshop_template_pair_v1(e.lk,e.li,e.rk,e.ri);
  end loop;
 elsif tg_table_name='rm_form_template_versions' then
  for e in select * from(values('family',new.family_id,'form_model',new.form_id),('family',new.family_id,'draft',new.draft_id),('draft',new.draft_id,'form_model',new.form_id))v(lk,li,rk,ri) loop
   perform rm_private.workshop_template_pair_v1(e.lk,e.li,e.rk,e.ri);
  end loop;
 end if;
 return new;
exception when lock_not_available then raise exception using errcode='PT409',message='Modelo em alteração. Reenvie o mesmo protocolo.';
end$$;
create trigger workshop_template_assign before insert on rm_private.workshop_template_ownership for each row execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_references after insert on rm_private.workshop_template_ownership for each row execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_references after insert on rm_private.workshop_catalog_ownership for each row execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_lifecycle before insert or update or delete on public.rm_form_template_drafts for each row execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_lifecycle before insert or update or delete on public.rm_form_template_families for each row execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_no_truncate before truncate on public.rm_form_template_drafts for each statement execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_no_truncate before truncate on public.rm_form_template_families for each statement execute function rm_private.workshop_template_guard_v1();
create trigger workshop_template_references before insert or update on public.rm_form_template_versions for each row execute function rm_private.workshop_template_guard_v1();

create function rm_private.adopt_workshop_templates_bma_v1(p_families bigint,p_drafts bigint) returns jsonb language plpgsql set search_path='' as $$
declare initial rm_private.workshop_legacy_adoption;receipt rm_private.workshop_template_adoption;begin
 if current_user::regrole<>(select relowner from pg_class where oid='rm_private.workshop_template_adoption'::regclass) then raise exception using errcode='42501',message='Technical adoption owner required.';end if;
 if p_families is null or p_drafts is null or p_families<0 or p_drafts<0 then raise exception using errcode='22023',message='Reviewed counts required.';end if;
 lock table public.rm_form_template_families,public.rm_form_template_drafts,public.rm_form_template_versions,public.rm_forms in share row exclusive mode;
 select * into initial from rm_private.workshop_legacy_adoption where singleton;
 if not found or initial.declaration_sha256<>'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2'
  or not exists(select 1 from rm_private.workshop_catalog_adoption where workshop_id=initial.legacy_workshop_id) then raise exception using errcode='PT409',message='Approved BMA adoption required.';end if;
 select * into receipt from rm_private.workshop_template_adoption where singleton;
 if found then
  if receipt.workshop_id<>initial.legacy_workshop_id or receipt.families<>p_families or receipt.drafts<>p_drafts then raise exception using errcode='PT409',message='Adoption already bound to another reviewed batch.';end if;
  return jsonb_build_object('replayed',true,'families',receipt.families,'drafts',receipt.drafts);
 end if;
 if(select count(*) from public.rm_form_template_families)<>p_families or(select count(*) from public.rm_form_template_drafts)<>p_drafts
  or exists(select 1 from public.rm_form_template_families where created_at>initial.recorded_at)
  or exists(select 1 from public.rm_form_template_drafts where created_at>initial.recorded_at)
  or exists(select 1 from public.rm_forms f where rm_private.workshop_catalog_scope_v1('form_model',f.id) is null)
  or exists(select 1 from rm_private.workshop_template_ownership) or exists(select 1 from rm_private.workshop_template_retirements) then
  raise exception using errcode='PT409',message='Template batch requires explicit origin review; no default office.';end if;
 insert into rm_private.workshop_template_adoption(singleton,workshop_id,declaration_sha256,families,drafts)
  values(true,initial.legacy_workshop_id,initial.declaration_sha256,p_families,p_drafts);
 insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) select 'family',id,initial.legacy_workshop_id from public.rm_form_template_families order by id;
 insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) select 'draft',id,initial.legacy_workshop_id from public.rm_form_template_drafts order by id;
 return jsonb_build_object('replayed',false,'families',p_families,'drafts',p_drafts);
end$$;

-- Reuse the exact reviewed 057 context validator without changing that RPC.
-- Only name, accepted operations, capability and new permit table differ.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 needle:='p_operation not in(''save_catalog'',''delete_catalog'')';
 if strpos(definition,needle)=0 or strpos(definition,'p_payload->>''kind'' is null or p_payload->>''kind'' not in(''clients'',''types'')')=0 then raise exception 'Unexpected 057 authority validator';end if;
 definition:=replace(definition,'public.rm_sso_catalog_workshop_permit_v1(','public.rm_sso_template_workshop_permit_v1(');
 definition:=replace(definition,needle,'p_operation not in(''create_form_template'',''save_form_template'',''publish_form_template'',''delete_form_template'')');
 definition:=replace(definition,' or p_payload->>''kind'' is null or p_payload->>''kind'' not in(''clients'',''types'')','');
 definition:=replace(definition,'''em.catalogs.manage''','''em.form_templates.manage''');
 definition:=replace(definition,'catalog_workshop_write_permits','template_workshop_write_permits');
 execute definition;
end$$;
revoke all on function public.rm_sso_template_workshop_permit_v1(text,uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_template_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

create function rm_private.workshop_template_require_v1(p_kind text,p_id uuid,p_office uuid) returns void language plpgsql set search_path='' as $$
declare k text;begin
 if p_id is null then return;end if;
 k:=case when p_kind='form_model' then 'em:workshop-catalog:v1:' else 'em:workshop-template:v1:' end||p_kind||':'||p_id;
 if not pg_try_advisory_xact_lock_shared(hashtextextended(k,0)) then raise exception using errcode='PT409',message='Modelo em conferência. Reenvie o mesmo protocolo.';end if;
 if rm_private.workshop_template_scope_v1(p_kind,p_id) is distinct from p_office then raise exception using errcode='42501',message='Modelo fora da oficina confirmada ou com origem pendente de revisão.';end if;
end$$;
create function rm_private.web_mutate_scoped_templates_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare permit rm_private.template_workshop_write_permits;sess rm_private.sso_sessions;binding rm_private.sso_identity_bindings;
 draft public.rm_form_template_drafts;publication public.rm_form_template_versions;enforced boolean;kind text;ident uuid;source_id uuid;family uuid;
 existing boolean;family_existed boolean;office uuid;retired boolean;result jsonb;published uuid;
begin
 if p_operation is null or p_operation not in('create_form_template','save_form_template','publish_form_template','delete_form_template') then
  return rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id,p_operation,p_payload);end if;
 select s.enforced into enforced from rm_private.template_workshop_write_settings s where singleton for share;
 select * into permit from rm_private.template_workshop_write_permits where submission_id=p_client_submission_id;
 if not found then
  if coalesce(enforced,true) then raise exception using errcode='42501',message='Confirme a oficina em uma sessão web atual antes de alterar o modelo.';end if;
  return rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id where s.hash=permit.session_hash for share of b;
 if not found then raise exception using errcode='42501',message='Sessão de oficina indisponível.';end if;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 if not found then raise exception using errcode='42501',message='Sessão de oficina indisponível.';end if;
 select * into permit from rm_private.template_workshop_write_permits where submission_id=p_client_submission_id for update;
 if not found or not binding.enabled or sess.binding_id<>binding.id or permit.session_hash<>sess.hash
  or binding.auth_user_id is distinct from auth.uid() or binding.subject<>permit.subject
  or sess.local_session_id::text is distinct from auth.jwt()->>'session_id' or sess.expires_at<=clock_timestamp()
  or permit.expires_at<=clock_timestamp() or permit.operation<>p_operation or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256') then
  raise exception using errcode='42501',message='Confirmação de oficina ausente, expirada ou divergente.';end if;
 ident:=(p_payload->>'id')::uuid;
 if ident is null then raise exception using errcode='22023',message='Modelo inválido.';end if;
 kind:=case when p_operation='delete_form_template' and p_payload->>'kind'='form' then 'form_model' else 'draft' end;
 if not pg_try_advisory_xact_lock(hashtextextended(case kind when 'form_model' then 'em:workshop-catalog:v1:' else 'em:workshop-template:v1:' end||kind||':'||ident,0)) then
  raise exception using errcode='PT409',message='Modelo em conferência. Reenvie o mesmo protocolo.';end if;
 if kind='form_model' then
  select workshop_id into office from rm_private.workshop_catalog_ownership where object_kind=kind and object_id=ident;
  select exists(select 1 from rm_private.workshop_catalog_retirements where object_kind=kind and object_id=ident) into retired;
  select exists(select 1 from public.rm_forms where id=ident) into existing;
 else
  select workshop_id into office from rm_private.workshop_template_ownership where object_kind=kind and object_id=ident;
  select exists(select 1 from rm_private.workshop_template_retirements where object_kind=kind and object_id=ident) into retired;
  select * into draft from public.rm_form_template_drafts where id=ident;existing:=found;
 end if;
 if office is not null and office<>permit.workshop_id or existing and office is null then raise exception using errcode='42501',message='Modelo fora da oficina confirmada ou com origem pendente de revisão.';end if;
 if retired then
  if p_operation<>'delete_form_template' or not exists(select 1 from rm_private.web_mutation_receipts r
   where r.client_submission_id=p_client_submission_id and r.auth_user_id=auth.uid() and r.operation=p_operation and r.payload=p_payload) then
   raise exception using errcode='PT410',message='Origem do modelo encerrada. Preserve o protocolo para conferência.';end if;
 else
  if kind='form_model' then
   select * into publication from public.rm_form_template_versions where form_id=ident for key share nowait;
   family:=publication.family_id;
   perform rm_private.workshop_template_require_v1('draft',publication.draft_id,permit.workshop_id);
  elsif p_operation='create_form_template' then
   source_id:=(p_payload->>'source_form_id')::uuid;
   perform rm_private.workshop_template_require_v1('form_model',source_id,permit.workshop_id);
   if p_payload->>'kind'='version' and source_id is not null then
    select * into publication from public.rm_form_template_versions where form_id=source_id for key share nowait;
    family:=coalesce(publication.family_id,source_id);
   else family:=ident;end if;
  else
   family:=draft.family_id;source_id:=draft.source_form_id;
   perform rm_private.workshop_template_require_v1('form_model',source_id,permit.workshop_id);
   perform rm_private.workshop_template_require_v1('form_model',draft.published_form_id,permit.workshop_id);
  end if;
  if family is not null then
   if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-template:v1:family:'||family,0)) then raise exception using errcode='PT409',message='Família do modelo em conferência.';end if;
   select exists(select 1 from public.rm_form_template_families where id=family) into family_existed;
   if family_existed then perform rm_private.workshop_template_require_v1('family',family,permit.workshop_id);
   elsif p_operation<>'create_form_template' then raise exception using errcode='42501',message='Família do modelo sem origem comprovada.';
   else perform rm_private.workshop_template_scope_v1('family',family);end if;
  end if;
 end if;
 result:=rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id,p_operation,p_payload);
 if p_operation='create_form_template' then
  select * into draft from public.rm_form_template_drafts where id=ident;
  if not found or draft.family_id is distinct from family then raise exception using errcode='42501',message='Origem do rascunho inconsistente.';end if;
  if not family_existed then
   if result->'idempotent_replay' is distinct from 'false'::jsonb then raise exception using errcode='42501',message='Origem anterior pendente de revisão.';end if;
   insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) values('family',family,permit.workshop_id);
  end if;
  if office is null then
   if result->'idempotent_replay' is distinct from 'false'::jsonb then raise exception using errcode='42501',message='Origem anterior pendente de revisão.';end if;
   insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) values('draft',ident,permit.workshop_id);
  end if;
 elsif p_operation='publish_form_template' then
  select published_form_id into published from public.rm_form_template_drafts where id=ident;
  if published is null then raise exception using errcode='42501',message='Publicação sem origem comprovada.';end if;
  office:=rm_private.workshop_catalog_scope_v1('form_model',published);
  if office is null then
   if result->'idempotent_replay' is distinct from 'false'::jsonb then raise exception using errcode='42501',message='Publicação anterior pendente de revisão.';end if;
   insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('form_model',published,permit.workshop_id);
  elsif office<>permit.workshop_id then raise exception using errcode='42501',message='Publicação fora da oficina confirmada.';end if;
 end if;
 if permit.expires_at<=clock_timestamp() or sess.expires_at<=clock_timestamp() then raise exception using errcode='42501',message='Confirmação de oficina expirou. Reenvie o mesmo protocolo.';end if;
 return result;
exception when lock_not_available then raise exception using errcode='PT409',message='Modelo em alteração. Reenvie o mesmo protocolo.';
end$$;

do $$declare definition text;needle text:='return rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id,p_operation,p_payload);';begin
 definition:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 if(length(definition)-length(replace(definition,needle,'')))<>length(needle) then raise exception 'Unexpected 057 public dispatch';end if;
 execute replace(definition,needle,'return rm_private.web_mutate_scoped_templates_v1(p_client_submission_id,p_operation,p_payload);');
end$$;

create function rm_private.activate_template_workshop_writes_v1(p_runtime_sha text,p_deployment_id uuid) returns jsonb language plpgsql set search_path='' as $$
declare settings rm_private.template_workshop_write_settings;begin
 if current_user::regrole<>(select relowner from pg_class where oid='rm_private.template_workshop_write_settings'::regclass) then raise exception using errcode='42501',message='Technical publication owner required.';end if;
 if p_runtime_sha is null or p_runtime_sha !~ '^[0-9a-f]{40}$' or p_deployment_id is null then raise exception using errcode='22023',message='Verified deployment required.';end if;
 select * into settings from rm_private.template_workshop_write_settings where singleton for update;
 if settings.enforced then
  if settings.runtime_sha<>p_runtime_sha or settings.deployment_id<>p_deployment_id then raise exception using errcode='PT409',message='Activation already bound to another deployment.';end if;
  return jsonb_build_object('enforced',true,'replayed',true,'full_isolation_active',false);
 end if;
 lock table public.rm_form_template_families,public.rm_form_template_drafts,public.rm_form_template_versions,public.rm_forms in share row exclusive mode;
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or not exists(select 1 from rm_private.catalog_workshop_write_settings where singleton and enforced)
  or not exists(select 1 from rm_private.workshop_template_adoption)
  or exists(select 1 from public.rm_form_template_families f where rm_private.workshop_template_scope_v1('family',f.id) is null)
  or exists(select 1 from public.rm_form_template_drafts d where rm_private.workshop_template_scope_v1('draft',d.id) is null)
  or exists(select 1 from public.rm_forms f where rm_private.workshop_template_scope_v1('form_model',f.id) is null) then
  raise exception using errcode='PT409',message='Template ownership or SSO prerequisites incomplete; preserve current records.';end if;
 perform rm_private.workshop_template_pair_v1(e.left_kind,e.left_id,e.right_kind,e.right_id) from rm_private.workshop_template_edges_v1() e;
 update rm_private.template_workshop_write_settings set enforced=true,runtime_sha=p_runtime_sha,deployment_id=p_deployment_id,activated_at=clock_timestamp(),database_actor=session_user where singleton;
 return jsonb_build_object('enforced',true,'replayed',false,'full_isolation_active',false);
end$$;
revoke all on function rm_private.workshop_template_scope_v1(text,uuid),rm_private.workshop_template_pair_v1(text,uuid,text,uuid),
 rm_private.workshop_template_edges_v1(),rm_private.workshop_template_check_v1(text,uuid),rm_private.workshop_template_guard_v1(),
 rm_private.adopt_workshop_templates_bma_v1(bigint,bigint),rm_private.workshop_template_require_v1(text,uuid,uuid),
 rm_private.web_mutate_scoped_templates_v1(uuid,text,jsonb),rm_private.activate_template_workshop_writes_v1(text,uuid) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

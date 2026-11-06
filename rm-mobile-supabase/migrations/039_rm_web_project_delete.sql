-- Explicit, audited hard deletion of one project and its exclusively owned graph.
-- Reuse receipts as minimal tombstones; never recreate deleted offline work.
begin;

create index rm_web_project_delete_tombstone on rm_private.web_mutation_receipts((payload->>'id')) where operation='delete_project';
create index rm_web_project_delete_bubble on rm_private.web_mutation_receipts((before_record->>'bubble_id')) where operation='delete_project';

create function rm_private.project_deletion_in_progress_v1(p_project uuid) returns boolean
language sql volatile security definer set search_path='' as $$
 select exists(select 1 from rm_private.web_mutation_receipts r where r.operation='delete_project'
  and r.payload->>'id'=p_project::text and r.auth_user_id=auth.uid()
  and r.before_record->>'transaction_id'=txid_current()::text and r.result->'record'->'deleted'='true'::jsonb);
$$;
revoke all on function rm_private.project_deletion_in_progress_v1(uuid) from public,anon,authenticated,service_role;

create function rm_private.project_deleted_v1(p_project uuid,p_bubble text default null) returns boolean
language sql volatile security definer set search_path='' as $$
 select exists(select 1 from rm_private.web_mutation_receipts r where r.operation='delete_project'
  and(r.payload->>'id'=p_project::text or(p_bubble is not null and r.before_record->>'bubble_id'=p_bubble)));
$$;
revoke all on function rm_private.project_deleted_v1(uuid,text) from public,anon,authenticated,service_role;

create function rm_private.guard_deleted_project_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and rm_private.project_deletion_in_progress_v1(old.id) then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended(new.id::text,11));
 if new.bubble_id is not null then perform pg_advisory_xact_lock(hashtextextended(new.bubble_id,39));end if;
 if rm_private.project_deleted_v1(new.id,new.bubble_id) then
  raise exception 'Projeto excluído explicitamente. O envio foi preservado para reconciliação.' using errcode='PT410';end if;
 return new;
end $$;
revoke all on function rm_private.guard_deleted_project_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_deleted_project before insert or update on public.rm_projetos for each row execute function rm_private.guard_deleted_project_v1();

-- Explicit ownership closure. Nullable references do not justify deleting a row
-- belonging to another project; those inconsistent/shared graphs are refused.
create function rm_private.project_delete_scope_v1(p_project uuid)
returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 with e as materialized(select id from public.rm_equipamentos where projeto_id=p_project),
 pc as materialized(select id from public.rm_propostas_controle where projeto_id=p_project or(projeto_id is null and equipamento_id in(select id from e))),
 os as materialized(select id from public.rm_ordens_servico where projeto_id=p_project or(projeto_id is null and equipamento_id in(select id from e))),
 fd as materialized(select id from public.rm_fichas_delineamento where projeto_id=p_project or(projeto_id is null and ordem_servico_id in(select id from os))),
 r as materialized(select id from public.rm_registros_formulario where projeto_id=p_project)
 select 'public','rm_projetos',array(select id from public.rm_projetos where id=p_project)
 union all select 'public','rm_equipamentos',array(select id from e)
 union all select 'public','rm_propostas_controle',array(select id from pc)
 union all select 'public','rm_propostas_budgetarias',array(select id from public.rm_propostas_budgetarias where projeto_id=p_project or(projeto_id is null and proposta_controle_id in(select id from pc)))
 union all select 'public','rm_ordens_servico',array(select id from os)
 union all select 'public','rm_componentes_os',array(select id from public.rm_componentes_os where ordem_servico_id in(select id from os))
 union all select 'public','rm_fichas_delineamento',array(select id from fd)
 union all select 'public','rm_itens_ficha_delineamento',array(select id from public.rm_itens_ficha_delineamento where ficha_delineamento_id in(select id from fd))
 union all select 'public','rm_fichas_desmontagem',array(select id from public.rm_fichas_desmontagem where projeto_id=p_project or(projeto_id is null and(equipamento_id in(select id from e) or ordem_servico_id in(select id from os))))
 union all select 'public','rm_ensaios_eletricos_laboratorio',array(select id from public.rm_ensaios_eletricos_laboratorio where projeto_id=p_project or(projeto_id is null and(equipamento_id in(select id from e) or ordem_servico_id in(select id from os))))
 union all select 'public','rm_celulas_projeto',array(select id from public.rm_celulas_projeto where projeto_id=p_project)
 union all select 'public','rm_aprovacoes_etapas',array(select id from public.rm_aprovacoes_etapas where projeto_id=p_project)
 union all select 'public','rm_fotos',array(select id from public.rm_fotos where projeto_id=p_project)
 union all select 'public','rm_registros_formulario',array(select id from r)
 union all select 'public','rm_respostas',array(select id from public.rm_respostas where registro_formulario_id in(select id from r))
 union all select 'public','rm_respostas_temp',array(select id from public.rm_respostas_temp where projeto_id=p_project or registro_formulario_id in(select id from r))
 union all select 'public','rm_logs_aprovacao',array(select id from public.rm_logs_aprovacao where projeto_id=p_project)
 union all select 'public','rm_aprovacoes_registro',array(select id from public.rm_aprovacoes_registro where projeto_id=p_project or(projeto_id is null and registro_formulario_id in(select id from r)))
 union all select 'public','rm_comentarios',array(select id from public.rm_comentarios where projeto_id=p_project)
 union all select 'public','rm_notificacoes',array(select id from public.rm_notificacoes where registro_formulario_id in(select id from r))
 union all select 'public','rm_docs',array(select id from public.rm_docs where projeto_id=p_project)
 union all select 'public','rm_documentos',array(select id from public.rm_documentos where projeto_id=p_project)
 union all select 'public','rm_form_reviewer_assignments',array(select id from public.rm_form_reviewer_assignments where projeto_id=p_project)
 union all select 'public','rm_web_stage_decisions',array(select id from public.rm_web_stage_decisions where projeto_id=p_project)
 union all select 'rm_private','stage_rule_events',array(select id from rm_private.stage_rule_events where projeto_id=p_project)
 union all select 'rm_private','cell_availability_events',array(select id from rm_private.cell_availability_events where projeto_id=p_project)
 union all select 'rm_private','equipment_change_events',array(select id from rm_private.equipment_change_events where projeto_id=p_project)
 union all select 'rm_private','project_attachment_versions',array(select id from rm_private.project_attachment_versions where projeto_id=p_project)
 union all select 'rm_private','project_attachment_uploads',array(select id from rm_private.project_attachment_uploads where projeto_id=p_project)
 union all select 'rm_private','project_comment_revisions',array(select id from rm_private.project_comment_revisions where projeto_id=p_project)
 union all select 'rm_private','project_route_instances',array(select projeto_id from rm_private.project_route_instances where projeto_id=p_project);
$$;
revoke all on function rm_private.project_delete_scope_v1(uuid) from public,anon,authenticated,service_role;

create function rm_private.project_delete_has_shared_fk_v1(p_scope jsonb) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare k record;join_sql text;source_ids uuid[];target_ids uuid[];source_key text;target_key text;hit boolean;source_scope boolean;
begin
 for k in select c.*,sn.nspname source_schema,s.relname source_table,tn.nspname target_schema,t.relname target_table
  from pg_constraint c join pg_class s on s.oid=c.conrelid join pg_namespace sn on sn.oid=s.relnamespace
   join pg_class t on t.oid=c.confrelid join pg_namespace tn on tn.oid=t.relnamespace
  where c.contype='f' and p_scope?(tn.nspname||'.'||t.relname) loop
  select coalesce(string_agg(format('x.%I=r.%I',sa.attname,ta.attname),' and ' order by pos.n),'false') into join_sql
   from generate_subscripts(k.conkey,1) pos(n) join pg_attribute sa on sa.attrelid=k.conrelid and sa.attnum=k.conkey[pos.n]
    join pg_attribute ta on ta.attrelid=k.confrelid and ta.attnum=k.confkey[pos.n];
  source_scope:=p_scope?(k.source_schema||'.'||k.source_table);
  source_ids:=array(select value::uuid from jsonb_array_elements_text(coalesce(p_scope->(k.source_schema||'.'||k.source_table),'[]')));
  target_ids:=array(select value::uuid from jsonb_array_elements_text(p_scope->(k.target_schema||'.'||k.target_table)));
  source_key:=case when k.source_schema='rm_private' and k.source_table='project_route_instances' then 'projeto_id' else 'id' end;
  target_key:=case when k.target_schema='rm_private' and k.target_table='project_route_instances' then 'projeto_id' else 'id' end;
  if source_scope and cardinality(source_ids)>0 then
   execute format('select exists(select 1 from %I.%I x join %I.%I r on %s where x.%I=any($2) and not(r.%I=any($1)))',k.source_schema,k.source_table,k.target_schema,k.target_table,join_sql,source_key,target_key) into hit using target_ids,source_ids;
   if hit then return true;end if;
  end if;
  if cardinality(target_ids)>0 then
   execute format('select exists(select 1 from %I.%I x join %I.%I r on %s where r.%I=any($1) and %s)',k.source_schema,k.source_table,k.target_schema,k.target_table,join_sql,target_key,
    case when source_scope then format('not(x.%I=any($2))',source_key) else 'true' end) into hit using target_ids,source_ids;
   if hit then return true;end if;
  end if;
 end loop;return false;
end $$;
revoke all on function rm_private.project_delete_has_shared_fk_v1(jsonb) from public,anon,authenticated,service_role;

create function rm_private.project_delete_context_v1(p_project uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.rm_projetos%rowtype;s record;state jsonb:='{}';counts jsonb:='{}';scope jsonb:='{}';n bigint;h text;shared boolean; files bigint;
 e uuid[];cp uuid[];r uuid[];docs uuid[];stages uuid[];logs uuid[];os uuid[];pc uuid[];fd uuid[];
begin
 select * into p from public.rm_projetos where id=p_project;if not found then return null;end if;
 for s in select * from rm_private.project_delete_scope_v1(p_project) order by schema_name,table_name loop
  if s.table_name='project_route_instances' then
   execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by x.projeto_id),'''')) from %I.%I x where projeto_id=any($1)',s.schema_name,s.table_name) into n,h using s.ids;
  else
   execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by x.id),'''')) from %I.%I x where id=any($1)',s.schema_name,s.table_name) into n,h using s.ids;
  end if;
  counts:=counts||jsonb_build_object(s.schema_name||'.'||s.table_name,n);state:=state||jsonb_build_object(s.schema_name||'.'||s.table_name,h);scope:=scope||jsonb_build_object(s.schema_name||'.'||s.table_name,to_jsonb(s.ids));
  case s.table_name when 'rm_equipamentos' then e:=s.ids;when 'rm_celulas_projeto' then cp:=s.ids;when 'rm_registros_formulario' then r:=s.ids;
   when 'rm_docs' then docs:=coalesce(docs,'{}')||s.ids;when 'rm_documentos' then docs:=coalesce(docs,'{}')||s.ids;when 'rm_aprovacoes_etapas' then stages:=s.ids;when 'rm_logs_aprovacao' then logs:=s.ids;
   when 'rm_ordens_servico' then os:=s.ids;when 'rm_propostas_controle' then pc:=s.ids;when 'rm_fichas_delineamento' then fd:=s.ids;else null;end case;
 end loop;
 select exists(select 1 from public.rm_projetos where id<>p.id and equipamento_id=any(e))
  or exists(select 1 from public.rm_fotos where celula_projeto_id=any(cp) and projeto_id is distinct from p.id)
  or exists(select 1 from public.rm_aprovacoes_etapas where celula_projeto_id=any(cp) and projeto_id is distinct from p.id)
  or exists(select 1 from public.rm_respostas_temp where registro_formulario_id=any(r) and projeto_id<>p.id)
  or exists(select 1 from public.rm_aprovacoes_registro where registro_formulario_id=any(r) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_documentos where projeto_id<>p.id and(registro_formulario_id=any(r) or documentos_origem_ids&&docs))
  or exists(select 1 from public.rm_propostas_controle where equipamento_id=any(e) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_propostas_budgetarias where proposta_controle_id=any(pc) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_ordens_servico where equipamento_id=any(e) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_fichas_delineamento where ordem_servico_id=any(os) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_fichas_desmontagem where(equipamento_id=any(e) or ordem_servico_id=any(os)) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_ensaios_eletricos_laboratorio where(equipamento_id=any(e) or ordem_servico_id=any(os)) and projeto_id is not null and projeto_id<>p.id)
  or exists(select 1 from public.rm_web_stage_decisions where projeto_id<>p.id and(aprovacao_etapa_id=any(stages) or celula_projeto_id=any(cp) or log_id=any(logs)))
  or exists(select 1 from rm_private.stage_rule_events where projeto_id<>p.id and(etapa_id=any(stages) or related_etapa_id=any(stages) or log_id=any(logs)))
  or rm_private.project_delete_has_shared_fk_v1(scope) into shared;
 select count(*) into files from rm_private.project_attachment_uploads where projeto_id=p.id and object_path='web-dossier/'||p.id::text||'/'||id::text||case mime_type when 'application/pdf' then '.pdf' when 'image/jpeg' then '.jpg' when 'image/png' then '.png' end;
 return jsonb_build_object('project',jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,'updated_at',p.updated_at),
  'can_delete',not shared,'reason',case when shared then 'Existem dependências compartilhadas ou vínculos com outro projeto. Revise esses vínculos antes de excluir.' end,
  'counts',jsonb_build_object('equipment',(counts->>'public.rm_equipamentos')::bigint,'cells',(counts->>'public.rm_celulas_projeto')::bigint,
   'photos',(counts->>'public.rm_fotos')::bigint,'form_records',(counts->>'public.rm_registros_formulario')::bigint,
   'answers',(counts->>'public.rm_respostas')::bigint+(counts->>'public.rm_respostas_temp')::bigint,
   'approvals',(counts->>'public.rm_aprovacoes_etapas')::bigint+(counts->>'public.rm_aprovacoes_registro')::bigint+(counts->>'public.rm_logs_aprovacao')::bigint,
   'comments',(counts->>'public.rm_comentarios')::bigint,'notifications',(counts->>'public.rm_notificacoes')::bigint,
   'documents',(counts->>'public.rm_docs')::bigint+(counts->>'public.rm_documentos')::bigint,
   'commercial',(counts->>'public.rm_propostas_controle')::bigint+(counts->>'public.rm_propostas_budgetarias')::bigint,
   'laboratory',(counts->>'public.rm_ordens_servico')::bigint+(counts->>'public.rm_componentes_os')::bigint+(counts->>'public.rm_fichas_delineamento')::bigint+(counts->>'public.rm_itens_ficha_delineamento')::bigint+(counts->>'public.rm_fichas_desmontagem')::bigint+(counts->>'public.rm_ensaios_eletricos_laboratorio')::bigint),
  'private_files',files,'context_version',encode(sha256(convert_to(jsonb_build_object('states',state,'shared',shared,'files',files)::text,'UTF8')),'hex'));
end $$;
revoke all on function rm_private.project_delete_context_v1(uuid) from public,anon,authenticated,service_role;

create function public.rm_web_project_delete_snapshot_v1(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.rm_users where auth_user_id=auth.uid() and status='ativo' and perfil='administrador') then raise exception 'Exclusão restrita a administradores do EM.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
 return rm_private.project_delete_context_v1(p_project_id);
end $$;
revoke all on function public.rm_web_project_delete_snapshot_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_delete_snapshot_v1(uuid) to authenticated;

-- Only proven project-exclusive paths are queued. Storage API owns physical
-- removal; deleting storage.objects directly would leave the actual blob orphaned.
create table rm_private.project_delete_files(
 id uuid primary key default gen_random_uuid(),delete_submission_id uuid not null,bucket_id text not null check(bucket_id='rm-documentos'),
 object_path text not null unique check(object_path~'^web-dossier/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|png)$'),
 status text not null default 'pending' check(status in('pending','leased','completed','preserved_shared')),
 attempts integer not null default 0 check(attempts>=0),next_attempt_at timestamptz not null default clock_timestamp(),
 lease_token uuid,lease_until timestamptz,last_error_code text,created_at timestamptz not null default clock_timestamp(),completed_at timestamptz,
 check((status='leased')=(lease_token is not null and lease_until is not null))
);
create index rm_project_delete_files_due on rm_private.project_delete_files(next_attempt_at,id) where status in('pending','leased');
revoke all on rm_private.project_delete_files from public,anon,authenticated,service_role;

-- Close the gap between exclusive ownership checking and physical deletion.
-- A reference writer and deletion enqueue acquire the same path lock; once a
-- committed cleanup job exists, a new reference cannot reuse the removed file.
create function rm_private.project_delete_reference_text_v1(p_value jsonb) returns text
language plpgsql immutable set search_path='' as $$
declare source text:=p_value::text;result text:='';part text[];code integer;
begin
 -- One URI-decoding pass for ASCII only. This covers encoded path separators
 -- and UUID letters/punctuation without interpreting arbitrary Unicode bytes.
 if source!~'%[0-9a-fA-F]{2}' then return source;end if;
 for part in select regexp_matches(source,'(%[0-9a-fA-F]{2}|[^%]+|%)','g') loop
  if part[1]~'^%[0-9a-fA-F]{2}$' then
   code:=get_byte(decode(substr(part[1],2,2),'hex'),0);
   if code between 32 and 126 then result:=result||chr(code);continue;end if;
  end if;
  result:=result||part[1];
 end loop;return result;
end $$;
revoke all on function rm_private.project_delete_reference_text_v1(jsonb) from public,anon,authenticated,service_role;

create function rm_private.guard_deleted_project_file_reference_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare serialized text:=rm_private.project_delete_reference_text_v1(to_jsonb(new));old_serialized text;path text;item text[];
begin
 if strpos(serialized,'web-dossier/')=0 then return new;end if;
 if tg_op='UPDATE' then old_serialized:=rm_private.project_delete_reference_text_v1(to_jsonb(old));end if;
 -- Compare the owned path itself: signed/public/authenticated URLs, copied
 -- strings and encoded slashes must all protect the very same object.
 for item in select regexp_matches(serialized,'(web-dossier/[0-9a-f-]{36}/[0-9a-f-]{36}\.(?:pdf|jpg|png))','g') loop
  path:=item[1];
  if old_serialized is not null and strpos(old_serialized,path)>0 then continue;end if;
  perform pg_advisory_xact_lock(hashtextextended(path,40));
  if exists(select 1 from rm_private.project_delete_files where object_path=path and status<>'preserved_shared') then
   raise exception 'Arquivo de projeto excluído. Selecione um novo arquivo sem substituir o envio original.' using errcode='PT410';end if;
 end loop;return new;
end $$;
revoke all on function rm_private.guard_deleted_project_file_reference_v1() from public,anon,authenticated,service_role;
do $$ declare t record;begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname like 'rm\_%' escape '\' loop
  execute format('create trigger rm_guard_deleted_project_file before insert or update on public.%I for each row execute function rm_private.guard_deleted_project_file_reference_v1()',t.relname);
 end loop;
end $$;

create function rm_private.guard_deleted_project_document_origin_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare source_id uuid;
begin
 for source_id in select distinct x from unnest(new.documentos_origem_ids) x order by x loop
  if source_id is null then continue;end if;
  perform pg_advisory_xact_lock(hashtextextended(source_id::text,41));
  if exists(select 1 from rm_private.web_mutation_receipts where operation='delete_project' and before_record->'deleted_document_ids'?source_id::text) then
   raise exception 'Documento de origem excluído. Atualize as origens antes de salvar.' using errcode='PT410';end if;
 end loop;return new;
end $$;
revoke all on function rm_private.guard_deleted_project_document_origin_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_deleted_document_origin before insert or update on public.rm_documentos for each row execute function rm_private.guard_deleted_project_document_origin_v1();

create function rm_private.project_delete_file_shared_v1(p_path text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare t record;found_ref boolean;
begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r'
  and((n.nspname='public' and c.relname like 'rm\_%' escape '\') or(n.nspname='rm_private' and c.relname<>'project_delete_files')) loop
  execute format('select exists(select 1 from %I.%I x where strpos(rm_private.project_delete_reference_text_v1(to_jsonb(x)),$1)>0)',t.nspname,t.relname) into found_ref using p_path;
  if found_ref then return true;end if;
 end loop;return false;
end $$;
revoke all on function rm_private.project_delete_file_shared_v1(text) from public,anon,authenticated,service_role;

create function public.rm_project_delete_files_claim_v1(p_limit integer default 3,p_submission_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare j rm_private.project_delete_files%rowtype;items jsonb:='[]';token uuid;
begin
 if(auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Serviço interno necessário.' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 5 then raise exception 'Limite inválido.' using errcode='22023';end if;
 for j in select * from rm_private.project_delete_files where(p_submission_id is null or delete_submission_id=p_submission_id) and((status='pending' and next_attempt_at<=clock_timestamp()) or(status='leased' and lease_until<clock_timestamp())) order by next_attempt_at,id limit p_limit for update skip locked loop
  if rm_private.project_delete_file_shared_v1(j.object_path) then
   update rm_private.project_delete_files set status='preserved_shared',lease_token=null,lease_until=null,completed_at=clock_timestamp(),last_error_code=null where id=j.id;
  else
   token:=gen_random_uuid();update rm_private.project_delete_files set status='leased',lease_token=token,lease_until=clock_timestamp()+interval '120 seconds',attempts=least(attempts+1,1000000000) where id=j.id;
   items:=items||jsonb_build_array(jsonb_build_object('id',j.id,'lease_token',token,'bucket_id',j.bucket_id,'object_path',j.object_path));
  end if;
 end loop;return items;
end $$;
revoke all on function public.rm_project_delete_files_claim_v1(integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_project_delete_files_claim_v1(integer,uuid) to service_role;

create function public.rm_project_delete_files_finish_v1(p_id uuid,p_lease_token uuid,p_success boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare j rm_private.project_delete_files%rowtype;
begin
 if(auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Serviço interno necessário.' using errcode='42501';end if;
 select * into j from rm_private.project_delete_files where id=p_id for update;
 if not found or j.status<>'leased' or j.lease_token is distinct from p_lease_token or j.lease_until<clock_timestamp() then return false;end if;
 if p_success is null then raise exception 'Resultado necessário.' using errcode='22023';end if;
 update rm_private.project_delete_files set status=case when p_success then 'completed' else 'pending' end,
  lease_token=null,lease_until=null,completed_at=case when p_success then clock_timestamp() end,
  next_attempt_at=clock_timestamp()+make_interval(secs=>least(3600,(5*power(2,least(j.attempts,10)))::integer)),
  last_error_code=case when not p_success then 'STORAGE_UNAVAILABLE' end where id=j.id;
 return true;
end $$;
revoke all on function public.rm_project_delete_files_finish_v1(uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.rm_project_delete_files_finish_v1(uuid,uuid,boolean) to service_role;

-- Guards retain their original behavior outside the exact owner-only proof.
do $$ declare d text;needle text;begin
 d:=pg_get_functiondef('rm_private.guard_cell_availability_v1()'::regprocedure);needle:='begin';
 if strpos(d,needle)=0 then raise exception 'Unexpected allocation guard';end if;
 execute replace(d,needle,'begin
 if tg_op=''DELETE'' and rm_private.project_deletion_in_progress_v1(old.projeto_id) then return old;end if;');
 d:=pg_get_functiondef('rm_private.guard_operational_stage_identity_v1()'::regprocedure);
 execute replace(d,needle,'begin
 if tg_op=''DELETE'' and rm_private.project_deletion_in_progress_v1(old.projeto_id) then return old;end if;');
 d:=pg_get_functiondef('rm_private.assert_allocation_available_v1(uuid,uuid,uuid)'::regprocedure);
 execute replace(d,needle,'begin
 if rm_private.project_deletion_in_progress_v1(p_project_id) then return;end if;');
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_project_delete_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype;receipt rm_private.web_mutation_receipts%rowtype;p public.rm_projetos%rowtype;c jsonb;result jsonb;
 s record;scope jsonb;pid uuid;reason text;label text;now_at timestamptz;expected timestamptz;doc_ids uuid[];reg_ids uuid[];photo_ids uuid[];comment_ids uuid[];all_ids uuid[];files bigint;deleted_bubbles jsonb:='{}';bubble_values jsonb;
begin
 if p_operation is distinct from 'delete_project' then
  select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
  if found and receipt.result->'resource_deleted'='true'::jsonb then
   select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
   if actor.id is null or receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation is distinct from p_operation
    or receipt.payload->>'original_sha256' is distinct from encode(sha256(convert_to(p_payload::text,'UTF8')),'hex') then raise exception 'Protocolo já utilizado.' using errcode='23505';end if;
   if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
   raise exception 'Projeto excluído explicitamente. Este envio permanece disponível para reconciliação.' using errcode='PT410';
  end if;
  return rm_private.web_mutate_before_project_delete_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo' and perfil='administrador' for share;
 if actor.id is null then raise exception 'Exclusão restrita a administradores do EM.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
 if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object'
  or not p_payload?&array['id','expected_updated_at','expected_context_version','confirm_delete','justificativa']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','expected_updated_at','expected_context_version','confirm_delete','justificativa'))
  or p_payload->'confirm_delete' is distinct from 'true'::jsonb or jsonb_typeof(p_payload->'justificativa') is distinct from 'string'
  or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string' or jsonb_typeof(p_payload->'expected_context_version') is distinct from 'string'
  or p_payload->>'expected_context_version' !~ '^[a-f0-9]{64}$' then raise exception 'Confirme a exclusão e informe a justificativa e a versão.' using errcode='22023';end if;
 reason:=btrim(p_payload->>'justificativa',E' \t\r\n\f\v'||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279));
 if length(reason) not between 1 and 2000 then raise exception 'Informe uma justificativa com até 2.000 caracteres.' using errcode='22023';end if;
 pid:=(p_payload->>'id')::uuid;expected:=(p_payload->>'expected_updated_at')::timestamptz;
 if pid is null or not isfinite(expected) then raise exception 'Projeto e versão necessários.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Protocolo já utilizado.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,11));
 select * into p from public.rm_projetos where id=pid for update;if not found then raise exception 'Projeto não disponível.' using errcode='P0002';end if;
 if p.bubble_id is not null then perform pg_advisory_xact_lock(hashtextextended(p.bubble_id,39));end if;
 for s in select id from public.rm_equipamentos where projeto_id=pid order by id loop perform pg_advisory_xact_lock(hashtextextended(s.id::text,37));end loop;
 for s in select id from public.rm_docs where projeto_id=pid union select id from public.rm_documentos where projeto_id=pid order by id loop
  if not pg_try_advisory_xact_lock(hashtextextended(s.id::text,41)) then raise exception 'Um documento está sendo referenciado. Recarregue antes de excluir.' using errcode='PT409';end if;
 end loop;
 for s in select object_path from rm_private.project_attachment_uploads where projeto_id=pid order by object_path loop
  if not pg_try_advisory_xact_lock(hashtextextended(s.object_path,40)) then raise exception 'Um arquivo está sendo referenciado. Recarregue antes de excluir.' using errcode='PT409';end if;
 end loop;
 for s in select * from rm_private.project_delete_scope_v1(pid) order by schema_name,table_name loop
  if s.table_name='project_route_instances' then execute format('select 1 from %I.%I where projeto_id=any($1) for update nowait',s.schema_name,s.table_name) using s.ids;
  else execute format('select 1 from %I.%I where id=any($1) order by id for update nowait',s.schema_name,s.table_name) using s.ids;end if;
 end loop;
 c:=rm_private.project_delete_context_v1(pid);
 if p.updated_at is distinct from expected or c->>'context_version' is distinct from p_payload->>'expected_context_version' then raise exception 'O projeto ou suas dependências mudaram. Recarregue antes de excluir.' using errcode='PT409';end if;
 if c->'can_delete' is distinct from 'true'::jsonb then raise exception 'Existem dependências compartilhadas. Revise os vínculos antes de excluir.' using errcode='PT424';end if;
 select jsonb_object_agg(schema_name||'.'||table_name,to_jsonb(ids)) into scope from rm_private.project_delete_scope_v1(pid);
 for s in select * from rm_private.project_delete_scope_v1(pid) where schema_name='public' and cardinality(ids)>0 loop
  execute format('select coalesce(jsonb_agg(bubble_id order by bubble_id),''[]'') from(select coalesce(to_jsonb(x)->>''bubble_id'',to_jsonb(x)->>''bubble_unique_id'') bubble_id from public.%I x where id=any($1)) b where bubble_id is not null',s.table_name) into bubble_values using s.ids;
  if jsonb_array_length(bubble_values)>0 then deleted_bubbles:=deleted_bubbles||jsonb_build_object(s.table_name,bubble_values);end if;
 end loop;
 select coalesce(array_agg(x::uuid),'{}') into all_ids from jsonb_each(scope) kv cross join lateral jsonb_array_elements_text(kv.value) x;
 select coalesce(array_agg(id),'{}') into reg_ids from public.rm_registros_formulario where projeto_id=pid;
 select coalesce(array_agg(id),'{}') into photo_ids from public.rm_fotos where projeto_id=pid;
 select coalesce(array_agg(id),'{}') into comment_ids from public.rm_comentarios where projeto_id=pid;
 label:=left(coalesce(nullif(p.numero,''),nullif(p.nome,''),'Projeto '||p.id::text),500);now_at:=clock_timestamp();
 result:=jsonb_build_object('operation',p_operation,'id',pid,'projeto_id',pid,'updated_at',now_at,'record',jsonb_build_object('id',pid,'deleted',true,'label',label,'counts',c->'counts','cleanup_pending',c->'private_files'),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
 values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,jsonb_build_object('transaction_id',txid_current(),'bubble_id',p.bubble_id,
  'deleted_document_ids',(scope->'public.rm_docs')||(scope->'public.rm_documentos'),'owned_bubble_ids',deleted_bubbles));
 insert into rm_private.project_delete_files(delete_submission_id,bucket_id,object_path)
 select p_client_submission_id,'rm-documentos',u.object_path from rm_private.project_attachment_uploads u where u.projeto_id=pid
  and u.object_path='web-dossier/'||pid::text||'/'||u.id::text||case u.mime_type when 'application/pdf' then '.pdf' when 'image/jpeg' then '.jpg' when 'image/png' then '.png' end on conflict(object_path) do nothing;
 -- Keep protocol/actor/hash tombstones, not full dossiers. Mixed queue receipts
 -- are shared evidence of other projects and are deliberately not rewritten.
 update rm_private.web_mutation_receipts w set payload=jsonb_build_object('deleted_project_id',pid,'original_sha256',encode(sha256(convert_to(w.payload::text,'UTF8')),'hex')),
  result=jsonb_build_object('id',w.result->'id','projeto_id',pid,'resource_deleted',true),before_record=null
 where w.client_submission_id<>p_client_submission_id and w.operation<>'delete_project' and
  (w.result->>'projeto_id'=pid::text or w.payload->>'projeto_id'=pid::text or(w.operation in('save_project','save_project_with_equipment') and w.payload->>'id'=pid::text)
   or(w.operation='save_cell_queue' and exists(select 1 from jsonb_array_elements(coalesce(w.before_record->'items','[]')) x where x->>'projeto_id'=pid::text)
     and not exists(select 1 from jsonb_array_elements(coalesce(w.before_record->'items','[]')) x where x->>'projeto_id' is null or not rm_private.project_deleted_v1((x->>'projeto_id')::uuid))));
 update rm_private.mobile_mutation_receipts m set params=jsonb_build_object('deleted_project_id',pid,'original_sha256',encode(sha256(convert_to(m.params::text,'UTF8')),'hex')),
  result=jsonb_build_object('id',coalesce(m.result->'id',m.result->'registro_formulario_id',m.result->'foto_id'),'projeto_id',pid,'resource_deleted',true)
 where m.result->>'projeto_id'=pid::text or m.params->>'p_projeto_id'=pid::text
  or m.result->>'registro_formulario_id'=any(array(select x::text from unnest(reg_ids) x)) or m.params->>'p_registro_formulario_id'=any(array(select x::text from unnest(reg_ids) x))
  or m.result->>'foto_id'=any(array(select x::text from unnest(photo_ids) x)) or m.result->>'comentario_id'=any(array(select x::text from unnest(comment_ids) x));
 delete from public.rm_sync_outbox where payload->>'projeto_id'=pid::text or payload->>'p_projeto_id'=pid::text
  or(entity_type in('Recebimento_Bundle','enviar_email_orcamento') and record_id=pid)
  or(entity_type in('Registro_Formulario_Bundle','Registro_Formulario_Revision') and record_id=any(reg_ids))
  or(entity_type in('Aprovacao_Etapa_Transition','enviar_email_aprovacao_etapa') and record_id=any(array(select x::uuid from jsonb_array_elements_text(scope->'public.rm_aprovacoes_etapas') x)))
  or(entity_type='Fotos_RM_Sync' and record_id=any(photo_ids));
 -- FK leaf order is explicit; global templates, people and client records never
 -- enter this graph. Remove private proofs before their protected public rows.
 foreach label in array array['rm_private.project_attachment_versions','rm_private.project_attachment_uploads','rm_private.project_comment_revisions','rm_private.stage_rule_events','rm_private.cell_availability_events','rm_private.equipment_change_events','rm_private.project_route_instances',
  'public.rm_web_stage_decisions','public.rm_form_reviewer_assignments','public.rm_notificacoes','public.rm_respostas_temp','public.rm_respostas','public.rm_aprovacoes_registro','public.rm_documentos','public.rm_docs','public.rm_comentarios','public.rm_logs_aprovacao','public.rm_registros_formulario','public.rm_fotos','public.rm_aprovacoes_etapas','public.rm_celulas_projeto',
  'public.rm_propostas_budgetarias','public.rm_propostas_controle','public.rm_itens_ficha_delineamento','public.rm_fichas_desmontagem','public.rm_ensaios_eletricos_laboratorio','public.rm_fichas_delineamento','public.rm_componentes_os','public.rm_ordens_servico'] loop
  select coalesce(array_agg(x::uuid),'{}') into doc_ids from jsonb_array_elements_text(scope->label) x;
  execute format('delete from %I.%I where %I=any($1)',split_part(label,'.',1),split_part(label,'.',2),case when label='rm_private.project_route_instances' then 'projeto_id' else 'id' end) using doc_ids;
 end loop;
 -- Deleting the parent cascades exclusively owned equipment after its reverse
 -- pointer is gone, avoiding an observable partial binding.
 delete from public.rm_projetos where id=pid;
 return result;
exception when lock_not_available then
 if p_operation is distinct from 'delete_project' then raise;end if;
 raise exception 'O projeto está sendo alterado. Recarregue antes de excluir.' using errcode='PT409';
 when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
 if p_operation is distinct from 'delete_project' then raise;end if;
 raise exception 'Identificador ou versão inválida.' using errcode='22023';
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_project_delete_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- A confirmed receipt remains a reserved protocol after its dossier is deleted.
-- Its original payload is reduced to a hash; replay must never create a new
-- receipt/project, especially the old receiving flow without an explicit ID.
do $$ declare d text;needle text;begin
 d:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 needle:='  if found then
    if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>p_rpc_name or receipt.params<>v_params then';
 if strpos(d,needle)=0 then raise exception 'Unexpected mobile receipt boundary';end if;
 execute replace(d,needle,'  if found then
    if receipt.result->''resource_deleted''=''true''::jsonb then
      if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>p_rpc_name or receipt.params->>''original_sha256'' is distinct from encode(sha256(convert_to(v_params::text,''UTF8'')),''hex'') then raise exception ''Identificador de envio já usado com outro conteúdo.'' using errcode=''22023'';end if;
      raise exception ''Projeto excluído explicitamente. O envio offline foi preservado para reconciliação.'' using errcode=''PT410'';
    end if;
    if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>p_rpc_name or receipt.params<>v_params then');
end $$;

create function public.rm_deleted_bubble_ids_v1(p_table text,p_ids text[]) returns text[]
language plpgsql stable security definer set search_path='' as $$
begin
 if(auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Serviço interno necessário.' using errcode='42501';end if;
 if p_ids is null or cardinality(p_ids)>500 or p_table is null or p_table!~'^rm_[a-z_]+$' then raise exception 'Consulta inválida.' using errcode='22023';end if;
 return array(select distinct x from rm_private.web_mutation_receipts r cross join lateral jsonb_array_elements_text(coalesce(r.before_record->'owned_bubble_ids'->p_table,'[]')) x where r.operation='delete_project' and x=any(p_ids));
end $$;
revoke all on function public.rm_deleted_bubble_ids_v1(text,text[]) from public,anon,authenticated,service_role;
grant execute on function public.rm_deleted_bubble_ids_v1(text,text[]) to service_role;
create function public.rm_deleted_project_bubble_ids_v1(p_ids text[]) returns text[]
language sql stable security definer set search_path='' as $$ select public.rm_deleted_bubble_ids_v1('rm_projetos',p_ids);$$;
revoke all on function public.rm_deleted_project_bubble_ids_v1(text[]) from public,anon,authenticated,service_role;
grant execute on function public.rm_deleted_project_bubble_ids_v1(text[]) to service_role;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check check(operation in(
 'save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title','create_form_template','save_form_template','publish_form_template',
 'transition_stage_approval','save_cell_queue','set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules','manage_cell_availability',
 'add_project_comment','reserve_project_attachment','finalize_project_attachment','save_project_equipment','edit_project_comment','reserve_project_attachment_version','finalize_project_attachment_version','save_project_with_equipment','delete_project'));
do $$ declare d text;needle text:='when ''save_project_with_equipment'' then ''em.projects.manage'' end;';begin
 d:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected SSO permit map';end if;
 execute replace(d,needle,'when ''save_project_with_equipment'' then ''em.projects.manage'' when ''delete_project'' then ''em.projects.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;

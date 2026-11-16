-- Delete only unused templates. Existing histories, answers and published
-- version immutability remain protected; no archival/backfill is invented.
begin;

-- Legacy arrays intentionally permit unresolved IDs for reconciliation.
-- Lock known parents against concurrent deletion; reject only IDs explicitly
-- tombstoned by this operation rather than introducing a new global FK rule.
create function rm_private.guard_allocation_form_references_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
 for fid in select distinct x from unnest(new.forms_ids) x order by x loop
  if tg_op='UPDATE' and array_position(old.forms_ids,fid) is not null then continue;end if;
  perform 1 from public.rm_forms where id=fid for key share;
  if not found and exists(select 1 from rm_private.web_mutation_receipts w
   where w.operation='delete_form_template' and w.payload->>'kind'='form' and w.before_record->'form'->>'id'=fid::text) then
   raise exception 'Modelo de formulário excluído; reconciliação necessária.' using errcode='23503';end if;
 end loop;
 return new;
end $$;
create trigger rm_allocation_form_references before insert or update of forms_ids on public.rm_celulas_projeto
 for each row execute function rm_private.guard_allocation_form_references_v1();

create function rm_private.guard_answer_item_references_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare iid uuid;
begin
 for iid in select distinct x from unnest(new.itens_questoes_ids) x order by x loop
  if tg_op='UPDATE' and array_position(old.itens_questoes_ids,iid) is not null then continue;end if;
  perform 1 from public.rm_itens_questoes where id=iid for key share;
  if not found and exists(select 1 from rm_private.web_mutation_receipts w
   cross join lateral jsonb_array_elements(case when jsonb_typeof(w.before_record->'items')='array' then w.before_record->'items' else '[]'::jsonb end) item
   where w.operation='delete_form_template' and w.payload->>'kind'='form' and item->>'id'=iid::text) then
   raise exception 'Opção do modelo excluído; reconciliação necessária.' using errcode='23503';end if;
 end loop;
 return new;
end $$;
create trigger rm_answer_item_references before insert or update of itens_questoes_ids on public.rm_respostas
 for each row execute function rm_private.guard_answer_item_references_v1();
create trigger rm_draft_answer_item_references before insert or update of itens_questoes_ids on public.rm_respostas_temp
 for each row execute function rm_private.guard_answer_item_references_v1();

create function rm_private.lock_form_identity_v1(p_id uuid,p_bubble text,p_wait boolean) returns void
language plpgsql security definer set search_path='' as $$
declare key text;
begin
 for key in select x from unnest(array['id:'||p_id::text,case when p_bubble is not null then 'bubble:'||p_bubble end]) x where x is not null order by x loop
  if p_wait then perform pg_advisory_xact_lock(hashtextextended('rm.form.identity:'||key,46));
  elsif not pg_try_advisory_xact_lock(hashtextextended('rm.form.identity:'||key,46)) then
   raise exception 'Identidade em uso. Tente novamente.' using errcode='PT409';end if;
 end loop;
end $$;

create function rm_private.guard_deleted_form_identity_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.id is not distinct from old.id and new.bubble_id is not distinct from old.bubble_id then return new;end if;
 -- INSERT has no old tuple lock and can wait. Identity UPDATE already holds
 -- its tuple: try-lock only, avoiding inversion with delete's identity->tuple.
 perform rm_private.lock_form_identity_v1(new.id,new.bubble_id,tg_op='INSERT');
 if exists(select 1 from rm_private.web_mutation_receipts w where w.operation='delete_form_template' and w.payload->>'kind'='form'
  and (w.before_record->'form'->>'id'=new.id::text or (new.bubble_id is not null and w.before_record->'form'->>'bubble_id'=new.bubble_id))) then
  raise exception 'Modelo excluído; reconciliação necessária.' using errcode='PT410';
 end if;
 return new;
end $$;
create trigger rm_deleted_form_identity before insert or update of id,bubble_id on public.rm_forms
 for each row execute function rm_private.guard_deleted_form_identity_v1();

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_template_delete_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 d public.rm_form_template_drafts%rowtype; f public.rm_forms%rowtype; v public.rm_form_template_versions%rowtype;
 ident uuid; expected timestamptz; kind text; original jsonb; result jsonb; removed_draft uuid; family uuid;
 dep record; used boolean; ids uuid[]; target_ids uuid[]; qids uuid[]; iids uuid[];
begin
 if p_operation is distinct from 'delete_form_template' then
  return rm_private.web_mutate_before_template_delete_v1(p_client_submission_id,p_operation,p_payload);end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or actor.perfil is distinct from 'administrador' then raise exception 'Modelos restritos à administração.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
 if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Envio inválido.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload ?& array['id','kind','expected_updated_at','confirmed']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','kind','expected_updated_at','confirmed'))
  or jsonb_typeof(p_payload->'id') is distinct from 'string' or p_payload->>'kind' not in('draft','form')
  or jsonb_typeof(p_payload->'kind') is distinct from 'string' or p_payload->'confirmed' is distinct from 'true'::jsonb
  or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string'
  or p_payload->>'expected_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
  raise exception 'Confirme o modelo e a versão antes de excluir.' using errcode='22023';end if;
 ident:=(p_payload->>'id')::uuid;kind:=p_payload->>'kind';expected:=(p_payload->>'expected_updated_at')::timestamptz;
 if ident is null or expected is null or not isfinite(expected) then raise exception 'Versão inválida.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17));
 if kind='draft' then
  perform pg_advisory_xact_lock(hashtextextended('form-draft:'||ident::text,19));
  select * into d from public.rm_form_template_drafts where id=ident for update;
  if not found or d.updated_at<>expected then raise exception 'Modelo alterado ou removido. Recarregue.' using errcode='PT409';end if;
  if d.state<>'draft' or d.published_form_id is not null or exists(select 1 from public.rm_form_template_versions where draft_id=d.id) then
   raise exception 'Consulte o modelo publicado para verificar suas dependências.' using errcode='23503';end if;
  original:=jsonb_build_object('draft',to_jsonb(d));family:=d.family_id;
  delete from public.rm_form_template_drafts where id=d.id;
 else
  -- Parent key locks exclude new FK references while the check/delete runs.
  select * into f from public.rm_forms where id=ident;
  perform rm_private.lock_form_identity_v1(ident,f.bubble_id,true);
  select * into f from public.rm_forms where id=ident for update;
  if not found or f.updated_at<>expected then raise exception 'Modelo alterado ou removido. Recarregue.' using errcode='PT409';end if;
  select * into v from public.rm_form_template_versions where form_id=ident for update;
  family:=v.family_id;removed_draft:=v.draft_id;
  if removed_draft is not null then
   perform pg_advisory_xact_lock(hashtextextended('form-draft:'||removed_draft::text,19));
   select * into d from public.rm_form_template_drafts where id=removed_draft for update;
   if d.state is distinct from 'published' or d.published_form_id is distinct from ident then raise exception 'Publicação inconsistente.' using errcode='23503';end if;
  end if;
  perform 1 from public.rm_questoes where form_id=ident order by id for update;
  qids:=array(select id from public.rm_questoes where form_id=ident);
  perform 1 from public.rm_itens_questoes where form_id=ident or questao_id=any(qids) order by id for update;
  iids:=array(select id from public.rm_itens_questoes where form_id=ident or questao_id=any(qids));
  if exists(select 1 from public.rm_itens_questoes where
   (questao_id=any(qids) and form_id is not null and form_id<>ident)
   or(form_id=ident and not questao_id=any(qids))) then
   raise exception 'Definição compartilhada ou inconsistente; exclusão bloqueada.' using errcode='23503';end if;
  if cardinality(f.celulas_ids)>0 or cardinality(f.equipes_ids)>0
   or exists(select 1 from public.rm_celulas_projeto where ident=any(forms_ids))
   or exists(select 1 from public.rm_form_template_drafts where(source_form_id=ident or published_form_id=ident) and id is distinct from removed_draft)
   or exists(select 1 from public.rm_form_template_versions where family_id=family and form_id<>ident)
   or exists(select 1 from public.rm_respostas where itens_questoes_ids&&iids)
   or exists(select 1 from public.rm_respostas_temp where itens_questoes_ids&&iids)
   or exists(select 1 from public.rm_numeracoes where form_id=ident and ult_numero>0) then
   raise exception 'Modelo vinculado ou utilizado; exclusão bloqueada.' using errcode='23503';end if;
  -- Discover all FK dependents, including future tables and SET NULL/CASCADE
  -- links. Only exclusive definition/publication children are removable.
  for dep in select c.conrelid,ns.nspname,t.relname,a.attname,c.confrelid
   from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace ns on ns.oid=t.relnamespace
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
   where c.contype='f' and c.confrelid in('public.rm_forms'::regclass,'public.rm_questoes'::regclass,'public.rm_itens_questoes'::regclass)
  loop
   if cardinality((select conkey from pg_constraint c where c.conrelid=dep.conrelid and c.confrelid=dep.confrelid and c.conkey[1]=(select attnum from pg_attribute where attrelid=dep.conrelid and attname=dep.attname) limit 1))<>1 then
    raise exception 'Dependência composta requer revisão.' using errcode='23503';end if;
   if dep.conrelid in('public.rm_questoes'::regclass,'public.rm_itens_questoes'::regclass,'public.rm_numeracoes'::regclass,
    'public.rm_form_template_drafts'::regclass,'public.rm_form_template_versions'::regclass) then continue;end if;
   target_ids:=case dep.confrelid when 'public.rm_forms'::regclass then array[ident] when 'public.rm_questoes'::regclass then qids else iids end;
   execute format('select exists(select 1 from %I.%I where %I=any($1))',dep.nspname,dep.relname,dep.attname) into used using target_ids;
   if used then raise exception 'Modelo possui dependências ou histórico; exclusão bloqueada.' using errcode='23503';end if;
  end loop;
  -- Retired routes may survive only in immutable journals. Keep their source
  -- definitions as well. Intrinsic builder receipts remain self-contained.
  ids:=array[ident]||qids||iids;
  if exists(select 1 from rm_private.web_mutation_receipts w cross join unnest(ids) x
   where w.operation not in('create_form_template','save_form_template','publish_form_template','delete_form_template')
    and(strpos(w.payload::text,x::text)>0 or strpos(coalesce(w.before_record::text,''),x::text)>0 or strpos(w.result::text,x::text)>0)) then
   raise exception 'Modelo consta no histórico de uso; exclusão bloqueada.' using errcode='23503';end if;
  original:=jsonb_build_object('form',to_jsonb(f),'draft',case when removed_draft is null then null else to_jsonb(d) end,
   'publication',case when v.form_id is null then null else to_jsonb(v) end,
   'questions',(select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') from public.rm_questoes q where q.id=any(qids)),
   'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') from public.rm_itens_questoes i where i.id=any(iids)));
  -- Removing exclusive publication metadata first permits deletion through the
  -- unchanged immutable-definition guard, inside this one atomic operation.
  delete from public.rm_form_template_versions where form_id=ident;
  if removed_draft is not null then delete from public.rm_form_template_drafts where id=removed_draft;end if;
  delete from public.rm_forms where id=ident;
 end if;
 if family is not null and not exists(select 1 from public.rm_form_template_drafts where family_id=family)
  and not exists(select 1 from public.rm_form_template_versions where family_id=family) then
  delete from public.rm_form_template_families where id=family;end if;
 result:=jsonb_build_object('operation',p_operation,'id',ident,'projeto_id',null,'updated_at',expected,
  'record',jsonb_build_object('id',ident,'kind',kind,'deleted',true),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,original);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='delete_form_template' then raise exception 'Identificador ou versão inválidos.' using errcode='22023';end if;raise;
end $$;

-- Reuse the existing ETL tombstone query; legacy models removed deliberately
-- must not be silently recreated on a later read-only Bubble import.
do $$ declare d text;needle text;begin
 d:=pg_get_functiondef('public.rm_web_form_source_snapshot_v1(uuid)'::regprocedure);
 needle:='''description'',f.description,''tipo'',f.tipo,''ativo'',f.ativo)';
 if strpos(d,needle)=0 then raise exception 'Unexpected form source snapshot';end if;
 execute replace(d,needle,'''description'',f.description,''tipo'',f.tipo,''ativo'',f.ativo,''updated_at'',f.updated_at)');
 d:=pg_get_functiondef('public.rm_deleted_bubble_ids_v1(text,text[])'::regprocedure);
 needle:='return array(select distinct x from rm_private.web_mutation_receipts';
 if strpos(d,needle)=0 then raise exception 'Unexpected tombstone reader';end if;
 d:=replace(d,'where r.operation=''delete_project'' and x=any(p_ids)',
  $tombstones$where r.operation='delete_project' and x=any(p_ids)
   union select r.before_record->'form'->>'bubble_id' from rm_private.web_mutation_receipts r
    where p_table='rm_forms' and r.operation='delete_form_template' and r.payload->>'kind'='form' and r.before_record->'form'->>'bubble_id'=any(p_ids)
   union select child->>'bubble_id' from rm_private.web_mutation_receipts r
    cross join lateral jsonb_array_elements(case
     when r.operation='delete_form_template' and r.payload->>'kind'='form' and p_table='rm_questoes' and jsonb_typeof(r.before_record->'questions')='array' then r.before_record->'questions'
     when r.operation='delete_form_template' and r.payload->>'kind'='form' and p_table='rm_itens_questoes' and jsonb_typeof(r.before_record->'items')='array' then r.before_record->'items'
     else '[]'::jsonb end) child
    where child->>'bubble_id'=any(p_ids)$tombstones$);
 if strpos(d,'delete_form_template')=0 then raise exception 'Unexpected tombstone predicate';end if;
 execute d;
 d:=pg_get_constraintdef((select oid from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check'));
 if strpos(d,'''manage_project_route_cell''::text')=0 then raise exception '040 required';end if;
 d:=replace(d,'''manage_project_route_cell''::text','''manage_project_route_cell''::text, ''delete_form_template''::text');
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check '||d;
 d:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 needle:='when ''publish_form_template'' then ''em.form_templates.manage''';
 if strpos(d,needle)=0 then raise exception 'Unexpected SSO map';end if;
 execute replace(d,needle,needle||' when ''delete_form_template'' then ''em.form_templates.manage''');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.guard_allocation_form_references_v1(),rm_private.guard_deleted_form_identity_v1(),
 rm_private.guard_answer_item_references_v1(),rm_private.lock_form_identity_v1(uuid,text,boolean),
 rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_template_delete_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

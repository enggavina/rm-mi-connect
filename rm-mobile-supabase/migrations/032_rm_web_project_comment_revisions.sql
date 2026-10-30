-- Correct proven manual comments without rewriting original attribution or offline receipts.
begin;
create table rm_private.project_comment_revisions (
 id uuid primary key default gen_random_uuid(),
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 comentario_id uuid not null references public.rm_comentarios(id) on delete restrict,
 revision integer not null check(revision>0),
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 auth_user_id uuid not null,
 client_submission_id uuid not null unique,
 motivo text not null check(length(motivo) between 1 and 2000),
 before_record jsonb not null,
 after_record jsonb not null,
 transaction_id bigint not null default txid_current(),
 created_at timestamptz not null default clock_timestamp(),
 unique(comentario_id,revision)
);
revoke all on rm_private.project_comment_revisions from public,anon,authenticated,service_role;

-- The only elevated reader exposes a scoped, bounded business projection. It
-- never returns Auth IDs, receipt bodies or complete private before/after rows.
create function rm_private.project_comment_revision_context_v1(p_project_id uuid,p_comment_id uuid,p_history_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.rm_comentarios%rowtype; a public.rm_celulas_projeto%rowtype; original jsonb;
 manual boolean:=false; total_count integer; page_no integer; history jsonb;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501'; end if;
 if p_history_page is null or p_history_page not between 1 and 100000 then raise exception 'Página do histórico inválida.' using errcode='22023'; end if;
 select * into c from public.rm_comentarios where id=p_comment_id and projeto_id=p_project_id;
 if not found then return null; end if;
 select * into a from public.rm_celulas_projeto where projeto_id=c.projeto_id and celula_id=c.celula_id;
 select before_record into original from rm_private.project_comment_revisions where comentario_id=c.id order by revision limit 1;
 original:=coalesce(original,to_jsonb(c));
 if a.id is not null and c.cadastrado_por_id is not null then
  manual:=exists(select 1 from rm_private.web_mutation_receipts r
   where r.operation='add_project_comment' and r.client_submission_id=c.id and r.actor_id=c.cadastrado_por_id
   and r.result->>'id'=c.id::text and r.result->>'projeto_id'=c.projeto_id::text
   and r.result->'record'->>'comment_id'=c.id::text and r.result->'record'->>'projeto_id'=c.projeto_id::text
   and r.result->'record'->>'celula_projeto_id'=a.id::text and r.result->'record'->>'celula_id'=c.celula_id::text
   and r.result->'record'->>'cadastrado_por_id'=c.cadastrado_por_id::text
   and (r.result->'record'->>'created_at')::timestamptz=c.created_at and r.result->'record'->>'evento'=original->>'evento'
   and (r.payload->>'projeto_id')::uuid=c.projeto_id and (r.payload->>'celula_projeto_id')::uuid=a.id
   and btrim(r.payload->>'evento')=original->>'evento')
  or exists(select 1 from rm_private.mobile_mutation_receipts r
   where r.rpc_name='rm_add_cell_comment_v1' and r.operator_id=c.cadastrado_por_id
   and r.result=jsonb_build_object('comentario_id',c.id,'projeto_id',c.projeto_id,'celula_id',c.celula_id)
   and (r.params->>'p_celula_projeto_id')::uuid=a.id and btrim(r.params->>'p_comentario')=original->>'evento'
   and r.created_at>=c.created_at);
 end if;
 -- A known creation receipt authorizes only the exact original identity and the
 -- latest audited text, never a detached/imported replacement of that row.
 if exists(select 1 from rm_private.project_comment_revisions r where r.comentario_id=c.id) then
  manual:=manual and exists(select 1 from rm_private.project_comment_revisions r where r.comentario_id=c.id
   and r.revision=(select max(x.revision) from rm_private.project_comment_revisions x where x.comentario_id=c.id)
   and r.after_record->>'evento'=c.evento and (r.after_record->>'created_at')::timestamptz=c.created_at
   and not exists(select 1 from unnest(array['id','projeto_id','celula_id','cadastrado_por_id']) k where r.after_record->k is distinct from to_jsonb(c)->k));
 end if;
 select count(*) into total_count from rm_private.project_comment_revisions where comentario_id=c.id and projeto_id=c.projeto_id;
 page_no:=least(p_history_page,greatest(1,ceil(total_count::numeric/25)::integer));
 select coalesce(jsonb_agg(v.row order by v.revision desc),'[]') into history from (
  select r.revision,jsonb_build_object('id',r.id,'revision',r.revision,'evento_anterior',r.before_record->>'evento',
   'evento_novo',r.after_record->>'evento','motivo',r.motivo,'editor_id',r.actor_id,'editor_name',u.nome,
   'editor_registration',u.matricula,'created_at',r.created_at) row
  from rm_private.project_comment_revisions r left join public.rm_users u on u.id=r.actor_id
  where r.comentario_id=c.id and r.projeto_id=c.projeto_id order by r.revision desc limit 25 offset (page_no-1)*25
 ) v;
 return jsonb_build_object('manual',manual,'stage_evidence',exists(select 1 from public.rm_web_stage_decisions d where d.comentario_id=c.id),
  'history',jsonb_build_object('items',history,'total',total_count,'page',page_no,'page_size',25));
end $$;
revoke all on function rm_private.project_comment_revision_context_v1(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function rm_private.project_comment_revision_context_v1(uuid,uuid,integer) to authenticated;

create function public.rm_web_project_comment_snapshot_v1(p_project_id uuid,p_comment_id uuid,p_history_page integer default 1)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare p public.rm_projetos%rowtype; c public.rm_comentarios%rowtype; a public.rm_celulas_projeto%rowtype;
 actor public.rm_users%rowtype; context jsonb; closed boolean; eligible boolean; reason text; author_name text; author_registration text; cell_name text;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501'; end if;
 select * into p from public.rm_projetos where id=p_project_id;
 if not found then return null; end if;
 select * into c from public.rm_comentarios where id=p_comment_id and projeto_id=p.id;
 if not found then return null; end if;
 select * into a from public.rm_celulas_projeto where projeto_id=p.id and celula_id=c.celula_id;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 context:=rm_private.project_comment_revision_context_v1(p.id,c.id,p_history_page);
 select nome,matricula into author_name,author_registration from public.rm_users where id=c.cadastrado_por_id;
 select nome into cell_name from public.rm_celulas where id=c.celula_id;
 closed:=p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false);
 reason:=case when (context->>'stage_evidence')::boolean then 'Observação vinculada a uma decisão: registro preservado para consulta.'
  when not (context->>'manual')::boolean then 'A origem manual deste registro não foi comprovada. Consulte o histórico preservado.'
  when closed then 'Projeto encerrado: somente consulta.'
  when a.id is null or a.retirada then 'A célula não está ativa neste projeto. Registro preservado para consulta.'
  when actor.perfil not in('administrador','padr_o') or (actor.perfil='padr_o' and c.cadastrado_por_id is distinct from actor.id)
   then 'Somente o autor ou um administrador pode corrigir este comentário.' else null end;
 eligible:=reason is null;
 return jsonb_build_object('project',jsonb_build_object('id',p.id,'numero',p.numero,'updated_at',p.updated_at,'status_pcp',p.status_pcp,
  'data_real_de_entrega',p.data_real_de_entrega,'closed',closed),
  'comment',jsonb_build_object('id',c.id,'projeto_id',c.projeto_id,'celula_id',c.celula_id,'cadastrado_por_id',c.cadastrado_por_id,
   'evento',c.evento,'created_at',c.created_at,'updated_at',c.updated_at,'author_name',author_name,'author_registration',author_registration,'cell_name',cell_name),
  'allocation',case when a.id is not null then jsonb_build_object('id',a.id,'updated_at',a.updated_at,'retirada',a.retirada) else null end,
  'can_edit',eligible,'reason',reason,'context_version',encode(sha256(convert_to(jsonb_build_object('project',to_jsonb(p),'comment',to_jsonb(c),
   'allocation',to_jsonb(a),'manual',context->'manual','stage',context->'stage_evidence','revision',context->'history'->'total')::text,'UTF8')),'hex'),
  'history',context->'history');
end $$;
revoke all on function public.rm_web_project_comment_snapshot_v1(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_comment_snapshot_v1(uuid,uuid,integer) to authenticated;

create function rm_private.guard_project_comment_revisions_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_json jsonb:=to_jsonb(old); new_json jsonb; protected constant text[]:=array['id','projeto_id','celula_id','cadastrado_por_id','created_at','evento'];
begin
 if not exists(select 1 from rm_private.project_comment_revisions r where r.comentario_id=old.id) then
  if tg_op='DELETE' then return old; else return new; end if;
 end if;
 if tg_op='DELETE' then raise exception 'Comentário com correção registrada: preserve o histórico.' using errcode='PT409'; end if;
 new_json:=to_jsonb(new);
 if exists(select 1 from unnest(protected) k where new_json->k is distinct from old_json->k)
 and not exists(select 1 from rm_private.project_comment_revisions r where r.comentario_id=old.id and r.transaction_id=txid_current()
  and r.before_record=old_json and r.after_record->>'evento'=new.evento
  and new_json-array['evento','updated_at']=old_json-array['evento','updated_at']) then
  raise exception 'Comentário corrigido no portal. Atualize o contexto sem substituir o registro original.' using errcode='PT409'; end if;
 return new;
end $$;
revoke all on function rm_private.guard_project_comment_revisions_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_comment_revisions before update or delete on public.rm_comentarios for each row execute function rm_private.guard_project_comment_revisions_v1();

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_project_equipment_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 p public.rm_projetos%rowtype; c public.rm_comentarios%rowtype; a public.rm_celulas_projeto%rowtype;
 project_id uuid; comment_id uuid; expected_project timestamptz; expected_comment timestamptz; snapshot jsonb; result jsonb;
 body text; correction_reason text; before_record jsonb; journal_id uuid; revision_no integer; changed boolean;
 allowed constant text[]:=array['projeto_id','comentario_id','expected_project_updated_at','expected_comment_updated_at','expected_context_version','evento','motivo','confirm_change'];
begin
 if p_operation is distinct from 'edit_project_comment' then return rm_private.web_mutate_project_equipment_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or actor.perfil not in('administrador','padr_o') then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object'
  or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string' or jsonb_typeof(p_payload->'comentario_id') is distinct from 'string'
 then raise exception 'Envio inválido.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; comment_id:=(p_payload->>'comentario_id')::uuid;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 -- Current role and original ownership precede recovery of a completed receipt.
 select * into c from public.rm_comentarios where id=comment_id and projeto_id=project_id;
 if actor.perfil='padr_o' and (c.id is null or c.cadastrado_por_id is distinct from actor.id) then raise exception 'Somente o autor ou um administrador pode corrigir este comentário.' using errcode='42501'; end if;
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or p_payload->'confirm_change' is distinct from 'true'::jsonb
  or jsonb_typeof(p_payload->'expected_project_updated_at') is distinct from 'string'
  or jsonb_typeof(p_payload->'expected_comment_updated_at') is distinct from 'string'
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_comment_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or jsonb_typeof(p_payload->'expected_context_version') is distinct from 'string' or p_payload->>'expected_context_version' !~ '^[a-f0-9]{64}$'
  or jsonb_typeof(p_payload->'evento') is distinct from 'string' or jsonb_typeof(p_payload->'motivo') is distinct from 'string'
 then raise exception 'Confirmação, versões ou comentário inválidos.' using errcode='22023'; end if;
 body:=btrim(p_payload->>'evento'); correction_reason:=btrim(p_payload->>'motivo');
 if length(body) not between 1 and 10000 or body !~ '[^[:space:]]' or length(correction_reason) not between 1 and 2000 or correction_reason !~ '[^[:space:]]' then raise exception 'Informe o comentário e o motivo da correção dentro dos limites.' using errcode='22023'; end if;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_comment:=(p_payload->>'expected_comment_updated_at')::timestamptz;
 if not isfinite(expected_project) or not isfinite(expected_comment) then raise exception 'Versões inválidas.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into p from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 select * into a from public.rm_celulas_projeto where projeto_id=project_id and celula_id=c.celula_id for update;
 select * into c from public.rm_comentarios where id=comment_id and projeto_id=project_id for update;
 if not found then raise exception 'Comentário inexistente neste projeto.' using errcode='P0002'; end if;
 snapshot:=public.rm_web_project_comment_snapshot_v1(project_id,comment_id,1);
 if p.updated_at<>expected_project or c.updated_at<>expected_comment or snapshot->>'context_version'<>p_payload->>'expected_context_version'
 then raise exception 'O projeto ou comentário mudou. Recarregue antes de corrigir.' using errcode='PT409'; end if;
 if not (snapshot->>'can_edit')::boolean then raise exception '%',snapshot->>'reason' using errcode='42501'; end if;
 before_record:=to_jsonb(c); changed:=c.evento is distinct from body;
 select coalesce(max(r.revision),0) into revision_no from rm_private.project_comment_revisions r where r.comentario_id=c.id;
 if changed then
  revision_no:=revision_no+1;
  insert into rm_private.project_comment_revisions(projeto_id,comentario_id,revision,actor_id,auth_user_id,client_submission_id,motivo,before_record,after_record)
   values(project_id,c.id,revision_no,actor.id,auth.uid(),p_client_submission_id,correction_reason,before_record,jsonb_set(before_record,'{evento}',to_jsonb(body))) returning id into journal_id;
  update public.rm_comentarios set evento=body where id=c.id returning * into c;
  update rm_private.project_comment_revisions set after_record=to_jsonb(c) where id=journal_id;
 end if;
 snapshot:=public.rm_web_project_comment_snapshot_v1(project_id,comment_id,1);
 result:=jsonb_build_object('operation',p_operation,'id',c.id,'projeto_id',project_id,'updated_at',c.updated_at,'idempotent_replay',false,
  'record',jsonb_build_object('projeto_id',project_id,'comentario_id',c.id,'project_updated_at',p.updated_at,'changed',changed,'revision',revision_no,'context_version',snapshot->>'context_version'));
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation='edit_project_comment' then raise exception 'Identificador, versão ou comentário inválido.' using errcode='22023'; end if; raise;
end $$;
alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check check(operation in(
 'save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title','create_form_template','save_form_template','publish_form_template',
 'transition_stage_approval','save_cell_queue','set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer',
 'manage_stage_rules','manage_cell_availability','add_project_comment','reserve_project_attachment','finalize_project_attachment','save_project_equipment','edit_project_comment'));
do $$ declare definition text; marker text:='when ''save_project_equipment'' then ''em.projects.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Unexpected comment revision permit map'; end if;
 execute replace(definition,marker,'when ''save_project_equipment'' then ''em.projects.manage'' when ''edit_project_comment'' then ''em.projects.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_project_equipment_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_assignment_permits (
 submission_id uuid primary key,
 session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 workshop_id uuid not null references rm_private.workshop_references(id),
 subject uuid not null,
 operation text not null,
 payload_hash bytea not null,
 eligible_ids uuid[] not null,
 expires_at timestamptz not null
);
create index workshop_assignment_permits_session on rm_private.workshop_assignment_permits(session_hash);
alter table rm_private.workshop_assignment_permits enable row level security;

create table rm_private.workshop_assignment_enforcement (
 singleton boolean primary key default true check (singleton),
 activated_at timestamptz not null
);
alter table rm_private.workshop_assignment_enforcement enable row level security;
revoke all on rm_private.workshop_assignment_enforcement,rm_private.workshop_assignment_permits from public,anon,authenticated,service_role;

create function rm_private.activate_workshop_assignments_v1() returns void
language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop-assignment-cutover',51));
 if not exists(select 1 from rm_private.engineering_workshop_enforcement where singleton) then
  raise exception 'Ative a engenharia por oficina antes das atribuições.' using errcode='22023';
 end if;
 insert into rm_private.workshop_assignment_enforcement(singleton,activated_at)
  values(true,clock_timestamp()) on conflict do nothing;
 revoke execute on function public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean),
  public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean) from authenticated;
end
$$;

create function rm_private.workshop_assignment_ids_v1(p_members jsonb,p_viewer uuid) returns uuid[]
language plpgsql stable set search_path='' as $$
declare ids uuid[];
begin
 if jsonb_typeof(p_members) is distinct from 'array' or jsonb_array_length(p_members) not between 1 and 768
  or not (p_members @> jsonb_build_array(jsonb_build_object('kind','corporate','subject',p_viewer)))
  or exists(select 1 from jsonb_array_elements(p_members) m
   where m is distinct from jsonb_build_object('kind',m->'kind','subject',m->'subject')
    or coalesce(m->>'kind','') not in('corporate','operator') or jsonb_typeof(m->'subject') is distinct from 'string'
    or (m->>'subject') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or exists(select 1 from jsonb_array_elements(p_members) m group by m having count(*)>1) then
  raise exception 'Vínculos de atribuição inválidos.' using errcode='22023';
 end if;
 with members as materialized (
  select m.kind,m.subject from jsonb_to_recordset(p_members) as m(kind text,subject uuid)
 ), matched as (
  select u.id from members m join public.rm_users u on u.id=m.subject and u.status='ativo' where m.kind='operator'
  union
  select u.id from members m join rm_private.sso_identity_bindings b on m.kind='corporate' and m.subject=b.subject
   and b.enabled and b.issuer='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
  join public.rm_users u on u.id=b.rm_user_id and u.auth_user_id=b.auth_user_id and u.status='ativo'
 )
 select coalesce(array_agg(id order by id),'{}') into ids from matched;
 return ids;
end
$$;

create function rm_private.workshop_assignment_read_v1(p_resource text,p_args jsonb,p_office uuid,p_viewer uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare args jsonb:=p_args-'members'; allowed uuid[]; project uuid; allocation uuid; include_choices boolean;
 result jsonb; choices jsonb; rows jsonb; entry jsonb;
begin
 if p_resource='assignment_people' and args->>'purpose' in('project','planning')
  and args=jsonb_build_object('purpose',args->'purpose') then
  allowed:=rm_private.workshop_assignment_ids_v1(p_args->'members',p_viewer);
  return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',nome,'status',status) order by nome,id),'[]')
   from public.rm_users where id=any(allowed));
 end if;
 if p_resource='engineering_assignment_choices' then
  allowed:=rm_private.workshop_assignment_ids_v1(p_args->'members',p_viewer);
  result:=rm_private.workshop_engineering_read_v1('engineering_choices',args,p_office);
  if result is null then return null;end if;
  entry:=rm_private.workshop_engineering_entry_v1((args->>'id')::uuid,p_office);
  select coalesce(jsonb_agg(l order by l->>'id'),'[]') into rows
   from jsonb_array_elements(result->'cellUserLinks') l where (l->>'identidade_id')::uuid=any(allowed);
  result:=jsonb_set(result,'{cellUserLinks}',rows);
  select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome,'matricula',u.matricula,'status',u.status) order by u.nome,u.id),'[]') into rows
  from public.rm_users u where exists(select 1 from jsonb_array_elements(result->'cellUserLinks') l where l->>'identidade_id'=u.id::text)
   or exists(select 1 from jsonb_array_elements(entry->'stages') s where s->>'aprovador_id'=u.id::text
    or s->'aprovadores_ids' ? u.id::text or s->'aprovadores_retorno_ids' ? u.id::text);
  return jsonb_set(result,'{users}',rows);
 end if;
 if p_resource not in('operational_reviewers','operational_stage_rules')
  or args is distinct from jsonb_build_object('project',args->'project','allocation',args->'allocation','include',args->'include')
  or jsonb_typeof(args->'project') is distinct from 'string' or jsonb_typeof(args->'allocation') is distinct from 'string'
  or jsonb_typeof(args->'include') is distinct from 'boolean' then
  raise exception 'Consulta de atribuição inválida.' using errcode='22023';
 end if;
 project:=(args->>'project')::uuid;
 allocation:=(args->>'allocation')::uuid;
 include_choices:=(args->>'include')::boolean;
 if include_choices then
  allowed:=rm_private.workshop_assignment_ids_v1(p_args->'members',p_viewer);
 elsif p_args?'members' then
  raise exception 'Consulta de atribuição inválida.' using errcode='22023';
 end if;
 if not rm_private.workshop_project_owned_v1(project,p_office)
  or not exists(select 1 from public.rm_celulas_projeto a where a.id=allocation and a.projeto_id=project)
  or exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=project
    and not rm_private.workshop_cell_owned_v1(a.celula_id,p_office)) then
  return null;
 end if;
 if p_resource='operational_reviewers' then
  result:=public.rm_web_form_reviewer_assignments_snapshot_v1(project,allocation,include_choices);
  if exists(select 1 from jsonb_array_elements(result->'forms') f
    where not rm_private.workshop_read_visible_v1('form_model',(f->>'id')::uuid,p_office)) then return null;end if;
 elsif p_resource='operational_stage_rules' then
  result:=public.rm_web_stage_rules_snapshot_v1(project,allocation,include_choices);
  if exists(select 1 from jsonb_array_elements(result->'rules') r where r->>'celula_destino_id' is not null
    and not rm_private.workshop_cell_owned_v1((r->>'celula_destino_id')::uuid,p_office)) then return null;end if;
 end if;
 if result is null or not include_choices or not (result->>'eligible_complete')::boolean
  or p_resource='operational_stage_rules' and not ((result->>'complete')::boolean and (result->>'allocations_complete')::boolean
   and (result->>'memberships_complete')::boolean) then return result;end if;
 select coalesce(jsonb_agg(person order by ord),'[]') into choices from jsonb_array_elements(result->'eligible_users') with ordinality e(person,ord)
  where (person->>'id')::uuid=any(allowed);
 result:=result||jsonb_build_object('eligible_users',choices,'eligible_total',jsonb_array_length(choices));
 if p_resource='operational_reviewers' then
  select coalesce(jsonb_agg(case when jsonb_typeof(f->'assignment')='object' then
   jsonb_set(f,'{assignment,eligible}',to_jsonb(exists(select 1 from jsonb_array_elements(choices) c
    where c->>'id'=f->'assignment'->>'avaliador_user_id'))) else f end order by ord),'[]') into rows
   from jsonb_array_elements(result->'forms') with ordinality e(f,ord);
  return jsonb_set(result,'{forms}',rows);
 end if;
 select coalesce(jsonb_agg(r||jsonb_build_object(
  'approvers',(select coalesce(jsonb_agg(jsonb_set(person,'{eligible}',to_jsonb((person->>'eligible')::boolean
   and (person->>'id')::uuid=any(allowed))) order by po),'[]') from jsonb_array_elements(r->'approvers') with ordinality x(person,po)),
  'return_approvers',(select coalesce(jsonb_agg(jsonb_set(person,'{eligible}',to_jsonb((person->>'eligible')::boolean
   and (person->>'id')::uuid=any(allowed))) order by po),'[]') from jsonb_array_elements(r->'return_approvers') with ordinality x(person,po)),
  'can_restore',(r->>'can_restore')::boolean and not exists(select 1 from
   jsonb_array_elements_text(coalesce(r->'aprovadores_ids','[]')||coalesce(r->'aprovadores_retorno_ids','[]')||
    jsonb_build_array(r->'aprovador_id')) person where person is not null and not(person::uuid=any(allowed)))) order by ord),'[]') into rows
  from jsonb_array_elements(result->'rules') with ordinality e(r,ord);
 return result||jsonb_build_object('rules',rows,'memberships_total',
  (select coalesce(sum(jsonb_array_length(c->'celula_ids')),0) from jsonb_array_elements(choices) c));
exception when invalid_text_representation then
 raise exception 'Identificador de atribuição inválido.' using errcode='22023';
end
$$;

create function rm_private.workshop_assignment_required_v1(p_operation text,p_payload jsonb) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(case p_operation
  when 'save_project' then jsonb_typeof(p_payload->'changes'->'gestor_responsavel_id')='string'
  when 'save_project_with_equipment' then jsonb_typeof(p_payload->'changes'->'gestor_responsavel_id')='string'
  when 'plan_cell' then jsonb_typeof(p_payload->'changes'->'responsavel_id')='string'
  when 'assign_form_reviewer' then jsonb_typeof(p_payload->'avaliador_user_id')='string'
  when 'manage_stage_rules' then p_payload->>'action' in('create','replace','restore','retire')
  when 'save_engineering' then jsonb_typeof(p_payload->'changes'->'stages')='array' and p_payload->'changes'->'stages'<>'[]'
  else false end,false);
$$;

create function public.rm_sso_assignment_workshop_permit_v1(p_session_hash text,p_submission_id uuid,p_operation text,
 p_payload jsonb,p_context jsonb,p_members jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare seed uuid:=gen_random_uuid(); scope rm_private.workshop_read_permits; eligible uuid[];
begin
 if p_submission_id is null or not rm_private.workshop_assignment_required_v1(p_operation,p_payload)
  or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2097152
  or (p_context->>'expires_at')::timestamptz>(p_context->>'issued_at')::timestamptz+interval '20 seconds' then
  raise exception 'Protocolo de atribuição inválido.' using errcode='22023';
 end if;
 perform public.rm_sso_workshop_read_permit_v1(p_session_hash,seed,'workshop_team',
  jsonb_build_object('q','','page',1,'members',p_members),p_context);
 delete from rm_private.workshop_read_permits where read_id=seed returning * into scope;
 eligible:=rm_private.workshop_assignment_ids_v1(p_members,scope.subject);
 insert into rm_private.workshop_assignment_permits as p (submission_id,session_hash,workshop_id,subject,operation,payload_hash,eligible_ids,expires_at)
  values(p_submission_id,scope.session_hash,scope.workshop_id,scope.subject,p_operation,extensions.digest(p_payload::text,'sha256'),eligible,scope.expires_at)
 on conflict(submission_id) do update set eligible_ids=excluded.eligible_ids,expires_at=excluded.expires_at
 where (p.session_hash,p.workshop_id,p.subject,p.operation,p.payload_hash)=
  (excluded.session_hash,excluded.workshop_id,excluded.subject,excluded.operation,excluded.payload_hash);
 if not found then raise exception 'Protocolo de atribuição divergente.' using errcode='42501';end if;
end
$$;

create function rm_private.assert_workshop_assignees_v1(p_people jsonb,p_allowed uuid[],p_previous uuid[] default '{}') returns void
language plpgsql stable set search_path='' as $$
begin
 if jsonb_typeof(p_people) is distinct from 'array' then
  raise exception 'Lista de atribuição inválida.' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_array_elements_text(p_people) person where person is null or
  (not coalesce(person::uuid=any(p_previous),false)
   and not exists(select 1 from public.rm_users u where u.id=person::uuid and u.id=any(p_allowed) and u.status='ativo'))) then
  raise exception 'A pessoa indicada precisa ter vínculo ativo com esta oficina.' using errcode='42501';
 end if;
end
$$;

create function rm_private.web_mutate_workshop_assignments_v1(p_submission uuid,p_operation text,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare permit rm_private.workshop_assignment_permits; binding rm_private.sso_identity_bindings; sess rm_private.sso_sessions;
 changes jsonb:=p_payload->'changes'; scope uuid; project uuid; cell uuid; allocation uuid; person uuid; prior uuid;
 rule public.rm_aprovacoes_etapas; item jsonb; exact_replay boolean; result jsonb;
begin
 if not rm_private.workshop_assignment_required_v1(p_operation,p_payload) then
  return rm_private.web_mutate_engineering_workshop_v1(p_submission,p_operation,p_payload);
 end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('workshop-assignment-cutover',51));
 select * into permit from rm_private.workshop_assignment_permits where submission_id=p_submission;
 if not found and not exists(select 1 from rm_private.workshop_assignment_enforcement where singleton) then
  return rm_private.web_mutate_engineering_workshop_v1(p_submission,p_operation,p_payload);
 end if;
 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=permit.session_hash for share of b;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 select * into permit from rm_private.workshop_assignment_permits where submission_id=p_submission for update;
 if not found or not coalesce(binding.enabled,false) or sess.binding_id is distinct from binding.id
  or permit.session_hash is distinct from sess.hash or permit.subject is distinct from binding.subject
  or binding.auth_user_id is distinct from auth.uid() or sess.local_session_id::text is distinct from auth.jwt()->>'session_id'
  or sess.expires_at<=clock_timestamp() or permit.expires_at<=clock_timestamp() or permit.operation is distinct from p_operation
  or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256')
  or not exists(select 1 from auth.sessions s where s.id=sess.local_session_id and s.user_id=binding.auth_user_id) then
  raise exception 'Confirmação da equipe ausente, expirada ou divergente.' using errcode='42501';
 end if;
 scope:=permit.workshop_id;
 select exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_submission and auth_user_id=auth.uid()
  and operation=p_operation and payload=p_payload) into exact_replay;
 if p_operation='save_engineering' then
  cell:=(p_payload->>'celula_id')::uuid;
  perform rm_private.workshop_assert_origin_v1('cell',cell,scope);
  if not exact_replay then
   for item in select value from jsonb_array_elements(changes->'stages') loop
    select * into rule from public.rm_aprovacoes_etapas where id=(item->>'id')::uuid
     and celula_tipo_equipamento_id=(p_payload->>'id')::uuid and projeto_id is null and celula_projeto_id is null
     and celula_origem_id=cell and celula_destino_id=(item->>'celula_destino_id')::uuid;
    perform rm_private.assert_workshop_assignees_v1(item->'aprovadores_ids',permit.eligible_ids,rule.aprovadores_ids);
    perform rm_private.assert_workshop_assignees_v1(item->'aprovadores_retorno_ids',permit.eligible_ids,rule.aprovadores_retorno_ids);
   end loop;
  end if;
 else
  project:=coalesce((p_payload->>'projeto_id')::uuid,(p_payload->>'id')::uuid);
  if project is null or not rm_private.workshop_project_owned_v1(project,scope)
   and not (p_operation='save_project_with_equipment' and p_payload->'expected_updated_at'='null'::jsonb
    and not exists(select 1 from public.rm_projetos where id=project)) then
   raise exception 'Projeto indisponível nesta oficina.' using errcode='42501';
  end if;
  if rm_private.workshop_project_owned_v1(project,scope) then
   perform rm_private.workshop_assert_origin_v1('project',project,scope);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(project::text,11));
  if p_operation in('save_project','save_project_with_equipment') then
   person:=(changes->>'gestor_responsavel_id')::uuid;
   select gestor_responsavel_id into prior from public.rm_projetos where id=project;
  elsif p_operation='plan_cell' then
   cell:=(p_payload->>'celula_id')::uuid;
   perform rm_private.workshop_assert_origin_v1('cell',cell,scope);
   person:=(changes->>'responsavel_id')::uuid;
   select responsavel_id into prior from public.rm_celulas_projeto where projeto_id=project and celula_id=cell;
  else
   allocation:=(p_payload->>'celula_projeto_id')::uuid;
   select celula_id into cell from public.rm_celulas_projeto where id=allocation and projeto_id=project;
   perform rm_private.workshop_assert_origin_v1('cell',cell,scope);
   if p_operation='assign_form_reviewer' then
    if not rm_private.workshop_read_visible_v1('form_model',(p_payload->>'form_id')::uuid,scope) then
     raise exception 'Formulário indisponível nesta oficina.' using errcode='42501';
    end if;
    person:=(p_payload->>'avaliador_user_id')::uuid;
   elsif not exact_replay then
    if p_payload->>'action' in('create','replace') then
     item:=p_payload->'config';
     perform rm_private.workshop_assert_origin_v1('cell',(item->>'celula_destino_id')::uuid,scope);
     perform rm_private.assert_workshop_assignees_v1(item->'aprovadores_ids',permit.eligible_ids);
     perform rm_private.assert_workshop_assignees_v1(item->'aprovadores_retorno_ids',permit.eligible_ids);
    elsif p_payload->>'action'='restore' then
     select * into rule from public.rm_aprovacoes_etapas where id=(p_payload->>'etapa_id')::uuid
      and projeto_id=project and celula_projeto_id=allocation and celula_origem_id=cell;
     perform rm_private.workshop_assert_origin_v1('cell',rule.celula_destino_id,scope);
     perform rm_private.assert_workshop_assignees_v1(
      to_jsonb(array_remove(array[rule.aprovador_id]||rule.aprovadores_ids||rule.aprovadores_retorno_ids,null)),permit.eligible_ids);
    end if;
   end if;
  end if;
  if person is not null and not exact_replay and person is distinct from prior then
   perform rm_private.assert_workshop_assignees_v1(jsonb_build_array(person),permit.eligible_ids);
  end if;
 end if;
 result:=rm_private.web_mutate_engineering_workshop_v1(p_submission,p_operation,p_payload);
 delete from rm_private.workshop_assignment_permits where submission_id=p_submission and expires_at>clock_timestamp();
 if not found then raise exception 'A confirmação da equipe expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
 return result;
exception when invalid_text_representation then
 if scope is null then raise;end if;
 raise exception 'Identificador de atribuição inválido.' using errcode='22023';
end
$$;

revoke all on function rm_private.activate_workshop_assignments_v1(),
 rm_private.workshop_assignment_ids_v1(jsonb,uuid),rm_private.workshop_assignment_read_v1(text,jsonb,uuid,uuid),
 rm_private.workshop_assignment_required_v1(text,jsonb),rm_private.assert_workshop_assignees_v1(jsonb,uuid[],uuid[]),
 rm_private.web_mutate_workshop_assignments_v1(uuid,text,jsonb),
 public.rm_sso_assignment_workshop_permit_v1(text,uuid,text,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_assignment_workshop_permit_v1(text,uuid,text,jsonb,jsonb,jsonb) to service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot','cell_availability','cell_queue','planning_load',
  'execution_snapshot','engineering_matrix','engineering_entry','engineering_choices','photo_title_list','photo_title_entry','workshop_team',
  'assignment_people','engineering_assignment_choices','operational_reviewers','operational_stage_rules'));

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 tail constant text:='''workshop_team'')';
 limits constant text:='p_resource=''workshop_team'' then 65536';
 dispatch constant text:='  when ''workshop_team'' then rm_private.workshop_team_read_v1(p_args,binding.subject)';
 previous constant text:='return rm_private.web_mutate_engineering_workshop_v1(p_client_submission_id,p_operation,p_payload);';
 resources constant text:='''assignment_people'',''engineering_assignment_choices'',''operational_reviewers'',''operational_stage_rules''';
 extra text;
begin
 if array_length(string_to_array(issuer,tail),1) is distinct from 2
  or array_length(string_to_array(issuer,limits),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2
  or array_length(string_to_array(writer,previous),1) is distinct from 2 then raise exception 'Unexpected workshop assignment contract';end if;
 issuer:=replace(issuer,tail,'''workshop_team'','||resources||')');
 execute replace(issuer,limits,'p_resource in(''workshop_team'','||resources||') then 65536');
 select string_agg(format('  when %L then rm_private.workshop_assignment_read_v1(p_resource,p_args,permit.workshop_id,binding.subject)', value),chr(10))
  into extra from unnest(array['assignment_people','engineering_assignment_choices','operational_reviewers','operational_stage_rules']) value;
 execute replace(reader,dispatch,dispatch||chr(10)||extra);
 execute replace(writer,previous,'return rm_private.web_mutate_workshop_assignments_v1(p_client_submission_id,p_operation,p_payload);');
end
$extend$;
notify pgrst,'reload schema';
commit;

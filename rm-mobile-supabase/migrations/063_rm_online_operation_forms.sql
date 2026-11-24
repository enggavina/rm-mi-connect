begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';

-- Consume the scoped project projection within the same database snapshot.
create function rm_private.online_operation_form_v1(p_project jsonb, p_form_id uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
begin
  if not coalesce(p_project->>'kind' = 'project'
    and (p_project->'forms') @> jsonb_build_array(jsonb_build_object('id',p_form_id)),false) then
    return null;
  end if;

  return (
    select jsonb_build_object('kind','form','cell',p_project->'cell','project',p_project->'project',
      'form',jsonb_build_object('id',f.id,'titulo',f.titulo,'descricao',f.descricao),
      'questions',coalesce((
        select jsonb_agg(jsonb_build_object('id',q.id,'indice',q.indice::text,'enunciado',q.enunciado,
          'subtitulo',q.subtitulo,'tipo',q.tipo,'obrigatorio',q.obrigatorio,
          'items',coalesce((
            select jsonb_agg(jsonb_build_object('id',i.id,'descricao',i.descricao) order by i.indice,i.id)
            from public.rm_itens_questoes i where i.questao_id=q.id and (i.form_id is null or i.form_id=q.form_id)
          ),'[]'::jsonb)) order by q.indice,q.id)
        from public.rm_questoes q where q.form_id=f.id
      ),'[]'::jsonb))
    from public.rm_forms f where f.id=p_form_id
  );
end;
$$;

create function public.rm_online_operation_form_read_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text,
  p_workshop_context jsonb, p_cell_id uuid, p_project_id uuid, p_form_id uuid
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if p_cell_id is null or p_project_id is null or p_form_id is null then return null; end if;
  return rm_private.online_operation_form_v1(public.rm_online_operation_read_v1(
    p_auth_user_id,p_session_id,p_operator_token,p_workshop_context,p_cell_id,p_project_id,1),p_form_id);
end;
$$;

revoke all on function rm_private.online_operation_form_v1(jsonb,uuid) from public,anon,authenticated,service_role;
revoke all on function public.rm_online_operation_form_read_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_online_operation_form_read_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid) to service_role;

-- The existing single-use permit binds form_id along with the other arguments.
create or replace function rm_private.online_operation_validation_v1(
  p_subject uuid, p_binding_id uuid, p_rm_user_id uuid, p_office_id uuid, p_args jsonb
) returns jsonb language plpgsql stable set search_path = '' as $$
declare
  operator_id uuid;
  cells uuid[];
  cell_id uuid;
  project_id uuid;
  form_id uuid;
  page_no integer;
  projection jsonb;
begin
  operator_id := rm_private.online_operation_validation_actor_v1(p_subject,p_binding_id,p_rm_user_id,p_office_id);
  if operator_id is null then
    raise exception using errcode = '42501', message = 'Validação operacional indisponível para esta identidade.';
  end if;
  if jsonb_typeof(p_args) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(p_args) k) is distinct from
      (case when p_args ? 'form_id' then array['cell_id','form_id','page','project_id'] else array['cell_id','page','project_id'] end)
    or jsonb_typeof(p_args->'cell_id') not in ('null','string')
    or jsonb_typeof(p_args->'project_id') not in ('null','string')
    or (p_args ? 'form_id' and jsonb_typeof(p_args->'form_id') is distinct from 'string')
    or jsonb_typeof(p_args->'page') is distinct from 'number' or p_args->>'page' !~ '^[0-9]{1,5}$' then
    raise exception using errcode = '22023', message = 'Seleção operacional inválida.';
  end if;
  cell_id := (p_args->>'cell_id')::uuid;
  project_id := (p_args->>'project_id')::uuid;
  form_id := (p_args->>'form_id')::uuid;
  page_no := (p_args->>'page')::integer;
  if page_no not between 1 and 10000 or (project_id is not null and cell_id is null)
    or (form_id is not null and (project_id is null or page_no <> 1)) then
    raise exception using errcode = '22023', message = 'Seleção operacional inválida.';
  end if;
  select coalesce(array_agg(distinct grant_row.celula_id),'{}'::uuid[]) into cells
  from public.rm_tablet_celula_users grant_row where grant_row.identidade_id = operator_id;

  projection := rm_private.online_operation_projection_v1(operator_id,p_office_id,cell_id,project_id,page_no,cells);
  if form_id is null then return projection; end if;
  return rm_private.online_operation_form_v1(projection,form_id);
end;
$$;

notify pgrst,'reload schema';
commit;

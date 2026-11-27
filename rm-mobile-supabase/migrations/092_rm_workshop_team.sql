begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Membership is issued by the corporate authority and bound to this read's
-- digest. Resolve only canonical local identities and expose the catalog DTO.
create function rm_private.workshop_team_read_v1(p_args jsonb,p_viewer uuid) returns jsonb
language plpgsql stable set search_path='' as $team$
declare term text; page integer; result jsonb;
begin
 if jsonb_typeof(p_args) is distinct from 'object'
  or p_args is distinct from jsonb_build_object('q',p_args->'q','page',p_args->'page','members',p_args->'members')
  or jsonb_typeof(p_args->'q') is distinct from 'string' or length(p_args->>'q')>100
  or jsonb_typeof(p_args->'page') is distinct from 'number' or p_args->>'page' !~ '^[1-9][0-9]{0,4}$'
  or jsonb_typeof(p_args->'members') is distinct from 'array' then
  raise exception 'Consulta da equipe inválida.' using errcode='22023';
 end if;
 if jsonb_array_length(p_args->'members') not between 1 and 768
  or not (p_args->'members' @> jsonb_build_array(jsonb_build_object('kind','corporate','subject',p_viewer)))
  or exists(select 1 from jsonb_array_elements(p_args->'members') member
   where member is distinct from jsonb_build_object('kind',member->'kind','subject',member->'subject')
     or jsonb_typeof(member->'kind') is distinct from 'string' or member->>'kind' not in('corporate','operator')
     or jsonb_typeof(member->'subject') is distinct from 'string'
     or (member->>'subject') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
  raise exception 'Vínculos da equipe inválidos.' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_array_elements(p_args->'members') member group by member having count(*)>1) then
  raise exception 'Vínculos da equipe repetidos.' using errcode='22023';
 end if;
 page:=(p_args->>'page')::integer;
 term:=lower(p_args->>'q');
 with members as materialized (
  select m.kind,m.subject from jsonb_to_recordset(p_args->'members') as m(kind text,subject uuid)
 ), identities as (
  select b.rm_user_id id,b.auth_user_id from members m join rm_private.sso_identity_bindings b
   on m.kind='corporate' and b.subject=m.subject and b.enabled
   and b.issuer='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
  union all
  select m.subject,null::uuid from members m where m.kind='operator'
 ), filtered as materialized (
  select u.id,u.nome,u.matricula,u.cargo,u.perfil,u.status from public.rm_users u where u.status='ativo'
   and exists(select 1 from identities i where i.id=u.id and (i.auth_user_id is null or i.auth_user_id=u.auth_user_id))
   and (term='' or strpos(lower(coalesce(u.nome,'')),term)>0 or strpos(lower(coalesce(u.matricula,'')),term)>0)
 ), selected as (
  select * from filtered order by nome,id limit 50 offset (page-1)*50
 )
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(s) order by nome,id) from selected s),'[]'),
  'total',(select count(*) from filtered),'page',page,'pageSize',50) into result;
 return result;
end;
$team$;
revoke all on function rm_private.workshop_team_read_v1(jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot','cell_availability','cell_queue','planning_load',
  'execution_snapshot','engineering_matrix','engineering_entry','engineering_choices','photo_title_list','photo_title_entry','workshop_team'));

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 tail constant text:='''photo_title_entry'')';
 argument_limit constant text:='octet_length(p_args::text)>4096';
 gate constant text:='from rm_private.workshop_read_permits where read_id=p_read_id for update;';
 dispatch constant text:='  when ''execution_snapshot'' then rm_private.workshop_execution_snapshot_v1(p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,tail),1) is distinct from 2
  or array_length(string_to_array(issuer,argument_limit),1) is distinct from 2
  or array_length(string_to_array(reader,gate),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then raise exception 'Unexpected workshop team contract';end if;
 issuer:=replace(issuer,tail,'''photo_title_entry'',''workshop_team'')');
 execute replace(issuer,argument_limit,'octet_length(p_args::text)>(case when p_resource=''workshop_team'' then 65536 else 4096 end)');
 execute replace(reader,dispatch,dispatch||chr(10)||
  '  when ''workshop_team'' then rm_private.workshop_team_read_v1(p_args,binding.subject)');
end;
$extend$;
notify pgrst,'reload schema';
commit;

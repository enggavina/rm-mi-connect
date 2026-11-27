begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_display_form_v1(p_id uuid,p_office uuid)
returns jsonb language sql stable set search_path='' as $$
 select to_jsonb(f) || case when v.version is null then '{}'::jsonb else
  jsonb_build_object('versao_modelo',v.version,'titulo_modelo',f.titulo,'titulo',coalesce(f.titulo,'null')||' · v'||v.version) end
 from (select id,titulo,title,descricao,tipo,ativo,usa_aprovacao,updated_at from public.rm_forms where id=p_id) f
 left join public.rm_form_template_versions v on v.form_id=f.id
 where rm_private.workshop_read_visible_v1('form_model',f.id,p_office)
$$;

create function rm_private.workshop_detail_people_v1(p_ids uuid[],p_photos boolean)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(u)||case when p_photos then jsonb_build_object('foto_url',p.foto_url) else '{}'::jsonb end
  order by u.id),'[]')
 from (select id,nome,matricula,cargo,perfil,status from public.rm_users where id=any(p_ids)) u
 join public.rm_users p using(id)
$$;

create function rm_private.workshop_project_detail_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare
 flags constant text[]:=array['planning','forms','photos','history','documents','equipment','dossier','edit','selected_only','selected_first'];
 base jsonb;
 result jsonb;
 pid uuid;
 photo_page int;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object'
  or (p_args-flags-array['id','photo_page'])<>'{}' or jsonb_typeof(p_args->'id') is distinct from 'string'
  or exists(select 1 from unnest(flags) key where jsonb_typeof(p_args->key) is distinct from 'boolean')
  or jsonb_typeof(p_args->'photo_page') is distinct from 'number' or p_args->>'photo_page' !~ '^[1-9][0-9]{0,4}$' then
  raise exception 'Consulta de projeto inválida.' using errcode='22023';
 end if;
 pid:=(p_args->>'id')::uuid;
 photo_page:=(p_args->>'photo_page')::int;
 base:=rm_private.workshop_project_read_data_v1('project_entry',jsonb_build_object('id',pid,'documents',p_args->'documents',
  'cells',p_args->'planning'='true'::jsonb or p_args->'history'='true'::jsonb),p_office);
 if base is null then return null;end if;

 with project_allocations as materialized (
  select id,projeto_id,celula_id,numero_projeto,cliente_nome_export,tipo_equipamento_nome_export,status,bloqueada,motivo_bloqueio,
   motivo_atraso,observacao,visibilidade,retirada,prioridade,indice,posicao,horas_previstas,horas_realizadas,data_inicio,data_limite,
   data_fim_real,responsavel_id,array(select f from unnest(a.forms_ids) with ordinality x(f,seq)
    where rm_private.workshop_read_visible_v1('form_model',f,p_office) order by seq) forms_ids,updated_at
  from public.rm_celulas_projeto a where a.projeto_id=pid and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)
   and (p_args->'planning'='true'::jsonb or p_args->'edit'='true'::jsonb)
  order by posicao,id limit 20000
 ), records as materialized (
  select id,projeto_id,numero_projeto_rm,celula_id,form_id,codigo,codigo_text,descricao,status,preenchido,revisado,parecer,data_conclusao,
   data_revisao,created_by_user_id,identidade_user_id,responsavel_user_id,avaliador_user_id,aprovadores_ids,user_revisao_id,created_at,updated_at
  from public.rm_registros_formulario r where r.projeto_id=pid and p_args->'forms'='true'::jsonb
   and (r.celula_id is null or rm_private.workshop_cell_owned_v1(r.celula_id,p_office))
   and rm_private.workshop_read_visible_v1('form_model',r.form_id,p_office)
  order by created_at,id limit 20000
 ), forms as materialized (
  select rm_private.workshop_display_form_v1(id,p_office) dto from (
   select unnest(forms_ids) id from project_allocations where p_args->'planning'='true'::jsonb
   union select form_id from records) ids where p_args->'forms'='true'::jsonb
 ), stages as materialized (
  select s.id,s.projeto_id,s.celula_projeto_id,s.celula_origem_id,s.celula_destino_id,s.status,s.status_cel_proj,
   s.aprovador_id,s.aprovado_por_id,s.data_aprovacao,s.updated_at
  from public.rm_aprovacoes_etapas s where s.projeto_id=pid and p_args->'history'='true'::jsonb
   and rm_private.workshop_cell_owned_v1(s.celula_origem_id,p_office)
   and (s.celula_destino_id is null or rm_private.workshop_cell_owned_v1(s.celula_destino_id,p_office))
   and (s.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a where a.id=s.celula_projeto_id
    and a.projeto_id=pid and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)))
  order by s.id limit 20000
 ), comments as materialized (
  select id,projeto_id,celula_id,cadastrado_por_id,evento,created_at
  from public.rm_comentarios c where c.projeto_id=pid and p_args->'history'='true'::jsonb and p_args->'dossier'='true'::jsonb
   and (c.celula_id is null or rm_private.workshop_cell_owned_v1(c.celula_id,p_office))
  order by id limit 20000
 ), documents as materialized (
  select id,projeto_id,registro_formulario_id,nome,tipo_documento,arquivo_url,ordem_compilacao,incluir_no_compilado,created_at,updated_at
  from public.rm_documentos d where d.projeto_id=pid and p_args->'documents'='true'::jsonb and p_args->'dossier'='true'::jsonb
   and (d.registro_formulario_id is null or exists(select 1 from public.rm_registros_formulario r where r.id=d.registro_formulario_id
    and r.projeto_id=pid and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office)))
  order by ordem_compilacao,id limit 20000
 ), attachments as materialized (
  select id,projeto_id,nome,descricao,arquivo_url,tipo_arquivo,status,data_vencimento,created_by,visivel_cliente,created_at,updated_at
  from public.rm_docs where projeto_id=pid and p_args->'documents'='true'::jsonb and p_args->'dossier'='true'::jsonb
  order by nome,id limit 20000
 ), gallery as materialized (
  select f.id,f.projeto_id,f.celula_id,f.celula_projeto_id,f.categoria_foto,f.tipo_recebimento,f.identificador_foto_key,
   f.titulo,f.descricao,f.legenda,f.numero,f.selecao_relatorio,f.created_at,f.updated_at
  from public.rm_fotos f where f.projeto_id=pid and p_args->'photos'='true'::jsonb and not f.lixeira
   and nullif(f.foto_url,'') is not null and (p_args->'selected_only'='false'::jsonb or f.selecao_relatorio)
   and (f.celula_id is null or rm_private.workshop_cell_owned_v1(f.celula_id,p_office))
   and (f.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a where a.id=f.celula_projeto_id
    and a.projeto_id=pid and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)))
 ), gallery_page as (
  select * from gallery order by case when p_args->'selected_first'='true'::jsonb then selecao_relatorio end desc,numero,id
  offset (photo_page-1)*24 limit 24
 ), people as (
  select unnest(array[identidade_user_id,created_by_user_id,responsavel_user_id,avaliador_user_id,user_revisao_id]) id from records
  union select cadastrado_por_id from comments union select created_by from attachments
  union select unnest(array[aprovador_id,aprovado_por_id]) from stages
  union select responsavel_id from project_allocations where p_args->'planning'='true'::jsonb
 ), equipment as (
  select id,projeto_id,tipo_equipamento_id,descricao,placa_motor,fabricante,modelo,numero_serie,potencia,tensao_estator,corrente_estator,
   rotacao,frequencia,classe_isolamento,grau_ip,forma,regime,peso,ligacao,certificado,norma,updated_at
  from public.rm_equipamentos e where e.id=(base->'project'->>'equipamento_id')::uuid and e.projeto_id=pid and p_args->'equipment'='true'::jsonb
 )
 select base||jsonb_build_object(
  'equipment',(select to_jsonb(e) from equipment e),
  'allocations',coalesce((select jsonb_agg(to_jsonb(a) order by posicao,id) from project_allocations a where p_args->'planning'='true'::jsonb),'[]'),
  'hasAllocations',exists(select 1 from project_allocations),
  'records',coalesce((select jsonb_agg(to_jsonb(r) order by created_at,id) from records r),'[]'),
  'forms',coalesce((select jsonb_agg(dto order by dto->>'id') from forms where dto is not null),'[]'),
  'stages',coalesce((select jsonb_agg(to_jsonb(s) order by id) from stages s),'[]'),
  'comments',coalesce((select jsonb_agg(to_jsonb(c) order by id) from comments c),'[]'),
  'documents',coalesce((select jsonb_agg(to_jsonb(d) order by ordem_compilacao,id) from documents d),'[]'),
  'attachments',coalesce((select jsonb_agg(to_jsonb(a) order by nome,id) from attachments a),'[]'),
  'users',rm_private.workshop_detail_people_v1(array(select id from people where id is not null),p_args->'photos'='true'::jsonb),
  'photos',coalesce((select jsonb_agg(to_jsonb(g) order by case when p_args->'selected_first'='true'::jsonb then selecao_relatorio end desc,numero,id) from gallery_page g),'[]'),
  'photoTotal',(select count(*) from gallery),'photoPage',photo_page,'photoPageSize',24,
  'complete',greatest((select count(*) from project_allocations),(select count(*) from records),(select count(*) from stages),
   (select count(*) from comments),(select count(*) from documents),(select count(*) from attachments))<20000
 ) into result;
 return result;
exception when invalid_text_representation then
 raise exception 'Consulta de projeto inválida.' using errcode='22023';
end
$$;

create function rm_private.workshop_form_record_detail_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare
 flags constant text[]:=array['projects','documents','photos'];
 result jsonb;
 rid uuid;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' or (p_args-flags-'id')<>'{}'
  or jsonb_typeof(p_args->'id') is distinct from 'string'
  or exists(select 1 from unnest(flags) key where jsonb_typeof(p_args->key) is distinct from 'boolean')
  or (p_args->'documents'='true'::jsonb and p_args->'projects'='false'::jsonb) then
  raise exception 'Consulta de formulário inválida.' using errcode='22023';
 end if;
 rid:=(p_args->>'id')::uuid;
 with record as materialized (
  select id,projeto_id,numero_projeto_rm,celula_id,form_id,codigo,codigo_text,descricao,status,preenchido,revisado,parecer,
   data_conclusao,data_revisao,created_by_user_id,identidade_user_id,responsavel_user_id,avaliador_user_id,aprovadores_ids,
   user_revisao_id,created_at,updated_at
  from public.rm_registros_formulario r where r.id=rid
   and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office)
   and rm_private.workshop_read_visible_v1('form_model',r.form_id,p_office)
 ), questions as materialized (
  select q.id,q.form_id,q.indice,q.enunciado,q.subtitulo,q.tag,q.tipo,q.subtipo,q.dimensoes,q.obrigatorio
  from public.rm_questoes q join record r on q.form_id=r.form_id order by q.indice,q.id limit 20000
 ), items as materialized (
  select i.id,i.form_id,i.questao_id,i.indice,i.descricao
  from public.rm_itens_questoes i join record r on i.form_id=r.form_id
  where i.questao_id is null or exists(select 1 from questions q where q.id=i.questao_id)
  order by i.id limit 20000
 ), answers as materialized (
  select a.id,a.registro_formulario_id,a.questao_id,a.titulo_form,a.indice,a.enunciado,a.tag,a.tipo,a.dimensoes,
   a.resposta,a.itens,a.itens_questoes_ids,a.date_inicio,a.data_fim,a.hora,a.revisar,a.updated_at
  from public.rm_respostas a join record r on r.id=a.registro_formulario_id order by a.indice,a.id limit 20000
 )
 select jsonb_build_object('record',to_jsonb(r),'form',rm_private.workshop_display_form_v1(r.form_id,p_office),
  'project',case when p_args->'projects'='true'::jsonb then rm_private.workshop_project_read_data_v1('project_entry',
   jsonb_build_object('id',r.projeto_id,'documents',p_args->'documents','cells',false),p_office)->'project' end,
  'questions',coalesce((select jsonb_agg(to_jsonb(q) order by indice,id) from questions q),'[]'),
  'items',coalesce((select jsonb_agg(to_jsonb(i) order by id) from items i),'[]'),
  'answers',coalesce((select jsonb_agg(to_jsonb(a)||case when p_args->'photos'='true'::jsonb then jsonb_build_object(
    'fotos_urls',p.fotos_urls,'assinatura_url',p.assinatura_url) else '{}'::jsonb end order by a.indice,a.id)
    from answers a join public.rm_respostas p using(id)),'[]'),
  'users',rm_private.workshop_detail_people_v1(
   array[r.identidade_user_id,r.created_by_user_id,r.responsavel_user_id,r.avaliador_user_id,r.user_revisao_id],p_args->'photos'='true'::jsonb),
  'complete',greatest((select count(*) from questions),(select count(*) from items),(select count(*) from answers))<20000
 ) into result from record r;
 return result;
exception when invalid_text_representation then
 raise exception 'Consulta de formulário inválida.' using errcode='22023';
end
$$;

revoke all on function rm_private.workshop_display_form_v1(uuid,uuid),rm_private.workshop_detail_people_v1(uuid[],boolean),
 rm_private.workshop_project_detail_v1(jsonb,uuid),rm_private.workshop_form_record_detail_v1(jsonb,uuid) from public,anon,authenticated,service_role;

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 allowed constant text:='''project_route'',''project_route_cell'',''operational_photos'')';
 dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 constraint_definition text;
begin
 if array_length(string_to_array(issuer,allowed),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop detail permit contract';
 end if;
 select pg_get_constraintdef(oid) into strict constraint_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(constraint_definition from 8 for char_length(constraint_definition)-8)||') or resource in (''project_detail'',''form_record_detail''))';
 execute replace(issuer,allowed,left(allowed,-1)||',''project_detail'',''form_record_detail'')');
 execute replace(reader,dispatch,$query$  when 'project_detail' then rm_private.workshop_project_detail_v1(p_args,permit.workshop_id)
  when 'form_record_detail' then rm_private.workshop_form_record_detail_v1(p_args,permit.workshop_id)
$query$||dispatch);
end
$extend$;

notify pgrst,'reload schema';
commit;

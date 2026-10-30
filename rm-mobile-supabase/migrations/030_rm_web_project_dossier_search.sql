-- Read-only, project-scoped dossier search. Existing rows, policies, receipts,
-- Storage and offline contracts remain unchanged.
begin;

create function rm_private.project_dossier_filters_v1(p_filters jsonb,p_documents boolean)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare allowed text[]; search text:=''; author_id uuid; cell_id uuid;
 from_date date; to_date date; page_no integer:=1; source text:='all'; status text:='all'; key text;
begin
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or p_documents is null then
  raise exception 'Filtros do dossiê inválidos.' using errcode='22023'; end if;
 allowed:=case when p_documents then array['search','author_id','from_date','to_date','page','source','status']
  else array['search','author_id','cell_id','from_date','to_date','page'] end;
 if exists(select 1 from jsonb_object_keys(p_filters) k where not k=any(allowed)) then
  raise exception 'Filtros do dossiê inválidos.' using errcode='22023'; end if;
 if p_filters ? 'search' then
  if jsonb_typeof(p_filters->'search') is distinct from 'string' or length(p_filters->>'search')>200 then
   raise exception 'Busca do dossiê inválida.' using errcode='22023'; end if;
  search:=btrim(p_filters->>'search');
 end if;
 foreach key in array array['author_id','cell_id'] loop
  if p_filters ? key and jsonb_typeof(p_filters->key)<>'null' then
   if jsonb_typeof(p_filters->key)<>'string' then raise exception 'Identidade de filtro inválida.' using errcode='22023'; end if;
   if key='author_id' then author_id:=(p_filters->>key)::uuid; else cell_id:=(p_filters->>key)::uuid; end if;
  end if;
 end loop;
 foreach key in array array['from_date','to_date'] loop
  if p_filters ? key and jsonb_typeof(p_filters->key)<>'null' then
   if jsonb_typeof(p_filters->key)<>'string' or p_filters->>key !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Período do dossiê inválido.' using errcode='22023'; end if;
   if key='from_date' then from_date:=(p_filters->>key)::date; else to_date:=(p_filters->>key)::date; end if;
  end if;
 end loop;
 if from_date>to_date then raise exception 'Período do dossiê inválido.' using errcode='22023'; end if;
 if p_filters ? 'page' then
  if jsonb_typeof(p_filters->'page') is distinct from 'number' or p_filters->>'page' !~ '^[1-9][0-9]*$'
   or (p_filters->>'page')::numeric>100000 then raise exception 'Página do dossiê inválida.' using errcode='22023'; end if;
  page_no:=(p_filters->>'page')::integer;
 end if;
 if p_documents then
  if p_filters ? 'source' then
   if jsonb_typeof(p_filters->'source') is distinct from 'string' or p_filters->>'source' not in('all','documents','docs') then
    raise exception 'Origem documental inválida.' using errcode='22023'; end if;
   source:=p_filters->>'source';
  end if;
  if p_filters ? 'status' then
   if jsonb_typeof(p_filters->'status') is distinct from 'string' or p_filters->>'status' not in('all','No prazo','Vencido','other') then
    raise exception 'Situação documental inválida.' using errcode='22023'; end if;
   status:=p_filters->>'status';
  end if;
 end if;
 return jsonb_build_object('search',search,'author_id',author_id,'from_date',from_date,'to_date',to_date,'page',page_no)
  ||case when p_documents then jsonb_build_object('source',source,'status',status) else jsonb_build_object('cell_id',cell_id) end;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception 'Filtros do dossiê inválidos.' using errcode='22023';
end $$;
revoke all on function rm_private.project_dossier_filters_v1(jsonb,boolean) from public,anon,service_role;
grant execute on function rm_private.project_dossier_filters_v1(jsonb,boolean) to authenticated;

create function public.rm_web_project_comments_v1(p_project_id uuid,p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare filters jsonb; result jsonb;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna do EM.' using errcode='42501'; end if;
 if p_project_id is null then raise exception 'Projeto inválido.' using errcode='22023'; end if;
 filters:=rm_private.project_dossier_filters_v1(p_filters,false);
 if not exists(select 1 from public.rm_projetos p where p.id=p_project_id) then return null; end if;
 with project_rows as materialized (
  select c.id,c.projeto_id,c.celula_id,c.cadastrado_por_id,c.evento,c.created_at,
   u.nome author_name,u.matricula author_registration,cell.nome cell_name
  from public.rm_comentarios c left join public.rm_users u on u.id=c.cadastrado_por_id
  left join public.rm_celulas cell on cell.id=c.celula_id where c.projeto_id=p_project_id
 ), filtered as materialized (
  select r.* from project_rows r where
   (filters->>'search'='' or strpos(lower(r.evento),lower(filters->>'search'))>0)
   and (filters->>'author_id' is null or r.cadastrado_por_id=(filters->>'author_id')::uuid)
   and (filters->>'cell_id' is null or r.celula_id=(filters->>'cell_id')::uuid)
   and (filters->>'from_date' is null or r.created_at>=((filters->>'from_date')::date::timestamp at time zone 'America/Sao_Paulo'))
   and (filters->>'to_date' is null or r.created_at<(((filters->>'to_date')::date+1)::timestamp at time zone 'America/Sao_Paulo'))
 ), counts as (
  select (select count(*) from filtered) total,(select count(*) from project_rows) unfiltered_total
 ), metadata as (
  select total,unfiltered_total,least((filters->>'page')::integer,greatest(1,ceil(total::numeric/25)::integer)) page from counts
 ), items as (
  select * from filtered order by created_at desc,id desc limit 25 offset (((select page from metadata)-1)*25)
 ) select jsonb_build_object('project_id',p_project_id,'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc,i.id desc) from items i),'[]'::jsonb),
  'total',m.total,'unfiltered_total',m.unfiltered_total,'page',m.page,'page_size',25,'filters',filters-'page',
  'facets',jsonb_build_object(
   'authors',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'nome',x.nome,'matricula',x.matricula) order by x.nome nulls last,x.id)
    from(select distinct r.cadastrado_por_id id,r.author_name nome,r.author_registration matricula from project_rows r where r.cadastrado_por_id is not null) x),'[]'::jsonb),
   'cells',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'nome',x.nome) order by x.nome nulls last,x.id)
    from(select distinct r.celula_id id,r.cell_name nome from project_rows r where r.celula_id is not null) x),'[]'::jsonb))) into result from metadata m;
 return result;
end $$;

create function public.rm_web_project_documents_v1(p_project_id uuid,p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare filters jsonb; result jsonb;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna do EM.' using errcode='42501'; end if;
 if p_project_id is null then raise exception 'Projeto inválido.' using errcode='22023'; end if;
 filters:=rm_private.project_dossier_filters_v1(p_filters,true);
 if not exists(select 1 from public.rm_projetos p where p.id=p_project_id) then return null; end if;
 with project_rows as materialized (
  select d.id,'documents'::text source,d.projeto_id,d.nome,null::text descricao,null::text tipo_arquivo,d.tipo_documento,
   null::text status,null::timestamptz data_vencimento,d.created_by,u.nome author_name,u.matricula author_registration,d.created_at,
   nullif(btrim(d.arquivo_url),'') is not null has_file,null::boolean visivel_cliente
  from public.rm_documentos d left join public.rm_users u on u.id=d.created_by where d.projeto_id=p_project_id
  union all
  select d.id,'docs',d.projeto_id,d.nome,d.descricao,d.tipo_arquivo,null::text tipo_documento,d.status,d.data_vencimento,d.created_by,
   u.nome,u.matricula,d.created_at,nullif(btrim(d.arquivo_url),'') is not null,d.visivel_cliente
  from public.rm_docs d left join public.rm_users u on u.id=d.created_by where d.projeto_id=p_project_id
 ), filtered as materialized (
  select r.* from project_rows r where
   (filters->>'search'='' or strpos(lower(concat_ws(' ',r.nome,r.descricao)),lower(filters->>'search'))>0)
   and (filters->>'source'='all' or r.source=filters->>'source')
   and (filters->>'status'='all' or r.source='docs' and (
    r.status=filters->>'status' or filters->>'status'='other' and (r.status is null or r.status not in('No prazo','Vencido'))))
   and (filters->>'author_id' is null or r.created_by=(filters->>'author_id')::uuid)
   and (filters->>'from_date' is null or r.created_at>=((filters->>'from_date')::date::timestamp at time zone 'America/Sao_Paulo'))
   and (filters->>'to_date' is null or r.created_at<(((filters->>'to_date')::date+1)::timestamp at time zone 'America/Sao_Paulo'))
 ), counts as (
  select (select count(*) from filtered) total,(select count(*) from project_rows) unfiltered_total
 ), metadata as (
  select total,unfiltered_total,least((filters->>'page')::integer,greatest(1,ceil(total::numeric/25)::integer)) page from counts
 ), items as (
  select * from filtered order by created_at desc,id desc,source limit 25 offset (((select page from metadata)-1)*25)
 ) select jsonb_build_object('project_id',p_project_id,'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc,i.id desc,i.source) from items i),'[]'::jsonb),
  'total',m.total,'unfiltered_total',m.unfiltered_total,'page',m.page,'page_size',25,'filters',filters-'page',
  'facets',jsonb_build_object(
   'authors',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'nome',x.nome,'matricula',x.matricula) order by x.nome nulls last,x.id)
    from(select distinct r.created_by id,r.author_name nome,r.author_registration matricula from project_rows r where r.created_by is not null) x),'[]'::jsonb),
   'statuses',coalesce((select jsonb_agg(jsonb_build_object('value',x.value,'label',case x.value when 'other' then 'Outras situações' else x.value end)
    order by case x.value when 'No prazo' then 1 when 'Vencido' then 2 else 3 end)
    from(select distinct case when r.status in('No prazo','Vencido') then r.status else 'other' end value from project_rows r where r.source='docs') x),'[]'::jsonb))) into result from metadata m;
 return result;
end $$;

revoke all on function public.rm_web_project_comments_v1(uuid,jsonb),public.rm_web_project_documents_v1(uuid,jsonb) from public,anon,service_role;
grant execute on function public.rm_web_project_comments_v1(uuid,jsonb),public.rm_web_project_documents_v1(uuid,jsonb) to authenticated;
create index rm_comments_project_recent_v1 on public.rm_comentarios(projeto_id,created_at desc,id desc);
create index rm_documents_project_recent_v1 on public.rm_documentos(projeto_id,created_at desc,id desc);
create index rm_attachments_project_recent_v1 on public.rm_docs(projeto_id,created_at desc,id desc);
notify pgrst,'reload schema';
commit;

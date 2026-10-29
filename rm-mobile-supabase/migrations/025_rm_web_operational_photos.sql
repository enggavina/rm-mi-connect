-- Operational exceptions to a project's mandatory photos; no existing rows change.
-- Keep retired slot IDs so delayed offline uploads can be recovered explicitly.
begin;

create function public.rm_web_operational_photos_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_titles boolean default false)
returns jsonb language sql stable security invoker set search_path='' as $$
 with context as materialized (
  select p.id project_id,p.numero,p.status_pcp,p.data_real_de_entrega,p.updated_at project_updated_at,
   p.data_real_de_entrega is not null or coalesce(p.status_pcp in ('cancelado','finalizando_para_faturar'),false) closed,
   a.id allocation_id,a.celula_id,a.status,a.updated_at allocation_updated_at,c.nome celula_nome,c.updated_at cell_updated_at
  from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id
   join public.rm_celulas c on c.id=a.celula_id where p.id=p_project_id and a.id=p_allocation_id
 ), photos as materialized (
  select f.*,nullif(btrim(f.foto_url),'') is not null or exists(
    select 1 from unnest(f.fotos_arquivos_urls) x where nullif(btrim(x),'') is not null) captured
  from public.rm_fotos f cross join context c where f.projeto_id=c.project_id and f.celula_id=c.celula_id
   and (f.celula_projeto_id=c.allocation_id or f.celula_projeto_id is null)
 ), titles as materialized (
  select t.* from public.rm_cadastro_fotos t cross join context c where nullif(btrim(regexp_replace(t.titulo,'[[:space:]]+',' ','g')),'') is not null and
   (nullif(btrim(regexp_replace(t.celula_nome,'[[:space:]]+',' ','g')),'') is null or (lower(btrim(regexp_replace(t.celula_nome,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(c.celula_nome,'[[:space:]]+',' ','g')))
    and (select count(*) from public.rm_celulas x where lower(btrim(regexp_replace(x.nome,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(t.celula_nome,'[[:space:]]+',' ','g'))))=1))
 ), photo_rows as (
  select f.*,exists(select 1 from photos x where x.id<>f.id and not x.lixeira and x.categoria_foto='obrigat_ria' and
   ((f.cadastro_foto_id is not null and x.cadastro_foto_id=f.cadastro_foto_id) or
    (nullif(btrim(regexp_replace(f.titulo,'[[:space:]]+',' ','g')),'') is not null and lower(btrim(regexp_replace(x.titulo,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(f.titulo,'[[:space:]]+',' ','g')))))) active_duplicate
  from photos f
 ), photo_dtos as (
  select f.id,f.numero,jsonb_build_object('id',f.id,'projeto_id',f.projeto_id,'celula_id',f.celula_id,
   'celula_projeto_id',f.celula_projeto_id,'cadastro_foto_id',f.cadastro_foto_id,'titulo',f.titulo,
   'categoria_foto',f.categoria_foto,'tag',f.tag,'numero',f.numero,'updated_at',f.updated_at,
   'captured',f.captured,'selected_for_report',f.selecao_relatorio,'retired',f.lixeira,
   'can_edit_tag',not c.closed and not coalesce(c.status in ('finalizado','n_a'),false) and coalesce(f.categoria_foto='obrigat_ria',false) and not f.lixeira,
   'can_retire',not c.closed and not coalesce(c.status in ('finalizado','n_a'),false) and coalesce(f.categoria_foto='obrigat_ria',false)
     and not f.lixeira and not f.captured and not f.selecao_relatorio,
   'can_restore',not c.closed and not coalesce(c.status in ('finalizado','n_a'),false) and coalesce(f.categoria_foto='obrigat_ria',false)
     and f.lixeira and not f.captured and not f.selecao_relatorio and not f.active_duplicate,
   'action_reason',case when c.closed or c.status in ('finalizado','n_a') then 'Projeto ou célula encerrados: somente consulta.'
     when f.categoria_foto is null then 'Classificação legada: somente consulta.'
     when f.categoria_foto is distinct from 'obrigat_ria' then 'Fotos complementares são mantidas para consulta.'
     when f.captured then 'A foto possui arquivo registrado e não pode ser retirada.'
     when f.selecao_relatorio then 'A foto está selecionada para relatório e não pode ser retirada.'
     when f.lixeira and f.active_duplicate then 'Outro item ativo já possui este título ou cadastro.'
     when f.lixeira then 'Item retirado. Restaure o mesmo item para recuperar uma captura offline pendente.' else null end) dto
  from photo_rows f cross join context c
 ), title_dtos as (
  select t.id,t.numero,t.titulo,jsonb_build_object('id',t.id,'titulo',t.titulo,'numero',t.numero,'updated_at',t.updated_at,
   'assigned',exists(select 1 from photos f where f.categoria_foto='obrigat_ria' and
    (f.cadastro_foto_id=t.id or lower(btrim(regexp_replace(f.titulo,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(t.titulo,'[[:space:]]+',' ','g'))))),
   'retired_photo_id',(select f.id from photos f where f.categoria_foto='obrigat_ria' and f.lixeira and
    (f.cadastro_foto_id=t.id or lower(btrim(regexp_replace(f.titulo,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(t.titulo,'[[:space:]]+',' ','g')))) order by f.id limit 1)) dto
  from titles t
 ), aggregate as (
  select (select count(*) from photos) total,(select count(*) from titles) titles_total,
   coalesce((select jsonb_agg(dto order by numero nulls last,id) from photo_dtos),'[]'::jsonb) photo_items,
   coalesce((select jsonb_agg(dto order by numero nulls last,titulo,id) from title_dtos),'[]'::jsonb) title_items,
   coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from photos),'[]'::jsonb) photo_revisions,
   coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from titles),'[]'::jsonb) title_revisions
 )
 select jsonb_build_object('project',jsonb_build_object('id',c.project_id,'numero',c.numero,'status_pcp',c.status_pcp,
   'data_real_de_entrega',c.data_real_de_entrega,'updated_at',c.project_updated_at,'closed',c.closed),
  'allocation',jsonb_build_object('id',c.allocation_id,'projeto_id',c.project_id,'celula_id',c.celula_id,
   'celula_nome',c.celula_nome,'status',c.status,'updated_at',c.allocation_updated_at),
  'photos',case when a.total<=2000 then a.photo_items else '[]'::jsonb end,'total',a.total,'complete',a.total<=2000,
  'titles',case when p_include_titles and a.titles_total<=1000 and exists(select 1 from public.rm_users u
    where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in ('administrador','padr_o'))
    then a.title_items else '[]'::jsonb end,'titles_total',a.titles_total,'titles_complete',a.titles_total<=1000,
  'photos_version',encode(sha256(convert_to(jsonb_build_object('project',c.project_id,'project_version',c.project_updated_at,
   'allocation',c.allocation_id,'allocation_version',c.allocation_updated_at,'cell_version',c.cell_updated_at,
   'photos',a.photo_revisions,'titles',a.title_revisions)::text,'UTF8')),'hex')) from context c cross join aggregate a;
$$;
revoke all on function public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_project_route_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 project public.rm_projetos%rowtype; allocation public.rm_celulas_projeto%rowtype; photo public.rm_fotos%rowtype;
 title public.rm_cadastro_fotos%rowtype; snapshot jsonb; before_record jsonb; result jsonb; action text;
 project_id uuid; allocation_id uuid; photo_id uuid; expected_project timestamptz; expected_allocation timestamptz;
 expected_photo timestamptz; allowed text[]; item jsonb; item_id uuid; title_id uuid; changed uuid[]:='{}';
 catalog_ids uuid[]; item_ids uuid[]; tag_value text; next_number bigint;
begin
 if p_operation is distinct from 'manage_operational_photos' then
  -- Preserve exact historical receipts, but stop writing the retired quantity field.
  if p_operation='save_engineering' and jsonb_typeof(p_payload->'changes')='object' and p_payload->'changes'?'numero_fotos' then
   perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
   if not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id) then
    raise exception 'Quantidade prevista de fotos foi removida. Configure os títulos obrigatórios.' using errcode='22023'; end if;
  end if;
  return rm_private.web_mutate_project_route_core_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in ('administrador','padr_o'),false) then
  raise exception 'Operação restrita à administração/planejamento.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 action:=p_payload->>'action';
 allowed:=array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','expected_photos_version'];
 if action='add' then allowed:=allowed||array['items'];
 elsif action='tag' then allowed:=allowed||array['foto_id','expected_foto_updated_at','tag'];
 elsif action in ('retire','restore') then allowed:=allowed||array['foto_id','expected_foto_updated_at'];
 else raise exception 'Ação de foto inválida.' using errcode='22023'; end if;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or exists(select 1 from unnest(array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','expected_photos_version']) k
    where jsonb_typeof(p_payload->k) is distinct from 'string')
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_photos_version' !~ '^[0-9a-f]{64}$' then raise exception 'Contexto ou versão inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; allocation_id:=(p_payload->>'celula_projeto_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz;
 expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
 if not isfinite(expected_project) or not isfinite(expected_allocation) then raise exception 'Versão inválida.' using errcode='22023'; end if;
 if action='add' then
  if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items') not between 1 and 100 then
   raise exception 'Selecione entre 1 e 100 títulos.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(p_payload->'items') loop
   if jsonb_typeof(item)<>'object' or not item ?& array['id','cadastro_foto_id']
    or exists(select 1 from jsonb_object_keys(item) k where k not in ('id','cadastro_foto_id'))
    or jsonb_typeof(item->'id') is distinct from 'string' or jsonb_typeof(item->'cadastro_foto_id') is distinct from 'string' then
    raise exception 'Título de foto inválido.' using errcode='22023'; end if;
   item_id:=(item->>'id')::uuid; title_id:=(item->>'cadastro_foto_id')::uuid;
   item_ids:=array_append(item_ids,item_id); catalog_ids:=array_append(catalog_ids,title_id);
  end loop;
  if cardinality(item_ids)<>(select count(distinct id) from unnest(item_ids) id)
   or cardinality(catalog_ids)<>(select count(distinct id) from unnest(catalog_ids) id) then
   raise exception 'Título ou identificador repetido.' using errcode='22023'; end if;
 else
  if jsonb_typeof(p_payload->'foto_id') is distinct from 'string' or jsonb_typeof(p_payload->'expected_foto_updated_at') is distinct from 'string'
   or p_payload->>'expected_foto_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
   raise exception 'Foto ou versão inválida.' using errcode='22023'; end if;
  photo_id:=(p_payload->>'foto_id')::uuid; expected_photo:=(p_payload->>'expected_foto_updated_at')::timestamptz;
  if not isfinite(expected_photo) then raise exception 'Versão inválida.' using errcode='22023'; end if;
  if action='tag' then
   if jsonb_typeof(p_payload->'tag') not in ('string','null') or length(p_payload->>'tag')>2000 then raise exception 'Tag inválida.' using errcode='22023'; end if;
   tag_value:=p_payload->>'tag';
  end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 select * into allocation from public.rm_celulas_projeto where id=allocation_id and projeto_id=project_id for update;
 if not found then raise exception 'Célula não pertence ao projeto.' using errcode='P0002'; end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('rm.web.catalogs',17));
 perform 1 from public.rm_celulas where id=allocation.celula_id for share;
 if action='add' then perform 1 from public.rm_cadastro_fotos where id=any(catalog_ids) order by id for share; end if;
 perform 1 from public.rm_fotos where projeto_id=project_id and celula_id=allocation.celula_id
  and (celula_projeto_id=allocation.id or celula_projeto_id is null) order by id for update;
 snapshot:=public.rm_web_operational_photos_snapshot_v1(project_id,allocation_id,true);
 if project.updated_at<>expected_project or allocation.updated_at<>expected_allocation
  or snapshot->>'photos_version' is distinct from p_payload->>'expected_photos_version' then
  raise exception 'Projeto, célula ou fotos alterados. Recarregue antes de salvar.' using errcode='PT409'; end if;
 if not (snapshot->>'complete')::boolean or (action='add' and not (snapshot->>'titles_complete')::boolean) then
  raise exception 'O conjunto excede o limite de edição completa.' using errcode='22023'; end if;
 if (snapshot->'project'->>'closed')::boolean or allocation.status in ('finalizado','n_a') then
  raise exception 'Projeto ou célula encerrados: somente consulta.' using errcode='22023'; end if;
 before_record:=snapshot;
 if action='add' then
  if (snapshot->>'total')::int+cardinality(item_ids)>2000 then raise exception 'O conjunto excede o limite de edição completa.' using errcode='22023'; end if;
  select greatest(coalesce(max(numero),0),0) into next_number from public.rm_fotos where projeto_id=project_id and celula_id=allocation.celula_id;
  for item in select value from jsonb_array_elements(p_payload->'items') loop
   item_id:=(item->>'id')::uuid; title_id:=(item->>'cadastro_foto_id')::uuid;
   if not exists(select 1 from jsonb_array_elements(snapshot->'titles') t where t->>'id'=title_id::text) then
    raise exception 'Título não pertence ao catálogo desta célula.' using errcode='22023'; end if;
   select * into title from public.rm_cadastro_fotos where id=title_id;
   if exists(select 1 from public.rm_fotos where id=item_id) then raise exception 'Identificador de foto já utilizado.' using errcode='22023'; end if;
   if exists(select 1 from public.rm_fotos f where f.projeto_id=project_id and f.celula_id=allocation.celula_id
    and (f.celula_projeto_id=allocation_id or f.celula_projeto_id is null) and f.categoria_foto='obrigat_ria'
    and (f.cadastro_foto_id=title_id or lower(btrim(regexp_replace(f.titulo,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(title.titulo,'[[:space:]]+',' ','g'))))) then
    raise exception 'Título já atribuído. Se retirado, restaure o mesmo item.' using errcode='22023'; end if;
   next_number:=next_number+1;
   insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,cadastro_foto_id,categoria_foto,titulo,numero,created_by_user_id,modified_by_id,sync_source)
    values(item_id,project_id,allocation.celula_id,allocation_id,title_id,'obrigat_ria',title.titulo,next_number::int,actor.id,actor.id,'supabase');
   changed:=array_append(changed,item_id);
  end loop;
 else
  select * into photo from public.rm_fotos where id=photo_id and projeto_id=project_id and celula_id=allocation.celula_id
   and (celula_projeto_id=allocation_id or celula_projeto_id is null);
  if not found then raise exception 'Foto não pertence a esta célula do projeto.' using errcode='22023'; end if;
  if photo.updated_at<>expected_photo then raise exception 'A foto foi alterada. Recarregue antes de salvar.' using errcode='PT409'; end if;
  if photo.categoria_foto is distinct from 'obrigat_ria' then raise exception 'Somente fotos obrigatórias previstas podem ser geridas aqui.' using errcode='22023'; end if;
  if action='tag' then
   if photo.lixeira then raise exception 'Restaure o item antes de alterar sua tag.' using errcode='22023'; end if;
   if photo.tag is distinct from tag_value then
    update public.rm_fotos set tag=tag_value,modified_by_id=actor.id,sync_source='supabase' where id=photo_id;
    changed:=array_append(changed,photo_id);
   end if;
  elsif action='retire' then
   if nullif(btrim(photo.foto_url),'') is not null or exists(select 1 from unnest(photo.fotos_arquivos_urls) x where nullif(btrim(x),'') is not null)
    or photo.selecao_relatorio then raise exception 'Foto com arquivo ou selecionada para relatório não pode ser retirada.' using errcode='22023'; end if;
   if not photo.lixeira then
    update public.rm_fotos set lixeira=true,modified_by_id=actor.id,sync_source='supabase' where id=photo_id;
    changed:=array_append(changed,photo_id);
   end if;
  else
   if photo.lixeira then
    if nullif(btrim(photo.foto_url),'') is not null or exists(select 1 from unnest(photo.fotos_arquivos_urls) x where nullif(btrim(x),'') is not null)
     or photo.selecao_relatorio then raise exception 'Item retirado com arquivo ou seleção não pode ser restaurado neste fluxo.' using errcode='22023'; end if;
    if exists(select 1 from public.rm_fotos f where f.id<>photo_id and f.projeto_id=project_id and f.celula_id=allocation.celula_id
     and (f.celula_projeto_id=allocation_id or f.celula_projeto_id is null) and not f.lixeira and f.categoria_foto='obrigat_ria'
     and ((photo.cadastro_foto_id is not null and f.cadastro_foto_id=photo.cadastro_foto_id)
      or (nullif(btrim(regexp_replace(photo.titulo,'[[:space:]]+',' ','g')),'') is not null and lower(btrim(regexp_replace(f.titulo,'[[:space:]]+',' ','g')))=lower(btrim(regexp_replace(photo.titulo,'[[:space:]]+',' ','g')))))) then
     raise exception 'Outro item ativo já possui este título ou cadastro.' using errcode='22023'; end if;
    update public.rm_fotos set lixeira=false,modified_by_id=actor.id,sync_source='supabase' where id=photo_id;
    changed:=array_append(changed,photo_id);
   end if;
  end if;
 end if;
 snapshot:=public.rm_web_operational_photos_snapshot_v1(project_id,allocation_id,true);
 result:=jsonb_build_object('operation',p_operation,'id',allocation_id,'projeto_id',project_id,'updated_at',clock_timestamp(),
  'record',jsonb_build_object('projeto_id',project_id,'celula_projeto_id',allocation_id,'action',action,
   'photos_version',snapshot->>'photos_version','changed_ids',to_jsonb(changed)),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='manage_operational_photos' then raise exception 'Identificador, ordem ou data inválida.' using errcode='22023'; end if;
 raise;
end $$;

-- Guard the shared capture primitive, not only a web button. Existing completed
-- mobile receipts still replay before this primitive is called by the envelope.
do $$ declare definition text; marker text:='    -- Atualiza o slot de foto obrigatória pré-cadastrado pelo Desktop'; begin
 definition:=pg_get_functiondef('public.rm_record_cell_photo_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,public.rm_categoria_foto_enum)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Unexpected photo capture definition'; end if;
 definition:=replace(definition,'v_foto public.rm_fotos%rowtype;','v_foto public.rm_fotos%rowtype; v_locked_project_id uuid;');
 definition:=replace(definition,marker,$guard$
    select * into v_foto from public.rm_fotos where id=p_foto_id;
    if not found or v_foto.projeto_id is null then raise exception 'Slot de projeto não encontrado.' using errcode='P0002'; end if;
    v_locked_project_id:=v_foto.projeto_id;
    perform pg_advisory_xact_lock(hashtextextended(v_locked_project_id::text,11));
    perform 1 from public.rm_projetos where id=v_locked_project_id for update;
    select * into v_foto from public.rm_fotos where id=p_foto_id for update;
    if not found or v_foto.projeto_id is null then raise exception 'Slot de projeto não encontrado.' using errcode='P0002'; end if;
    if v_foto.projeto_id is distinct from v_locked_project_id then raise exception 'O contexto da foto mudou. Sincronize novamente.' using errcode='PT409'; end if;
    if (p_projeto_id is not null and p_projeto_id is distinct from v_foto.projeto_id)
      or (p_celula_id is not null and p_celula_id is distinct from v_foto.celula_id)
      or (p_celula_projeto_id is not null and v_foto.celula_projeto_id is not null and p_celula_projeto_id is distinct from v_foto.celula_projeto_id) then
      raise exception 'Foto não pertence ao contexto informado.' using errcode='22023'; end if;
    if v_foto.lixeira then
      raise exception 'Foto obrigatória retirada do planejamento. Solicite ao gestor restaurar o mesmo item e tente sincronizar novamente; sua captura pendente foi preservada.' using errcode='PT409'; end if;
$guard$||marker);
 execute definition;
 -- Recompile the caller's warm cached plan without altering its payload/receipt.
 execute pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
  'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
  'set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos'));
do $$ declare definition text; needle text:='when ''save_project_route'' then ''em.planning.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
 execute replace(definition,needle,'when ''save_project_route'' then ''em.planning.manage'' when ''manage_operational_photos'' then ''em.planning.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_project_route_core_v1(uuid,text,jsonb)
 from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;

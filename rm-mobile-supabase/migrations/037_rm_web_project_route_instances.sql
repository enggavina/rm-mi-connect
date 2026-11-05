-- Canonical equipment classification and one-time, persistent project routes.
-- No backfill: existing project, allocation, photo, answer and offline IDs survive.
begin;

create table rm_private.project_route_instances (
 projeto_id uuid primary key references public.rm_projetos(id) on delete restrict,
 equipamento_id uuid not null unique references public.rm_equipamentos(id) on delete restrict,
 tipo_equipamento_id uuid not null references public.rm_tipos_equipamento(id) on delete restrict,
 actor_id uuid references public.rm_users(id) on delete restrict,
 client_submission_id uuid,
 origin_snapshot jsonb not null check(jsonb_typeof(origin_snapshot)='array'),
 created_at timestamptz not null default clock_timestamp()
);
revoke all on rm_private.project_route_instances from public,anon,authenticated,service_role;

-- Protect the canonical binding even when a legacy equipment already had the
-- selected type and initialization therefore required no technical-field edit.
-- Applies equally to web, mobile and ETL writers; no client flag bypass exists.
create function rm_private.guard_project_route_binding_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare instance rm_private.project_route_instances%rowtype;
begin
 if tg_table_name='rm_projetos' then
  if tg_op<>'DELETE' and new.equipamento_id is not null
   and (tg_op='INSERT' or new.equipamento_id is distinct from old.equipamento_id) then
   -- The advisory lock also exists when a newly inserted equipment row is not
   -- visible yet. A row lock alone would miss it and later wait only at the FK.
   perform pg_advisory_xact_lock(hashtextextended(new.equipamento_id::text,37));
   perform 1 from public.rm_equipamentos where id=new.equipamento_id for update;
   select * into instance from rm_private.project_route_instances where equipamento_id=new.equipamento_id;
   if found and instance.projeto_id is distinct from new.id then
    raise exception 'O equipamento já pertence ao roteiro de outro projeto.' using errcode='PT409'; end if;
  end if;
  if tg_op='INSERT' then return new; end if;
  select * into instance from rm_private.project_route_instances where projeto_id=old.id;
  if not found then return case when tg_op='DELETE' then old else new end; end if;
  if tg_op='DELETE' then raise exception 'Projeto com roteiro próprio: exclusão exige reconciliação.' using errcode='PT409'; end if;
  if new.id is distinct from old.id or new.equipamento_id is distinct from instance.equipamento_id then
   raise exception 'O vínculo do equipamento do roteiro exige reconciliação.' using errcode='PT409'; end if;
 else
  select * into instance from rm_private.project_route_instances where equipamento_id=old.id;
  if not found then return case when tg_op='DELETE' then old else new end; end if;
  if tg_op='DELETE' then raise exception 'Equipamento com roteiro próprio: exclusão exige reconciliação.' using errcode='PT409'; end if;
  if new.id is distinct from old.id or new.projeto_id is distinct from instance.projeto_id or new.tipo_equipamento_id is distinct from instance.tipo_equipamento_id then
   raise exception 'O tipo e vínculo do equipamento do roteiro exigem reconciliação.' using errcode='PT409'; end if;
 end if;
 return new;
end $$;
revoke all on function rm_private.guard_project_route_binding_v1() from public,anon,authenticated,service_role;
create trigger rm_project_route_project_binding before insert or update or delete on public.rm_projetos for each row execute function rm_private.guard_project_route_binding_v1();
create trigger rm_project_route_equipment_binding before update or delete on public.rm_equipamentos for each row execute function rm_private.guard_project_route_binding_v1();

-- This is a projection, not another stored relationship. Ambiguous legacy links
-- never acquire a classification by arbitrarily picking an equipment row.
create function rm_private.effective_project_type_v1(p public.rm_projetos) returns uuid
language sql stable security invoker set search_path='' as $$
 select case
  when p.equipamento_id is null and not exists(select 1 from public.rm_equipamentos e where e.projeto_id=p.id) then p.tipo_equipamento_id
  when exists(select 1 from public.rm_equipamentos e where e.id=p.equipamento_id and e.projeto_id=p.id)
   and (select count(*) from public.rm_projetos x where x.equipamento_id=p.equipamento_id)=1
   then coalesce((select e.tipo_equipamento_id from public.rm_equipamentos e where e.id=p.equipamento_id and e.projeto_id=p.id),p.tipo_equipamento_id)
  else null end;
$$;
revoke all on function rm_private.effective_project_type_v1(public.rm_projetos) from public,anon,service_role;
grant execute on function rm_private.effective_project_type_v1(public.rm_projetos) to authenticated;

create function rm_private.project_route_state_v1(p_project uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select case when not rm_private.is_rm_authenticated() then null else jsonb_build_object(
  'initialized_from_type',exists(select 1 from rm_private.project_route_instances r where r.projeto_id=p_project),
  'source_type_id',(select r.tipo_equipamento_id from rm_private.project_route_instances r where r.projeto_id=p_project),
  'has_project_route',exists(select 1 from rm_private.project_route_instances r where r.projeto_id=p_project)
   or exists(select 1 from public.rm_celulas_projeto c where c.projeto_id=p_project)
   or exists(select 1 from public.rm_fotos f where f.projeto_id=p_project)
   or exists(select 1 from public.rm_registros_formulario f where f.projeto_id=p_project)
   or exists(select 1 from public.rm_aprovacoes_etapas a where a.projeto_id=p_project)
   or exists(select 1 from public.rm_logs_aprovacao l where l.projeto_id=p_project)
   or exists(select 1 from public.rm_aprovacoes_registro a where a.projeto_id=p_project)) end;
$$;
revoke all on function rm_private.project_route_state_v1(uuid) from public,anon,service_role;
grant execute on function rm_private.project_route_state_v1(uuid) to authenticated;

-- Keep the original RPC names, versions, RLS and DTOs. Only add minimum route
-- evidence; the legacy raw-column mismatch flag remains backward compatible.
do $$ declare d text; needle text; begin
 d:=pg_get_functiondef('public.rm_web_project_equipment_snapshot_v1(uuid)'::regprocedure);
 needle:='''type_mismatch'',binding=''linked'' and p.tipo_equipamento_id is distinct from e.tipo_equipamento_id)';
 if strpos(d,needle)=0 then raise exception 'Unexpected equipment snapshot'; end if;
 execute replace(d,needle,'''type_mismatch'',binding=''linked'' and p.tipo_equipamento_id is distinct from e.tipo_equipamento_id,
  ''has_project_route'',coalesce((rm_private.project_route_state_v1(p.id)->>''has_project_route'')::boolean,false),
  ''can_change_type'',binding in(''linked'',''missing'') and not closed and not coalesce((rm_private.project_route_state_v1(p.id)->>''has_project_route'')::boolean,true))');
 d:=pg_get_functiondef('public.rm_web_project_route_snapshot_v1(uuid)'::regprocedure);
 needle:='select jsonb_build_object(''project'',p.dto,''total'',a.total,''complete'',a.total<=2000,';
 if strpos(d,needle)=0 then raise exception 'Unexpected route snapshot'; end if;
 execute replace(d,needle,'select jsonb_build_object(''initialized_from_type'',coalesce((rm_private.project_route_state_v1(p.id)->>''initialized_from_type'')::boolean,false),
  ''source_type_id'',rm_private.project_route_state_v1(p.id)->''source_type_id'',''project'',p.dto,''total'',a.total,''complete'',a.total<=2000,');
 -- Filtering, summary counts and pagination must all use the same canonical
 -- projection. Replacing only the returned DTO would leave wrong receiving rows.
 d:=pg_get_functiondef('public.rm_web_receivings_v1(text,text,integer,integer)'::regprocedure);
 needle:='select p.*,c.nome cliente_nome,t.nome tipo_equipamento_nome,';
 if strpos(d,needle)=0 then raise exception 'Unexpected receiving source'; end if;
 d:=replace(d,needle,'select p.*,rm_private.effective_project_type_v1(p) effective_type_id,c.nome cliente_nome,t.nome tipo_equipamento_nome,');
 d:=replace(d,'case when p.tipo_equipamento_id is null','case when rm_private.effective_project_type_v1(p) is null');
 d:=replace(d,'t.id=p.tipo_equipamento_id','t.id=rm_private.effective_project_type_v1(p)');
 d:=replace(d,'or p.tipo_equipamento_id is null','or rm_private.effective_project_type_v1(p) is null');
 d:=replace(d,'''tipo_equipamento_id'',p.tipo_equipamento_id','''tipo_equipamento_id'',p.effective_type_id');
 execute d;
end $$;

-- Capture the whole model in ONE MVCC statement. All later writes read this
-- immutable JSON, so concurrent template edits cannot mix cells/forms/photos/
-- rules from different snapshots. Existing engineering pair locks still protect
-- the source configuration while its snapshot is acquired.
create function rm_private.initialize_project_route_v1(p_project uuid,p_actor uuid,p_submission uuid) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare p public.rm_projetos%rowtype; e public.rm_equipamentos%rowtype; type_id uuid; source jsonb;
 item jsonb; child jsonb; allocation uuid; forms uuid[]; candidate record;
 cell_count int:=0; photo_count int:=0; stage_count int:=0;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_project::text,11));
 select * into p from public.rm_projetos where id=p_project for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 if exists(select 1 from rm_private.project_route_instances where projeto_id=p_project) then
  return jsonb_build_object('projeto_id',p_project,'celulas_materializadas',0,'fotos_clonadas',0,'aprovacoes_clonadas',0,'already_initialized',true); end if;
 if (rm_private.project_route_state_v1(p_project)->>'has_project_route')::boolean then
  raise exception 'O projeto já possui dados operacionais. O roteiro atual será preservado.' using errcode='PT409'; end if;
 select * into e from public.rm_equipamentos where id=p.equipamento_id and projeto_id=p.id for update;
 type_id:=rm_private.effective_project_type_v1(p);
 if e.id is null or e.tipo_equipamento_id is null or type_id is distinct from e.tipo_equipamento_id then
  raise exception 'Selecione o tipo no equipamento vinculado ao projeto.' using errcode='22023'; end if;
 for candidate in select m.celula_id from public.rm_celula_tipos_equipamento m where m.tipo_equipamento_id=type_id order by m.celula_id loop
  perform rm_private.engineering_pair_lock(candidate.celula_id,type_id,false);
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('matrix_id',m.id,'matrix_updated_at',m.updated_at,'celula_id',m.celula_id,
  'visibilidade',m.visibilidade,'indice',coalesce(c.ordem,c.indice),
  'forms',coalesce((select jsonb_agg(f.form_id order by f.form_id) from public.rm_celula_form_tipos_equipamento f where f.celula_tipo_equipamento_id=m.id and f.ativo),'[]'::jsonb),
  'photos',coalesce((select jsonb_agg(jsonb_build_object('origin_id',f.id,'cadastro_foto_id',f.cadastro_foto_id,
   'categoria_foto',f.categoria_foto,'etapa',f.etapa,'tipo_recebimento',f.tipo_recebimento,'identificador_foto_key',f.identificador_foto_key,
   'titulo',coalesce(nullif(f.titulo,''),(select t.titulo from public.rm_cadastro_fotos t where t.id=f.cadastro_foto_id)),
   'descricao',f.descricao,'legenda',f.legenda,'tag',f.tag,'numero',f.numero) order by f.numero nulls last,f.id)
   from public.rm_fotos f where f.celula_tipo_equipamento_id=m.id and f.projeto_id is null and f.celula_projeto_id is null and not f.lixeira),'[]'::jsonb),
  'stages',coalesce((select jsonb_agg(jsonb_build_object('origin_id',a.id,'celula_origem_id',a.celula_origem_id,'celula_destino_id',a.celula_destino_id,
   'status_cel_proj',a.status_cel_proj,'bloquear_avanco_sem_aprov',a.bloquear_avanco_sem_aprov,'aprovador_id',a.aprovador_id,
   'aprovadores_ids',a.aprovadores_ids,'aprovadores_retorno_ids',a.aprovadores_retorno_ids) order by a.created_at,a.id)
   from public.rm_aprovacoes_etapas a where a.celula_tipo_equipamento_id=m.id and a.projeto_id is null and a.celula_projeto_id is null and a.ativo),'[]'::jsonb))
   order by c.ordem nulls last,c.indice nulls last,m.id),'[]'::jsonb) into source
 from public.rm_celula_tipos_equipamento m join public.rm_celulas c on c.id=m.celula_id where m.tipo_equipamento_id=type_id and m.ativo;
 if jsonb_array_length(source)>2000 then raise exception 'Roteiro excede o limite de células.' using errcode='22023'; end if;
 -- Invalid model destinations must roll back creation instead of producing a
 -- partial route whose approvals point outside the copied project cells.
 if exists(select 1 from jsonb_array_elements(source) s cross join jsonb_array_elements(s->'stages') a
   where a->>'celula_origem_id' is distinct from s->>'celula_id' or a->>'celula_destino_id' is null
    or not exists(select 1 from jsonb_array_elements(source) d where d->>'celula_id'=a->>'celula_destino_id')) then
  raise exception 'O roteiro modelo possui aprovação com origem ou destino fora das células ativas. Revise a Engenharia.' using errcode='PT422'; end if;
 insert into rm_private.project_route_instances(projeto_id,equipamento_id,tipo_equipamento_id,actor_id,client_submission_id,origin_snapshot)
  values(p.id,e.id,type_id,p_actor,p_submission,source);
 for item in select value from jsonb_array_elements(source) loop
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into forms from jsonb_array_elements_text(item->'forms');
  insert into public.rm_celulas_projeto(projeto_id,celula_id,numero_projeto,cliente_nome_export,tipo_equipamento_nome_export,escopo_abreviado,
   status_historico,visibilidade,indice,forms_ids,modified_by_id,sync_source)
   values(p.id,(item->>'celula_id')::uuid,p.numero,p.cliente_nome_exportacao,(select nome from public.rm_tipos_equipamento where id=type_id),p.escopo_abreviado,
    array['pendente']::public.rm_status_cel_proj_enum[],coalesce((item->>'visibilidade')::boolean,false),cell_count+1,forms,p_actor,'supabase') returning id into allocation;
  cell_count:=cell_count+1;
  for child in select value from jsonb_array_elements(item->'photos') loop
   insert into public.rm_fotos(projeto_id,celula_id,celula_projeto_id,celula_tipo_equipamento_id,cadastro_foto_id,categoria_foto,etapa,tipo_recebimento,
    identificador_foto_key,titulo,descricao,legenda,tag,numero,created_by_user_id,sync_source)
    values(p.id,(item->>'celula_id')::uuid,allocation,(item->>'matrix_id')::uuid,(child->>'cadastro_foto_id')::uuid,
     coalesce((child->>'categoria_foto')::public.rm_categoria_foto_enum,'obrigat_ria'),(child->>'etapa')::public.rm_etapa_foto_enum,
     (child->>'tipo_recebimento')::public.rm_tipo_foto_recebimento_enum,child->>'identificador_foto_key',child->>'titulo',child->>'descricao',child->>'legenda',child->>'tag',(child->>'numero')::integer,p_actor,'supabase');
   photo_count:=photo_count+1;
  end loop;
  for child in select value from jsonb_array_elements(item->'stages') loop
   insert into public.rm_aprovacoes_etapas(projeto_id,celula_projeto_id,celula_tipo_equipamento_id,celula_origem_id,celula_destino_id,
    status,status_cel_proj,bloquear_avanco_sem_aprov,aprovador_id,aprovadores_ids,aprovadores_retorno_ids,sync_source)
    values(p.id,allocation,(item->>'matrix_id')::uuid,(child->>'celula_origem_id')::uuid,(child->>'celula_destino_id')::uuid,'nulo',
     (child->>'status_cel_proj')::public.rm_status_cel_proj_enum,(child->>'bloquear_avanco_sem_aprov')::boolean,(child->>'aprovador_id')::uuid,
     array(select value::uuid from jsonb_array_elements_text(child->'aprovadores_ids')),
     array(select value::uuid from jsonb_array_elements_text(child->'aprovadores_retorno_ids')),'supabase');
   stage_count:=stage_count+1;
  end loop;
 end loop;
 return jsonb_build_object('projeto_id',p.id,'celulas_materializadas',cell_count,'fotos_clonadas',photo_count,'aprovacoes_clonadas',stage_count,'already_initialized',false);
end $$;
revoke all on function rm_private.initialize_project_route_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

-- Extend the existing atomic command. Historical receipts and existing-project
-- updates remain compatible; fresh web creation must use the typed bundle.
alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_route_instance_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 p public.rm_projetos%rowtype; e public.rm_equipamentos%rowtype; proposed public.rm_equipamentos%rowtype;
 project_id uuid; equipment_id uuid; type_id uuid; snapshot jsonb; result jsonb; journal uuid; is_new boolean;
begin
 if p_operation is distinct from 'save_project_with_equipment' or not (p_payload->'equipment'?'tipo_equipamento_id') then
  if p_operation in('save_project','save_project_with_equipment') then
   select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
   if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
   if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
   if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
   perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
   if not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id) then
    project_id:=(p_payload->>'id')::uuid;
    perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
    select * into p from public.rm_projetos where id=project_id for update;
    if not found then raise exception 'Crie o projeto junto com o equipamento e seu tipo.' using errcode='PT423'; end if;
   end if;
  end if;
  -- An old UI must not rewrite the legacy project type after classification has
  -- become equipment-owned. Historical replays remain valid and side-effect free.
  if p_operation='save_project' and p_payload->'changes'?'tipo_equipamento_id' then
   select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
   if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
   perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
   perform pg_advisory_xact_lock(hashtextextended(p_payload->>'id',11));
   select * into p from public.rm_projetos where id=(p_payload->>'id')::uuid for update;
   if not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id)
    and (exists(select 1 from rm_private.project_route_instances where projeto_id=p.id)
     or exists(select 1 from public.rm_equipamentos x where x.id=p.equipamento_id and x.projeto_id=p.id and x.tipo_equipamento_id is not null))
    and (p_payload->'changes'->>'tipo_equipamento_id')::uuid is distinct from p.tipo_equipamento_id then
    raise exception 'Altere o tipo no equipamento do projeto. O roteiro existente será preservado.' using errcode='22023'; end if;
  end if;
  return rm_private.web_mutate_before_route_instance_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and (auth.jwt()->>'aal') is distinct from 'aal2' then
  raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if jsonb_typeof(p_payload->'equipment'->'tipo_equipamento_id') not in('string','null') then raise exception 'Tipo de equipamento inválido.' using errcode='22023'; end if;
 project_id:=(p_payload->>'id')::uuid; equipment_id:=(p_payload->'equipment'->>'id')::uuid; type_id:=(p_payload->'equipment'->>'tipo_equipamento_id')::uuid;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into p from public.rm_projetos where id=project_id for update; is_new:=not found;
 perform pg_advisory_xact_lock(hashtextextended(equipment_id::text,37));
 if p.equipamento_id is not null then select * into e from public.rm_equipamentos where id=p.equipamento_id for update; end if;
 if type_id is not null and not exists(select 1 from public.rm_tipos_equipamento where id=type_id) then raise exception 'Tipo de equipamento inexistente.' using errcode='22023'; end if;
 if (is_new or e.id is null) and type_id is null then raise exception 'Selecione o tipo de equipamento.' using errcode='22023'; end if;
 if type_id is distinct from e.tipo_equipamento_id and not is_new
  and coalesce((rm_private.project_route_state_v1(project_id)->>'has_project_route')::boolean,true) then
  raise exception 'O tipo não pode mudar após a criação do roteiro ou de dados operacionais. O roteiro atual será preservado.' using errcode='22023'; end if;
 -- Reuse 036: exact optimistic checks, canonical binding, project validation,
 -- technical fields, protected offline journal and atomic rollback stay intact.
 result:=rm_private.web_mutate_before_route_instance_v1(gen_random_uuid(),p_operation,p_payload #- '{equipment,tipo_equipamento_id}');
 select * into e from public.rm_equipamentos where id=equipment_id and projeto_id=project_id for update;
 if e.id is null then raise exception 'Vínculo do equipamento inconsistente.' using errcode='PT409'; end if;
 if e.tipo_equipamento_id is distinct from type_id then
  proposed:=e; proposed.tipo_equipamento_id:=type_id;
  insert into rm_private.equipment_change_events(projeto_id,equipamento_id,auth_user_id,actor_id,client_submission_id,changed_fields,before_record,after_record)
   values(project_id,e.id,auth.uid(),actor.id,gen_random_uuid(),array['tipo_equipamento_id'],to_jsonb(e),to_jsonb(proposed)) returning id into journal;
  update public.rm_equipamentos set tipo_equipamento_id=type_id,sync_source='supabase' where id=e.id returning * into e;
  update rm_private.equipment_change_events set after_record=to_jsonb(e) where id=journal;
 end if;
 if type_id is not null and not coalesce((rm_private.project_route_state_v1(project_id)->>'has_project_route')::boolean,true) then
  perform rm_private.initialize_project_route_v1(project_id,actor.id,p_client_submission_id);
 end if;
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation='save_project_with_equipment' then raise exception 'Identificador, versão ou tipo de equipamento inválido.' using errcode='22023'; end if; raise;
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_route_instance_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- A new allocation in an initialized route is a project-specific exception.
-- Never read the current template again (including after all cells are retired).
do $$ declare d text; needle text; replacement text; begin
 d:=pg_get_functiondef('rm_private.web_mutate_project_core_v1(uuid,text,jsonb)'::regprocedure);
 needle:=$old$      if project.tipo_equipamento_id is not null then
        perform rm_private.engineering_pair_lock(cell_id,project.tipo_equipamento_id,false);
      end if;
      select * into template from public.rm_celula_tipos_equipamento
        where celula_id=cell_id and tipo_equipamento_id=project.tipo_equipamento_id;$old$;
 replacement:=$new$      if not exists(select 1 from rm_private.project_route_instances where projeto_id=project_id) then
        if rm_private.effective_project_type_v1(project) is not null then
          perform rm_private.engineering_pair_lock(cell_id,rm_private.effective_project_type_v1(project),false);
        end if;
        select * into template from public.rm_celula_tipos_equipamento
          where celula_id=cell_id and tipo_equipamento_id=rm_private.effective_project_type_v1(project);
      end if;$new$;
 if strpos(d,needle)=0 then raise exception 'Unexpected allocation source'; end if;
 d:=replace(d,needle,replacement);
 needle:='''horas_previstas'',''responsavel_id'',''observacao'',''forms_ids''];';
 if strpos(d,needle)=0 then raise exception 'Unexpected allocation editable fields'; end if;
 d:=replace(d,needle,'''horas_previstas'',''responsavel_id'',''observacao'',''forms_ids'',''motivo_atraso''];');
 needle:='motivo_bloqueio=next_cell.motivo_bloqueio,visibilidade=next_cell.visibilidade,';
 if strpos(d,needle)=0 then raise exception 'Unexpected allocation update'; end if;
 d:=replace(d,needle,'motivo_bloqueio=next_cell.motivo_bloqueio,motivo_atraso=next_cell.motivo_atraso,visibilidade=next_cell.visibilidade,');
 execute d;
 -- Existing service materialization remains compatible for legacy projects,
 -- but can never reapply current templates to initialized project instances.
 d:=pg_get_functiondef('public.rm_materialize_project_cells_v1(uuid,timestamptz,timestamptz)'::regprocedure);
 needle:='  if pr.tipo_equipamento_id is null then raise exception ''Informe o tipo de equipamento.'' using errcode=''22023''; end if;';
 if strpos(d,needle)=0 then raise exception 'Unexpected materialization source'; end if;
 d:=replace(d,needle,'  if exists(select 1 from rm_private.project_route_instances where projeto_id=pr.id) then return jsonb_build_object(''projeto_id'',pr.id,''celulas_materializadas'',0,''fotos_clonadas'',0,''aprovacoes_clonadas'',0); end if;
  pr.tipo_equipamento_id:=rm_private.effective_project_type_v1(pr);
  if pr.tipo_equipamento_id is null then raise exception ''Informe o tipo de equipamento.'' using errcode=''22023''; end if;');
 execute d;
 -- Rebind warmed public dispatch plans to the new core, without changing SSO
 -- capability mapping, permit checks or operation names.
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;

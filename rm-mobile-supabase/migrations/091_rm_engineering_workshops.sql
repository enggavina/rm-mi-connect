begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.engineering_photo_title_scope (
 title_id uuid primary key,
 workshop_id uuid not null references rm_private.workshop_references(id),
 cell_id uuid,
 captured_at timestamptz not null default clock_timestamp()
);
create index engineering_photo_titles_by_office on rm_private.engineering_photo_title_scope(workshop_id,cell_id,title_id);
alter table rm_private.engineering_photo_title_scope enable row level security;
revoke all on rm_private.engineering_photo_title_scope from public,anon,authenticated,service_role;
create trigger engineering_title_scope_immutable before update or delete on rm_private.engineering_photo_title_scope
 for each row execute function rm_private.workshop_origin_immutable_v1();
create trigger engineering_title_scope_no_truncate before truncate on rm_private.engineering_photo_title_scope
 for each statement execute function rm_private.workshop_origin_immutable_v1();

create table rm_private.engineering_workshop_enforcement (
 singleton boolean primary key default true check(singleton),
 activated_at timestamptz not null,
 legacy_title_count bigint not null check(legacy_title_count>=0)
);
alter table rm_private.engineering_workshop_enforcement enable row level security;
revoke all on rm_private.engineering_workshop_enforcement from public,anon,authenticated,service_role;

create function rm_private.activate_engineering_workshops_v1(p_expected_titles bigint) returns void
language plpgsql set search_path='' as $$
declare bma uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended('engineering-workshop-cutover',51));
 if exists(select 1 from rm_private.engineering_workshop_enforcement) then
  raise exception 'A Engenharia já foi ativada por oficina.' using errcode='PT409';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17));
 lock table public.rm_cadastro_fotos, rm_private.engineering_photo_title_scope in share row exclusive mode;
 select a.legacy_workshop_id into bma from rm_private.workshop_legacy_adoption a
 join rm_private.workshop_references w on w.id=a.legacy_workshop_id where w.code='BMA';
 if bma is null or p_expected_titles is distinct from (select count(*) from public.rm_cadastro_fotos) then
  raise exception 'Confira a adoção da BMA e a contagem atual de títulos.' using errcode='PT409';
 end if;
 if exists(select 1 from public.rm_celula_tipos_equipamento m
  join rm_private.workshop_cell_ownership c on c.cell_id=m.celula_id
  where not rm_private.workshop_read_owned_v1('equipment_type',m.tipo_equipamento_id,c.workshop_id))
  or exists(select 1 from public.rm_celula_tipos_equipamento m
   where not exists(select 1 from rm_private.workshop_cell_ownership c where c.cell_id=m.celula_id)) then
  raise exception 'Há configurações com oficina pendente ou divergente.' using errcode='PT409';
 end if;
 if exists(select 1 from public.rm_cadastro_fotos t left join rm_private.engineering_photo_title_scope a on a.title_id=t.id
  where a.title_id is null and nullif(rm_private.catalog_name_key(t.celula_nome),'') is not null
  and (select count(*) from public.rm_celulas c where rm_private.workshop_cell_owned_v1(c.id,bma)
       and rm_private.catalog_name_key(c.nome)=rm_private.catalog_name_key(t.celula_nome)) <> 1) then
  raise exception 'Há títulos legados com célula de origem ambígua ou pendente.' using errcode='PT409';
 end if;
 insert into rm_private.engineering_photo_title_scope(title_id,workshop_id,cell_id)
 select t.id,bma,c.id from public.rm_cadastro_fotos t left join public.rm_celulas c
  on nullif(rm_private.catalog_name_key(t.celula_nome),'') is not null
  and rm_private.catalog_name_key(c.nome)=rm_private.catalog_name_key(t.celula_nome)
  and rm_private.workshop_cell_owned_v1(c.id,bma)
 where not exists(select 1 from rm_private.engineering_photo_title_scope a where a.title_id=t.id);
 if exists(select 1 from public.rm_fotos f
   join rm_private.engineering_photo_title_scope t on t.title_id=f.cadastro_foto_id
   left join public.rm_celula_tipos_equipamento m on m.id=f.celula_tipo_equipamento_id
   where (f.projeto_id is not null and not rm_private.workshop_project_owned_v1(f.projeto_id,t.workshop_id))
    or (coalesce(f.celula_id,m.celula_id) is not null and
     not rm_private.workshop_cell_owned_v1(coalesce(f.celula_id,m.celula_id),t.workshop_id))) then
  raise exception 'Há títulos vinculados a registros de outra oficina.' using errcode='PT409';
 end if;
 insert into rm_private.engineering_workshop_enforcement values(true,clock_timestamp(),p_expected_titles);
 revoke execute on function public.rm_web_engineering_snapshot_v1(uuid) from authenticated;
 perform pg_notify('pgrst','reload schema');
end
$$;

create function rm_private.workshop_engineering_title_v1(p_id uuid,p_office uuid,p_cell uuid default null) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from rm_private.engineering_photo_title_scope s join public.rm_cadastro_fotos t on t.id=s.title_id
  where s.title_id=p_id and s.workshop_id=p_office
   and (s.cell_id is null or rm_private.workshop_cell_owned_v1(s.cell_id,p_office) and (p_cell is null or s.cell_id=p_cell)))
$$;

create function rm_private.guard_engineering_photo_workshop_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare office uuid; allocation public.rm_celulas_projeto; matrix public.rm_celula_tipos_equipamento;
begin
 if new.cadastro_foto_id is null or not exists(select 1 from rm_private.engineering_workshop_enforcement) then return new;end if;
 if tg_op='UPDATE' and (new.cadastro_foto_id,new.projeto_id,new.celula_id,new.celula_projeto_id,new.celula_tipo_equipamento_id)
  is not distinct from (old.cadastro_foto_id,old.projeto_id,old.celula_id,old.celula_projeto_id,old.celula_tipo_equipamento_id) then
  return new;
 end if;
 select t.workshop_id into office from rm_private.engineering_photo_title_scope t where t.title_id=new.cadastro_foto_id;
 select * into allocation from public.rm_celulas_projeto where id=new.celula_projeto_id;
 select * into matrix from public.rm_celula_tipos_equipamento where id=new.celula_tipo_equipamento_id;
 if office is null or coalesce(new.projeto_id,new.celula_id,allocation.id,matrix.id) is null
  or (new.projeto_id is not null and not rm_private.workshop_project_owned_v1(new.projeto_id,office))
  or (new.celula_id is not null and not rm_private.workshop_cell_owned_v1(new.celula_id,office))
  or (new.celula_projeto_id is not null and (allocation.id is null or not rm_private.workshop_project_owned_v1(allocation.projeto_id,office)
   or not rm_private.workshop_cell_owned_v1(allocation.celula_id,office)))
  or (new.celula_tipo_equipamento_id is not null and not rm_private.workshop_mobile_cell_type_owned_v1(matrix.id,office)) then
  raise exception 'Título de foto indisponível para este vínculo.' using errcode='42501';
 end if;
 return new;
end
$$;
create trigger engineering_photo_title_workshop before insert or update of cadastro_foto_id,projeto_id,celula_id,celula_projeto_id,celula_tipo_equipamento_id
 on public.rm_fotos for each row execute function rm_private.guard_engineering_photo_workshop_v1();

create function rm_private.workshop_engineering_entry_v1(p_id uuid,p_office uuid,p_snapshot jsonb default null) returns jsonb
language plpgsql stable set search_path='' as $$
declare snapshot jsonb;
begin
 if not rm_private.workshop_mobile_cell_type_owned_v1(p_id,p_office) then return null;end if;
 snapshot:=coalesce(p_snapshot,public.rm_web_engineering_snapshot_v1(p_id));
 return snapshot||jsonb_build_object(
  'form_ids',coalesce((select jsonb_agg(f order by n) from jsonb_array_elements(snapshot->'form_ids') with ordinality e(f,n)
      where rm_private.workshop_read_owned_v1('form_model',(f#>>'{}')::uuid,p_office)),'[]'::jsonb),
  'photos',coalesce((select jsonb_agg(case when f->>'cadastro_foto_id' is null
    or rm_private.workshop_engineering_title_v1((f->>'cadastro_foto_id')::uuid,p_office) then f
    else f - 'cadastro_foto_id' - 'titulo' || jsonb_build_object('cadastro_foto_id',null,'titulo',null) end order by n)
      from jsonb_array_elements(snapshot->'photos') with ordinality e(f,n)
      where exists(select 1 from public.rm_fotos r where r.id=(f->>'id')::uuid
        and (r.celula_id is null or rm_private.workshop_cell_owned_v1(r.celula_id,p_office)))),'[]'::jsonb),
  'stages',coalesce((select jsonb_agg(s order by n) from jsonb_array_elements(snapshot->'stages') with ordinality e(s,n)
      where (s->>'celula_origem_id' is null or rm_private.workshop_cell_owned_v1((s->>'celula_origem_id')::uuid,p_office))
       and (s->>'celula_destino_id' is null or rm_private.workshop_cell_owned_v1((s->>'celula_destino_id')::uuid,p_office))),'[]'::jsonb)
 );
end
$$;

create function rm_private.workshop_engineering_read_v1(p_resource text,p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare keys text[]; ident uuid; cell uuid; term text; page integer; result jsonb; cells jsonb; types jsonb; entry jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' then
  raise exception 'Consulta de engenharia inválida.' using errcode='22023';
 end if;
 select coalesce(array_agg(k order by k),'{}') into keys from jsonb_object_keys(p_args) k;
 if p_resource in('engineering_entry','photo_title_entry') and keys=array['id'] and jsonb_typeof(p_args->'id')='string' then
  ident:=(p_args->>'id')::uuid;
  if p_resource='engineering_entry' then return rm_private.workshop_engineering_entry_v1(ident,p_office);end if;
  return (select jsonb_build_object('id',t.id,'titulo',t.titulo,'numero',t.numero,'celula_nome',c.nome,'celula_id',s.cell_id,
   'updated_at',t.updated_at,'scope_resolved',true,'scope_ambiguous',false)
   from public.rm_cadastro_fotos t join rm_private.engineering_photo_title_scope s on s.title_id=t.id
   left join public.rm_celulas c on c.id=s.cell_id where t.id=ident
    and rm_private.workshop_engineering_title_v1(t.id,p_office));
 end if;

 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'codigo',c.codigo,'indice',c.indice,
  'ordem',c.ordem) order by c.ordem,c.nome,c.id),'[]') into cells
 from public.rm_celulas c where rm_private.workshop_cell_owned_v1(c.id,p_office);
 if p_resource='photo_title_list' and keys=array['cell','page','q'] and jsonb_typeof(p_args->'cell') in('null','string')
  and jsonb_typeof(p_args->'q')='string' and length(p_args->>'q')<=100
  and jsonb_typeof(p_args->'page')='number' and p_args->>'page' ~ '^[1-9][0-9]{0,4}$' then
  cell:=(p_args->>'cell')::uuid; page:=(p_args->>'page')::int; term:=lower(p_args->>'q');
  with rows as materialized(select t.id,t.titulo,t.numero,c.nome celula_nome,s.cell_id celula_id,t.updated_at,
    true scope_resolved,false scope_ambiguous
   from rm_private.engineering_photo_title_scope s join public.rm_cadastro_fotos t on t.id=s.title_id
   left join public.rm_celulas c on c.id=s.cell_id
   where s.workshop_id=p_office and (cell is null or cell=s.cell_id)
    and rm_private.workshop_engineering_title_v1(t.id,p_office)
    and (term='' or strpos(lower(coalesce(t.titulo,'')),term)>0 or strpos(lower(coalesce(c.nome,'')),term)>0)
  ), selected as (select * from rows order by titulo,id limit 50 offset (page-1)*50)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(s) order by s.titulo,s.id) from selected s),'[]'),
   'total',(select count(*) from rows),'page',page,'pageSize',50,'cells',cells) into result;
  return result;
 end if;

 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'nome',t.nome,'sigla',t.sigla) order by t.nome,t.id),'[]') into types
 from public.rm_tipos_equipamento t where rm_private.workshop_read_visible_v1('equipment_type',t.id,p_office);
 if p_resource='engineering_matrix' and keys=array['type'] and jsonb_typeof(p_args->'type') in('null','string') then
  ident:=coalesce((p_args->>'type')::uuid,(types->0->>'id')::uuid);
  if ident is not null and not rm_private.workshop_read_visible_v1('equipment_type',ident,p_office) then ident:=null;end if;
  return jsonb_build_object('types',types,'cells',cells,'selectedTypeId',ident,'rows',
   (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'celula_id',m.celula_id,
    'tipo_equipamento_id',m.tipo_equipamento_id,'ativo',m.ativo,'visibilidade',m.visibilidade,'updated_at',m.updated_at,
    'form_count',jsonb_array_length(d.value->'form_ids'),'photo_count',jsonb_array_length(d.value->'photos'),
    'stage_count',jsonb_array_length(d.value->'stages')) order by m.id),'[]')
   from public.rm_celula_tipos_equipamento m cross join lateral (select rm_private.workshop_engineering_entry_v1(m.id,p_office) value) d
   where m.tipo_equipamento_id=ident and rm_private.workshop_cell_owned_v1(m.celula_id,p_office)));
 elsif p_resource='engineering_choices' and keys=array['id'] and jsonb_typeof(p_args->'id') in('null','string') then
  ident:=(p_args->>'id')::uuid;
  if ident is not null then
   entry:=rm_private.workshop_engineering_entry_v1(ident,p_office);
   if entry is null then return null;end if;
  end if;
  return jsonb_build_object('types',types,'cells',cells,
   'forms',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'titulo',
    case when v.version is not null then coalesce(f.titulo,'')||' · v'||v.version else f.titulo end,'ativo',f.ativo) order by f.titulo,f.id),'[]')
    from public.rm_forms f left join public.rm_form_template_versions v on v.form_id=f.id
    where rm_private.workshop_read_visible_v1('form_model',f.id,p_office)
     and (f.ativo or (entry->'form_ids') ? f.id::text)),
   'users',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome,'matricula',u.matricula,'status',u.status) order by u.nome,u.id),'[]')
    from public.rm_users u where exists(select 1 from public.rm_tablet_celula_users l
     where l.identidade_id=u.id and rm_private.workshop_cell_owned_v1(l.celula_id,p_office))),
   'cellUserLinks',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'celula_id',l.celula_id,'identidade_id',l.identidade_id) order by l.id),'[]')
    from public.rm_tablet_celula_users l where l.identidade_id is not null and rm_private.workshop_cell_owned_v1(l.celula_id,p_office)),
   'photoTitles',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'titulo',t.titulo,'numero',t.numero,'celula_nome',c.nome,
    'celula_id',s.cell_id,'scope_resolved',true,'scope_ambiguous',false,'updated_at',t.updated_at) order by t.titulo,t.id),'[]')
    from rm_private.engineering_photo_title_scope s join public.rm_cadastro_fotos t on t.id=s.title_id
    left join public.rm_celulas c on c.id=s.cell_id where s.workshop_id=p_office
     and rm_private.workshop_engineering_title_v1(t.id,p_office)),
   'statuses',(select coalesce(jsonb_agg(jsonb_build_object('id',option_key,'option_key',option_key,
    'bubble_display',bubble_display,'sort_order',sort_order) order by sort_order,option_key),'[]')
    from public.rm_option_sets where option_set_key='status_cel_proj'));
 end if;
 raise exception 'Consulta de engenharia inválida.' using errcode='22023';
exception when invalid_text_representation or numeric_value_out_of_range then
 raise exception 'Filtros de engenharia inválidos.' using errcode='22023';
end
$$;

create function rm_private.web_mutate_engineering_workshop_v1(p_submission uuid,p_operation text,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare office uuid; ident uuid; cell uuid; model_type uuid; recorded rm_private.engineering_photo_title_scope;
 changes jsonb; result jsonb;
begin
 if p_operation is null or p_operation not in('save_engineering','save_photo_title','delete_photo_title') then
  return rm_private.web_mutate_form_review_workshop_v1(p_submission,p_operation,p_payload);
 end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('engineering-workshop-cutover',51));
 office:=rm_private.planning_workshop_permit_v1(p_submission,p_operation,p_payload,
  exists(select 1 from rm_private.engineering_workshop_enforcement where singleton));
 if office is null then return rm_private.web_mutate_form_review_workshop_v1(p_submission,p_operation,p_payload);end if;
 ident:=(p_payload->>'id')::uuid;
 changes:=p_payload->'changes';
 perform pg_advisory_xact_lock(hashtextextended(p_submission::text,14));
 if p_operation='save_engineering' then
  cell:=(p_payload->>'celula_id')::uuid; model_type:=(p_payload->>'tipo_equipamento_id')::uuid;
  if not rm_private.workshop_cell_owned_v1(cell,office)
   or not rm_private.workshop_read_visible_v1('equipment_type',model_type,office)
   or exists(select 1 from public.rm_celula_tipos_equipamento where id=ident
    and (celula_id is distinct from cell or tipo_equipamento_id is distinct from model_type)) then
   raise exception 'Configuração indisponível nesta oficina.' using errcode='42501';
  end if;
  perform rm_private.workshop_assert_origin_v1('cell',cell,office);
  if jsonb_typeof(changes->'form_ids')='array' and exists(select 1 from jsonb_array_elements_text(changes->'form_ids') e
   where not rm_private.workshop_read_visible_v1('form_model',e::uuid,office)) then
   raise exception 'Modelo de formulário indisponível nesta oficina.' using errcode='42501';
  end if;
  if jsonb_typeof(changes->'stages')='array' and exists(select 1 from jsonb_array_elements(changes->'stages') e
   where e->>'celula_destino_id' is not null and not rm_private.workshop_cell_owned_v1((e->>'celula_destino_id')::uuid,office)) then
   raise exception 'Célula de destino indisponível nesta oficina.' using errcode='42501';
  end if;
  if jsonb_typeof(changes->'photos')='array' and exists(select 1 from jsonb_array_elements(changes->'photos') e
   where e->>'cadastro_foto_id' is not null and not rm_private.workshop_engineering_title_v1((e->>'cadastro_foto_id')::uuid,office,cell)
    and not exists(select 1 from public.rm_fotos f where f.id=(e->>'id')::uuid and f.celula_tipo_equipamento_id=ident
     and f.projeto_id is null and f.celula_projeto_id is null and not f.lixeira
     and e=jsonb_build_object('id',f.id,'cadastro_foto_id',f.cadastro_foto_id,'numero',f.numero,'descricao',f.descricao)
     and rm_private.workshop_engineering_title_v1(f.cadastro_foto_id,office))) then
   raise exception 'Título de foto indisponível para esta etapa.' using errcode='42501';
  end if;
 else
  perform pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17));
  select * into recorded from rm_private.engineering_photo_title_scope where title_id=ident;
  if p_operation='save_photo_title' and changes?'celula_id' then
   cell:=(changes->>'celula_id')::uuid;
   if cell is not null then perform rm_private.workshop_assert_origin_v1('cell',cell,office);end if;
  end if;
  if recorded.title_id is not null then
   if recorded.workshop_id<>office or (recorded.cell_id is not null and not rm_private.workshop_cell_owned_v1(recorded.cell_id,office))
    or (p_operation='save_photo_title' and changes?'celula_id' and cell is distinct from recorded.cell_id)
    or (p_operation='save_photo_title' and not exists(select 1 from public.rm_cadastro_fotos where id=ident)) then
    raise exception 'Título de foto indisponível nesta oficina.' using errcode='42501';
   end if;
  elsif p_operation='delete_photo_title' or p_payload->'expected_updated_at' is distinct from 'null'::jsonb
   or exists(select 1 from public.rm_cadastro_fotos where id=ident) then
   raise exception 'Título de foto indisponível nesta oficina.' using errcode='42501';
  end if;
 end if;
 result:=rm_private.web_mutate_form_review_workshop_v1(p_submission,p_operation,p_payload);
 if p_operation='save_photo_title' and recorded.title_id is null then
  insert into rm_private.engineering_photo_title_scope(title_id,workshop_id,cell_id) values(ident,office,cell);
 elsif p_operation='save_engineering' then
  result:=jsonb_set(result,'{snapshot}',rm_private.workshop_engineering_entry_v1(ident,office,result->'snapshot'),false);
 end if;
 delete from rm_private.gantt_workshop_write_permits where submission_id=p_submission and expires_at>clock_timestamp();
 if not found then raise exception 'A confirmação de oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
 return result;
exception when invalid_text_representation then
 raise exception 'Identificador de engenharia inválido.' using errcode='22023';
end
$$;

revoke all on function rm_private.activate_engineering_workshops_v1(bigint),
 rm_private.workshop_engineering_title_v1(uuid,uuid,uuid),rm_private.workshop_engineering_entry_v1(uuid,uuid,jsonb),
 rm_private.workshop_engineering_read_v1(text,jsonb,uuid),rm_private.web_mutate_engineering_workshop_v1(uuid,text,jsonb),
 rm_private.guard_engineering_photo_workshop_v1()
 from public,anon,authenticated,service_role;

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell','save_project_route','manage_project_route_cell','assign_form_reviewer',
  'save_capacity_resource','save_capacity_bookings','manage_cell_availability','save_cell_queue','review_execution_session',
  'save_engineering','save_photo_title','delete_photo_title'));
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot','cell_availability','cell_queue','planning_load',
  'execution_snapshot','engineering_matrix','engineering_entry','engineering_choices','photo_title_list','photo_title_entry'));

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 read_issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 target constant text:='return rm_private.web_mutate_form_review_workshop_v1(p_client_submission_id,p_operation,p_payload);';
 read_tail constant text:='''execution_snapshot'')';
 dispatch constant text:='  when ''execution_snapshot'' then rm_private.workshop_execution_snapshot_v1(p_args,permit.workshop_id)';
 engineering_reads constant text:='''engineering_matrix'',''engineering_entry'',''engineering_choices'',''photo_title_list'',''photo_title_entry''';
 old_operations text;
begin
 old_operations:=substring(issuer from 'p_operation not in\([^)]*\)');
 if old_operations is null or strpos(old_operations,'review_execution_session')=0
  or array_length(string_to_array(read_issuer,read_tail),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2
  or array_length(string_to_array(writer,target),1) is distinct from 2 then
  raise exception 'Unexpected engineering workshop contract';
 end if;
 issuer:=replace(issuer,'public.rm_sso_gantt_workshop_permit_v1(','public.rm_sso_engineering_workshop_permit_v1(');
 issuer:=replace(issuer,old_operations,'p_operation not in(''save_engineering'',''save_photo_title'',''delete_photo_title'')');
 execute replace(issuer,'''em.planning.manage''','''em.engineering.manage''');
 execute replace(read_issuer,read_tail,'''execution_snapshot'','||engineering_reads||')');
 execute replace(reader,dispatch,dispatch||chr(10)||
  (select string_agg('  when '||quote_literal(resource)||
   ' then rm_private.workshop_engineering_read_v1(p_resource,p_args,permit.workshop_id)',chr(10))
   from unnest(array['engineering_matrix','engineering_entry','engineering_choices','photo_title_list','photo_title_entry']) resource));
 execute replace(writer,target,'return rm_private.web_mutate_engineering_workshop_v1(p_client_submission_id,p_operation,p_payload);');
end
$extend$;
revoke all on function public.rm_sso_engineering_workshop_permit_v1(text,uuid,text,jsonb,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_engineering_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

notify pgrst,'reload schema';
commit;

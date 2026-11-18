-- Independent catalog ownership. No personal grants, login change or activation
-- of full isolation. Existing content is never copied or reassigned here.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

create table rm_private.workshop_catalog_adoption (
 singleton boolean primary key default true check(singleton),
 workshop_id uuid not null references rm_private.workshop_references(id),
 policy_sha256 text not null check(policy_sha256='f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff'),
 counts jsonb not null,
 recorded_at timestamptz not null default clock_timestamp(),
 database_actor text not null default session_user
);
create table rm_private.workshop_catalog_ownership (
 object_kind text not null check(object_kind in('client','equipment_type','form_model')),
 object_id uuid not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 adoption boolean references rm_private.workshop_catalog_adoption(singleton) check(adoption),
 captured_at timestamptz not null default clock_timestamp(),
 database_actor text not null default session_user,
 primary key(object_kind,object_id)
 -- No FK to the disposable business object: original ownership survives deletion.
);
create index workshop_catalog_by_office on rm_private.workshop_catalog_ownership(workshop_id,object_kind,object_id);
create table rm_private.workshop_catalog_retirements (
 object_kind text not null,object_id uuid not null,
 retired_at timestamptz not null default clock_timestamp(),
 database_actor text not null default session_user,
 primary key(object_kind,object_id),
 foreign key(object_kind,object_id) references rm_private.workshop_catalog_ownership(object_kind,object_id)
);
alter table rm_private.workshop_catalog_adoption enable row level security;
alter table rm_private.workshop_catalog_ownership enable row level security;
alter table rm_private.workshop_catalog_retirements enable row level security;
revoke all on rm_private.workshop_catalog_adoption,rm_private.workshop_catalog_ownership,rm_private.workshop_catalog_retirements
 from public,anon,authenticated,service_role;
do $$declare t text;begin
 foreach t in array array['workshop_catalog_adoption','workshop_catalog_ownership','workshop_catalog_retirements'] loop
  execute format('create trigger workshop_catalog_immutable before update or delete on rm_private.%I for each row execute function rm_private.workshop_origin_immutable_v1()',t);
  execute format('create trigger workshop_catalog_no_truncate before truncate on rm_private.%I for each statement execute function rm_private.workshop_origin_immutable_v1()',t);
 end loop;
end$$;

-- Explicit direct rules only. Contacts/questions inherit their parent later;
-- these rules do not classify other catalogs, files or user identities.
create function rm_private.workshop_catalog_relations_v1()
returns table(schema_name text,table_name text,left_kind text,left_column text,right_kind text,right_column text,right_array boolean)
language sql immutable set search_path='' as $$
 values
 ('public','rm_projetos','project','id','client','cliente_id',false),
 ('public','rm_projetos','project','id','equipment_type','tipo_equipamento_id',false),
 ('public','rm_projetos','client','cliente_id','equipment_type','tipo_equipamento_id',false),
 ('public','rm_equipamentos','project','projeto_id','equipment_type','tipo_equipamento_id',false),
 ('public','rm_registros_formulario','project','projeto_id','form_model','form_id',false),
 ('public','rm_registros_formulario','project','projeto_id','client','empresa_id',false),
 ('public','rm_registros_formulario','cell','celula_id','form_model','form_id',false),
 ('public','rm_registros_formulario','cell','celula_id','client','empresa_id',false),
 ('public','rm_registros_formulario','form_model','form_id','client','empresa_id',false),
 ('public','rm_aprovacoes_registro','project','projeto_id','form_model','form_id',false),
 ('public','rm_aprovacoes_registro','cell','celula_id','form_model','form_id',false),
 ('public','rm_respostas_temp','project','projeto_id','form_model','form_id',false),
 ('public','rm_respostas_temp','project','projeto_id','client','empresa_id',false),
 ('public','rm_respostas_temp','form_model','form_id','client','empresa_id',false),
 ('public','rm_propostas_controle','project','projeto_id','client','cliente_id',false),
 ('public','rm_propostas_budgetarias','project','projeto_id','client','cliente_id',false),
 ('public','rm_ordens_servico','project','projeto_id','client','cliente_id',false),
 ('public','rm_celula_tipos_equipamento','cell','celula_id','equipment_type','tipo_equipamento_id',false),
 ('public','rm_form_reviewer_assignments','project','projeto_id','form_model','form_id',false),
 ('public','rm_form_reviewer_assignments','cell','celula_id','form_model','form_id',false),
 ('rm_private','project_route_instances','project','projeto_id','equipment_type','tipo_equipamento_id',false),
 ('public','rm_form_template_drafts','form_model','source_form_id','form_model','published_form_id',false),
 ('public','rm_forms','form_model','id','cell','celulas_ids',true);
$$;

create function rm_private.workshop_catalog_scope_v1(p_kind text,p_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare office uuid;origin_office uuid;
begin
 if p_id is null then return null;end if;
 if p_kind in('project','cell') then
  if p_kind='project' then select workshop_id into office from rm_private.workshop_project_ownership where id=p_id;
  else select workshop_id into office from rm_private.workshop_cell_ownership where cell_id=p_id;end if;
  select workshop_id into origin_office from rm_private.workshop_object_origins where object_kind=p_kind and object_id=p_id;
  if exists(select 1 from rm_private.workshop_origin_retirements where object_kind=p_kind and object_id=p_id) then
   raise exception using errcode='PT410',message='A origem foi encerrada. Preserve o registro para conferência.';end if;
  if office is distinct from origin_office then raise exception using errcode='PT409',message='Origem sem propriedade ativa comprovada.';end if;
 elsif p_kind in('client','equipment_type','form_model') then
  select workshop_id into office from rm_private.workshop_catalog_ownership where object_kind=p_kind and object_id=p_id;
  if exists(select 1 from rm_private.workshop_catalog_retirements where object_kind=p_kind and object_id=p_id) then
   raise exception using errcode='PT410',message='A origem do cadastro foi encerrada. Preserve o registro para conferência.';end if;
 else raise exception using errcode='22023',message='Tipo de origem inválido.';end if;
 return office;
end;
$$;

create function rm_private.workshop_catalog_pair_v1(p_left_kind text,p_left_id uuid,p_right_kind text,p_right_id uuid)
returns void language plpgsql set search_path='' as $$
declare k text;l uuid;r uuid;
begin
 if p_left_id is null or p_right_id is null then return;end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Reinicie a transação para conferir a oficina atual.';end if;
 for k in select distinct key from(values
  (case when p_left_kind in('project','cell') then 'em:workshop-origin:v1:' else 'em:workshop-catalog:v1:' end||p_left_kind||':'||p_left_id),
  (case when p_right_kind in('project','cell') then 'em:workshop-origin:v1:' else 'em:workshop-catalog:v1:' end||p_right_kind||':'||p_right_id))v(key) order by key loop
  if not pg_try_advisory_xact_lock_shared(hashtextextended(k,0)) then
   raise exception using errcode='PT409',message='A oficina do cadastro está sendo conferida. Reenvie a mesma operação.';end if;
 end loop;
 l:=rm_private.workshop_catalog_scope_v1(p_left_kind,p_left_id);
 r:=rm_private.workshop_catalog_scope_v1(p_right_kind,p_right_id);
 if l is not null and r is not null and l<>r then
  raise exception using errcode='PT409',message='Cadastros de oficinas diferentes não podem ser vinculados.';end if;
end;
$$;

create function rm_private.workshop_catalog_guard_reference_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare rule record;payload jsonb:=to_jsonb(new);left_id uuid;right_id uuid;
begin
 if tg_op not in('INSERT','UPDATE') then raise exception using errcode='42501',message='Origem do vínculo inválida.';end if;
 for rule in select * from rm_private.workshop_catalog_relations_v1() where schema_name=tg_table_schema and table_name=tg_table_name loop
  left_id:=(payload->>rule.left_column)::uuid;
  if rule.right_array then
   for right_id in select value::uuid from jsonb_array_elements_text(payload->rule.right_column) loop
    perform rm_private.workshop_catalog_pair_v1(rule.left_kind,left_id,rule.right_kind,right_id);
   end loop;
  else
   perform rm_private.workshop_catalog_pair_v1(rule.left_kind,left_id,rule.right_kind,(payload->>rule.right_column)::uuid);
  end if;
 end loop;
 return new;
end;
$$;

-- BEFORE validates a catalog assignment. AFTER checks references using the
-- now-visible mapping; project/cell assignments join the same check AFTER 055.
create function rm_private.workshop_catalog_guard_assignment_v1()
returns trigger language plpgsql set search_path='' as $$
declare kind text;object_key uuid;rule record;pair record;predicate text;from_sql text;right_expr text;business_table text;
begin
 if tg_table_schema<>'rm_private' then raise exception using errcode='42501',message='Origem da classificação inválida.';end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Reinicie a transação para conferir a oficina atual.';end if;
 if tg_table_name='workshop_catalog_ownership' then kind:=new.object_kind;object_key:=new.object_id;
 elsif tg_table_name='workshop_project_ownership' then kind:='project';object_key:=new.id;
 elsif tg_table_name='workshop_cell_ownership' then kind:='cell';object_key:=new.cell_id;
 else raise exception using errcode='42501',message='Origem da classificação inválida.';end if;
 if tg_when='BEFORE' then
  business_table:=case kind when 'client' then 'rm_clientes' when 'equipment_type' then 'rm_tipos_equipamento' when 'form_model' then 'rm_forms' end;
  if business_table is null then raise exception using errcode='22023',message='Tipo de cadastro inválido.';end if;
  if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-catalog:v1:'||kind||':'||object_key,0)) then
   raise exception using errcode='PT409',message='A origem do cadastro está sendo conferida. Reenvie a mesma operação.';end if;
  if exists(select 1 from rm_private.workshop_catalog_retirements where object_kind=kind and object_id=object_key) then
   raise exception using errcode='PT410',message='A origem do cadastro foi encerrada.';end if;
  execute format('select id from public.%I where id=$1 for key share nowait',business_table) into object_key using object_key;
  if object_key is null then raise exception using errcode='23503',message='Cadastro original não encontrado.';end if;
  return new;
 end if;
 for rule in select * from rm_private.workshop_catalog_relations_v1() where left_kind=kind or right_kind=kind loop
  right_expr:=case when rule.right_array then 'a.id' else format('x.%I',rule.right_column) end;
  from_sql:=format('%I.%I x',rule.schema_name,rule.table_name)||case when rule.right_array then format(' cross join lateral unnest(x.%I) a(id)',rule.right_column) else '' end;
  predicate:=case when rule.left_kind=kind then format('x.%I=$1',rule.left_column) else 'false' end||' or '||
   case when rule.right_kind=kind then right_expr||'=$1' else 'false' end;
  for pair in execute format('select distinct x.%I as l,%s as r from %s where (%s)',rule.left_column,right_expr,from_sql,predicate) using object_key loop
   perform rm_private.workshop_catalog_pair_v1(rule.left_kind,pair.l,rule.right_kind,pair.r);
  end loop;
 end loop;
 return new;
exception when lock_not_available then raise exception using errcode='PT409',message='O cadastro está sendo alterado. Reenvie a mesma operação.';
end;
$$;

create function rm_private.workshop_catalog_guard_lifecycle_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare kind text;object_key uuid;
begin
 if tg_table_schema<>'public' or tg_table_name not in('rm_clientes','rm_tipos_equipamento','rm_forms') then
  raise exception using errcode='42501',message='Origem do cadastro inválida.';end if;
 kind:=case tg_table_name when 'rm_clientes' then 'client' when 'rm_tipos_equipamento' then 'equipment_type' else 'form_model' end;
 if tg_op='UPDATE' and new.id=old.id then return new;end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Reinicie a transação para conferir a origem do cadastro.';end if;
 if tg_op='UPDATE' and exists(select 1 from rm_private.workshop_catalog_ownership where object_kind=kind and object_id=old.id) then
  raise exception using errcode='PT409',message='A identidade de um cadastro classificado é imutável.';end if;
 object_key:=case when tg_op='DELETE' then old.id else new.id end;
 if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-catalog:v1:'||kind||':'||object_key,0)) then
  raise exception using errcode='PT409',message='A origem do cadastro está sendo conferida. Reenvie a mesma operação.';end if;
 if tg_op='DELETE' then
  insert into rm_private.workshop_catalog_retirements(object_kind,object_id)
   select object_kind,object_id from rm_private.workshop_catalog_ownership where object_kind=kind and object_id=object_key
   on conflict do nothing;
  return old;
 end if;
 if exists(select 1 from rm_private.workshop_catalog_retirements where object_kind=kind and object_id=object_key) then
  raise exception using errcode='PT410',message='A identidade deste cadastro foi encerrada. Preserve o envio para conferência.';end if;
 return new;
end;
$$;

create trigger workshop_catalog_assign before insert on rm_private.workshop_catalog_ownership for each row execute function rm_private.workshop_catalog_guard_assignment_v1();
create trigger workshop_catalog_references after insert on rm_private.workshop_catalog_ownership for each row execute function rm_private.workshop_catalog_guard_assignment_v1();
create trigger workshop_catalog_references after insert or update on rm_private.workshop_project_ownership for each row execute function rm_private.workshop_catalog_guard_assignment_v1();
create trigger workshop_catalog_references after insert or update on rm_private.workshop_cell_ownership for each row execute function rm_private.workshop_catalog_guard_assignment_v1();
do $$declare rule record;t text;begin
 for rule in select schema_name,table_name,string_agg(quote_ident(col),',' order by col) cols from (
  select schema_name,table_name,left_column col from rm_private.workshop_catalog_relations_v1()
  union select schema_name,table_name,right_column from rm_private.workshop_catalog_relations_v1()) s group by schema_name,table_name loop
  execute format('create trigger workshop_catalog_reference_guard before insert or update of %s on %I.%I for each row execute function rm_private.workshop_catalog_guard_reference_v1()',rule.cols,rule.schema_name,rule.table_name);
 end loop;
 foreach t in array array['rm_clientes','rm_tipos_equipamento','rm_forms'] loop
  execute format('create trigger workshop_catalog_lifecycle before insert or update or delete on public.%I for each row execute function rm_private.workshop_catalog_guard_lifecycle_v1()',t);
  execute format('create trigger workshop_catalog_no_truncate before truncate on public.%I for each statement execute function rm_private.workshop_origin_immutable_v1()',t);
 end loop;
end$$;

create function rm_private.workshop_catalog_adopt_bma_v1(p_policy_sha256 text,p_clients bigint,p_equipment_types bigint,p_form_models bigint)
returns jsonb language plpgsql set search_path='' as $$
declare receipt rm_private.workshop_catalog_adoption;office uuid;expected jsonb;rule record;
begin
 if current_user::regrole<>(select relowner from pg_class where oid='rm_private.workshop_catalog_ownership'::regclass) then
  raise exception using errcode='42501',message='Technical catalog owner required.';end if;
 if p_policy_sha256 is distinct from 'f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff'
  or p_clients is null or p_equipment_types is null or p_form_models is null or least(p_clients,p_equipment_types,p_form_models)<0 then
  raise exception using errcode='22023',message='Exact approved catalog policy and counts required.';end if;
 expected:=jsonb_build_object('clients',p_clients,'equipment_types',p_equipment_types,'form_models',p_form_models);
 perform pg_advisory_xact_lock(hashtextextended('em:catalog-adoption:v1',0));
 select a.legacy_workshop_id into office from rm_private.workshop_legacy_adoption a join rm_private.workshop_references w on w.id=a.legacy_workshop_id where w.code='BMA';
 if office is null then raise exception using errcode='PT409',message='Verified original BMA adoption required.';end if;
 select * into receipt from rm_private.workshop_catalog_adoption;
 if found then
  if receipt.workshop_id<>office or receipt.policy_sha256<>p_policy_sha256 or receipt.counts<>expected then
   raise exception using errcode='PT409',message='Catalog adoption differs from its immutable receipt.';end if;
  return jsonb_build_object('replayed',true,'counts',receipt.counts,'isolation_active',false);
 end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Fresh READ COMMITTED transaction required.';end if;
 -- The release envelope takes this same order before its preservation baseline.
 lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership in share row exclusive mode;
 for rule in select distinct schema_name,table_name from rm_private.workshop_catalog_relations_v1()
  union select 'public',unnest(array['rm_clientes','rm_tipos_equipamento']) order by 1,2 loop
  execute format('lock table %I.%I in share row exclusive mode',rule.schema_name,rule.table_name);
 end loop;
 lock table rm_private.workshop_catalog_adoption,rm_private.workshop_catalog_ownership,rm_private.workshop_catalog_retirements in share row exclusive mode;
 if exists(select 1 from rm_private.workshop_catalog_ownership) or exists(select 1 from rm_private.workshop_catalog_retirements)
  or(select count(*) from public.rm_clientes)<>p_clients or(select count(*) from public.rm_tipos_equipamento)<>p_equipment_types or(select count(*) from public.rm_forms)<>p_form_models then
  raise exception using errcode='PT409',message='Catalogs changed; review counts and preserve all records.';end if;
 insert into rm_private.workshop_catalog_adoption(workshop_id,policy_sha256,counts) values(office,p_policy_sha256,expected);
 insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id,adoption)
  select 'client',id,office,true from public.rm_clientes union all
  select 'equipment_type',id,office,true from public.rm_tipos_equipamento union all
  select 'form_model',id,office,true from public.rm_forms;
 return jsonb_build_object('replayed',false,'counts',expected,'isolation_active',false);
end;
$$;

create function rm_private.workshop_catalog_readiness_v1()
returns jsonb language plpgsql stable set search_path='' as $$
declare kind text;t text;n bigint;assigned bigint;rows jsonb:='[]';rule record;counts jsonb;edges jsonb:='[]';right_expr text;from_sql text;
 conflicts bigint:=0;pending bigint:=0;
begin
 foreach kind in array array['client','equipment_type','form_model'] loop
  t:=case kind when 'client' then 'rm_clientes' when 'equipment_type' then 'rm_tipos_equipamento' else 'rm_forms' end;
  execute format('select count(*),count(o.object_id) filter(where r.object_id is null) from public.%I x left join rm_private.workshop_catalog_ownership o on o.object_kind=$1 and o.object_id=x.id left join rm_private.workshop_catalog_retirements r using(object_kind,object_id)',t) into n,assigned using kind;
  rows:=rows||jsonb_build_array(jsonb_build_object('kind',kind,'total',n,'classified',assigned,'pending',n-assigned));
 end loop;
 for rule in select * from rm_private.workshop_catalog_relations_v1() order by schema_name,table_name,left_column,right_column loop
  right_expr:=case when rule.right_array then 'a.id' else format('x.%I',rule.right_column) end;
  from_sql:=format('%I.%I x',rule.schema_name,rule.table_name)||case when rule.right_array then format(' cross join lateral unnest(x.%I) a(id)',rule.right_column) else '' end;
  -- Diagnostics do not call the refusing scope helper: retired references must
  -- remain countable for reconciliation rather than hide the entire report.
  execute format($q$with edges as(select x.%I l,%s r from %s),scopes as(
   select e.*,case $1 when 'project' then p.workshop_id when 'cell' then c.workshop_id else o.workshop_id end lo,
    case $2 when 'project' then rp.workshop_id when 'cell' then rc.workshop_id else ro.workshop_id end rr
   from edges e left join rm_private.workshop_project_ownership p on $1='project' and p.id=e.l
   left join rm_private.workshop_cell_ownership c on $1='cell' and c.cell_id=e.l
   left join rm_private.workshop_catalog_ownership o on o.object_kind=$1 and o.object_id=e.l
   left join rm_private.workshop_project_ownership rp on $2='project' and rp.id=e.r
   left join rm_private.workshop_cell_ownership rc on $2='cell' and rc.cell_id=e.r
   left join rm_private.workshop_catalog_ownership ro on ro.object_kind=$2 and ro.object_id=e.r where e.l is not null and e.r is not null)
   select jsonb_build_object('pairs',count(*),'conflicts',count(*) filter(where lo is not null and rr is not null and lo<>rr),'pending',count(*) filter(where lo is null or rr is null)) from scopes$q$,
   rule.left_column,right_expr,from_sql) into counts using rule.left_kind,rule.right_kind;
  conflicts:=conflicts+(counts->>'conflicts')::bigint;pending:=pending+(counts->>'pending')::bigint;
  edges:=edges||jsonb_build_array(to_jsonb(rule)||counts);
 end loop;
 return jsonb_build_object('format_version',1,'isolation_active',false,'catalogs',rows,'rules',edges,'conflicts',conflicts,'pending_references',pending,
  'adoption_recorded',exists(select 1 from rm_private.workshop_catalog_adoption),'retirements',(select count(*) from rm_private.workshop_catalog_retirements));
end;
$$;
revoke all on function rm_private.workshop_catalog_relations_v1(),rm_private.workshop_catalog_scope_v1(text,uuid),
 rm_private.workshop_catalog_pair_v1(text,uuid,text,uuid),rm_private.workshop_catalog_guard_reference_v1(),
 rm_private.workshop_catalog_guard_assignment_v1(),rm_private.workshop_catalog_guard_lifecycle_v1(),
 rm_private.workshop_catalog_adopt_bma_v1(text,bigint,bigint,bigint),rm_private.workshop_catalog_readiness_v1()
 from public,anon,authenticated,service_role;
commit;

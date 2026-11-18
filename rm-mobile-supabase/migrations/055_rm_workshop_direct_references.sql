-- Direct project/cell integrity, not tenant authorization or full isolation.
-- Unknown ownership stays pending. No row, identity or offline payload is moved.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership,
 public.rm_celulas_projeto,public.rm_aprovacoes_etapas,public.rm_aprovacoes_registro,
 public.rm_comentarios,public.rm_form_reviewer_assignments,public.rm_fotos,
 public.rm_logs_aprovacao,public.rm_registros_formulario,public.rm_web_stage_decisions
 in share row exclusive mode;

create function rm_private.workshop_reference_relations_v1()
returns table(table_name text,project_column text,cell_column text)
language sql immutable set search_path='' as $$
 values('rm_celulas_projeto','projeto_id','celula_id'),
 ('rm_aprovacoes_etapas','projeto_id','celula_origem_id'),
 ('rm_aprovacoes_etapas','projeto_id','celula_destino_id'),
 ('rm_aprovacoes_registro','projeto_id','celula_id'),
 ('rm_comentarios','projeto_id','celula_id'),
 ('rm_form_reviewer_assignments','projeto_id','celula_id'),
 ('rm_fotos','projeto_id','celula_id'),
 ('rm_logs_aprovacao','projeto_id','celula_id'),
 ('rm_registros_formulario','projeto_id','celula_id'),
 ('rm_web_stage_decisions','projeto_id','celula_id');
$$;

create function rm_private.workshop_reference_pair_v1(p_project uuid,p_cell uuid,
 p_pending_kind text default null,p_pending_workshop uuid default null)
returns void language plpgsql set search_path='' as $$
declare project_office uuid;cell_office uuid;origin_project uuid;origin_cell uuid;lock_key text;
begin
 -- Nullable legacy/template references do not imply a pair or ownership.
 if p_project is null or p_cell is null then return;end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Reinicie a transação para conferir a oficina atual. O registro não foi descartado.';end if;
 if (p_pending_kind is null)<>(p_pending_workshop is null) or
  (p_pending_kind is not null and p_pending_kind not in('project','cell')) then
  raise exception using errcode='22023',message='Contexto interno de classificação inválido.';end if;
 -- Share 054's lock keys: ordinary references coexist; classification and
 -- retirement hold exclusive locks. Nonblocking acquisition avoids a wait
 -- cycle with FK rows, deletion gateways and inverse classifications.
 for lock_key in select k from(values('em:workshop-origin:v1:project:'||p_project::text),
  ('em:workshop-origin:v1:cell:'||p_cell::text)) s(k) order by k loop
  if not pg_try_advisory_xact_lock_shared(hashtextextended(lock_key,0)) then
   raise exception using errcode='PT409',message='A oficina está sendo conferida. Reenvie a mesma operação.';end if;
 end loop;
 select workshop_id into project_office from rm_private.workshop_project_ownership where id=p_project;
 select workshop_id into cell_office from rm_private.workshop_cell_ownership where cell_id=p_cell;
 select workshop_id into origin_project from rm_private.workshop_object_origins where object_kind='project' and object_id=p_project;
 select workshop_id into origin_cell from rm_private.workshop_object_origins where object_kind='cell' and object_id=p_cell;
 if p_pending_kind='project' then
  if project_office is not null and project_office<>p_pending_workshop then
   raise exception using errcode='PT409',message='Vínculo incompatível com a oficina de origem.';end if;
  project_office:=p_pending_workshop;
 elsif p_pending_kind='cell' then
  if cell_office is not null and cell_office<>p_pending_workshop then
   raise exception using errcode='PT409',message='Vínculo incompatível com a oficina de origem.';end if;
  cell_office:=p_pending_workshop;
 end if;
 if exists(select 1 from rm_private.workshop_origin_retirements where
  (object_kind='project' and object_id=p_project) or(object_kind='cell' and object_id=p_cell)) then
  raise exception using errcode='PT410',message='A origem do registro foi encerrada. Preserve o envio para conferência.';end if;
 if project_office is distinct from origin_project or cell_office is distinct from origin_cell or
  (project_office is not null and cell_office is not null and project_office<>cell_office) then
  raise exception using errcode='PT409',message='Vínculo incompatível com a oficina de origem. Preserve o registro para conferência.';end if;
 -- One or both roots may still be unknown. This does not assign an office or
 -- authorize reads. Later classification must also recheck all existing pairs.
end;
$$;

create function rm_private.workshop_guard_reference_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare relation record;payload jsonb:=to_jsonb(new);matched boolean:=false;
begin
 if tg_table_schema<>'public' or tg_op not in('INSERT','UPDATE') then
  raise exception using errcode='42501',message='Origem do vínculo inválida.';end if;
 for relation in select * from rm_private.workshop_reference_relations_v1() where table_name=tg_table_name loop
  matched:=true;
  perform rm_private.workshop_reference_pair_v1((payload->>relation.project_column)::uuid,(payload->>relation.cell_column)::uuid);
 end loop;
 if not matched then raise exception using errcode='42501',message='Origem do vínculo inválida.';end if;
 return new;
end;
$$;

create function rm_private.workshop_guard_root_references_v1()
returns trigger language plpgsql set search_path='' as $$
declare kind text;root_id uuid;relation record;pair record;root_column text;
begin
 if tg_table_schema<>'rm_private' or tg_table_name not in('workshop_project_ownership','workshop_cell_ownership')
  or tg_op not in('INSERT','UPDATE') then raise exception using errcode='42501',message='Origem da classificação inválida.';end if;
 if current_setting('transaction_isolation') not in('read committed','read uncommitted') then
  raise exception using errcode='PT409',message='Reinicie a transação para conferir a oficina atual. O registro não foi descartado.';end if;
 if tg_table_name='workshop_project_ownership' then kind:='project';root_id:=new.id;
 else kind:='cell';root_id:=new.cell_id;end if;
 -- 054's alphabetically earlier origin trigger has locked and recorded this
 -- root. Supply only that pending root's real NEW office, before FK insertion.
 for relation in select * from rm_private.workshop_reference_relations_v1() loop
  root_column:=case when kind='project' then relation.project_column else relation.cell_column end;
  for pair in execute format('select distinct %I as project_id,%I as cell_id from public.%I where %I=$1 and %I is not null and %I is not null',
   relation.project_column,relation.cell_column,relation.table_name,root_column,relation.project_column,relation.cell_column) using root_id loop
   perform rm_private.workshop_reference_pair_v1(pair.project_id,pair.cell_id,kind,new.workshop_id);
  end loop;
 end loop;
 return new;
end;
$$;

create trigger workshop_project_reference_guard before insert or update on rm_private.workshop_project_ownership
 for each row execute function rm_private.workshop_guard_root_references_v1();
create trigger workshop_cell_reference_guard before insert or update on rm_private.workshop_cell_ownership
 for each row execute function rm_private.workshop_guard_root_references_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_celulas_projeto
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_origem_id,celula_destino_id on public.rm_aprovacoes_etapas
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_aprovacoes_registro
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_comentarios
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_form_reviewer_assignments
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_fotos
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_logs_aprovacao
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_registros_formulario
 for each row execute function rm_private.workshop_guard_reference_v1();
create trigger workshop_direct_reference_guard before insert or update of projeto_id,celula_id on public.rm_web_stage_decisions
 for each row execute function rm_private.workshop_guard_reference_v1();

create function rm_private.workshop_reference_readiness_v1()
returns jsonb language plpgsql stable set search_path='' as $$
declare relation record;counts jsonb;rows jsonb:='[]';conflicts bigint:=0;pending bigint:=0;retired bigint:=0;
begin
 for relation in select * from rm_private.workshop_reference_relations_v1() order by table_name,cell_column loop
  execute format($q$
   select jsonb_build_object('pairs',count(*),
    'conflicts',count(*) filter(where p.workshop_id is not null and c.workshop_id is not null and p.workshop_id<>c.workshop_id),
    'pending',count(*) filter(where p.workshop_id is null or c.workshop_id is null),
    'retired',count(*) filter(where exists(select 1 from rm_private.workshop_origin_retirements r where
     (r.object_kind='project' and r.object_id=x.%I) or(r.object_kind='cell' and r.object_id=x.%I))))
   from public.%I x left join rm_private.workshop_project_ownership p on p.id=x.%I
   left join rm_private.workshop_cell_ownership c on c.cell_id=x.%I where x.%I is not null and x.%I is not null
  $q$,relation.project_column,relation.cell_column,relation.table_name,relation.project_column,relation.cell_column,relation.project_column,relation.cell_column) into counts;
  conflicts:=conflicts+(counts->>'conflicts')::bigint;pending:=pending+(counts->>'pending')::bigint;retired:=retired+(counts->>'retired')::bigint;
  rows:=rows||jsonb_build_array(jsonb_build_object('table',relation.table_name,'project_column',relation.project_column,'cell_column',relation.cell_column)||counts);
 end loop;
 return jsonb_build_object('format_version',1,'direct_reference_guard_enabled',true,'isolation_active',false,
  'rules',rows,'conflicts',conflicts,'pending',pending,'retired',retired);
end;
$$;
revoke all on function rm_private.workshop_reference_relations_v1(),
 rm_private.workshop_reference_pair_v1(uuid,uuid,text,uuid),rm_private.workshop_guard_reference_v1(),
 rm_private.workshop_guard_root_references_v1(),rm_private.workshop_reference_readiness_v1()
 from public,anon,authenticated,service_role;
do $$begin
 if(rm_private.workshop_reference_readiness_v1()->>'conflicts')::bigint<>0 then
  raise exception 'Existing cross-workshop references require explicit review; no rows were changed.';end if;
end$$;
commit;

-- The status belongs to Projeto + Celula, never to the project itself.
-- Reuse the current status writer and plan_cell receipt/audit contracts.
begin;

insert into public.rm_option_sets(option_set_key,option_key,bubble_display,attributes,sort_order) values
 ('status_cel_proj','aguardando_coleta','Aguardando coleta','{"ordem0":11}',11),
 ('status_cel_proj','coletado','Coletado','{"ordem0":12}',12);

-- Keep the exact existing mobile validation, finalization effects and queue
-- contract in one owner-only writer. The operational wrapper retains access,
-- context and lock checks; the planner already has its own current permission.
do $migration$ declare d text;access_line text:='  perform rm_private.assert_cell_access(p_operator,cp.celula_id);';
 start_marker text:='  next_status:=p_status::public.rm_status_cel_proj_enum;';
 end_marker text:='  return jsonb_build_object(''celula_projeto_id'',cp.id,''projeto_id'',cp.projeto_id,''status'',next_status);';
 start_at integer;end_at integer;shared text;
begin
 d:=pg_get_functiondef('rm_private.update_cell_status_v1(uuid,uuid,text)'::regprocedure);
 if strpos(d,access_line)=0 or strpos(d,start_marker)=0 or strpos(d,end_marker)=0 then raise exception 'Unexpected existing cell status contract';end if;
 shared:=replace(d,'FUNCTION rm_private.update_cell_status_v1(','FUNCTION rm_private.apply_cell_status_v1(');
 if shared=d then raise exception 'Unexpected status function identity';end if;
 execute replace(shared,access_line,'  -- Access is checked by the operational or planning gateway.');
 start_at:=strpos(d,start_marker);end_at:=strpos(d,end_marker)+length(end_marker);
 d:=substring(d,1,start_at-1)||'  return rm_private.apply_cell_status_v1(p_operator,p_cell_project,p_status);'||substring(d,end_at);
 execute d;
end $migration$;
revoke all on function rm_private.apply_cell_status_v1(uuid,uuid,text) from public,anon,authenticated,service_role;

-- Preserve all previous plan_cell validation, exact versions, authorization,
-- SSO/MFA and retry behavior. The original implementation still owns receipts.
do $migration$ declare d text;needle text;replacement text;
begin
 d:=pg_get_functiondef('rm_private.web_mutate_project_core_v1(uuid,text,jsonb)'::regprocedure);
 needle:='    allowed := array[''data_inicio'',''data_limite''';
 if strpos(d,needle)=0 then raise exception 'Unexpected planning allowlist';end if;
 d:=replace(d,needle,'    allowed := array[''status'',''data_inicio'',''data_limite''');
 needle:='    before_record := case when is_new then null else to_jsonb(cell) end;';
 if strpos(d,needle)=0 then raise exception 'Unexpected planning preflight';end if;
 replacement:=$patch$
    if changes?'status' and(jsonb_typeof(changes->'status') is distinct from 'string' or changes->>'status'='') then
      raise exception 'Selecione um status válido para a célula.' using errcode='22023';end if;
    if is_new and changes->>'status'='retornado' then
      raise exception 'Retornado não é um status inicial de alocação.' using errcode='22023';end if;
$patch$;
 d:=replace(d,needle,replacement||needle);
 needle:='        status_historico,visibilidade,forms_ids,modified_by_id)';
 if strpos(d,needle)=0 then raise exception 'Unexpected allocation initial fields';end if;
 d:=replace(d,needle,'        status,status_historico,visibilidade,forms_ids,modified_by_id)');
 needle:='        array[''pendente'']::public.rm_status_cel_proj_enum[],coalesce(template.visibilidade,false),template_forms,actor.id)';
 if strpos(d,needle)=0 then raise exception 'Unexpected allocation initial status';end if;
 d:=replace(d,needle,'        coalesce((changes->>''status'')::public.rm_status_cel_proj_enum,''pendente''),
        array[coalesce((changes->>''status'')::public.rm_status_cel_proj_enum,''pendente'')],coalesce(template.visibilidade,false),template_forms,actor.id)');
 needle:='    record_id := cell.id;';
 if strpos(d,needle)=0 then raise exception 'Unexpected planning result';end if;
 replacement:=$patch$
    if changes?'status' and(cell.status is distinct from next_cell.status or(is_new and cell.status<>'pendente')) then
      perform rm_private.apply_cell_status_v1(actor.id,cell.id,next_cell.status::text);
      select * into cell from public.rm_celulas_projeto where id=cell.id;
    end if;
$patch$;
 d:=replace(d,needle,replacement||needle);
 execute d;
end $migration$;

notify pgrst,'reload schema';
commit;

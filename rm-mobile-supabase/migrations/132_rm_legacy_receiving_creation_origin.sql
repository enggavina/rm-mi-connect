begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Only the two verified legacy branches that have just created a project
-- call this. Scoped requests register their own origin in the gateway.
create function rm_private.record_legacy_receiving_project_origin_v1(
 p_submission uuid,p_phase text,p_project uuid,p_operator uuid
) returns void language plpgsql set search_path='' as $$
declare office uuid;
begin
 if not exists(select 1 from rm_private.workshop_legacy_mobile_write_settings where singleton)
  or exists(select 1 from rm_private.mobile_receiving_workshop_permits p
   where p.submission_id=p_submission and p.phase=p_phase and p.auth_user_id=auth.uid()
     and p.operator_id=p_operator and p.gateway_xid=pg_current_xact_id_if_assigned()) then
  return;
 end if;

 -- Serialize with retirement of the legacy tablet during a verified transfer.
 select a.workshop_id into office from rm_private.workshop_legacy_catalog_access a
 where a.singleton and a.auth_user_id=auth.uid() and a.revoked_at is null
 for share;
 if office is null or office is distinct from rm_private.workshop_legacy_operator_office_v1(p_operator) then
  raise exception 'Confirme a oficina do recebimento. O protocolo continua preservado.' using errcode='42501';
 end if;
 insert into rm_private.workshop_project_ownership(id,workshop_id) values(p_project,office);
end
$$;
revoke all on function rm_private.record_legacy_receiving_project_origin_v1(uuid,text,uuid,uuid)
 from public,anon,authenticated,service_role;

do $integrate$
declare
 opener text:=pg_get_functiondef('public.rm_mobile_open_receiving_v1(uuid,jsonb,text)'::regprocedure);
 completer text:=pg_get_functiondef('rm_private.mobile_mutate_before_execution_v1(uuid,text,jsonb,text)'::regprocedure);
 trigger_body text:=pg_get_functiondef('rm_private.require_new_workshop_root_v1()'::regprocedure);
 open_marker constant text:='  params->>''p_contato'',params->>''p_proprietario'',params->>''p_eventualidades'',eq,''[]'');';
 complete_marker constant text:='        p_params->>''p_eventualidades'',coalesce(p_params->''p_equipamento'',''{}''),coalesce(p_params->''p_fotos_recebimento'',''[]''));';
 trigger_marker constant text:=' if not all_writers_guarded and auth.uid() is not null and auth.jwt()->>''role''=''authenticated'' then';
begin
 if array_length(string_to_array(opener,open_marker),1) is distinct from 2
  or array_length(string_to_array(completer,complete_marker),1) is distinct from 2
  or array_length(string_to_array(trigger_body,trigger_marker),1) is distinct from 2 then
  raise exception 'Unexpected receiving creation boundary';
 end if;
 execute replace(opener,open_marker,open_marker||$patch$
 perform rm_private.record_legacy_receiving_project_origin_v1(p_client_submission_id,'open',(result->>'projeto_id')::uuid,d.operator_id);
$patch$);
 execute replace(completer,complete_marker,complete_marker||$patch$
      perform rm_private.record_legacy_receiving_project_origin_v1(p_client_submission_id,'complete',(v_result->>'projeto_id')::uuid,d.operator_id);
$patch$);
 execute replace(trigger_body,trigger_marker,$patch$ if not all_writers_guarded
  and not exists(select 1 from rm_private.workshop_legacy_mobile_write_settings where singleton)
  and auth.uid() is not null and auth.jwt()->>'role'='authenticated' then$patch$);
end
$integrate$;

notify pgrst,'reload schema';
commit;

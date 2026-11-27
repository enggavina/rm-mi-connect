begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Tie the reply to the durable receipt while the gateway still holds the
-- protocol and project locks. Keep existing receipts and their replay shape.
do $confirmation$
declare
 gateway text:=pg_get_functiondef('public.rm_mobile_workshop_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 variables constant text:=' identity record; project uuid; result jsonb;';
 writer constant text:=' result:=public.rm_mobile_mutate_v1(p_client_submission_id,p_rpc_name,p_params,p_operator_token);';
 response constant text:=' return result;';
begin
 if array_length(string_to_array(gateway,variables),1) is distinct from 2
  or array_length(string_to_array(gateway,writer),1) is distinct from 2
  or array_length(string_to_array(gateway,response),1) is distinct from 2 then
  raise exception 'Unexpected offline mutation confirmation boundary';
 end if;
 gateway:=replace(gateway,variables,' identity record; project uuid; mutation_result jsonb; confirmation jsonb;');
 gateway:=replace(gateway,writer,replace(writer,'result:=','mutation_result:='));
 execute replace(gateway,response,$receipt$ select jsonb_build_object(
  'protocolo',r.client_submission_id,'operacao',r.rpc_name,'dispositivo_id',r.auth_user_id,
  'operador_id',r.operator_id,'oficina_id',permit.workshop_id,'projeto_id',project) into confirmation
 from rm_private.mobile_mutation_receipts r
 where r.client_submission_id=p_client_submission_id and r.rpc_name=p_rpc_name
  and r.auth_user_id=permit.auth_user_id and r.operator_id=permit.operator_id
  and jsonb_typeof(r.result)='object' and r.result-'idempotent_replay'<>'{}'::jsonb
  and r.result-'idempotent_replay'=mutation_result-'idempotent_replay'
  and (not (r.result?'projeto_id') or r.result->>'projeto_id'=project::text);
 if confirmation is null then
  raise exception 'A confirmação do envio está indisponível. Preserve o protocolo.' using errcode='PT503';
 end if;
 return mutation_result||jsonb_build_object('confirmacao',confirmation);$receipt$);
end
$confirmation$;

notify pgrst,'reload schema';
commit;

begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Reply with the row that accepted this request. Keep the original mutation
-- result and its stored receipt intact for already deployed Android clients.
do $confirmation$
declare
 gateway text:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 result_variable constant text:=' result jsonb;';
 row_match constant text:='  and binding.workshop_id=excluded.workshop_id;';
 response constant text:=' return result;';
begin
 if array_length(string_to_array(gateway,result_variable),1) is distinct from 2
  or array_length(string_to_array(gateway,row_match),1) is distinct from 2
  or array_length(string_to_array(gateway,response),1) is distinct from 2 then
  raise exception 'Unexpected receiving confirmation boundary';
 end if;
 gateway:=replace(gateway,result_variable,result_variable||chr(10)||' confirmation jsonb;');
 gateway:=replace(gateway,row_match,$projection$  and binding.workshop_id=excluded.workshop_id
 returning jsonb_build_object('protocolo',binding.submission_id,'oficina_id',binding.workshop_id,'fase',p_phase,
  'projeto_id',binding.project_id,'equipamento_id',binding.equipment_id) into confirmation;$projection$);
 execute replace(gateway,response,' return result||jsonb_build_object(''confirmacao'',confirmation);');
end
$confirmation$;

notify pgrst,'reload schema';
commit;

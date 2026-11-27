begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The existing readers and writer already validate the active Central context,
-- local identity, cell, project, model and exact receipt. Remove the initial
-- pilot-code restriction after the review queue has been scoped by workshop.
do $enable$
declare
 entry text:=pg_get_functiondef('public.rm_online_operation_form_entry_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid)'::regprocedure);
 writer text:=pg_get_functiondef('public.rm_online_operation_submit_form_v1(uuid,uuid,text,jsonb,uuid,uuid,uuid,uuid,text,jsonb)'::regprocedure);
 pilot constant text:=' or p_workshop_context->''workshop''->>''code'' is distinct from ''BMA''';
 note constant text:='  -- The review queue for this pilot is in BMA. Other offices retain consultation.'||chr(10);
begin
 if array_length(string_to_array(entry,'if form is null'||pilot),1) is distinct from 2
  or array_length(string_to_array(writer,'if office is null'||pilot),1) is distinct from 2
  or array_length(string_to_array(entry,note),1) is distinct from 2 then
  raise exception 'Unexpected online form pilot boundary';
 end if;
 execute replace(replace(entry,note,''),'if form is null'||pilot,'if form is null');
 execute replace(writer,'if office is null'||pilot,'if office is null');
end
$enable$;

notify pgrst,'reload schema';
commit;

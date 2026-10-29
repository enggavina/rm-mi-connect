-- PostgREST 14 retries SQLSTATE 40001 indefinitely. A stale browser version is
-- a business conflict, not a transient serialization failure: return HTTP409.
-- Preserve 014's deployed history and every other permission/validation rule.
begin;
do $$
declare definition text; old_code text := 'errcode=''40001'''; new_code text := 'errcode=''PT409'''; matches integer;
begin
  select pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure) into definition;
  matches := (length(definition)-length(replace(definition,old_code,'')))/length(old_code);
  if matches<>3 then raise exception 'Unexpected web RPC definition: expected three version guards, got %',matches; end if;
  execute replace(definition,old_code,new_code);
end $$;
notify pgrst,'reload schema';
commit;

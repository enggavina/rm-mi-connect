-- Bubble uses fractional ordering positions when inserting between questions.
-- Preserve those positions throughout the form, answer and draft lifecycle.
begin;

alter table public.rm_questoes alter column indice type numeric using indice::numeric;
alter table public.rm_itens_questoes alter column indice type numeric using indice::numeric;
alter table public.rm_respostas alter column indice type numeric using indice::numeric;
alter table public.rm_respostas_temp alter column indice type numeric using indice::numeric;

-- Replace only the two integer casts in the original procedures. CREATE OR
-- REPLACE retains the established signatures, ownership and execute grants.
-- Abort on unexpected definitions instead of silently accepting a partial fix.
do $migration$
declare
  signature text;
  old_cast text;
  new_cast text;
  definition text;
begin
  for signature, old_cast, new_cast in
    values
      ('public.rm_submit_form_inspection_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb)',
       'nullif(v_resp->>''indice'', '''')::integer',
       'nullif(v_resp->>''indice'', '''')::numeric'),
      ('public.rm_apply_bubble_webhook_v1(text,text,jsonb)',
       'nullif(p_payload->>''Indice'', '''')::integer',
       'nullif(p_payload->>''Indice'', '''')::numeric')
  loop
    definition := pg_get_functiondef(signature::regprocedure);
    if strpos(definition, old_cast) > 0 then
      execute replace(definition, old_cast, new_cast);
    elsif strpos(definition, new_cast) = 0 then
      raise exception 'Unexpected index cast in %', signature;
    end if;
  end loop;
end $migration$;

notify pgrst, 'reload schema';
commit;

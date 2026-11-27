begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- A historical option may omit its redundant form ID. The question owns the
-- option. An explicit form ID, when present, must agree with the question.
do $options$
declare
 published_at timestamptz;
begin
 select greatest(clock_timestamp(),max(updated_at) filter(where isfinite(updated_at)))+interval '1 microsecond'
  into published_at from public.rm_itens_questoes;
 -- Resend previously invisible options to existing scoped cursors without
 -- rewriting the source records or their audit timestamps.
 execute format($view$
  create view rm_private.workshop_form_options_v1 as
  select i.id,i.bubble_id,q.form_id,i.questao_id,i.indice,i.descricao,i.description,i.slug,i.created_at,
   case when i.form_id is null then greatest(i.updated_at,%L::timestamptz) else i.updated_at end updated_at,
   i.bubble_modified_at,i.sync_source
  from public.rm_itens_questoes i join public.rm_questoes q on q.id=i.questao_id
  where i.form_id is null or i.form_id=q.form_id
 $view$,published_at);
end
$options$;
revoke all on rm_private.workshop_form_options_v1 from public,anon,authenticated,service_role;

do $readers$
declare
 catalog text:=pg_get_functiondef('public.rm_mobile_workshop_catalog_v1(uuid,uuid,text,jsonb,text,timestamptz,uuid,boolean)'::regprocedure);
 detail text:=pg_get_functiondef('rm_private.workshop_form_record_detail_v1(jsonb,uuid)'::regprocedure);
 catalog_from constant text:='value from public.%I r where (%s)';
 catalog_args constant text:='projection,p_table,predicate) into result';
 detail_items constant text:=$old$  from public.rm_itens_questoes i join record r on i.form_id=r.form_id
  where i.questao_id is null or exists(select 1 from questions q where q.id=i.questao_id)$old$;
begin
 if array_length(string_to_array(catalog,catalog_from),1) is distinct from 2
  or array_length(string_to_array(catalog,catalog_args),1) is distinct from 2
  or array_length(string_to_array(detail,detail_items),1) is distinct from 2 then
  raise exception 'Unexpected workshop form option contracts';
 end if;
 catalog:=replace(catalog,catalog_from,'value from %s r where (%s)');
 execute replace(catalog,catalog_args,$source$projection,case when p_table='rm_itens_questoes' then 'rm_private.workshop_form_options_v1'
   else format('public.%I',p_table) end,predicate) into result$source$);
 execute replace(detail,detail_items,$items$  from rm_private.workshop_form_options_v1 i join questions q on q.id=i.questao_id and q.form_id=i.form_id$items$);
end
$readers$;

notify pgrst,'reload schema';
commit;

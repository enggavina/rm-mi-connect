begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Historical project attachments also include Word documents. They use the
-- same verified copy, private object and ownership contract as existing files.
alter table rm_private.workshop_archive_files drop constraint workshop_archive_files_mime_type_check;
alter table rm_private.workshop_archive_files add constraint workshop_archive_files_mime_type_check check(mime_type in(
 'application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif',
 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
update storage.buckets b set allowed_mime_types=(select array_agg(distinct m order by m)
 from unnest(b.allowed_mime_types||array['application/vnd.openxmlformats-officedocument.wordprocessingml.document']) m)
 where b.id='rm-documentos' and not b.public and b.allowed_mime_types is not null
  and not 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'=any(b.allowed_mime_types);

do $word_type$
declare
 definition text:=pg_get_functiondef('public.rm_confirm_workshop_archive_v1(uuid,text,text,text,integer)'::regprocedure);
 marker constant text:='when ''image/heif'' then ''heif'' end;';
begin
 if array_length(string_to_array(definition,marker),1) is distinct from 2 then
  raise exception 'Unexpected archive confirmation format contract';
 end if;
 execute replace(definition,marker,$type$when 'image/heif' then 'heif'
  when 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'docx' end;$type$);
end
$word_type$;
notify pgrst,'reload schema';
commit;

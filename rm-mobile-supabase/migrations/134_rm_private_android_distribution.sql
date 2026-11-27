begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('rm-aplicativo-android','rm-aplicativo-android',false,52428800,array['application/vnd.android.package-archive']);

create policy rm_android_distribution_no_direct_access on storage.objects
as restrictive for all to anon,authenticated
using (bucket_id <> 'rm-aplicativo-android') with check (bucket_id <> 'rm-aplicativo-android');

commit;

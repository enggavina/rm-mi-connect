begin;
do $test$
begin
  if not exists (
    select 1 from storage.buckets
    where id='rm-aplicativo-android' and not public and file_size_limit=52428800
      and allowed_mime_types=array['application/vnd.android.package-archive']
  ) then raise exception 'Android installer bucket must be private and limited to APKs'; end if;
end;
$test$;

-- A permissive policy elsewhere in Storage must not open the release objects.
grant usage on schema storage to anon;
grant select,insert,update,delete on storage.objects to anon,authenticated;
create policy android_test_permissive on storage.objects for all to anon,authenticated using (true) with check (true);
insert into storage.objects(bucket_id,name) values
  ('rm-aplicativo-android','installer-fixture'),('rm-documentos','ordinary-file-fixture');

set local role anon;
do $test$
begin
  if exists(select 1 from storage.objects where name='installer-fixture')
    or not exists(select 1 from storage.objects where name='ordinary-file-fixture')
  then raise exception 'Unexpected anonymous Storage scope'; end if;
end;
$test$;

set local role authenticated;
do $test$
begin
  if exists(select 1 from storage.objects where name='installer-fixture')
    or not exists(select 1 from storage.objects where name='ordinary-file-fixture')
  then raise exception 'Unexpected authenticated Storage scope'; end if;

  delete from storage.objects where name='installer-fixture';
  if found then raise exception 'Authenticated user could delete the APK'; end if;
  begin
    insert into storage.objects(bucket_id,name) values ('rm-aplicativo-android','user-apk');
    raise exception 'Authenticated user could upload an APK';
  exception when insufficient_privilege then null;
  end;
  begin
    update storage.objects set bucket_id='rm-aplicativo-android' where name='ordinary-file-fixture';
    raise exception 'Authenticated user could move an object into the APK bucket';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

reset role;
rollback;
select 'PASS: Android installer Storage denies direct access';

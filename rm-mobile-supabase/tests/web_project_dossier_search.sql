-- TEST DATABASE ONLY: scoped, stable server pagination without dossier writes.
\set ON_ERROR_STOP on
begin;
create function pg_temp.dq_key(h text,n int) returns uuid language sql immutable as $$
 select (h||'ac30000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.dq_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.dq_actor(n int) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.dq_key('1',n)::text,true);
 perform set_config('request.jwt.claims','{"aal":"aal1"}',true); end $$;
create function pg_temp.dq_reject(p_filters jsonb,wanted text,p_documents boolean default false) returns void language plpgsql as $$ declare actual text; begin
 begin
  set local role authenticated;
  if p_documents then perform public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),p_filters);
  else perform public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),p_filters); end if;
  reset role;
 exception when others then reset role; get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
 end; raise exception 'FAIL: dossier search unexpectedly succeeded';
end $$;
insert into auth.users(id) select pg_temp.dq_key('1',n) from generate_series(1,5) n;
insert into public.rm_users(id,auth_user_id,nome,matricula,perfil,status)
 select pg_temp.dq_key('2',n),pg_temp.dq_key('1',n),'Search actor '||n,'DQ-'||n,
 case n when 1 then 'administrador'::public.rm_perfil_usuario_enum when 2 then 'padr_o' when 3 then 'auditor' when 4 then 'cliente' else 'administrador' end,
 case n when 5 then 'inativo'::public.rm_status_user_enum else 'ativo' end from generate_series(1,5) n;
insert into public.rm_projetos(id,numero,status_pcp) values
 (pg_temp.dq_key('5',1),'DOSSIER-SEARCH-30','cancelado'),(pg_temp.dq_key('5',2),'DOSSIER-SEARCH-OTHER',null),
 (pg_temp.dq_key('5',3),'DOSSIER-SEARCH-EMPTY',null);
insert into public.rm_celulas(id,nome) values(pg_temp.dq_key('4',1),'Historical search cell'),(pg_temp.dq_key('4',2),'Foreign cell');
-- A historic recipient is deliberately not currently allocated; its comments
-- and filter option remain visible without recreating an operational target.
insert into public.rm_comentarios(id,projeto_id,celula_id,cadastrado_por_id,evento,created_at)
 select pg_temp.dq_key('a',n),pg_temp.dq_key('5',1),case when n%2=1 then pg_temp.dq_key('4',1) end,
 case when n%2=1 then pg_temp.dq_key('2',1) end,'Note '||n,'2026-10-30T15:00:00Z'::timestamptz from generate_series(1,53) n;
insert into public.rm_comentarios(id,projeto_id,celula_id,cadastrado_por_id,evento,created_at) values
 (pg_temp.dq_key('a',101),pg_temp.dq_key('5',1),pg_temp.dq_key('4',1),pg_temp.dq_key('2',2),'Literal 100%_* needle'' OR true','2026-10-30T03:00:00Z'),
 (pg_temp.dq_key('a',102),pg_temp.dq_key('5',1),null,null,'Previous local day','2026-10-30T02:59:59.999999Z'),
 (pg_temp.dq_key('a',103),pg_temp.dq_key('5',1),null,null,'Inclusive local end','2026-10-31T02:59:59.999999Z'),
 (pg_temp.dq_key('a',104),pg_temp.dq_key('5',1),null,null,'Following local day','2026-10-31T03:00:00Z'),
 (pg_temp.dq_key('a',200),pg_temp.dq_key('5',2),pg_temp.dq_key('4',2),pg_temp.dq_key('2',3),'Foreign secret needle','2026-10-30T15:00:00Z');
insert into public.rm_documentos(id,projeto_id,nome,arquivo_url,tipo_documento,created_by,created_at)
 select pg_temp.dq_key('b',n),pg_temp.dq_key('5',1),'Generated '||n,case when n=1 then '   ' else 'https://example.cdn.bubble.io/report.pdf' end,
 'Legacy report type',case when n%2=1 then pg_temp.dq_key('2',2) end,'2026-10-30T15:00:00Z'::timestamptz from generate_series(1,29) n;
insert into public.rm_docs(id,projeto_id,nome,descricao,arquivo_url,tipo_arquivo,status,data_vencimento,created_by,created_at,visivel_cliente)
 select pg_temp.dq_key('b',n),pg_temp.dq_key('5',1),'Attachment '||n,case when n=1 then 'Literal 100%_* attachment' else 'Preserved description' end,
 case when n=2 then null when n=1 then 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/'||pg_temp.dq_key('5',1)||'/'||pg_temp.dq_key('b',n)||'.pdf' else 'https://example.cdn.bubble.io/attachment.pdf' end,
 'application/pdf',case n%4 when 1 then 'No prazo' when 2 then 'Vencido' when 3 then 'Historic free text' end,
 '2027-01-01T12:00:00Z',case when n%2=1 then pg_temp.dq_key('2',1) end,'2026-10-30T15:00:00Z'::timestamptz,false from generate_series(1,30) n;
insert into public.rm_docs(id,projeto_id,nome,arquivo_url,status,created_by) values
 (pg_temp.dq_key('b',100),pg_temp.dq_key('5',2),'Foreign secret attachment','https://example.cdn.bubble.io/foreign.pdf','Foreign status',pg_temp.dq_key('2',3));
insert into public.rm_docs(id,projeto_id,nome,arquivo_url,created_at) values
 (pg_temp.dq_key('b',101),pg_temp.dq_key('5',1),'Before SP day','https://example.cdn.bubble.io/file.pdf','2026-10-30T02:59:59.999999Z'),
 (pg_temp.dq_key('b',102),pg_temp.dq_key('5',1),'Start SP day','https://example.cdn.bubble.io/file.pdf','2026-10-30T03:00:00Z'),
 (pg_temp.dq_key('b',103),pg_temp.dq_key('5',1),'End SP day','https://example.cdn.bubble.io/file.pdf','2026-10-31T02:59:59.999999Z'),
 (pg_temp.dq_key('b',104),pg_temp.dq_key('5',1),'After SP day','https://example.cdn.bubble.io/file.pdf','2026-10-31T03:00:00Z');

select pg_temp.dq_actor(1);
select pg_temp.dq_check(has_function_privilege('authenticated','public.rm_web_project_comments_v1(uuid,jsonb)','execute')
 and has_function_privilege('authenticated','public.rm_web_project_documents_v1(uuid,jsonb)','execute')
 and not has_function_privilege('anon','public.rm_web_project_comments_v1(uuid,jsonb)','execute')
 and not has_function_privilege('service_role','public.rm_web_project_documents_v1(uuid,jsonb)','execute'), 'only authenticated calls exposed');
select pg_temp.dq_check((select bool_and(not prosecdef and provolatile='s') from pg_proc where oid in(
 'public.rm_web_project_comments_v1(uuid,jsonb)'::regprocedure,'public.rm_web_project_documents_v1(uuid,jsonb)'::regprocedure)), 'both readers stable security invoker');

do $$ declare r jsonb; first_page jsonb; second_page jsonb; again jsonb; n int; begin
 set local role authenticated;
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1));
 perform pg_temp.dq_check((r->>'total')::int=57 and (r->>'unfiltered_total')::int=57 and (r->>'page')::int=1 and (r->>'page_size')::int=25
  and jsonb_array_length(r->'items')=25,'comments one bounded page from exact project');
 perform pg_temp.dq_check(r->'items'->0->>'id'=pg_temp.dq_key('a',104)::text,'newest first across days');
 perform pg_temp.dq_check(jsonb_array_length(r->'facets'->'authors')=2 and jsonb_array_length(r->'facets'->'cells')=1
  and r->'facets'->'cells'->0->>'id'=pg_temp.dq_key('4',1)::text,'historical project facets exclude unrelated identities/cells');
 perform pg_temp.dq_check(not(r->'filters' ? 'page') and r->'filters'->>'search'='' and r->'filters'->'cell_id'='null'::jsonb,'canonical filter defaults separate effective page');
 first_page:=r->'items';
 second_page:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),'{"page":2}')->'items';
 again:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1))->'items';
 perform pg_temp.dq_check(first_page=again and not exists(select 1 from jsonb_array_elements(first_page) a cross join jsonb_array_elements(second_page) b where a->>'id'=b->>'id'),'stable id tie order gives repeatable, disjoint pages');
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),'{"page":99999}');
 perform pg_temp.dq_check((r->>'page')::int=3 and jsonb_array_length(r->'items')=7,'out of range page clamps to final page');
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),'{"search":"100%_*"}');
 perform pg_temp.dq_check((r->>'total')::int=1 and r->'items'->0->>'id'=pg_temp.dq_key('a',101)::text and (r->>'unfiltered_total')::int=57,'literal percent underscore star search does not broaden');
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),jsonb_build_object('author_id',pg_temp.dq_key('2',1),'cell_id',pg_temp.dq_key('4',1)));
 perform pg_temp.dq_check((r->>'total')::int=27,'author and recipient filters combine before pagination');
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),'{"from_date":"2026-10-30","to_date":"2026-10-30"}');
 perform pg_temp.dq_check((r->>'total')::int=55 and not exists(select 1 from jsonb_array_elements(r->'items') x where x->>'id' in(pg_temp.dq_key('a',102)::text,pg_temp.dq_key('a',104)::text)),'São Paulo inclusive day boundaries ignore server timezone');
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',1),jsonb_build_object('author_id',pg_temp.dq_key('2',3),'page',2));
 perform pg_temp.dq_check((r->>'total')::int=0 and (r->>'unfiltered_total')::int=57 and (r->>'page')::int=1
  and jsonb_array_length(r->'items')=0 and jsonb_array_length(r->'facets'->'authors')=2,'foreign valid identity gives empty result without new facet/name');
 perform pg_temp.dq_check(public.rm_web_project_comments_v1(pg_temp.dq_key('5',99)) is null,'unknown project remains null');
 r:=public.rm_web_project_comments_v1(pg_temp.dq_key('5',3));
 perform pg_temp.dq_check((r->>'total')::int=0 and (r->>'unfiltered_total')::int=0 and jsonb_array_length(r->'facets'->'authors')=0,'empty project distinct from filtered empty');

 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1));
 perform pg_temp.dq_check((r->>'total')::int=63 and (r->>'unfiltered_total')::int=63 and jsonb_array_length(r->'items')=25,'union of generated documents and attachments uses one total/page');
 first_page:=r->'items';second_page:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"page":2}')->'items';
 perform pg_temp.dq_check(not exists(select 1 from jsonb_array_elements(first_page) a cross join jsonb_array_elements(second_page) b
  where a->>'id'=b->>'id' and a->>'source'=b->>'source'),'stable source and id ordering prevents pagination overlap');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"page":3}');
 perform pg_temp.dq_check(jsonb_array_length(r->'items')=13 and (select count(*) from jsonb_array_elements(r->'items') x where x->>'id'=pg_temp.dq_key('b',1)::text)=2,'same UUID across source tables is not deduplicated');
 perform pg_temp.dq_check(not exists(select 1 from jsonb_array_elements(r->'items') x where x ?| array['arquivo_url','s3_key','auth_user_id','object_path','sha256','payload']), 'list never exposes file URLs, keys or private envelopes');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"source":"documents","author_id":"2ac30000-0000-4000-8000-000000000002"}');
 perform pg_temp.dq_check((r->>'total')::int=15 and (r->'items'->0->>'author_name')='Search actor 2','real generated-document authors are preserved, not invented nulls');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"source":"docs","status":"No prazo"}');
 perform pg_temp.dq_check((r->>'total')::int=8 and not exists(select 1 from jsonb_array_elements(r->'items') x where x->>'status'<>'No prazo' or x->>'source'<>'docs'),'attachment status filter applies before one page');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"status":"other"}');
 perform pg_temp.dq_check((r->>'total')::int=18 and not exists(select 1 from jsonb_array_elements(r->'items') x where x->>'source'<>'docs'),'other is an explicit historical/null filter category, not a generated status');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"source":"documents","status":"Vencido"}');
 perform pg_temp.dq_check((r->>'total')::int=0,'documents do not acquire artificial attachment statuses');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"search":"100%_*"}');
 perform pg_temp.dq_check((r->>'total')::int=1 and (r->'items'->0->>'has_file')::boolean and r->'items'->0->>'source'='docs','description search is literal and file availability boolean');
 perform pg_temp.dq_check(jsonb_array_length(r->'facets'->'authors')=2 and jsonb_array_length(r->'facets'->'statuses')=3,'facets remain limited to visible project rows, independent of active search');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"from_date":"2026-10-30","to_date":"2026-10-30"}');
 perform pg_temp.dq_check((r->>'total')::int=61,'document creation bounds use São Paulo inclusive dates');
 r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1),'{"source":"docs","search":"Attachment 2"}');
 perform pg_temp.dq_check(exists(select 1 from jsonb_array_elements(r->'items') x where x->>'id'=pg_temp.dq_key('b',2)::text and not(x->>'has_file')::boolean),'missing file remains a known record with unavailable action');
 reset role;
end $$;

-- Explicitly malformed or broadened queries are not silently coerced.
select pg_temp.dq_reject(x,'22023') from (values('null'::jsonb),('[]'),('{"extra":true}'),('{"page":0}'),('{"page":100001}'),('{"page":1.5}'),
 ('{"page":"2"}'),('{"page":null}'),('{"author_id":"not-a-uuid"}'),('{"cell_id":4}'),('{"from_date":"2026-02-30"}'),
 ('{"to_date":"2026-10-30T00:00:00Z"}'),('{"from_date":"2026-10-31","to_date":"2026-10-30"}'),('{"search":null}'),
 (jsonb_build_object('search',repeat('x',201)))) v(x);
select pg_temp.dq_reject(x,'22023',true) from (values('{"source":"unknown"}'::jsonb),('{"status":"approved"}'),('{"cell_id":null}'),('{"from_date":"infinity"}')) v(x);
do $$ declare n int;r jsonb; begin
 for n in 1..3 loop
  perform pg_temp.dq_actor(n);set local role authenticated;r:=public.rm_web_project_documents_v1(pg_temp.dq_key('5',1));reset role;
  perform pg_temp.dq_check((r->>'total')::int=63,'active internal profiles preserve private attachment list');
 end loop;
 for n in 4..5 loop
  perform pg_temp.dq_actor(n);perform pg_temp.dq_reject('{}','42501');perform pg_temp.dq_reject('{}','42501',true);
 end loop;
 perform set_config('request.jwt.claim.sub','',true);perform pg_temp.dq_reject('{}','42501');
end $$;
select 'PASS:030 scoped dossier search, literal text, historical facets, combined source pagination, stable ties, SP dates, exact capabilities and no private file metadata' as result;
rollback;

-- A real second connection commits new dossier rows while an authenticated
-- reader holds a READ ONLY repeatable snapshot. No live data or remote service.
create extension if not exists dblink;
begin;
insert into auth.users(id) values('1fb00000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2fb00000-0000-4000-8000-000000000001','1fb00000-0000-4000-8000-000000000001','Snapshot reader','auditor');
insert into public.rm_projetos(id,numero) values('5fb00000-0000-4000-8000-000000000001','DOSSIER-READ-SNAPSHOT-30');
insert into public.rm_comentarios(id,projeto_id,evento) values('afb00000-0000-4000-8000-000000000001','5fb00000-0000-4000-8000-000000000001','Before concurrent write');
insert into public.rm_documentos(id,projeto_id,nome,arquivo_url) values('bfb00000-0000-4000-8000-000000000001','5fb00000-0000-4000-8000-000000000001','Before generated','https://example.cdn.bubble.io/snapshot.pdf');
insert into public.rm_docs(id,projeto_id,nome,arquivo_url) values('bfb00000-0000-4000-8000-000000000001','5fb00000-0000-4000-8000-000000000001','Before attachment','https://example.cdn.bubble.io/snapshot-attachment.pdf');
commit;
do $$ declare conn text:=format('host=127.0.0.1 port=%s dbname=%s user=postgres',current_setting('port'),current_database());
 first_comments jsonb; first_documents jsonb; during_comments jsonb; during_documents jsonb; after_comments jsonb; after_documents jsonb;
begin
 perform dblink_connect('dossier_search_reader',conn);perform dblink_connect('dossier_search_writer',conn);
 perform dblink_exec('dossier_search_reader',$remote$set request.jwt.claim.sub='1fb00000-0000-4000-8000-000000000001';set request.jwt.claims='{"aal":"aal1"}';set role authenticated;begin isolation level repeatable read read only;$remote$);
 select value into first_comments from dblink('dossier_search_reader',$remote$select public.rm_web_project_comments_v1('5fb00000-0000-4000-8000-000000000001')$remote$) as t(value jsonb);
 select value into first_documents from dblink('dossier_search_reader',$remote$select public.rm_web_project_documents_v1('5fb00000-0000-4000-8000-000000000001')$remote$) as t(value jsonb);
 perform dblink_exec('dossier_search_writer',$remote$
  insert into public.rm_comentarios(id,projeto_id,evento) values('afb00000-0000-4000-8000-000000000002','5fb00000-0000-4000-8000-000000000001','During reader snapshot');
  insert into public.rm_documentos(id,projeto_id,nome,arquivo_url) values('bfb00000-0000-4000-8000-000000000002','5fb00000-0000-4000-8000-000000000001','During generated','https://example.cdn.bubble.io/next.pdf');
 $remote$);
 select value into during_comments from dblink('dossier_search_reader',$remote$select public.rm_web_project_comments_v1('5fb00000-0000-4000-8000-000000000001')$remote$) as t(value jsonb);
 select value into during_documents from dblink('dossier_search_reader',$remote$select public.rm_web_project_documents_v1('5fb00000-0000-4000-8000-000000000001')$remote$) as t(value jsonb);
 if first_comments<>during_comments or first_documents<>during_documents or (first_comments->>'total')::int<>1 or (first_documents->>'total')::int<>2 then
  raise exception 'FAIL: concurrent writer changed the read-only snapshot or total/items composition';end if;
 perform dblink_exec('dossier_search_reader','commit;begin isolation level repeatable read read only;');
 select value into after_comments from dblink('dossier_search_reader',$remote$select public.rm_web_project_comments_v1('5fb00000-0000-4000-8000-000000000001')$remote$) as t(value jsonb);
 select value into after_documents from dblink('dossier_search_reader',$remote$select public.rm_web_project_documents_v1('5fb00000-0000-4000-8000-000000000001')$remote$) as t(value jsonb);
 if (after_comments->>'total')::int<>2 or jsonb_array_length(after_comments->'items')<>2
  or (after_documents->>'total')::int<>3 or jsonb_array_length(after_documents->'items')<>3 then
  raise exception 'FAIL: fresh request did not see the committed writer rows with exact counts/items';end if;
 perform dblink_exec('dossier_search_reader','rollback;');
 perform dblink_disconnect('dossier_search_reader');perform dblink_disconnect('dossier_search_writer');
exception when others then
 if 'dossier_search_reader'=any(dblink_get_connections()) then perform dblink_disconnect('dossier_search_reader');end if;
 if 'dossier_search_writer'=any(dblink_get_connections()) then perform dblink_disconnect('dossier_search_writer');end if;raise;
end $$;
select 'PASS:030 two real connections preserve read-only comment/document snapshot counts, union identities and publication across concurrent commits' as result;
-- Fixtures remain only until this disposable cluster is removed by the runner.

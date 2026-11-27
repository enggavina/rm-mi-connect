\set ON_ERROR_STOP on
begin;
create function pg_temp.rx_id(n int) returns uuid language sql immutable as $$
 select ('06600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.rx_check(v boolean,msg text) returns void language plpgsql as $$
begin
 if v is distinct from true then raise exception 'FAIL: %',msg; end if;
end $$;
create function pg_temp.rx_reject(statement text,state text) returns void language plpgsql as $$
begin
 begin execute statement; exception when others then if sqlstate=state then return; end if; raise; end;
 raise exception 'FAIL: receiving unexpectedly accepted';
end $$;
create function pg_temp.rx_context(office int default 1) returns jsonb language sql as $$
 select jsonb_build_object('version',2,'application','em','channel','mobile',
  'authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
  'workshop',jsonb_build_object('id',pg_temp.rx_id(office),'code',case office when 1 then 'BMA' else 'BRJ' end,
   'name','Oficina local','active',true,'revision',1,'updated_at',stamp),
  'principals',jsonb_build_array(
   jsonb_build_object('kind','device','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1','subject',pg_temp.rx_id(11),'revision',1),
   jsonb_build_object('kind','operator','issuer','https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1','subject',pg_temp.rx_id(14),'revision',1)),
  'issued_at',stamp,'expires_at',stamp+interval '4 minutes') from(select clock_timestamp() stamp)s;
$$;
create function pg_temp.rx_payload(id uuid,phase text) returns jsonb language sql as $$
 select jsonb_build_object('p_operador_id',pg_temp.rx_id(14),'p_cliente_id',pg_temp.rx_id(20),
  'p_chegada_equipamento','2026-11-17T12:00:00Z','p_descricao_equipamento','Local intake 066',
  'p_nota_fiscal','NF-066','p_equipamento',jsonb_build_object('descricao','Local intake 066'),
  'p_arquivo_nota_fiscal_url',prefix||'invoice.pdf',
  'p_fotos_recebimento',jsonb_build_array(jsonb_build_object('foto_url',prefix||'front.jpg','tipo_recebimento','frente','titulo','Frontal','numero',1)),
  'p_receiving_draft_id',id,'p_receiving_draft_revision',0,'p_receiving_draft_save_id',null,
  'p_receiving_draft_snapshot',jsonb_build_object('id',id,'version',2,'submitted',false,'cliente',pg_temp.rx_id(20),
   'chegada','2026-11-17T12:00:00Z','notaFiscal','NF-066','arquivoNotaFiscal',prefix||'invoice.pdf','fotos',
    jsonb_build_array(jsonb_build_object('id','rx-066-photo','uri',prefix||'front.jpg','tipo','frente'))))
 from (select case phase when 'open' then 'file:///local/' else 'https://fixture.invalid/' end prefix)s;
$$;
create function pg_temp.rx_mint(id uuid,phase text,payload jsonb,office int default 1) returns void language sql as $$
 select public.rm_authorize_mobile_receiving_workshop_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),id,phase,payload);
$$;
create function pg_temp.rx_call(id uuid,phase text,payload jsonb,office int default 1) returns jsonb language plpgsql as $$
declare result jsonb;
begin
 perform pg_temp.rx_mint(id,phase,payload,office);
 set local role authenticated;
 result:=public.rm_mobile_receiving_workshop_v1(id,phase,payload,repeat('6',64));
 reset role;
 return result;
end $$;

select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"06600000-0000-4000-8000-000000000001","code":"BMA"},{"id":"06600000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"06600000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into auth.users(id) values(pg_temp.rx_id(11));
insert into auth.sessions(id,user_id) values(pg_temp.rx_id(12),pg_temp.rx_id(11)),(pg_temp.rx_id(16),pg_temp.rx_id(11));
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 (pg_temp.rx_id(13),pg_temp.rx_id(11),'Local tablet 066','administrador'),(pg_temp.rx_id(14),null,'Local operator 066','mobile');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest(repeat('6',64),'sha256'),pg_temp.rx_id(11),pg_temp.rx_id(13),pg_temp.rx_id(14),clock_timestamp()+interval '1 hour');
insert into public.rm_clientes(id,nome) values(pg_temp.rx_id(20),'Local customer 066');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',pg_temp.rx_id(20),pg_temp.rx_id(1));
select set_config('request.jwt.claim.sub',pg_temp.rx_id(11)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.rx_id(12),'aal','aal1')::text,true);

set local role authenticated;
select pg_temp.rx_reject('select pg_temp.rx_mint(pg_temp.rx_id(30),''open'',pg_temp.rx_payload(pg_temp.rx_id(30),''open''))','42501');
select pg_temp.rx_reject('select public.rm_mobile_receiving_workshop_v1(pg_temp.rx_id(30),''open'',pg_temp.rx_payload(pg_temp.rx_id(30),''open''),repeat(''6'',64))','42501');
reset role;
select pg_temp.rx_reject('select pg_temp.rx_call(pg_temp.rx_id(30),''open'',pg_temp.rx_payload(pg_temp.rx_id(30),''open''),2)','42501');
select pg_temp.rx_check(not exists(select 1 from rm_private.receiving_openings where client_submission_id=pg_temp.rx_id(30)),'cross-office creates nothing');

-- The same frozen draft can be submitted after reconnection, before uploads.
do $case$
declare
 sid uuid:=pg_temp.rx_id(31);
 opened jsonb;
 received jsonb;
 pid uuid;
begin
 opened:=pg_temp.rx_call(sid,'open',pg_temp.rx_payload(sid,'open'));
 pid:=(opened->>'projeto_id')::uuid;
 perform pg_temp.rx_check(exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1() proof
  where proof.submission_id=sid and proof.creation_phase='open' and not proof.completed)
  and not rm_private.workshop_receiving_pilot_ready_v1(),'a fresh scoped opening is tracked and does not qualify before completion');
 perform pg_temp.rx_check((select workshop_id=pg_temp.rx_id(1) from rm_private.workshop_project_ownership where id=pid),'early project records its workshop');
 perform pg_temp.rx_check(exists(select 1 from public.rm_projetos where id=pid and numero is null and tipo_equipamento_id is null),'early project preserves blank OS and type');
 perform pg_temp.rx_check(exists(select 1 from jsonb_array_elements(public.rm_web_receivings_v1('all','Local intake 066',1,100)->'items') p where p->>'id'=pid::text),'portal immediately lists the scoped project');
 perform pg_temp.rx_check((pg_temp.rx_call(sid,'open',pg_temp.rx_payload(sid,'open'))->>'idempotent_replay')::boolean,'early retry keeps project');
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''complete'',pg_temp.rx_payload(%L,''complete''),2)',sid,sid),'42501');
 received:=pg_temp.rx_call(sid,'complete',pg_temp.rx_payload(sid,'complete'));
 perform pg_temp.rx_check(received->>'projeto_id'=pid::text,'final receipt uses the original project');
 perform pg_temp.rx_check(rm_private.workshop_receiving_pilot_ready_v1(),'both scoped phases and the original receipt qualify the pilot');
 perform pg_temp.rx_check((pg_temp.rx_call(sid,'complete',pg_temp.rx_payload(sid,'complete'))->>'idempotent_replay')::boolean,'final retry keeps one receipt');
 perform pg_temp.rx_check((select count(*)=1 from public.rm_fotos where projeto_id=pid)
  and (select count(*)=1 from public.rm_documentos where projeto_id=pid),'photos and invoice appended once');
end
$case$;

-- The complete branch also accepts a preexisting queue envelope with no open ACK.
do $case$
declare sid uuid:=pg_temp.rx_id(32);p jsonb;
begin
 p:=pg_temp.rx_call(sid,'complete',pg_temp.rx_payload(sid,'complete'));
 perform pg_temp.rx_check((select workshop_id=pg_temp.rx_id(1) from rm_private.workshop_project_ownership where id=(p->>'projeto_id')::uuid),'legacy offline completion records origin');
 perform pg_temp.rx_check(exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1() proof
  where proof.submission_id=sid and proof.creation_phase='complete' and proof.completed),'a new project created on offline completion is separate evidence');
 p:=pg_temp.rx_call(sid,'open',pg_temp.rx_payload(sid,'open'));
 perform pg_temp.rx_check((p->>'idempotent_replay')::boolean and exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1() proof
  where proof.submission_id=sid and proof.creation_phase='complete' and proof.completed),'replaying open cannot turn offline completion into an early opening');
end
$case$;

select pg_temp.rx_mint(pg_temp.rx_id(33),'open',pg_temp.rx_payload(pg_temp.rx_id(33),'open'));
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.rx_id(16),'aal','aal1')::text,true);
set local role authenticated;
select pg_temp.rx_reject('select public.rm_mobile_receiving_workshop_v1(pg_temp.rx_id(33),''open'',pg_temp.rx_payload(pg_temp.rx_id(33),''open''),repeat(''6'',64))','42501');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.rx_id(12),'aal','aal1')::text,true);
set local role authenticated;
select pg_temp.rx_reject('select public.rm_mobile_receiving_workshop_v1(pg_temp.rx_id(33),''open'',pg_temp.rx_payload(pg_temp.rx_id(33),''open'')||''{"p_nota_fiscal":"changed"}'',repeat(''6'',64))','42501');
reset role;
select pg_temp.rx_check(not exists(select 1 from rm_private.receiving_openings where client_submission_id=pg_temp.rx_id(33)),'tampered session and payload have no effect');

select 'PASS: scoped mobile receiving before uploads, legacy queue completion, cross-office rejection, visible portal and exact retries' result;

create function pg_temp.rx_catalog(office int,table_name text,after_at timestamptz default null,after_id uuid default null,
 ids_only boolean default false) returns jsonb language sql as $$
 select public.rm_mobile_workshop_catalog_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),
  table_name,after_at,after_id,ids_only)
$$;
insert into public.rm_clientes(id,nome) select pg_temp.rx_id(n),'LOCAL catalog client' from generate_series(500,750)n;
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id)
 select 'client',pg_temp.rx_id(n),pg_temp.rx_id(case when n=750 then 2 else 1 end) from generate_series(500,750)n;

do $$
declare page jsonb; next_page jsonb; last jsonb;
begin
 page:=pg_temp.rx_catalog(1,'rm_clientes');
 perform pg_temp.rx_check(page->>'workshop_id'=pg_temp.rx_id(1)::text and jsonb_array_length(page->'rows')=250
  and not (page->>'complete')::boolean and not exists(select 1 from jsonb_array_elements(page->'rows') item
   where item->>'id'=pg_temp.rx_id(750)::text),'mobile catalog scopes before keyset limit');
 last:=page->'rows'->249;
 next_page:=pg_temp.rx_catalog(1,'rm_clientes',(last->>'updated_at')::timestamptz,(last->>'id')::uuid);
 perform pg_temp.rx_check(jsonb_array_length(next_page->'rows')=1 and (next_page->>'complete')::boolean,
  'incremental mobile catalogue returns the remaining own row');
 page:=pg_temp.rx_catalog(1,'rm_clientes',null,null,true);
 last:=page->'rows'->249;
 update public.rm_clientes set nome='LOCAL earlier ID updated during reconciliation' where id=pg_temp.rx_id(500);
 next_page:=pg_temp.rx_catalog(1,'rm_clientes',(last->>'updated_at')::timestamptz,(last->>'id')::uuid,true);
 perform pg_temp.rx_check(jsonb_array_length(next_page->'rows')=1 and next_page->'rows'->0->>'id'=pg_temp.rx_id(749)::text
  and not (next_page->'rows'->0?'nome'),'reconciliation is ordered by immutable IDs despite concurrent timestamp changes');
 page:=pg_temp.rx_catalog(2,'rm_clientes');
 perform pg_temp.rx_check(jsonb_array_length(page->'rows')=1 and page->'rows'->0->>'id'=pg_temp.rx_id(750)::text,
  'rebound operator only receives the other office catalogue');
 perform pg_temp.rx_reject('select pg_temp.rx_catalog(1,''rm_sync_outbox'')','22023');
 perform pg_temp.rx_reject('select public.rm_mobile_workshop_catalog_v1(pg_temp.rx_id(11),pg_temp.rx_id(17),repeat(''6'',64),pg_temp.rx_context(),''rm_celulas'',null,null,false)','28000');
 set local role authenticated;
 perform pg_temp.rx_reject('select pg_temp.rx_catalog(1,''rm_clientes'')','42501');
 reset role;
end$$;
select 'PASS: native workshop catalog pagination, immutable ID reconciliation and office boundaries' result;

insert into public.rm_users(id,nome,email) values(pg_temp.rx_id(775),'LOCAL manager BRJ','local-shadow@example.invalid');
insert into public.rm_projetos(id,nome,gestor_responsavel_id) values(pg_temp.rx_id(779),'LOCAL BRJ project',pg_temp.rx_id(775));
insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.rx_id(779),pg_temp.rx_id(2));
do $$
declare page jsonb;
begin
 page:=pg_temp.rx_catalog(1,'rm_users');
 perform pg_temp.rx_check(exists(select 1 from jsonb_array_elements(page->'rows') r where r->>'id'=pg_temp.rx_id(14)::text)
  and not exists(select 1 from jsonb_array_elements(page->'rows') r where r->>'id'=pg_temp.rx_id(775)::text),
  'operator can resolve self and not an unrelated workshop manager');
 page:=pg_temp.rx_catalog(2,'rm_users');
 perform pg_temp.rx_check(exists(select 1 from jsonb_array_elements(page->'rows') r where r->>'id'=pg_temp.rx_id(775)::text
  and not(r?'email') and not(r?'auth_user_id') and not(r?'matricula')),'staff projection contains names without authentication data');
 page:=pg_temp.rx_catalog(1,'rm_documentos');
 perform pg_temp.rx_check(exists(select 1 from jsonb_array_elements(page->'rows') r where r->>'arquivo_url' like '%invoice.pdf')
  and pg_temp.rx_catalog(2,'rm_documentos')->'rows'='[]'::jsonb,'receiving invoice follows workshop scope');
 page:=pg_temp.rx_catalog(1,'rm_fotos');
 perform pg_temp.rx_check(exists(select 1 from jsonb_array_elements(page->'rows') r where r->>'foto_url' like '%front.jpg')
  and pg_temp.rx_catalog(2,'rm_fotos')->'rows'='[]'::jsonb,'project photos follow workshop scope');
 perform pg_temp.rx_check(pg_temp.rx_catalog(1,'rm_cadastro_fotos')->'rows'='[]'::jsonb,'unowned legacy photo title dictionary is not synced');
end$$;
select 'PASS: native related catalog, actors, media and historical workshop boundaries' result;

create function pg_temp.rx_mutation(rid uuid,op text,p jsonb,office int default 1,actual jsonb default null) returns jsonb language plpgsql as $$
declare result jsonb;
begin
 perform public.rm_authorize_mobile_workshop_mutation_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),rid,op,p);
 set local role authenticated;
 result:=public.rm_mobile_workshop_mutate_v1(rid,op,coalesce(actual,p),repeat('6',64));
 reset role;
 return result;
exception when others then reset role;raise;
end$$;

insert into public.rm_celulas(id,nome) values(pg_temp.rx_id(801),'LOCAL BMA'),(pg_temp.rx_id(802),'LOCAL BRJ');
insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(pg_temp.rx_id(801),pg_temp.rx_id(1)),(pg_temp.rx_id(802),pg_temp.rx_id(2));
insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(pg_temp.rx_id(801),pg_temp.rx_id(14));
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade)
 select pg_temp.rx_id(811),project_id,pg_temp.rx_id(801),true
 from rm_private.receiving_openings where client_submission_id=pg_temp.rx_id(31);
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade)
 values(pg_temp.rx_id(812),pg_temp.rx_id(779),pg_temp.rx_id(802),true);
do $$
declare rid uuid:=gen_random_uuid(); op text:='rm_add_cell_comment_v1'; p jsonb; result jsonb;
begin
 p:=jsonb_build_object('p_celula_projeto_id',pg_temp.rx_id(811),'p_comentario','LOCAL authorized offline comment',
  'p_operador_id',pg_temp.rx_id(14));
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_workshop_mutate_v1(%L,%L,%L,repeat(''6'',64))',rid,op,p),'42501');
 reset role;
 perform pg_temp.rx_reject(format('select pg_temp.rx_mutation(%L,%L,%L,2)',rid,op,p),'42501');
 perform pg_temp.rx_reject(format('select pg_temp.rx_mutation(%L,%L,%L,1,%L)',rid,op,p,jsonb_set(p,'{p_comentario}','"LOCAL changed"')),'42501');
 perform pg_temp.rx_reject(format('select pg_temp.rx_mutation(%L,%L,%L,1)',gen_random_uuid(),op,
  jsonb_set(p,'{p_celula_projeto_id}',to_jsonb(pg_temp.rx_id(812)))),'42501');
 result:=pg_temp.rx_mutation(rid,op,p);
 perform pg_temp.rx_check(result is not null and (pg_temp.rx_mutation(rid,op,p)->>'idempotent_replay')::boolean
  and (select count(*)=1 from public.rm_comentarios where evento='LOCAL authorized offline comment'
   and cadastrado_por_id=pg_temp.rx_id(14)),'offline protocol returns one registered comment with the original author');
end$$;
select 'PASS: native queued mutation preserves author, exact payload and retry and refuses another workshop' result;

create function pg_temp.rx_media(office int,urls text[]) returns jsonb language sql as $$
 select public.rm_mobile_workshop_media_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),urls)
$$;
insert into public.rm_fotos(id,projeto_id,celula_id,foto_url) values
 (pg_temp.rx_id(893),pg_temp.rx_id(779),pg_temp.rx_id(802),'https://files.cdn.bubble.io/foreign.jpg');
insert into public.rm_projetos(id,nome) values(pg_temp.rx_id(884),'LOCAL BMA photos');
insert into rm_private.workshop_project_ownership(id,workshop_id) values(pg_temp.rx_id(884),pg_temp.rx_id(1));
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,visibilidade) values(pg_temp.rx_id(885),pg_temp.rx_id(884),pg_temp.rx_id(801),true);
insert into public.rm_fotos(id,projeto_id,celula_id,foto_url) values
 (pg_temp.rx_id(894),pg_temp.rx_id(884),pg_temp.rx_id(801),'https://files.cdn.bubble.io/team.jpg');
do $$
declare refs text[]; found jsonb; draft_url text; draft_photo text;
begin
 draft_url:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||pg_temp.rx_id(11)||'/draft.pdf';
 draft_photo:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||pg_temp.rx_id(11)||'/draft.jpg';
 insert into storage.objects(bucket_id,name,owner_id) values('rm-fotos',pg_temp.rx_id(11)||'/draft.jpg',pg_temp.rx_id(11)::text);
 insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,last_save_id,payload) values
  (pg_temp.rx_id(895),pg_temp.rx_id(11),pg_temp.rx_id(14),gen_random_uuid(),jsonb_build_object('id',pg_temp.rx_id(895),
   'cliente',pg_temp.rx_id(20),'arquivoNotaFiscal',draft_url,'fotos',jsonb_build_array(jsonb_build_object('uri',draft_photo))));
 select array(select f.foto_url from public.rm_fotos f where f.projeto_id=o.project_id and f.foto_url like '%/front.jpg' limit 1)
  ||array(select d.arquivo_url from public.rm_documentos d where d.projeto_id=o.project_id and d.arquivo_url like '%/invoice.pdf' limit 1)
  ||array['https://files.cdn.bubble.io/team.jpg',draft_url,draft_photo,'https://files.cdn.bubble.io/foreign.jpg','https://files.cdn.bubble.io/unknown.jpg'] into refs
  from rm_private.receiving_openings o where o.client_submission_id=pg_temp.rx_id(31);
 found:=pg_temp.rx_media(1,refs);
 perform pg_temp.rx_check(cardinality(refs)=7 and jsonb_array_length(found->'files')=5
  and found->'files' @> jsonb_build_array(jsonb_build_object('url',refs[1],'source','project_photo'),jsonb_build_object('url',refs[2],'source','document'))
  and pg_temp.rx_media(2,refs)->'files'='[]'::jsonb,'batch returns only media referenced by a project allowed in the workshop and cells');
 delete from public.rm_tablet_celula_users where celula_id=pg_temp.rx_id(801) and identidade_id=pg_temp.rx_id(14);
 perform pg_temp.rx_check(jsonb_array_length(pg_temp.rx_media(1,refs)->'files')=4
  and pg_temp.rx_media(1,array[refs[3]])->'files'='[]'::jsonb,'revoked cell removes team media and preserves the original receiving and draft');
 set local role authenticated;
 perform pg_temp.rx_reject(format('select pg_temp.rx_media(1,%L)',refs),'42501');
 reset role;
end$$;
select 'PASS: native media references and cell revocation before credentials for files' result;

create function pg_temp.rx_upload(office int,asset uuid,payload jsonb,ref text,stored boolean default false,checksum text default repeat('a',64))
returns jsonb language sql as $$
 select public.rm_mobile_workshop_upload_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),
  pg_temp.rx_id(office),pg_temp.rx_id(31),'rm_submit_recebimento_v1',payload,asset,'document',ref,'application/pdf',24,checksum,stored)
$$;
do $$
declare asset uuid:=pg_temp.rx_id(911); p jsonb; ref text; result jsonb; object_name text; url text; proj uuid;
begin
 ref:='file:///storage/rm-media/'||asset||'.pdf';
 p:=jsonb_set(pg_temp.rx_payload(pg_temp.rx_id(31),'complete'),'{p_arquivo_nota_fiscal_url}',to_jsonb(ref));
 perform pg_temp.rx_reject(format('select pg_temp.rx_upload(2,%L,%L,%L)',asset,p,ref),'42501');
 perform pg_temp.rx_reject(format('select pg_temp.rx_upload(1,%L,%L,%L)',asset,p,'file:///other.pdf'),'22023');
 perform pg_temp.rx_reject(format('select pg_temp.rx_upload(1,%L,%L,%L,true)',asset,p,ref),'42501');
 result:=pg_temp.rx_upload(1,asset,p,ref);
 object_name:=result->>'path';
 url:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||object_name;
 perform pg_temp.rx_check(result->>'stored'='false' and object_name='mobile-oficina/'||pg_temp.rx_id(1)||'/'||pg_temp.rx_id(31)||'/'||asset||'.pdf'
  and pg_temp.rx_upload(1,asset,p,ref)=result,'native upload reserves one immutable canonical path for the original project and operator');
 perform pg_temp.rx_reject(format('select pg_temp.rx_upload(1,%L,%L,%L,false,%L)',asset,p,ref,repeat('b',64)),'PT409');
 perform pg_temp.rx_reject(format('select pg_temp.rx_upload(1,%L,%L,%L,true)',asset,p,ref),'PT409');
 perform pg_temp.rx_check(not rm_private.workshop_stored_media_owned_v1(url,pg_temp.rx_id(1),'document'),'pending objects cannot be signed');
 insert into storage.objects(bucket_id,name,metadata,user_metadata) values
  ('rm-documentos',object_name,jsonb_build_object('size',24,'mimetype','application/pdf'),jsonb_build_object('sha256',repeat('a',64)));
 perform pg_temp.rx_check((pg_temp.rx_upload(1,asset,p,ref,true)->>'stored')::boolean
  and (pg_temp.rx_upload(1,asset,p,ref,true)->>'stored')::boolean,'storage receipt is idempotent and only acknowledges the verified bytes');
 perform pg_temp.rx_check(rm_private.workshop_stored_media_owned_v1(url,pg_temp.rx_id(1),'document')
  and not rm_private.workshop_stored_media_owned_v1(url,pg_temp.rx_id(2),'document')
  and not rm_private.workshop_stored_media_owned_v1(url,pg_temp.rx_id(1),'answer_signature'),'signed files require the exact workshop and type');
 select project_id into proj from rm_private.receiving_openings where client_submission_id=pg_temp.rx_id(31);
 update public.rm_projetos set arquivo_nota_fiscal_url=url where id=proj;
 perform pg_temp.rx_check(rm_private.workshop_project_link_v1('document_link',jsonb_build_object('id',proj,'source','invoice'),pg_temp.rx_id(1))->>'file'=url
  and pg_temp.rx_media(1,array[url])->'files'@>jsonb_build_array(jsonb_build_object('url',url,'source','document')),'established private invoice works through both controlled readers');
 set local role authenticated;
 perform pg_temp.rx_check(not exists(select 1 from storage.objects where bucket_id='rm-documentos' and name=object_name),'legacy direct storage reads exclude the new private namespace');
 perform pg_temp.rx_reject(format('select pg_temp.rx_upload(1,%L,%L,%L)',asset,p,ref),'42501');
 reset role;
end$$;
select 'PASS: mobile media upload watches exact ownership, immutable metadata, and private stored files' result;

create function pg_temp.rx_draft_workshop(office int,args jsonb,actual jsonb default null) returns jsonb language plpgsql as $$
declare request_id uuid:=gen_random_uuid(); value jsonb;
begin
 perform public.rm_authorize_receiving_draft_workshop_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),request_id,args);
 set local role authenticated;
 value:=public.rm_mobile_receiving_draft_workshop_v1(request_id,coalesce(actual,args),repeat('6',64));
 reset role;
 return value;
exception when others then reset role;raise;
end$$;
do $$
declare legacy_id uuid:=pg_temp.rx_id(895); command jsonb; snapshot jsonb; fresh uuid:=pg_temp.rx_id(956);
 request_id uuid:=gen_random_uuid(); foreign_client uuid:=pg_temp.rx_id(957); foreign_open jsonb; saved jsonb; replay jsonb;
begin
 command:=jsonb_build_object('action','read','draftId',null);
 perform pg_temp.rx_check(pg_temp.rx_draft_workshop(1,command)->>'id'=legacy_id::text,'legacy BMA draft is recovered by its original client');
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(2,%L)',command),'42501');
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(1,%L,%L)',command,jsonb_set(command,'{draftId}',to_jsonb(legacy_id))),'42501');
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_receiving_draft_workshop_v1(%L,%L,repeat(''6'',64))',request_id,command),'42501');
 reset role;
 select payload into strict snapshot from rm_private.receiving_drafts d where d.id=legacy_id;
 snapshot:=snapshot||'{"version":2,"eventualidades":"LOCAL revised draft"}'::jsonb;
 command:=jsonb_build_object('action','save','draftId',legacy_id,'expectedRevision',1,'saveId',gen_random_uuid(),'payload',snapshot);
 saved:=pg_temp.rx_draft_workshop(1,command);
 replay:=pg_temp.rx_draft_workshop(1,command);
 perform pg_temp.rx_check(saved->>'revision'='2' and replay=saved
  and exists(select 1 from rm_private.receiving_draft_workshops where draft_id=legacy_id and workshop_id=pg_temp.rx_id(1)),
  'legacy save records its proven workshop and exactly replays the original revision');
 delete from rm_private.receiving_drafts d where d.id=legacy_id;
 command:=jsonb_build_object('action','save','draftId',fresh,'expectedRevision',0,'saveId',gen_random_uuid(),
  'payload',jsonb_build_object('id',fresh,'version',2,'cliente',''));
 saved:=pg_temp.rx_draft_workshop(1,command);
 perform pg_temp.rx_check(saved->>'id'=fresh::text
  and exists(select 1 from rm_private.receiving_draft_workshops where draft_id=fresh and workshop_id=pg_temp.rx_id(1)),
  'new draft freezes its office even while fields are incomplete');
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(2,%L)',jsonb_build_object('action','read','draftId',fresh)),'42501');
 insert into public.rm_clientes(id,nome) values(foreign_client,'LOCAL BRJ customer');
 insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',foreign_client,pg_temp.rx_id(2));
 foreign_open:=jsonb_set(jsonb_set(pg_temp.rx_payload(fresh,'open'),'{p_cliente_id}',to_jsonb(foreign_client)),
  '{p_receiving_draft_snapshot,cliente}',to_jsonb(foreign_client));
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''open'',%L,2)',fresh,foreign_open),'42501');
 perform pg_temp.rx_check((select count(*)=1 from rm_private.receiving_drafts d where d.id=fresh and d.state='draft' and d.revision=1),
  'blocked transfer preserves the original unfinished draft');
end$$;
select 'PASS: receiving draft workshop, original ownership, exact retry and blocked cross-workshop recovery' result;

create function pg_temp.rx_draft_media_upload(office int,draft uuid,asset uuid,kind text,mime text,payload jsonb,ref text,stored boolean)
returns jsonb language sql as $$
 select public.rm_mobile_workshop_upload_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('6',64),pg_temp.rx_context(office),
  pg_temp.rx_id(office),draft,'receiving_draft',payload,asset,kind,ref,mime,24,repeat('a',64),stored)
$$;
do $draft_media$
declare sid uuid:=pg_temp.rx_id(956); inv uuid:=pg_temp.rx_id(961); photo uuid:=pg_temp.rx_id(962);
 base text:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/';
 inv_name text; photo_name text; inv_url text; photo_url text; result jsonb; context jsonb; save_args jsonb;
 receipt jsonb; snapshot jsonb; project uuid; kind text; asset uuid; mime text; local_uri text; intent jsonb; remote_path text;
begin
 context:=jsonb_build_object('p_receiving_draft_id',sid,'p_operador_id',pg_temp.rx_id(14),'p_cliente_id',pg_temp.rx_id(20));
 for asset,kind,mime,local_uri in select * from (values
   (inv,'document','application/pdf','file:///storage/'||inv||'.pdf'),(photo,'photo','image/jpeg','file:///storage/'||photo||'.jpg')) v loop
  intent:=context||case kind when 'document' then jsonb_build_object('p_arquivo_nota_fiscal_url',local_uri)
   else jsonb_build_object('p_fotos_recebimento',jsonb_build_array(jsonb_build_object('foto_url',local_uri))) end;
  perform pg_temp.rx_reject(format('select pg_temp.rx_draft_media_upload(2,%L,%L,%L,%L,%L,%L,false)',
   sid,asset,kind,mime,intent,local_uri),'42501');
  perform pg_temp.rx_reject(format('select pg_temp.rx_draft_media_upload(1,%L,%L,%L,%L,%L,%L,false)',
   sid,asset,kind,mime,intent||jsonb_build_object('p_receiving_draft_id',pg_temp.rx_id(970)),local_uri),'22023');
  result:=pg_temp.rx_draft_media_upload(1,sid,asset,kind,mime,intent,local_uri,false);
  remote_path:=result->>'path';
  perform pg_temp.rx_check(not (result->>'stored')::boolean
    and (select project_id is null from rm_private.mobile_workshop_uploads where id=asset),'draft file reserves no project');
  perform pg_temp.rx_reject(format('select pg_temp.rx_draft_media_upload(1,%L,%L,%L,%L,%L,%L,true)',
   sid,asset,kind,mime,intent,local_uri),'PT409');
  insert into storage.objects(bucket_id,name,metadata,user_metadata)
   values('rm-documentos',remote_path,jsonb_build_object('size',24,'mimetype',mime),jsonb_build_object('sha256',repeat('a',64)));
  result:=pg_temp.rx_draft_media_upload(1,sid,asset,kind,mime,intent,local_uri,true);
  perform pg_temp.rx_check((result->>'stored')::boolean
    and result=pg_temp.rx_draft_media_upload(1,sid,asset,kind,mime,intent,local_uri,true),'draft file receipt continues exactly after a lost acknowledgement');
  perform pg_temp.rx_check(pg_temp.rx_media(1,array[base||remote_path])->'files'='[]'::jsonb,'unpublished draft attachment cannot be downloaded');
  if kind='document' then inv_name:=remote_path; else photo_name:=remote_path;end if;
 end loop;
 inv_url:=base||inv_name; photo_url:=base||photo_name;
 perform pg_temp.rx_check(not exists(select 1 from rm_private.receiving_openings where client_submission_id=sid)
  and not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=sid),'draft attachments do not open a project');
 snapshot:=(pg_temp.rx_payload(sid,'complete')->'p_receiving_draft_snapshot')||
  jsonb_build_object('arquivoNotaFiscal',inv_url,'fotos',jsonb_build_array(jsonb_build_object('uri',photo_url,'tipo','frente')));
 save_args:=jsonb_build_object('action','save','draftId',sid,'expectedRevision',1,'saveId',gen_random_uuid(),'payload',snapshot);
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(1,%L)',jsonb_set(save_args,'{payload,arquivoNotaFiscal}',
  to_jsonb(base||replace(inv_name,inv::text,pg_temp.rx_id(998)::text)))),'42501');
 result:=pg_temp.rx_draft_workshop(1,save_args);
 perform pg_temp.rx_check(result->>'revision'='2' and pg_temp.rx_draft_workshop(1,save_args)=result
  and jsonb_array_length(pg_temp.rx_media(1,array[inv_url,photo_url])->'files')=2
  and pg_temp.rx_media(2,array[inv_url,photo_url])->'files'='[]'::jsonb,
  'only the original office and actor recover the private draft files after saving');
 set local role authenticated;
 perform pg_temp.rx_check(not exists(select 1 from storage.objects where bucket_id='rm-documentos' and name in(inv_name,photo_name)),
  'authenticated direct storage bypass is blocked for draft files');
 reset role;

 receipt:=pg_temp.rx_payload(sid,'complete')||jsonb_build_object('p_receiving_draft_revision',2,
  'p_receiving_draft_snapshot',snapshot,'p_arquivo_nota_fiscal_url',inv_url);
 receipt:=jsonb_set(receipt,'{p_fotos_recebimento,0,foto_url}',to_jsonb(photo_url));
 result:=pg_temp.rx_call(sid,'open',jsonb_set(jsonb_set(receipt,'{p_arquivo_nota_fiscal_url}','"file:///local/invoice.pdf"'),
  '{p_fotos_recebimento,0,foto_url}','"file:///local/front.jpg"'));
 project:=(result->>'projeto_id')::uuid;
 perform pg_temp.rx_check(project is not null and (result->>'attachments_pending')::boolean and
  rm_private.workshop_project_link_v1('document_link',jsonb_build_object('id',project,'source','invoice'),pg_temp.rx_id(1))->>'file' is null,
  'early opening still creates the project before publishing its attachments');
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''complete'',%L)',sid,jsonb_set(receipt,'{p_arquivo_nota_fiscal_url}',
  to_jsonb(base||replace(inv_name,inv::text,pg_temp.rx_id(998)::text)))),'42501');
 perform pg_temp.rx_check(not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=sid)
  and exists(select 1 from rm_private.receiving_drafts where id=sid and revision=2 and state='draft'),'rejection preserves pending draft and opening');
 result:=pg_temp.rx_call(sid,'complete',receipt);
 perform pg_temp.rx_check(result->>'projeto_id'=project::text and (select count(*)=2 from rm_private.mobile_workshop_uploads
   where id in(inv,photo) and project_id=project)
  and (pg_temp.rx_call(sid,'complete',receipt)->>'idempotent_replay')::boolean
  and (select count(*)=1 from public.rm_fotos where projeto_id=project and foto_url=photo_url)
  and rm_private.workshop_project_link_v1('document_link',jsonb_build_object('id',project,'source','invoice'),pg_temp.rx_id(1))->>'file'=inv_url
  and jsonb_array_length(pg_temp.rx_media(1,array[inv_url,photo_url])->'files')=2,
  'completion promotes the same stored bytes and preserves a single receiving across retries');
end
$draft_media$;
select 'PASS: private receiving draft media before opening, cross-office denial, exact replay and atomic promotion' result;

do $pristine_recovery$
declare
 draft uuid:=pg_temp.rx_id(90);
 stamp timestamptz:=clock_timestamp();
 pristine jsonb;
 original rm_private.receiving_drafts;
 read_command jsonb;
 save_command jsonb;
 contents jsonb;
 remote jsonb;
 completed jsonb;
 repeated jsonb;
 receipt jsonb;
 project uuid;
begin
 pristine:=jsonb_build_object('version',2,'id',draft,'step',0,'cliente','',
  'chegada',to_char(stamp at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'notaFiscal','','arquivoNotaFiscal','','descricaoEquipamento','','placaMotor','','eventualidades','','equipamento','{}'::jsonb,'fotos','[]'::jsonb);
 insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,last_save_id,payload,created_at,updated_at)
 values(draft,pg_temp.rx_id(11),pg_temp.rx_id(14),pg_temp.rx_id(91),pristine,stamp,stamp) returning * into original;
 read_command:=jsonb_build_object('action','read','draftId',draft);
 save_command:=jsonb_build_object('action','save','draftId',draft,'expectedRevision',1,'saveId',pg_temp.rx_id(92),'payload',pristine);
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(1,%L)',save_command),'42501');

 for contents in select * from (values
  (pristine||'{"fotos":[{"uri":"https://fixture.invalid/existing.png"}]}'),
  (pristine||'{"arquivoNotaFiscal":"file:///invoice.pdf"}'),
  (pristine||'{"eventualidades":"old work"}'),
  (pristine||'{"legacySnapshot":{"owner":"historical"}}'),
  (pristine||'{"chegada":"2026-11-01T08:29:05.000Z"}'),
  (pristine||'{"chegada":"9999-99-99T99:99:99.999Z"}')
 ) variations(payload) loop
  update rm_private.receiving_drafts set payload=contents where id=draft;
  perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(1,%L)',read_command),'42501');
 end loop;
 update rm_private.receiving_drafts set payload=pristine,revision=2 where id=draft;
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(1,%L)',read_command),'42501');
 update rm_private.receiving_drafts set revision=1,updated_at=stamp+interval '1 second' where id=draft;
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(1,%L)',read_command),'42501');
 update rm_private.receiving_drafts set updated_at=stamp where id=draft;
 perform pg_temp.rx_check(not exists(select 1 from rm_private.receiving_draft_recoveries where draft_id=draft),
  'substantive or edited drafts do not obtain the current desk as origin');

 set local role authenticated;
 perform pg_temp.rx_check(public.rm_receiving_draft_v1(repeat('6',64),'read',draft)->'payload'=pristine,
  'legacy access to the original unclassified slot remains available during transition');
 perform pg_temp.rx_reject(format('select rm_private.receiving_draft_store_v1(repeat(''6'',64),''read'',%L,null,null,null,true)',draft),'42501');
 reset role;

 remote:=pg_temp.rx_draft_workshop(1,read_command);
 perform pg_temp.rx_check(remote->'payload'=pristine
  and (select to_jsonb(d)=to_jsonb(original) from rm_private.receiving_drafts d where id=draft)
  and exists(select 1 from rm_private.receiving_draft_workshops where draft_id=draft and workshop_id=pg_temp.rx_id(1)),
  'verified recovery preserves the entire original database record');
 perform pg_temp.rx_reject(format('select pg_temp.rx_draft_workshop(2,%L)',read_command),'42501');
 remote:=pg_temp.rx_draft_workshop(1,read_command);
 perform pg_temp.rx_check(remote->>'id'=draft::text
  and (select count(*)=1 from rm_private.receiving_draft_recoveries where draft_id=draft and original_revision=1
   and auth_user_id=original.auth_user_id and operator_id=original.operator_id
   and original_payload_sha256=encode(sha256(convert_to(pristine::text,'UTF8')),'hex')),
  'reopening the recovered draft does not duplicate the origin or audit');

 receipt:=pg_temp.rx_payload(draft,'complete')||'{"p_receiving_draft_revision":2}';
 contents:=receipt->'p_receiving_draft_snapshot';
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_receiving_draft_v1(repeat(''6'',64),''read'',%L)',draft),'42501');
 perform pg_temp.rx_reject(format('select public.rm_receiving_draft_v1(repeat(''6'',64),''save'',%L,%L,1,%L)',draft,contents,pg_temp.rx_id(92)),'42501');
 perform pg_temp.rx_reject(format('select public.rm_mobile_open_receiving_v1(%L,%L,repeat(''6'',64))',draft,receipt),'42501');
 perform pg_temp.rx_reject(format('select public.rm_mobile_mutate_v1(%L,''rm_submit_recebimento_v1'',%L,repeat(''6'',64))',draft,receipt),'42501');
 reset role;

 perform pg_temp.rx_check((pg_temp.rx_draft_workshop(1,save_command||jsonb_build_object('payload',contents))->>'revision')::int=2,
  'the current scoped operator can continue editing the same draft');
 project:=(pg_temp.rx_call(draft,'open',receipt)->>'projeto_id')::uuid;
 completed:=pg_temp.rx_call(draft,'complete',receipt);
 repeated:=pg_temp.rx_call(draft,'complete',receipt);
 perform pg_temp.rx_check(project is not null and (completed->>'projeto_id')::uuid=project and (repeated->>'idempotent_replay')::boolean
  and exists(select 1 from rm_private.receiving_drafts d where id=draft and state='finalized' and operator_id=original.operator_id)
  and (select count(*)=1 from rm_private.mobile_mutation_receipts where client_submission_id=draft),
  'recovered draft proceeds through opening and completion once with the original actor');
end
$pristine_recovery$;
select 'PASS: pristine legacy draft recovery preserves exact provenance, denies raw routes and completes idempotently' result;

do $legacy_recovery$
declare
 opening_id uuid:=pg_temp.rx_id(160);
 complete_id uuid:=pg_temp.rx_id(161);
 final_id uuid:=pg_temp.rx_id(162);
 replay_open_id uuid:=pg_temp.rx_id(163);
 other_operator uuid:=pg_temp.rx_id(165);
 args jsonb;
 finalized_arguments jsonb;
 result jsonb;
 original_project public.rm_projetos;
 original_receipt rm_private.mobile_mutation_receipts;
 project uuid;
 crossed_command jsonb;
begin
 args:=pg_temp.rx_payload(opening_id,'open');
 set local role authenticated;
 result:=public.rm_mobile_open_receiving_v1(opening_id,args,repeat('6',64));
 reset role;
 project:=(result->>'projeto_id')::uuid;
 select * into strict original_project from public.rm_projetos where id=project;
 perform pg_temp.rx_check(not exists(select 1 from rm_private.workshop_project_ownership where id=project),
  'an earlier legacy opening has no artificial owner');
 crossed_command:=args||jsonb_build_object('p_projeto_id',project);
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''open'',%L)',pg_temp.rx_id(164),crossed_command),'42501');
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''open'',%L)',opening_id,args||'{"p_nota_fiscal":"changed"}'),'42501');
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''open'',%L,2)',opening_id,args),'42501');

 insert into public.rm_users(id,nome,perfil) values(other_operator,'Other local operator','mobile');
 insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest(repeat('b',64),'sha256'),pg_temp.rx_id(11),pg_temp.rx_id(13),other_operator,clock_timestamp()+interval '1 hour');
 crossed_command:=args||jsonb_build_object('p_operador_id',other_operator);
 perform public.rm_authorize_mobile_receiving_workshop_v1(pg_temp.rx_id(11),pg_temp.rx_id(12),repeat('b',64),
  jsonb_set(pg_temp.rx_context(1),'{principals,1,subject}',to_jsonb(other_operator)),opening_id,'open',crossed_command);
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_receiving_workshop_v1(%L,''open'',%L,repeat(''b'',64))',opening_id,crossed_command),'42501');
 reset role;
 delete from rm_private.mobile_receiving_workshop_permits where submission_id=opening_id and phase='open' and operator_id=other_operator;

 update public.rm_projetos set cliente_id=pg_temp.rx_id(957) where id=project;
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''open'',%L)',opening_id,args),'42501');
 perform pg_temp.rx_check(not exists(select 1 from rm_private.receiving_project_recoveries where submission_id=opening_id),
  'an inconsistent project or changed request cannot grant origin');
 update public.rm_projetos set cliente_id=original_project.cliente_id where id=project;
 select * into strict original_project from public.rm_projetos where id=project;
 result:=pg_temp.rx_call(opening_id,'open',args);
 perform pg_temp.rx_check((result->>'projeto_id')::uuid=project and (result->>'idempotent_replay')::boolean
  and (select to_jsonb(p)=to_jsonb(original_project) from public.rm_projetos p where id=project)
  and exists(select 1 from rm_private.receiving_project_recoveries a where a.submission_id=opening_id and a.project_id=project
   and a.operator_id=pg_temp.rx_id(14) and a.auth_user_id=pg_temp.rx_id(11) and a.workshop_id=pg_temp.rx_id(1) and a.basis='opening_original'),
  'the exact old opening adds an audited origin to its existing project and preserves the project data');
 perform pg_temp.rx_check(
  rm_private.workshop_receiving_read_v1('{"page":1,"q":"Local intake 066","reason":"all"}',pg_temp.rx_id(1))->'items'
    @> jsonb_build_array(jsonb_build_object('id',project))
  and not (rm_private.workshop_receiving_read_v1('{"page":1,"q":"Local intake 066","reason":"all"}',pg_temp.rx_id(2))->'items'
    @> jsonb_build_array(jsonb_build_object('id',project))), 'the recovered project appears only in its workshop inbox');
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_open_receiving_v1(%L,%L,repeat(''6'',64))',opening_id,args),'42501');
 reset role;
 finalized_arguments:=pg_temp.rx_payload(opening_id,'complete');
 result:=pg_temp.rx_call(opening_id,'complete',finalized_arguments);
 perform pg_temp.rx_check((result->>'projeto_id')::uuid=project and (select count(*)=1 from public.rm_fotos where projeto_id=project)
  and (select count(*)=1 from public.rm_documentos where projeto_id=project), 'the recovered opening uploads and finalizes once');

 args:=pg_temp.rx_payload(complete_id,'complete');
 set local role authenticated;
 result:=public.rm_mobile_mutate_v1(complete_id,'rm_submit_recebimento_v1',args,repeat('6',64));
 reset role;
 project:=(result->>'projeto_id')::uuid;
 select * into strict original_receipt from rm_private.mobile_mutation_receipts where client_submission_id=complete_id;
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''complete'',%L)',complete_id,args||'{"p_eventualidades":"changed"}'),'42501');
 result:=pg_temp.rx_call(complete_id,'complete',args);
 perform pg_temp.rx_check((result->>'projeto_id')::uuid=project and (result->>'idempotent_replay')::boolean
  and (select to_jsonb(r)=to_jsonb(original_receipt) from rm_private.mobile_mutation_receipts r where client_submission_id=complete_id)
  and exists(select 1 from rm_private.receiving_project_recoveries a where a.submission_id=complete_id and a.basis='receipt_exact')
  and (select count(*)=1 from public.rm_fotos where projeto_id=project), 'a completed legacy submission gains origin without replacing the receipt or adding photos');
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_mutate_v1(%L,''rm_submit_recebimento_v1'',%L,repeat(''6'',64))',complete_id,args),'42501');
 perform pg_temp.rx_reject(format('select rm_private.recover_legacy_receiving_project_v1(%L,%L,''complete'',%L,%L,%L)',
  complete_id,project,args,pg_temp.rx_id(14),pg_temp.rx_id(1)),'42501');
 reset role;
 result:=pg_temp.rx_call(complete_id,'complete',args);
 perform pg_temp.rx_check((result->>'idempotent_replay')::boolean and
  (select count(*)=1 from rm_private.receiving_project_recoveries where submission_id=complete_id),'scoped replay preserves one origin confirmation');

 args:=pg_temp.rx_payload(final_id,'open');
 set local role authenticated;
 result:=public.rm_mobile_open_receiving_v1(final_id,args,repeat('6',64));
 reset role;
 project:=(result->>'projeto_id')::uuid;
 result:=pg_temp.rx_call(final_id,'complete',pg_temp.rx_payload(final_id,'complete'));
 perform pg_temp.rx_check((result->>'projeto_id')::uuid=project
  and exists(select 1 from rm_private.receiving_project_recoveries where submission_id=final_id and basis='opening_metadata'),
  'valid final media can resume the original unclassified opening without another open step');

 args:=pg_temp.rx_payload(replay_open_id,'complete');
 set local role authenticated;
 result:=public.rm_mobile_mutate_v1(replay_open_id,'rm_submit_recebimento_v1',args,repeat('6',64));
 reset role;
 project:=(result->>'projeto_id')::uuid;
 result:=pg_temp.rx_call(replay_open_id,'open',pg_temp.rx_payload(replay_open_id,'open'));
 perform pg_temp.rx_check((result->>'projeto_id')::uuid=project and result->'attachments_pending'='false'::jsonb
  and (result->>'idempotent_replay')::boolean
  and exists(select 1 from rm_private.receiving_project_recoveries where submission_id=replay_open_id and basis='receipt_metadata'),
  'the older completion confirms metadata once even when the client still has the original local file paths');
 perform pg_temp.rx_check((select count(*)=4 and bool_and(creation_phase is null)
  from rm_private.receiving_workshop_protocols p where p.submission_id in(opening_id,complete_id,final_id,replay_open_id))
  and not exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1() proof
   where proof.submission_id in(opening_id,complete_id,final_id,replay_open_id)),
  'legacy opening and completion recovery cannot pass as new project creation');
end
$legacy_recovery$;
select 'PASS: exact receiving replay classifies legacy openings and receipts without changing authors, attachments or project IDs' result;

do $protocols$
declare
 sid uuid:=pg_temp.rx_id(989);
 qr uuid:=pg_temp.rx_id(990);
 offline uuid:=pg_temp.rx_id(991);
 args jsonb:=pg_temp.rx_payload(sid,'open');
 intake jsonb;
 prior rm_private.receiving_workshop_protocols;
 foreign_args jsonb;
begin
 perform pg_temp.rx_mint(sid,'open',args);
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_open_receiving_v1(%L,%L,repeat(''6'',64))',sid,args),'42501');
 reset role;
 perform pg_temp.rx_check(not exists(select 1 from rm_private.receiving_openings where client_submission_id=sid),
  'a pending permit cannot be presented over the raw RPC');
 intake:=pg_temp.rx_call(sid,'open',args);
 select * into strict prior from rm_private.receiving_workshop_protocols where submission_id=sid;
 perform pg_temp.rx_check(prior.project_id=(intake->>'projeto_id')::uuid and prior.operator_id=pg_temp.rx_id(14)
  and prior.workshop_id=pg_temp.rx_id(1) and prior.opened_at is not null and prior.completed_at is null,
  'verified opening records the original team, project and phase');
 perform pg_temp.rx_check((pg_temp.rx_call(sid,'open',args)->>'idempotent_replay')::boolean
  and (select opened_at from rm_private.receiving_workshop_protocols where submission_id=sid)=prior.opened_at,
  'opening replay preserves original verification');
 args:=pg_temp.rx_payload(sid,'complete');
 perform pg_temp.rx_mint(sid,'complete',args);
 foreign_args:=pg_temp.rx_payload(qr,'open')||jsonb_build_object('p_projeto_id',pg_temp.rx_id(779));
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_mutate_v1(%L,''rm_submit_recebimento_v1'',%L,repeat(''6'',64))',sid,args),'42501');
 perform pg_temp.rx_reject(format('select public.rm_mobile_open_receiving_v1(%L,%L,repeat(''6'',64))',qr,foreign_args),'42501');
 perform pg_temp.rx_reject(format('select public.rm_mobile_mutate_v1(%L,''rm_submit_recebimento_v1'',%L,repeat(''6'',64))',qr,foreign_args),'42501');
 perform pg_temp.rx_reject(format('select public.rm_mobile_open_receiving_v1(%L,%L,repeat(''6'',64))',qr,
  pg_temp.rx_payload(qr,'open')||jsonb_build_object('p_cliente_id',pg_temp.rx_id(750))),'42501');
 reset role;
 intake:=pg_temp.rx_call(sid,'complete',args);
 perform pg_temp.rx_check(prior.project_id=(intake->>'projeto_id')::uuid and exists(
  select 1 from rm_private.receiving_workshop_protocols where submission_id=sid and opened_at=prior.opened_at and completed_at is not null),
  'authorized completion establishes both phases without creating another project');
 perform pg_temp.rx_check((pg_temp.rx_call(sid,'complete',args)->>'idempotent_replay')::boolean,
  'authorized exact replay remains available');

 -- Repeat the fallback with the actual production activation function. From
 -- here on, raw BMA QR and offline completions also need current verification.
 update rm_private.sso_settings set require_sso=true;
 perform rm_private.activate_root_creation_v1(repeat('8',40),pg_temp.rx_id(997));
 set constraints all immediate;
 perform rm_private.activate_workshop_root_enforcement_v1();
 perform rm_private.activate_workshop_root_enforcement_v1();
 set constraints all deferred;
 args:=pg_temp.rx_payload(offline,'complete');
 set local role authenticated;
 perform pg_temp.rx_reject(format('select public.rm_mobile_mutate_v1(%L,''rm_submit_recebimento_v1'',%L,repeat(''6'',64))',offline,args),'42501');
 perform pg_temp.rx_reject(format('select public.rm_mobile_open_receiving_v1(%L,%L,repeat(''6'',64))',qr,
  pg_temp.rx_payload(qr,'open')||jsonb_build_object('p_projeto_id',prior.project_id)),'42501');
 reset role;
 intake:=pg_temp.rx_call(qr,'open',pg_temp.rx_payload(qr,'open')||jsonb_build_object('p_projeto_id',prior.project_id));
 perform pg_temp.rx_check((intake->>'projeto_id')::uuid=prior.project_id and exists(select 1 from rm_private.receiving_workshop_protocols
  where submission_id=qr and creation_phase is null) and not exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1()
  where submission_id=qr),'authorized QR updates never qualify as new project creation');
 intake:=pg_temp.rx_call(offline,'complete',args);
 set constraints workshop_new_project_origin immediate;
 perform pg_temp.rx_check(exists(select 1 from rm_private.receiving_workshop_protocols p
  join rm_private.mobile_mutation_receipts r on r.client_submission_id=p.submission_id and r.operator_id=p.operator_id
  join rm_private.workshop_project_ownership o on o.id=p.project_id and o.workshop_id=p.workshop_id
  where p.submission_id=offline and p.opened_at is null and p.completed_at is not null
   and p.project_id=(intake->>'projeto_id')::uuid and p.workshop_id=pg_temp.rx_id(1)),
  'offline completion alone creates project, origin, exact receipt and evidence in one transaction');
 perform pg_temp.rx_check(not has_table_privilege('authenticated','rm_private.receiving_workshop_protocols','select')
  and not has_table_privilege('service_role','rm_private.receiving_workshop_protocols','update')
  and not has_function_privilege('authenticated','rm_private.workshop_receiving_creation_evidence_v1()','execute')
  and not has_function_privilege('service_role','rm_private.workshop_receiving_pilot_ready_v1()','execute'),
  'receiving proofs may not be read or changed directly');
end
$protocols$;
select 'PASS: native receiving uses a transaction-bound workshop proof with phase, origin and offline replay' result;
select 'PASS: only new scoped receiving with an exact completion can qualify the pilot and activate the root guard' result;
rollback;

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
 perform pg_temp.rx_check((select workshop_id=pg_temp.rx_id(1) from rm_private.workshop_project_ownership where id=pid),'early project records its workshop');
 perform pg_temp.rx_check(exists(select 1 from public.rm_projetos where id=pid and numero is null and tipo_equipamento_id is null),'early project preserves blank OS and type');
 perform pg_temp.rx_check(exists(select 1 from jsonb_array_elements(public.rm_web_receivings_v1('all','Local intake 066',1,100)->'items') p where p->>'id'=pid::text),'portal immediately lists the scoped project');
 perform pg_temp.rx_check((pg_temp.rx_call(sid,'open',pg_temp.rx_payload(sid,'open'))->>'idempotent_replay')::boolean,'early retry keeps project');
 perform pg_temp.rx_reject(format('select pg_temp.rx_call(%L,''complete'',pg_temp.rx_payload(%L,''complete''),2)',sid,sid),'42501');
 received:=pg_temp.rx_call(sid,'complete',pg_temp.rx_payload(sid,'complete'));
 perform pg_temp.rx_check(received->>'projeto_id'=pid::text,'final receipt uses the original project');
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
rollback;

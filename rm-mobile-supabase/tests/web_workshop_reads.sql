\set ON_ERROR_STOP on
begin;
create function pg_temp.wr_id(n int) returns uuid language sql immutable as $$select ('05900000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.wr_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.wr_deny(statement text,state text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlstate=state then return;end if;raise;end;raise exception 'FAIL: request unexpectedly accepted';end$$;
create function pg_temp.wr_context(office int default 1) returns jsonb language sql as $$select jsonb_build_object(
 'version',2,'application','em','channel','web','authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
 'workshop',jsonb_build_object('id',pg_temp.wr_id(office),'code',case office when 1 then 'BMA' else 'BRJ' end,'name','LOCAL office','active',true,'revision',1,'updated_at',stamp),
 'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','subject',pg_temp.wr_id(14),'revision',1)),
 'issued_at',stamp,'expires_at',stamp+interval '5 minutes') from(select clock_timestamp() stamp)s;$$;
create function pg_temp.wr_mint(rid uuid,resource text,args jsonb,office int default 1) returns void language sql as $$
 select public.rm_sso_workshop_read_permit_v1(repeat('6',64),rid,resource,args,pg_temp.wr_context(office));$$;
create function pg_temp.wr_call(resource text,args jsonb,office int default 1) returns jsonb language plpgsql as $$declare rid uuid:=gen_random_uuid();r jsonb;begin
 perform pg_temp.wr_mint(rid,resource,args,office);set local role authenticated;r:=public.rm_web_workshop_read_v1(rid,resource,args);reset role;
 perform pg_temp.wr_check(r->>'request_id'=rid::text and r->>'resource'=resource and r->>'workshop_id'=pg_temp.wr_id(office)::text,'response binds exact request/office/resource');return r->'data';
 exception when others then reset role;raise;end$$;
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"05900000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05900000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05900000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',(select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into auth.users(id) values(pg_temp.wr_id(11));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.wr_id(12),pg_temp.wr_id(11),'LOCAL read admin','administrador');
insert into auth.sessions(id,user_id) values(pg_temp.wr_id(13),pg_temp.wr_id(11));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 (pg_temp.wr_id(15),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.wr_id(14),pg_temp.wr_id(12),pg_temp.wr_id(11),true,pg_temp.wr_id(12),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('6',64),pg_temp.wr_id(15),pg_temp.wr_id(13),'opaque-local-read-session',clock_timestamp()+interval '30 minutes');
select set_config('request.jwt.claim.sub',pg_temp.wr_id(11)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.wr_id(13),'aal','aal1')::text,true);
insert into public.rm_clientes(id,nome,codigo) select pg_temp.wr_id(100+n),'LOCAL client '||lpad(n::text,3,'0'),case when n in(1,2,56) then 'needle' end from generate_series(1,59)n;
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) select 'client',pg_temp.wr_id(100+n),pg_temp.wr_id(case when n<=55 then 1 else 2 end) from generate_series(1,58)n;
insert into public.rm_tipos_equipamento(id,nome,sigla) values(pg_temp.wr_id(201),'LOCAL BMA type','BMA'),(pg_temp.wr_id(202),'LOCAL BRJ type','BRJ'),(pg_temp.wr_id(203),'LOCAL unknown type','UNK');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('equipment_type',pg_temp.wr_id(201),pg_temp.wr_id(1)),('equipment_type',pg_temp.wr_id(202),pg_temp.wr_id(2));
insert into public.rm_forms(id,titulo,imagem_capa_url) values(pg_temp.wr_id(301),'LOCAL BMA model','https://private.invalid/cover'),(pg_temp.wr_id(302),'LOCAL BRJ model','https://private.invalid/other'),(pg_temp.wr_id(303),'LOCAL unknown model',null);
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('form_model',pg_temp.wr_id(301),pg_temp.wr_id(1)),('form_model',pg_temp.wr_id(302),pg_temp.wr_id(2));
insert into public.rm_form_template_families(id,created_by) values(pg_temp.wr_id(401),pg_temp.wr_id(12)),(pg_temp.wr_id(402),pg_temp.wr_id(12)),(pg_temp.wr_id(403),pg_temp.wr_id(12));
insert into public.rm_form_template_drafts(id,family_id,kind,content,source_snapshot,created_by,updated_by)
 select pg_temp.wr_id(n),pg_temp.wr_id(n),'new','{"titulo":"LOCAL draft","descricao":null,"title":null,"description":null,"tipo":null,"questions":[]}',
 '{"usa_aprovacao":true,"imagem_capa_url":"https://private.invalid/secret","celulas_ids":["05900000-0000-4000-8000-000000000999"],"equipes_ids":["05900000-0000-4000-8000-000000000998"]}',pg_temp.wr_id(12),pg_temp.wr_id(12) from generate_series(401,403)n;
insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) select k,pg_temp.wr_id(n),pg_temp.wr_id(n-400) from generate_series(401,402)n cross join unnest(array['family','draft'])k;
create temporary table wr_before on commit drop as select(select count(*) from public.rm_clientes) clients,(select count(*) from public.rm_forms) forms,(select count(*) from rm_private.web_mutation_receipts) receipts;

do $$declare r jsonb;r2 jsonb;begin
 r:=pg_temp.wr_call('catalog_list','{"kind":"clients","q":"","page":1}');r2:=pg_temp.wr_call('catalog_list','{"kind":"clients","q":"","page":2}');
 perform pg_temp.wr_check((r->>'total')::int=55 and jsonb_array_length(r->'rows')=50 and jsonb_array_length(r2->'rows')=5,'scope before total and pagination');
 perform pg_temp.wr_check((pg_temp.wr_call('catalog_list','{"kind":"clients","q":"needle","page":1}')->>'total')::int=2,'search cannot count another office');
 perform pg_temp.wr_check((pg_temp.wr_call('catalog_list','{"kind":"clients","q":"","page":1}',2)->>'total')::int=3,'second office has own total');
 perform pg_temp.wr_check(pg_temp.wr_call('catalog_entry',jsonb_build_object('kind','clients','id',pg_temp.wr_id(156)))='null'::jsonb,'cross office UUID returns no record');
 perform pg_temp.wr_check(pg_temp.wr_call('catalog_entry',jsonb_build_object('kind','clients','id',pg_temp.wr_id(159)))='null'::jsonb,'unknown root not exposed');
 perform pg_temp.wr_check(pg_temp.wr_call('catalog_entry',jsonb_build_object('kind','clients','id',pg_temp.wr_id(101)))->>'id'=pg_temp.wr_id(101)::text,'own entry exact ID');
 perform pg_temp.wr_check((pg_temp.wr_call('catalog_list','{"kind":"types","q":"","page":1}')->>'total')::int=1,'types scoped');
 perform pg_temp.wr_check((pg_temp.wr_call('catalog_list','{"kind":"forms","q":"","page":1}')->>'total')::int=1,'form catalog scoped');
 r:=pg_temp.wr_call('template_list','{"q":"","state":"all","page":1}');
 perform pg_temp.wr_check((r->>'draftTotal')::int=1 and(r->>'publishedTotal')::int=1,'template lists count only own active origins');
 r:=pg_temp.wr_call('template_draft',jsonb_build_object('id',pg_temp.wr_id(401)));
 perform pg_temp.wr_check(r->'draft'->'source_snapshot'->'has_cover'='true'::jsonb and r->'draft'->'source_snapshot'->'links_redacted'='true'::jsonb
  and strpos(r::text,'private.invalid')=0 and strpos(r::text,'celulas_ids')=0 and strpos(r::text,'equipes_ids')=0,'draft response redacts URLs and operational association IDs');
 perform pg_temp.wr_check(pg_temp.wr_call('template_draft',jsonb_build_object('id',pg_temp.wr_id(402)))='null'::jsonb,'other draft hidden');
 perform pg_temp.wr_check(pg_temp.wr_call('template_form',jsonb_build_object('id',pg_temp.wr_id(302)))='null'::jsonb,'other form hidden');
 r:=pg_temp.wr_call('template_form',jsonb_build_object('id',pg_temp.wr_id(301)));
 perform pg_temp.wr_check(r->'source_snapshot'->'has_cover'='true'::jsonb and strpos(r::text,'private.invalid')=0,'own source safe');
 perform pg_temp.wr_check(jsonb_typeof(pg_temp.wr_call('template_choices','{}'))='array','shared enum vocabulary bounded to allowed sets');
end$$;

-- A question's option cannot pull content from another form through an inconsistent legacy link.
insert into public.rm_questoes(id,form_id,indice,enunciado,tipo) values(pg_temp.wr_id(501),pg_temp.wr_id(301),1,'LOCAL own question','texto_curto');
insert into public.rm_itens_questoes(id,form_id,questao_id,indice,descricao) values(pg_temp.wr_id(502),pg_temp.wr_id(302),pg_temp.wr_id(501),1,'LOCAL cross option');
select pg_temp.wr_check(pg_temp.wr_call('template_form',jsonb_build_object('id',pg_temp.wr_id(301)))='null'::jsonb,'inconsistent nested source refused');
delete from public.rm_itens_questoes where id=pg_temp.wr_id(502);
-- An unclassified family must not masquerade as an ordinary legacy v1.
insert into public.rm_form_template_versions(family_id,version,form_id,legacy,published_by) values(pg_temp.wr_id(403),7,pg_temp.wr_id(301),true,pg_temp.wr_id(12));
select pg_temp.wr_check((pg_temp.wr_call('template_list','{"q":"","state":"all","page":1}')->>'publishedTotal')::int=0,'unclassified version metadata hidden before count');
delete from public.rm_form_template_versions where form_id=pg_temp.wr_id(301);

-- Reader requires exact body/resource, same Auth session, current MFA and one-use authorization.
select pg_temp.wr_mint(pg_temp.wr_id(601),'catalog_list','{"kind":"clients","q":"","page":1}');
set local role authenticated;
select pg_temp.wr_deny('select public.rm_sso_workshop_read_permit_v1(repeat(''6'',64),gen_random_uuid(),''template_choices'',''{}'',pg_temp.wr_context())','42501');
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(601),''catalog_list'',''{"kind":"clients","q":"","page":2}'')','42501');
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(601),''template_list'',''{"kind":"clients","q":"","page":1}'')','42501');
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.wr_id(99),'aal','aal1')::text,true);
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(601),''catalog_list'',''{"kind":"clients","q":"","page":1}'')','42501');
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.wr_id(13),'aal','aal1')::text,true);
select public.rm_web_workshop_read_v1(pg_temp.wr_id(601),'catalog_list','{"kind":"clients","q":"","page":1}');
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(601),''catalog_list'',''{"kind":"clients","q":"","page":1}'')','42501');
reset role;
select pg_temp.wr_deny('select pg_temp.wr_call(''catalog_list'',''{"kind":"clients","q":"","page":1,"workshop_id":"BRJ"}'')','22023');
select pg_temp.wr_deny('select pg_temp.wr_call(''template_list'',''{"q":"","state":"all","page":10001}'')','22023');
select pg_temp.wr_mint(pg_temp.wr_id(602),'template_choices','{}');
update rm_private.workshop_read_permits set expires_at=clock_timestamp()-interval '1 second' where read_id=pg_temp.wr_id(602);
set local role authenticated;
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(602),''template_choices'',''{}'')','42501');
reset role;
select pg_temp.wr_mint(pg_temp.wr_id(603),'template_choices','{}');
insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.wr_id(11),'totp','verified');
set local role authenticated;
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(603),''template_choices'',''{}'')','42501');
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.wr_id(13),'aal','aal2')::text,true);
select public.rm_web_workshop_read_v1(pg_temp.wr_id(603),'template_choices','{}');
reset role;
update public.rm_users set perfil='auditor' where id=pg_temp.wr_id(12);
select pg_temp.wr_check((pg_temp.wr_call('catalog_list','{"kind":"types","q":"","page":1}')->>'total')::int=1,'auditor retains scoped reading');
select pg_temp.wr_deny(format('select pg_temp.wr_call(''catalog_entry'',%L)',jsonb_build_object('kind','types','id',pg_temp.wr_id(201))),'42501');
select pg_temp.wr_mint(pg_temp.wr_id(604),'template_choices','{}');
update rm_private.sso_identity_bindings set enabled=false where id=pg_temp.wr_id(15);
set local role authenticated;
select pg_temp.wr_deny('select public.rm_web_workshop_read_v1(pg_temp.wr_id(604),''template_choices'',''{}'')','42501');
reset role;
select public.rm_sso_session_delete_v1(repeat('6',64));
select pg_temp.wr_check(not exists(select 1 from rm_private.workshop_read_permits),'logout cascades read authorizations');
select pg_temp.wr_check((select clients=(select count(*) from public.rm_clientes) and forms=(select count(*) from public.rm_forms) and receipts=(select count(*) from rm_private.web_mutation_receipts) from wr_before),'reading does not mutate business records or receipts');
select pg_temp.wr_check(not has_table_privilege('service_role','rm_private.workshop_read_permits','select')
 and not has_function_privilege('service_role','public.rm_web_workshop_read_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('authenticated','rm_private.workshop_read_data_v1(text,jsonb,uuid)','execute'),'no bypass of reader boundary');
select 'PASS: workshop portal reads, counts/search/pagination, two offices/unknown roots, nested metadata, body/session binding, one use, MFA and logout' result;
rollback;

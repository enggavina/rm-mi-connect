\set ON_ERROR_STOP on
begin;
create function pg_temp.tw_id(n int) returns uuid language sql immutable as $$select ('05800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.tw_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.tw_deny(statement text,state text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlstate=state then return;end if;raise;end;raise exception 'FAIL: request unexpectedly accepted: %',statement;end$$;
create function pg_temp.tw_context(office int default 1) returns jsonb language sql as $$
 select jsonb_build_object('version',2,'application','em','channel','web','authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
 'workshop',jsonb_build_object('id',pg_temp.tw_id(office),'code',case office when 1 then 'BMA' else 'BRJ' end,'name','LOCAL office','active',true,'revision',1,'updated_at',stamp),
 'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','subject',pg_temp.tw_id(14),'revision',1)),
 'issued_at',stamp,'expires_at',stamp+interval '5 minutes') from(select clock_timestamp() stamp)s;$$;
create function pg_temp.tw_create(ident uuid,kind text default 'new',source uuid default null) returns jsonb language sql as $$
 select jsonb_build_object('id',ident,'kind',kind,'source_form_id',source);$$;
create function pg_temp.tw_content() returns jsonb language sql as $$select jsonb_build_object('titulo','LOCAL scoped form','descricao',null,'title',null,'description',null,'tipo',null,
 'questions',jsonb_build_array(jsonb_build_object('id',pg_temp.tw_id(99),'indice','1','enunciado','LOCAL question','title',null,'subtitulo',null,'tag',null,'tipo','texto_curto',
 'subtipo',null,'dimensoes',null,'obrigatorio',false,'colaborador_filtro_perfil',null,'items','[]'::jsonb)));$$;
create function pg_temp.tw_mint(rid uuid,operation text,payload jsonb,office int default 1) returns void language sql as $$
 select public.rm_sso_template_workshop_permit_v1(repeat('8',64),rid,operation,payload,pg_temp.tw_context(office));$$;
create function pg_temp.tw_call(rid uuid,operation text,payload jsonb,office int default 1) returns jsonb language plpgsql as $$declare result jsonb;begin
 perform pg_temp.tw_mint(rid,operation,payload,office);set local role authenticated;result:=public.rm_web_mutate_v1(rid,operation,payload);reset role;return result;
 exception when others then reset role;raise;end$$;

insert into auth.users(id) values(pg_temp.tw_id(11));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.tw_id(12),pg_temp.tw_id(11),'LOCAL template admin','administrador');
insert into auth.sessions(id,user_id) values(pg_temp.tw_id(13),pg_temp.tw_id(11));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 (pg_temp.tw_id(15),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.tw_id(14),pg_temp.tw_id(12),pg_temp.tw_id(11),true,pg_temp.tw_id(12),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('8',64),pg_temp.tw_id(15),pg_temp.tw_id(13),'opaque-local-template-session',clock_timestamp()+interval '30 minutes');
select set_config('request.jwt.claim.sub',pg_temp.tw_id(11)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.tw_id(13),'aal','aal1')::text,true);
insert into public.rm_forms(id,titulo) values(pg_temp.tw_id(20),'LOCAL original BMA model');
insert into public.rm_form_template_families(id,created_by) values(pg_temp.tw_id(21),pg_temp.tw_id(12));
insert into public.rm_form_template_drafts(id,family_id,kind,content,source_snapshot,created_by,updated_by)
 values(pg_temp.tw_id(21),pg_temp.tw_id(21),'new','{"titulo":"","descricao":null,"title":null,"description":null,"tipo":null,"questions":[]}',
 '{"usa_aprovacao":true,"imagem_capa_url":null,"celulas_ids":[],"equipes_ids":[]}',pg_temp.tw_id(12),pg_temp.tw_id(12));
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"05800000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05800000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05800000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',(select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
select rm_private.workshop_catalog_adopt_bma_v1('f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff',
 (select count(*) from public.rm_clientes),(select count(*) from public.rm_tipos_equipamento),(select count(*) from public.rm_forms));
select pg_temp.tw_deny('select rm_private.adopt_workshop_templates_bma_v1(999,999)','PT409');
select rm_private.adopt_workshop_templates_bma_v1((select count(*) from public.rm_form_template_families),(select count(*) from public.rm_form_template_drafts));
select pg_temp.tw_check((rm_private.adopt_workshop_templates_bma_v1((select families from rm_private.workshop_template_adoption),(select drafts from rm_private.workshop_template_adoption))->>'replayed')::boolean,'exact adoption replay');
update rm_private.sso_settings set require_sso=true;
select rm_private.activate_catalog_workshop_writes_v1(repeat('a',40),pg_temp.tw_id(90));
select rm_private.activate_template_workshop_writes_v1(repeat('a',40),pg_temp.tw_id(90));
select pg_temp.tw_check((rm_private.activate_template_workshop_writes_v1(repeat('a',40),pg_temp.tw_id(90))->>'replayed')::boolean,'exact activation retry');
select pg_temp.tw_deny(format('select rm_private.activate_template_workshop_writes_v1(%L,%L)',repeat('b',40),pg_temp.tw_id(90)),'PT409');

-- Old v1 permits and browser calls cannot bypass the new guard.
do $$declare bad jsonb;begin
 foreach bad in array array[pg_temp.tw_context()||'{"extra":true}',jsonb_set(pg_temp.tw_context(),'{channel}','"mobile"'),jsonb_set(pg_temp.tw_context(),'{workshop,active}','false')] loop
  perform pg_temp.tw_deny(format('select public.rm_sso_template_workshop_permit_v1(%L,%L,%L,%L,%L)',repeat('8',64),gen_random_uuid(),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(30)),bad),'22023');
 end loop;
 perform pg_temp.tw_deny(format('select public.rm_sso_template_workshop_permit_v1(%L,%L,%L,%L,%L)',repeat('8',64),gen_random_uuid(),'save_catalog','{"kind":"clients"}',pg_temp.tw_context()),'22023');
 perform pg_temp.tw_deny(format('select public.rm_sso_template_workshop_permit_v1(%L,%L,%L,%L,%L)',repeat('8',64),gen_random_uuid(),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(30)),jsonb_set(pg_temp.tw_context(),'{principals,0,subject}',to_jsonb(pg_temp.tw_id(99)))),'42501');
end$$;
select public.rm_sso_action_permit_v1(repeat('8',64),pg_temp.tw_id(31),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(30)),'em.form_templates.manage');
set local role authenticated;
select pg_temp.tw_deny('select public.rm_web_mutate_v1(pg_temp.tw_id(31),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(30)))','42501');
select pg_temp.tw_deny('select pg_temp.tw_mint(pg_temp.tw_id(31),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(30)))','42501');
reset role;
set local role service_role;
select pg_temp.tw_mint(pg_temp.tw_id(31),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(30)));
reset role;
select pg_temp.tw_deny('select pg_temp.tw_mint(pg_temp.tw_id(31),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(30)),2)','23505');
set local role authenticated;
select public.rm_web_mutate_v1(pg_temp.tw_id(31),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(30)));
reset role;
select pg_temp.tw_check((pg_temp.tw_call(pg_temp.tw_id(31),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(30)))->>'idempotent_replay')::boolean,'fresh create replay');
select pg_temp.tw_check((select count(*)=2 from rm_private.workshop_template_ownership where object_id=pg_temp.tw_id(30) and workshop_id=pg_temp.tw_id(1)),'new family and draft classified atomically');

-- Save, publish, mappings, version/copy and deletion retain their old contracts.
do $$declare rid uuid:=gen_random_uuid();p jsonb;r jsonb;fid uuid;v uuid;begin
 p:=jsonb_build_object('id',pg_temp.tw_id(30),'expected_updated_at',(select updated_at from public.rm_form_template_drafts where id=pg_temp.tw_id(30)),'content',pg_temp.tw_content());
 r:=pg_temp.tw_call(rid,'save_form_template',p);
 perform pg_temp.tw_check((pg_temp.tw_call(rid,'save_form_template',p)->>'idempotent_replay')::boolean,'save replay');
 p:=jsonb_build_object('id',pg_temp.tw_id(30),'expected_updated_at',r->>'updated_at');rid:=gen_random_uuid();
 r:=pg_temp.tw_call(rid,'publish_form_template',p);fid:=(r->'publication'->>'form_id')::uuid;
 perform pg_temp.tw_check(rm_private.workshop_catalog_scope_v1('form_model',fid)=pg_temp.tw_id(1),'publication owns same office');
 perform pg_temp.tw_check((pg_temp.tw_call(rid,'publish_form_template',p)->>'idempotent_replay')::boolean,'publication replay');
 perform pg_temp.tw_deny(format('update public.rm_forms set titulo=''TAMPERED'' where id=%L',fid),'55000');
 r:=pg_temp.tw_call(gen_random_uuid(),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(40),'copy',fid));
 perform pg_temp.tw_check(r->'record'->>'family_id'=pg_temp.tw_id(40)::text,'copy is independent family');
 perform pg_temp.tw_call(gen_random_uuid(),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(41),'version',fid));
 perform pg_temp.tw_check((select family_id=pg_temp.tw_id(30) from public.rm_form_template_drafts where id=pg_temp.tw_id(41)),'version retains family');
 p:=jsonb_build_object('id',pg_temp.tw_id(40),'kind','draft','confirmed',true,'expected_updated_at',(select updated_at from public.rm_form_template_drafts where id=pg_temp.tw_id(40)));
 rid:=gen_random_uuid();perform pg_temp.tw_call(rid,'delete_form_template',p);
 perform pg_temp.tw_check((pg_temp.tw_call(rid,'delete_form_template',p)->>'idempotent_replay')::boolean,'draft delete replay');
 perform pg_temp.tw_check((select count(*)=2 from rm_private.workshop_template_retirements where object_id=pg_temp.tw_id(40)),'deleted copy retains family/draft origins');
 perform pg_temp.tw_deny(format('select pg_temp.tw_call(%L,''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(40)))',gen_random_uuid()),'PT410');
end$$;

-- Legacy version registration classifies its family without rewriting source.
select pg_temp.tw_call(gen_random_uuid(),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(42),'version',pg_temp.tw_id(20)));
select pg_temp.tw_check(rm_private.workshop_template_scope_v1('family',pg_temp.tw_id(20))=pg_temp.tw_id(1),'legacy version family inherits confirmed office');

-- Unused publication deletion removes exclusive definition rows while keeping origins.
do $$declare r jsonb;p jsonb;fid uuid;rid uuid:=gen_random_uuid();begin
 r:=pg_temp.tw_call(gen_random_uuid(),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(70)));
 r:=pg_temp.tw_call(gen_random_uuid(),'save_form_template',jsonb_build_object('id',pg_temp.tw_id(70),'expected_updated_at',r->>'updated_at','content',pg_temp.tw_content()));
 r:=pg_temp.tw_call(gen_random_uuid(),'publish_form_template',jsonb_build_object('id',pg_temp.tw_id(70),'expected_updated_at',r->>'updated_at'));fid:=(r->'publication'->>'form_id')::uuid;
 p:=jsonb_build_object('id',fid,'kind','form','confirmed',true,'expected_updated_at',(select updated_at from public.rm_forms where id=fid));
 perform pg_temp.tw_call(rid,'delete_form_template',p);
 perform pg_temp.tw_check((pg_temp.tw_call(rid,'delete_form_template',p)->>'idempotent_replay')::boolean,'published deletion replay');
 perform pg_temp.tw_check(not exists(select 1 from public.rm_forms where id=fid) and not exists(select 1 from public.rm_form_template_drafts where id=pg_temp.tw_id(70))
  and exists(select 1 from rm_private.workshop_catalog_retirements where object_id=fid)
  and(select count(*)=2 from rm_private.workshop_template_retirements where object_id=pg_temp.tw_id(70)),'publication delete preserves all three origins');
end$$;

-- Known other office and unknown roots cannot be used as sources or targets.
insert into public.rm_forms(id,titulo) values(pg_temp.tw_id(50),'LOCAL BRJ model'),(pg_temp.tw_id(51),'LOCAL unknown model');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('form_model',pg_temp.tw_id(50),pg_temp.tw_id(2));
select pg_temp.tw_deny('select pg_temp.tw_call(gen_random_uuid(),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(52),''copy'',pg_temp.tw_id(50)))','42501');
select pg_temp.tw_deny('select pg_temp.tw_call(gen_random_uuid(),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(52),''version'',pg_temp.tw_id(51)))','42501');
select pg_temp.tw_deny('update public.rm_form_template_drafts set source_form_id=pg_temp.tw_id(50),kind=''copy'',source_version=1 where id=pg_temp.tw_id(21)','PT409');
select pg_temp.tw_check(not exists(select 1 from public.rm_form_template_drafts where id=pg_temp.tw_id(52)),'refused copy leaves no draft');
-- Later objects never join the adopted batch through replay.
insert into public.rm_form_template_families(id,created_by) values(pg_temp.tw_id(53),pg_temp.tw_id(12));
select rm_private.adopt_workshop_templates_bma_v1((select families from rm_private.workshop_template_adoption),(select drafts from rm_private.workshop_template_adoption));
select pg_temp.tw_check(not exists(select 1 from rm_private.workshop_template_ownership where object_id=pg_temp.tw_id(53)),'no future default');
-- Classification validates indirect links through a not-yet-classified draft.
insert into public.rm_form_template_drafts(id,family_id,kind,source_form_id,source_version,content,source_snapshot,created_by,updated_by)
 values(pg_temp.tw_id(54),pg_temp.tw_id(53),'copy',pg_temp.tw_id(20),1,pg_temp.tw_content(),'{"usa_aprovacao":true,"imagem_capa_url":null,"celulas_ids":[],"equipes_ids":[]}',pg_temp.tw_id(12),pg_temp.tw_id(12));
select pg_temp.tw_deny('insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) values(''family'',pg_temp.tw_id(53),pg_temp.tw_id(2))','PT409');
insert into rm_private.workshop_template_ownership(object_kind,object_id,workshop_id) values('family',pg_temp.tw_id(53),pg_temp.tw_id(1));
select pg_temp.tw_deny('update public.rm_form_template_drafts set source_form_id=pg_temp.tw_id(50) where id=pg_temp.tw_id(54)','PT409');
select pg_temp.tw_deny('insert into public.rm_form_template_versions(family_id,version,form_id,legacy,published_by) values(pg_temp.tw_id(53),1,pg_temp.tw_id(50),true,pg_temp.tw_id(12))','PT409');
update public.rm_form_template_drafts set source_form_id=pg_temp.tw_id(51) where id=pg_temp.tw_id(54);
select pg_temp.tw_deny('insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values(''form_model'',pg_temp.tw_id(51),pg_temp.tw_id(2))','PT409');
select pg_temp.tw_deny(format('select pg_temp.tw_call(%L,''delete_form_template'',%L)',gen_random_uuid(),jsonb_build_object('id',pg_temp.tw_id(50),'kind','form','confirmed',true,'expected_updated_at',(select updated_at from public.rm_forms where id=pg_temp.tw_id(50)))),'42501');

-- A late classification failure rolls back family, draft and business receipt.
create function pg_temp.tw_fail_assignment() returns trigger language plpgsql as $$begin raise exception using errcode='PT409',message='LOCAL classification conflict';end$$;
create trigger tw_local_assignment_failure before insert on rm_private.workshop_template_ownership for each row execute function pg_temp.tw_fail_assignment();
select pg_temp.tw_deny('select pg_temp.tw_call(pg_temp.tw_id(62),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(61)))','PT409');
select pg_temp.tw_check(not exists(select 1 from public.rm_form_template_families where id=pg_temp.tw_id(61)) and not exists(select 1 from public.rm_form_template_drafts where id=pg_temp.tw_id(61))
 and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=pg_temp.tw_id(62)),'late failure rolls back all changes');
drop trigger tw_local_assignment_failure on rm_private.workshop_template_ownership;

select pg_temp.tw_mint(pg_temp.tw_id(63),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(61)));
update rm_private.template_workshop_write_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=pg_temp.tw_id(63);
set local role authenticated;
select pg_temp.tw_deny('select public.rm_web_mutate_v1(pg_temp.tw_id(63),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(61)))','42501');
reset role;
select pg_temp.tw_mint(pg_temp.tw_id(63),'create_form_template',pg_temp.tw_create(pg_temp.tw_id(61)));
insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.tw_id(11),'totp','verified');
set local role authenticated;
select pg_temp.tw_deny('select public.rm_web_mutate_v1(pg_temp.tw_id(63),''create_form_template'',pg_temp.tw_create(pg_temp.tw_id(61)))','42501');
reset role;
select public.rm_sso_session_delete_v1(repeat('8',64));
select pg_temp.tw_check(not exists(select 1 from rm_private.template_workshop_write_permits),'logout removes template permits');
select pg_temp.tw_check(not has_table_privilege('service_role','rm_private.workshop_template_ownership','select')
 and not has_function_privilege('authenticated','public.rm_sso_template_workshop_permit_v1(text,uuid,text,jsonb,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.activate_template_workshop_writes_v1(text,uuid)','execute'),'new metadata and activation private');
select 'PASS: template workshop writes, BMA legacy adoption, no default/bypass, create/copy/version/save/publish/delete/replay, immutable source, late rollback, MFA and logout' result;
rollback;

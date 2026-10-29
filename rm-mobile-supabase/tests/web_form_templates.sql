\set ON_ERROR_STOP on
begin;
create extension if not exists dblink with schema public;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.call_builder(rid uuid,op text,p jsonb,cap text default 'em.form_templates.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform public.rm_sso_action_permit_v1(repeat('9',64),rid,op,p,cap);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.reject_builder(op text,p jsonb,wanted text,cap text default 'em.form_templates.manage') returns void language plpgsql as $$
declare actual text; n integer:=coalesce(nullif(current_setting('rm.test.builder.reject_no',true),''),'0')::integer+1; begin
  perform set_config('rm.test.builder.reject_no',n::text,true);
  begin perform pg_temp.call_builder(gen_random_uuid(),op,p,cap);
  exception when others then get stacked diagnostics actual=returned_sqlstate;
    if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
  end; raise exception 'FAIL: builder request unexpectedly succeeded (case %, operation %, expected %)',n,op,wanted;
end $$;
create function pg_temp.draft_payload(id uuid,content jsonb default null) returns jsonb language sql as $$
  select jsonb_build_object('id',d.id,'expected_updated_at',d.updated_at)||case when $2 is null then '{}'::jsonb else jsonb_build_object('content',$2) end
  from public.rm_form_template_drafts d where d.id=$1;
$$;
insert into auth.users(id) values('19000000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('29000000-0000-4000-8000-000000000001','19000000-0000-4000-8000-000000000001','Builder admin fixture','administrador');
insert into auth.sessions(id,user_id) values('39000000-0000-4000-8000-000000000001','19000000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('89000000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','99000000-0000-4000-8000-000000000001',
 '29000000-0000-4000-8000-000000000001','19000000-0000-4000-8000-000000000001',true,'29000000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('9',64),'89000000-0000-4000-8000-000000000001','39000000-0000-4000-8000-000000000001',
 'opaque-builder-test-session',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','19000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"39000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select set_config('rm.test.builder.outbox',(select count(*)::text from public.rm_sync_outbox),true);
insert into public.rm_celulas(id,nome) values('49000000-0000-4000-8000-000000000001','Builder cell');
insert into public.rm_equipes(id,nome) values('49000000-0000-4000-8000-000000000002','Builder team');
insert into public.rm_tipos_equipamento(id,nome) values('59000000-0000-4000-8000-000000000001','Builder type');
insert into public.rm_forms(id,titulo,title,descricao,description,usa_aprovacao,imagem_capa_url,celulas_ids,equipes_ids) values
 ('79000000-0000-4000-8000-000000000001','Legacy fixture','English form','Descrição original','Original description',false,
 'https://example.invalid/legacy-cover.png','{49000000-0000-4000-8000-000000000001}','{49000000-0000-4000-8000-000000000002}');
insert into public.rm_questoes(id,form_id,indice,enunciado,title,tipo,obrigatorio) values
 ('a9000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000001',1.5,'Original choice','Choice title','escolha__nica',true),
 ('a9000000-0000-4000-8000-000000000002','79000000-0000-4000-8000-000000000001',2.25,'Original number','Number title','numero',false);
insert into public.rm_itens_questoes(id,form_id,questao_id,indice,descricao,description) values
 ('b9000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001',1.25,'Original option','Option description');
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id) values
 ('69000000-0000-4000-8000-000000000001','49000000-0000-4000-8000-000000000001','59000000-0000-4000-8000-000000000001');
insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id) values
 ('69000000-0000-4000-8000-000000000001','79000000-0000-4000-8000-000000000001');
insert into public.rm_projetos(id,numero,tipo_equipamento_id) values
 ('d9000000-0000-4000-8000-000000000001','BUILDER-FIXTURE-OLD','59000000-0000-4000-8000-000000000001'),
 ('d9000000-0000-4000-8000-000000000002','BUILDER-FIXTURE-NEW','59000000-0000-4000-8000-000000000001');
insert into public.rm_celulas_projeto(projeto_id,celula_id,forms_ids) values
 ('d9000000-0000-4000-8000-000000000001','49000000-0000-4000-8000-000000000001','{79000000-0000-4000-8000-000000000001}');
select set_config('rm.test.builder.source',public.rm_web_form_source_snapshot_v1('79000000-0000-4000-8000-000000000001')::text,true);

-- Structural draft validation allows recovery of incomplete legacy forms, but
-- publishing uses saved content and validates every supported type.
do $$ declare r jsonb; c jsonb; q jsonb; typ public.rm_tipo_questao_enum; idx integer:=0; expected text; rid uuid:=gen_random_uuid(); p jsonb;
  draft_id uuid:='c9000000-0000-4000-8000-000000000001'; begin
  p:=jsonb_build_object('id',draft_id,'source_form_id',null,'kind','new');
  r:=pg_temp.call_builder(rid,'create_form_template',p);
  perform pg_temp.check(r->'record'->>'state'='draft' and r->'record'->'source_snapshot'->>'usa_aprovacao'='true','new draft metadata');
  perform pg_temp.check((pg_temp.call_builder(rid,'create_form_template',p)->>'idempotent_replay')::bool,'create replay');
  begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'create_form_template',p); raise exception 'FAIL: permitless replay';
  exception when insufficient_privilege then reset role; end;
  perform pg_temp.reject_builder('create_form_template',p,'22023','em.forms.review');
  c:=r->'record'->'content';
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,c||'{"usa_aprovacao":false}'),'22023');
  c:=c||jsonb_build_object('titulo','All supported types','questions','[]'::jsonb);
  foreach typ in array enum_range(null::public.rm_tipo_questao_enum) loop
    idx:=idx+1;
    q:=jsonb_build_object('id',gen_random_uuid(),'indice',idx::text,'enunciado','Question '||idx,'title',null,'subtitulo',null,'tag',null,
      'tipo',typ,'subtipo',case typ when 'data' then 'intervalo_de_datas' when 'hora' then 'intervalo_de_hor_rios' end,
      'dimensoes',case when typ in ('texto_curto','texto_longo','numero') then 'volts' end,
      'colaborador_filtro_perfil',case when typ='colaborador' then 'padr_o' end,'obrigatorio',false,'items','[]'::jsonb);
    if typ in ('escolha__nica','caixas_de_sele__o','lista_suspensa','lista_multi_sele__o') then
      q:=q||jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'indice','1.25','descricao','Option','description',null)));
    end if;
    c:=jsonb_set(c,'{questions}',(c->'questions')||jsonb_build_array(q));
  end loop;
  r:=pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,c));
  perform rm_private.validate_form_template_content(c,true);
  perform pg_temp.reject_builder('save_form_template',jsonb_build_object('id',draft_id,'expected_updated_at','2000-01-01T00:00:00Z','content',c),'PT409');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,0,tipo}','"unsupported"')),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,0,indice}','1.5')),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,0,indice}','"1e2"')),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,c||jsonb_build_object('description',repeat('x',800001))),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions}',
    (select jsonb_agg(c->'questions'->0) from generate_series(1,1001)))),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,2,items}',
    (select jsonb_agg(c->'questions'->2->'items'->0) from generate_series(1,5001)))),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,1,id}',c->'questions'->0->'id')),'22023');
  -- An incomplete choice and blank text can be saved, never published.
  perform pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,2,items}','[]')));
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  perform pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{titulo}','"\t\n"')));
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  -- Numeric twins and double-precision twins would make mobile order ambiguous.
  perform pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,1,indice}','"1.0"')));
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  perform pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,1,indice}','"1.0000000000000000000000000001"')));
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,1,indice}','"1000000001"')),'22023');
  perform pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,jsonb_set(c,'{questions,0,subtipo}','"intervalo_de_datas"')));
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  perform pg_temp.call_builder(gen_random_uuid(),'save_form_template',pg_temp.draft_payload(draft_id,c));
  p:=pg_temp.draft_payload(draft_id); rid:=gen_random_uuid();
  r:=pg_temp.call_builder(rid,'publish_form_template',p);
  perform pg_temp.check(r->'publication'->>'version'='1' and r->'record'->>'state'='published','new family publication');
  perform pg_temp.check((select count(*)=15 from public.rm_questoes where form_id=(r->'publication'->>'form_id')::uuid),'all 15 types published');
  perform pg_temp.check((pg_temp.call_builder(rid,'publish_form_template',p)->>'idempotent_replay')::bool,'publish replay returns same version');
  perform pg_temp.reject_builder('publish_form_template',pg_temp.draft_payload(draft_id),'22023');
  perform pg_temp.reject_builder('save_form_template',pg_temp.draft_payload(draft_id,c),'22023');
end $$;

-- Copy is independent; version preserves family provenance without mutating the
-- source, existing allocations, engineering joins or operational sequence.
do $$ declare r jsonb; p jsonb; source jsonb; c jsonb; draft_id uuid:='c9000000-0000-4000-8000-000000000002';
  new_form uuid; new_question uuid; new_item uuid; other uuid; before_hash text; begin
  source:=current_setting('rm.test.builder.source')::jsonb;
  perform pg_temp.check(source->'content'->'questions'->0->>'indice'='1.5' and source->>'family_id' is null,'legacy exact snapshot and no family');
  r:=pg_temp.call_builder(gen_random_uuid(),'create_form_template',jsonb_build_object('id',draft_id,'source_form_id','79000000-0000-4000-8000-000000000001','kind','version'));
  c:=r->'record'->'content';
  perform pg_temp.check(r->'record'->>'source_version'='1' and r->'record'->>'family_id'='79000000-0000-4000-8000-000000000001','legacy family registration');
  perform pg_temp.check(c->'questions'->0->>'id'<>'a9000000-0000-4000-8000-000000000001','copy editor keys are new');
  perform pg_temp.check(c->'questions'->0->'items'->0->>'description'='Option description' and c->>'title'='English form','alternate metadata retained');
  perform pg_temp.check(r->'record'->'source_snapshot'=source->'source_snapshot','readonly source metadata retained');
  r:=pg_temp.call_builder(gen_random_uuid(),'publish_form_template',pg_temp.draft_payload(draft_id));
  new_form:=(r->'publication'->>'form_id')::uuid;
  new_question:=(r->'publication'->'id_mapping'->'questions'->>(c->'questions'->0->>'id'))::uuid;
  new_item:=(r->'publication'->'id_mapping'->'items'->>(c->'questions'->0->'items'->0->>'id'))::uuid;
  perform pg_temp.check(r->'publication'->>'version'='2' and new_form<>'79000000-0000-4000-8000-000000000001','published second version');
  perform pg_temp.check(new_question<>(c->'questions'->0->>'id')::uuid and new_item<>(c->'questions'->0->'items'->0->>'id')::uuid,'published IDs independent of editor keys');
  perform pg_temp.check((select indice=1.5 from public.rm_questoes where id=new_question) and (select indice=1.25 from public.rm_itens_questoes where id=new_item),'fractional indices exact');
  perform pg_temp.check((select not usa_aprovacao and ativo and title='English form' and imagem_capa_url='https://example.invalid/legacy-cover.png'
    and celulas_ids='{49000000-0000-4000-8000-000000000001}' and equipes_ids='{49000000-0000-4000-8000-000000000002}' from public.rm_forms where id=new_form),'readonly fields copied without review toggle');
  perform pg_temp.check((public.rm_web_form_source_snapshot_v1('79000000-0000-4000-8000-000000000001')-'family_id')=(source-'family_id'),'source content unchanged');
  perform pg_temp.check(not exists(select 1 from public.rm_numeracoes where form_id=new_form),'new version does not copy sequence');
  perform pg_temp.check((select forms_ids='{79000000-0000-4000-8000-000000000001}' from public.rm_celulas_projeto where projeto_id='d9000000-0000-4000-8000-000000000001'),'existing allocation unchanged');
  perform pg_temp.check((select form_id='79000000-0000-4000-8000-000000000001' from public.rm_celula_form_tipos_equipamento where celula_tipo_equipamento_id='69000000-0000-4000-8000-000000000001'),'engineering never auto-adopts');
  perform set_config('rm.test.builder.new_form',new_form::text,true);
  perform set_config('rm.test.builder.new_question',new_question::text,true);
  perform set_config('rm.test.builder.new_item',new_item::text,true);
  -- Append from an older source remains legal; there is no mutable latest pointer.
  other:=gen_random_uuid();
  perform pg_temp.call_builder(gen_random_uuid(),'create_form_template',jsonb_build_object('id',other,'source_form_id','79000000-0000-4000-8000-000000000001','kind','version'));
  r:=pg_temp.call_builder(gen_random_uuid(),'publish_form_template',pg_temp.draft_payload(other));
  perform pg_temp.check(r->'publication'->>'version'='3','old source appends version3 safely');
  other:=gen_random_uuid();
  r:=pg_temp.call_builder(gen_random_uuid(),'create_form_template',jsonb_build_object('id',other,'source_form_id',new_form,'kind','copy'));
  perform pg_temp.check(r->'record'->>'family_id'=other::text and r->'record'->>'source_version'='2','copy gets independent family');
  r:=pg_temp.call_builder(gen_random_uuid(),'publish_form_template',pg_temp.draft_payload(other));
  perform pg_temp.check(r->'publication'->>'version'='1','independent copy starts version1');
end $$;

-- Even a technical caller cannot silently edit a managed published definition.
do $$ declare f uuid:=current_setting('rm.test.builder.new_form')::uuid; q uuid:=current_setting('rm.test.builder.new_question')::uuid;
  i uuid:=current_setting('rm.test.builder.new_item')::uuid; begin
  begin update public.rm_forms set titulo='mutated' where id=f; raise exception 'FAIL: changed published form'; exception when object_not_in_prerequisite_state then null; end;
  begin update public.rm_questoes set obrigatorio=false where id=q; raise exception 'FAIL: changed published question'; exception when object_not_in_prerequisite_state then null; end;
  begin delete from public.rm_itens_questoes where id=i; raise exception 'FAIL: deleted published item'; exception when object_not_in_prerequisite_state then null; end;
  begin insert into public.rm_questoes(form_id,enunciado,tipo) values(f,'extra','texto_curto'); raise exception 'FAIL: inserted published question'; exception when object_not_in_prerequisite_state then null; end;
  begin insert into public.rm_itens_questoes(questao_id,descricao) values(q,'hidden extra'); raise exception 'FAIL: item null form_id bypass'; exception when object_not_in_prerequisite_state then null; end;
  begin update public.rm_itens_questoes set questao_id=q where id='b9000000-0000-4000-8000-000000000001'; raise exception 'FAIL: moved legacy item into published question'; exception when object_not_in_prerequisite_state then null; end;
  -- Explicit source ownership distinction: legacy rows remain under old contracts.
  update public.rm_forms set updated_at=updated_at where id='79000000-0000-4000-8000-000000000001';
end $$;

-- Explicit engineering adoption affects only future allocations. An old queued
-- mobile submission still validates old question/item IDs, and can be revised.
do $$ declare new_form uuid:=current_setting('rm.test.builder.new_form')::uuid; r jsonb; params jsonb; submission uuid:=gen_random_uuid(); registration uuid; begin
  perform pg_temp.call_builder(gen_random_uuid(),'save_engineering',jsonb_build_object('id','69000000-0000-4000-8000-000000000001',
    'celula_id','49000000-0000-4000-8000-000000000001','tipo_equipamento_id','59000000-0000-4000-8000-000000000001',
    'expected_updated_at',(select updated_at from public.rm_celula_tipos_equipamento where id='69000000-0000-4000-8000-000000000001'),
    'changes',jsonb_build_object('form_ids',jsonb_build_array(new_form))),'em.engineering.manage');
  perform pg_temp.call_builder(gen_random_uuid(),'plan_cell',jsonb_build_object('projeto_id','d9000000-0000-4000-8000-000000000002',
    'celula_id','49000000-0000-4000-8000-000000000001','expected_updated_at',null,'changes','{}'::jsonb),'em.planning.manage');
  perform pg_temp.check((select forms_ids=array[new_form] from public.rm_celulas_projeto where projeto_id='d9000000-0000-4000-8000-000000000002'),'future allocation adopts new version');
  perform pg_temp.check((select forms_ids='{79000000-0000-4000-8000-000000000001}' from public.rm_celulas_projeto where projeto_id='d9000000-0000-4000-8000-000000000001'),'old allocation remains old after adoption');
  insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values
    (extensions.digest('builder-test-operator-token','sha256'),auth.uid(),'29000000-0000-4000-8000-000000000001','29000000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
  params:=jsonb_build_object('p_projeto_id','d9000000-0000-4000-8000-000000000001','p_celula_id','49000000-0000-4000-8000-000000000001',
    'p_form_id','79000000-0000-4000-8000-000000000001','p_respostas',jsonb_build_array(jsonb_build_object('questao_id','a9000000-0000-4000-8000-000000000001',
      'resposta','Original option','itens_questoes_ids',jsonb_build_array('b9000000-0000-4000-8000-000000000001'))));
  set local role authenticated;
  r:=public.rm_mobile_mutate_v1(submission,'rm_submit_form_inspection_v1',params,'builder-test-operator-token');
  perform pg_temp.check((public.rm_mobile_mutate_v1(submission,'rm_submit_form_inspection_v1',params,'builder-test-operator-token')->>'idempotent_replay')::boolean,'old mobile queue replay');
  reset role; registration:=(r->>'registro_formulario_id')::uuid;
  perform pg_temp.check((select indice=1.5 and questao_id='a9000000-0000-4000-8000-000000000001' from public.rm_respostas where registro_formulario_id=registration),'old submission retains source question');
  update public.rm_registros_formulario set status='direcionado' where id=registration;
  update public.rm_respostas set revisar=true where registro_formulario_id=registration;
  set local role authenticated;
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_revision_v1',jsonb_build_object('p_registro_formulario_id',registration,
    'p_respostas_corrigidas',jsonb_build_array(jsonb_build_object('questao_id','a9000000-0000-4000-8000-000000000001','resposta','Original option',
      'itens_questoes_ids',jsonb_build_array('b9000000-0000-4000-8000-000000000001')))),'builder-test-operator-token');
  reset role;
  perform pg_temp.check((select not revisar from public.rm_respostas where registro_formulario_id=registration),'old revision still works');
end $$;

-- Authorization, MFA and read boundaries also apply to the new operations.
do $$ declare p jsonb:=jsonb_build_object('id',gen_random_uuid(),'kind','new','source_form_id',null); rid uuid:=gen_random_uuid(); begin
  update public.rm_users set perfil='auditor' where auth_user_id=auth.uid(); perform pg_temp.reject_builder('create_form_template',p,'42501');
  update public.rm_users set perfil='administrador' where auth_user_id=auth.uid();
  perform pg_temp.call_builder(rid,'create_form_template',p);
  insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
  begin perform pg_temp.call_builder(rid,'create_form_template',p); raise exception 'FAIL: AAL1 replay'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"session_id":"39000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
  perform pg_temp.check((pg_temp.call_builder(rid,'create_form_template',p)->>'idempotent_replay')::bool,'AAL2 replay');
  update rm_private.sso_identity_bindings set enabled=false where auth_user_id=auth.uid();
  perform pg_temp.reject_builder('create_form_template',jsonb_set(p,'{id}',to_jsonb(gen_random_uuid())),'42501');
  update rm_private.sso_identity_bindings set enabled=true where auth_user_id=auth.uid();
end $$;
set local role authenticated;
select pg_temp.check(public.rm_web_form_template_snapshot_v1('c9000000-0000-4000-8000-000000000002')->'draft'->>'state'='published','authenticated draft snapshot');
select pg_temp.check(public.rm_web_form_source_snapshot_v1(current_setting('rm.test.builder.new_form')::uuid)->>'version'='2','authenticated published source');
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
select pg_temp.check(public.rm_web_form_template_snapshot_v1('c9000000-0000-4000-8000-000000000002') is null,'draft RLS requires active RM');
select pg_temp.check(public.rm_web_form_source_snapshot_v1('79000000-0000-4000-8000-000000000001') is null,'source RLS requires active RM');
reset role;
select pg_temp.check((select bool_and(not prosecdef and provolatile='s') from pg_proc where oid in
 ('public.rm_web_form_source_snapshot_v1(uuid)'::regprocedure,'public.rm_web_form_template_snapshot_v1(uuid)'::regprocedure)),'read RPCs stable invoker');
select pg_temp.check(not has_function_privilege('anon','public.rm_web_form_template_snapshot_v1(uuid)','execute')
 and not has_function_privilege('service_role','public.rm_web_form_source_snapshot_v1(uuid)','execute'),'snapshot ACL');
select pg_temp.check(not has_function_privilege('authenticated','rm_private.validate_form_template_content(jsonb,boolean)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute'),'private helpers not bypassable');
select pg_temp.check(not has_table_privilege('authenticated','public.rm_form_template_drafts','insert')
 and not has_table_privilege('service_role','public.rm_form_template_versions','update'),'direct builder writes denied');
-- Only the deliberate mobile submission/revision in this fixture may enqueue work.
select pg_temp.check((select count(*) from public.rm_sync_outbox)=current_setting('rm.test.builder.outbox')::int+2,'builder and engineering never enqueue outbound work');
rollback;

-- Committed fixtures below are ONLY for the disposable local PostgreSQL database:
-- two independent connections must see the same drafts to exercise real races.
-- The harness destroys this complete database after the suite (also on failure).
begin;
create extension if not exists dblink with schema public;
create schema rm_test_builder;
create function rm_test_builder.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('19000000-0000-4000-8000-000000000101'),('19000000-0000-4000-8000-000000000102');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('29000000-0000-4000-8000-000000000101','19000000-0000-4000-8000-000000000101','Concurrent builder A','administrador'),
 ('29000000-0000-4000-8000-000000000102','19000000-0000-4000-8000-000000000102','Concurrent builder B','administrador');
insert into auth.sessions(id,user_id) values
 ('39000000-0000-4000-8000-000000000101','19000000-0000-4000-8000-000000000101'),
 ('39000000-0000-4000-8000-000000000102','19000000-0000-4000-8000-000000000102');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('89000000-0000-4000-8000-000000000101','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','99000000-0000-4000-8000-000000000101',
 '29000000-0000-4000-8000-000000000101','19000000-0000-4000-8000-000000000101',true,'29000000-0000-4000-8000-000000000101',clock_timestamp()),
 ('89000000-0000-4000-8000-000000000102','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','99000000-0000-4000-8000-000000000102',
 '29000000-0000-4000-8000-000000000102','19000000-0000-4000-8000-000000000102',true,'29000000-0000-4000-8000-000000000101',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('a',64),'89000000-0000-4000-8000-000000000101','39000000-0000-4000-8000-000000000101',
 'test-concurrent-a',clock_timestamp()+interval '45 minutes');
select public.rm_sso_session_put_v1(repeat('b',64),'89000000-0000-4000-8000-000000000102','39000000-0000-4000-8000-000000000102',
 'test-concurrent-b',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_forms(id,titulo) values('79000000-0000-4000-8000-000000000101','Concurrent source fixture');
insert into public.rm_questoes(form_id,indice,enunciado,tipo) values('79000000-0000-4000-8000-000000000101',1.5,'Concurrent question','texto_curto');
create function rm_test_builder.run(p_admin integer,p_operation text,p_payload jsonb,p_hold real default 0) returns jsonb
language plpgsql as $$
declare rid uuid:=gen_random_uuid(); result jsonb; state text;
begin
  perform set_config('request.jwt.claim.sub','19000000-0000-4000-8000-'||case p_admin when 1 then '000000000101' else '000000000102' end,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id','39000000-0000-4000-8000-'||case p_admin when 1 then '000000000101' else '000000000102' end,'aal','aal1')::text,true);
  perform public.rm_sso_action_permit_v1(repeat(case p_admin when 1 then 'a' else 'b' end,64),rid,p_operation,p_payload,'em.form_templates.manage');
  set local role authenticated; result:=public.rm_web_mutate_v1(rid,p_operation,p_payload); reset role;
  perform pg_sleep(p_hold);
  return jsonb_build_object('sqlstate','00000','result',result);
exception when others then
  reset role; get stacked diagnostics state=returned_sqlstate;
  return jsonb_build_object('sqlstate',state);
end $$;
do $$ declare id uuid; r jsonb; begin
  foreach id in array array['c9000000-0000-4000-8000-000000000101'::uuid,'c9000000-0000-4000-8000-000000000102'::uuid] loop
    r:=rm_test_builder.run(1,'create_form_template',jsonb_build_object('id',id,'kind','version','source_form_id','79000000-0000-4000-8000-000000000101'));
    perform rm_test_builder.check(r->>'sqlstate'='00000','concurrent version draft setup');
  end loop;
  r:=rm_test_builder.run(1,'create_form_template',jsonb_build_object('id','c9000000-0000-4000-8000-000000000103','kind','new','source_form_id',null));
  perform rm_test_builder.check(r->>'sqlstate'='00000','shared draft setup');
end $$;
commit;

do $$ declare a jsonb; b jsonb; pa jsonb; pb jsonb; content jsonb; pid_a integer; waited integer;
begin
  perform dblink_connect('builder_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
  perform dblink_connect('builder_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
  select pid into pid_a from dblink('builder_a','select pg_backend_pid()') as t(pid integer);
  select jsonb_build_object('id',id,'expected_updated_at',updated_at) into pa from public.rm_form_template_drafts where id='c9000000-0000-4000-8000-000000000101';
  select jsonb_build_object('id',id,'expected_updated_at',updated_at) into pb from public.rm_form_template_drafts where id='c9000000-0000-4000-8000-000000000102';
  perform dblink_send_query('builder_a',format('select rm_test_builder.run(1,%L,%L::jsonb,1.0)','publish_form_template',pa::text));
  waited:=0;
  loop
    perform pg_stat_clear_snapshot();
    exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
    waited:=waited+1; if waited>200 then raise exception 'FAIL: publisher A did not hold family lock'; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('builder_b',format('select rm_test_builder.run(2,%L,%L::jsonb,0)','publish_form_template',pb::text));
  select r into a from dblink_get_result('builder_a') as t(r jsonb);
  perform r from dblink_get_result('builder_a') as t(r jsonb);
  select r into b from dblink_get_result('builder_b') as t(r jsonb);
  perform r from dblink_get_result('builder_b') as t(r jsonb);
  perform rm_test_builder.check(a->>'sqlstate'='00000' and b->>'sqlstate'='00000','two real admins publish concurrently');
  perform rm_test_builder.check(a->'result'->'publication'->>'version'='2' and b->'result'->'publication'->>'version'='3','family lock sees newly committed append');
  perform rm_test_builder.check((select count(*)=3 from public.rm_form_template_versions where family_id='79000000-0000-4000-8000-000000000101'),'no duplicate or lost family versions');

  select d.content,jsonb_build_object('id',id,'expected_updated_at',updated_at) into content,pa from public.rm_form_template_drafts d where id='c9000000-0000-4000-8000-000000000103';
  pb:=pa||jsonb_build_object('content',content||'{"titulo":"Second concurrent editor"}');
  pa:=pa||jsonb_build_object('content',content||'{"titulo":"First concurrent editor"}');
  perform dblink_send_query('builder_a',format('select rm_test_builder.run(1,%L,%L::jsonb,1.0)','save_form_template',pa::text));
  waited:=0;
  loop
    perform pg_stat_clear_snapshot();
    exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
    waited:=waited+1; if waited>200 then raise exception 'FAIL: editor A did not hold draft lock'; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('builder_b',format('select rm_test_builder.run(2,%L,%L::jsonb,0)','save_form_template',pb::text));
  select r into a from dblink_get_result('builder_a') as t(r jsonb);
  perform r from dblink_get_result('builder_a') as t(r jsonb);
  select r into b from dblink_get_result('builder_b') as t(r jsonb);
  perform r from dblink_get_result('builder_b') as t(r jsonb);
  perform rm_test_builder.check(a->>'sqlstate'='00000' and b->>'sqlstate'='PT409','concurrent stale editor gets PT409');
  perform rm_test_builder.check((select d.content->>'titulo'='First concurrent editor' from public.rm_form_template_drafts d where d.id='c9000000-0000-4000-8000-000000000103'),'second editor did not overwrite first');
  perform dblink_disconnect('builder_a'); perform dblink_disconnect('builder_b');
exception when others then
  if 'builder_a'=any(dblink_get_connections()) then perform dblink_disconnect('builder_a'); end if;
  if 'builder_b'=any(dblink_get_connections()) then perform dblink_disconnect('builder_b'); end if; raise;
end $$;
select 'PASS: immutable versions, draft recovery, exact indices, real concurrent SSO admins, explicit adoption, old offline submissions/revisions, RLS/SSO/MFA' as result;

\set ON_ERROR_STOP on
begin;
create function pg_temp.fd_id(n int) returns uuid language sql immutable as $$ select ('46000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;$$;
create function pg_temp.fd_check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end $$;
create function pg_temp.fd_call(rid uuid,op text,p jsonb,cap text default 'em.form_templates.manage') returns jsonb language plpgsql as $$
declare r jsonb;begin
 perform public.rm_sso_action_permit_v1(repeat('6',64),rid,op,p,cap);
 set local role authenticated;r:=public.rm_web_mutate_v1(rid,op,p);reset role;return r;
exception when others then reset role;raise;end $$;
create function pg_temp.fd_payload(n int,kind text default 'form') returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fd_id(n),'kind',kind,'confirmed',true,'expected_updated_at',
 case when kind='form' then(select updated_at from public.rm_forms where id=pg_temp.fd_id(n))
 else(select updated_at from public.rm_form_template_drafts where id=pg_temp.fd_id(n)) end);$$;
create function pg_temp.fd_reject(p jsonb,wanted text,cap text default 'em.form_templates.manage') returns void language plpgsql as $$
declare actual text;begin
 begin perform pg_temp.fd_call(gen_random_uuid(),'delete_form_template',p,cap);
 exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return;end if;raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;end;
 raise exception 'FAIL: deletion accepted; expected %',wanted;end $$;
insert into auth.users(id) values(pg_temp.fd_id(1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.fd_id(2),pg_temp.fd_id(1),'Template deletion test','administrador');
insert into auth.sessions(id,user_id) values(pg_temp.fd_id(3),pg_temp.fd_id(1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(pg_temp.fd_id(4),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.fd_id(5),pg_temp.fd_id(2),pg_temp.fd_id(1),true,pg_temp.fd_id(2),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('6',64),pg_temp.fd_id(4),pg_temp.fd_id(3),'opaque-template-delete-fixture',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub',pg_temp.fd_id(1)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.fd_id(3),'aal','aal1')::text,true);
insert into public.rm_forms(id,titulo) select pg_temp.fd_id(n),'Template deletion fixture '||n from generate_series(10,30) n;
insert into public.rm_projetos(id,numero) values(pg_temp.fd_id(50),'DELETE-FORM-46');
insert into public.rm_celulas(id,nome) values(pg_temp.fd_id(51),'Delete form cell');
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.fd_id(52),'Delete form equipment');
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id) values(pg_temp.fd_id(53),pg_temp.fd_id(51),pg_temp.fd_id(52));

do $$ declare p jsonb:=pg_temp.fd_payload(10);rid uuid:=gen_random_uuid();r jsonb;begin
 perform pg_temp.fd_reject(p-'confirmed','22023');perform pg_temp.fd_reject(p||'{"confirmed":false}','22023');
 perform pg_temp.fd_reject(p||'{"unexpected":true}','22023');
 perform pg_temp.fd_reject(p||'{"expected_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.fd_reject(p,'22023','em.projects.manage');
 update public.rm_users set perfil='auditor' where id=pg_temp.fd_id(2);perform pg_temp.fd_reject(p,'42501');
 update public.rm_users set perfil='padr_o' where id=pg_temp.fd_id(2);perform pg_temp.fd_reject(p,'42501');
 update public.rm_users set perfil='administrador' where id=pg_temp.fd_id(2);
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.fd_id(1),'totp','verified');perform pg_temp.fd_reject(p,'42501');
 delete from auth.mfa_factors where user_id=pg_temp.fd_id(1);
 r:=pg_temp.fd_call(rid,'delete_form_template',p);
 perform pg_temp.fd_check(not exists(select 1 from public.rm_forms where id=pg_temp.fd_id(10)),'unused legacy form removed');
 perform pg_temp.fd_check((pg_temp.fd_call(rid,'delete_form_template',p)->>'idempotent_replay')::boolean,'exact replay after delete');
 begin set local role authenticated;perform public.rm_web_mutate_v1(rid,'delete_form_template',p);reset role;raise exception 'FAIL: no permit accepted';
 exception when insufficient_privilege then reset role;end;
 begin perform pg_temp.fd_call(rid,'delete_form_template',pg_temp.fd_payload(11));raise exception 'FAIL: changed retry';exception when unique_violation then null;end;
 begin insert into public.rm_forms(id,titulo) values(pg_temp.fd_id(10),'Recreated');raise exception 'FAIL: deleted id reused';exception when sqlstate 'PT410' then null;end;
end $$;

-- FK links which previously cascade or nullify must all block deletion.
insert into public.rm_celula_form_tipos_equipamento(celula_tipo_equipamento_id,form_id,ativo) values(pg_temp.fd_id(53),pg_temp.fd_id(11),false);
insert into public.rm_celulas_projeto(projeto_id,celula_id,forms_ids) values(pg_temp.fd_id(50),pg_temp.fd_id(51),array[pg_temp.fd_id(12)]);
insert into public.rm_templates_word(nome,form_id) values('Report template dependency',pg_temp.fd_id(13));
insert into public.rm_questoes(id,form_id,enunciado,tipo) select pg_temp.fd_id(n+100),pg_temp.fd_id(n),'Historical question','texto_curto' from generate_series(14,16) n;
insert into public.rm_respostas_temp(projeto_id,form_id,questao_id,operador_user_id) values(pg_temp.fd_id(50),pg_temp.fd_id(14),pg_temp.fd_id(114),pg_temp.fd_id(2));
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,created_by_user_id,codigo)
 values(pg_temp.fd_id(60),pg_temp.fd_id(50),pg_temp.fd_id(51),pg_temp.fd_id(15),pg_temp.fd_id(2),1);
insert into public.rm_respostas(registro_formulario_id,questao_id) values(pg_temp.fd_id(60),pg_temp.fd_id(115));
insert into public.rm_numeracoes(form_id,ult_numero) values(pg_temp.fd_id(16),1);
update public.rm_forms set celulas_ids=array[pg_temp.fd_id(51)] where id=pg_temp.fd_id(17);
insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
 values(gen_random_uuid(),pg_temp.fd_id(1),pg_temp.fd_id(2),'save_engineering',jsonb_build_object('form_ids',array[pg_temp.fd_id(18)]),'{}','{}');
do $$ declare n int;begin
 for n in 11..18 loop perform pg_temp.fd_reject(pg_temp.fd_payload(n),'23503');end loop;
 perform pg_temp.fd_check((select count(*) from public.rm_respostas where registro_formulario_id=pg_temp.fd_id(60))=1,'historical answers preserved');
 begin update public.rm_celulas_projeto set forms_ids=array[pg_temp.fd_id(10)] where projeto_id=pg_temp.fd_id(50);raise exception 'FAIL: deleted array reference';exception when foreign_key_violation then null;end;
end $$;

-- Unresolved legacy array identities remain visible for reconciliation. These
-- arrays historically have no FK, so importing one is not a template deletion.
update public.rm_celulas_projeto set forms_ids=array[pg_temp.fd_id(12),pg_temp.fd_id(999),null] where projeto_id=pg_temp.fd_id(50);
select pg_temp.fd_check((select forms_ids=array[pg_temp.fd_id(12),pg_temp.fd_id(999),null] from public.rm_celulas_projeto where projeto_id=pg_temp.fd_id(50)),'unknown legacy form identity preserved');
update public.rm_respostas set itens_questoes_ids=array[pg_temp.fd_id(998),null] where registro_formulario_id=pg_temp.fd_id(60);
update public.rm_respostas_temp set itens_questoes_ids=array[pg_temp.fd_id(998),null] where projeto_id=pg_temp.fd_id(50);
select pg_temp.fd_check((select itens_questoes_ids=array[pg_temp.fd_id(998),null] from public.rm_respostas where registro_formulario_id=pg_temp.fd_id(60)),'unknown legacy answer item identity preserved');
select pg_temp.fd_check((select itens_questoes_ids=array[pg_temp.fd_id(998),null] from public.rm_respostas_temp where projeto_id=pg_temp.fd_id(50)),'unknown legacy draft item identity preserved');
update public.rm_respostas set itens_questoes_ids=itens_questoes_ids where registro_formulario_id=pg_temp.fd_id(60);
update public.rm_respostas_temp set itens_questoes_ids=itens_questoes_ids where projeto_id=pg_temp.fd_id(50);
update public.rm_celulas_projeto set forms_ids=forms_ids where projeto_id=pg_temp.fd_id(50);

-- Incomplete drafts are deletable; their source model is not removed.
do $$ declare did uuid:=pg_temp.fd_id(70);p jsonb;r jsonb;fid uuid;draft_timestamp timestamptz;begin
 r:=pg_temp.fd_call(gen_random_uuid(),'create_form_template',jsonb_build_object('id',did,'kind','copy','source_form_id',pg_temp.fd_id(19)));
 perform pg_temp.fd_reject(pg_temp.fd_payload(19),'23503');
 p:=pg_temp.fd_payload(70,'draft');perform pg_temp.fd_call(gen_random_uuid(),'delete_form_template',p);
 perform pg_temp.fd_check(not exists(select 1 from public.rm_form_template_drafts where id=did) and exists(select 1 from public.rm_forms where id=pg_temp.fd_id(19)),'draft only removed');
 -- Publish a complete unused definition, then remove its exclusive graph.
 did:=pg_temp.fd_id(71);
 r:=pg_temp.fd_call(gen_random_uuid(),'create_form_template',jsonb_build_object('id',did,'kind','new','source_form_id',null));
 r:=pg_temp.fd_call(gen_random_uuid(),'save_form_template',jsonb_build_object('id',did,'expected_updated_at',r->'record'->'updated_at','content',jsonb_build_object(
 'titulo','Unused publication','descricao',null,'title',null,'description',null,'tipo',null,'questions',jsonb_build_array(jsonb_build_object(
 'id',pg_temp.fd_id(72),'indice','1','enunciado','Unused question','title',null,'subtitulo',null,'tag',null,'tipo','texto_curto','subtipo',null,'dimensoes',null,'obrigatorio',false,'colaborador_filtro_perfil',null,'items','[]'::jsonb)))));
 r:=pg_temp.fd_call(gen_random_uuid(),'publish_form_template',jsonb_build_object('id',did,'expected_updated_at',r->'record'->'updated_at'));
 fid:=(r->'record'->>'published_form_id')::uuid;
 perform pg_temp.fd_check(public.rm_web_form_source_snapshot_v1(fid)->'form'->>'updated_at' is not null,'version visible in same source snapshot');
 perform pg_temp.fd_reject(pg_temp.fd_payload(71,'draft'),'23503');
 begin update public.rm_forms set titulo='Changed immutable' where id=fid;raise exception 'FAIL: immutability lost';exception when sqlstate '55000' then null;end;
 perform pg_temp.fd_call(gen_random_uuid(),'delete_form_template',jsonb_build_object('id',fid,'kind','form','confirmed',true,'expected_updated_at',(select updated_at from public.rm_forms where id=fid)));
 perform pg_temp.fd_check(not exists(select 1 from public.rm_forms where id=fid) and not exists(select 1 from public.rm_questoes where form_id=fid)
  and not exists(select 1 from public.rm_form_template_drafts where id=did),'unused published graph removed atomically');
end $$;

update public.rm_forms set bubble_id='legacy-removed-form-46' where id=pg_temp.fd_id(20);
insert into public.rm_questoes(id,form_id,enunciado,tipo,bubble_id) values(pg_temp.fd_id(120),pg_temp.fd_id(20),'Deleted legacy question','escolha__nica','legacy-removed-question-46');
insert into public.rm_itens_questoes(id,form_id,questao_id,descricao,bubble_id) values(pg_temp.fd_id(220),null,pg_temp.fd_id(120),'Deleted legacy item','legacy-removed-item-46');
select pg_temp.fd_call(gen_random_uuid(),'delete_form_template',pg_temp.fd_payload(20));
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select pg_temp.fd_check(public.rm_deleted_bubble_ids_v1('rm_forms',array['legacy-removed-form-46','other'])=array['legacy-removed-form-46'],'ETL tombstone lookup reused');
select pg_temp.fd_check(public.rm_deleted_bubble_ids_v1('rm_questoes',array['legacy-removed-question-46','other'])=array['legacy-removed-question-46'],'ETL deleted question identity lookup');
select pg_temp.fd_check(public.rm_deleted_bubble_ids_v1('rm_itens_questoes',array['legacy-removed-item-46','other'])=array['legacy-removed-item-46'],'ETL item without form_id has a tombstone');
select pg_temp.fd_check(public.rm_deleted_bubble_ids_v1('rm_clientes',array['legacy-removed-item-46','legacy-removed-question-46','legacy-removed-form-46'])='{}'::text[],'unrelated table cannot inherit template tombstones');
reset role;
do $$ begin
 begin insert into public.rm_forms(titulo,bubble_id) values('Resurrection','legacy-removed-form-46');raise exception 'FAIL: deleted Bubble identity reused';exception when sqlstate 'PT410' then null;end;
 begin update public.rm_respostas set itens_questoes_ids=array[pg_temp.fd_id(220)] where registro_formulario_id=pg_temp.fd_id(60);raise exception 'FAIL: deleted answer item reference';exception when foreign_key_violation then null;end;
 begin update public.rm_respostas_temp set itens_questoes_ids=array[pg_temp.fd_id(220)] where projeto_id=pg_temp.fd_id(50);raise exception 'FAIL: deleted draft item reference';exception when foreign_key_violation then null;end;
end $$;
-- The immutable before-record contains canonical UUIDs even when a caller's
-- original idempotency payload spells a UUID with uppercase hexadecimal.
do $$ declare fid uuid:='ab460000-0000-4000-8000-000000000001';p jsonb;begin
 insert into public.rm_forms(id,titulo) values(fid,'Uppercase request identity');
 p:=jsonb_build_object('id',upper(fid::text),'kind','form','confirmed',true,'expected_updated_at',(select updated_at from public.rm_forms where id=fid));
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.fd_id(3),'aal','aal1')::text,true);
 perform pg_temp.fd_call(gen_random_uuid(),'delete_form_template',p);
 begin insert into public.rm_forms(id,titulo) values(fid,'Uppercase identity resurrection');raise exception 'FAIL: uppercase UUID bypassed tombstone';exception when sqlstate 'PT410' then null;end;
 begin update public.rm_celulas_projeto set forms_ids=array[fid] where projeto_id=pg_temp.fd_id(50);raise exception 'FAIL: uppercase UUID acquired array reference';exception when foreign_key_violation then null;end;
end $$;
select pg_temp.fd_check(not has_function_privilege('authenticated','rm_private.web_mutate_before_template_delete_v1(uuid,text,jsonb)','execute'),'private dispatch not exposed');
rollback;

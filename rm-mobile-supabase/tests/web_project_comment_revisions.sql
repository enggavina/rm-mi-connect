-- TEST DATABASE ONLY: manual comment correction, original attribution and append-only history.
\set ON_ERROR_STOP on
begin;
create function pg_temp.cm_key(h text,n int) returns uuid language sql immutable as $$ select(h||'f340000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.cm_check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.cm_actor(n int,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.cm_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.cm_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.cm.actor',n::text,true); end $$;
create function pg_temp.cm_call(p jsonb,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns jsonb language plpgsql as $$ declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.cm.actor'),64,'f4'),rid,'edit_project_comment',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'edit_project_comment',p); reset role; return r;
 exception when others then reset role; raise; end $$;
create function pg_temp.cm_reject(p jsonb,wanted text,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns void language plpgsql as $$ declare actual text; begin
 begin perform pg_temp.cm_call(p,rid,cap); exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: wanted %, got %: %',wanted,actual,sqlerrm; end;
 raise exception 'FAIL: comment correction unexpectedly succeeded'; end $$;
create function pg_temp.cm_payload(cid uuid,body text default 'Corrected manual text') returns jsonb language plpgsql as $$ declare s jsonb; begin
 s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),cid,1);
 return jsonb_build_object('projeto_id',s->'project'->>'id','comentario_id',s->'comment'->>'id','expected_project_updated_at',s->'project'->>'updated_at',
  'expected_comment_updated_at',s->'comment'->>'updated_at','expected_context_version',s->>'context_version','evento',body,'motivo','Correction verified','confirm_change',true); end $$;
create function pg_temp.cm_add(n int) returns jsonb language plpgsql as $$ declare p jsonb; r jsonb; begin
 p:=jsonb_build_object('projeto_id',upper(pg_temp.cm_key('5',1)::text),'celula_projeto_id',upper(pg_temp.cm_key('b',1)::text),
  'expected_project_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.cm_key('5',1)),
  'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.cm_key('b',1)),'evento','Original manual '||n);
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.cm.actor'),64,'f4'),pg_temp.cm_key('c',n),'add_project_comment',p,'em.projects.manage');
 set local role authenticated; r:=public.rm_web_mutate_v1(pg_temp.cm_key('c',n),'add_project_comment',p); reset role; return r;
 exception when others then reset role; raise; end $$;
do $$ declare n int; begin for n in 1..6 loop
 insert into auth.users(id) values(pg_temp.cm_key('1',n));
 insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.cm_key('2',n),pg_temp.cm_key('1',n),'Comment actor '||n,
  case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=4 then 'auditor' when n=6 then 'cliente' else 'padr_o' end,
  case when n=5 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
 insert into auth.sessions(id,user_id) values(pg_temp.cm_key('3',n),pg_temp.cm_key('1',n));
 insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(pg_temp.cm_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.cm_key('9',n),pg_temp.cm_key('2',n),pg_temp.cm_key('1',n),true,pg_temp.cm_key('2',1),clock_timestamp());
 if n in(1,2,3,4) then perform public.rm_sso_session_put_v1(lpad(n::text,64,'f4'),pg_temp.cm_key('8',n),pg_temp.cm_key('3',n),'opaque-comment-fixture-'||n,clock_timestamp()+interval '45 minutes'); end if;
 end loop; end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_clientes(id,nome) values(pg_temp.cm_key('4',1),'Comment test client');
insert into public.rm_projetos(id,numero,cliente_id) values(pg_temp.cm_key('5',1),'COMMENTS-32',pg_temp.cm_key('4',1)),(pg_temp.cm_key('5',2),'OTHER-32',pg_temp.cm_key('4',1));
insert into public.rm_celulas(id,nome) values(pg_temp.cm_key('a',1),'Comment cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id) values(pg_temp.cm_key('b',1),pg_temp.cm_key('5',1),pg_temp.cm_key('a',1));
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values(pg_temp.cm_key('a',1),pg_temp.cm_key('2',2),pg_temp.cm_key('2',2));
select pg_temp.cm_actor(2);
select pg_temp.cm_add(1);select pg_temp.cm_add(2);select pg_temp.cm_add(3);select pg_temp.cm_add(6);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_projeto_id,status_cel_proj,status)
 values(pg_temp.cm_key('d',1),pg_temp.cm_key('5',1),pg_temp.cm_key('a',1),pg_temp.cm_key('b',1),'pendente','aprovado');
insert into public.rm_logs_aprovacao(id,projeto_id,celula_id,aprovador_id,status_aprovacao,data_aprovacao)
 values(pg_temp.cm_key('e',1),pg_temp.cm_key('5',1),pg_temp.cm_key('a',1),pg_temp.cm_key('2',2),'aprovado',clock_timestamp());
insert into public.rm_web_stage_decisions(aprovacao_etapa_id,projeto_id,celula_id,celula_projeto_id,actor_id,acao,status_anterior,status_novo,log_id,comentario_id,client_submission_id)
 values(pg_temp.cm_key('d',1),pg_temp.cm_key('5',1),pg_temp.cm_key('a',1),pg_temp.cm_key('b',1),pg_temp.cm_key('2',2),'liberar','nulo','aprovado',pg_temp.cm_key('e',1),pg_temp.cm_key('c',6),pg_temp.cm_key('f',99));
insert into public.rm_comentarios(id,projeto_id,celula_id,cadastrado_por_id,evento,bubble_id,sync_source)
 values(pg_temp.cm_key('c',4),pg_temp.cm_key('5',1),pg_temp.cm_key('a',1),pg_temp.cm_key('2',2),'Original legacy unknown','legacy-comment-32','bubble'),
 (pg_temp.cm_key('c',5),pg_temp.cm_key('5',1),null,pg_temp.cm_key('2',2),'QR do recebimento: preserved',null,'supabase');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('comment-test-mobile','sha256'),pg_temp.cm_key('1',2),pg_temp.cm_key('2',2),pg_temp.cm_key('2',2),clock_timestamp()+interval '1 day');
create temporary table cm_mobile(r jsonb,rid uuid,p jsonb);
grant select,update on cm_mobile to authenticated;
insert into cm_mobile(rid,p) values(pg_temp.cm_key('f',90),jsonb_build_object('p_celula_projeto_id',upper(pg_temp.cm_key('b',1)::text),'p_comentario','Mobile manual original'));
set local role authenticated;
update cm_mobile set r=public.rm_mobile_mutate_v1(rid,'rm_add_cell_comment_v1',p,'comment-test-mobile');
reset role;
-- Safe scope and exact evidence: no prefix or inferred source grants editing.
do $$ declare s jsonb; n int; begin
 for n in 1..3 loop s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),pg_temp.cm_key('c',n),1);
  perform pg_temp.cm_check((s->>'can_edit')::boolean and (s->'history'->>'total')::int=0 and s->'history'->'items'='[]','own manual web eligible with empty history'); end loop;
 for n in 4..6 loop s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),pg_temp.cm_key('c',n),1);
  perform pg_temp.cm_check(not(s->>'can_edit')::boolean and s->>'reason' is not null,'unknown/QR preserved readonly'); end loop;
 s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),(select(m.r->>'comentario_id')::uuid from cm_mobile m),1);
 perform pg_temp.cm_check((s->>'can_edit')::boolean,'mobile manual proven by exact completed creation receipt');
 perform pg_temp.cm_check(public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',2),pg_temp.cm_key('c',1),1) is null,'cross-project comment never disclosed');
 perform pg_temp.cm_actor(3); s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),pg_temp.cm_key('c',1),1);
 perform pg_temp.cm_check(not(s->>'can_edit')::boolean,'other padrão cannot correct');
 perform pg_temp.cm_reject(pg_temp.cm_payload(pg_temp.cm_key('c',1)),'42501');
 perform pg_temp.cm_actor(1); s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),pg_temp.cm_key('c',1),1);
 perform pg_temp.cm_check((s->>'can_edit')::boolean,'administrator can correct another creator while preserving attribution');
 for n in 4..6 loop perform pg_temp.cm_actor(n);
  if n=4 then s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),pg_temp.cm_key('c',1),1); perform pg_temp.cm_check(not(s->>'can_edit')::boolean,'auditor reads only');
  else set local role authenticated; begin perform public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),pg_temp.cm_key('c',1),1); raise exception 'FAIL: inactive/customer read'; exception when insufficient_privilege then null; end; reset role; end if;
  perform pg_temp.cm_reject(jsonb_build_object('projeto_id',pg_temp.cm_key('5',1),'comentario_id',pg_temp.cm_key('c',1)),'42501');
 end loop; perform pg_temp.cm_actor(2);
end $$;
select pg_temp.cm_check(not has_table_privilege('authenticated','rm_private.project_comment_revisions','select')
 and not has_table_privilege('service_role','rm_private.project_comment_revisions','insert')
 and not has_function_privilege('anon','public.rm_web_project_comment_snapshot_v1(uuid,uuid,integer)','execute')
 and not has_function_privilege('service_role','rm_private.project_comment_revision_context_v1(uuid,uuid,integer)','execute')
 and not has_function_privilege('authenticated','rm_private.guard_project_comment_revisions_v1()','execute'),'private history/guard and snapshot scopes');
create temporary table cm_saved(p jsonb,rid uuid,r jsonb);
do $$ declare p jsonb; r jsonb; before_row jsonb; after_row jsonb; creation_receipt jsonb; outbox_count bigint; s jsonb; cid uuid:=pg_temp.cm_key('c',1); begin
 perform set_config('TimeZone','UTC',true);
 select to_jsonb(c) into before_row from public.rm_comentarios c where id=cid;
 select to_jsonb(x) into creation_receipt from rm_private.web_mutation_receipts x where client_submission_id=cid;
 select count(*) into outbox_count from public.rm_sync_outbox;
 perform set_config('TimeZone','UTC',true);
 perform pg_temp.cm_check((public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),cid,1)->>'can_edit')::boolean,'creation provenance survives timezone change');
 p:=pg_temp.cm_payload(cid,'  Corrected text with units 55 kW  '); p:=p||'{"motivo":"  Verified correction  "}';
 r:=pg_temp.cm_call(p,pg_temp.cm_key('f',1)); insert into cm_saved values(p,pg_temp.cm_key('f',1),r);
 select to_jsonb(c) into after_row from public.rm_comentarios c where id=cid;
 perform pg_temp.cm_check((before_row-array['evento','updated_at'])=(after_row-array['evento','updated_at']) and after_row->>'evento'='Corrected text with units 55 kW','only text/version changed; original identity/import/source untouched');
 perform pg_temp.cm_check((select to_jsonb(x)=creation_receipt from rm_private.web_mutation_receipts x where client_submission_id=cid),'original creation receipt remains byte-identical');
 perform pg_temp.cm_check((select count(*)=outbox_count from public.rm_sync_outbox),'correction does not enqueue external bridge work');
 perform pg_temp.cm_check(r->'record'->>'revision'='1' and(r->'record'->>'changed')::boolean and r->'record'->>'context_version'=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),cid,1)->>'context_version','fresh minimal result/context');
 perform pg_temp.cm_check((select before_record=before_row and after_record=after_row and motivo='Verified correction' and actor_id=pg_temp.cm_key('2',2) from rm_private.project_comment_revisions where client_submission_id=pg_temp.cm_key('f',1)),'exact before/after author/reason journal');
 r:=pg_temp.cm_call(p,pg_temp.cm_key('f',1)); perform pg_temp.cm_check((r->>'idempotent_replay')::boolean,'exact correction replay');
 perform pg_temp.cm_reject(p||'{"evento":"Different intention"}','23505',pg_temp.cm_key('f',1));
 perform pg_temp.cm_reject(p,'PT409');
 p:=pg_temp.cm_payload(cid,'Corrected text with units 55 kW'); r:=pg_temp.cm_call(p,pg_temp.cm_key('f',2));
 perform pg_temp.cm_check(not(r->'record'->>'changed')::boolean and r->'record'->>'revision'='1' and (select to_jsonb(c)=after_row from public.rm_comentarios c where id=cid)
  and not exists(select 1 from rm_private.project_comment_revisions where client_submission_id=pg_temp.cm_key('f',2)),'no-op produces receipt only, no timestamp/history');
 perform set_config('TimeZone','America/Sao_Paulo',true);
 perform pg_temp.cm_check((public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),cid,1)->>'can_edit')::boolean,'audited origin survives another timezone change');
 for i in 2..27 loop perform pg_temp.cm_call(pg_temp.cm_payload(cid,'Correction version '||i)); end loop;
 s:=public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),cid,999);
 perform pg_temp.cm_check((s->'history'->>'total')::int=27 and(s->'history'->>'page')::int=2 and jsonb_array_length(s->'history'->'items')=2
  and s->'history'->'items'->0->>'revision'='2' and s->'history'->'items'->1->>'evento_anterior'=before_row->>'evento','bounded clamped descending history retains original first text');
 r:=pg_temp.cm_add(1); perform pg_temp.cm_check((r->>'idempotent_replay')::boolean and r->'record'->>'evento'='Original manual 1' and (select evento='Correction version 27' from public.rm_comentarios where id=cid),'original web creation receipt replays unchanged after corrections');
 perform pg_temp.cm_check(not(s->'history'->'items'->0 ?| array['auth_user_id','client_submission_id','before_record','after_record','transaction_id']),'safe business history excludes private identity/receipt/full rows');
 begin update public.rm_comentarios set evento='Stale ETL body' where id=cid; raise exception 'FAIL: overwritten audit'; exception when sqlstate 'PT409' then null; end;
 begin update public.rm_comentarios set cadastrado_por_id=pg_temp.cm_key('2',1) where id=cid; raise exception 'FAIL: rewritten creator'; exception when sqlstate 'PT409' then null; end;
 begin delete from public.rm_comentarios where id=cid; raise exception 'FAIL: deleted corrected comment'; exception when sqlstate 'PT409' then null; end;
 perform set_config('rm.allow_comment_edit','true',true);
 begin update public.rm_comentarios set evento='Client flag bypass' where id=cid; raise exception 'FAIL: GUC bypass'; exception when sqlstate 'PT409' then null; end;
 update public.rm_comentarios set bubble_modified_at=clock_timestamp() where id=cid;
 perform pg_temp.cm_check((public.rm_web_project_comment_snapshot_v1(pg_temp.cm_key('5',1),cid,1)->>'can_edit')::boolean,'metadata-only external refresh preserves manual chain');
 perform pg_temp.cm_call(pg_temp.cm_payload((select(m.r->>'comentario_id')::uuid from cm_mobile m),'Corrected mobile manual'));
 set local role authenticated; r:=(select public.rm_mobile_mutate_v1(m.rid,'rm_add_cell_comment_v1',m.p,'comment-test-mobile') from cm_mobile m); reset role;
 perform pg_temp.cm_check((r->>'idempotent_replay')::boolean,'completed original mobile receipt still replays after correction without duplicate insertion');
end $$;
-- Strict fields, current identity before replay, closed/unknown contexts remain protected.
do $$ declare p jsonb; r jsonb; key text; begin
 p:=pg_temp.cm_payload(pg_temp.cm_key('c',2));
 foreach key in array array['cadastrado_por_id','celula_id','created_at','projeto_override','bubble_id'] loop perform pg_temp.cm_reject(p||jsonb_build_object(key,'forbidden'),'22023'); end loop;
 perform pg_temp.cm_reject(p||'{"evento":"   "}','22023'); perform pg_temp.cm_reject(p||'{"motivo":"   "}','22023');
 perform pg_temp.cm_reject(p||jsonb_build_object('evento',chr(9)||chr(10)),'22023'); perform pg_temp.cm_reject(p||jsonb_build_object('motivo',chr(9)||chr(10)),'22023');
 perform pg_temp.cm_reject(p||jsonb_build_object('evento',repeat('X',10001)),'22023'); perform pg_temp.cm_reject(p||jsonb_build_object('motivo',repeat('X',2001)),'22023');
 perform pg_temp.cm_reject(p||'{"confirm_change":false}','22023'); perform pg_temp.cm_reject(p,'22023',gen_random_uuid(),'em.projects.read');
 perform pg_temp.cm_reject(pg_temp.cm_payload(pg_temp.cm_key('c',4)),'42501'); perform pg_temp.cm_reject(pg_temp.cm_payload(pg_temp.cm_key('c',6)),'42501');
 -- Downgrading the administrator does not allow replay of another author's correction.
 perform pg_temp.cm_actor(1); p:=pg_temp.cm_payload(pg_temp.cm_key('c',3),'Administrator verified text');
 perform pg_temp.cm_call(p,pg_temp.cm_key('f',3));
 update public.rm_users set perfil='padr_o' where id=pg_temp.cm_key('2',1);
 perform pg_temp.cm_reject(p,'42501',pg_temp.cm_key('f',3));
 update public.rm_users set perfil='administrador' where id=pg_temp.cm_key('2',1); perform pg_temp.cm_actor(2);
 select m.p into p from cm_saved m;
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.cm_key('1',2),'totp','verified');
 perform pg_temp.cm_reject(p,'42501',pg_temp.cm_key('f',1)); perform pg_temp.cm_actor(2,'aal2');
 r:=pg_temp.cm_call(p,pg_temp.cm_key('f',1)); perform pg_temp.cm_check((r->>'idempotent_replay')::boolean,'fresh MFA before replay');
 update public.rm_users set status='inativo' where id=pg_temp.cm_key('2',2); perform pg_temp.cm_reject(p,'42501',pg_temp.cm_key('f',1)); update public.rm_users set status='ativo' where id=pg_temp.cm_key('2',2);
 p:=pg_temp.cm_payload(pg_temp.cm_key('c',2)); update public.rm_projetos set status_pcp='cancelado' where id=pg_temp.cm_key('5',1);
 perform pg_temp.cm_reject(p,'PT409'); p:=pg_temp.cm_payload(pg_temp.cm_key('c',2)); perform pg_temp.cm_reject(p,'42501');
 select m.p into p from cm_saved m; r:=pg_temp.cm_call(p,pg_temp.cm_key('f',1)); perform pg_temp.cm_check((r->>'idempotent_replay')::boolean,'completed correction replays after closure');
end $$;
rollback;
select 'PASS:032 proven manual comment correction, exact attribution/history, scoped reads, current SSO/MFA replay and external-write guards' as result;

-- Real independent transactions, committed only in this disposable local database.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_comment_revisions;
create function rm_test_comment_revisions.key(h text,n int) returns uuid language sql immutable as $$ select(h||'f350000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function rm_test_comment_revisions.check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values(rm_test_comment_revisions.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_comment_revisions.key('2',1),rm_test_comment_revisions.key('1',1),'Comment race actor','administrador');
insert into auth.sessions(id,user_id) values(rm_test_comment_revisions.key('3',1),rm_test_comment_revisions.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_comment_revisions.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_comment_revisions.key('9',1),rm_test_comment_revisions.key('2',1),rm_test_comment_revisions.key('1',1),true,rm_test_comment_revisions.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('f5',32),rm_test_comment_revisions.key('8',1),rm_test_comment_revisions.key('3',1),'opaque-comment-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('comment-mobile-races','sha256'),rm_test_comment_revisions.key('1',1),rm_test_comment_revisions.key('2',1),rm_test_comment_revisions.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_clientes(id,nome) values(rm_test_comment_revisions.key('4',1),'Comment race client');
insert into public.rm_celulas(id,nome) values(rm_test_comment_revisions.key('a',1),'Comment race cell');
insert into public.rm_projetos(id,numero,cliente_id) select rm_test_comment_revisions.key('5',n),'COMMENT-RACE-32-'||n,rm_test_comment_revisions.key('4',1) from generate_series(1,10) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id) select rm_test_comment_revisions.key('b',n),rm_test_comment_revisions.key('5',n),rm_test_comment_revisions.key('a',1) from generate_series(1,10) n;
create function rm_test_comment_revisions.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; op text; begin
 perform set_config('request.jwt.claim.sub',rm_test_comment_revisions.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_comment_revisions.key('3',1),'aal','aal1')::text,true);
 if mode in('edit','close','create') then
  op:=case mode when 'edit' then 'edit_project_comment' when 'close' then 'save_project' else 'add_project_comment' end;
  perform public.rm_sso_action_permit_v1(repeat('f5',32),rid,op,p,'em.projects.manage');
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role;
 elsif mode='raw' then update public.rm_comentarios set evento='Raw concurrent' where id=(p->>'comentario_id')::uuid;
 elsif mode='allocation' then update public.rm_celulas_projeto set observacao='Allocation concurrent' where id=(p->>'id')::uuid;
 elsif mode='mobile' then set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_add_cell_comment_v1',p,'comment-mobile-races'); reset role;
 else raise exception 'Unknown local comment race'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state,'message',sqlerrm); end $$;
do $$ declare n int; p jsonb; r jsonb; begin for n in 1..10 loop
 p:=jsonb_build_object('projeto_id',rm_test_comment_revisions.key('5',n),'celula_projeto_id',rm_test_comment_revisions.key('b',n),
  'expected_project_updated_at',(select updated_at from public.rm_projetos where id=rm_test_comment_revisions.key('5',n)),
  'expected_allocation_updated_at',(select updated_at from public.rm_celulas_projeto where id=rm_test_comment_revisions.key('b',n)),'evento','Original race '||n);
 r:=rm_test_comment_revisions.run('create',rm_test_comment_revisions.key('c',n),p);
 perform rm_test_comment_revisions.check(r->>'sqlstate'='00000','manual race fixture creation'); end loop; end $$;
commit;
do $$ declare scenario int; s jsonb; p jsonb; other_p jsonb; first_p jsonb; second_p jsonb; a jsonb; b jsonb;
 first_mode text; second_mode text; first_id uuid; second_id uuid; pid_a int; pid_b int; waited int; expected_state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_comment_revisions.key('1',1)::text,true);
 perform dblink_connect('comment_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('comment_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('comment_a','select pg_backend_pid()') as t(pid int);
 select pid into pid_b from dblink('comment_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..10 loop
  s:=public.rm_web_project_comment_snapshot_v1(rm_test_comment_revisions.key('5',scenario),rm_test_comment_revisions.key('c',scenario),1);
  p:=jsonb_build_object('projeto_id',s->'project'->>'id','comentario_id',s->'comment'->>'id',
   'expected_project_updated_at',s->'project'->>'updated_at','expected_comment_updated_at',s->'comment'->>'updated_at',
   'expected_context_version',s->>'context_version','confirm_change',true,'evento','Web corrected concurrent','motivo','Concurrent verification');
  first_mode:='edit'; second_mode:='edit'; other_p:=p;
  if scenario in(3,4) then
   other_p:=jsonb_build_object('id',rm_test_comment_revisions.key('5',scenario),'expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('status_pcp','cancelado'));
   first_mode:=case when scenario=4 then 'close' else 'edit' end; second_mode:=case when scenario=4 then 'edit' else 'close' end;
  elsif scenario in(5,6) then other_p:=jsonb_build_object('comentario_id',rm_test_comment_revisions.key('c',scenario));
   first_mode:=case when scenario=6 then 'raw' else 'edit' end; second_mode:=case when scenario=6 then 'edit' else 'raw' end;
  elsif scenario in(7,8) then other_p:=jsonb_build_object('id',rm_test_comment_revisions.key('b',scenario));
   first_mode:=case when scenario=8 then 'allocation' else 'edit' end; second_mode:=case when scenario=8 then 'edit' else 'allocation' end;
  elsif scenario in(9,10) then other_p:=jsonb_build_object('p_celula_projeto_id',rm_test_comment_revisions.key('b',scenario),'p_comentario','Original offline intention');
   first_mode:=case when scenario=10 then 'mobile' else 'edit' end; second_mode:=case when scenario=10 then 'edit' else 'mobile' end;
  end if;
  first_p:=case when first_mode='edit' then p else other_p end; second_p:=case when second_mode='edit' then p else other_p end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=2 then first_id else gen_random_uuid() end;
  perform dblink_send_query('comment_a',format('select rm_test_comment_revisions.run(%L,%L,%L::jsonb,0.7)',first_mode,first_id,first_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first comment race % did not hold',scenario; end if; perform pg_sleep(0.01); end loop;
  perform dblink_send_query('comment_b',format('select rm_test_comment_revisions.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_p::text));
  if scenario<>9 then
   waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
    waited:=waited+1; if waited>100 then raise exception 'FAIL: second comment race % did not contend',scenario; end if; perform pg_sleep(0.005); end loop;
  end if;
  select r into a from dblink_get_result('comment_a') as t(r jsonb); perform r from dblink_get_result('comment_a') as t(r jsonb);
  select r into b from dblink_get_result('comment_b') as t(r jsonb); perform r from dblink_get_result('comment_b') as t(r jsonb);
  expected_state:=case when scenario in(2,3,7,9,10) then '00000' else 'PT409' end;
  perform rm_test_comment_revisions.check(a->>'sqlstate'='00000',format('first comment race %s: %s',scenario,a));
  perform rm_test_comment_revisions.check(b->>'sqlstate'=expected_state or (scenario=9 and b->>'sqlstate'='PT409'),format('second comment race %s: %s',scenario,b));
  if scenario=2 then perform rm_test_comment_revisions.check((b->'result'->>'idempotent_replay')::boolean
   and(select count(*)=1 from rm_private.project_comment_revisions where comentario_id=rm_test_comment_revisions.key('c',scenario)),'same UUID returns completed receipt with one history event'); end if;
  if scenario=9 and b->>'sqlstate'='PT409' then
   perform rm_test_comment_revisions.check(not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=second_id),'blocked offline intention creates no receipt');
   b:=rm_test_comment_revisions.run('mobile',second_id,second_p);
   perform rm_test_comment_revisions.check(b->>'sqlstate'='00000' and exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=second_id and params=second_p),'same offline UUID/body retries after parent is available');
  end if;
  if scenario=9 then perform rm_test_comment_revisions.check(exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=second_id and params=second_p),'original mobile intention accepted once after contention'); end if;
  if scenario in(1,2,3,5,7,9,10) then perform rm_test_comment_revisions.check((select evento='Web corrected concurrent' from public.rm_comentarios where id=rm_test_comment_revisions.key('c',scenario)),'winning comment text preserved'); end if;
 end loop;
 perform dblink_disconnect('comment_a'); perform dblink_disconnect('comment_b');
exception when others then if 'comment_a'=any(dblink_get_connections()) then perform dblink_disconnect('comment_a'); end if;
 if 'comment_b'=any(dblink_get_connections()) then perform dblink_disconnect('comment_b'); end if; raise; end $$;
select 'PASS:10 real comment races cover two editors, exact retry, closure, raw writes, allocation context and original mobile intentions' as result;

-- TEST DATABASE ONLY: canonical technical editing, exact receipts and old mobile coexistence.
\set ON_ERROR_STOP on
begin;
create function pg_temp.eq_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.eq_key(h text,n int) returns uuid language sql immutable as $$
 select (h||'f310000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.eq_actor(n int,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.eq_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.eq_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.eq.actor',n::text,true); end $$;
create function pg_temp.eq_call(p jsonb,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.eq.actor'),64,'f3'),rid,'save_project_equipment',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'save_project_equipment',p); reset role; return r;
 exception when others then reset role; raise; end $$;
create function pg_temp.eq_reject(p jsonb,wanted text,rid uuid default gen_random_uuid(),cap text default 'em.projects.manage') returns void language plpgsql as $$ declare actual text; begin
 begin perform pg_temp.eq_call(p,rid,cap); exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm; end;
 raise exception 'FAIL: technical edit unexpectedly succeeded'; end $$;
create function pg_temp.eq_payload(changes jsonb,n int default 1) returns jsonb language plpgsql as $$ declare s jsonb; begin
 s:=public.rm_web_project_equipment_snapshot_v1(pg_temp.eq_key('5',n));
 return jsonb_build_object('projeto_id',s->'project'->>'id','equipamento_id',s->'project'->>'equipamento_id',
  'expected_project_updated_at',s->'project'->>'updated_at','expected_equipment_updated_at',s->'equipment'->>'updated_at',
  'expected_context_version',s->>'context_version','confirm_change',true,'changes',changes); end $$;
create function pg_temp.eq_mobile(p jsonb,rid uuid default gen_random_uuid()) returns jsonb language plpgsql as $$ declare r jsonb; begin
 set local role authenticated;
 r:=public.rm_mobile_mutate_v1(rid,'rm_submit_recebimento_v1',p,'equipment-test-mobile'); reset role; return r;
 exception when others then reset role; raise; end $$;
do $$ declare n int; begin for n in 1..5 loop
 insert into auth.users(id) values(pg_temp.eq_key('1',n));
 insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.eq_key('2',n),pg_temp.eq_key('1',n),'Equipment actor '||n,
  case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' when n=5 then 'cliente' else 'padr_o' end,
  case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
 insert into auth.sessions(id,user_id) values(pg_temp.eq_key('3',n),pg_temp.eq_key('1',n));
 insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(pg_temp.eq_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.eq_key('9',n),pg_temp.eq_key('2',n),pg_temp.eq_key('1',n),true,pg_temp.eq_key('2',1),clock_timestamp());
 if n in(1,2,3) then perform public.rm_sso_session_put_v1(lpad(n::text,64,'f3'),pg_temp.eq_key('8',n),pg_temp.eq_key('3',n),'opaque-equipment-fixture-'||n,clock_timestamp()+interval '45 minutes'); end if;
 end loop; end $$;
update rm_private.sso_settings set require_sso=true;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('equipment-test-mobile','sha256'),pg_temp.eq_key('1',1),pg_temp.eq_key('2',1),pg_temp.eq_key('2',1),clock_timestamp()+interval '1 day');
insert into public.rm_clientes(id,nome) values(pg_temp.eq_key('4',1),'Equipment test client');
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.eq_key('a',1),'Legacy type A'),(pg_temp.eq_key('a',2),'Legacy type B');
insert into public.rm_projetos(id,numero,cliente_id,tipo_equipamento_id,status_pcp,data_real_de_entrega)
 select pg_temp.eq_key('5',n),'EQUIPMENT-31-'||n,pg_temp.eq_key('4',1),pg_temp.eq_key('a',1),
 case when n=3 then 'cancelado'::public.rm_status_pcp_enum when n=4 then 'finalizando_para_faturar' end,
 case when n=5 then clock_timestamp() end from generate_series(1,13) n;
insert into public.rm_equipamentos(id,projeto_id,tipo_equipamento_id,descricao,potencia,fabricante,fp,fs,numero_cabos,desmontar_para_orcar,ensaiar_antes_desmontar,teste_intermediario,bubble_id,sync_source)
 select pg_temp.eq_key('6',n),pg_temp.eq_key('5',n),pg_temp.eq_key('a',2),'Original description','["55 kW","75 kW"]',repeat('L',10001),
 1.23000000000000000001,-0.00000000000000000001,-5,'sim','n_o','sim','equipment-legacy-'||n,'bubble' from generate_series(1,6) n;
update public.rm_projetos set equipamento_id=pg_temp.eq_key('6',n) from generate_series(1,6) n where id=pg_temp.eq_key('5',n);
-- Missing7; unlinked8; orphaned9; conflicting10; shared11/12; coherent13.
insert into public.rm_equipamentos(id,projeto_id,descricao) values
 (pg_temp.eq_key('6',8),pg_temp.eq_key('5',8),'Unlinked private contents'),
 (pg_temp.eq_key('6',9),null,'Orphan private contents'),
 (pg_temp.eq_key('6',10),pg_temp.eq_key('5',13),'Foreign private contents'),
 (pg_temp.eq_key('6',11),pg_temp.eq_key('5',11),'Shared private contents');
update public.rm_projetos set equipamento_id=pg_temp.eq_key('6',9) where id=pg_temp.eq_key('5',9);
update public.rm_projetos set equipamento_id=pg_temp.eq_key('6',10) where id=pg_temp.eq_key('5',10);
update public.rm_projetos set equipamento_id=pg_temp.eq_key('6',11) where id in(pg_temp.eq_key('5',11),pg_temp.eq_key('5',12));
select pg_temp.eq_actor(1);

-- Only current internal readers, explicit safe projection, no arbitrary fallback.
do $$ declare s jsonb; n int; wanted text; begin
 set local role authenticated; s:=public.rm_web_project_equipment_snapshot_v1(pg_temp.eq_key('5',1)); reset role;
 perform pg_temp.eq_check(s->>'binding_state'='linked' and (s->>'can_edit')::boolean and (s->>'type_mismatch')::boolean,'canonical binding and legacy type mismatch eligible');
 perform pg_temp.eq_check(s->'equipment'->>'fp'='1.23000000000000000001' and s->'equipment'->>'fs'='-0.00000000000000000001'
  and (s->'equipment'->>'numero_cabos')::int=-5,'legacy exact decimal strings and negative cable value remain readable');
 perform pg_temp.eq_check(not(s->'equipment' ?| array['bubble_id','sync_source','desmontar_para_orcar','ensaiar_antes_desmontar','teste_intermediario']),'no private import/retired fields in DTO');
 for n in 7..12 loop
  s:=public.rm_web_project_equipment_snapshot_v1(pg_temp.eq_key('5',n));
  wanted:=case n when 7 then 'missing' when 8 then 'unlinked' when 9 then 'orphaned' when 10 then 'conflicting' when 11 then 'shared' else 'conflicting' end;
  perform pg_temp.eq_check(s->>'binding_state'=wanted and s->'equipment'='null'::jsonb and not(s->>'can_edit')::boolean
   and not(s->>'type_mismatch')::boolean,'noncanonical readonly without foreign equipment blob '||n);
 end loop;
 perform pg_temp.eq_check(public.rm_web_project_equipment_snapshot_v1(gen_random_uuid()) is null,'unknown project returns null');
 for n in 1..3 loop
  perform pg_temp.eq_actor(n); set local role authenticated;
  s:=public.rm_web_project_equipment_snapshot_v1(pg_temp.eq_key('5',1)); reset role;
  perform pg_temp.eq_check((s->>'can_edit')::boolean,'operational eligibility independent of reader role');
 end loop;
 for n in 4..5 loop
  perform pg_temp.eq_actor(n); set local role authenticated;
  begin perform public.rm_web_project_equipment_snapshot_v1(pg_temp.eq_key('5',1)); raise exception 'FAIL: restricted snapshot exposed'; exception when insufficient_privilege then null; end;
  reset role;
 end loop;
 perform pg_temp.eq_actor(1);
end $$;
select pg_temp.eq_check(not has_table_privilege('authenticated','rm_private.equipment_change_events','select')
 and not has_table_privilege('service_role','rm_private.equipment_change_events','select')
 and not has_function_privilege('authenticated','rm_private.assert_legacy_equipment_edit_v1(uuid,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('anon','public.rm_web_project_equipment_snapshot_v1(uuid)','execute'),'private journal/guards/core inaccessible');

-- Warm completed receiving receipt before web ownership, then replay after web save.
create temporary table eq_completed_mobile(p jsonb,rid uuid,r jsonb);
insert into eq_completed_mobile(p,rid) values(jsonb_build_object('p_projeto_id',pg_temp.eq_key('5',2),'p_cliente_id',pg_temp.eq_key('4',1),
 'p_equipamento',jsonb_build_object('descricao','Original description'),'p_fotos_recebimento','[]'::jsonb),pg_temp.eq_key('f',70));
update eq_completed_mobile set r=pg_temp.eq_mobile(p,rid);

do $$ declare p jsonb; r jsonb; before_project jsonb; before_equipment jsonb; after_equipment jsonb; journal jsonb; n int; begin
 select to_jsonb(x) into before_project from public.rm_projetos x where id=pg_temp.eq_key('5',1);
 select to_jsonb(x) into before_equipment from public.rm_equipamentos x where id=pg_temp.eq_key('6',1);
 p:=pg_temp.eq_payload('{"descricao":"  Exact whitespace  ","potencia":"[\"55 kW\",\"75 kW\"]","fp":"+123456789012345678901234567890.12345678901234567890","fs":"-2.75","numero_cabos":2147483647,"placa_motor":"c___placa"}');
 r:=pg_temp.eq_call(p,pg_temp.eq_key('f',1));
 select to_jsonb(x) into after_equipment from public.rm_equipamentos x where id=pg_temp.eq_key('6',1);
 perform pg_temp.eq_check(r->'record'->>'context_version'=public.rm_web_project_equipment_snapshot_v1(pg_temp.eq_key('5',1))->>'context_version'
  and r->>'updated_at'=after_equipment->>'updated_at','save returns fresh post-write context and equipment version');
 perform pg_temp.eq_check(r->>'id'=pg_temp.eq_key('6',1)::text and r->'record'->'changed_fields'='["descricao","fp","fs","numero_cabos","placa_motor"]'::jsonb,'result actual changed subset excludes identical requested string');
 perform pg_temp.eq_check(after_equipment->>'descricao'='  Exact whitespace  ' and after_equipment->>'fp'='123456789012345678901234567890.12345678901234567890','exact whitespace and SQL decimal precision');
 perform pg_temp.eq_check((after_equipment-array['descricao','fp','fs','numero_cabos','placa_motor','updated_at','sync_source'])=
  (before_equipment-array['descricao','fp','fs','numero_cabos','placa_motor','updated_at','sync_source']),'only actually dirty fields changed; oversize legacy/retired flags/type IDs unchanged');
 perform pg_temp.eq_check((select to_jsonb(x)=before_project from public.rm_projetos x where id=pg_temp.eq_key('5',1)),'no project/receipt description/type rewrite');
 perform pg_temp.eq_check((select before_record=before_equipment and after_record=after_equipment and actor_id=pg_temp.eq_key('2',1)
  and client_submission_id=pg_temp.eq_key('f',1) and changed_fields=array['descricao','fp','fs','numero_cabos','placa_motor'] from rm_private.equipment_change_events where client_submission_id=pg_temp.eq_key('f',1)),'private complete before/after server author and protocol');
 perform pg_temp.eq_check(not(r ? 'before_record') and not(r->'record' ? 'descricao'),'minimal result excludes technical values/private audit');
 r:=pg_temp.eq_call(p,pg_temp.eq_key('f',1));
 perform pg_temp.eq_check((r->>'idempotent_replay')::boolean and (select count(*)=1 from rm_private.equipment_change_events where client_submission_id=pg_temp.eq_key('f',1)),'exact replay no duplicate event');
 perform pg_temp.eq_reject(p||'{"changes":{"descricao":"Other intention"}}','23505',pg_temp.eq_key('f',1));
 perform pg_temp.eq_reject(p,'PT409');
 p:=pg_temp.eq_payload('{"descricao":"  Exact whitespace  ","fp":"123456789012345678901234567890.1234567890123456789"}');
 r:=pg_temp.eq_call(p,pg_temp.eq_key('f',2));
 perform pg_temp.eq_check(r->'record'->'changed_fields'='[]'::jsonb and not exists(select 1 from rm_private.equipment_change_events where client_submission_id=pg_temp.eq_key('f',2))
  and (select to_jsonb(x)=after_equipment from public.rm_equipamentos x where id=pg_temp.eq_key('6',1)),'numeric-scale/text no-op receipt without update/audit/timestamp');
 p:=pg_temp.eq_payload('{"descricao":null,"fs":null,"numero_cabos":0}');
 perform pg_temp.eq_call(p,pg_temp.eq_key('f',3));
 perform pg_temp.eq_check((select descricao is null and fs is null and numero_cabos=0 from public.rm_equipamentos where id=pg_temp.eq_key('6',1)),'explicit null clears; zero cable count valid');
 perform pg_temp.eq_call(pg_temp.eq_payload('{"descricao":"Web owns description"}',2),pg_temp.eq_key('f',4));
 perform pg_temp.eq_check((select (pg_temp.eq_mobile(m.p,m.rid)->>'idempotent_replay')::boolean from eq_completed_mobile m),'completed old mobile receipt replays after web edits');
end $$;

-- Strict patch: no accidental identities, planning type, flags or value coercion.
do $$ declare c jsonb; p jsonb; k text; begin
 p:=pg_temp.eq_payload('{"modelo":"Valid"}');
 foreach c in array array['{}'::jsonb,'{"tipo_equipamento_id":null}','{"projeto_id":null}','{"bubble_id":"x"}','{"sync_source":"etl"}',
  '{"desmontar_para_orcar":"sim"}','{"ensaiar_antes_desmontar":"sim"}','{"teste_intermediario":"sim"}',
  '{"fp":0.9}','{"fp":"1e-3"}','{"fp":".2"}','{"fp":"NaN"}','{"fp":" 1"}','{"fp":"1234567890123456789012345678901"}',
  '{"fs":"0.123456789012345678901"}','{"numero_cabos":-1}','{"numero_cabos":1.5}','{"numero_cabos":"1"}',
  '{"numero_cabos":2147483648}','{"placa_motor":"Sim"}','{"potencia":["55 kW"]}','{"modelo":false}'] loop
  perform pg_temp.eq_reject(p||jsonb_build_object('changes',c),'22023');
 end loop;
 perform pg_temp.eq_reject(p||jsonb_build_object('changes',jsonb_build_object('fabricante',repeat('x',10001))),'22023');
 perform pg_temp.eq_reject(p||'{"confirm_change":false}','22023');
 perform pg_temp.eq_reject(p||'{"unrecognized":true}','22023');
 perform pg_temp.eq_reject(p||'{"expected_project_updated_at":"infinity"}','22023');
 perform pg_temp.eq_reject(p||'{"expected_equipment_updated_at":"2026-02-30T12:00:00Z"}','22023');
 perform pg_temp.eq_reject(p||'{"expected_equipment_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.eq_reject(p||'{"expected_context_version":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}','PT409');
 perform pg_temp.eq_reject(p,'22023',gen_random_uuid(),'em.planning.manage');
 perform pg_temp.eq_actor(3); perform pg_temp.eq_reject(p,'42501'); perform pg_temp.eq_actor(1);
end $$;

-- Old offline edits: overlap rejects atomically without consuming protocol; exact
-- values/unclaimed fields still work. Raw/ETL cannot overwrite owned fields.
do $$ declare p jsonb; r jsonb; project_before jsonb; equipment_before jsonb; rid uuid:=pg_temp.eq_key('f',80); actual text; begin
 p:=jsonb_build_object('p_projeto_id',pg_temp.eq_key('5',2),'p_cliente_id',pg_temp.eq_key('4',1),'p_nome_projeto','Must not be committed',
  'p_equipamento',jsonb_build_object('descricao','Original description','modelo','Unclaimed mobile change'),'p_fotos_recebimento','[]'::jsonb);
 select to_jsonb(x) into project_before from public.rm_projetos x where id=pg_temp.eq_key('5',2);
 select to_jsonb(x) into equipment_before from public.rm_equipamentos x where id=pg_temp.eq_key('6',2);
 begin perform pg_temp.eq_mobile(p,rid); raise exception 'FAIL: stale mobile overwrote web field'; exception when sqlstate 'PT409' then null; end;
 perform pg_temp.eq_check((select to_jsonb(x)=project_before from public.rm_projetos x where id=pg_temp.eq_key('5',2))
  and (select to_jsonb(x)=equipment_before from public.rm_equipamentos x where id=pg_temp.eq_key('6',2))
  and not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=rid),'mobile conflict leaves original project/equipment/queue protocol untouched');
 begin update public.rm_equipamentos set descricao='ETL stale' where id=pg_temp.eq_key('6',2); raise exception 'FAIL: raw overwrite'; exception when sqlstate 'PT409' then null; end;
 begin update public.rm_equipamentos set projeto_id=null where id=pg_temp.eq_key('6',2); raise exception 'FAIL: raw rebind'; exception when sqlstate 'PT409' then null; end;
 begin delete from public.rm_equipamentos where id=pg_temp.eq_key('6',2); raise exception 'FAIL: raw delete'; exception when sqlstate 'PT409' then null; end;
 update public.rm_equipamentos set modelo='Unclaimed ETL change' where id=pg_temp.eq_key('6',2);
 p:=jsonb_set(p,'{p_equipamento,descricao}','"Web owns description"');
 r:=pg_temp.eq_mobile(p,pg_temp.eq_key('f',81));
 perform pg_temp.eq_check((select descricao='Web owns description' and modelo='Unclaimed mobile change' from public.rm_equipamentos where id=pg_temp.eq_key('6',2)),'equal web-owned value plus untouched mobile field accepted');
 -- Shared/unlinked binding must not be silently repaired by receiving.
 update public.rm_projetos set equipamento_id=null where id=pg_temp.eq_key('5',2);
 begin perform pg_temp.eq_mobile(p,pg_temp.eq_key('f',82)); raise exception 'FAIL: mobile repaired web-managed binding'; exception when sqlstate 'PT409' then null; end;
 update public.rm_projetos set equipamento_id=pg_temp.eq_key('6',2) where id=pg_temp.eq_key('5',2);
 update public.rm_projetos set equipamento_id=pg_temp.eq_key('6',2) where id=pg_temp.eq_key('5',7);
 begin perform pg_temp.eq_mobile(p,pg_temp.eq_key('f',83)); raise exception 'FAIL: mobile ignored shared binding'; exception when sqlstate 'PT409' then null; end;
 update public.rm_projetos set equipamento_id=null where id=pg_temp.eq_key('5',7);
end $$;

-- Current authentication precedes even completed receipts; closure forbids new
-- writes but exact successful receipts remain useful to interrupted clients.
do $$ declare p jsonb; r jsonb; n int; begin
 for n in 3..5 loop perform pg_temp.eq_reject(pg_temp.eq_payload('{"modelo":"No closed write"}',n),'22023'); end loop;
 p:=pg_temp.eq_payload('{"modelo":"Before closure"}',6); perform pg_temp.eq_call(p,pg_temp.eq_key('f',90));
 update public.rm_projetos set status_pcp='cancelado' where id=pg_temp.eq_key('5',6);
 r:=pg_temp.eq_call(p,pg_temp.eq_key('f',90)); perform pg_temp.eq_check((r->>'idempotent_replay')::boolean,'closed project exact completed receipt allowed');
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.eq_key('1',1),'totp','verified');
 perform pg_temp.eq_reject(p,'42501',pg_temp.eq_key('f',90));
 perform pg_temp.eq_actor(1,'aal2'); r:=pg_temp.eq_call(p,pg_temp.eq_key('f',90));
 perform pg_temp.eq_check((r->>'idempotent_replay')::boolean,'current MFA satisfied before replay');
 update public.rm_users set status='inativo' where id=pg_temp.eq_key('2',1);
 perform pg_temp.eq_reject(p,'42501',pg_temp.eq_key('f',90));
 update public.rm_users set status='ativo' where id=pg_temp.eq_key('2',1);
end $$;
rollback;
select 'PASS:031 canonical equipment snapshot, exact partial edits, private audit, SSO/MFA replay and mobile/ETL conflict guards' as result;

-- Committed disposable fixtures enable real independent transactions. Retained
-- locally because the production journal correctly prevents deleting edited rows.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_equipment;
create function rm_test_equipment.key(h text,n int) returns uuid language sql immutable as $$ select(h||'f320000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function rm_test_equipment.check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values(rm_test_equipment.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_equipment.key('2',1),rm_test_equipment.key('1',1),'Equipment concurrent writer','administrador');
insert into auth.sessions(id,user_id) values(rm_test_equipment.key('3',1),rm_test_equipment.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_equipment.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_equipment.key('9',1),rm_test_equipment.key('2',1),rm_test_equipment.key('1',1),true,rm_test_equipment.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('f3',32),rm_test_equipment.key('8',1),rm_test_equipment.key('3',1),'opaque-equipment-local-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('equipment-mobile-races','sha256'),rm_test_equipment.key('1',1),rm_test_equipment.key('2',1),rm_test_equipment.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_clientes(id,nome) values(rm_test_equipment.key('4',1),'Equipment concurrent client');
insert into public.rm_projetos(id,numero,cliente_id) select rm_test_equipment.key('5',n),'EQUIPMENT-RACE-31-'||n,rm_test_equipment.key('4',1) from generate_series(1,22) n;
insert into public.rm_equipamentos(id,projeto_id,descricao,modelo) select rm_test_equipment.key('6',n),rm_test_equipment.key('5',n),'Original','Original model' from generate_series(1,11) n;
update public.rm_projetos set equipamento_id=rm_test_equipment.key('6',n) from generate_series(1,11) n where id=rm_test_equipment.key('5',n);
create function rm_test_equipment.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; op text; begin
 perform set_config('request.jwt.claim.sub',rm_test_equipment.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_equipment.key('3',1),'aal','aal1')::text,true);
 if mode in('equipment','close') then
  op:=case when mode='close' then 'save_project' else 'save_project_equipment' end;
  perform public.rm_sso_action_permit_v1(repeat('f3',32),rid,op,p,'em.projects.manage');
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role;
 elsif mode='mobile' then
  set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_submit_recebimento_v1',p,'equipment-mobile-races'); reset role;
 elsif mode='raw' then update public.rm_equipamentos set descricao='Raw concurrent' where id=(p->>'equipamento_id')::uuid;
 elsif mode='bind' then update public.rm_projetos set equipamento_id=(p->>'equipamento_id')::uuid where id=(p->>'other_project_id')::uuid;
 else raise exception 'Unknown local equipment race'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state,'message',sqlerrm); end $$;
commit;
do $$ declare scenario int; s jsonb; p jsonb; other_p jsonb; first_p jsonb; second_p jsonb; a jsonb; b jsonb;
 first_mode text; second_mode text; first_id uuid; second_id uuid; pid_a int; pid_b int; waited int; expected_state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_equipment.key('1',1)::text,true);
 perform dblink_connect('equipment_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('equipment_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('equipment_a','select pg_backend_pid()') as t(pid int);
 select pid into pid_b from dblink('equipment_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..11 loop
  s:=public.rm_web_project_equipment_snapshot_v1(rm_test_equipment.key('5',scenario));
  p:=jsonb_build_object('projeto_id',s->'project'->>'id','equipamento_id',s->'equipment'->>'id',
   'expected_project_updated_at',s->'project'->>'updated_at','expected_equipment_updated_at',s->'equipment'->>'updated_at',
   'expected_context_version',s->>'context_version','confirm_change',true,'changes',jsonb_build_object('descricao','Web concurrent'));
  first_mode:='equipment'; second_mode:='equipment'; other_p:=p;
  if scenario in(1,2,9,10) then
   other_p:=jsonb_build_object('p_projeto_id',rm_test_equipment.key('5',scenario),'p_cliente_id',rm_test_equipment.key('4',1),
    'p_equipamento',case when scenario=9 then jsonb_build_object('modelo','Untouched concurrent') when scenario=10 then jsonb_build_object('descricao','Web concurrent') else jsonb_build_object('descricao','Mobile concurrent') end);
   first_mode:=case when scenario=2 then 'mobile' else 'equipment' end; second_mode:=case when scenario=2 then 'equipment' else 'mobile' end;
  elsif scenario in(3,4) then
   other_p:=jsonb_build_object('id',rm_test_equipment.key('5',scenario),'expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('status_pcp','cancelado'));
   first_mode:=case when scenario=4 then 'close' else 'equipment' end; second_mode:=case when scenario=4 then 'equipment' else 'close' end;
  elsif scenario in(5,6) then
   other_p:=jsonb_build_object('equipamento_id',rm_test_equipment.key('6',scenario));
   first_mode:=case when scenario=6 then 'raw' else 'equipment' end; second_mode:=case when scenario=6 then 'equipment' else 'raw' end;
  elsif scenario in(7,11) then
   other_p:=jsonb_build_object('equipamento_id',rm_test_equipment.key('6',scenario),'other_project_id',rm_test_equipment.key('5',scenario+10));
   first_mode:=case when scenario=7 then 'bind' else 'equipment' end; second_mode:=case when scenario=7 then 'equipment' else 'bind' end;
  end if;
  first_p:=case when first_mode='equipment' then p else other_p end;
  second_p:=case when second_mode='equipment' then p else other_p end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=8 then first_id else gen_random_uuid() end;
  perform dblink_send_query('equipment_a',format('select rm_test_equipment.run(%L,%L,%L::jsonb,0.7)',first_mode,first_id,first_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first equipment race % did not hold',scenario; end if; perform pg_sleep(0.01); end loop;
  perform dblink_send_query('equipment_b',format('select rm_test_equipment.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>100 then raise exception 'FAIL: second equipment race % did not contend',scenario; end if; perform pg_sleep(0.005); end loop;
  select r into a from dblink_get_result('equipment_a') as t(r jsonb); perform r from dblink_get_result('equipment_a') as t(r jsonb);
  select r into b from dblink_get_result('equipment_b') as t(r jsonb); perform r from dblink_get_result('equipment_b') as t(r jsonb);
  expected_state:=case when scenario in(3,8,9,10,11) then '00000' else 'PT409' end;
  perform rm_test_equipment.check(a->>'sqlstate'='00000',format('first equipment race %s: %s',scenario,a));
  perform rm_test_equipment.check(b->>'sqlstate'=expected_state,format('second equipment race %s: %s',scenario,b));
  if scenario=8 then perform rm_test_equipment.check((b->'result'->>'idempotent_replay')::boolean
   and(select count(*)=1 from rm_private.equipment_change_events where equipamento_id=rm_test_equipment.key('6',scenario)),'concurrent same UUID produces one audit and completed replay'); end if;
  if scenario in(1,3,5,8,9,10) then perform rm_test_equipment.check((select descricao='Web concurrent' from public.rm_equipamentos where id=rm_test_equipment.key('6',scenario)),'winning web technical field never overwritten'); end if;
  if scenario=9 then perform rm_test_equipment.check((select modelo='Untouched concurrent' from public.rm_equipamentos where id=rm_test_equipment.key('6',scenario)),'unclaimed mobile field remains writable after concurrent web edit'); end if;
  if scenario in(7,11) then perform rm_test_equipment.check(public.rm_web_project_equipment_snapshot_v1(rm_test_equipment.key('5',scenario))->>'binding_state'='shared','serialized external binding makes subsequent editor read only'); end if;
 end loop;
 perform dblink_disconnect('equipment_a'); perform dblink_disconnect('equipment_b');
exception when others then if 'equipment_a'=any(dblink_get_connections()) then perform dblink_disconnect('equipment_a'); end if;
 if 'equipment_b'=any(dblink_get_connections()) then perform dblink_disconnect('equipment_b'); end if; raise; end $$;
select 'PASS:11 real equipment races cover old receiving, closure, raw writers and shared binding in both orders, exact retry, unclaimed and unchanged mobile fields' as result;

\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end $$;
insert into auth.users(id) values('14500000-0000-4000-8000-000000000001'),('14500000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,matricula,nome,perfil) values
 ('24500000-0000-4000-8000-000000000001','14500000-0000-4000-8000-000000000001','DRAFTADMIN','Draft admin','administrador'),
 ('24500000-0000-4000-8000-000000000002','14500000-0000-4000-8000-000000000002','DRAFTOTHER','Draft other','administrador');
insert into rm_private.user_credentials(user_id,palavra_chave_hash) values
 ('24500000-0000-4000-8000-000000000001',extensions.crypt('fixture',extensions.gen_salt('bf',4))),
 ('24500000-0000-4000-8000-000000000002',extensions.crypt('fixture',extensions.gen_salt('bf',4)));
insert into public.rm_clientes(id,nome) values('44500000-0000-4000-8000-000000000001','Draft client');
select set_config('rm.test.project_count',(select count(*)::text from public.rm_projetos),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','14500000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"14500000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare a jsonb; draft jsonb; saved jsonb; begin
 a:=public.rm_authenticate_operator_v1('DRAFTADMIN','fixture');
 perform set_config('rm.test.draft_token',a->>'operator_token',true);
 draft:=jsonb_build_object('id','94500000-0000-4000-8000-000000000001','version',2,'step',0,'cliente','','chegada','2026-11-16T12:00:00Z','fotos','[]'::jsonb,'notaFiscal','NF DRAFT');
 saved:=public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000001',draft,0,'a4500000-0000-4000-8000-000000000001');
 perform pg_temp.check(saved->>'revision'='1' and saved->>'state'='draft','partial autosave accepted before receiving validation');
 perform pg_temp.check(public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read')->>'id'=draft->>'id','cloud resume active slot');
 perform pg_temp.check(public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000001',draft,0,'a4500000-0000-4000-8000-000000000001')->>'revision'='1','lost save response exact replay');
 begin
  perform public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000001',draft||'{"notaFiscal":"different"}',0,'a4500000-0000-4000-8000-000000000001');
  raise exception 'FAIL: changed save replay accepted';
 exception when invalid_parameter_value then null;end;
 begin
  perform public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000001',draft||'{"notaFiscal":"other device"}',0,'a4500000-0000-4000-8000-000000000002');
  raise exception 'FAIL: stale cloud revision accepted';
 exception when sqlstate 'PT409' then null;end;
 saved:=public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000001',draft||'{"notaFiscal":"newer"}',1,'a4500000-0000-4000-8000-000000000002');
 perform pg_temp.check(saved->>'revision'='2','second edit increments revision');
 begin
  perform public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000002',draft||'{"id":"94500000-0000-4000-8000-000000000002"}',0,'a4500000-0000-4000-8000-000000000003');
  raise exception 'FAIL: parallel active slot accepted';
 exception when sqlstate 'PT409' then null;end;
 perform set_config('rm.test.draft_payload',draft::text,true);
end $$;
reset role;
select pg_temp.check((select count(*)::text=current_setting('rm.test.project_count') from public.rm_projetos),'autosave creates no effective project');
select pg_temp.check((select count(*)=0 from rm_private.mobile_mutation_receipts where client_submission_id='94500000-0000-4000-8000-000000000001'),'autosave creates no final mutation receipt');
set local role authenticated;
do $$ declare params jsonb; saved jsonb; first_result jsonb; begin
 params:=jsonb_build_object('p_receiving_draft_id','94500000-0000-4000-8000-000000000001','p_receiving_draft_revision',2,
  'p_receiving_draft_snapshot',current_setting('rm.test.draft_payload')::jsonb,'p_chegada_equipamento','2026-11-16T12:00:00Z');
 begin
  perform public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'));
  raise exception 'FAIL: invalid final receiving accepted';
 exception when invalid_parameter_value then null;end;
 saved:=public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read','94500000-0000-4000-8000-000000000001');
 perform pg_temp.check(saved->>'revision'='2' and saved->>'state'='draft' and saved->'payload'->>'notaFiscal'='newer','failed finalize rolls back draft snapshot and state');
 params:=params||jsonb_build_object('p_cliente_id','44500000-0000-4000-8000-000000000001','p_receiving_draft_revision',0);
 begin
  perform public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'));
  raise exception 'FAIL: stale final receiving accepted';
 exception when sqlstate 'PT409' then null;end;
 -- Recognize the one unacknowledged autosave (revision1->2) before finalizing.
 params:=params||jsonb_build_object('p_receiving_draft_revision',1,'p_receiving_draft_save_id','a4500000-0000-4000-8000-000000000002');
 first_result:=public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'));
 perform set_config('rm.test.final_params',params::text,true);
 perform pg_temp.check((public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000001','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'))->>'idempotent_replay')::boolean,'double click/retry reuses existing receipt');
 saved:=public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read','94500000-0000-4000-8000-000000000001');
 perform pg_temp.check(saved->>'state'='finalized' and saved->'result'->>'projeto_id'=first_result->>'projeto_id','finalization persisted with resulting project');
 perform pg_temp.check(public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read') is null,'finalized draft removed from active resume slot');
 begin
  perform public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'));
  raise exception 'FAIL: same draft finalized under another protocol';
 exception when invalid_parameter_value then null;end;
 begin
  perform public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'save','94500000-0000-4000-8000-000000000001',current_setting('rm.test.draft_payload')::jsonb,3,'a4500000-0000-4000-8000-000000000004');
  raise exception 'FAIL: finalized draft edited';
 exception when sqlstate 'PT409' then null;end;
end $$;
reset role;
select pg_temp.check((select count(*)=current_setting('rm.test.project_count')::integer+1 from public.rm_projetos),'exactly one project after retries');
select pg_temp.check((select count(*)=1 from rm_private.mobile_mutation_receipts where client_submission_id='94500000-0000-4000-8000-000000000001'),'exactly one final receipt');
set local role authenticated;
do $$declare params jsonb; result jsonb;begin
 -- Offline confirmation can arrive before the draft's first cloud autosave.
 params:=jsonb_build_object('p_receiving_draft_id','94500000-0000-4000-8000-000000000002','p_receiving_draft_revision',0,
  'p_receiving_draft_snapshot',current_setting('rm.test.draft_payload')::jsonb||'{"id":"94500000-0000-4000-8000-000000000002"}',
  'p_chegada_equipamento','2026-11-16T12:00:00Z');
 begin
  perform public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'));
  raise exception 'FAIL: invalid offline receiving accepted';
 exception when invalid_parameter_value then null;end;
 perform pg_temp.check(public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read','94500000-0000-4000-8000-000000000002') is null,'failed first offline confirmation creates no cloud draft');
 params:=params||'{"p_cliente_id":"44500000-0000-4000-8000-000000000001"}';
 result:=public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'));
 perform pg_temp.check(public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read','94500000-0000-4000-8000-000000000002')->>'state'='finalized','first offline confirmation atomically creates finalized snapshot');
 perform pg_temp.check((public.rm_mobile_mutate_v1('94500000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',params,current_setting('rm.test.draft_token'))->>'idempotent_replay')::boolean,'first offline confirmation replay');
end $$;
do $$declare token text;begin
 token:=public.rm_authenticate_operator_v1('DRAFTOTHER','fixture')->>'operator_token';
 perform pg_temp.check(public.rm_receiving_draft_v1(token,'read','94500000-0000-4000-8000-000000000001') is null,'another operator on same tablet cannot read draft');
 begin
  perform public.rm_receiving_draft_v1(token,'save','94500000-0000-4000-8000-000000000001',current_setting('rm.test.draft_payload')::jsonb,3,'a4500000-0000-4000-8000-000000000006');
  raise exception 'FAIL: another operator on same tablet changed draft';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','14500000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"14500000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare token text;begin
 token:=public.rm_authenticate_operator_v1('DRAFTOTHER','fixture')->>'operator_token';
 perform set_config('rm.test.other_token',token,true);
 perform pg_temp.check(public.rm_receiving_draft_v1(token,'read','94500000-0000-4000-8000-000000000001') is null,'another device account cannot read snapshot');
 begin
  perform public.rm_receiving_draft_v1(token,'save','94500000-0000-4000-8000-000000000001',current_setting('rm.test.draft_payload')::jsonb,3,'a4500000-0000-4000-8000-000000000005');
  raise exception 'FAIL: foreign actor changed draft';
 exception when insufficient_privilege then null;end;
 begin
  perform public.rm_receiving_draft_v1(current_setting('rm.test.draft_token'),'read');
  raise exception 'FAIL: foreign token accepted';
 exception when invalid_authorization_specification then null;end;
 begin
  perform count(*) from rm_private.receiving_drafts;
  raise exception 'FAIL: private table exposed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
update rm_private.operator_delegations set expires_at=clock_timestamp()-interval '1 second' where token_hash=extensions.digest(current_setting('rm.test.other_token'),'sha256');
set local role authenticated;
do $$begin
 begin
  perform public.rm_receiving_draft_v1(current_setting('rm.test.other_token'),'read');
  raise exception 'FAIL: expired token accepted';
 exception when invalid_authorization_specification then null;end;
end $$;
set local role anon;
do $$begin
 begin
  perform public.rm_receiving_draft_v1('forged','read');
  raise exception 'FAIL: anonymous draft access';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;

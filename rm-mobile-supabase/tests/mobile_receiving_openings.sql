\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required';end if;end$$;
create function pg_temp.opening_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
insert into auth.users(id) values('10520000-0000-4000-8000-000000000001'),('10520000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 ('20520000-0000-4000-8000-000000000001','10520000-0000-4000-8000-000000000001','Opening planner','administrador','ativo'),
 ('20520000-0000-4000-8000-000000000002','10520000-0000-4000-8000-000000000002','Other opening actor','administrador','ativo');
insert into public.rm_clientes(id,nome) values('40520000-0000-4000-8000-000000000001','Receiving client'),('40520000-0000-4000-8000-000000000002','Consolidated web client');
insert into public.rm_tipos_equipamento(id,nome) values('50520000-0000-4000-8000-000000000001','Receiving motor');
insert into public.rm_celulas(id,nome) values('60520000-0000-4000-8000-000000000001','Receiving route');
insert into public.rm_celula_tipos_equipamento(celula_id,tipo_equipamento_id,visibilidade) values('60520000-0000-4000-8000-000000000001','50520000-0000-4000-8000-000000000001',true);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values
 (extensions.digest('opening-token','sha256'),'10520000-0000-4000-8000-000000000001','20520000-0000-4000-8000-000000000001','20520000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
create function pg_temp.opening_params(sid uuid) returns jsonb language sql as $$select jsonb_build_object(
 'p_operador_id','20520000-0000-4000-8000-000000000001','p_cliente_id','40520000-0000-4000-8000-000000000001',
 'p_chegada_equipamento','2026-11-17T12:00:00Z','p_descricao_equipamento','Original mobile motor','p_equipamento',jsonb_build_object('descricao','Original mobile motor','placa_motor','c___placa'),
 'p_nota_fiscal','NF-original','p_arquivo_nota_fiscal_url','file:///local/invoice.pdf','p_eventualidades','Original event',
 'p_fotos_recebimento',jsonb_build_array(jsonb_build_object('foto_url','file:///local/front.jpg','tipo_recebimento','frente','titulo','Frontal','legenda','Original caption','numero',1,'categoria_foto','obrigat_ria')),
 'p_receiving_draft_id',sid,'p_receiving_draft_revision',0,'p_receiving_draft_save_id',null,
 'p_receiving_draft_snapshot',jsonb_build_object('id',sid,'version',2,'submitted',false,'cliente','40520000-0000-4000-8000-000000000001','chegada','2026-11-17T12:00:00Z','notaFiscal','NF-original','arquivoNotaFiscal','file:///local/invoice.pdf',
 'fotos',jsonb_build_array(jsonb_build_object('id','stable-photo-id','uri','file:///local/front.jpg','tipo','frente','comentario','Original caption'))));$$;
select set_config('request.jwt.claim.sub','10520000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
do $$declare sid uuid:='70520000-0000-4000-8000-000000000001';p jsonb;r jsonb;again jsonb;pid uuid;eid uuid;s jsonb;payload jsonb;allocation_ids uuid[];begin
 p:=pg_temp.opening_params(sid);
 r:=public.rm_mobile_open_receiving_v1(sid,p,'opening-token');pid:=(r->>'projeto_id')::uuid;eid:=(r->>'equipamento_id')::uuid;
 perform pg_temp.opening_check(r->>'receiving_id'=sid::text and r->>'opening_created'='true' and r->>'attachments_pending'='true' and r->>'idempotent_replay'='false' and (select count(*)=6 from jsonb_object_keys(r)),'exact early opening DTO');
 perform pg_temp.opening_check(exists(select 1 from public.rm_projetos where id=pid and numero is null and tipo_equipamento_id is null and nota_fiscal='NF-original'),'effective project exists without synthetic OS/type before media');
 perform pg_temp.opening_check(exists(select 1 from jsonb_array_elements(public.rm_web_receivings_v1('all','',1,100)->'items') x where x->>'id'=pid::text),'effective project visible in web receivings immediately');
 again:=public.rm_mobile_open_receiving_v1(sid,p,'opening-token');
 perform pg_temp.opening_check(again->>'projeto_id'=pid::text and again->>'idempotent_replay'='true','lost opening response same binding');
 begin perform public.rm_mobile_open_receiving_v1(sid,p||'{"p_nota_fiscal":"changed"}','opening-token');raise exception 'FAIL: altered frozen opening';exception when invalid_parameter_value then null;end;
 begin perform public.rm_mobile_open_receiving_v1(sid,p||'{"p_operador_id":"20520000-0000-4000-8000-000000000002"}','opening-token');raise exception 'FAIL: forged opening actor';exception when insufficient_privilege then null;end;
 -- Web classification/OS/customer/planning occurs while photos still live on the tablet.
 s:=public.rm_web_project_equipment_snapshot_v1(pid);
 payload:=jsonb_build_object('id',pid,'expected_updated_at',s->'project'->'updated_at','changes',jsonb_build_object('numero','WEB-OS-52','cliente_id','40520000-0000-4000-8000-000000000002'),
  'equipment',jsonb_build_object('id',eid,'expected_updated_at',s->'equipment'->'updated_at','expected_context_version',s->>'context_version','tipo_equipamento_id','50520000-0000-4000-8000-000000000001','changes',jsonb_build_object('descricao','Consolidated web motor')));
 perform public.rm_web_mutate_v1('80520000-0000-4000-8000-000000000001','save_project_with_equipment',payload);
 select array_agg(id order by id) into allocation_ids from public.rm_celulas_projeto where projeto_id=pid;
 -- Attachments convert URLs only; frozen metadata and IDs stay exact.
 p:=replace(p::text,'file:///local/','https://fixture.invalid/')::jsonb;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',p||'{"p_nota_fiscal":"changed"}','opening-token');raise exception 'FAIL: altered final metadata';exception when invalid_parameter_value then null;end;
 r:=public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',p,'opening-token');
 perform pg_temp.opening_check(r->>'projeto_id'=pid::text and r->>'fotos_criadas'='1','final appends media to same project');
 perform pg_temp.opening_check((select numero='WEB-OS-52' and cliente_id='40520000-0000-4000-8000-000000000002' and arquivo_nota_fiscal_url='https://fixture.invalid/invoice.pdf' from public.rm_projetos where id=pid)
  and (select tipo_equipamento_id='50520000-0000-4000-8000-000000000001' and descricao='Consolidated web motor' from public.rm_equipamentos where id=eid),'final preserves consolidated web metadata/type');
 perform pg_temp.opening_check(allocation_ids=(select array_agg(id order by id) from public.rm_celulas_projeto where projeto_id=pid),'final preserves copied route IDs and configuration');
 perform pg_temp.opening_check(public.rm_receiving_draft_v1('opening-token','read',sid)->>'state'='finalized','draft finalizes only after attachments');
 perform pg_temp.opening_check(public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',p,'opening-token')->>'idempotent_replay'='true','lost final ACK exact replay');
 r:=public.rm_mobile_open_receiving_v1(sid,pg_temp.opening_params(sid),'opening-token');
 perform pg_temp.opening_check(r->>'opening_created'='false' and r->>'attachments_pending'='false','opening retry reports fully finalized');
 perform set_config('rm.test.opening_project',pid::text,true);
end$$;
reset role;
select pg_temp.opening_check((select count(*)=1 from rm_private.mobile_mutation_receipts where client_submission_id='70520000-0000-4000-8000-000000000001'),'one final receipt');
select pg_temp.opening_check((select count(*)=1 from public.rm_fotos where projeto_id=current_setting('rm.test.opening_project')::uuid and foto_url='https://fixture.invalid/front.jpg'),'one receipt photo');
select pg_temp.opening_check((select count(*)=1 from public.rm_documentos where projeto_id=current_setting('rm.test.opening_project')::uuid),'invoice preserved as project document');
-- Future native clients cannot call helpers or inspect another operator's map.
set local role authenticated;
do $$begin begin perform * from rm_private.receiving_openings;raise exception 'FAIL: private openings readable';exception when insufficient_privilege then null;end;end$$;
do $$declare sid uuid:='70520000-0000-4000-8000-000000000002';p jsonb;pid uuid;eid uuid;s jsonb;r jsonb;begin
 -- A photo-only legacy receiving must remain classifiable before an actual route.
 p:=replace(pg_temp.opening_params(sid)::text,'file:///local/','https://fixture.invalid/')::jsonb;
 r:=public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',p,'opening-token');pid:=(r->>'projeto_id')::uuid;eid:=(r->>'equipamento_id')::uuid;
 s:=public.rm_web_project_equipment_snapshot_v1(pid);
 perform pg_temp.opening_check(s->>'has_project_route'='false' and s->>'can_change_type'='true','receiving photos are not operational route evidence');
 perform public.rm_web_mutate_v1('80520000-0000-4000-8000-000000000002','save_project_with_equipment',jsonb_build_object('id',pid,'expected_updated_at',s->'project'->'updated_at','changes','{}'::jsonb,
  'equipment',jsonb_build_object('id',eid,'expected_updated_at',s->'equipment'->'updated_at','expected_context_version',s->>'context_version','tipo_equipamento_id','50520000-0000-4000-8000-000000000001','changes','{}'::jsonb)));
 perform pg_temp.opening_check(exists(select 1 from public.rm_fotos where projeto_id=pid and foto_url='https://fixture.invalid/front.jpg') and (public.rm_web_project_equipment_snapshot_v1(pid)->>'can_change_type')='false','initial classification preserves intake photo and then protects actual route');
 r:=public.rm_mobile_open_receiving_v1(sid,pg_temp.opening_params(sid),'opening-token');perform pg_temp.opening_check(r->>'opening_created'='false' and r->>'attachments_pending'='false','legacy finalization forward-compatible with opening worker');
end$$;
do $$declare sid uuid:='70520000-0000-4000-8000-000000000003';p jsonb;pid uuid;s jsonb;r jsonb;begin
 p:=pg_temp.opening_params(sid);r:=public.rm_mobile_open_receiving_v1(sid,p,'opening-token');pid:=(r->>'projeto_id')::uuid;
 s:=public.rm_web_project_delete_snapshot_v1(pid);
 perform public.rm_web_mutate_v1('80520000-0000-4000-8000-000000000003','delete_project',jsonb_build_object('id',pid,'expected_updated_at',s->'project'->>'updated_at','expected_context_version',s->>'context_version','confirm_delete',true,'justificativa','Remove isolated pending opening'));
 begin perform public.rm_mobile_open_receiving_v1(sid,p,'opening-token');raise exception 'FAIL: deleted opening recreated';exception when sqlstate 'PT410' then null;end;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',replace(p::text,'file:///local/','https://fixture.invalid/')::jsonb,'opening-token');raise exception 'FAIL: deleted opening finalized as new';exception when sqlstate 'PT410' then null;end;
 perform pg_temp.opening_check(not exists(select 1 from public.rm_projetos where id=pid),'pending opening tombstone prevents recreation');
end$$;
reset role;
-- A newer invoice consolidated on the web remains canonical; the original
-- mobile attachment is still appended to documents and never disappears.
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.rm_mobile_open_receiving_v1('70520000-0000-4000-8000-000000000004',pg_temp.opening_params('70520000-0000-4000-8000-000000000004'),'opening-token');
 perform set_config('rm.test.invoice_project',r->>'projeto_id',true);
end$$;
reset role;
update public.rm_projetos set arquivo_nota_fiscal_url='https://fixture.invalid/consolidated-web-invoice.pdf' where id=current_setting('rm.test.invoice_project')::uuid;
set local role authenticated;
do $$declare p jsonb;sid uuid:='70520000-0000-4000-8000-000000000004';s jsonb;pid uuid:=current_setting('rm.test.invoice_project')::uuid;begin
 p:=replace(pg_temp.opening_params(sid)::text,'file:///local/','https://fixture.invalid/')::jsonb;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',jsonb_set(p,'{p_fotos_recebimento,0,titulo}','"Changed title"'),'opening-token');raise exception 'FAIL: changed photo title';exception when invalid_parameter_value then null;end;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',jsonb_set(p,'{p_receiving_draft_snapshot,fotos,0,id}','"changed-photo-id"'),'opening-token');raise exception 'FAIL: changed local photo identity';exception when invalid_parameter_value then null;end;
 perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',p,'opening-token');
 perform pg_temp.opening_check((select arquivo_nota_fiscal_url='https://fixture.invalid/consolidated-web-invoice.pdf' from public.rm_projetos where id=pid)
  and exists(select 1 from public.rm_documentos where projeto_id=pid and arquivo_url='https://fixture.invalid/invoice.pdf'),'new web invoice and original mobile invoice both preserved');
 s:=public.rm_web_project_delete_snapshot_v1(pid);
 perform public.rm_web_mutate_v1('80520000-0000-4000-8000-000000000004','delete_project',jsonb_build_object('id',pid,'expected_updated_at',s->'project'->>'updated_at','expected_context_version',s->>'context_version','confirm_delete',true,'justificativa','Delete finalized receiving fixture'));
 begin perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',p,'opening-token');raise exception 'FAIL: finalized deleted receiving replay';exception when sqlstate 'PT410' then null;end;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',jsonb_set(p,'{p_fotos_recebimento,0,foto_url}','"https://fixture.invalid/altered.jpg"'),'opening-token');raise exception 'FAIL: changed deleted receipt URL accepted';exception when invalid_parameter_value then null;end;
end$$;
do $$declare sid uuid:='70520000-0000-4000-8000-000000000005';p jsonb;d jsonb;r jsonb;begin
 p:=pg_temp.opening_params(sid);
 d:=public.rm_receiving_draft_v1('opening-token','save',sid,p->'p_receiving_draft_snapshot',0,'90520000-0000-4000-8000-000000000005');
 p:=p||'{"p_receiving_draft_save_id":"90520000-0000-4000-8000-000000000005"}';
 -- A lost autosave ACK is recognized without consuming another draft revision.
 r:=public.rm_mobile_open_receiving_v1(sid,p,'opening-token');
 perform pg_temp.opening_check(public.rm_receiving_draft_v1('opening-token','read',sid)->>'revision'='1','preopening does not increment cloud draft revision');
 begin perform public.rm_receiving_draft_v1('opening-token','save',sid,(p->'p_receiving_draft_snapshot')||'{"notaFiscal":"other device"}',1,'90520000-0000-4000-8000-000000000006');raise exception 'FAIL: opened frozen draft overwritten';exception when sqlstate 'PT409' then null;end;
 r:=public.rm_mobile_open_receiving_v1('70520000-0000-4000-8000-000000000006',pg_temp.opening_params('70520000-0000-4000-8000-000000000006'),'opening-token');
 perform pg_temp.opening_check(r->>'opening_created'='true','another already-submitted receiving opens while previous attachments pending');
 perform public.rm_mobile_mutate_v1(sid,'rm_submit_recebimento_v1',replace(p::text,'file:///local/','https://fixture.invalid/')::jsonb,'opening-token');
 perform pg_temp.opening_check(public.rm_receiving_draft_v1('opening-token','read',sid)->>'state'='finalized','frozen original revision still finalizes');
 begin perform public.rm_mobile_open_receiving_v1('70520000-0000-4000-8000-000000000007',pg_temp.opening_params('70520000-0000-4000-8000-000000000007')||'{"p_receiving_draft_revision":9}','opening-token');raise exception 'FAIL: stale nonexistent draft opens';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
set local role authenticated;
do $$declare aid uuid;sid uuid:='70520000-0000-4000-8000-000000000006';begin
 select id into aid from public.rm_celulas_projeto where projeto_id=current_setting('rm.test.opening_project')::uuid limit 1;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',aid,'p_status','em_dia'),'opening-token');raise exception 'FAIL: pending receiving UUID consumed by other legacy RPC';exception when invalid_parameter_value then null;end;
 begin perform public.rm_mobile_mutate_v1(sid,'rm_record_execution_event_v1',jsonb_build_object('p_session_id','a0520000-0000-4000-8000-000000000001','p_allocation_id',aid,'p_previous_event_id',null,'p_kind','start','p_occurred_at','2026-11-17T12:00:00Z','p_pause_reason',null,'p_note',null,'p_effort_minutes',null,'p_operador_id','20520000-0000-4000-8000-000000000001'),'opening-token');raise exception 'FAIL: pending receiving UUID consumed by execution RPC';exception when invalid_parameter_value then null;end;
end$$;
reset role;
select pg_temp.opening_check(not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id='70520000-0000-4000-8000-000000000006')
 and not exists(select 1 from rm_private.execution_events where id='70520000-0000-4000-8000-000000000006'),'reserved pending UUID produces no unrelated receipt or execution evidence');
update rm_private.operator_delegations set expires_at=clock_timestamp()-interval '1 second' where token_hash=extensions.digest('opening-token','sha256');
set local role authenticated;
do $$begin begin perform public.rm_mobile_open_receiving_v1('70520000-0000-4000-8000-000000000001',pg_temp.opening_params('70520000-0000-4000-8000-000000000001'),'opening-token');raise exception 'FAIL: expired opening replay';exception when sqlstate '28000' then null;end;end$$;
reset role;
rollback;
select 'PASS: early receiving visibility, exact protocols, media finalization, web edits, safe initial classification, legacy and deletion preserved' result;

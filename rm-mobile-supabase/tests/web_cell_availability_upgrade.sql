-- TEST DATABASE ONLY: 027 -> 028 preserves all69 old projections and warmed OIDs.
\set ON_ERROR_STOP on
\if :{?rm_migration_028_path}
\else
\echo 'Run the isolated SQL runner: absolute migration028 path is required.'
\quit 3
\endif
select set_config('rm.test.migration_028_path',:'rm_migration_028_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create schema rm_test_cell_upgrade;
create table rm_test_cell_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1e800000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values('2e800000-0000-4000-8000-000000000001','1e800000-0000-4000-8000-000000000001','Availability upgrade actor','administrador');
select set_config('request.jwt.claim.sub','1e800000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('availability-upgrade-mobile','sha256'),'1e800000-0000-4000-8000-000000000001','2e800000-0000-4000-8000-000000000001','2e800000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into public.rm_projetos(id,numero) values('5e800000-0000-4000-8000-000000000001','AVAILABILITY-UPGRADE-28-USED'),('5e800000-0000-4000-8000-000000000002','AVAILABILITY-UPGRADE-28-UNUSED');
insert into public.rm_celulas(id,nome) values('4e800000-0000-4000-8000-000000000001','Warm availability origin'),('4e800000-0000-4000-8000-000000000002','Warm availability destination');
insert into public.rm_forms(id,titulo) values('ae800000-0000-4000-8000-000000000001','Warm availability form');
insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) values('be800000-0000-4000-8000-000000000001','ae800000-0000-4000-8000-000000000001','Original offline question','texto_curto',true);
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids,visibilidade,posicao,indice) values
 ('6e800000-0000-4000-8000-000000000001','5e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000001',array['ae800000-0000-4000-8000-000000000001']::uuid[],true,17,9),
 ('6e800000-0000-4000-8000-000000000002','5e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000002','{}',false,11,10),
 ('6e800000-0000-4000-8000-000000000003','5e800000-0000-4000-8000-000000000002','4e800000-0000-4000-8000-000000000001','{}',false,23,1);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov)
 values('ce800000-0000-4000-8000-000000000001','5e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000002','em_dia',true);
-- Real legacy-shaped inconsistency is introduced BEFORE028. The new guard
-- must preserve its historical row/read-only consultation, while forbidding new ones.
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_projeto_id,status_cel_proj)
 values('ce800000-0000-4000-8000-000000000099','5e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000001','6e800000-0000-4000-8000-000000000002','pendente');
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo)
 values('de800000-0000-4000-8000-000000000001','5e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000001','6e800000-0000-4000-8000-000000000001','obrigat_ria','Warm preserved slot');
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo)
 values('de800000-0000-4000-8000-000000000099','5e800000-0000-4000-8000-000000000001','4e800000-0000-4000-8000-000000000001','6e800000-0000-4000-8000-000000000002','obrigat_ria','Legacy mismatched slot must remain preserved');
do $$ declare p jsonb; s jsonb; r jsonb; begin
 p:=jsonb_build_object('projeto_id','5e800000-0000-4000-8000-000000000002','celula_id','4e800000-0000-4000-8000-000000000001',
  'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id='6e800000-0000-4000-8000-000000000003'),'changes',jsonb_build_object('visibilidade',true));
 set local role authenticated; perform public.rm_web_mutate_v1('fe800000-0000-4000-8000-000000000001','plan_cell',p);
 perform public.rm_mobile_mutate_v1('fe800000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6e800000-0000-4000-8000-000000000001","p_status":"em_dia"}','availability-upgrade-mobile');
 perform public.rm_mobile_mutate_v1('fe800000-0000-4000-8000-000000000003','rm_add_cell_comment_v1','{"p_celula_projeto_id":"6e800000-0000-4000-8000-000000000001","p_comentario":"Preserve exact completed comment"}','availability-upgrade-mobile');
 perform public.rm_mobile_mutate_v1('fe800000-0000-4000-8000-000000000004','rm_record_cell_photo_v1','{"p_foto_id":"de800000-0000-4000-8000-000000000001","p_foto_url":"https://example.invalid/warm-slot.jpg"}','availability-upgrade-mobile');
 perform public.rm_mobile_mutate_v1('fe800000-0000-4000-8000-000000000005','rm_submit_form_inspection_v1','{"p_projeto_id":"5e800000-0000-4000-8000-000000000001","p_celula_id":"4e800000-0000-4000-8000-000000000001","p_form_id":"ae800000-0000-4000-8000-000000000001","p_respostas":[{"questao_id":"be800000-0000-4000-8000-000000000001","resposta":"Original complete response"}]}','availability-upgrade-mobile');
 reset role;
 p:=jsonb_build_object('aprovacao_etapa_id','ce800000-0000-4000-8000-000000000001','expected_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id='ce800000-0000-4000-8000-000000000001'),
  'expected_cell_updated_at',(select updated_at from public.rm_celulas_projeto where id='6e800000-0000-4000-8000-000000000001'),'acao','liberar','observacao',null);
 set local role authenticated; perform public.rm_web_mutate_v1('fe800000-0000-4000-8000-000000000006','transition_stage_approval',p); reset role;
 s:=public.rm_web_cell_queue_snapshot_v1('4e800000-0000-4000-8000-000000000001');
 p:=jsonb_build_object('celula_id','4e800000-0000-4000-8000-000000000001','expected_queue_version',s->>'queue_version','apply_order',false,
  'items',(select jsonb_agg(jsonb_build_object('id',x->>'id','expected_updated_at',x->>'updated_at','prioridade',x->'prioridade') order by n) from jsonb_array_elements(s->'items') with ordinality a(x,n)));
 set local role authenticated; perform public.rm_web_mutate_v1('fe800000-0000-4000-8000-000000000007','save_cell_queue',p); reset role;
 perform public.rm_web_project_route_snapshot_v1('5e800000-0000-4000-8000-000000000002');
 perform public.rm_web_planning_load_v1(); perform public.rm_web_receivings_v1();
end $$;
do $$ declare t record; n bigint; h text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname) into n,h;
  insert into rm_test_cell_upgrade.snapshots values(t.nspname||'.'||t.relname,n,h);
 end loop;
 if (select count(*) from rm_test_cell_upgrade.snapshots)<>69 then raise exception 'FAIL: expected all69 pre028 tables'; end if;
end $$;
-- Exercise the exact source in the SAME local transaction as the committed-
-- shaped legacy fixture, removing only its outer transaction delimiters. This
-- keeps warmed caller plans and allows an honest ROLLBACK of every fixture and
-- DDL change; no trigger or product guard is ever disabled for cleanup.
do $install_test$ declare source text; begin
 source:=pg_read_file(current_setting('rm.test.migration_028_path'));
 if (select count(*) from regexp_matches(source,'(?m)^begin;\r?$','g'))<>1
  or (select count(*) from regexp_matches(source,'(?m)^commit;\r?$','g'))<>1
  or source !~ E'\ncommit;\r?\n?$' then raise exception 'FAIL: unexpected migration transaction envelope'; end if;
 source:=regexp_replace(source,'(?m)^begin;\r?\n','','g');
 source:=regexp_replace(source,'(?m)^commit;\r?\n?$','','g');
 execute source;
end $install_test$;
do $$ declare t record; n bigint; h text; expression text; p jsonb; r jsonb; s jsonb; receipt record; before_alloc jsonb; begin
 for t in select * from rm_test_cell_upgrade.snapshots loop
  expression:=case when t.name='public.rm_celulas_projeto' then 'to_jsonb(t)-''retirada''' else 'to_jsonb(t)' end;
  execute format('select count(*),md5(coalesce(jsonb_agg(%s order by (%s)::text)::text,''[]'')) from %s t',expression,expression,t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL:028 changed old data projection %',t.name; end if;
 end loop;
 if exists(select 1 from rm_private.cell_availability_events) or exists(select 1 from public.rm_celulas_projeto where retirada) then raise exception 'FAIL:028 invented lifecycle data'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='rm_celulas_projeto' and column_name='retirada' and is_nullable='NO') then raise exception 'FAIL: missing additive lifecycle default'; end if;
 set local role authenticated; s:=public.rm_web_stage_approval_snapshot_v1('ce800000-0000-4000-8000-000000000099'); reset role;
 if s->'available_actions'<>'[]'::jsonb or not exists(select 1 from public.rm_aprovacoes_etapas where id='ce800000-0000-4000-8000-000000000099'
  and celula_projeto_id='6e800000-0000-4000-8000-000000000002') then raise exception 'FAIL: preserved legacy mismatched linkage was rewritten or offered a decision'; end if;
 p:=jsonb_build_object('aprovacao_etapa_id','ce800000-0000-4000-8000-000000000099','expected_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id='ce800000-0000-4000-8000-000000000099'),
  'expected_cell_updated_at',(select updated_at from public.rm_celulas_projeto where id='6e800000-0000-4000-8000-000000000001'),'acao','liberar','observacao',null);
 begin set local role authenticated; perform public.rm_web_mutate_v1(gen_random_uuid(),'transition_stage_approval',p); reset role;
  raise exception 'FAIL: old inconsistent allocation allowed decision'; exception when invalid_parameter_value then reset role; end;
 set local role authenticated; s:=public.rm_web_operational_photos_snapshot_v1('5e800000-0000-4000-8000-000000000001','6e800000-0000-4000-8000-000000000001',true); reset role;
 if exists(select 1 from jsonb_array_elements(s->'photos') x where x->>'id'='de800000-0000-4000-8000-000000000099')
  or not exists(select 1 from public.rm_fotos where id='de800000-0000-4000-8000-000000000099' and celula_projeto_id='6e800000-0000-4000-8000-000000000002') then
  raise exception 'FAIL: legacy mismatched photo leaked into current scope or was rewritten'; end if;
 for receipt in select * from rm_private.mobile_mutation_receipts where auth_user_id='1e800000-0000-4000-8000-000000000001' loop
  set local role authenticated; r:=public.rm_mobile_mutate_v1(receipt.client_submission_id,receipt.rpc_name,receipt.params,'availability-upgrade-mobile'); reset role;
  if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old mobile receipt %',receipt.rpc_name; end if;
 end loop;
 for receipt in select * from rm_private.web_mutation_receipts where auth_user_id='1e800000-0000-4000-8000-000000000001' loop
  set local role authenticated; r:=public.rm_web_mutate_v1(receipt.client_submission_id,receipt.operation,receipt.payload); reset role;
  if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed old web receipt %',receipt.operation; end if;
 end loop;
 select to_jsonb(a) into before_alloc from public.rm_celulas_projeto a where id='6e800000-0000-4000-8000-000000000003';
 s:=public.rm_web_cell_availability_snapshot_v1('5e800000-0000-4000-8000-000000000002','6e800000-0000-4000-8000-000000000003');
 p:=jsonb_build_object('action','retire','projeto_id','5e800000-0000-4000-8000-000000000002','celula_projeto_id','6e800000-0000-4000-8000-000000000003',
  'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
 set local role authenticated; r:=public.rm_web_mutate_v1('fe800000-0000-4000-8000-000000000008','manage_cell_availability',p); reset role;
 if not(r->'record'->>'retirada')::boolean then raise exception 'FAIL: warmed wrapper missed retirement'; end if;
 set local role authenticated; r:=public.rm_web_mutate_v1('fe800000-0000-4000-8000-000000000008','manage_cell_availability',p); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL:028 new receipt replay'; end if;
 s:=public.rm_web_cell_availability_snapshot_v1('5e800000-0000-4000-8000-000000000002','6e800000-0000-4000-8000-000000000003');
 p:=p||jsonb_build_object('action','restore','expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version');
 set local role authenticated; r:=public.rm_web_mutate_v1('fe800000-0000-4000-8000-000000000009','manage_cell_availability',p); reset role;
 if (r->'record'->>'retirada')::boolean or (r->'record'->>'visibilidade')::boolean then raise exception 'FAIL: restore did not keep original hidden identity'; end if;
 if (select posicao<>23 or indice<>1 from public.rm_celulas_projeto where id='6e800000-0000-4000-8000-000000000003') then raise exception 'FAIL: restore renormalized order'; end if;
end $$;
rollback;
-- Install cleanly for the remaining suites, using the unmodified file with its
-- original transaction boundaries. All adversarial legacy fixtures are gone.
\ir ../migrations/028_rm_web_cell_availability.sql
select 'PASS:028 preserves69 old projections with additive false default, empty journal, warmed web/mobile receipts and unchanged restored allocation identity/order' as result;

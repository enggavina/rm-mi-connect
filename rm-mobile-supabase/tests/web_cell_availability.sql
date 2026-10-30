-- TEST DATABASE ONLY: retirement is reversible identity preservation, never DELETE.
\set ON_ERROR_STOP on
begin;
create function pg_temp.ca_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.ca_key(h text,n int) returns uuid language sql immutable as $$
 select (h||'e600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function pg_temp.ca_actor(n int,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',pg_temp.ca_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.ca_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.ca.actor',n::text,true); end $$;
create function pg_temp.ca_payload(action text,n int default 1,visible boolean default false) returns jsonb language sql as $$
 with s as(select public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',n),pg_temp.ca_key('6',n*10+1)) r)
 select jsonb_build_object('action',action,'projeto_id',pg_temp.ca_key('5',n),'celula_projeto_id',pg_temp.ca_key('6',n*10+1),
  'expected_project_updated_at',r->'project'->>'updated_at','expected_allocation_updated_at',r->'allocation'->>'updated_at',
  'expected_context_version',r->>'context_version','confirm_change',true)||
  case when action='set_visibility' then jsonb_build_object('visibilidade',visible) else '{}'::jsonb end from s; $$;
create function pg_temp.ca_call(rid uuid,p jsonb,cap text default 'em.planning.manage',op text default 'manage_cell_availability') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.ca.actor'),64,'e6'),rid,op,p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role; return r;
 exception when others then reset role; raise; end $$;
create function pg_temp.ca_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$ declare actual text; begin
 begin perform pg_temp.ca_call(gen_random_uuid(),p,cap); exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm; end;
 raise exception 'FAIL: availability unexpectedly succeeded'; end $$;
create function pg_temp.ca_mobile(rid uuid,rpc text,p jsonb) returns jsonb language plpgsql as $$ declare r jsonb; begin
 set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,rpc,p,'cell-availability-mobile-fixture'); reset role; return r;
 exception when others then reset role; raise; end $$;
create function pg_temp.ca_mobile_reject(rpc text,p jsonb,wanted text default 'PT409') returns void language plpgsql as $$ declare actual text; begin
 begin perform pg_temp.ca_mobile(gen_random_uuid(),rpc,p); exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: old mobile expected %, got %: %',wanted,actual,sqlerrm; end;
 raise exception 'FAIL: old offline mutation reached retired allocation'; end $$;

do $$ declare n int; begin for n in 1..4 loop
 insert into auth.users(id) values(pg_temp.ca_key('1',n));
 insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.ca_key('2',n),pg_temp.ca_key('1',n),'Availability actor '||n,
  case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
  case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
 insert into auth.sessions(id,user_id) values(pg_temp.ca_key('3',n),pg_temp.ca_key('1',n));
 if n<>4 then
  insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.ca_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.ca_key('9',n),pg_temp.ca_key('2',n),pg_temp.ca_key('1',n),true,pg_temp.ca_key('2',1),clock_timestamp());
  perform public.rm_sso_session_put_v1(lpad(n::text,64,'e6'),pg_temp.ca_key('8',n),pg_temp.ca_key('3',n),'opaque-cell-availability-fixture-'||n,clock_timestamp()+interval '45 minutes');
 end if; end loop; end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero,status_pcp) select pg_temp.ca_key('5',n),'CELL-AVAILABILITY-28-'||n,
 case when n=22 then 'cancelado'::public.rm_status_pcp_enum end from generate_series(1,32) n;
insert into public.rm_celulas(id,nome) select pg_temp.ca_key('4',n*10+k),'Availability cell '||n||'-'||k from generate_series(1,32) n cross join generate_series(1,2) k;
insert into public.rm_forms(id,titulo) select pg_temp.ca_key('a',n),'Availability form '||n from generate_series(1,32) n;
insert into public.rm_forms(id,titulo) values(pg_temp.ca_key('a',99),'Unlinked historical form');
insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) select pg_temp.ca_key('b',n),pg_temp.ca_key('a',n),'Preserved question '||n,'texto_curto',true from generate_series(1,32) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,status_historico,visibilidade,forms_ids,indice,posicao,prioridade,observacao)
 select pg_temp.ca_key('6',n*10+k),pg_temp.ca_key('5',n),pg_temp.ca_key('4',n*10+k),'pendente',array['pendente']::public.rm_status_cel_proj_enum[],k=1,
 case when k=1 then array[pg_temp.ca_key('a',n)] else '{}'::uuid[] end,9+k,17+k,'alta','Preserve allocation configuration'
 from generate_series(1,32) n cross join generate_series(1,2) k;
insert into public.rm_tablet_celula_users(celula_id,identidade_id) select pg_temp.ca_key('4',n*10+k),pg_temp.ca_key('2',1) from generate_series(1,32) n cross join generate_series(1,2) k;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('cell-availability-mobile-fixture','sha256'),pg_temp.ca_key('1',1),pg_temp.ca_key('2',1),pg_temp.ca_key('2',1),clock_timestamp()+interval '1 day');

-- Pure configuration is retained: a blank slot, a pre-record designation and an
-- unused stage already retired through the separate stage lifecycle.
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,tag,numero)
 values(pg_temp.ca_key('d',1),pg_temp.ca_key('5',1),pg_temp.ca_key('4',11),pg_temp.ca_key('6',11),'obrigat_ria','Blank preserved slot','ORIGINAL-TAG',7);
insert into public.rm_form_reviewer_assignments(id,projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id)
 values(pg_temp.ca_key('e',1),pg_temp.ca_key('5',1),pg_temp.ca_key('4',11),pg_temp.ca_key('6',11),pg_temp.ca_key('a',1),pg_temp.ca_key('2',1));
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,ativo)
 values(pg_temp.ca_key('c',1),pg_temp.ca_key('5',1),pg_temp.ca_key('6',11),pg_temp.ca_key('4',11),pg_temp.ca_key('4',12),'finalizado',false);
update public.rm_celulas_projeto set status='em_dia' where id=pg_temp.ca_key('6',21);
update public.rm_celulas_projeto set status='n_a' where id=pg_temp.ca_key('6',31);
update public.rm_celulas_projeto set status='finalizado' where id=pg_temp.ca_key('6',41);
update public.rm_celulas_projeto set status_historico=array['pendente','em_dia']::public.rm_status_cel_proj_enum[] where id=pg_temp.ca_key('6',51);
update public.rm_celulas_projeto set horas_realizadas=0.25 where id=pg_temp.ca_key('6',61);
update public.rm_celulas_projeto set data_fim_real=clock_timestamp() where id=pg_temp.ca_key('6',71);
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,preenchido)
 values(pg_temp.ca_key('f',8),pg_temp.ca_key('5',8),pg_temp.ca_key('4',81),pg_temp.ca_key('a',99),false);
insert into public.rm_fotos(projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,foto_url,fotos_arquivos_urls,selecao_relatorio,lixeira)
 select pg_temp.ca_key('5',n),pg_temp.ca_key('4',n*10+1),case when n=9 then null else pg_temp.ca_key('6',n*10+1) end,'obrigat_ria','Preserve captured or selected',
 case when n=9 then 'https://example.invalid/preserved.jpg' end,case when n=10 then array['https://example.invalid/list-preserved.jpg'] else '{}'::text[] end,n=11,true from generate_series(9,11) n;
insert into public.rm_comentarios(projeto_id,celula_id,evento) values(pg_temp.ca_key('5',12),pg_temp.ca_key('4',121),'Preserve operator comment');
insert into public.rm_logs_aprovacao(projeto_id,celula_id,status_aprovacao) values(pg_temp.ca_key('5',13),pg_temp.ca_key('4',131),'aprovado');
insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,ativo,status)
 select pg_temp.ca_key('5',n),pg_temp.ca_key('4',n*10+case when n=15 then 2 else 1 end),pg_temp.ca_key('4',n*10+case when n=15 then 1 else 2 end),'finalizado',n<>16,
 case when n=16 then 'aprovado'::public.rm_status_etapa_enum else 'nulo' end from generate_series(14,16) n;
insert into public.rm_respostas_temp(projeto_id,form_id,questao_id,operador_user_id,resposta)
 values(pg_temp.ca_key('5',17),pg_temp.ca_key('a',17),pg_temp.ca_key('b',17),pg_temp.ca_key('2',1),'Preserve server draft');
update public.rm_celulas_projeto set forms_ids=array[pg_temp.ca_key('a',17)] where id=pg_temp.ca_key('6',172);
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.ca_key('9',18),'Materialization must skip existing identity');
update public.rm_projetos set tipo_equipamento_id=pg_temp.ca_key('9',18) where id=pg_temp.ca_key('5',18);
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id,visibilidade) values(pg_temp.ca_key('e',181),pg_temp.ca_key('4',181),pg_temp.ca_key('9',18),true);
insert into public.rm_fotos(id,celula_id,celula_tipo_equipamento_id,categoria_foto,titulo) values(pg_temp.ca_key('d',18),pg_temp.ca_key('4',181),pg_temp.ca_key('e',181),'obrigat_ria','Template must not reclone withdrawn work');
insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result)
 values(pg_temp.ca_key('f',19),pg_temp.ca_key('1',1),pg_temp.ca_key('2',1),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',upper(pg_temp.ca_key('6',191)::text),'p_status','em_dia'),jsonb_build_object('celula_projeto_id',pg_temp.ca_key('6',191)));
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,ativo)
 values(pg_temp.ca_key('c',20),pg_temp.ca_key('5',20),pg_temp.ca_key('4',201),pg_temp.ca_key('4',202),'finalizado',false);
insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result)
 values(pg_temp.ca_key('f',20),pg_temp.ca_key('1',1),pg_temp.ca_key('2',1),'transition_stage_approval',jsonb_build_object('aprovacao_etapa_id',pg_temp.ca_key('c',20),'acao','liberar'),
  jsonb_build_object('id',pg_temp.ca_key('c',20),'projeto_id',pg_temp.ca_key('5',20),'snapshot',jsonb_build_object('allocation',jsonb_build_object('id',pg_temp.ca_key('6',201)))));
insert into public.rm_sync_outbox(target_system,entity_type,operation,record_id,payload)
 values('bubble_data_api','Celula_Projeto_Status','update',pg_temp.ca_key('6',211),jsonb_build_object('projeto_id',pg_temp.ca_key('5',21),'celula_projeto_id',pg_temp.ca_key('6',211),'status','em_dia'));
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo)
 values(pg_temp.ca_key('d',23),pg_temp.ca_key('5',23),pg_temp.ca_key('4',231),pg_temp.ca_key('6',231),'obrigat_ria','Only the prior photo synchronization event survives');
insert into public.rm_sync_outbox(target_system,entity_type,operation,record_id,payload)
 values('bubble_data_api','Fotos_RM_Sync','update',pg_temp.ca_key('d',23),jsonb_build_object('foto_id',pg_temp.ca_key('d',23)));
select pg_temp.ca_actor(1);

set local role authenticated;
do $$ declare s jsonb:=public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',1),pg_temp.ca_key('6',11)); begin
 perform pg_temp.ca_check((s->>'can_retire')::boolean and (s->>'can_set_visibility')::boolean and (s->>'in_queue')::boolean,'unused pending allocation may be managed despite retained pure configuration');
 perform pg_temp.ca_check(s::text !~ '"(email|auth_user_id|token|payload|bubble_id|sync_source|foto_url|resposta|actor_id|client_submission_id)"','coarse DTO never exposes protected evidence');
 perform pg_temp.ca_check(public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',2),pg_temp.ca_key('6',11)) is null,'cross-project allocation is not exposed');
end $$;
reset role;

do $$ begin
 begin update public.rm_celulas_projeto set id=gen_random_uuid() where id=pg_temp.ca_key('6',251); raise exception 'FAIL: allocation identity rewritten'; exception when invalid_parameter_value then null; end;
 begin update public.rm_celulas_projeto set celula_id=pg_temp.ca_key('4',252) where id=pg_temp.ca_key('6',251); raise exception 'FAIL: immutable natural context rewritten'; exception when invalid_parameter_value then null; end;
 begin delete from public.rm_celulas_projeto where id=pg_temp.ca_key('6',251); raise exception 'FAIL: hard-delete bypass'; exception when invalid_parameter_value then null; end;
 begin update public.rm_celulas_projeto set retirada=true,visibilidade=false where id=pg_temp.ca_key('6',251); raise exception 'FAIL: direct lifecycle bypass'; exception when insufficient_privilege then null; end;
end $$;

do $$ declare p jsonb:=pg_temp.ca_payload('retire'); n int; begin
 perform pg_temp.ca_reject(p,'22023','em.approvals.decide');
 perform pg_temp.ca_reject(p||'{"actor_id":"2e600000-0000-4000-8000-000000000001"}','22023');
 perform pg_temp.ca_reject(p-'confirm_change','22023'); perform pg_temp.ca_reject(p||'{"confirm_change":"true"}','22023');
 perform pg_temp.ca_reject(p||'{"visibilidade":false}','22023');
 perform pg_temp.ca_reject(p||'{"expected_context_version":"bad"}','22023');
 perform pg_temp.ca_reject(p||'{"expected_allocation_updated_at":"infinity"}','22023');
 for n in 2..17 loop perform pg_temp.ca_reject(pg_temp.ca_payload('retire',n),'PT409'); end loop;
 for n in 19..21 loop perform pg_temp.ca_reject(pg_temp.ca_payload('retire',n),'PT409'); end loop;
 perform pg_temp.ca_reject(pg_temp.ca_payload('retire',23),'PT409');
 perform pg_temp.ca_reject(pg_temp.ca_payload('retire',22),'22023');
 perform pg_temp.ca_check(not(public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',17),pg_temp.ca_key('6',172))->>'can_retire')::boolean,'ambiguous server draft protects every compatible cell');
 perform pg_temp.ca_check((public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',4),pg_temp.ca_key('6',41))->>'can_set_visibility')::boolean,'finalized work can remain visible for existing approvals');
 perform pg_temp.ca_check(not(public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',3),pg_temp.ca_key('6',31))->>'can_set_visibility')::boolean,'N/A origin is not operationally reactivated');
end $$;

-- Owner-only events construct adversarial legacy/technical states in this
-- disposable DB. All triggers remain enabled when any product RPC is called.
create function pg_temp.ca_force_retired(n int,k int default 1) returns void language plpgsql as $$ begin
 if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if;
 insert into rm_private.cell_availability_events(projeto_id,celula_projeto_id,actor_id,action,old_visibility,new_visibility,old_retired,new_retired,allocation_version,client_submission_id)
  select projeto_id,id,pg_temp.ca_key('2',1),'retire',visibilidade,false,retirada,true,updated_at,gen_random_uuid() from public.rm_celulas_projeto where id=pg_temp.ca_key('6',n*10+k);
 update public.rm_celulas_projeto set retirada=true,visibilidade=false where id=pg_temp.ca_key('6',n*10+k);
end $$;
create temporary table ca_receipt_cases(mode text,rid uuid primary key,op text,payload jsonb) on commit drop;
do $$ declare n int; p jsonb; rid uuid; r jsonb; rpc_name text; record_id uuid; stage_id uuid:=pg_temp.ca_key('c',26); item record; before_rows jsonb; after_rows jsonb; before_receipts bigint; begin
 -- Real completed operations, not fabricated success envelopes, prove that
 -- replay remains possible after a later technical retirement.
 for n in 1..4 loop
  rid:=gen_random_uuid();
  if n=1 then p:=jsonb_build_object('p_celula_projeto_id',pg_temp.ca_key('6',261),'p_comentario','Completed comment before retirement');
  elsif n=2 then p:=jsonb_build_object('p_celula_projeto_id',pg_temp.ca_key('6',261),'p_status','em_dia');
  elsif n=3 then p:=jsonb_build_object('p_projeto_id',pg_temp.ca_key('5',26),'p_celula_id',pg_temp.ca_key('4',261),'p_form_id',pg_temp.ca_key('a',26),
   'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.ca_key('b',26),'resposta','Completed original inspection')));
  else p:=jsonb_build_object('p_projeto_id',pg_temp.ca_key('5',26),'p_celula_id',pg_temp.ca_key('4',261),'p_foto_url','https://example.invalid/completed-complementary.jpg','p_titulo','Completed complementary','p_categoria_foto','complementar'); end if;
  rpc_name:=case n when 1 then 'rm_add_cell_comment_v1' when 2 then 'rm_update_cell_status_v1' when 3 then 'rm_submit_form_inspection_v1' else 'rm_record_cell_photo_v1' end;
  insert into ca_receipt_cases values('mobile',rid,rpc_name,p);
  r:=pg_temp.ca_mobile(rid,rpc_name,p);
  if n=3 then record_id:=(r->>'registro_formulario_id')::uuid; end if;
 end loop;
 if record_id is null then select id into record_id from public.rm_registros_formulario where projeto_id=pg_temp.ca_key('5',26); end if;
 update public.rm_registros_formulario set status='direcionado' where id=record_id;
 update public.rm_respostas set revisar=true where registro_formulario_id=record_id;
 p:=jsonb_build_object('p_registro_formulario_id',record_id,'p_respostas_corrigidas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.ca_key('b',26),'resposta','Completed correction before retirement')));
 rid:=gen_random_uuid(); perform pg_temp.ca_mobile(rid,'rm_submit_form_revision_v1',p); insert into ca_receipt_cases values('mobile',rid,'rm_submit_form_revision_v1',p);
 insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov)
  values(stage_id,pg_temp.ca_key('5',26),pg_temp.ca_key('4',261),pg_temp.ca_key('4',262),'em_dia',true);
 p:=jsonb_build_object('aprovacao_etapa_id',stage_id,'expected_updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=stage_id),
  'expected_cell_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.ca_key('6',261)),'acao','liberar','observacao',null);
 rid:=gen_random_uuid(); perform pg_temp.ca_call(rid,p,'em.approvals.decide','transition_stage_approval'); insert into ca_receipt_cases values('web',rid,'transition_stage_approval',p);
 update public.rm_registros_formulario set status='direcionado' where id=record_id;
 update public.rm_respostas set revisar=true where registro_formulario_id=record_id;
 perform pg_temp.ca_force_retired(26);
 select jsonb_build_object('allocations',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_celulas_projeto x where projeto_id=pg_temp.ca_key('5',26)),
  'records',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_registros_formulario x where projeto_id=pg_temp.ca_key('5',26)),
  'photos',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_fotos x where projeto_id=pg_temp.ca_key('5',26)),
  'journal',(select count(*) from rm_private.cell_availability_events),'stage_journal',(select count(*) from rm_private.stage_rule_events),'outbox',(select count(*) from public.rm_sync_outbox)) into before_rows;
 for item in select * from ca_receipt_cases loop
  if item.mode='mobile' then r:=pg_temp.ca_mobile(item.rid,item.op,item.payload); else r:=pg_temp.ca_call(item.rid,item.payload,'em.approvals.decide',item.op); end if;
  perform pg_temp.ca_check((r->>'idempotent_replay')::boolean,'every completed receipt replays before retired/closed state validation');
 end loop;
 select jsonb_build_object('allocations',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_celulas_projeto x where projeto_id=pg_temp.ca_key('5',26)),
  'records',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_registros_formulario x where projeto_id=pg_temp.ca_key('5',26)),
  'photos',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_fotos x where projeto_id=pg_temp.ca_key('5',26)),
  'journal',(select count(*) from rm_private.cell_availability_events),'stage_journal',(select count(*) from rm_private.stage_rule_events),'outbox',(select count(*) from public.rm_sync_outbox)) into after_rows;
 perform pg_temp.ca_check(after_rows=before_rows,'completed replay changes no business state, logs, lifecycle or outbound effects');
 perform pg_temp.ca_mobile_reject('rm_submit_form_revision_v1',p:=jsonb_build_object('p_registro_formulario_id',record_id,'p_respostas_corrigidas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.ca_key('b',26),'resposta','New delayed correction'))));
end $$;

do $$ declare n int; p jsonb; old_state jsonb; begin
 for n in 27..29 loop
  update public.rm_celulas_projeto set status=case when n=29 then 'retornado'::public.rm_status_cel_proj_enum else 'em_dia' end where id=pg_temp.ca_key('6',n*10+1);
  insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj)
   values(pg_temp.ca_key('c',n),pg_temp.ca_key('5',n),pg_temp.ca_key('4',n*10+1),pg_temp.ca_key('4',n*10+2),case when n=29 then 'retornado'::public.rm_status_cel_proj_enum else 'em_dia' end);
  perform pg_temp.ca_force_retired(n,case when n=27 then 1 else 2 end);
  select jsonb_agg(to_jsonb(x) order by id) into old_state from public.rm_celulas_projeto x where projeto_id=pg_temp.ca_key('5',n);
  p:=jsonb_build_object('p_aprovacao_etapa_id',pg_temp.ca_key('c',n),'p_acao',case when n=29 then 'retornar' else 'liberar' end,'p_observacao','Preserve pending operational decision');
  perform pg_temp.ca_mobile_reject('rm_transition_stage_approval_v1',p);
  perform pg_temp.ca_check((select jsonb_agg(to_jsonb(x) order by id)=old_state from public.rm_celulas_projeto x where projeto_id=pg_temp.ca_key('5',n))
   and not exists(select 1 from public.rm_logs_aprovacao where projeto_id=pg_temp.ca_key('5',n)),'origin/destination/return failure is atomic and never restores hidden withdrawn work');
 end loop;
end $$;

do $$ declare p jsonb; rid uuid:=gen_random_uuid(); r jsonb; old_row jsonb; unchanged jsonb; child_state jsonb; journals bigint; q jsonb; route jsonb; before_outbox bigint; begin
 select to_jsonb(a) into old_row from public.rm_celulas_projeto a where id=pg_temp.ca_key('6',11);
 select jsonb_build_object('photos',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_fotos x where projeto_id=pg_temp.ca_key('5',1)),
  'stages',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_aprovacoes_etapas x where projeto_id=pg_temp.ca_key('5',1)),
  'reviewers',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_form_reviewer_assignments x where projeto_id=pg_temp.ca_key('5',1))) into child_state;
 select count(*) into before_outbox from public.rm_sync_outbox;
 p:=pg_temp.ca_payload('set_visibility',1,false); r:=pg_temp.ca_call(gen_random_uuid(),p);
 perform pg_temp.ca_check(r->'record'->>'visibilidade'='false' and not(r->'record'->>'retirada')::boolean,'hide changes presentation, not lifecycle');
 select to_jsonb(a) into unchanged from public.rm_celulas_projeto a where id=pg_temp.ca_key('6',11);
 perform pg_temp.ca_check(unchanged-array['visibilidade','updated_at','replanejada_em','replanejada_por_id','modified_by_id','sync_source']=old_row-array['visibilidade','updated_at','replanejada_em','replanejada_por_id','modified_by_id','sync_source'],'visibility preserves positions, priorities, route and all execution/configuration data');
 set local role authenticated; q:=public.rm_web_cell_queue_snapshot_v1(pg_temp.ca_key('4',11)); reset role;
 perform pg_temp.ca_check((q->>'total')::int=1 and not(q->'items'->0->>'visibilidade')::boolean,'hidden open work remains in the complete 021 queue');
 p:=pg_temp.ca_payload('set_visibility',1,false); select count(*) into journals from rm_private.cell_availability_events;
 r:=pg_temp.ca_call(gen_random_uuid(),p);
 perform pg_temp.ca_check(r->'record'->'changed_ids'='[]' and (select to_jsonb(a)=unchanged from public.rm_celulas_projeto a where id=pg_temp.ca_key('6',11))
  and (select count(*)=journals from rm_private.cell_availability_events),'unchanged visibility is a timestamp/journal no-op');
 p:=pg_temp.ca_payload('set_visibility',1,true); perform pg_temp.ca_call(gen_random_uuid(),p);
 p:=pg_temp.ca_payload('retire'); r:=pg_temp.ca_call(rid,p);
 perform pg_temp.ca_check(r->>'id'=pg_temp.ca_key('6',11)::text and (r->'record'->>'retirada')::boolean and not(r->'record'->>'visibilidade')::boolean
  and r->'record'->'changed_ids'=jsonb_build_array(pg_temp.ca_key('6',11)),'retirement preserves identity and emits the single changed allocation');
 set local role authenticated;
 q:=public.rm_web_cell_queue_snapshot_v1(pg_temp.ca_key('4',11)); route:=public.rm_web_project_route_snapshot_v1(pg_temp.ca_key('5',1));
 perform pg_temp.ca_check(exists(select 1 from public.rm_celulas_projeto where id=pg_temp.ca_key('6',11) and retirada and not visibilidade),'RLS/pull retains the hidden retirement tombstone'); reset role;
 perform pg_temp.ca_check((q->>'total')::int=0,'retired work leaves the operational queue');
 perform pg_temp.ca_check((route->>'total')::int=1 and not exists(select 1 from jsonb_array_elements(route->'items') x where x->>'id'=pg_temp.ca_key('6',11)::text),
  'active route excludes withdrawn work without rewriting its preserved historical index');
 set local role authenticated;
 perform pg_temp.ca_check((select (x->>'open_allocations')::int=0 from jsonb_array_elements(public.rm_web_planning_load_v1()->'cells') x where x->>'id'=pg_temp.ca_key('4',11)::text),
  'withdrawn work leaves planning load without being confused with hidden active work'); reset role;
 perform pg_temp.ca_check((select count(*)=before_outbox from public.rm_sync_outbox),'availability does not create outbound business effects');
 perform pg_temp.ca_check((select jsonb_build_object('photos',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_fotos x where projeto_id=pg_temp.ca_key('5',1)),
  'stages',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_aprovacoes_etapas x where projeto_id=pg_temp.ca_key('5',1)),
  'reviewers',(select jsonb_agg(to_jsonb(x) order by id) from public.rm_form_reviewer_assignments x where projeto_id=pg_temp.ca_key('5',1)))=child_state),'retirement never deletes slots, rules, reviewer designations or rematerializes their IDs');
 perform pg_temp.ca_check((pg_temp.ca_call(rid,p)->>'idempotent_replay')::boolean,'fresh permit exact replay precedes the changed snapshot');
 perform pg_temp.ca_reject(pg_temp.ca_payload('set_visibility',1,true),'PT409');
 perform pg_temp.ca_mobile_reject('rm_submit_form_inspection_v1',jsonb_build_object('p_projeto_id',pg_temp.ca_key('5',1),'p_celula_id',pg_temp.ca_key('4',11),
  'p_form_id',pg_temp.ca_key('a',1),'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.ca_key('b',1),'resposta','Preserved offline inspection without allocation ID'))));
 perform pg_temp.ca_mobile_reject('rm_record_cell_photo_v1',jsonb_build_object('p_foto_id',pg_temp.ca_key('d',1),'p_foto_url','https://example.invalid/delayed-slot.jpg'));
 perform pg_temp.ca_mobile_reject('rm_record_cell_photo_v1',jsonb_build_object('p_projeto_id',pg_temp.ca_key('5',1),'p_celula_id',pg_temp.ca_key('4',11),
  'p_foto_url','https://example.invalid/delayed-complementary.jpg','p_titulo','Real queued complementary','p_categoria_foto','complementar'));
 perform pg_temp.ca_mobile_reject('rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.ca_key('6',11),'p_status','em_dia'));
 perform pg_temp.ca_mobile_reject('rm_add_cell_comment_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.ca_key('6',11),'p_comentario','Preserved offline comment'));
 p:=pg_temp.ca_payload('restore'); r:=pg_temp.ca_call(gen_random_uuid(),p);
 perform pg_temp.ca_check(not(r->'record'->>'retirada')::boolean and not(r->'record'->>'visibilidade')::boolean,'restoration always starts hidden instead of silently resuming work');
 perform pg_temp.ca_check((select indice=10 and posicao=18 and prioridade='alta' and forms_ids=array[pg_temp.ca_key('a',1)] from public.rm_celulas_projeto where id=pg_temp.ca_key('6',11)),
  'restoration keeps historical order, priority and original form membership');
 -- A hidden ACTIVE context still accepts existing offline work. Visibility is
 -- deliberately not a new authorization gate for saved submissions.
 r:=pg_temp.ca_mobile(gen_random_uuid(),'rm_submit_form_inspection_v1',jsonb_build_object('p_projeto_id',pg_temp.ca_key('5',1),'p_celula_id',pg_temp.ca_key('4',11),
  'p_form_id',pg_temp.ca_key('a',1),'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.ca_key('b',1),'resposta','Same saved work after explicit restore'))));
 perform pg_temp.ca_check((select count(*)=1 from public.rm_registros_formulario where projeto_id=pg_temp.ca_key('5',1)),'restored same identity accepts a delayed inspection without a new allocation');
end $$;

do $$ declare s jsonb; p jsonb; r jsonb; typ uuid:=pg_temp.ca_key('9',99); state text; begin
 -- Retiring the final active membership must not erase the historical type lock.
 perform pg_temp.ca_call(gen_random_uuid(),pg_temp.ca_payload('retire',30));
 s:=public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',30),pg_temp.ca_key('6',302));
 p:=jsonb_build_object('action','retire','projeto_id',pg_temp.ca_key('5',30),'celula_projeto_id',pg_temp.ca_key('6',302),
  'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
 perform pg_temp.ca_call(gen_random_uuid(),p);
 set local role authenticated; r:=public.rm_web_receivings_v1('without_allocation','CELL-AVAILABILITY-28-30'); reset role;
 perform pg_temp.ca_check((select (x->>'allocation_count')::int=0 and (x->>'historical_allocation_count')::int=2
  and x->'reasons' ? 'without_allocation' and x->'reasons' ? 'legacy_type_locked' from jsonb_array_elements(r->'items') x where x->>'id'=pg_temp.ca_key('5',30)::text),
  'type-null final withdrawal is both without active allocation and historically type-locked');
 insert into public.rm_tipos_equipamento(id,nome) values(typ,'Different type must not reinterpret old offline work');
 p:=jsonb_build_object('id',pg_temp.ca_key('5',30),'expected_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.ca_key('5',30)),'changes',jsonb_build_object('tipo_equipamento_id',typ));
 begin perform pg_temp.ca_call(gen_random_uuid(),p,'em.projects.manage','save_project'); raise exception 'FAIL: historical type lock bypass'; exception when invalid_parameter_value then null; end;
 begin insert into public.rm_celulas_projeto(projeto_id,celula_id) values(pg_temp.ca_key('5',30),pg_temp.ca_key('4',301)); raise exception 'FAIL: recreated withdrawn natural identity'; exception when unique_violation then null; end;
 p:=jsonb_build_object('projeto_id',pg_temp.ca_key('5',30),'celula_id',pg_temp.ca_key('4',301),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.ca_key('6',301)),
  'changes',jsonb_build_object('visibilidade',true,'observacao','Old client cannot restore through plan_cell'));
 begin perform pg_temp.ca_call(gen_random_uuid(),p,'em.planning.manage','plan_cell'); raise exception 'FAIL: old planning resurrected retired allocation'; exception when sqlstate 'PT409' then null; end;
 p:=jsonb_build_object('projeto_id',pg_temp.ca_key('5',24),'celula_id',pg_temp.ca_key('4',241),'expected_updated_at',(select updated_at from public.rm_celulas_projeto where id=pg_temp.ca_key('6',241)),
  'changes',jsonb_build_object('visibilidade',not(select visibilidade from public.rm_celulas_projeto where id=pg_temp.ca_key('6',241))));
 begin perform pg_temp.ca_call(gen_random_uuid(),p,'em.planning.manage','plan_cell'); raise exception 'FAIL: old planning bypassed explicit visibility command'; exception when invalid_parameter_value then null; end;
end $$;

do $$ declare old_row jsonb; r jsonb; begin
 perform pg_temp.ca_call(gen_random_uuid(),pg_temp.ca_payload('retire',18));
 select to_jsonb(a) into old_row from public.rm_celulas_projeto a where id=pg_temp.ca_key('6',181);
 set local role service_role; r:=public.rm_materialize_project_cells_v1(pg_temp.ca_key('5',18)); reset role;
 perform pg_temp.ca_check((r->>'celulas_materializadas')::int=0 and (r->>'fotos_clonadas')::int=0
  and (select to_jsonb(a)=old_row from public.rm_celulas_projeto a where id=pg_temp.ca_key('6',181)),'service materialization skips the retired natural identity without resetting configuration or visibility');
 perform pg_temp.ca_check(not exists(select 1 from public.rm_fotos where projeto_id=pg_temp.ca_key('5',18)),'a visible template does not rematerialize children of an existing retired allocation');
end $$;

do $$ declare s jsonb; p jsonb; r jsonb; begin
 -- Billing ignores purely planned obligations of retired parents, while the
 -- active-completed prerequisite and actual active obligations remain strict.
 insert into public.rm_fotos(projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo) values
  (pg_temp.ca_key('5',31),pg_temp.ca_key('4',311),pg_temp.ca_key('6',311),'obrigat_ria','Empty withdrawn obligation'),
  (pg_temp.ca_key('5',32),pg_temp.ca_key('4',321),pg_temp.ca_key('6',321),'obrigat_ria','Empty active obligation');
 perform pg_temp.ca_call(gen_random_uuid(),pg_temp.ca_payload('retire',31));
 update public.rm_celulas_projeto set status='finalizado' where id=pg_temp.ca_key('6',312);
 p:=jsonb_build_object('id',pg_temp.ca_key('5',31),'expected_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.ca_key('5',31)),
  'changes',jsonb_build_object('status_pcp','finalizando_para_faturar'));
 r:=pg_temp.ca_call(gen_random_uuid(),p,'em.projects.manage','save_project');
 perform pg_temp.ca_check((select status_pcp='finalizando_para_faturar' from public.rm_projetos where id=pg_temp.ca_key('5',31)),
  'billing ignores withdrawn unfilled forms and blank slots with one completed active allocation');
 p:=jsonb_build_object('id',pg_temp.ca_key('5',30),'expected_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.ca_key('5',30)),
  'changes',jsonb_build_object('status_pcp','finalizando_para_faturar'));
 begin perform pg_temp.ca_call(gen_random_uuid(),p,'em.projects.manage','save_project'); raise exception 'FAIL: billed with no active allocation'; exception when invalid_parameter_value then null; end;
 s:=public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',32),pg_temp.ca_key('6',322));
 p:=jsonb_build_object('action','retire','projeto_id',pg_temp.ca_key('5',32),'celula_projeto_id',pg_temp.ca_key('6',322),
  'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
 perform pg_temp.ca_call(gen_random_uuid(),p);
 update public.rm_celulas_projeto set status='finalizado' where id=pg_temp.ca_key('6',321);
 p:=jsonb_build_object('id',pg_temp.ca_key('5',32),'expected_updated_at',(select updated_at from public.rm_projetos where id=pg_temp.ca_key('5',32)),
  'changes',jsonb_build_object('status_pcp','finalizando_para_faturar'));
 begin perform pg_temp.ca_call(gen_random_uuid(),p,'em.projects.manage','save_project'); raise exception 'FAIL: billed with active missing form'; exception when invalid_parameter_value then null; end;
 insert into public.rm_registros_formulario(projeto_id,celula_id,form_id,preenchido) values(pg_temp.ca_key('5',32),pg_temp.ca_key('4',321),pg_temp.ca_key('a',32),true);
 begin perform pg_temp.ca_call(gen_random_uuid(),p,'em.projects.manage','save_project'); raise exception 'FAIL: billed with active missing photo'; exception when invalid_parameter_value then null; end;
end $$;

do $$ declare p jsonb:=pg_temp.ca_payload('set_visibility',24,false); rid uuid:=gen_random_uuid(); r jsonb; begin
 perform pg_temp.ca_call(rid,p);
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'manage_cell_availability',p); raise exception 'FAIL: permitless replay'; exception when insufficient_privilege then reset role; end;
 begin perform pg_temp.ca_call(rid,p||'{"visibilidade":true}'); raise exception 'FAIL: mutated replay'; exception when unique_violation then null; end;
 perform pg_temp.ca_actor(2); begin perform pg_temp.ca_call(rid,p); raise exception 'FAIL: another actor replay'; exception when unique_violation then null; end;
 perform pg_temp.ca_actor(1); insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.ca_call(rid,p); raise exception 'FAIL: MFA replay'; exception when insufficient_privilege then null; end;
 perform pg_temp.ca_actor(1,'aal2'); perform pg_temp.ca_check((pg_temp.ca_call(rid,p)->>'idempotent_replay')::boolean,'exact replay requires current verified MFA');
 delete from auth.mfa_factors where user_id=auth.uid(); perform pg_temp.ca_actor(1);
 p:=pg_temp.ca_payload('set_visibility',24,true); update public.rm_celulas set nome='Changed current context' where id=pg_temp.ca_key('4',241); perform pg_temp.ca_reject(p,'PT409');
 p:=pg_temp.ca_payload('set_visibility',24,true); update public.rm_projetos set nome='Changed current project' where id=pg_temp.ca_key('5',24); perform pg_temp.ca_reject(p,'PT409');
 perform pg_temp.ca_actor(2); r:=pg_temp.ca_call(gen_random_uuid(),pg_temp.ca_payload('set_visibility',24,true));
 perform pg_temp.ca_check(r->>'operation'='manage_cell_availability','standard planning writer need not be an approval decider');
 p:=pg_temp.ca_payload('set_visibility',24,false); perform pg_temp.ca_actor(3); perform pg_temp.ca_reject(p,'42501');
 perform pg_temp.ca_actor(4); perform pg_temp.ca_reject(p,'42501');
 set local role authenticated; perform pg_temp.ca_check(public.rm_web_cell_availability_snapshot_v1(pg_temp.ca_key('5',24),pg_temp.ca_key('6',241)) is null,'inactive RM user has no snapshot'); reset role;
 perform pg_temp.ca_actor(1);
 perform pg_temp.ca_check(not has_table_privilege('authenticated','rm_private.cell_availability_events','SELECT') and not has_table_privilege('service_role','rm_private.cell_availability_events','INSERT'),
  'no private lifecycle journal selection or arbitrary audit writes');
end $$;
rollback;
select 'PASS:028 protected lifecycle, exact fields/children, authorization, old offline guards and completed receipt compatibility' as result;

-- Independent committed fixtures let dblink exercise real transactions. No
-- writer is awaited while the controlling transaction owns its fixture locks.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_cell_availability;
create function rm_test_cell_availability.key(h text,n int) returns uuid language sql immutable as $$ select (h||'e700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create function rm_test_cell_availability.check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values(rm_test_cell_availability.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_cell_availability.key('2',1),rm_test_cell_availability.key('1',1),'Availability concurrent writer','administrador');
insert into auth.sessions(id,user_id) values(rm_test_cell_availability.key('3',1),rm_test_cell_availability.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_cell_availability.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_cell_availability.key('9',1),rm_test_cell_availability.key('2',1),rm_test_cell_availability.key('1',1),true,rm_test_cell_availability.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('e7',32),rm_test_cell_availability.key('8',1),rm_test_cell_availability.key('3',1),'opaque-availability-local-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('availability-mobile-races','sha256'),rm_test_cell_availability.key('1',1),rm_test_cell_availability.key('2',1),rm_test_cell_availability.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero) select rm_test_cell_availability.key('5',n),'AVAILABILITY-RACE-28-'||n from generate_series(1,22) n;
insert into public.rm_celulas(id,nome) select rm_test_cell_availability.key('4',n*10+k),'Availability race cell '||n||'-'||k from generate_series(1,22) n cross join generate_series(1,2) k;
insert into public.rm_celulas(id,nome) select rm_test_cell_availability.key('4',n*10+3),'New materialized race cell '||n from generate_series(21,22) n;
insert into public.rm_forms(id,titulo) select rm_test_cell_availability.key('a',n),'Availability race form '||n from generate_series(1,22) n;
insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) select rm_test_cell_availability.key('b',n),rm_test_cell_availability.key('a',n),'Concurrent offline question','texto_curto',true from generate_series(1,22) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,forms_ids,indice,posicao)
 select rm_test_cell_availability.key('6',n*10+k),rm_test_cell_availability.key('5',n),rm_test_cell_availability.key('4',n*10+k),'pendente',k=1,
  case when k=1 then array[rm_test_cell_availability.key('a',n)] else '{}'::uuid[] end,8+k,16+k from generate_series(1,22) n cross join generate_series(1,2) k;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo)
 select rm_test_cell_availability.key('d',n),rm_test_cell_availability.key('5',n),rm_test_cell_availability.key('4',n*10+1),rm_test_cell_availability.key('6',n*10+1),'obrigat_ria','Concurrent blank slot' from generate_series(1,22) n;
insert into public.rm_tipos_equipamento(id,nome) select rm_test_cell_availability.key('9',n),'Concurrent materialization type '||n from generate_series(21,22) n;
update public.rm_projetos set tipo_equipamento_id=rm_test_cell_availability.key('9',21) where id=rm_test_cell_availability.key('5',21);
update public.rm_projetos set tipo_equipamento_id=rm_test_cell_availability.key('9',22) where id=rm_test_cell_availability.key('5',22);
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id,visibilidade)
 select rm_test_cell_availability.key('e',n*10+k),rm_test_cell_availability.key('4',n*10+k),rm_test_cell_availability.key('9',n),true from generate_series(21,22) n cross join generate_series(1,3) k;
insert into public.rm_fotos(celula_id,celula_tipo_equipamento_id,categoria_foto,titulo)
 select rm_test_cell_availability.key('4',n*10+k),rm_test_cell_availability.key('e',n*10+k),'obrigat_ria','Template race '||n||'-'||k from generate_series(21,22) n cross join (values(1),(3)) t(k);
insert into rm_private.cell_availability_events(projeto_id,celula_projeto_id,actor_id,action,old_visibility,new_visibility,old_retired,new_retired,allocation_version,client_submission_id)
 select projeto_id,id,rm_test_cell_availability.key('2',1),'retire',visibilidade,false,retirada,true,updated_at,gen_random_uuid() from public.rm_celulas_projeto where id=rm_test_cell_availability.key('6',201);
update public.rm_celulas_projeto set retirada=true,visibilidade=false where id=rm_test_cell_availability.key('6',201);
create function rm_test_cell_availability.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; op text; cap text; begin
 perform set_config('request.jwt.claim.sub',rm_test_cell_availability.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_cell_availability.key('3',1),'aal','aal1')::text,true);
 if mode in('availability','queue','route','plan') then
  op:=case mode when 'availability' then 'manage_cell_availability' when 'queue' then 'save_cell_queue' when 'route' then 'save_project_route' else 'plan_cell' end;
  perform public.rm_sso_action_permit_v1(repeat('e7',32),rid,op,p,'em.planning.manage');
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role;
 elsif mode in('inspection','photo','status','comment') then
  op:=case mode when 'inspection' then 'rm_submit_form_inspection_v1' when 'photo' then 'rm_record_cell_photo_v1' when 'status' then 'rm_update_cell_status_v1' else 'rm_add_cell_comment_v1' end;
  set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,op,p,'availability-mobile-races'); reset role;
 elsif mode='raw_record' then insert into public.rm_registros_formulario(projeto_id,celula_id,form_id,preenchido) values((p->>'projeto_id')::uuid,(p->>'celula_id')::uuid,(p->>'form_id')::uuid,false);
 elsif mode='raw_stage' then insert into public.rm_aprovacoes_etapas(projeto_id,celula_origem_id,celula_destino_id,status_cel_proj) values((p->>'projeto_id')::uuid,(p->>'celula_id')::uuid,(p->>'celula_destino_id')::uuid,'finalizado');
 elsif mode='materialize' then set local role service_role; r:=public.rm_materialize_project_cells_v1((p->>'id')::uuid); reset role;
 else raise exception 'Unknown local availability race'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state,'message',sqlerrm); end $$;
commit;

do $$ declare scenario int; s jsonb; q jsonb; route jsonb; p jsonb; other_p jsonb; first_p jsonb; second_p jsonb;
 first_mode text; second_mode text; first_id uuid; second_id uuid; a jsonb; b jsonb; pid_a int; pid_b int; waited int; expected_state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_cell_availability.key('1',1)::text,true);
 perform dblink_connect('availability_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('availability_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('availability_a','select pg_backend_pid()') as t(pid int); select pid into pid_b from dblink('availability_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..22 loop
  s:=public.rm_web_cell_availability_snapshot_v1(rm_test_cell_availability.key('5',scenario),rm_test_cell_availability.key('6',scenario*10+1));
  p:=jsonb_build_object('action',case when scenario=20 then 'restore' else 'retire' end,'projeto_id',rm_test_cell_availability.key('5',scenario),'celula_projeto_id',rm_test_cell_availability.key('6',scenario*10+1),
   'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
  first_mode:='availability'; second_mode:='availability'; other_p:=p;
  if scenario in(1,2) then
   other_p:=jsonb_build_object('p_projeto_id',rm_test_cell_availability.key('5',scenario),'p_celula_id',rm_test_cell_availability.key('4',scenario*10+1),'p_form_id',rm_test_cell_availability.key('a',scenario),
    'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',rm_test_cell_availability.key('b',scenario),'resposta','Concurrent offline inspection without allocation ID')));
   first_mode:=case when scenario=1 then 'availability' else 'inspection' end; second_mode:=case when scenario=1 then 'inspection' else 'availability' end;
  elsif scenario in(3,4) then
   other_p:=jsonb_build_object('p_foto_id',rm_test_cell_availability.key('d',scenario),'p_foto_url','https://example.invalid/concurrent-capture.jpg');
   first_mode:=case when scenario=3 then 'availability' else 'photo' end; second_mode:=case when scenario=3 then 'photo' else 'availability' end;
  elsif scenario in(5,6,20) then
   other_p:=jsonb_build_object('p_celula_projeto_id',rm_test_cell_availability.key('6',scenario*10+1),'p_status','em_dia');
   first_mode:=case when scenario=6 then 'status' else 'availability' end; second_mode:=case when scenario=6 then 'availability' else 'status' end;
  elsif scenario in(7,8) then
   other_p:=jsonb_build_object('p_celula_projeto_id',rm_test_cell_availability.key('6',scenario*10+1),'p_comentario','Concurrent real operator comment');
   first_mode:=case when scenario=7 then 'availability' else 'comment' end; second_mode:=case when scenario=7 then 'comment' else 'availability' end;
  elsif scenario in(9,10) then
   other_p:=jsonb_build_object('projeto_id',rm_test_cell_availability.key('5',scenario),'celula_id',rm_test_cell_availability.key('4',scenario*10+1),'form_id',rm_test_cell_availability.key('a',scenario));
   first_mode:=case when scenario=9 then 'availability' else 'raw_record' end; second_mode:=case when scenario=9 then 'raw_record' else 'availability' end;
  elsif scenario=11 then other_p:=p||'{"action":"set_visibility","visibilidade":false}';
  elsif scenario in(13,14) then
   q:=public.rm_web_cell_queue_snapshot_v1(rm_test_cell_availability.key('4',scenario*10+1));
   other_p:=jsonb_build_object('celula_id',rm_test_cell_availability.key('4',scenario*10+1),'expected_queue_version',q->>'queue_version','apply_order',false,
    'items',(select jsonb_agg(jsonb_build_object('id',x->>'id','expected_updated_at',x->>'updated_at','prioridade','alta') order by n) from jsonb_array_elements(q->'items') with ordinality t(x,n)));
   first_mode:=case when scenario=13 then 'availability' else 'queue' end; second_mode:=case when scenario=13 then 'queue' else 'availability' end;
  elsif scenario in(15,16) then
   route:=public.rm_web_project_route_snapshot_v1(rm_test_cell_availability.key('5',scenario));
   other_p:=jsonb_build_object('projeto_id',rm_test_cell_availability.key('5',scenario),'expected_project_updated_at',route->'project'->>'updated_at','expected_route_version',route->>'route_version',
     'items',(select jsonb_agg(jsonb_build_object('id',x->>'id','expected_updated_at',x->>'updated_at') order by n) from jsonb_array_elements(route->'items') with ordinality t(x,n)));
   first_mode:=case when scenario=15 then 'availability' else 'route' end; second_mode:=case when scenario=15 then 'route' else 'availability' end;
  elsif scenario=17 then
   other_p:=jsonb_build_object('projeto_id',rm_test_cell_availability.key('5',scenario),'celula_id',rm_test_cell_availability.key('4',scenario*10+1),'expected_updated_at',s->'allocation'->>'updated_at','changes',jsonb_build_object('observacao','Concurrent authorized planning'));
   second_mode:='plan';
  elsif scenario in(18,19) then
   other_p:=jsonb_build_object('projeto_id',rm_test_cell_availability.key('5',scenario),'celula_id',rm_test_cell_availability.key('4',scenario*10+1),'celula_destino_id',rm_test_cell_availability.key('4',scenario*10+2));
   first_mode:=case when scenario=18 then 'availability' else 'raw_stage' end; second_mode:=case when scenario=18 then 'raw_stage' else 'availability' end;
  elsif scenario in(21,22) then
   other_p:=jsonb_build_object('id',rm_test_cell_availability.key('5',scenario));
   first_mode:=case when scenario=21 then 'availability' else 'materialize' end; second_mode:=case when scenario=21 then 'materialize' else 'availability' end;
  end if;
  first_p:=case when first_mode='availability' then p else other_p end; second_p:=case when second_mode='availability' then case when scenario=11 then other_p else p end else other_p end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=12 then first_id else gen_random_uuid() end;
  perform dblink_send_query('availability_a',format('select rm_test_cell_availability.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,first_p::text));
  waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first availability race % did not hold',scenario; end if; perform pg_sleep(0.01); end loop;
  perform dblink_send_query('availability_b',format('select rm_test_cell_availability.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_p::text));
  if second_mode not in('raw_record','raw_stage') then
   waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
    waited:=waited+1; if waited>150 then raise exception 'FAIL: second availability race % did not contend',scenario; end if; perform pg_sleep(0.005); end loop;
  else
   -- Raw child guards deliberately use NOWAIT; a fast PT409 is the required
   -- contention outcome while the first writer still owns the parent resource.
   perform pg_sleep(0.025);
   perform rm_test_cell_availability.check(exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep'),'technical child really overlaps the retirement transaction');
  end if;
  select r into a from dblink_get_result('availability_a') as t(r jsonb); perform r from dblink_get_result('availability_a') as t(r jsonb);
  select r into b from dblink_get_result('availability_b') as t(r jsonb); perform r from dblink_get_result('availability_b') as t(r jsonb);
  expected_state:=case when scenario in(12,20,21,22) then '00000' else 'PT409' end;
  perform rm_test_cell_availability.check(a->>'sqlstate'='00000',format('first availability race %s: %s',scenario,a));
  perform rm_test_cell_availability.check(b->>'sqlstate'=expected_state,format('second availability race %s: %s',scenario,b));
  if scenario=12 then perform rm_test_cell_availability.check((b->'result'->>'idempotent_replay')::boolean,'same UUID has exactly one retirement and a completed replay'); end if;
  if scenario in(1,3,5,7,9,11,12,13,15,17,18) then perform rm_test_cell_availability.check((select retirada and not visibilidade from public.rm_celulas_projeto where id=rm_test_cell_availability.key('6',scenario*10+1)),'winning retirement is never silently restored by a later writer'); end if;
  if scenario=20 then perform rm_test_cell_availability.check((select not retirada and not visibilidade and status='em_dia' from public.rm_celulas_projeto where id=rm_test_cell_availability.key('6',201)),'restore wins and hidden active context still accepts the saved status'); end if;
  if scenario in(21,22) then
   perform rm_test_cell_availability.check((select retirada and not visibilidade and forms_ids=array[rm_test_cell_availability.key('a',scenario)] and posicao=17 and indice=9 from public.rm_celulas_projeto where id=rm_test_cell_availability.key('6',scenario*10+1)),'materializer never reopens or reinterprets the retired existing identity');
   perform rm_test_cell_availability.check((select count(*)=3 from public.rm_celulas_projeto where projeto_id=rm_test_cell_availability.key('5',scenario)) and
    (select count(*)=1 from public.rm_fotos where projeto_id=rm_test_cell_availability.key('5',scenario) and celula_id=rm_test_cell_availability.key('4',scenario*10+1)),
    'only the genuinely missing cell is materialized and existing children are not recloned');
  end if;
 end loop;
 perform dblink_disconnect('availability_a'); perform dblink_disconnect('availability_b');
exception when others then if 'availability_a'=any(dblink_get_connections()) then perform dblink_disconnect('availability_a'); end if;
 if 'availability_b'=any(dblink_get_connections()) then perform dblink_disconnect('availability_b'); end if; raise; end $$;
select 'PASS:22 real availability races cover inspection/photo/status/comment in both orders, raw children, retry, queue, route, old planning, stages, hidden restore and materialization both ways' as result;

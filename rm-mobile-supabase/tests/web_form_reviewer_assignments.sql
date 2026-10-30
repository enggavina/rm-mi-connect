\set ON_ERROR_STOP on
begin;
create function pg_temp.fa_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.fa_key(h text,n int) returns uuid language sql immutable as $$
 select (h||'c600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.fa_actor(n int,aal text default 'aal1') returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fa_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.fa_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.fa.actor',n::text,true);
end $$;
create function pg_temp.fa_payload(form_n int default 1,reviewer_n int default 2,confirm boolean default true,project_n int default 1,allocation_n int default 1) returns jsonb language sql as $$
 with s as(select public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',project_n),pg_temp.fa_key('6',allocation_n),true) r)
 select jsonb_build_object('projeto_id',pg_temp.fa_key('5',project_n),'celula_projeto_id',pg_temp.fa_key('6',allocation_n),'form_id',pg_temp.fa_key('a',form_n),
  'avaliador_user_id',pg_temp.fa_key('2',reviewer_n),'expected_project_updated_at',r->'project'->>'updated_at','expected_allocation_updated_at',r->'allocation'->>'updated_at',
  'expected_context_version',(select x->>'context_version' from jsonb_array_elements(r->'forms') x where x->>'id'=pg_temp.fa_key('a',form_n)::text),'confirm_replace',confirm) from s;
$$;
create function pg_temp.fa_call(rid uuid,p jsonb,op text default 'assign_form_reviewer',cap text default 'em.planning.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.fa.actor'),64,'c6'),rid,op,p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,op,p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.fa_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$
declare actual text; begin
 begin perform pg_temp.fa_call(gen_random_uuid(),p,'assign_form_reviewer',cap);
 exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
 end; raise exception 'FAIL: assignment succeeded (expected %)',wanted;
end $$;
do $$ declare n int; begin
 for n in 1..4 loop
  insert into auth.users(id) values(pg_temp.fa_key('1',n));
  insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.fa_key('2',n),pg_temp.fa_key('1',n),'Assignment fixture '||n,
   case when n=1 then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
   case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end);
  insert into auth.sessions(id,user_id) values(pg_temp.fa_key('3',n),pg_temp.fa_key('1',n));
  if n<>4 then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.fa_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.fa_key('9',n),pg_temp.fa_key('2',n),pg_temp.fa_key('1',n),true,pg_temp.fa_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'c6'),pg_temp.fa_key('8',n),pg_temp.fa_key('3',n),'opaque-local-assignment-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end $$;
insert into public.rm_users(id,nome,matricula,perfil) values(pg_temp.fa_key('2',5),'Legacy identity','ASSIGN5','mobile'),(pg_temp.fa_key('2',6),'Tablet only','ASSIGN6','administrador');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) values(pg_temp.fa_key('4',1),'Assignment cell'),(pg_temp.fa_key('4',2),'Other assignment cell');
insert into public.rm_projetos(id,numero,status_pcp) select pg_temp.fa_key('5',n),'ASSIGNMENT-26-'||n,case when n=3 then 'cancelado'::public.rm_status_pcp_enum end from generate_series(1,3) n;
insert into public.rm_forms(id,titulo) select pg_temp.fa_key('a',n),'Assignment form '||n from generate_series(1,5) n;
insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) select pg_temp.fa_key('b',n),pg_temp.fa_key('a',n),'Question '||n,'texto_curto',true from generate_series(1,3) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids)
 select pg_temp.fa_key('6',n),pg_temp.fa_key('5',n),pg_temp.fa_key('4',1),array[pg_temp.fa_key('a',1),pg_temp.fa_key('a',2),pg_temp.fa_key('a',3)] from generate_series(1,3) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,forms_ids) values(pg_temp.fa_key('6',4),pg_temp.fa_key('5',1),pg_temp.fa_key('4',2),'finalizado',array[pg_temp.fa_key('a',1)]);
insert into public.rm_tablet_celula_users(id,celula_id,identidade_id,usuario_id) values
 (pg_temp.fa_key('7',1),pg_temp.fa_key('4',1),pg_temp.fa_key('2',2),null),
 (pg_temp.fa_key('7',2),pg_temp.fa_key('4',1),pg_temp.fa_key('2',5),null),
 (pg_temp.fa_key('7',3),pg_temp.fa_key('4',1),pg_temp.fa_key('2',5),null),
 (pg_temp.fa_key('7',4),pg_temp.fa_key('4',1),null,pg_temp.fa_key('2',6)),
 (pg_temp.fa_key('7',5),pg_temp.fa_key('4',2),pg_temp.fa_key('2',6),null);
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,status,avaliador_user_id)
 select pg_temp.fa_key('c',n),pg_temp.fa_key('5',1),pg_temp.fa_key('4',1),pg_temp.fa_key('a',case when n<=3 then 1 when n=4 then 2 else 4 end),
  case when n=2 then 'direcionado'::public.rm_status_registro_enum when n=3 then 'direcionado' when n=4 then 'aprovado' else 'em_an_lise' end,
  case when n in(2,5) then pg_temp.fa_key('2',5) end from generate_series(1,5) n;
insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta) values(pg_temp.fa_key('d',1),pg_temp.fa_key('c',1),pg_temp.fa_key('b',1),'Preserved original');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('assignment-mobile-fixture','sha256'),pg_temp.fa_key('1',1),pg_temp.fa_key('2',1),pg_temp.fa_key('2',1),clock_timestamp()+interval '1 day');
select pg_temp.fa_actor(1);
set local role authenticated;
do $$ declare s jsonb:=public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true); begin
 perform pg_temp.fa_check((s->>'total')::int=4 and (s->>'records_total')::int=5 and (s->>'eligible_total')::int=2,'snapshot union and dedup exact identity grants');
 perform pg_temp.fa_check(s::text !~ '"(email|auth_user_id|token|bubble_id|legacy_source_ids|sync_source|resposta|parecer)"','minimum DTO without auth/answers/provenance');
 perform pg_temp.fa_check(exists(select 1 from jsonb_array_elements(s->'eligible_users') u where u->>'id'=pg_temp.fa_key('2',5)::text and u->>'matricula'='ASSIGN5'),'legacy active identity may be designated without creating Auth/SSO');
 perform pg_temp.fa_check(not exists(select 1 from jsonb_array_elements(s->'eligible_users') u where u->>'id' in(pg_temp.fa_key('2',1)::text,pg_temp.fa_key('2',6)::text)),'administrator/tablet/other-cell bypass does not create eligibility');
 perform pg_temp.fa_check((select not(x->>'can_assign')::boolean from jsonb_array_elements(s->'forms') x where x->>'id'=pg_temp.fa_key('a',2)::text),'ANY approved record blocks whole tuple');
 perform pg_temp.fa_check((select not(x->>'linked')::boolean and not(x->>'can_assign')::boolean from jsonb_array_elements(s->'forms') x where x->>'id'=pg_temp.fa_key('a',4)::text),'unlinked legacy form is consultative');
 perform pg_temp.fa_check(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',2),pg_temp.fa_key('6',1),true) is null,'cross-project allocation hidden');
 perform pg_temp.fa_check(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),false)->'eligible_users'='[]','readonly omits choices');
end $$;
reset role;
do $$ declare p jsonb:=pg_temp.fa_payload(); rid uuid:=gen_random_uuid(); r jsonb; original jsonb; after_rows jsonb; assignment_row jsonb; before_context jsonb; begin
 perform pg_temp.fa_reject(p,'22023','em.forms.review');
 perform pg_temp.fa_reject(p||'{"actor_id":"2c600000-0000-4000-8000-000000000001"}','22023');
 perform pg_temp.fa_reject(p-'confirm_replace','22023'); perform pg_temp.fa_reject(p||'{"confirm_replace":"true"}','22023');
 perform pg_temp.fa_reject(p||'{"expected_context_version":"bad"}','22023'); perform pg_temp.fa_reject(p||'{"expected_project_updated_at":"infinity"}','22023');
 perform pg_temp.fa_reject(p||'{"expected_allocation_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.fa_reject(p||jsonb_build_object('projeto_id',gen_random_uuid()),'P0002');
 perform pg_temp.fa_reject(p||jsonb_build_object('celula_projeto_id',pg_temp.fa_key('6',2)),'P0002');
 perform pg_temp.fa_reject(pg_temp.fa_payload(1,1),'22023'); perform pg_temp.fa_reject(pg_temp.fa_payload(1,6),'22023');
 perform pg_temp.fa_reject(pg_temp.fa_payload(2),'22023'); perform pg_temp.fa_reject(pg_temp.fa_payload(4),'22023');
 perform pg_temp.fa_reject(pg_temp.fa_payload(1,2,true,3,3),'22023'); perform pg_temp.fa_reject(pg_temp.fa_payload(1,6,true,1,4),'22023');
 perform pg_temp.fa_reject(pg_temp.fa_payload(1,2,false),'22023');
 select jsonb_agg(to_jsonb(q) order by id) into original from public.rm_registros_formulario q where projeto_id=pg_temp.fa_key('5',1) and form_id=pg_temp.fa_key('a',1);
 select jsonb_build_object('p',to_jsonb(proj),'a',to_jsonb(alloc)) into before_context from public.rm_projetos proj join public.rm_celulas_projeto alloc on alloc.projeto_id=proj.id where alloc.id=pg_temp.fa_key('6',1);
 r:=pg_temp.fa_call(rid,p);
 select jsonb_agg(to_jsonb(q) order by id) into after_rows from public.rm_registros_formulario q where projeto_id=pg_temp.fa_key('5',1) and form_id=pg_temp.fa_key('a',1);
 perform pg_temp.fa_check(jsonb_array_length(r->'record'->'records_updated_ids')=3 and r->>'id'=r->'record'->>'assignment_id','one contextual assignment updates every divergent nonapproved record');
 perform pg_temp.fa_check((select jsonb_agg(x-array['avaliador_user_id','updated_at','sync_source'] order by x->>'id') from jsonb_array_elements(original) x)=
  (select jsonb_agg(x-array['avaliador_user_id','updated_at','sync_source'] order by x->>'id') from jsonb_array_elements(after_rows) x),'assignment preserves record identity/status/authorship/answers');
 perform pg_temp.fa_check((select resposta='Preserved original' from public.rm_respostas where id=pg_temp.fa_key('d',1)) and not exists(select 1 from public.rm_aprovacoes_registro where projeto_id=pg_temp.fa_key('5',1)),'designation invents no decision or answer');
 perform pg_temp.fa_check((select jsonb_build_object('p',to_jsonb(proj),'a',to_jsonb(alloc))=before_context from public.rm_projetos proj join public.rm_celulas_projeto alloc on alloc.projeto_id=proj.id where alloc.id=pg_temp.fa_key('6',1)),'project and allocation unchanged');
 perform pg_temp.fa_check((pg_temp.fa_call(rid,p)->>'idempotent_replay')::boolean,'exact replay precedes stale hash after fresh permit');
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'assign_form_reviewer',p); raise exception 'FAIL: permitless replay'; exception when insufficient_privilege then reset role; end;
 begin perform pg_temp.fa_call(rid,p||jsonb_build_object('avaliador_user_id',pg_temp.fa_key('2',5))); raise exception 'FAIL: altered replay'; exception when unique_violation then null; end;
 perform pg_temp.fa_actor(2); begin perform pg_temp.fa_call(rid,p); raise exception 'FAIL: another actor replay'; exception when unique_violation then null; end;
 perform pg_temp.fa_actor(1);
 select to_jsonb(a) into assignment_row from public.rm_form_reviewer_assignments a where a.id=(r->>'id')::uuid;
 r:=pg_temp.fa_call(gen_random_uuid(),pg_temp.fa_payload());
 perform pg_temp.fa_check(r->'record'->'records_updated_ids'='[]' and (select to_jsonb(a)=assignment_row from public.rm_form_reviewer_assignments a where a.id=(r->>'id')::uuid)
  and after_rows=(select jsonb_agg(to_jsonb(q) order by id) from public.rm_registros_formulario q where projeto_id=pg_temp.fa_key('5',1) and form_id=pg_temp.fa_key('a',1)),'no-op preserves every timestamp/row');
 perform pg_temp.fa_reject(pg_temp.fa_payload(1,2,false),'22023');
 perform pg_temp.fa_call(gen_random_uuid(),pg_temp.fa_payload(3,5,false));
 perform pg_temp.fa_check(not exists(select 1 from public.rm_registros_formulario where form_id=pg_temp.fa_key('a',3)),'pre-registration designation creates no artificial record');
end $$;
do $$ declare p jsonb; r jsonb; rid uuid:=gen_random_uuid(); created_id uuid; assignment_id uuid; begin
 p:=jsonb_build_object('p_projeto_id',pg_temp.fa_key('5',1),'p_celula_id',pg_temp.fa_key('4',1),'p_form_id',pg_temp.fa_key('a',3),
  'p_avaliador_user_id',pg_temp.fa_key('2',6),'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.fa_key('b',3),'resposta','Offline original')));
 set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_submit_form_inspection_v1',p,'assignment-mobile-fixture'); reset role;
 created_id:=(r->>'registro_formulario_id')::uuid;
 perform pg_temp.fa_check((select avaliador_user_id=pg_temp.fa_key('2',5) from public.rm_registros_formulario where id=created_id),'server derives current designation, ignoring forged mobile evaluator');
 update public.rm_users set status='inativo' where id=pg_temp.fa_key('2',5);
 set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_submit_form_inspection_v1',p,'assignment-mobile-fixture'); reset role;
 perform pg_temp.fa_check((r->>'idempotent_replay')::boolean and (select avaliador_user_id=pg_temp.fa_key('2',5) from public.rm_registros_formulario where id=created_id),'completed queued UUID preserves original inheritance after revocation');
 set local role authenticated; r:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_inspection_v1',p,'assignment-mobile-fixture'); reset role;
 perform pg_temp.fa_check((select avaliador_user_id is null from public.rm_registros_formulario where id=(r->>'registro_formulario_id')::uuid),'inactive designation never blocks offline submission and grants no evaluator');
 perform pg_temp.fa_check((select not(x->'assignment'->>'eligible')::boolean from jsonb_array_elements(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true)->'forms') x where x->>'id'=pg_temp.fa_key('a',3)::text),'stale designation explicitly flagged');
 update public.rm_users set status='ativo' where id=pg_temp.fa_key('2',5); delete from public.rm_tablet_celula_users where identidade_id=pg_temp.fa_key('2',5);
 set local role authenticated; r:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_inspection_v1',p,'assignment-mobile-fixture'); reset role;
 perform pg_temp.fa_check((select avaliador_user_id is null from public.rm_registros_formulario where id=(r->>'registro_formulario_id')::uuid),'removed identity grant never blocks offline or inherits target');
 insert into public.rm_tablet_celula_users(id,celula_id,identidade_id) values(pg_temp.fa_key('7',2),pg_temp.fa_key('4',1),pg_temp.fa_key('2',5));
end $$;
do $$ declare p jsonb; r jsonb; before_assignment jsonb; begin
 select to_jsonb(a) into before_assignment from public.rm_form_reviewer_assignments a where form_id=pg_temp.fa_key('a',1);
 p:=jsonb_build_object('registro_formulario_id',pg_temp.fa_key('c',1),'expected_updated_at',(select updated_at from public.rm_registros_formulario where id=pg_temp.fa_key('c',1)),
  'decision','return','parecer','Correct original','resposta_ids',jsonb_build_array(pg_temp.fa_key('d',1)));
 perform pg_temp.fa_call(gen_random_uuid(),p,'review_form','em.forms.review');
 perform pg_temp.fa_check((select avaliador_user_id=pg_temp.fa_key('2',1) and status='direcionado' from public.rm_registros_formulario where id=pg_temp.fa_key('c',1)) and
  (select to_jsonb(a)=before_assignment from public.rm_form_reviewer_assignments a where form_id=pg_temp.fa_key('a',1)),'decision keeps historical actor semantics without overwriting future designation');
 perform pg_temp.fa_reject(pg_temp.fa_payload(1,2,false),'22023');
 r:=pg_temp.fa_call(gen_random_uuid(),pg_temp.fa_payload()); perform pg_temp.fa_check(r->'record'->'records_updated_ids'=jsonb_build_array(pg_temp.fa_key('c',1)),'confirmed reapply reconciles only divergent record');
 set local role authenticated; r:=public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_submit_form_revision_v1',jsonb_build_object('p_registro_formulario_id',pg_temp.fa_key('c',1),
  'p_respostas_corrigidas',jsonb_build_array(jsonb_build_object('questao_id',pg_temp.fa_key('b',1),'resposta','Corrected'))),'assignment-mobile-fixture'); reset role;
 perform pg_temp.fa_check((select status='em_an_lise' and avaliador_user_id=pg_temp.fa_key('2',2) from public.rm_registros_formulario where id=pg_temp.fa_key('c',1)),'mobile correction preserves assigned evaluator and semantics');
end $$;
create function pg_temp.fa_import(form_n int,project_n int default 1,reviewer_n int default 5) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.fa_key('e',form_n),'bubble_id','real-source-'||form_n,'legacy_source_ids',jsonb_build_array('real-source-'||form_n,'real-source-duplicate-'||form_n),
  'projeto_id',p.id,'celula_id',a.celula_id,'celula_projeto_id',a.id,'form_id',pg_temp.fa_key('a',form_n),'avaliador_user_id',pg_temp.fa_key('2',reviewer_n),
  'expected_project_updated_at',p.updated_at,'expected_allocation_updated_at',a.updated_at,'created_at','2020-01-01T00:00:00Z','bubble_modified_at','2020-02-01T00:00:00Z')
  from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id where a.id=pg_temp.fa_key('6',project_n);
$$;
do $$ declare p jsonb; r jsonb; original jsonb; state text; begin
 perform pg_temp.fa_check(not has_function_privilege('authenticated','public.rm_bootstrap_form_reviewer_assignment_v1(jsonb)','EXECUTE') and
  not has_table_privilege('authenticated','public.rm_form_reviewer_assignments','INSERT') and not has_table_privilege('service_role','public.rm_form_reviewer_assignments','UPDATE'),'only explicit bootstrap RPC permits service historical inserts');
 select to_jsonb(q) into original from public.rm_registros_formulario q where id=pg_temp.fa_key('c',4);
 p:=pg_temp.fa_import(2);
 set local role service_role; r:=public.rm_bootstrap_form_reviewer_assignment_v1(p); reset role;
 perform pg_temp.fa_check(r->>'status'='inserted' and (select to_jsonb(q)=original from public.rm_registros_formulario q where id=pg_temp.fa_key('c',4)),'historical metadata for approved record never changes record or approval');
 set local role service_role; r:=public.rm_bootstrap_form_reviewer_assignment_v1(p); reset role;
 perform pg_temp.fa_check(r->>'status'='existing','exact historical provenance replays without update');
 begin set local role service_role; perform public.rm_bootstrap_form_reviewer_assignment_v1(p||'{"bubble_modified_at":"2020-03-01T00:00:00Z"}'); raise exception 'FAIL: historical update'; exception when sqlstate 'PT409' then reset role; end;
 begin set local role service_role; perform public.rm_bootstrap_form_reviewer_assignment_v1(p||'{"legacy_source_ids":[]}'); raise exception 'FAIL: no provenance'; exception when invalid_parameter_value then reset role; end;
 begin set local role service_role; perform public.rm_bootstrap_form_reviewer_assignment_v1(p||jsonb_build_object('created_by_id',pg_temp.fa_key('2',1))); raise exception 'FAIL: fabricated historical creator'; exception when invalid_parameter_value then reset role; end;
 begin set local role service_role; perform public.rm_bootstrap_form_reviewer_assignment_v1(p||jsonb_build_object('celula_id',pg_temp.fa_key('4',2))); raise exception 'FAIL: mismatched historical cell'; exception when no_data_found then reset role; end;
 p:=pg_temp.fa_import(4); set local role service_role; r:=public.rm_bootstrap_form_reviewer_assignment_v1(p); reset role;
 perform pg_temp.fa_check(r->>'status'='inserted' and (select not(x->>'linked')::boolean and not(x->>'can_assign')::boolean from jsonb_array_elements(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true)->'forms') x where x->>'id'=pg_temp.fa_key('a',4)::text),'unlinked historical designation is preserved consultatively');
 update public.rm_users set status='inativo' where id=pg_temp.fa_key('2',5);
 p:=pg_temp.fa_import(1,3); set local role service_role; r:=public.rm_bootstrap_form_reviewer_assignment_v1(p); reset role;
 perform pg_temp.fa_check(r->>'status'='inserted' and (select not(x->'assignment'->>'eligible')::boolean and not(x->>'can_assign')::boolean from jsonb_array_elements(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',3),pg_temp.fa_key('6',3),true)->'forms') x where x->>'id'=pg_temp.fa_key('a',1)::text),'closed/inactive real history grants no eligibility');
 update public.rm_users set status='ativo' where id=pg_temp.fa_key('2',5);
 begin update public.rm_celulas_projeto set celula_id=pg_temp.fa_key('4',2) where id=pg_temp.fa_key('6',3); raise exception 'FAIL: silently moved contextual assignment'; exception when invalid_parameter_value then null; end;
 begin delete from public.rm_celulas_projeto where id=pg_temp.fa_key('6',3); raise exception 'FAIL: cascading assignment delete'; exception when invalid_parameter_value then null; end;
 perform pg_temp.fa_check(exists(select 1 from pg_constraint where conrelid='public.rm_form_reviewer_assignments'::regclass and confrelid='public.rm_celulas_projeto'::regclass
  and contype='f' and cardinality(conkey)=3 and confdeltype='r' and confupdtype='r'),'composite historical FK still forbids cascade/movement in addition to the new allocation guard');
 p:=pg_temp.fa_import(3); begin set local role service_role; perform public.rm_bootstrap_form_reviewer_assignment_v1(p); raise exception 'FAIL: bootstrap overwrote local designation'; exception when sqlstate 'PT409' then reset role; end;
end $$;
do $$ declare p jsonb:=pg_temp.fa_payload(); rid uuid:=gen_random_uuid(); begin
 perform pg_temp.fa_call(rid,p);
 insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.fa_call(rid,p); raise exception 'FAIL: MFA replay bypass'; exception when insufficient_privilege then null; end;
 perform pg_temp.fa_actor(1,'aal2'); perform pg_temp.fa_check((pg_temp.fa_call(rid,p)->>'idempotent_replay')::boolean,'MFA revalidated on exact receipt replay');
 delete from auth.mfa_factors where user_id=auth.uid(); perform pg_temp.fa_actor(1);
 p:=pg_temp.fa_payload(); update public.rm_users set nome='Changed eligible name' where id=pg_temp.fa_key('2',5); perform pg_temp.fa_reject(p,'PT409');
 p:=pg_temp.fa_payload(); update public.rm_tablet_celula_users set slug='changed grant version' where id=pg_temp.fa_key('7',2); perform pg_temp.fa_reject(p,'PT409');
 p:=pg_temp.fa_payload(); update public.rm_celulas set nome='Changed cell context' where id=pg_temp.fa_key('4',1); perform pg_temp.fa_reject(p,'PT409');
end $$;
savepoint overflow_records;
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id) select pg_temp.fa_key('c',n),pg_temp.fa_key('5',1),pg_temp.fa_key('4',1),pg_temp.fa_key('a',1) from generate_series(100,2100) n;
do $$ declare s jsonb:=public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true); begin
 perform pg_temp.fa_check(not(s->>'records_complete')::boolean and s->'forms'='[]','overflow records never exposes partial editable contexts');
 perform pg_temp.fa_reject(pg_temp.fa_payload(),'22023');
end $$;
rollback to overflow_records;
savepoint overflow_forms;
insert into public.rm_forms(id,titulo) select pg_temp.fa_key('a',n),'Overflow form '||n from generate_series(100,1100) n;
update public.rm_celulas_projeto set forms_ids=forms_ids||(select array_agg(pg_temp.fa_key('a',n)) from generate_series(100,1100) n) where id=pg_temp.fa_key('6',1);
do $$ declare s jsonb:=public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true); begin
 perform pg_temp.fa_check(not(s->>'complete')::boolean and s->'forms'='[]','overflow forms explicit without partial editing');
 perform pg_temp.fa_reject(pg_temp.fa_payload(),'22023');
end $$;
rollback to overflow_forms;
savepoint overflow_eligible;
insert into public.rm_users(id,nome) select pg_temp.fa_key('2',n),'Overflow identity '||n from generate_series(100,1100) n;
insert into public.rm_tablet_celula_users(celula_id,identidade_id) select pg_temp.fa_key('4',1),pg_temp.fa_key('2',n) from generate_series(100,1100) n;
do $$ declare s jsonb:=public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true); begin
 perform pg_temp.fa_check(not(s->>'eligible_complete')::boolean and s->'eligible_users'='[]' and (select bool_and(not(x->>'can_assign')::boolean) from jsonb_array_elements(s->'forms') x),'overflow choices explicit and commands fail closed');
 perform pg_temp.fa_reject(pg_temp.fa_payload(),'22023');
end $$;
rollback to overflow_eligible;
select pg_temp.fa_actor(2);
select pg_temp.fa_check((pg_temp.fa_call(gen_random_uuid(),pg_temp.fa_payload())->>'operation')='assign_form_reviewer','standard planning writer can assign without engineering/review capability');
select pg_temp.fa_actor(3);
set local role authenticated;
select pg_temp.fa_check(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true)->'eligible_users'='[]','auditor never receives planning choices');
reset role;
select pg_temp.fa_reject(pg_temp.fa_payload(),'42501');
select pg_temp.fa_actor(4);
select pg_temp.fa_reject(pg_temp.fa_payload(),'42501');
set local role authenticated;
select pg_temp.fa_check(public.rm_web_form_reviewer_assignments_snapshot_v1(pg_temp.fa_key('5',1),pg_temp.fa_key('6',1),true) is null,'inactive account cannot read');
reset role;
select pg_temp.fa_actor(1);
do $$ declare p jsonb:=pg_temp.fa_payload(); rid uuid:=gen_random_uuid(); begin
 perform public.rm_sso_action_permit_v1(lpad('1',64,'c6'),rid,'assign_form_reviewer',p,'em.planning.manage');
 update rm_private.sso_action_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=rid;
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'assign_form_reviewer',p); raise exception 'FAIL: expired permit'; exception when insufficient_privilege then reset role; end;
 update rm_private.sso_sessions set expires_at=clock_timestamp()-interval '1 second' where hash=lpad('1',64,'c6'); perform pg_temp.fa_reject(p,'42501');
end $$;
rollback;
select 'PASS: form reviewer snapshot, contextual designation without fake records, multiple records, confirmation/reapply, historical review semantics and offline inheritance/revocation/replay' as result;

-- Committed, disjoint contexts let the driver observe real contention without
-- holding any project/registration lock in its own connection.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_reviewer;
create function rm_test_reviewer.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function rm_test_reviewer.key(h text,n int) returns uuid language sql immutable as $$
 select (h||'c700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
insert into auth.users(id) values(rm_test_reviewer.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_reviewer.key('2',1),rm_test_reviewer.key('1',1),'Concurrent reviewer planner','administrador');
insert into public.rm_users(id,nome) select rm_test_reviewer.key('2',n+100),'Concurrent identity '||n from generate_series(1,20) n;
insert into auth.sessions(id,user_id) values(rm_test_reviewer.key('3',1),rm_test_reviewer.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_reviewer.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_reviewer.key('9',1),rm_test_reviewer.key('2',1),rm_test_reviewer.key('1',1),true,rm_test_reviewer.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('c7',32),rm_test_reviewer.key('8',1),rm_test_reviewer.key('3',1),'opaque-local-reviewer-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('reviewer-mobile-races','sha256'),rm_test_reviewer.key('1',1),rm_test_reviewer.key('2',1),rm_test_reviewer.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select rm_test_reviewer.key('4',n),'Reviewer race cell '||n from generate_series(1,20) n;
insert into public.rm_projetos(id,numero) select rm_test_reviewer.key('5',n),'REVIEWER-RACE-26-'||n from generate_series(1,20) n;
insert into public.rm_forms(id,titulo) select rm_test_reviewer.key('a',n),'Reviewer race form '||n from generate_series(1,20) n;
insert into public.rm_questoes(id,form_id,enunciado,tipo,obrigatorio) select rm_test_reviewer.key('b',n),rm_test_reviewer.key('a',n),'Concurrent question','texto_curto',true from generate_series(1,20) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids)
 select rm_test_reviewer.key('6',n),rm_test_reviewer.key('5',n),rm_test_reviewer.key('4',n),array[rm_test_reviewer.key('a',n)] from generate_series(1,20) n;
insert into public.rm_tablet_celula_users(id,celula_id,identidade_id)
 select rm_test_reviewer.key('7',n),rm_test_reviewer.key('4',n),rm_test_reviewer.key('2',n+100) from generate_series(1,20) n;
insert into public.rm_registros_formulario(id,projeto_id,celula_id,form_id,status)
 select rm_test_reviewer.key('c',n),rm_test_reviewer.key('5',n),rm_test_reviewer.key('4',n),rm_test_reviewer.key('a',n),
  case when n in(7,8) then 'direcionado'::public.rm_status_registro_enum else 'em_an_lise' end from generate_series(1,20) n;
insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta,revisar)
 select rm_test_reviewer.key('d',n),rm_test_reviewer.key('c',n),rm_test_reviewer.key('b',n),'Concurrent original',n in(7,8) from generate_series(1,20) n;
insert into public.rm_form_reviewer_assignments(projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id)
 select rm_test_reviewer.key('5',n),rm_test_reviewer.key('4',n),rm_test_reviewer.key('6',n),rm_test_reviewer.key('a',n),rm_test_reviewer.key('2',n+100) from generate_series(11,14) n;
create function rm_test_reviewer.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_reviewer.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_reviewer.key('3',1),'aal','aal1')::text,true);
 if mode in('assign','review') then
  perform public.rm_sso_action_permit_v1(repeat('c7',32),rid,case when mode='assign' then 'assign_form_reviewer' else 'review_form' end,p,
   case when mode='assign' then 'em.planning.manage' else 'em.forms.review' end);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,case when mode='assign' then 'assign_form_reviewer' else 'review_form' end,p); reset role;
 elsif mode in('create','revision') then
  set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,case when mode='create' then 'rm_submit_form_inspection_v1' else 'rm_submit_form_revision_v1' end,p,'reviewer-mobile-races'); reset role;
 elsif mode='bootstrap' then set local role service_role; r:=public.rm_bootstrap_form_reviewer_assignment_v1(p); reset role;
 elsif mode='revoke_user' then update public.rm_users set status='inativo' where id=(p->>'id')::uuid;
 elsif mode='revoke_tcu' then delete from public.rm_tablet_celula_users where id=(p->>'id')::uuid;
 elsif mode='raw_review' then update public.rm_registros_formulario set status='aprovado' where id=(p->>'id')::uuid;
 elsif mode='raw_insert' then insert into public.rm_registros_formulario(projeto_id,celula_id,form_id) values((p->>'projeto_id')::uuid,(p->>'celula_id')::uuid,(p->>'form_id')::uuid);
 elsif mode='rename' then update public.rm_celulas set nome='Renamed concurrent cell' where id=(p->>'id')::uuid;
 else raise exception 'Unknown local reviewer mode'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate;
 return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end $$;
commit;
do $$ declare scenario int; s jsonb; f jsonb; p jsonb; other_payload jsonb; first_payload jsonb; second_payload jsonb;
 first_mode text; second_mode text; first_id uuid; second_id uuid; a jsonb; b jsonb; pid_a int; pid_b int; waited int; expected_state text;
begin
 perform dblink_connect('reviewer_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('reviewer_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('reviewer_a','select pg_backend_pid()') as t(pid int);
 select pid into pid_b from dblink('reviewer_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..20 loop
  s:=public.rm_web_form_reviewer_assignments_snapshot_v1(rm_test_reviewer.key('5',scenario),rm_test_reviewer.key('6',scenario),true); f:=s->'forms'->0;
  p:=jsonb_build_object('projeto_id',rm_test_reviewer.key('5',scenario),'celula_projeto_id',rm_test_reviewer.key('6',scenario),
   'form_id',rm_test_reviewer.key('a',scenario),'avaliador_user_id',rm_test_reviewer.key('2',scenario+100),'expected_project_updated_at',s->'project'->>'updated_at',
   'expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',f->>'context_version','confirm_replace',true);
  first_mode:='assign'; second_mode:='assign'; other_payload:=p;
  if scenario in(1,2) then
   other_payload:=jsonb_build_object('registro_formulario_id',rm_test_reviewer.key('c',scenario),'expected_updated_at',f->'records'->0->>'updated_at','decision','approve','parecer',null,'resposta_ids','[]'::jsonb);
   first_mode:=case when scenario=1 then 'assign' else 'review' end; second_mode:=case when scenario=1 then 'review' else 'assign' end;
  elsif scenario in(3,4) then
   other_payload:=jsonb_build_object('p_projeto_id',rm_test_reviewer.key('5',scenario),'p_celula_id',rm_test_reviewer.key('4',scenario),'p_form_id',rm_test_reviewer.key('a',scenario),
    'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',rm_test_reviewer.key('b',scenario),'resposta','Concurrent queued inspection')));
   first_mode:=case when scenario=3 then 'assign' else 'create' end; second_mode:=case when scenario=3 then 'create' else 'assign' end;
  elsif scenario in(7,8) then
   other_payload:=jsonb_build_object('p_registro_formulario_id',rm_test_reviewer.key('c',scenario),'p_respostas_corrigidas',jsonb_build_array(jsonb_build_object('questao_id',rm_test_reviewer.key('b',scenario),'resposta','Concurrent correction')));
   first_mode:=case when scenario=7 then 'assign' else 'revision' end; second_mode:=case when scenario=7 then 'revision' else 'assign' end;
  elsif scenario=9 then other_payload:=jsonb_build_object('id',rm_test_reviewer.key('2',scenario+100)); first_mode:='revoke_user'; second_mode:='assign';
  elsif scenario=10 then other_payload:=jsonb_build_object('id',rm_test_reviewer.key('7',scenario)); first_mode:='assign'; second_mode:='revoke_tcu';
  elsif scenario in(11,12,13,14) then
   p:=jsonb_build_object('p_projeto_id',rm_test_reviewer.key('5',scenario),'p_celula_id',rm_test_reviewer.key('4',scenario),'p_form_id',rm_test_reviewer.key('a',scenario),
    'p_respostas',jsonb_build_array(jsonb_build_object('questao_id',rm_test_reviewer.key('b',scenario),'resposta','Concurrent current designation')));
   other_payload:=jsonb_build_object('id',case when scenario in(11,12) then rm_test_reviewer.key('7',scenario) else rm_test_reviewer.key('2',scenario+100) end);
   first_mode:=case when scenario in(11,13) then case when scenario=11 then 'revoke_tcu' else 'revoke_user' end else 'create' end;
   second_mode:=case when scenario in(11,13) then 'create' else case when scenario=12 then 'revoke_tcu' else 'revoke_user' end end;
  elsif scenario in(15,16) then
   other_payload:=jsonb_build_object('id',rm_test_reviewer.key('e',scenario),'bubble_id','concurrent-real-source-'||scenario,'legacy_source_ids',jsonb_build_array('concurrent-real-source-'||scenario),
    'projeto_id',rm_test_reviewer.key('5',scenario),'celula_id',rm_test_reviewer.key('4',scenario),'celula_projeto_id',rm_test_reviewer.key('6',scenario),'form_id',rm_test_reviewer.key('a',scenario),'avaliador_user_id',rm_test_reviewer.key('2',scenario+100),
    'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','created_at','2020-01-01T00:00:00Z','bubble_modified_at','2020-02-01T00:00:00Z');
   first_mode:=case when scenario=15 then 'bootstrap' else 'assign' end; second_mode:=case when scenario=15 then 'assign' else 'bootstrap' end;
  elsif scenario=17 then other_payload:=jsonb_build_object('id',rm_test_reviewer.key('c',scenario)); first_mode:='raw_review'; second_mode:='assign';
  elsif scenario=18 then other_payload:=jsonb_build_object('projeto_id',rm_test_reviewer.key('5',scenario),'celula_id',rm_test_reviewer.key('4',scenario),'form_id',rm_test_reviewer.key('a',scenario)); first_mode:='raw_insert'; second_mode:='assign';
  elsif scenario in(19,20) then other_payload:=jsonb_build_object('id',rm_test_reviewer.key('4',scenario)); first_mode:=case when scenario=19 then 'rename' else 'assign' end; second_mode:=case when scenario=19 then 'assign' else 'rename' end;
  end if;
  first_payload:=case when first_mode=case when scenario in(11,12,13,14) then 'create' else 'assign' end then p else other_payload end;
  second_payload:=case when second_mode=case when scenario in(11,12,13,14) then 'create' else 'assign' end then p else other_payload end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=5 then first_id else gen_random_uuid() end;
  perform dblink_send_query('reviewer_a',format('select rm_test_reviewer.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,first_payload::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first reviewer scenario % did not hold',scenario; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('reviewer_b',format('select rm_test_reviewer.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>150 then raise exception 'FAIL: second reviewer scenario % did not contend',scenario; end if; perform pg_sleep(0.005);
  end loop;
  select r into a from dblink_get_result('reviewer_a') as t(r jsonb); perform r from dblink_get_result('reviewer_a') as t(r jsonb);
  select r into b from dblink_get_result('reviewer_b') as t(r jsonb); perform r from dblink_get_result('reviewer_b') as t(r jsonb);
  expected_state:=case when scenario in(1,2,4,6,8,9,15,16,17,18,19) then 'PT409' else '00000' end;
  perform rm_test_reviewer.check(a->>'sqlstate'='00000',format('first reviewer scenario %s succeeds: %s',scenario,a));
  perform rm_test_reviewer.check(b->>'sqlstate'=expected_state,format('second reviewer scenario %s serializes or rejects changed complete context: %s',scenario,b));
  if scenario=5 then perform rm_test_reviewer.check((b->'result'->>'idempotent_replay')::boolean and (select count(*)=1 from rm_private.web_mutation_receipts where client_submission_id=first_id),'same UUID has one effect and exact receipt'); end if;
  if scenario=2 then perform rm_test_reviewer.check((select status='aprovado' from public.rm_registros_formulario where id=rm_test_reviewer.key('c',scenario)) and not exists(select 1 from public.rm_form_reviewer_assignments where projeto_id=rm_test_reviewer.key('5',scenario)),'approval first prevents designation and leaves approved record intact'); end if;
  if scenario in(3,12,14) then
   perform rm_test_reviewer.check((select avaliador_user_id=rm_test_reviewer.key('2',scenario+100) from public.rm_registros_formulario where id=((case when first_mode='create' then a else b end)->'result'->>'registro_formulario_id')::uuid),'creation inherited eligible designation before subsequent revoke');
  elsif scenario in(4,11,13) then
   perform rm_test_reviewer.check((select avaliador_user_id is null from public.rm_registros_formulario where id=((case when first_mode='create' then a else b end)->'result'->>'registro_formulario_id')::uuid),'creation before designation or after revoke still succeeds without inappropriate evaluator');
  end if;
  if scenario=15 then perform rm_test_reviewer.check((select avaliador_user_id is null from public.rm_registros_formulario where id=rm_test_reviewer.key('c',scenario)),'bootstrap does not propagate into existing registration'); end if;
 end loop;
 perform dblink_disconnect('reviewer_a'); perform dblink_disconnect('reviewer_b');
exception when others then
 if 'reviewer_a'=any(dblink_get_connections()) then perform dblink_disconnect('reviewer_a'); end if;
 if 'reviewer_b'=any(dblink_get_connections()) then perform dblink_disconnect('reviewer_b'); end if; raise;
end $$;
select 'PASS:20 real reviewer races cover approval, creation, correction, exact retry, revocation, bootstrap, raw approval/insertion and cell rename' as result;
-- Concurrent fixtures remain intact only in this disposable local cluster.
-- The runner destroys the cluster; cleanup must not bypass protected DELETE.
begin;
update rm_private.sso_settings set require_sso=false;
commit;

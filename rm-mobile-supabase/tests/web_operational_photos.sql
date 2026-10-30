\set ON_ERROR_STOP on
begin;
create function pg_temp.op_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.op_key(h text,n int) returns uuid language sql immutable as $$
 select (h||'b500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.op_actor(n int,aal text default 'aal1') returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',pg_temp.op_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.op_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.op.actor',n::text,true);
end $$;
create function pg_temp.op_payload(action text,photo_number int default 1,project_number int default 1,allocation_number int default 1) returns jsonb language sql as $$
 with s as(select public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',project_number),pg_temp.op_key('6',allocation_number),true) r)
 select jsonb_build_object('action',action,'projeto_id',pg_temp.op_key('5',project_number),'celula_projeto_id',pg_temp.op_key('6',allocation_number),
  'expected_project_updated_at',r->'project'->>'updated_at','expected_allocation_updated_at',r->'allocation'->>'updated_at',
  'expected_photos_version',r->>'photos_version')||case when action='add' then jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',pg_temp.op_key('f',photo_number),'cadastro_foto_id',pg_temp.op_key('a',7))))
  else jsonb_build_object('foto_id',pg_temp.op_key('c',photo_number),'expected_foto_updated_at',(select updated_at from public.rm_fotos where id=pg_temp.op_key('c',photo_number)))||
   case when action='tag' then jsonb_build_object('tag','operational tag') else '{}'::jsonb end end from s;
$$;
create function pg_temp.op_call(rid uuid,p jsonb,cap text default 'em.planning.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.op.actor'),64,'b5'),rid,'manage_operational_photos',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'manage_operational_photos',p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.op_reject(p jsonb,wanted text,cap text default 'em.planning.manage') returns void language plpgsql as $$
declare actual text; begin
 begin perform pg_temp.op_call(gen_random_uuid(),p,cap);
 exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
 end; raise exception 'FAIL: operational photos succeeded (expected %)',wanted;
end $$;
do $$ declare n int; begin
 for n in 1..6 loop
  insert into auth.users(id) values(pg_temp.op_key('1',n));
  if n<>5 then insert into public.rm_users(id,auth_user_id,nome,perfil,status)
   values(pg_temp.op_key('2',n),pg_temp.op_key('1',n),'Operational photo fixture '||n,
    case when n in(1,6) then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
    case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end); end if;
  insert into auth.sessions(id,user_id) values(pg_temp.op_key('3',n),pg_temp.op_key('1',n));
  if n not in(4,5) then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.op_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.op_key('9',n),
    pg_temp.op_key('2',n),pg_temp.op_key('1',n),true,pg_temp.op_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'b5'),pg_temp.op_key('8',n),pg_temp.op_key('3',n),
    'opaque-local-operational-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) values(pg_temp.op_key('4',1),'Operational fixture'),(pg_temp.op_key('4',2),'Other operational'),
 (pg_temp.op_key('4',3),'Ambiguous fixture'),(pg_temp.op_key('4',4),E'  AMBIGUOUS\t fixture  ');
insert into public.rm_projetos(id,numero,status_pcp,data_real_de_entrega)
 select pg_temp.op_key('5',n),'OPS-25-'||n,case when n=3 then 'cancelado'::public.rm_status_pcp_enum when n=4 then 'finalizando_para_faturar' end,
  case when n=5 then clock_timestamp() end from generate_series(1,5) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,observacao,indice,posicao)
 select pg_temp.op_key('6',n),pg_temp.op_key('5',n),pg_temp.op_key('4',1),'em_dia',true,'Preserved note',79,35 from generate_series(1,5) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) values
 (pg_temp.op_key('6',6),pg_temp.op_key('5',1),pg_temp.op_key('4',2),'finalizado'),
 (pg_temp.op_key('6',7),pg_temp.op_key('5',1),pg_temp.op_key('4',3),'em_dia');
insert into public.rm_cadastro_fotos(id,titulo,numero,celula_nome) select pg_temp.op_key('a',n),'Operational title '||n,n,
 case when n=8 then E'  OPERATIONAL\t fixture  ' when n=9 then 'Other operational' when n=10 then 'Ambiguous fixture' when n=13 then E'\t\n' end from generate_series(1,13) n;
update public.rm_cadastro_fotos set titulo='   ' where id=pg_temp.op_key('a',11);
update public.rm_cadastro_fotos set titulo=E' OPERATIONAL\t TITLE 7 ' where id=pg_temp.op_key('a',12);
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,cadastro_foto_id,categoria_foto,titulo,numero,foto_url,fotos_arquivos_urls,lixeira,selecao_relatorio,tag,legenda)
 select pg_temp.op_key('c',n),pg_temp.op_key('5',case when n=8 then 2 else 1 end),pg_temp.op_key('4',1),
  case when n=7 then null when n=8 then pg_temp.op_key('6',2) when n=9 then pg_temp.op_key('6',6) else pg_temp.op_key('6',1) end,
  case when n=5 then pg_temp.op_key('a',5) when n=13 then pg_temp.op_key('a',1) end,
  case when n=6 then 'complementar'::public.rm_categoria_foto_enum when n=10 then null else 'obrigat_ria' end,
  case when n=5 then 'Operational title 5' when n=13 then 'Slot 1' else 'Slot '||n end,n*3,
  case when n in(2,6) then 'https://example.invalid/main.jpg' when n=12 then '   ' end,
  case when n in(3,14) then array['','https://example.invalid/list.jpg'] when n=12 then array['','   '] else '{}' end,
  n in(5,13,14),n=4,'existing tag','preserved legend' from generate_series(1,14) n where n<>9;
-- Pre028 malformed-slot consultation remains covered in the availability
-- upgrade. New incoherent writes are now forbidden without partial insertion.
do $$ begin
 begin insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo)
  values(pg_temp.op_key('c',9),pg_temp.op_key('5',1),pg_temp.op_key('4',1),pg_temp.op_key('6',6),'obrigat_ria','New incoherent slot');
  raise exception 'FAIL: mismatched new photo context accepted'; exception when invalid_parameter_value then null; end;
 perform pg_temp.op_check(not exists(select 1 from public.rm_fotos where id=pg_temp.op_key('c',9)),'incoherent rejected slot creates no partial photo');
end $$;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('operational-offline-fixture','sha256'),pg_temp.op_key('1',1),pg_temp.op_key('2',1),pg_temp.op_key('2',1),clock_timestamp()+interval '1 day');
select pg_temp.op_actor(1);
set local role authenticated;
do $$ declare s jsonb; begin
 s:=public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',1),pg_temp.op_key('6',1),true);
 perform pg_temp.op_check((s->>'total')::int=12 and (s->>'complete')::boolean and (s->>'titles_complete')::boolean,'complete exact allocation plus legacy null scope');
 perform pg_temp.op_check(s::text !~ '"(foto_url|fotos_arquivos_urls|email|token|auth_user_id|bubble_id|sync_source|modified_by_id)"','DTO contains no media URLs, audit internals or credentials');
 perform pg_temp.op_check((select bool_and(jsonb_typeof(i->'can_edit_tag')='boolean' and jsonb_typeof(i->'can_retire')='boolean' and jsonb_typeof(i->'can_restore')='boolean') from jsonb_array_elements(s->'photos') i),'all photo flags are booleans including null category');
 perform pg_temp.op_check((select i->>'action_reason'='Classificação legada: somente consulta.' from jsonb_array_elements(s->'photos') i where i->>'id'=pg_temp.op_key('c',10)::text),'null legacy category receives its own consultation reason');
 perform pg_temp.op_check((select (i->>'can_edit_tag')::boolean and not(i->>'can_retire')::boolean from jsonb_array_elements(s->'photos') i where i->>'id'=pg_temp.op_key('c',2)::text),'captured mandatory remains tag editable');
 perform pg_temp.op_check((select (i->>'captured')::boolean from jsonb_array_elements(s->'photos') i where i->>'id'=pg_temp.op_key('c',3)::text),'secondary array file counts as capture');
 perform pg_temp.op_check((select not(i->>'captured')::boolean and (i->>'can_retire')::boolean from jsonb_array_elements(s->'photos') i where i->>'id'=pg_temp.op_key('c',12)::text),'only whitespace files are empty');
 perform pg_temp.op_check(not exists(select 1 from jsonb_array_elements(s->'titles') t where t->>'id' in(pg_temp.op_key('a',9)::text,pg_temp.op_key('a',10)::text,pg_temp.op_key('a',11)::text)),'other cell, ambiguous cell and blank titles excluded');
 perform pg_temp.op_check(exists(select 1 from jsonb_array_elements(s->'titles') t where t->>'id'=pg_temp.op_key('a',8)::text),'uniquely normalized cell title applies');
 perform pg_temp.op_check(exists(select 1 from jsonb_array_elements(s->'titles') t where t->>'id'=pg_temp.op_key('a',13)::text),'whitespace-only cell scope remains global using existing catalog normalization');
 perform pg_temp.op_check((select (t->>'assigned')::boolean and t->>'retired_photo_id'=pg_temp.op_key('c',5)::text from jsonb_array_elements(s->'titles') t where t->>'id'=pg_temp.op_key('a',5)::text),'retired title directs restore of original ID');
 perform pg_temp.op_check(public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',2),pg_temp.op_key('6',1),true) is null,'cross-project allocation snapshot is null');
 perform pg_temp.op_check(public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',1),pg_temp.op_key('6',1),false)->'titles'='[]','read-only request omits choices');
end $$;
reset role;
do $$ declare p jsonb:=pg_temp.op_payload('tag',2); r jsonb; rid uuid:=gen_random_uuid(); before_row jsonb; after_row jsonb; before_context jsonb; n int; begin
 perform pg_temp.op_reject(p,'22023','em.projects.manage');
 perform pg_temp.op_reject(p||'{"actor_id":"2b500000-0000-4000-8000-000000000002"}','22023');
 perform pg_temp.op_reject(p-'expected_photos_version','22023');
 perform pg_temp.op_reject(p||'{"expected_photos_version":"invalid"}','22023');
 perform pg_temp.op_reject(p||'{"expected_project_updated_at":"infinity"}','22023');
 perform pg_temp.op_reject(p||'{"expected_foto_updated_at":null}','22023');
 perform pg_temp.op_reject(p||'{"expected_foto_updated_at":"2000-01-01T00:00:00Z"}','PT409');
 perform pg_temp.op_reject(p||'{"tag":12}','22023');
 perform pg_temp.op_reject(p||jsonb_build_object('tag',repeat('x',2001)),'22023');
 perform pg_temp.op_reject(p||jsonb_build_object('projeto_id',gen_random_uuid()),'P0002');
 perform pg_temp.op_reject(p||jsonb_build_object('celula_projeto_id',pg_temp.op_key('6',2)),'P0002');
 perform pg_temp.op_reject(pg_temp.op_payload('tag',6),'22023');
 perform pg_temp.op_reject(pg_temp.op_payload('tag',10),'22023');
 perform pg_temp.op_reject(pg_temp.op_payload('tag',5),'22023');
 perform pg_temp.op_reject(pg_temp.op_payload('tag',8),'22023');
 select to_jsonb(f) into before_row from public.rm_fotos f where id=pg_temp.op_key('c',2);
 select jsonb_build_object('p',to_jsonb(proj),'a',to_jsonb(a)) into before_context from public.rm_projetos proj join public.rm_celulas_projeto a on a.projeto_id=proj.id where a.id=pg_temp.op_key('6',1);
 r:=pg_temp.op_call(rid,p);
 select to_jsonb(f) into after_row from public.rm_fotos f where id=pg_temp.op_key('c',2);
 perform pg_temp.op_check(before_row-array['tag','updated_at','modified_by_id','sync_source']=after_row-array['tag','updated_at','modified_by_id','sync_source'] and after_row->>'tag'='operational tag','tag changes no media, report selection, title or metadata');
 perform pg_temp.op_check((select jsonb_build_object('p',to_jsonb(proj),'a',to_jsonb(a))=before_context from public.rm_projetos proj join public.rm_celulas_projeto a on a.projeto_id=proj.id where a.id=pg_temp.op_key('6',1)),'photo operation preserves project and allocation');
 perform pg_temp.op_check(r->>'id'=pg_temp.op_key('6',1)::text and r->'record'->'changed_ids'=jsonb_build_array(pg_temp.op_key('c',2)) and (r->'record'->>'photos_version')~'^[0-9a-f]{64}$','result is exact context plus changed IDs and new version');
 perform pg_temp.op_check((pg_temp.op_call(rid,p)->>'idempotent_replay')::boolean,'exact replay bypasses stale hashes after fresh authorization');
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'manage_operational_photos',p); raise exception 'FAIL: permitless replay'; exception when insufficient_privilege then reset role; end;
 begin perform pg_temp.op_call(rid,p||'{"tag":"other"}'); raise exception 'FAIL: altered replay'; exception when unique_violation then null; end;
 perform pg_temp.op_actor(6); begin perform pg_temp.op_call(rid,p); raise exception 'FAIL: other actor replay'; exception when unique_violation then null; end;
 perform pg_temp.op_actor(1); insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.op_call(rid,p); raise exception 'FAIL: MFA replay'; exception when insufficient_privilege then null; end;
 perform pg_temp.op_actor(1,'aal2'); perform pg_temp.op_check((pg_temp.op_call(rid,p)->>'idempotent_replay')::boolean,'verified factor requires fresh AAL2 even on replay');
 delete from auth.mfa_factors where user_id=auth.uid(); perform pg_temp.op_actor(1);
 r:=pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('tag',2));
 perform pg_temp.op_check(r->'record'->'changed_ids'='[]' and (select to_jsonb(f)=after_row from public.rm_fotos f where id=pg_temp.op_key('c',2)),'no-op tag preserves complete row including timestamp');
 p:=pg_temp.op_payload('tag',2); update public.rm_cadastro_fotos set titulo='Changed global title' where id=pg_temp.op_key('a',13); perform pg_temp.op_reject(p,'PT409');
 p:=pg_temp.op_payload('tag',2); update public.rm_fotos set legenda='Another capture detail' where id=pg_temp.op_key('c',7); perform pg_temp.op_reject(p,'PT409');
 for n in 3..5 loop perform pg_temp.op_reject(pg_temp.op_payload('add',n,n,n),'22023'); end loop;
 perform pg_temp.op_reject(pg_temp.op_payload('add',60,1,6),'22023');
 update public.rm_celulas_projeto set status='n_a' where id=pg_temp.op_key('6',6); perform pg_temp.op_reject(pg_temp.op_payload('add',60,1,6),'22023');
end $$;
do $$ declare p jsonb; r jsonb; before_count int; original jsonb; before_outbox bigint; before_jobs bigint; begin
 p:=pg_temp.op_payload('add',1); perform pg_temp.op_reject(p||'{"items":[]}','22023');
 perform pg_temp.op_reject(p||jsonb_build_object('items',jsonb_build_array(p->'items'->0,p->'items'->0)),'22023');
 perform pg_temp.op_reject(jsonb_set(p,'{items,0,unexpected}','true'),'22023');
 perform pg_temp.op_reject(p||jsonb_build_object('items',(select jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'cadastro_foto_id',gen_random_uuid())) from generate_series(1,101))),'22023');
 perform pg_temp.op_reject(jsonb_set(p,'{items,0,cadastro_foto_id}',to_jsonb(pg_temp.op_key('a',9))),'22023');
 perform pg_temp.op_reject(jsonb_set(p,'{items,0,cadastro_foto_id}',to_jsonb(pg_temp.op_key('a',5))),'22023');
 select count(*) into before_count from public.rm_fotos;
 p:=p||jsonb_build_object('items',jsonb_build_array(p->'items'->0,jsonb_build_object('id',pg_temp.op_key('f',2),'cadastro_foto_id',pg_temp.op_key('a',12))));
 perform pg_temp.op_reject(p,'22023'); perform pg_temp.op_check((select count(*)=before_count from public.rm_fotos),'batch duplicate title rolls back first insert');
 p:=pg_temp.op_payload('add',1)||jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',pg_temp.op_key('f',1),'cadastro_foto_id',pg_temp.op_key('a',7)),jsonb_build_object('id',pg_temp.op_key('f',2),'cadastro_foto_id',pg_temp.op_key('a',8))));
 select count(*) into before_outbox from public.rm_sync_outbox; select count(*) into before_jobs from rm_private.web_mutation_receipts;
 r:=pg_temp.op_call(pg_temp.op_key('e',1),p);
 perform pg_temp.op_check(jsonb_array_length(r->'record'->'changed_ids')=2 and (select array_agg(numero order by numero)=array[43,44] from public.rm_fotos where id in(pg_temp.op_key('f',1),pg_temp.op_key('f',2))),'batch creates only exact requested stable IDs with sequential order');
 perform pg_temp.op_check((select bool_and(categoria_foto='obrigat_ria' and foto_url is null and fotos_arquivos_urls='{}' and not lixeira and not selecao_relatorio and celula_tipo_equipamento_id is null) from public.rm_fotos where id in(pg_temp.op_key('f',1),pg_temp.op_key('f',2))),'operational slots create no capture/report/template state');
 perform pg_temp.op_check((select count(*)=before_outbox from public.rm_sync_outbox) and (select count(*)=before_jobs+1 from rm_private.web_mutation_receipts),'no outbound jobs and one receipt');
 perform pg_temp.op_check((pg_temp.op_call(pg_temp.op_key('e',1),p)->>'idempotent_replay')::boolean,'batch exact replay');
 perform pg_temp.op_reject(pg_temp.op_payload('add',3),'22023');
 perform pg_temp.op_reject(pg_temp.op_payload('retire',2),'22023'); perform pg_temp.op_reject(pg_temp.op_payload('retire',3),'22023'); perform pg_temp.op_reject(pg_temp.op_payload('retire',4),'22023');
 perform pg_temp.op_reject(pg_temp.op_payload('restore',13),'22023'); perform pg_temp.op_reject(pg_temp.op_payload('restore',14),'22023');
 select to_jsonb(f) into original from public.rm_fotos f where id=pg_temp.op_key('c',7);
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('retire',7));
 perform pg_temp.op_check((select lixeira and celula_projeto_id is null and to_jsonb(f)-array['lixeira','updated_at','modified_by_id','sync_source']=original-array['lixeira','updated_at','modified_by_id','sync_source'] from public.rm_fotos f where id=pg_temp.op_key('c',7)),'retire retains legacy null context, ID and every other field');
 select to_jsonb(f) into original from public.rm_fotos f where id=pg_temp.op_key('c',7);
 r:=pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('retire',7)); perform pg_temp.op_check(r->'record'->'changed_ids'='[]' and (select to_jsonb(f)=original from public.rm_fotos f where id=pg_temp.op_key('c',7)),'no-op retirement preserves timestamp');
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('restore',7));
 select to_jsonb(f) into original from public.rm_fotos f where id=pg_temp.op_key('c',7);
 r:=pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('restore',7)); perform pg_temp.op_check(r->'record'->'changed_ids'='[]' and (select to_jsonb(f)=original from public.rm_fotos f where id=pg_temp.op_key('c',7)),'no-op restoration preserves timestamp');
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('retire',12));
end $$;
-- Failed mobile calls retain their submission ID; restoring the same slot lets
-- the unchanged queued envelope retry, with no silent recreation or restoration.
do $$ declare p jsonb; r jsonb; rid uuid:=pg_temp.op_key('d',1); message text; begin
 p:=jsonb_build_object('p_projeto_id',pg_temp.op_key('5',1),'p_celula_id',pg_temp.op_key('4',1),'p_celula_projeto_id',pg_temp.op_key('6',1),'p_foto_id',pg_temp.op_key('c',5),'p_foto_url','https://example.invalid/offline.jpg');
 begin set local role authenticated; perform public.rm_mobile_mutate_v1(rid,'rm_record_cell_photo_v1',p,'operational-offline-fixture'); raise exception 'FAIL: offline upload restored retired slot';
 exception when sqlstate 'PT409' then get stacked diagnostics message=message_text; reset role; end;
 perform pg_temp.op_check(message like '%restaurar o mesmo item%' and (select lixeira and foto_url is null from public.rm_fotos where id=pg_temp.op_key('c',5)) and not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=rid),'retired upload fails clearly, preserving row and leaving no receipt');
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('restore',5));
 set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_record_cell_photo_v1',p,'operational-offline-fixture'); reset role;
 perform pg_temp.op_check(r->>'foto_id'=pg_temp.op_key('c',5)::text and (select not lixeira and foto_url='https://example.invalid/offline.jpg' from public.rm_fotos where id=pg_temp.op_key('c',5)),'unchanged queued UUID succeeds on restored original ID');
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('tag',5));
 set local role authenticated; r:=public.rm_mobile_mutate_v1(rid,'rm_record_cell_photo_v1',p,'operational-offline-fixture'); reset role;
 perform pg_temp.op_check((r->>'idempotent_replay')::boolean,'completed mobile receipt survives later web metadata edits');
end $$;
-- More contextual choices than the picker limit must not block corrections of
-- existing slots; incomplete photo sets must block every write.
insert into public.rm_cadastro_fotos(id,titulo) select pg_temp.op_key('a',n),'Overflow title '||n from generate_series(100,1100) n;
do $$ declare s jsonb:=public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',1),pg_temp.op_key('6',1),true); begin
 perform pg_temp.op_check(not(s->>'titles_complete')::boolean and s->'titles'='[]' and (s->>'complete')::boolean,'oversized choices are explicit and never truncated');
 perform pg_temp.op_reject(pg_temp.op_payload('add',80),'22023');
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('tag',2)||'{"tag":"choice overflow correction"}');
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('restore',12));
 perform pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('retire',12));
end $$;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo)
 select pg_temp.op_key('f',n),pg_temp.op_key('5',1),pg_temp.op_key('4',1),pg_temp.op_key('6',1),'obrigat_ria','Overflow slot '||n from generate_series(100,2100) n;
do $$ declare s jsonb:=public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',1),pg_temp.op_key('6',1),true); begin
 perform pg_temp.op_check(not(s->>'complete')::boolean and s->'photos'='[]','oversized photos fail closed without partial editable array');
 perform pg_temp.op_reject(pg_temp.op_payload('tag',2),'22023');
end $$;
delete from public.rm_fotos where id between pg_temp.op_key('f',100) and pg_temp.op_key('f',2100);
select pg_temp.op_actor(2);
select pg_temp.op_check((pg_temp.op_call(gen_random_uuid(),pg_temp.op_payload('tag',2)||'{"tag":"standard planner"}')->>'operation')='manage_operational_photos','standard profile may plan without engineering permission');
select pg_temp.op_actor(3);
set local role authenticated;
select pg_temp.op_check(public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',1),pg_temp.op_key('6',1),true)->'titles'='[]','auditor receives no planning choices even if requested');
reset role;
select pg_temp.op_reject(pg_temp.op_payload('tag',2),'42501');
select pg_temp.op_actor(4);
select pg_temp.op_reject(pg_temp.op_payload('tag',2),'42501');
set local role authenticated;
select pg_temp.op_check(public.rm_web_operational_photos_snapshot_v1(pg_temp.op_key('5',1),pg_temp.op_key('6',1),true) is null,'inactive actor cannot read snapshot');
reset role;
select pg_temp.op_actor(5);
select pg_temp.op_reject(pg_temp.op_payload('tag',2),'42501');
select pg_temp.op_actor(1);
do $$ declare p jsonb:=pg_temp.op_payload('tag',2); rid uuid:=gen_random_uuid(); begin
 perform public.rm_sso_action_permit_v1(lpad('1',64,'b5'),rid,'manage_operational_photos',p,'em.planning.manage');
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',gen_random_uuid(),'aal','aal1')::text,true);
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'manage_operational_photos',p); raise exception 'FAIL: foreign Auth session'; exception when insufficient_privilege then reset role; end;
 perform pg_temp.op_actor(1); update rm_private.sso_action_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=rid;
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'manage_operational_photos',p); raise exception 'FAIL: expired action permit'; exception when insufficient_privilege then reset role; end;
 update rm_private.sso_sessions set expires_at=clock_timestamp()-interval '1 second' where hash=lpad('1',64,'b5'); perform pg_temp.op_reject(p,'42501');
end $$;
rollback;
select 'PASS: operational photo scope, contextual choices, strict payload, media guards, metadata-only tag, retirement/restore, exact replay, MFA/SSO and offline UUID retry' as result;

-- Independent committed fixtures make both connections contend against actual
-- project/row locks, without the test driver holding either resource itself.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_operational;
create function rm_test_operational.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function rm_test_operational.key(h text,n int) returns uuid language sql immutable as $$
 select (h||'b600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
insert into auth.users(id) values(rm_test_operational.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(rm_test_operational.key('2',1),rm_test_operational.key('1',1),'Operational race planner','administrador');
insert into auth.sessions(id,user_id) values(rm_test_operational.key('3',1),rm_test_operational.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_operational.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_operational.key('9',1),
  rm_test_operational.key('2',1),rm_test_operational.key('1',1),true,rm_test_operational.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('b6',32),rm_test_operational.key('8',1),rm_test_operational.key('3',1),'opaque-local-operational-races',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('operational-mobile-races','sha256'),rm_test_operational.key('1',1),rm_test_operational.key('2',1),rm_test_operational.key('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) select rm_test_operational.key('4',n),'Operational race '||n from generate_series(1,12) n;
insert into public.rm_projetos(id,numero) select rm_test_operational.key('5',n),'OPERATIONAL-RACE-25-'||n from generate_series(1,12) n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status) select rm_test_operational.key('6',n),rm_test_operational.key('5',n),rm_test_operational.key('4',n),'em_dia' from generate_series(1,12) n;
insert into public.rm_cadastro_fotos(id,titulo,celula_nome) select rm_test_operational.key('a',n),'Race title '||n,'Operational race '||n from generate_series(1,12) n;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,lixeira)
 select rm_test_operational.key('c',n),rm_test_operational.key('5',n),rm_test_operational.key('4',n),rm_test_operational.key('6',n),'obrigat_ria','Race existing '||n,n=11 from generate_series(1,12) n;
create function rm_test_operational.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare result jsonb; state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_operational.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_operational.key('3',1),'aal','aal1')::text,true);
 if mode='web' then
  perform public.rm_sso_action_permit_v1(repeat('b6',32),rid,'manage_operational_photos',p,'em.planning.manage');
  set local role authenticated; result:=public.rm_web_mutate_v1(rid,'manage_operational_photos',p); reset role;
 elsif mode='mobile' then
  set local role authenticated; result:=public.rm_mobile_mutate_v1(rid,'rm_record_cell_photo_v1',p,'operational-mobile-races'); reset role;
 elsif mode='title' then
  -- Deliberately omit catalog advisory17: requested row locks must also protect
  -- against an existing technical/direct SQL writer using normal row locking.
  update public.rm_cadastro_fotos set titulo=p->>'titulo',celula_nome=p->>'celula_nome' where id=(p->>'id')::uuid;
 elsif mode='close' then
  perform pg_advisory_xact_lock(hashtextextended(p->>'id',11));
  update public.rm_projetos set status_pcp='cancelado' where id=(p->>'id')::uuid;
 else raise exception 'Unknown local operational mode'; end if;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',result);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate;
 return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end $$;
commit;
do $$ declare scenario int; s jsonb; p jsonb; other_payload jsonb; first_payload jsonb; second_payload jsonb;
 first_mode text; second_mode text; first_id uuid; second_id uuid; a jsonb; b jsonb; pid_a int; pid_b int; waited int; action text;
begin
 perform dblink_connect('operational_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('operational_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('operational_a','select pg_backend_pid()') as t(pid integer);
 select pid into pid_b from dblink('operational_b','select pg_backend_pid()') as t(pid integer);
 for scenario in 1..12 loop
  s:=public.rm_web_operational_photos_snapshot_v1(rm_test_operational.key('5',scenario),rm_test_operational.key('6',scenario),true);
  action:=case when scenario in(1,2,12) then 'retire' when scenario in(3,4) then 'tag' when scenario=11 then 'restore' else 'add' end;
  p:=jsonb_build_object('action',action,'projeto_id',rm_test_operational.key('5',scenario),'celula_projeto_id',rm_test_operational.key('6',scenario),
   'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_photos_version',s->>'photos_version');
  if action='add' then p:=p||jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',rm_test_operational.key('f',scenario),'cadastro_foto_id',rm_test_operational.key('a',scenario))));
  else p:=p||jsonb_build_object('foto_id',rm_test_operational.key('c',scenario),'expected_foto_updated_at',s->'photos'->0->>'updated_at');
   if action='tag' then p:=p||'{"tag":"concurrent tag"}'; end if;
  end if;
  first_mode:='web'; second_mode:='web'; other_payload:=p;
  if scenario in(1,2,3,4) then
   other_payload:=jsonb_build_object('p_foto_id',rm_test_operational.key('c',scenario),'p_projeto_id',rm_test_operational.key('5',scenario),
    'p_celula_id',rm_test_operational.key('4',scenario),'p_celula_projeto_id',rm_test_operational.key('6',scenario),'p_foto_url','https://example.invalid/race.jpg');
   first_mode:=case when scenario in(1,4) then 'mobile' else 'web' end;
   second_mode:=case when first_mode='mobile' then 'web' else 'mobile' end;
  elsif scenario in(7,8) then
   other_payload:=jsonb_build_object('id',rm_test_operational.key('a',scenario),'titulo','Changed raw title '||scenario,'celula_nome','Other scope');
   first_mode:=case when scenario=7 then 'title' else 'web' end; second_mode:=case when scenario=7 then 'web' else 'title' end;
  elsif scenario in(9,10) then
   other_payload:=jsonb_build_object('id',rm_test_operational.key('5',scenario));
   first_mode:=case when scenario=9 then 'close' else 'web' end; second_mode:=case when scenario=9 then 'web' else 'close' end;
  elsif scenario=12 then other_payload:=p||'{"action":"tag","tag":"late tag"}';
  end if;
  first_payload:=case when first_mode='web' then p else other_payload end;
  second_payload:=case when second_mode='web' then case when scenario=12 then other_payload else p end else other_payload end;
  first_id:=gen_random_uuid(); second_id:=case when scenario in(5,11) then first_id else gen_random_uuid() end;
  perform dblink_send_query('operational_a',format('select rm_test_operational.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,first_payload::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first operational scenario % did not hold',scenario; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('operational_b',format('select rm_test_operational.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>150 then raise exception 'FAIL: second operational scenario % did not contend',scenario; end if; perform pg_sleep(0.005);
  end loop;
  select r into a from dblink_get_result('operational_a') as t(r jsonb); perform r from dblink_get_result('operational_a') as t(r jsonb);
  select r into b from dblink_get_result('operational_b') as t(r jsonb); perform r from dblink_get_result('operational_b') as t(r jsonb);
  perform rm_test_operational.check(a->>'sqlstate'='00000',format('first operational scenario %s succeeds: %s',scenario,a));
  perform rm_test_operational.check(b->>'sqlstate'=case when scenario in(1,2,4,6,7,9,12) then 'PT409' else '00000' end,
   format('second operational scenario %s serializes or rejects stale version: %s',scenario,b));
  if scenario in(5,11) then perform rm_test_operational.check((b->'result'->>'idempotent_replay')::boolean and (select count(*)=1 from rm_private.web_mutation_receipts where client_submission_id=first_id),'same UUID returns exact receipt once'); end if;
  if scenario=1 then perform rm_test_operational.check((select not lixeira and foto_url is not null from public.rm_fotos where id=rm_test_operational.key('c',scenario)),'capture before retirement retains captured active row'); end if;
  if scenario=2 then perform rm_test_operational.check((select lixeira and foto_url is null from public.rm_fotos where id=rm_test_operational.key('c',scenario)) and b->>'message' like '%restaurar o mesmo item%','retirement before capture preserves retired slot and explains recovery'); end if;
  if scenario=3 then perform rm_test_operational.check((select tag='concurrent tag' and foto_url is not null from public.rm_fotos where id=rm_test_operational.key('c',scenario)),'mobile after tag preserves tag and adds capture'); end if;
  if scenario=7 then perform rm_test_operational.check(not exists(select 1 from public.rm_fotos where id=rm_test_operational.key('f',scenario)),'raw catalog update first cannot create out-of-scope slot'); end if;
  if scenario=8 then perform rm_test_operational.check((select titulo='Race title 8' from public.rm_fotos where id=rm_test_operational.key('f',scenario)) and (select celula_nome='Other scope' from public.rm_cadastro_fotos where id=rm_test_operational.key('a',scenario)),'add before raw catalog update uses the locked validated title; future catalog edits preserve materialized title'); end if;
 end loop;
 perform dblink_disconnect('operational_a'); perform dblink_disconnect('operational_b');
exception when others then
 if 'operational_a'=any(dblink_get_connections()) then perform dblink_disconnect('operational_a'); end if;
 if 'operational_b'=any(dblink_get_connections()) then perform dblink_disconnect('operational_b'); end if; raise;
end $$;
select 'PASS: 12 real races cover mobile capture/tag/retirement, add and restore same UUID, stale batches, raw title updates, project closure and blocked late tag' as result;
-- Concurrent fixtures remain intact only in this disposable local cluster.
-- The runner destroys the cluster; cleanup must not bypass protected DELETE.
begin;
update rm_private.sso_settings set require_sso=false;
commit;

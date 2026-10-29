\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.call_catalog(request_id uuid,operation text,payload jsonb,cap text default 'em.catalogs.manage')
returns jsonb language plpgsql as $$
declare result jsonb;
begin
  perform public.rm_sso_action_permit_v1(repeat('7',64),request_id,operation,payload,cap);
  set local role authenticated;
  result:=public.rm_web_mutate_v1(request_id,operation,payload);
  reset role;
  return result;
exception when others then reset role; raise;
end $$;
create function pg_temp.reject_catalog(operation text,payload jsonb,wanted text) returns void language plpgsql as $$
declare actual text;
begin
  begin perform pg_temp.call_catalog(gen_random_uuid(),operation,payload);
  exception when others then get stacked diagnostics actual=returned_sqlstate;
    if actual=wanted then return; end if;
    raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
  end;
  raise exception 'FAIL: request unexpectedly accepted (%).',wanted;
end $$;
create function pg_temp.save_payload(kind text,id uuid,version text,changes jsonb) returns jsonb language sql as $$
  select jsonb_build_object('kind',kind,'id',id,'expected_updated_at',version,'changes',changes);
$$;
create function pg_temp.delete_payload(kind text,id uuid,version text) returns jsonb language sql as $$
  select jsonb_build_object('kind',kind,'id',id,'expected_updated_at',version);
$$;
insert into auth.users(id) values('17000000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('27000000-0000-4000-8000-000000000001','17000000-0000-4000-8000-000000000001','Catalog admin fixture','administrador');
insert into auth.sessions(id,user_id) values('37000000-0000-4000-8000-000000000001','17000000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('47000000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','57000000-0000-4000-8000-000000000001',
 '27000000-0000-4000-8000-000000000001','17000000-0000-4000-8000-000000000001',true,'27000000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('7',64),'47000000-0000-4000-8000-000000000001','37000000-0000-4000-8000-000000000001',
 'opaque-catalog-fixture-session',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','17000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"37000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select set_config('rm.test.outbox_before',(select count(*)::text from public.rm_sync_outbox),true);

-- Local harness only: a second real database connection holds the exact locks
-- taken by concurrent data writers. Contention fails safely with HTTP409,
-- retaining the row and avoiding a lock-order deadlock with mobile work.
create extension dblink;
do $$
#variable_conflict use_variable
declare id uuid; v text;
begin
  insert into public.rm_clientes(nome) values('Concurrent deletion fixture') returning rm_clientes.id,updated_at::text into id,v;
  perform dblink_connect('catalog_lock','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user='||current_user);
  perform dblink_exec('catalog_lock','begin');
  perform dblink_exec('catalog_lock','lock table public.rm_forms in row exclusive mode');
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('clients',id,v),'PT409');
  perform pg_temp.check(exists(select 1 from public.rm_clientes where rm_clientes.id=id),'concurrent soft-link writer preserves catalog');
  perform dblink_exec('catalog_lock','rollback');
  perform dblink_disconnect('catalog_lock');
exception when others then
  if 'catalog_lock'=any(dblink_get_connections()) then
    perform dblink_exec('catalog_lock','rollback'); perform dblink_disconnect('catalog_lock');
  end if;
  raise;
end $$;

-- End-to-end create/update/delete with strict BFF permits and full receipt replay.
do $$
#variable_conflict use_variable
declare id uuid:=gen_random_uuid(); rid uuid:=gen_random_uuid(); p jsonb; r jsonb; version text; deleted jsonb;
begin
  p:=pg_temp.save_payload('clients',id,null,'{"nome":"  Fixture Client  ","codigo":" ","descricao":"  Detail  "}');
  r:=pg_temp.call_catalog(rid,'save_catalog',p);
  perform pg_temp.check(r->'record'->>'nome'='Fixture Client' and r->'record'->'codigo'='null'::jsonb
    and r->'record'->>'descricao'='Detail' and r->'projeto_id'='null'::jsonb,'text normalization/result contract');
  version:=r->>'updated_at';
  perform pg_temp.check((pg_temp.call_catalog(rid,'save_catalog',p)->>'idempotent_replay')::boolean,'save replay with fresh permit');
  begin perform pg_temp.call_catalog(rid,'save_catalog',p||'{"extra":true}');
    raise exception 'FAIL: UUID reused with another payload'; exception when unique_violation then null; end;
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('clients',gen_random_uuid(),null,'{"nome":"fixture   CLIENT"}'),'23505');
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('clients',id,null,'{"nome":"Conflict"}'),'PT409');
  r:=pg_temp.call_catalog(gen_random_uuid(),'save_catalog',pg_temp.save_payload('clients',id,version,'{"descricao":null}'));
  perform pg_temp.check(r->'record'->'descricao'='null'::jsonb and r->'record'->>'nome'='Fixture Client','PATCH preserves omitted fields');
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('clients',id,version),'PT409');
  version:=r->>'updated_at'; p:=pg_temp.delete_payload('clients',id,version); rid:=gen_random_uuid();
  deleted:=pg_temp.call_catalog(rid,'delete_catalog',p);
  perform pg_temp.check(not exists(select 1 from public.rm_clientes where rm_clientes.id=id)
    and deleted->'record'=r->'record' and deleted->>'updated_at'=version,'unused deletion returns exact snapshot');
  perform pg_temp.check((pg_temp.call_catalog(rid,'delete_catalog',p)->>'idempotent_replay')::boolean,'delete replay after row absent');
  perform pg_temp.reject_catalog('delete_catalog',p,'PT409');
end $$;

-- Whitelist/type/bounds, all catalog types, auto ordering and legacy duplicates.
do $$
#variable_conflict use_variable
declare id uuid; p jsonb; r jsonb; max_ind integer; max_ord integer; v text; bad jsonb;
begin
  foreach bad in array array['{}'::jsonb,'{"nome":null}','{"nome":"  "}','{"nome":"\t\n"}','{"nome":12}','{"nome":"Valid","bubble_id":"injected"}',
    '{"nome":"Valid","auth_user_id":null}','{"nome":"Valid","sync_source":"bubble"}',
    jsonb_build_object('nome',repeat('x',201)),jsonb_build_object('nome','Valid','codigo',repeat('x',81)),
    jsonb_build_object('nome','Valid','descricao',repeat('x',4001))] loop
    perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('clients',gen_random_uuid(),null,bad),'22023');
  end loop;
  foreach bad in array array['{"nome":"Valid","indice":-1}'::jsonb,'{"nome":"Valid","ordem":1000001}',
    '{"nome":"Valid","indice":1.5}','{"nome":"Valid","ordem":"3"}','{"nome":"Valid","ordem":true}'] loop
    perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('cells',gen_random_uuid(),null,bad),'22023');
  end loop;
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('types',gen_random_uuid(),null,jsonb_build_object('nome','Type','sigla',repeat('s',31))),'22023');
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('users',gen_random_uuid(),null,'{"nome":"Forbidden"}'),'22023');
  perform pg_temp.reject_catalog('save_catalog','{"kind":"clients","id":"not-uuid","expected_updated_at":null,"changes":{"nome":"Invalid"}}','22023');
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('clients',gen_random_uuid(),'infinity','{"nome":"Invalid"}'),'22023');
  select greatest(coalesce(max(indice),0),0)+1,greatest(coalesce(max(ordem),0),0)+1 into max_ind,max_ord from public.rm_celulas;
  id:=gen_random_uuid();r:=pg_temp.call_catalog(gen_random_uuid(),'save_catalog',pg_temp.save_payload('cells',id,null,'{"nome":"Cell fixture","ordem":null}'));
  perform pg_temp.check((r->'record'->>'indice')::int=max_ind and (r->'record'->>'ordem')::int=max_ord,'new cell assigns both MAX+1');
  r:=pg_temp.call_catalog(gen_random_uuid(),'save_catalog',pg_temp.save_payload('cells',id,r->>'updated_at','{"indice":null,"ordem":0}'));
  perform pg_temp.check(r->'record'->'indice'='null'::jsonb and r->'record'->>'ordem'='0','existing cell preserves explicit null and zero');
  r:=pg_temp.call_catalog(gen_random_uuid(),'save_catalog',pg_temp.save_payload('types',gen_random_uuid(),null,'{"nome":"Equipment type fixture","sigla":"  MT  "}'));
  perform pg_temp.check(r->'record'->>'sigla'='MT','type saved');
  insert into public.rm_clientes(nome) values('Legacy duplicate'),('legacy DUPLICATE');
  select rm_clientes.id,updated_at::text into id,v from public.rm_clientes where nome='Legacy duplicate';
  perform pg_temp.call_catalog(gen_random_uuid(),'save_catalog',pg_temp.save_payload('clients',id,v,'{"codigo":"safe-edit"}'));
  perform pg_temp.check((select codigo='safe-edit' from public.rm_clientes where rm_clientes.id=id),'non-rename of preexisting duplicate permitted');
end $$;

-- All FK delete actions are blockers (CASCADE and SET NULL), including a future
-- FK discovered dynamically, UUID arrays, and legacy text references.
create table public.rm_catalog_test_fk(id uuid primary key default gen_random_uuid(),client_id uuid references public.rm_clientes(id) on delete set null);
do $$
#variable_conflict use_variable
declare id uuid; child uuid; v text; cell uuid; typ uuid; p uuid;
begin
  insert into public.rm_clientes(nome) values('Used client') returning rm_clientes.id,updated_at::text into id,v;
  insert into public.rm_contatos_clientes(cliente_id,nome) values(id,'Contact fixture') returning rm_contatos_clientes.id into child;
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('clients',id,v),'23503');
  perform pg_temp.check(exists(select 1 from public.rm_contatos_clientes where rm_contatos_clientes.id=child),'CASCADE child preserved');
  delete from public.rm_contatos_clientes where rm_contatos_clientes.id=child;
  insert into public.rm_catalog_test_fk(client_id) values(id) returning rm_catalog_test_fk.id into child;
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('clients',id,v),'23503');
  perform pg_temp.check((select client_id=id from public.rm_catalog_test_fk where rm_catalog_test_fk.id=child),'SET NULL child unchanged');
  delete from public.rm_catalog_test_fk where rm_catalog_test_fk.id=child;
  insert into public.rm_projetos(nome,cliente_nome_exportacao) values('Legacy project fixture','  USED   CLIENT ') returning rm_projetos.id into p;
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('clients',id,v),'23503');
  perform pg_temp.call_catalog(gen_random_uuid(),'save_catalog',pg_temp.save_payload('clients',id,v,'{"nome":"Renamed used client"}'));
  select updated_at::text into v from public.rm_clientes where rm_clientes.id=id;
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('clients',id,v),'23503');
  insert into public.rm_celulas(nome) values('Array cell fixture') returning rm_celulas.id,updated_at::text into cell,v;
  insert into public.rm_forms(titulo,celulas_ids) values('Array form fixture',array[cell]);
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('cells',cell,v),'23503');
  insert into public.rm_tipos_equipamento(nome) values('Legacy type fixture') returning rm_tipos_equipamento.id,updated_at::text into typ,v;
  insert into public.rm_templates_word(nome,tipo_equipamento) values('Template fixture','Legacy type fixture');
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('types',typ,v),'23503');
end $$;

-- Cell names are real photo-catalog links. Rename and receipt audit are atomic;
-- ambiguous old names and adoption of orphan destination links are forbidden.
do $$
#variable_conflict use_variable
declare id uuid; photo uuid; v text; rid uuid:=gen_random_uuid(); r jsonb;
begin
  insert into public.rm_celulas(nome) values('Original photo cell') returning rm_celulas.id,updated_at::text into id,v;
  insert into public.rm_cadastro_fotos(celula_nome,titulo) values(' ORIGINAL  PHOTO CELL ','Photo fixture') returning rm_cadastro_fotos.id into photo;
  r:=pg_temp.call_catalog(rid,'save_catalog',pg_temp.save_payload('cells',id,v,'{"nome":"Renamed photo cell"}'));
  perform pg_temp.check((select celula_nome='Renamed photo cell' from public.rm_cadastro_fotos where rm_cadastro_fotos.id=photo),'rename preserves text photo link');
  perform pg_temp.check((select before_record->'_related_changes'->0->'before'->>'celula_nome'=' ORIGINAL  PHOTO CELL '
    and before_record->'_related_changes'->0->'after'->>'celula_nome'='Renamed photo cell'
    from rm_private.web_mutation_receipts where client_submission_id=rid),'related before and after audited');
  perform pg_temp.reject_catalog('delete_catalog',pg_temp.delete_payload('cells',id,r->>'updated_at'),'23503');
  insert into public.rm_celulas(nome) values('Ambiguous'),('ambiguous');
  insert into public.rm_cadastro_fotos(celula_nome,titulo) values('Ambiguous','Ambiguous photo fixture');
  select rm_celulas.id,updated_at::text into id,v from public.rm_celulas where nome='Ambiguous';
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('cells',id,v,'{"nome":"Unique future cell"}'),'23503');
  insert into public.rm_cadastro_fotos(celula_nome,titulo) values('Orphan future cell','Orphan photo fixture');
  perform pg_temp.reject_catalog('save_catalog',pg_temp.save_payload('cells',gen_random_uuid(),null,'{"nome":"Orphan future cell"}'),'23503');
end $$;

-- SSO, explicit capability, role, activity and MFA remain mandatory on replays.
do $$
#variable_conflict use_variable
declare p jsonb:=pg_temp.save_payload('types',gen_random_uuid(),null,'{"nome":"Security fixture"}'); rid uuid:=gen_random_uuid();
begin
  begin perform pg_temp.call_catalog(rid,'save_catalog',p,'em.projects.manage');
    raise exception 'FAIL: wrong capability accepted'; exception when invalid_parameter_value then null; end;
  set local role authenticated;
  begin perform public.rm_web_mutate_v1(rid,'save_catalog',p);
    raise exception 'FAIL: missing SSO permit'; exception when insufficient_privilege then null; end;
  reset role;
  perform pg_temp.call_catalog(rid,'save_catalog',p);
  update public.rm_users set perfil='auditor' where auth_user_id=auth.uid();
  perform pg_temp.reject_catalog('save_catalog',p,'42501');
  update public.rm_users set perfil='padr_o' where auth_user_id=auth.uid();
  perform pg_temp.reject_catalog('save_catalog',p,'42501');
  update public.rm_users set perfil='administrador' where auth_user_id=auth.uid();
  insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
  begin perform pg_temp.call_catalog(rid,'save_catalog',p);
    raise exception 'FAIL: AAL1 replay bypass'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"session_id":"37000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
  perform pg_temp.check((pg_temp.call_catalog(rid,'save_catalog',p)->>'idempotent_replay')::boolean,'AAL2 replay succeeds');
  update public.rm_users set status='inativo' where auth_user_id=auth.uid();
  perform pg_temp.reject_catalog('save_catalog',p,'42501');
  update public.rm_users set status='ativo' where auth_user_id=auth.uid();
end $$;
select pg_temp.check(not has_function_privilege('anon','public.rm_web_mutate_v1(uuid,text,jsonb)','EXECUTE'),'anon RPC denied');
select pg_temp.check(not has_function_privilege('service_role','public.rm_web_mutate_v1(uuid,text,jsonb)','EXECUTE'),'service RPC bypass denied');
select pg_temp.check(not has_function_privilege('authenticated','rm_private.web_mutate_core_v1(uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('service_role','rm_private.web_mutate_project_core_v1(uuid,text,jsonb)','EXECUTE'),'private dispatcher/core denied');
select pg_temp.check(not has_table_privilege('authenticated','public.rm_clientes','INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.rm_celulas','INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.rm_tipos_equipamento','INSERT,UPDATE,DELETE'),'direct catalog writes denied');

select pg_temp.check((select count(*)::text from public.rm_sync_outbox)=current_setting('rm.test.outbox_before'),'no outbound events');
select 'PASS: web catalogs, references, text rename audit, versions, idempotency, SSO and MFA' as result;
rollback;

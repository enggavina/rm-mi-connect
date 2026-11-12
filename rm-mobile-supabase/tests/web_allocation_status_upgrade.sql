\set ON_ERROR_STOP on
\if :{?rm_migration_042_path}
\else
\quit 3
\endif
select set_config('rm.test.migration_042_path',:'rm_migration_042_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required';end if;end$$;
create function pg_temp.csu_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.csu_id(h text,n int) returns uuid language sql immutable as $$select(h||'b420000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
insert into auth.users(id) values(pg_temp.csu_id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(pg_temp.csu_id('2',1),pg_temp.csu_id('1',1),'Status upgrade planner','administrador','ativo');
insert into public.rm_projetos(id,nome,status_pcp) values(pg_temp.csu_id('5',1),'Legacy status upgrade project','executando');
insert into public.rm_celulas(id,nome) select pg_temp.csu_id('4',n),'Legacy status upgrade cell '||n from generate_series(1,2)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,status_historico,visibilidade) select pg_temp.csu_id('6',n),pg_temp.csu_id('5',1),pg_temp.csu_id('4',n),'pendente',array['pendente']::public.rm_status_cel_proj_enum[],true from generate_series(1,2)n;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) select pg_temp.csu_id('4',n),pg_temp.csu_id('2',1),pg_temp.csu_id('2',1) from generate_series(1,2)n;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values(extensions.digest('status-upgrade-mobile','sha256'),pg_temp.csu_id('1',1),pg_temp.csu_id('2',1),pg_temp.csu_id('2',1),clock_timestamp()+interval '1 day');
insert into auth.sessions(id,user_id) values(pg_temp.csu_id('3',1),pg_temp.csu_id('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values(pg_temp.csu_id('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.csu_id('9',1),pg_temp.csu_id('2',1),pg_temp.csu_id('1',1),true,pg_temp.csu_id('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('b4',32),pg_temp.csu_id('8',1),pg_temp.csu_id('3',1),'opaque-status-upgrade-local',clock_timestamp()+interval '45 minutes');
select set_config('request.jwt.claim.sub',pg_temp.csu_id('1',1)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.csu_id('3',1),'aal','aal1')::text,true);
update rm_private.sso_settings set require_sso=true;
create temporary table csu_payloads(id uuid,payload jsonb,result jsonb);
grant select,update on csu_payloads to authenticated;
insert into csu_payloads select pg_temp.csu_id('e',1),jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Warm old planning command')),null from public.rm_celulas_projeto where id=pg_temp.csu_id('6',2);
select public.rm_sso_action_permit_v1(repeat('b4',32),pg_temp.csu_id('e',1),'plan_cell',(select payload from csu_payloads),'em.planning.manage');
create function pg_temp.csu_warm_web(rid uuid,p jsonb) returns jsonb language plpgsql as $$begin return public.rm_web_mutate_v1(rid,'plan_cell',p);end$$;
create function pg_temp.csu_warm_mobile(rid uuid,p jsonb) returns jsonb language plpgsql as $$begin return public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',p,'status-upgrade-mobile');end$$;
set local role authenticated;
update csu_payloads set result=pg_temp.csu_warm_web(id,payload);
select pg_temp.csu_warm_mobile(pg_temp.csu_id('d',1),jsonb_build_object('p_celula_projeto_id',pg_temp.csu_id('6',1),'p_status','em_dia'));
reset role;
select public.rm_sso_action_permit_v1(repeat('b4',32),pg_temp.csu_id('e',1),'plan_cell',(select payload from csu_payloads),'em.planning.manage');
insert into csu_payloads select pg_temp.csu_id('e',2),jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Permit issued before upgrade')),null from public.rm_celulas_projeto where id=pg_temp.csu_id('6',2);
select public.rm_sso_action_permit_v1(repeat('b4',32),pg_temp.csu_id('e',2),'plan_cell',(select payload from csu_payloads where id=pg_temp.csu_id('e',2)),'em.planning.manage');
create temporary table csu_rows(name text primary key,projection text,rows bigint,hash text);
create temporary table csu_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table csu_catalog(kind text,id oid,value jsonb,primary key(kind,id));
do $$declare t record;cols text;n bigint;h text;condition text;begin
 for t in select ns.nspname,c.relname,c.oid from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and(ns.nspname='rm_private' or(ns.nspname='public' and c.relname like 'rm\_%' escape '\') or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  select string_agg(quote_ident(attname),',' order by attnum) into cols from pg_attribute where attrelid=t.oid and attnum>0 and not attisdropped;
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %I.%I) r',cols,t.nspname,t.relname) into n,h;
  insert into csu_rows values(format('%I.%I',t.nspname,t.relname),cols,n,h);
 end loop;
 insert into csu_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into csu_catalog select 'policy',p.oid,to_jsonb(p) from pg_policy p;
 insert into csu_catalog select 'trigger',p.oid,to_jsonb(p) from pg_trigger p;
 insert into csu_catalog select 'constraint',p.oid,to_jsonb(p) from pg_constraint p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_042_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected migration boundary';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare t record;n bigint;h text;condition text;begin
 for t in select * from csu_rows loop
  condition:=case when t.name='public.rm_option_sets' then 'where not(option_set_key=''status_cel_proj'' and option_key in(''aguardando_coleta'',''coletado''))' else '' end;
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %s %s) r',t.projection,t.name,condition) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: installation rewrote old data: %',t.name;end if;
 end loop;
 for t in select * from csu_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and p.proname=t.name and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner) then raise exception 'FAIL: old function OID/ACL/owner changed: %',t.name;end if;
  if t.name not in('web_mutate_project_core_v1','update_cell_status_v1') and pg_get_functiondef(t.id) is distinct from t.definition then raise exception 'FAIL: unrelated function changed: %',t.name;end if;
 end loop;
 if exists(select 1 from csu_catalog c where c.kind='policy' and not exists(select 1 from pg_policy p where p.oid=c.id and to_jsonb(p)=c.value)) or exists(select 1 from csu_catalog c where c.kind='trigger' and not exists(select 1 from pg_trigger p where p.oid=c.id and to_jsonb(p)=c.value)) or exists(select 1 from csu_catalog c where c.kind='constraint' and not exists(select 1 from pg_constraint p where p.oid=c.id and to_jsonb(p)=c.value)) then raise exception 'FAIL: old catalog contract changed';end if;
 perform pg_temp.csu_check((select count(*)=12 from public.rm_option_sets where option_set_key='status_cel_proj'),'only two new options were seeded');
end$$;
set local role authenticated;
select pg_temp.csu_check((pg_temp.csu_warm_web(pg_temp.csu_id('e',1),(select payload from csu_payloads where id=pg_temp.csu_id('e',1)))->>'idempotent_replay')::boolean,'warmed old web receipt replays');
select pg_temp.csu_warm_web(pg_temp.csu_id('e',2),(select payload from csu_payloads where id=pg_temp.csu_id('e',2)));
select pg_temp.csu_check((pg_temp.csu_warm_mobile(pg_temp.csu_id('d',1),jsonb_build_object('p_celula_projeto_id',pg_temp.csu_id('6',1),'p_status','em_dia'))->>'idempotent_replay')::boolean,'warmed old mobile receipt replays');
select pg_temp.csu_check(pg_temp.csu_warm_mobile(pg_temp.csu_id('d',2),jsonb_build_object('p_celula_projeto_id',pg_temp.csu_id('6',1),'p_status','coletado'))->>'status'='coletado','warm mobile caller reaches shared writer with new enum');
reset role;
rollback;
\i :rm_migration_042_path
select 'PASS: status upgrade preserves all old rows/functions/contracts, existing receipts, warm callers and pre-issued SSO permits' result;

-- TEST DATABASE ONLY: 024 -> 025 preserves every existing row, old quantity
-- receipts and cached dispatcher/capture callers in the same database session.
\set ON_ERROR_STOP on
begin;
create schema rm_test_operational_upgrade;
create table rm_test_operational_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1b700000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values('2b700000-0000-4000-8000-000000000001','1b700000-0000-4000-8000-000000000001','Operational upgrade planner','administrador');
insert into public.rm_projetos(id,numero) values('5b700000-0000-4000-8000-000000000001','OPERATIONAL-UPGRADE-25');
insert into public.rm_celulas(id,nome) values('4b700000-0000-4000-8000-000000000001','Operational upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,indice,posicao)
 values('6b700000-0000-4000-8000-000000000001','5b700000-0000-4000-8000-000000000001','4b700000-0000-4000-8000-000000000001',null,17);
insert into public.rm_tipos_equipamento(id,nome) values('bb700000-0000-4000-8000-000000000001','Operational upgrade type');
insert into public.rm_cadastro_fotos(id,titulo) values('ab700000-0000-4000-8000-000000000001','Operational upgrade title');
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,lixeira)
 values('cb700000-0000-4000-8000-000000000001','5b700000-0000-4000-8000-000000000001','4b700000-0000-4000-8000-000000000001','6b700000-0000-4000-8000-000000000001','obrigat_ria','Preexisting retired ID',true),
 ('cb700000-0000-4000-8000-000000000002','5b700000-0000-4000-8000-000000000001','4b700000-0000-4000-8000-000000000001','6b700000-0000-4000-8000-000000000001','obrigat_ria','Warm active slot',false);
select set_config('request.jwt.claim.sub','1b700000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('operational-upgrade-mobile','sha256'),'1b700000-0000-4000-8000-000000000001','2b700000-0000-4000-8000-000000000001','2b700000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
do $$ declare p jsonb; begin
 p:=jsonb_build_object('id','db700000-0000-4000-8000-000000000001','celula_id','4b700000-0000-4000-8000-000000000001',
  'tipo_equipamento_id','bb700000-0000-4000-8000-000000000001','expected_updated_at',null,'changes',jsonb_build_object('numero_fotos',77));
 set local role authenticated; perform public.rm_web_mutate_v1('fb700000-0000-4000-8000-000000000001','save_engineering',p);
 perform public.rm_mobile_mutate_v1('fb700000-0000-4000-8000-000000000002','rm_record_cell_photo_v1',
  '{"p_foto_id":"cb700000-0000-4000-8000-000000000002","p_foto_url":"https://example.invalid/warm.jpg"}', 'operational-upgrade-mobile'); reset role;
end $$;
do $$ declare t record; total bigint; digest text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname) into total,digest;
  insert into rm_test_operational_upgrade.snapshots values(t.nspname||'.'||t.relname,total,digest);
 end loop;
 if (select count(*) from rm_test_operational_upgrade.snapshots where split_part(name,'.',1)='public')<>56
  or (select count(*) from rm_test_operational_upgrade.snapshots where split_part(name,'.',1)='rm_private')<>11
  or (select count(*) from rm_test_operational_upgrade.snapshots)<>67 then raise exception 'FAIL: expected all 67 RM/private snapshots'; end if;
 if to_regprocedure('rm_private.web_mutate_project_route_core_v1(uuid,text,jsonb)') is not null then raise exception 'FAIL: predecessor name unavailable'; end if;
end $$;
commit;
\ir ../migrations/025_rm_web_operational_photos.sql
begin;
do $$ declare t record; total bigint; digest text; p jsonb; r jsonb; s jsonb; message text; begin
 for t in select * from rm_test_operational_upgrade.snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name) into total,digest;
  if total<>t.rows or digest<>t.hash then raise exception 'FAIL: operational installation changed old rows: %',t.name; end if;
 end loop;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fb700000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fb700000-0000-4000-8000-000000000001','save_engineering',p); reset role;
 if not (r->>'idempotent_replay')::boolean or (select numero_fotos<>77 from public.rm_celula_tipos_equipamento where id='db700000-0000-4000-8000-000000000001') then raise exception 'FAIL: old quantity receipt or historical value lost'; end if;
 begin set local role authenticated; perform public.rm_web_mutate_v1(gen_random_uuid(),'save_engineering',p); raise exception 'FAIL: new retired quantity command';
 exception when invalid_parameter_value then get stacked diagnostics message=message_text; reset role; end;
 if message not like '%Quantidade prevista de fotos foi removida%' then raise exception 'FAIL: wrong quantity rejection: %',message; end if;
 s:=public.rm_web_operational_photos_snapshot_v1('5b700000-0000-4000-8000-000000000001','6b700000-0000-4000-8000-000000000001',true);
 p:=jsonb_build_object('action','add','projeto_id',s->'project'->>'id','celula_projeto_id',s->'allocation'->>'id','expected_project_updated_at',s->'project'->>'updated_at',
  'expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_photos_version',s->>'photos_version','items',jsonb_build_array(jsonb_build_object('id','eb700000-0000-4000-8000-000000000001','cadastro_foto_id','ab700000-0000-4000-8000-000000000001')));
 set local role authenticated; r:=public.rm_web_mutate_v1('fb700000-0000-4000-8000-000000000003','manage_operational_photos',p); reset role;
 if r->>'operation'<>'manage_operational_photos' or jsonb_array_length(r->'record'->'changed_ids')<>1 then raise exception 'FAIL: warmed wrapper missed new dispatcher'; end if;
 set local role authenticated; r:=public.rm_web_mutate_v1('fb700000-0000-4000-8000-000000000003','manage_operational_photos',p); reset role;
 if not (r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed new operation replay'; end if;
 begin set local role authenticated; perform public.rm_mobile_mutate_v1('fb700000-0000-4000-8000-000000000004','rm_record_cell_photo_v1',
   '{"p_foto_id":"cb700000-0000-4000-8000-000000000001","p_foto_url":"https://example.invalid/late.jpg"}','operational-upgrade-mobile');
  raise exception 'FAIL: warm mobile wrapper missed retirement guard'; exception when sqlstate 'PT409' then reset role; end;
 if (select not lixeira or foto_url is not null from public.rm_fotos where id='cb700000-0000-4000-8000-000000000001') then raise exception 'FAIL: warm mobile restored retired slot'; end if;
 set local role authenticated; r:=public.rm_mobile_mutate_v1('fb700000-0000-4000-8000-000000000002','rm_record_cell_photo_v1',
  '{"p_foto_id":"cb700000-0000-4000-8000-000000000002","p_foto_url":"https://example.invalid/warm.jpg"}','operational-upgrade-mobile'); reset role;
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: old completed capture receipt lost'; end if;
end $$;
rollback;
begin;
delete from rm_private.mobile_mutation_receipts where auth_user_id='1b700000-0000-4000-8000-000000000001';
delete from rm_private.web_mutation_receipts where auth_user_id='1b700000-0000-4000-8000-000000000001';
delete from rm_private.operator_delegations where auth_user_id='1b700000-0000-4000-8000-000000000001';
delete from public.rm_fotos where projeto_id='5b700000-0000-4000-8000-000000000001';
delete from public.rm_celula_tipos_equipamento where id='db700000-0000-4000-8000-000000000001';
delete from public.rm_celulas_projeto where projeto_id='5b700000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5b700000-0000-4000-8000-000000000001';
delete from public.rm_cadastro_fotos where id='ab700000-0000-4000-8000-000000000001';
delete from public.rm_celulas where id='4b700000-0000-4000-8000-000000000001';
delete from public.rm_tipos_equipamento where id='bb700000-0000-4000-8000-000000000001';
delete from public.rm_users where id='2b700000-0000-4000-8000-000000000001';
delete from auth.users where id='1b700000-0000-4000-8000-000000000001';
drop schema rm_test_operational_upgrade cascade;
commit;
select 'PASS: 025 preserves 67 full snapshots, historical quantity and receipts; warmed web/mobile callers reach new dispatcher and offline retirement guard' as result;

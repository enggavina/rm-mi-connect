\set ON_ERROR_STOP on
begin;
create function pg_temp.ws_key(n integer) returns uuid language sql immutable as $$select ('04800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.ws_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.ws_actor(n int,aal text default 'aal1') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.ws_key(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ws_key(n),'role','authenticated','aal',aal)::text,true);
end$$;
create function pg_temp.ws_read(n int,aal text default 'aal1') returns jsonb language plpgsql as $$declare r jsonb;begin
 perform pg_temp.ws_actor(n,aal);set local role authenticated;r:=public.rm_web_workshop_snapshot_v1();reset role;return r;
exception when others then reset role;raise;end$$;
create function pg_temp.ws_deny(n int,aal text default 'aal1') returns void language plpgsql as $$begin
 begin perform pg_temp.ws_read(n,aal);exception when insufficient_privilege then return;end;
 raise exception 'FAIL: forbidden actor read workshop';
end$$;

insert into auth.users(id) select pg_temp.ws_key(n) from generate_series(1,6)n;
insert into public.rm_users(id,auth_user_id,nome,email,matricula,perfil,status) select pg_temp.ws_key(10+n),pg_temp.ws_key(n),'WS actor '||n,'private-'||n||'@invalid.test','PRIVATE-'||n,
 case n when 1 then 'administrador'::public.rm_perfil_usuario_enum when 2 then 'padr_o' when 3 then 'auditor' when 4 then 'mobile' else 'administrador' end,
 case when n=5 then 'inativo'::public.rm_status_user_enum else 'ativo' end from generate_series(1,5)n;
create temporary table ws_baseline on commit drop as select pg_temp.ws_read(1) snapshot;
insert into public.rm_clientes(id,nome) values(pg_temp.ws_key(30),'Workshop client');
insert into public.rm_tipos_equipamento(id,nome) values(pg_temp.ws_key(31),'Motor canonical'),(pg_temp.ws_key(32),'Legacy generator');
insert into public.rm_celulas(id,nome,ordem) values(pg_temp.ws_key(40),'Empty cell',1),(pg_temp.ws_key(41),'Working cell',2);
insert into public.rm_projetos(id,numero,nome,cliente_id,gestor_responsavel_id,tipo_equipamento_id,status_pcp,chegada_do_equipamento,data_prevista_final,nota_fiscal,contato)
select pg_temp.ws_key(100+n),'WS-048-'||n,'Workshop fixture '||n,pg_temp.ws_key(30),pg_temp.ws_key(11),pg_temp.ws_key(32),
 case n when 2 then 'cancelado'::public.rm_status_pcp_enum when 3 then 'finalizando_para_faturar' when 4 then 'aguardando_recebimento_equipamento'
  when 5 then 'sem_status' when 6 then null else 'executando' end,
 case when n=7 then null when n=8 then (((statement_timestamp() at time zone 'America/Sao_Paulo')::date+1)+time '00:01') at time zone 'America/Sao_Paulo'
  when n=9 then (((statement_timestamp() at time zone 'America/Sao_Paulo')::date)+time '23:59') at time zone 'America/Sao_Paulo'
  else statement_timestamp()-interval '1 day' end,
 '2026-11-30T18:25:12.123456Z','PRIVATE-INVOICE','PRIVATE-CONTACT' from generate_series(1,12)n;
update public.rm_projetos set data_real_de_entrega=statement_timestamp() where id=pg_temp.ws_key(110);
insert into public.rm_equipamentos(id,projeto_id,tipo_equipamento_id,descricao,fabricante,modelo,numero_serie,potencia) values
 (pg_temp.ws_key(201),pg_temp.ws_key(101),pg_temp.ws_key(31),'Canonical motor','Workshop','M75','DEMO-048','75 kW'),
 (pg_temp.ws_key(211),pg_temp.ws_key(111),null,'No classified type','Workshop','Unknown','DEMO-UNKNOWN',null);
update public.rm_projetos set equipamento_id=pg_temp.ws_key(201) where id=pg_temp.ws_key(101);
update public.rm_projetos set equipamento_id=pg_temp.ws_key(211),tipo_equipamento_id=null where id=pg_temp.ws_key(111);
update public.rm_projetos set tipo_equipamento_id=null where id=pg_temp.ws_key(112);
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,bloqueada,visibilidade,data_inicio,data_limite,horas_previstas,horas_realizadas,responsavel_id)
values(pg_temp.ws_key(301),pg_temp.ws_key(101),pg_temp.ws_key(41),'em_dia',null,false,'2026-11-16T14:00:00.123456Z','2026-11-20T18:30:59.987654Z',8.50,2.25,pg_temp.ws_key(12));
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,retirada,visibilidade) values
 (pg_temp.ws_key(302),pg_temp.ws_key(102),pg_temp.ws_key(41),'em_dia',false,true),
 (pg_temp.ws_key(303),pg_temp.ws_key(109),pg_temp.ws_key(41),'pendente',true,false),
 (pg_temp.ws_key(304),pg_temp.ws_key(111),pg_temp.ws_key(41),'finalizado',false,true);

-- Snapshot is a reader: even internal receipts/private metadata remain untouched.
create temporary table ws_before(t text,n bigint,digest text) on commit drop;
do $$declare r record;begin
 for r in select n.nspname schema_name,c.relname table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and(n.nspname='rm_private' or(n.nspname='public' and c.relname like 'rm\_%' escape '\')) loop
  execute format('insert into ws_before select %L,count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by md5(to_jsonb(x)::text)),'''')) from %I.%I x',r.schema_name||'.'||r.table_name,r.schema_name,r.table_name);
 end loop;
end$$;
do $$declare s jsonb;p jsonb;a jsonb;begin
 s:=pg_temp.ws_read(1);
 perform pg_temp.ws_check((s->>'project_count')::int=(select(snapshot->>'project_count')::int+4 from ws_baseline) and jsonb_array_length(s->'projects')=(s->>'project_count')::int,'bounded complete project cohort');
 perform pg_temp.ws_check((s->>'allocation_count')::int=(select(snapshot->>'allocation_count')::int+2 from ws_baseline) and jsonb_array_length(s->'allocations')=(s->>'allocation_count')::int,'nonretired allocations for selected cohort, including hidden and finished');
 perform pg_temp.ws_check((s->>'cell_count')::int=(select(snapshot->>'cell_count')::int+2 from ws_baseline) and jsonb_array_length(s->'cells')=(s->>'cell_count')::int,'all cells, including zero work');
 perform pg_temp.ws_check(exists(select 1 from jsonb_array_elements(s->'projects') x where x->>'id'=pg_temp.ws_key(109)::text),'same Sao Paulo calendar day future instant included');
 perform pg_temp.ws_check(not exists(select 1 from jsonb_array_elements(s->'projects') x where x->>'id'=any(array[pg_temp.ws_key(102),pg_temp.ws_key(103),pg_temp.ws_key(104),pg_temp.ws_key(105),pg_temp.ws_key(106),pg_temp.ws_key(107),pg_temp.ws_key(108),pg_temp.ws_key(110)]::text[])),'excluded statuses, missing/future arrival, delivered');
 select x into p from jsonb_array_elements(s->'projects')x where x->>'id'=pg_temp.ws_key(101)::text;
 perform pg_temp.ws_check(p->>'equipamento_tipo'='Motor canonical' and (p->>'equipment_binding')::boolean and p->>'equipamento_descricao'='Canonical motor','canonical type overrides legacy type');
 perform pg_temp.ws_check((p->>'data_prevista_final')::timestamptz='2026-11-30T18:25:12.123456Z'::timestamptz,'project timestamp microseconds preserved');
 select x into p from jsonb_array_elements(s->'projects')x where x->>'id'=pg_temp.ws_key(111)::text;
 perform pg_temp.ws_check(p->'equipamento_tipo'='null'::jsonb and(p->>'equipment_binding')::boolean,'unknown classified equipment remains unknown');
 select x into p from jsonb_array_elements(s->'projects')x where x->>'id'=pg_temp.ws_key(112)::text;
 perform pg_temp.ws_check(p->'equipamento_tipo'='null'::jsonb and not(p->>'equipment_binding')::boolean,'missing equipment remains generic');
 select x into a from jsonb_array_elements(s->'allocations')x where x->>'id'=pg_temp.ws_key(301)::text;
 perform pg_temp.ws_check(a->'bloqueada'='null'::jsonb and a->>'horas_previstas'='8.50' and a->>'horas_realizadas'='2.25','nullable blocked and decimal hour strings preserved');
 perform pg_temp.ws_check((a->>'data_inicio')::timestamptz='2026-11-16T14:00:00.123456Z'::timestamptz and(a->>'data_limite')::timestamptz='2026-11-20T18:30:59.987654Z'::timestamptz,'allocation timestamps preserved');
 perform pg_temp.ws_check(s::text not like '%PRIVATE-%' and not(s::text like '%auth_user_id%' or s::text like '%email%' or s::text like '%nota_fiscal%' or s::text like '%contato%'),'no contact, invoice, email, matricula or auth identities');
 perform pg_temp.ws_check(pg_temp.ws_read(2)->>'project_count'=s->>'project_count' and pg_temp.ws_read(3)->>'project_count'=s->>'project_count','standard and auditor readers allowed');
 perform pg_temp.ws_deny(4);perform pg_temp.ws_deny(5);perform pg_temp.ws_deny(6);
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.ws_key(1),'totp','verified');
 perform pg_temp.ws_deny(1);perform pg_temp.ws_check(pg_temp.ws_read(1,'aal2')->>'project_count'=s->>'project_count','MFA enforced, aal2 accepted');
 delete from auth.mfa_factors where user_id=pg_temp.ws_key(1);
 begin set local role anon;perform public.rm_web_workshop_snapshot_v1();raise exception 'FAIL anonymous reader';exception when insufficient_privilege then reset role;end;
 perform pg_temp.ws_check(not has_function_privilege('anon','public.rm_web_workshop_snapshot_v1()','EXECUTE') and not has_function_privilege('service_role','public.rm_web_workshop_snapshot_v1()','EXECUTE'),'no anon/service direct execution');
end$$;
do $$declare r record;n bigint;d text;begin for r in select * from ws_before loop
 execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by md5(to_jsonb(x)::text)),'''')) from %s x',r.t)into n,d;
 if n<>r.n or d<>r.digest then raise exception 'Snapshot modified %',r.t;end if;
end loop;end$$;
-- Counts exceeding the complete-snapshot limit must fail, never truncate.
insert into public.rm_projetos(id,numero,status_pcp,chegada_do_equipamento)
 select pg_temp.ws_key(10000+n),'WS-LIMIT-'||n,'executando',statement_timestamp()-interval '1 day' from generate_series(1,2001)n;
do $$begin
 begin perform pg_temp.ws_read(1);exception when sqlstate 'PT413' then return;end;
 raise exception 'FAIL oversized workshop returned a partial snapshot';
end$$;
rollback;
\echo 'Workshop snapshot contract passed'

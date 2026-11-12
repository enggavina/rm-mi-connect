\set ON_ERROR_STOP on
\if :{?rm_migration_041_path}
\else
\quit 3
\endif
select set_config('rm.test.migration_041_path',:'rm_migration_041_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required';end if;end$$;
create temporary table cs_enum_before as select e.oid,e.enumtypid,e.enumsortorder,e.enumlabel from pg_enum e where enumtypid='public.rm_status_cel_proj_enum'::regtype;
create temporary table cs_option_before as select * from public.rm_option_sets;
create temporary table cs_columns_before as select a.attrelid,a.attnum,to_jsonb(a) value from pg_attribute a where attrelid='public.rm_celulas_projeto'::regclass;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_041_path'));begin
 if(select count(*) from cs_enum_before)<>10 then raise exception 'Unexpected old enum';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
 if exists(select 1 from cs_enum_before b where not exists(select 1 from pg_enum e where e.oid=b.oid and e.enumtypid=b.enumtypid and e.enumsortorder=b.enumsortorder and e.enumlabel=b.enumlabel)) then raise exception 'FAIL: old enum identity/order changed';end if;
 if(select array_agg(enumlabel::text order by enumsortorder) from pg_enum where enumtypid='public.rm_status_cel_proj_enum'::regtype) is distinct from array['pendente','retornado','liberado_para_ensaios_parciais','liberado_para_impregna__o','liberado_para_montagem','para_execu__o','em_dia','finalizado','atrasado','n_a','aguardando_coleta','coletado'] then raise exception 'FAIL: status extension differs';end if;
 if exists((select * from cs_option_before except select * from public.rm_option_sets) union all(select * from public.rm_option_sets except select * from cs_option_before))
 or exists(select 1 from cs_columns_before b where not exists(select 1 from pg_attribute a where a.attrelid=b.attrelid and a.attnum=b.attnum and to_jsonb(a)=b.value)) then raise exception 'FAIL: enum phase changed old data or columns';end if;
end$$;
rollback;
\i :rm_migration_041_path
select 'PASS: enum phase appends two values while preserving all ten previous OIDs/order and allocation columns/catalog' result;

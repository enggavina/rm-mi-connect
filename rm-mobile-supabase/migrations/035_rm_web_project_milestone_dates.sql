-- Optional calendar days, independent for inspection and repair. Existing
-- project records and all older clients remain unchanged on installation.
begin;

alter table public.rm_projetos
  add column data_inicio_peritagem date,
  add column data_fim_peritagem date,
  add column data_inicio_reparo date,
  add column data_fim_reparo date,
  add constraint rm_project_peritagem_dates_check check (data_inicio_peritagem <= data_fim_peritagem),
  add constraint rm_project_reparo_dates_check check (data_inicio_reparo <= data_fim_reparo);

-- Preserve the existing authentication, SSO permit, actor, receipt, locking,
-- conflict and operation rules. Unspecified fields keep their current value.
do $$
declare
  definition text;
  marker text;
begin
  definition := pg_get_functiondef('rm_private.web_mutate_project_core_v1(uuid,text,jsonb)'::regprocedure);
  marker := '''data_prevista_inicio'',''data_prevista_final'',''data_contratual'',''data_renegociada'',''replanejamento_motivo''';
  if (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 then raise exception 'Unexpected project field allowlist'; end if;
  definition := replace(definition, marker, marker || ',''data_inicio_peritagem'',''data_fim_peritagem'',''data_inicio_reparo'',''data_fim_reparo''');

  marker := '    next_project := jsonb_populate_record(project,changes);';
  if (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 then raise exception 'Unexpected project record population'; end if;
  definition := replace(definition, marker, $patch$
    -- Reject PostgreSQL's permissive date inputs, including "today", infinity,
    -- numbers, timestamps and year zero, even on direct RPC calls.
    if exists(select 1 from unnest(array['data_inicio_peritagem','data_fim_peritagem','data_inicio_reparo','data_fim_reparo']) d(field)
      where changes ? d.field and (jsonb_typeof(changes->d.field) not in ('string','null')
        or (jsonb_typeof(changes->d.field)='string' and ((changes->>d.field) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          or left(changes->>d.field,4)='0000')))) then
      raise exception 'Informe datas de calendário válidas.' using errcode='22023'; end if;
$patch$ || marker);

  marker := 'data_renegociada=next_project.data_renegociada,replanejamento_motivo=next_project.replanejamento_motivo,sync_source=''supabase''';
  if (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 then raise exception 'Unexpected project update assignments'; end if;
  definition := replace(definition, marker, 'data_renegociada=next_project.data_renegociada,replanejamento_motivo=next_project.replanejamento_motivo,' ||
    'data_inicio_peritagem=next_project.data_inicio_peritagem,data_fim_peritagem=next_project.data_fim_peritagem,' ||
    'data_inicio_reparo=next_project.data_inicio_reparo,data_fim_reparo=next_project.data_fim_reparo,sync_source=''supabase''');
  execute definition;
end $$;

notify pgrst,'reload schema';
commit;

-- Publish every table consumed by the native incremental pull. The original 004
-- published execution records only, so edited form definitions and photo titles
-- did not notify tablets until their next scheduled pull.
begin;
do $$
declare t text;
begin
  if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
    return;
  end if;
  foreach t in array array[
    'rm_clientes','rm_users','rm_tipos_equipamento','rm_celulas',
    'rm_tablet_celula_users','rm_celula_tipos_equipamento',
    'rm_celula_form_tipos_equipamento','rm_forms','rm_questoes',
    'rm_itens_questoes','rm_projetos','rm_equipamentos',
    'rm_celulas_projeto','rm_fotos','rm_registros_formulario',
    'rm_respostas','rm_aprovacoes_etapas'
  ] loop
    if not exists(select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;
commit;

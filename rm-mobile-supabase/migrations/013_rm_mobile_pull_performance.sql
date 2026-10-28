-- The authenticated initial pull timed out at 8s after 61,803 historical answers.
-- Keep the same read authorization; evaluate its row-independent result once and
-- index the exact (updated_at,id) order used by the native incremental cursor.
begin;
do $migration$
declare t text; p record;
begin
  foreach t in array array[
    'rm_clientes','rm_users','rm_tipos_equipamento','rm_celulas',
    'rm_tablet_celula_users','rm_celula_tipos_equipamento',
    'rm_celula_form_tipos_equipamento','rm_forms','rm_questoes',
    'rm_itens_questoes','rm_projetos','rm_equipamentos','rm_celulas_projeto',
    'rm_fotos','rm_registros_formulario','rm_respostas','rm_aprovacoes_etapas',
    'rm_comentarios','rm_logs_aprovacao','rm_documentos','rm_docs','rm_cadastro_fotos'
  ] loop
    execute format('create index if not exists %I on public.%I (updated_at,id)', 'idx_'||t||'_mobile_cursor',t);
    -- Only this exact, row-independent SELECT policy is eligible. Do not rewrite
    -- operator/cell predicates, write policies, roles or granted privileges.
    for p in select policyname from pg_policies where schemaname='public' and tablename=t
      and cmd='SELECT' and qual='rm_private.is_rm_authenticated()'
    loop
      execute format('alter policy %I on public.%I using ((select rm_private.is_rm_authenticated()))',p.policyname,t);
    end loop;
    execute format('analyze public.%I',t);
  end loop;
end $migration$;
notify pgrst,'reload schema';
commit;

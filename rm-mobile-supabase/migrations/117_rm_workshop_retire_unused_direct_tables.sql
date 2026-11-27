begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Server routines and service-role imports remain the consumers of these
-- tables. The native sync contract and portal direct fallbacks use other tables.
revoke all privileges on table
 public.rm_componentes_os,
 public.rm_contatos_clientes,
 public.rm_devices,
 public.rm_elementos_permissao,
 public.rm_ensaios_eletricos_laboratorio,
 public.rm_equipes,
 public.rm_escopo_rm,
 public.rm_eventos_api,
 public.rm_eventos_sistema,
 public.rm_fichas_delineamento,
 public.rm_fichas_desmontagem,
 public.rm_form_template_families,
 public.rm_itens_ficha_delineamento,
 public.rm_materiais,
 public.rm_notificacoes,
 public.rm_numeracoes,
 public.rm_ordens_servico,
 public.rm_pecas_rm,
 public.rm_precificacao_orcamentaria,
 public.rm_project_document_folders,
 public.rm_project_document_locations,
 public.rm_propostas_budgetarias,
 public.rm_propostas_controle,
 public.rm_respostas_temp,
 public.rm_solicitacoes_suporte,
 public.rm_sync_outbox,
 public.rm_tablets,
 public.rm_templates_proposta,
 public.rm_templates_word,
 public.rm_vendedores_clientes,
 public.rm_web_stage_decisions
 from public,anon,authenticated;

notify pgrst,'reload schema';
commit;

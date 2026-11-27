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
 public.rm_propostas_budgetarias,
 public.rm_propostas_controle,
 public.rm_respostas_temp,
 public.rm_solicitacoes_suporte,
 public.rm_sync_outbox,
 public.rm_tablets,
 public.rm_templates_proposta,
 public.rm_templates_word,
 public.rm_vendedores_clientes
 from public,anon,authenticated;

-- A fresh installation may still use the pre-cutover review and dossier APIs.
-- Retire their underlying grants when that API is retired, including sites
-- that had already switched to the office-scoped gateways before this release.
do $cutovers$
declare
 review text:=pg_get_functiondef('rm_private.activate_workshop_review_cutover_v1()'::regprocedure);
 dossier text:=pg_get_functiondef('rm_private.activate_workshop_project_dossier_v1()'::regprocedure);
 review_marker constant text:=' revoke select on rm_private.web_stage_approval_context_v1 from authenticated;';
 dossier_marker constant text:=' notify pgrst,''reload schema'';';
 review_grants constant text:='revoke all privileges on table public.rm_web_stage_decisions from public,anon,authenticated;';
 dossier_grants constant text:='revoke all privileges on table public.rm_project_document_folders,public.rm_project_document_locations from public,anon,authenticated;';
begin
 if array_length(string_to_array(review,review_marker),1) is distinct from 2
  or array_length(string_to_array(dossier,dossier_marker),1) is distinct from 2 then
  raise exception 'Unexpected legacy review or dossier activation contract';
 end if;
 execute replace(review,review_marker,review_marker||chr(10)||' '||review_grants);
 execute replace(dossier,dossier_marker,' '||dossier_grants||chr(10)||dossier_marker);
 if exists(select 1 from rm_private.form_review_workshop_settings where singleton and enforced)
  and not has_function_privilege('authenticated','public.rm_web_stage_approval_snapshot_v1(uuid)','execute') then
  execute review_grants;
 end if;
 if exists(select 1 from rm_private.workshop_dossier_settings where singleton and enforced)
  and not has_function_privilege('authenticated','public.rm_web_project_documents_v1(uuid,jsonb)','execute') then
  execute dossier_grants;
 end if;
end
$cutovers$;

notify pgrst,'reload schema';
commit;

-- ============================================================================
-- MIGRATION 001: RM (Revisão de Motores) - Schemas, Option Sets & Enums
-- Origem: Auditoria completa do app Bubble "rmmi" (foco rm_mobile)
-- Destino: PostgreSQL / Supabase (Opção B - Migração Direta + Sync Temporário)
-- ============================================================================

begin;

create extension if not exists pgcrypto;

-- Schema privado para credenciais sensíveis, funções internas e controle de sync
create schema if not exists rm_private;
revoke all on schema rm_private from public, anon, authenticated;

-- ============================================================================
-- 1. CATÁLOGO UNIVERSAL DE OPTION SETS DO BUBBLE
-- Preserva chave interna (bubble_key), texto de exibição (bubble_display) e
-- atributos extras para tradução bidirecional sem perda (Supabase <-> Bubble).
-- ============================================================================

create table if not exists public.rm_option_sets (
  option_set_key text not null,
  option_key text not null,
  bubble_display text not null,
  attributes jsonb not null default '{}'::jsonb,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  primary key (option_set_key, option_key)
);

create index if not exists idx_rm_option_sets_display
  on public.rm_option_sets (option_set_key, bubble_display);

-- ============================================================================
-- 2. TIPOS ENUMERADOS (ENUMS) ESSENCIAIS AO DOMÍNIO RM / RM_MOBILE
-- Usam as chaves internas canônicas do Bubble para integridade referencial
-- ============================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'rm_status_user_enum') then
    create type public.rm_status_user_enum as enum ('ativo', 'inativo');
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_perfil_usuario_enum') then
    create type public.rm_perfil_usuario_enum as enum (
      'cliente',
      'auditor',
      'vendedor',
      'mobile',
      'padr_o',
      'administrador'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_perfil_assinante_enum') then
    -- Nota de auditoria: 'aprovador' exibe como 'Verificador' no Bubble
    create type public.rm_perfil_assinante_enum as enum (
      'testador',
      'aprovador',
      'aprovador_supervis_o'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_sim_nao_enum') then
    create type public.rm_sim_nao_enum as enum ('sim', 'n_o');
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_placa_motor_enum') then
    create type public.rm_placa_motor_enum as enum ('c___placa', 's___placa');
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_rm_enum') then
    create type public.rm_status_rm_enum as enum (
      'requisi__o',
      'peritagem',
      'calculo',
      'proposta'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_pcp_enum') then
    -- Nota de auditoria: 'revis_o_comercial' e 'revis_o_comercial0' possuem o mesmo Display "Revisão comercial"
    create type public.rm_status_pcp_enum as enum (
      'equipamento_inspecionado',
      'executando',
      'aguardando_aprova__o',
      'sem_status',
      'revis_o_comercial',
      'finalizando_para_faturar',
      'susponso__hold_',
      'aguardando_recebimento_equipamento',
      'revis_o_comercial0',
      'equipamento_em_inspe__o',
      'sem_previs_o',
      'investiga__o_de_garantia',
      'executando_com_garantia',
      'cancelado'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_cel_proj_enum') then
    -- Nota de auditoria: 'em_dia' exibe como 'Executando' no Bubble
    create type public.rm_status_cel_proj_enum as enum (
      'pendente',
      'retornado',
      'liberado_para_ensaios_parciais',
      'liberado_para_impregna__o',
      'liberado_para_montagem',
      'para_execu__o',
      'em_dia',
      'finalizado',
      'atrasado',
      'n_a'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_etapa_enum') then
    -- Nota de auditoria: 'reprovado' exibe como 'Retornado' no Bubble
    create type public.rm_status_etapa_enum as enum (
      'aprovado',
      'reprovado',
      'nulo'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_prioridade_cel_enum') then
    create type public.rm_prioridade_cel_enum as enum (
      'muito_baixa',
      'baixa',
      'media',
      'alta',
      'muito_alta'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_registro_enum') then
    -- Nota de auditoria: 'direcionado' exibe como 'Revisar' no Bubble
    create type public.rm_status_registro_enum as enum (
      'em_an_lise',
      'direcionado',
      'aprovado'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_tipo_questao_enum') then
    create type public.rm_tipo_questao_enum as enum (
      'texto_curto',
      'texto_longo',
      'escolha__nica',
      'caixas_de_sele__o',
      'lista_suspensa',
      'lista_multi_sele__o',
      'foto',
      'foto_antes_depois',
      'data',
      'hora',
      'subt_tulo',
      'colaborador',
      'assinatura',
      'cliente',
      'numero'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_subtipo_questao_enum') then
    create type public.rm_subtipo_questao_enum as enum (
      'intervalo_de_datas',
      'intervalo_de_hor_rios'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_dimensao_enum') then
    create type public.rm_dimensao_enum as enum (
      '_hmico',
      'ceusus',
      'mili_ohms',
      'mega_ohms',
      'volts',
      'kilowatts',
      'amperes',
      'rota__es_por_minuto',
      'hertz',
      'porcentagem',
      'kilo_ohms',
      'watts',
      'cent_metro',
      'dec_metro',
      'metro',
      'mil_metro',
      'mili_amperes',
      'centimetros_c_bicos',
      'micr_metros',
      'milimetros_por_segundo'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_categoria_foto_enum') then
    create type public.rm_categoria_foto_enum as enum (
      'obrigat_ria',
      'complementar'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_etapa_foto_enum') then
    create type public.rm_etapa_foto_enum as enum ('recebimento');
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_tipo_foto_recebimento_enum') then
    create type public.rm_tipo_foto_recebimento_enum as enum (
      'lateral_direita',
      'lateral_esquerda',
      'frente',
      'vista_superior',
      'placa',
      'antes_de_descarregar',
      'embalagem',
      'em_cima_do_caminh_o_lonado'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_tipo_formulario_enum') then
    create type public.rm_tipo_formulario_enum as enum (
      'ordem_de_servico',
      'teste_eletrico_inicial',
      'teste_eletrico_final',
      'ficha_delineamento'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_origem_notificacao_enum') then
    create type public.rm_origem_notificacao_enum as enum (
      'formul_rio',
      'registros',
      'avalia__o',
      'usu_rio',
      'login'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_tipo_evento_sistema_enum') then
    create type public.rm_tipo_evento_sistema_enum as enum (
      'altera__o_de_senha',
      'login',
      'identidade'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_processo_enum') then
    create type public.rm_status_processo_enum as enum (
      'em_processamento',
      'processado',
      'n_o_processado'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'rm_status_atividade_enum') then
    create type public.rm_status_atividade_enum as enum (
      'em_andamento',
      'finalizado',
      'n_o_iniciado',
      'em_espera'
    );
  end if;
end
$$;

-- ============================================================================
-- 3. CARGA COMPLETA DOS OPTION SETS (SEED PARA TRADUÇÃO BUBBLE <-> SUPABASE)
-- ============================================================================

insert into public.rm_option_sets (option_set_key, option_key, bubble_display, attributes, sort_order)
values
  -- Status User (option.status)
  ('status', 'ativo', 'Ativo', '{}', 1),
  ('status', 'inativo', 'Inativo', '{}', 2),

  -- Perfil Usuário (option.tipo_de_usu_rio)
  ('tipo_de_usu_rio', 'cliente', 'Cliente', '{}', 1),
  ('tipo_de_usu_rio', 'auditor', 'Auditor', '{}', 2),
  ('tipo_de_usu_rio', 'vendedor', 'Vendedor', '{}', 3),
  ('tipo_de_usu_rio', 'mobile', 'Mobile', '{}', 4),
  ('tipo_de_usu_rio', 'padr_o', 'Padrão', '{}', 5),
  ('tipo_de_usu_rio', 'administrador', 'Administrador', '{}', 6),

  -- Perfil assinante (option.perfil_assinante)
  ('perfil_assinante', 'testador', 'Testador', '{}', 1),
  ('perfil_assinante', 'aprovador', 'Verificador', '{}', 2),
  ('perfil_assinante', 'aprovador_supervis_o', 'Aprovador supervisão', '{}', 3),

  -- Sim ou Nao (option.sim_ou_nao)
  ('sim_ou_nao', 'sim', 'Sim', '{}', 1),
  ('sim_ou_nao', 'n_o', 'Não', '{}', 2),

  -- Placa_motor (option.placa_motor)
  ('placa_motor', 'c___placa', 'C / placa', '{}', 1),
  ('placa_motor', 's___placa', 'S / placa', '{}', 2),

  -- StatusRm (option.status_rm)
  ('status_rm', 'requisi__o', 'Requisição', '{}', 1),
  ('status_rm', 'peritagem', 'Peritagem', '{}', 2),
  ('status_rm', 'calculo', 'Cálculo', '{}', 3),
  ('status_rm', 'proposta', 'Proposta', '{}', 4),

  -- Status PCP (option.status_pcp)
  ('status_pcp', 'equipamento_inspecionado', 'Equipamento inspecionado', '{}', 1),
  ('status_pcp', 'executando', 'Executando', '{}', 2),
  ('status_pcp', 'aguardando_aprova__o', 'Aguardando aprovação', '{}', 3),
  ('status_pcp', 'sem_status', 'Sem status', '{}', 4),
  ('status_pcp', 'revis_o_comercial', 'Revisão comercial', '{"canonical": true}', 5),
  ('status_pcp', 'finalizando_para_faturar', 'Finalizado para faturar', '{}', 6),
  ('status_pcp', 'susponso__hold_', 'Suspenso (HOLD)', '{}', 7),
  ('status_pcp', 'aguardando_recebimento_equipamento', 'Aguardando recebimento equipamento', '{}', 8),
  ('status_pcp', 'revis_o_comercial0', 'Revisão comercial', '{"canonical": false}', 9),
  ('status_pcp', 'equipamento_em_inspe__o', 'Equipamento em inspeção', '{}', 10),
  ('status_pcp', 'sem_previs_o', 'Sem previsão', '{}', 11),
  ('status_pcp', 'investiga__o_de_garantia', 'Investigação de garantia', '{}', 12),
  ('status_pcp', 'executando_com_garantia', 'Executando com garantia', '{}', 13),
  ('status_pcp', 'cancelado', 'Cancelado', '{}', 14),

  -- Status Cel Proj (option.status_cel_proj)
  ('status_cel_proj', 'pendente', 'Pendente', '{"ordem0": 1}', 1),
  ('status_cel_proj', 'retornado', 'Retornado', '{"ordem0": 2}', 2),
  ('status_cel_proj', 'liberado_para_ensaios_parciais', 'Liberado para ensaios parciais', '{"ordem0": 3}', 3),
  ('status_cel_proj', 'liberado_para_impregna__o', 'Liberado para impregnação', '{"ordem0": 4}', 4),
  ('status_cel_proj', 'liberado_para_montagem', 'Liberado para montagem', '{"ordem0": 5}', 5),
  ('status_cel_proj', 'para_execu__o', 'Para execução', '{"ordem0": 6}', 6),
  ('status_cel_proj', 'em_dia', 'Executando', '{"ordem0": 7}', 7),
  ('status_cel_proj', 'finalizado', 'Finalizado', '{"ordem0": 8}', 8),
  ('status_cel_proj', 'atrasado', 'Atrasado', '{"ordem0": 9}', 9),
  ('status_cel_proj', 'n_a', 'N/A', '{"ordem0": 10}', 10),

  -- StatusEtapa (option.statusetapa)
  ('statusetapa', 'aprovado', 'Aprovado', '{}', 1),
  ('statusetapa', 'reprovado', 'Retornado', '{}', 2),
  ('statusetapa', 'nulo', 'Nulo', '{}', 3),

  -- Prioridade (option.prioridade0)
  ('prioridade0', 'muito_baixa', 'Muito Baixa', '{}', 1),
  ('prioridade0', 'baixa', 'Baixa', '{}', 2),
  ('prioridade0', 'media', 'Media', '{}', 3),
  ('prioridade0', 'alta', 'Alta', '{}', 4),
  ('prioridade0', 'muito_alta', 'Muito Alta', '{}', 5),

  -- Status Registro (option.status_registro0)
  ('status_registro0', 'em_an_lise', 'Em analise', '{}', 1),
  ('status_registro0', 'direcionado', 'Revisar', '{}', 2),
  ('status_registro0', 'aprovado', 'Aprovado', '{}', 3),

  -- Tipo Questão (option.tipo_quest_o)
  ('tipo_quest_o', 'texto_curto', 'Texto Curto', '{"lsita": false, "sele__o": false}', 1),
  ('tipo_quest_o', 'texto_longo', 'Texto Longo', '{"lsita": false, "sele__o": false}', 2),
  ('tipo_quest_o', 'escolha__nica', 'Escolha Única', '{"lsita": false, "sele__o": true}', 3),
  ('tipo_quest_o', 'caixas_de_sele__o', 'Caixas de Seleção', '{"lsita": true, "sele__o": true}', 4),
  ('tipo_quest_o', 'lista_suspensa', 'Lista Suspensa', '{"lsita": false, "sele__o": true}', 5),
  ('tipo_quest_o', 'lista_multi_sele__o', 'Lista Multi-Seleção', '{"lsita": true, "sele__o": true}', 6),
  ('tipo_quest_o', 'foto', 'Foto', '{"lsita": true, "sele__o": false}', 7),
  ('tipo_quest_o', 'foto_antes_depois', 'Foto Antes/Depois', '{"lsita": true, "sele__o": false}', 8),
  ('tipo_quest_o', 'data', 'Data', '{"lsita": false, "sele__o": false}', 9),
  ('tipo_quest_o', 'hora', 'Hora', '{"lsita": false, "sele__o": false}', 10),
  ('tipo_quest_o', 'subt_tulo', 'Subtítulo', '{"lsita": false, "sele__o": false}', 11),
  ('tipo_quest_o', 'colaborador', 'Colaborador', '{"lsita": false, "sele__o": false}', 12),
  ('tipo_quest_o', 'assinatura', 'Assinatura', '{"lsita": false, "sele__o": false}', 13),
  ('tipo_quest_o', 'cliente', 'Cliente', '{"lsita": false, "sele__o": false}', 14),
  ('tipo_quest_o', 'numero', 'Numero', '{"lsita": false, "sele__o": false}', 15),

  -- Subtipos (option.subtipos)
  ('subtipos', 'intervalo_de_datas', 'Intervalo de Datas', '{"tipo_pai": "data"}', 1),
  ('subtipos', 'intervalo_de_hor_rios', 'Intervalo de Horários', '{"tipo_pai": "hora"}', 2),

  -- Tipo Dimensoes (option.dimensoes)
  ('dimensoes', '_hmico', 'Ω', '{"simbolo": "Ω"}', 1),
  ('dimensoes', 'ceusus', '°C', '{"simbolo": "°C"}', 2),
  ('dimensoes', 'mili_ohms', 'mΩ', '{"simbolo": "mΩ"}', 3),
  ('dimensoes', 'mega_ohms', 'MΩ', '{"simbolo": "MΩ"}', 4),
  ('dimensoes', 'volts', 'V', '{"simbolo": "V"}', 5),
  ('dimensoes', 'kilowatts', 'kW', '{"simbolo": "kW"}', 6),
  ('dimensoes', 'amperes', 'A', '{"simbolo": "A"}', 7),
  ('dimensoes', 'rota__es_por_minuto', 'RPM', '{"simbolo": "RPM"}', 8),
  ('dimensoes', 'hertz', 'Hz', '{"simbolo": "Hz"}', 9),
  ('dimensoes', 'porcentagem', '%', '{"simbolo": "%"}', 10),
  ('dimensoes', 'kilo_ohms', 'kΩ', '{"simbolo": "kΩ"}', 11),
  ('dimensoes', 'watts', 'W', '{"simbolo": "W"}', 12),
  ('dimensoes', 'cent_metro', 'cm', '{"simbolo": "cm"}', 13),
  ('dimensoes', 'dec_metro', 'dm', '{"simbolo": "dm"}', 14),
  ('dimensoes', 'metro', 'm', '{"simbolo": "m"}', 15),
  ('dimensoes', 'mil_metro', 'mm', '{"simbolo": "mm"}', 16),
  ('dimensoes', 'mili_amperes', 'mA', '{"simbolo": "mA"}', 17),
  ('dimensoes', 'centimetros_c_bicos', 'cm³', '{"simbolo": "cm³"}', 18),
  ('dimensoes', 'micr_metros', 'μm', '{"simbolo": "μm"}', 19),
  ('dimensoes', 'milimetros_por_segundo', 'mm/s', '{"simbolo": "mm/s"}', 20),

  -- CategoriaFoto (option.categoriafoto)
  ('categoriafoto', 'obrigat_ria', 'Obrigatória', '{}', 1),
  ('categoriafoto', 'complementar', 'Complementar', '{}', 2),

  -- Etapa (option.etapa)
  ('etapa', 'recebimento', 'Recebimento', '{}', 1),

  -- RMTipoFoto (option.rmtipofoto)
  ('rmtipofoto', 'lateral_direita', 'Vista lateral direita', '{}', 1),
  ('rmtipofoto', 'lateral_esquerda', 'Vista lateral esquerda', '{}', 2),
  ('rmtipofoto', 'frente', 'Vista frontal', '{}', 3),
  ('rmtipofoto', 'vista_superior', 'Vista Traseira', '{}', 4),
  ('rmtipofoto', 'placa', 'Placa de identificação', '{}', 5),
  ('rmtipofoto', 'antes_de_descarregar', 'Antes de descarregar', '{}', 6),
  ('rmtipofoto', 'embalagem', 'Embalagem', '{}', 7),
  ('rmtipofoto', 'em_cima_do_caminh_o_lonado', 'Em cima do caminhão lonado', '{}', 8),

  -- Tipo Formulario (option.tipo_formulario)
  ('tipo_formulario', 'ordem_de_servico', 'Ordem de servico', '{}', 1),
  ('tipo_formulario', 'teste_eletrico_inicial', 'Teste eletrico inicial', '{}', 2),
  ('tipo_formulario', 'teste_eletrico_final', 'Teste eletrico final', '{}', 3),
  ('tipo_formulario', 'ficha_delineamento', 'Ficha delineamento', '{}', 4),

  -- Origem Notificação (option.origem_notifica__o0)
  ('origem_notifica__o0', 'formul_rio', 'Formulário', '{}', 1),
  ('origem_notifica__o0', 'registros', 'Registros', '{}', 2),
  ('origem_notifica__o0', 'avalia__o', 'Avaliação', '{}', 3),
  ('origem_notifica__o0', 'usu_rio', 'Usuário', '{}', 4),
  ('origem_notifica__o0', 'login', 'Login', '{}', 5),

  -- Tipo Evento Sistema (option.tipo_evento_sistema)
  ('tipo_evento_sistema', 'altera__o_de_senha', 'Alteração de senha', '{}', 1),
  ('tipo_evento_sistema', 'login', 'Login', '{}', 2),
  ('tipo_evento_sistema', 'identidade', 'Identidade', '{}', 3),

  -- StatusProcesso (option.statusprocesso)
  ('statusprocesso', 'em_processamento', 'Em processamento', '{}', 1),
  ('statusprocesso', 'processado', 'Processado', '{}', 2),
  ('statusprocesso', 'n_o_processado', 'Não processado', '{}', 3),

  -- StatusAtividade (option.statusatividade)
  ('statusatividade', 'em_andamento', 'Em andamento', '{}', 1),
  ('statusatividade', 'finalizado', 'Finalizado', '{}', 2),
  ('statusatividade', 'n_o_iniciado', 'Não Iniciado', '{}', 3),
  ('statusatividade', 'em_espera', 'Em espera', '{}', 4)
on conflict (option_set_key, option_key) do update
set bubble_display = excluded.bubble_display,
    attributes = excluded.attributes,
    sort_order = excluded.sort_order;

-- ============================================================================
-- 4. FUNÇÕES DE TRADUÇÃO BUBBLE <-> SUPABASE PARA OPTION SETS
-- ============================================================================

create or replace function rm_private.resolve_option_key(
  p_option_set_key text,
  p_raw_value text
)
returns text
language sql
stable
set search_path = ''
as $$
  select o.option_key
  from public.rm_option_sets o
  where o.option_set_key = p_option_set_key
    and (
      o.option_key = p_raw_value
      or lower(trim(o.bubble_display)) = lower(trim(p_raw_value))
    )
  order by
    case when o.option_key = p_raw_value then 0 else 1 end,
    o.sort_order asc
  limit 1;
$$;

create or replace function rm_private.resolve_option_display(
  p_option_set_key text,
  p_option_key text
)
returns text
language sql
stable
set search_path = ''
as $$
  select o.bubble_display
  from public.rm_option_sets o
  where o.option_set_key = p_option_set_key
    and o.option_key = p_option_key
  limit 1;
$$;

commit;

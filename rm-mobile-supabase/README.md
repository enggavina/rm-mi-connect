# EM · MI Electric Brasil — PostgreSQL / Supabase e sincronização

Este diretório contém a infraestrutura de banco de dados (PostgreSQL/Supabase), scripts de ETL da Data API do Bubble (`rmmi`), worker de sincronização bidirecional temporária (`Supabase <-> Bubble Desktop / n8n`) e schema SQLite offline-first do aplicativo **EM**, da **MI Electric Brasil**, em **React Native (Expo + TypeScript)**. Os identificadores técnicos `rm_*` e os nomes da infraestrutura existente permanecem preservados.

O aplicativo implementado está em `../mobile`; o runtime da ponte e do ETL está em `../desktop`. Consulte [MOBILE_DEPLOYMENT.md](MOBILE_DEPLOYMENT.md) para provisionamento, [PROJECT_OPERATIONS.md](PROJECT_OPERATIONS.md) para operações e carga histórica e [desktop/README.md](../desktop/README.md) para contratos e operação da ponte.

## Estrutura de Arquivos

- [`migrations/001_rm_enums_and_option_sets.sql`](./migrations/001_rm_enums_and_option_sets.sql)
  Cria o schema privado `rm_private`, a tabela de tradução `public.rm_option_sets`, todos os tipos `ENUM` canônicos do domínio RM e as funções `rm_private.resolve_option_key` / `rm_private.resolve_option_display` (tratando divergências críticas como `direcionado` ↔ `"Revisar"`, `em_dia` ↔ `"Executando"` e `aprovador` ↔ `"Verificador"`).
- [`migrations/002_rm_core_tables.sql`](./migrations/002_rm_core_tables.sql)
  Cria as 29 tabelas operacionais e de catálogo (`public.rm_*` + `rm_private.user_credentials`), separando credenciais e PII sensíveis (`cpf`, `palavra_chave_hash`, `segredo_totp`) da tabela pública `public.rm_users`.
- [`migrations/003_rm_workflows_rpcs_and_triggers.sql`](./migrations/003_rm_workflows_rpcs_and_triggers.sql)
  Substitui os workflows recursivos do Bubble e as cadeias de ações do `rm_mobile` por RPCs transacionais e atômicas no PostgreSQL:
  - `public.rm_authenticate_operator_v1` (substitui a página `identify` `coZum`)
  - `rm_private.next_form_sequence_v1` (substitui `codigo_sequencial` `coUMy` sem race conditions)
  - `public.rm_submit_recebimento_v1` (substitui o wizard `formrecebimento` `cojXG`/`cojXl`/`cofqG` + e-mail n8n)
  - `public.rm_materialize_project_cells_v1` (substitui `projetocell_copy` `coZAA` em transação única)
  - `public.rm_submit_form_inspection_v1` (substitui `coVnW` + `novo_form_recursivo` `cofnw` com idempotência por `client_submission_id`)
  - `public.rm_submit_form_revision_v1` (substitui `Popup Corrigir` `cofgY`)
  - `public.rm_transition_stage_approval_v1` (substitui `copmq` Liberar, `copmY` Retornar, `copzz` Aprovar e `conwe` Finalizar ciclo)
- [`migrations/004_rm_rls_and_sync_bridge.sql`](./migrations/004_rm_rls_and_sync_bridge.sql)
  Configura Row Level Security (RLS) em todas as tabelas, cria os buckets do Supabase Storage (`rm-fotos`, `rm-assinaturas`, `rm-documentos`), ativa a publicação `supabase_realtime` e cria o RPC `public.rm_apply_bubble_webhook_v1` para receber atualizações vindas do Desktop Bubble (`rm_planejamento`, `proposta`, `rm_gestao`, `settings_rm`).
- [`migrations/005_rm_commercial_proposals_and_legacy_forms.sql`](./migrations/005_rm_commercial_proposals_and_legacy_forms.sql)
  Acrescenta tabelas preparatórias de autorização legada, comercial/precificação, documentos/templates, laboratório e suporte. **Não representa paridade funcional completa:** geração/compilação de PDF, cálculos comerciais, policies e fluxos de laboratório ainda exigem implementação. A revisão Live encontrou divergências entre a precificação do Bubble e o modelo aproximado desta migração. Consulte o [plano de paridade](../plano_paridade_rmmi_web.md).
- [`migrations/006_rm_mobile_delegation_and_idempotency.sql`](./migrations/006_rm_mobile_delegation_and_idempotency.sql)
  Adiciona delegação de operador, idempotência transacional, validação de respostas e policies de upload por dispositivo.
- [`migrations/007_rm_bridge_leases_and_checkpoints.sql`](./migrations/007_rm_bridge_leases_and_checkpoints.sql)
  Adiciona leases, checkpoints, claims recuperáveis e avanço monotônico da numeração de formulários importados.
- [`migrations/008_rm_realtime_mobile_catalogs.sql`](./migrations/008_rm_realtime_mobile_catalogs.sql)
  Completa a publicação Realtime de todas as 17 tabelas consumidas pelo mobile.
- [`migrations/009_rm_fractional_question_indices.sql`](./migrations/009_rm_fractional_question_indices.sql)
  Preserva índices fracionários de questões e opções, incluindo respostas, rascunhos e os casts das RPCs de importação/envio.
- [`migrations/010_rm_operator_cell_permissions.sql`](./migrations/010_rm_operator_cell_permissions.sql)
  Usa as células cadastradas para a identidade do operador, preserva os vínculos durante o login e permite atualizar o contexto sem renovar o turno offline.
- [`migrations/011_rm_project_operations.sql`](./migrations/011_rm_project_operations.sql)
  Adiciona status e comentários da célula, regras contextuais de aprovação, documentos privados e recebimento com NF sem exigir número de projeto ou tipo de equipamento.
- [`migrations/012_rm_historical_answer_snapshots.sql`](./migrations/012_rm_historical_answer_snapshots.sql)
  Preserva respostas históricas importadas cujo vínculo de questão foi removido na origem, sem permitir novos envios ou correções sem questão válida.
- [`migrations/013_rm_mobile_pull_performance.sql`](./migrations/013_rm_mobile_pull_performance.sql)
  Indexa a paginação mobile por `updated_at,id` e avalia a mesma autorização RLS uma vez por consulta, eliminando o timeout do histórico de respostas.
- [`migrations/014_rm_web_management.sql`](./migrations/014_rm_web_management.sql) e [`015_rm_web_conflict_http_status.sql`](./migrations/015_rm_web_conflict_http_status.sql)
  Gestão web de projetos, planejamento e revisão, com autoria, idempotência, controle de versão e conflito HTTP 409.
- [`migrations/016_rm_web_sso_bridge.sql`](./migrations/016_rm_web_sso_bridge.sql)
  Ponte SSO privada, vínculos explícitos e permissões de ação de uso único. A ativação segue [SSO_BRIDGE.md](SSO_BRIDGE.md).
- [`migrations/017_rm_web_catalog_management.sql`](./migrations/017_rm_web_catalog_management.sql)
  Dados cadastrais básicos de clientes, células e tipos, com permissão administrativa própria e proteção de referências. Não inclui construtor de formulários nem toda a engenharia.
- [`blueprint/01_integracoes_render_n8n_s3_contratos.md`](./blueprint/01_integracoes_render_n8n_s3_contratos.md)
  Mapeamento completo e contratos JSON dos 3 serviços no Render (`Auth`, `PDF_Proposta`, `Insp`), 13 webhooks do n8n, AWS S3/CloudFront, Google Docs, `rm-gantt-tableau` e `RM Report Builder`.
- [`blueprint/02_especificacao_paginas_e_prompts_ia.md`](./blueprint/02_especificacao_paginas_e_prompts_ia.md)
  Especificação funcional das 27 páginas web, 9 reutilizáveis, 3 views nativas, matriz RBAC completa e pacote de 6 Prompts Mestres para recriação hard-code com IA.
- [`scripts/etl_bubble_to_supabase.ts`](./scripts/etl_bubble_to_supabase.ts)
  Entrypoint de extração e carga (ETL) em ordem topológica para a implementação em `desktop/src/server/bridge`. Possui modo `--dry-run`; referências ou endpoints ausentes produzem erros explícitos, sem fabricar registros incompletos.
- [`scripts/sync_worker_bubble_supabase.ts`](./scripts/sync_worker_bubble_supabase.ts)
  Worker de sincronização bidirecional temporária que consome `public.rm_sync_outbox` (enviando criações/atualizações do Mobile para o Bubble e webhooks do n8n) e faz polling incremental das revisões e planejamentos feitos no Desktop do Bubble.
- [`mobile-offline/sqlite_schema.ts`](./mobile-offline/sqlite_schema.ts)
  Schema SQLite local (`expo-sqlite`) para o app React Native com suporte offline-first e preenchimento instantâneo de `"N/A"` (`buildDefaultNaAnswer`).

---

## Como Executar

### 1. Aplicar as Migrações SQL no Supabase

Aplicar as migrações 001–017 em ordem, conferindo o ambiente de destino. As 014–015 acrescentam a gestão web, a 016 prepara o SSO sem ativá-lo automaticamente e a 017 acrescenta os cadastros básicos. O cadastro da capacidade na Central e sua concessão são operações separadas da migração SQL. Não expor as RPCs legadas diretamente ao aplicativo.

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/001_rm_enums_and_option_sets.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/002_rm_core_tables.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/003_rm_workflows_rpcs_and_triggers.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/004_rm_rls_and_sync_bridge.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/005_rm_commercial_proposals_and_legacy_forms.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/006_rm_mobile_delegation_and_idempotency.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/007_rm_bridge_leases_and_checkpoints.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/008_rm_realtime_mobile_catalogs.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/009_rm_fractional_question_indices.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/010_rm_operator_cell_permissions.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/011_rm_project_operations.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/012_rm_historical_answer_snapshots.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/013_rm_mobile_pull_performance.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/014_rm_web_management.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/015_rm_web_conflict_http_status.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/016_rm_web_sso_bridge.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f rm-mobile-supabase/migrations/017_rm_web_catalog_management.sql
```

### 2. Executar o ETL Inicial (Bubble -> Supabase)

```bash
cd desktop
npm ci
# Preencher desktop/.env a partir de .env.example.
npm run etl -- --dry-run
# Após conferir contratos e referências:
npm run etl
```

### 3. Iniciar o Worker de Sincronização Bidirecional

```bash
cd desktop
npm run worker
```

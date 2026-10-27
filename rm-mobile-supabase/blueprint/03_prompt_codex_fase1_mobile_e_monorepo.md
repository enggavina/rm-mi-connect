# Prompt Mestre para o Codex — Fase 1 (Estrutura Monorepo `mobile` + `desktop`, GitHub Privado, Supabase Pago e Implementação Completa do App `mobile` Offline-First)

Copie o bloco abaixo e envie diretamente para o **Codex**:

```markdown
Você é um Engenheiro de Software Sênior responsável por iniciar a recriação completa (hard-code) do sistema **RM - MI Connect** (atualmente no Bubble.io sob o app `rmmi`, combinado com microsserviços no Render e fluxos no n8n).

Toda a engenharia reversa, os 61 volumes de especificação extraídos do Bubble, as 5 migrações SQL do PostgreSQL/Supabase, os scripts de ETL/Sincronização e o schema SQLite offline-first já foram gerados e estão disponíveis no diretório local:
- Pacote de banco, ETL, Sync e Blueprints: `./rm-mobile-supabase/`
  - `./rm-mobile-supabase/migrations/001_rm_enums_and_option_sets.sql`
  - `./rm-mobile-supabase/migrations/002_rm_core_tables.sql`
  - `./rm-mobile-supabase/migrations/003_rm_workflows_rpcs_and_triggers.sql`
  - `./rm-mobile-supabase/migrations/004_rm_rls_and_sync_bridge.sql`
  - `./rm-mobile-supabase/migrations/005_rm_commercial_proposals_and_legacy_forms.sql`
  - `./rm-mobile-supabase/mobile-offline/sqlite_schema.ts`
  - `./rm-mobile-supabase/scripts/etl_bubble_to_supabase.ts`
  - `./rm-mobile-supabase/scripts/sync_worker_bubble_supabase.ts`
  - `./rm-mobile-supabase/blueprint/01_integracoes_render_n8n_s3_contratos.md`
  - `./rm-mobile-supabase/blueprint/02_especificacao_paginas_e_prompts_ia.md`
- Microsserviços legados locais (para referência de contratos):
  - `../Auth/main.py` (TOTP 2FA no Render)
  - `../pdf_generator-main/pdf_generator-main/main.py` (Gerador PDF no Render)
  - `../rm_report/src/rm_report_builder/app.py` (RM Report Builder + Webhooks n8n)
  - `../nr12-novo/` (App mobile irmão em Expo 54 + React Native para referência de padrão visual e fila offline)

---

## 1. DIRETRIZES ARQUITETURAIS OBRIGATÓRIAS

1. **Estrutura de Pastas (Dois Projetos Separados + Banco):**
   Organize a raiz do repositório com duas pastas de aplicação estritamente separadas e a pasta de infraestrutura de banco:
   - `/mobile`: Aplicativo nativo **React Native com Expo (SDK 54, TypeScript, Expo Router)** que será instalado nos tablets/dispositivos móveis do chão de fábrica.
   - `/desktop`: Aplicação Web Desktop + Backend Unificado (**Next.js 15 App Router, TypeScript, Node.js runtime**) que rodará na nuvem no **Railway** (com `Dockerfile` e `railway.json`). O projeto `/desktop` no Railway absorverá também todas as funções que hoje rodam espalhadas no Render (`Auth` TOTP, `PDF_Proposta`, `Insp`) e no `n8n` (geração/compilação de relatórios PDF, templates `.docx`, envio de e-mails SMTP e worker de sincronização).
   - `/supabase` (ou mantendo `/rm-mobile-supabase`): Migrações SQL (`001` a `005`), seeds, scripts de ETL e worker de sincronização bidirecional.

2. **Repositório GitHub Privado:**
   - Inicialize o repositório Git na raiz, configure um `.gitignore` seguro (nunca versione `.env`, chaves do Supabase, tokens do Bubble ou builds nativos pesados) e crie/publique tudo em um **repositório privado no GitHub** (`gh repo create rm-mi-connect --private --source=. --push`).
   - Crie arquivos `.env.example` documentados tanto em `/mobile` quanto em `/desktop` e `/rm-mobile-supabase`.

3. **Banco de Dados no Supabase (Plano Pago já existente):**
   - O banco de dados principal é o **PostgreSQL no nosso projeto Supabase pago**.
   - Utilize exatamente as tabelas, Enums, Views, Triggers, políticas RLS, buckets de Storage (`rm-fotos`, `rm-assinaturas`, `rm-documentos`) e as **7 Stored Procedures (RPCs)** já definidas em `migrations/001` a `005`.

4. **Escopo deste Primeiro Momento (Foco 100% na Implementação do `/mobile`):**
   - **Neste primeiro momento, desenvolva de ponta a ponta apenas o aplicativo `/mobile`** (pronto para ser compilado e instalado no tablet/equipamento mobile) e deixe o `/desktop` apenas com o scaffold inicial preparado para deploy no Railway (incluindo o endpoint/worker de ponte com o Bubble e a estrutura de pastas para absorver o Render/n8n na Fase 2).

---

## 2. ESPECIFICAÇÃO COMPLETA DO PROJETO `/mobile` (FASE 1 — IMPLEMENTAR AGORA)

Leia obrigatoriamente `./rm-mobile-supabase/migrations/003_rm_workflows_rpcs_and_triggers.sql`, `./rm-mobile-supabase/mobile-offline/sqlite_schema.ts` e `./rm-mobile-supabase/blueprint/02_especificacao_paginas_e_prompts_ia.md` antes de codificar.

### 2.1. Arquitetura Offline-First (`expo-sqlite` + Fila de Sincronização)
O aplicativo `/mobile` operará em galpões industriais com oscilação de Wi-Fi. Ele **DEVE funcionar 100% offline quando necessário e sincronizar automaticamente quando voltar a ficar online**:
1. **Banco Local (`expo-sqlite`):**
   - Utilize o schema definido em `rm-mobile-supabase/mobile-offline/sqlite_schema.ts`:
     - Cache de catálogo e roteiro: `local_projetos`, `local_celulas_projeto`, `local_forms`, `local_questoes`, `local_itens_questoes`, `local_fotos_slots`.
     - Rascunhos em tempo real (auto-save a cada campo preenchido): `local_registros_formulario_draft`, `local_respostas_draft`.
     - Filas persistentes de saída: `local_media_upload_queue` (fotos e assinaturas salvas no `expo-file-system` local) e `local_sync_outbox` (chamadas RPC pendentes com `client_submission_id` UUID v4 para idempotência total).
2. **Motor de Sincronização (`SyncEngine` + `@react-native-community/netinfo`):**
   - **Downsync (Pull Incremental):** Quando online, baixa/atualiza do Supabase apenas os projetos ativos (`rm_projetos`), equipamentos (`rm_equipamentos`), células do projeto (`rm_celulas_projeto`), slots de fotos (`rm_fotos` pré-cadastradas pelo Desktop com seus títulos), formulários dinâmicos confeccionados no Desktop (`rm_forms`, `rm_questoes`, `rm_itens_questoes`), registros em revisão (`rm_registros_formulario` com `status_execucao = 'Revisar'` e suas `rm_respostas`) e etapas de aprovação (`rm_aprovacao_etapas`).
   - **Upsync (Push em Ordem Estrita):**
     1. Primeiro faz upload de todas as mídias pendentes em `local_media_upload_queue` para os buckets `rm-fotos` e `rm-assinaturas` do Supabase Storage (com compressão inteligente de imagem antes do envio).
     2. Substitui os URIs `file://` locais pelas URLs públicas/assinadas do Supabase Storage no payload das mutações em `local_sync_outbox`.
     3. Executa as RPCs transacionais no Supabase (`rm_submit_recebimento_v1`, `rm_record_cell_photo_v1`, `rm_submit_form_inspection_v1`, `rm_submit_form_revision_v1`, `rm_transition_stage_approval_v1`) com retry exponencial.
   - **Indicador Visual de Sincronização:** Barra/badge global no topo mostrando status (`Online` / `Offline`), quantidade de fotos/formulários na fila de sincronização e botão "Sincronizar Agora".

### 2.2. Autenticação Híbrida de Chão de Fábrica (`/identify` + Troca Rápida de Operador)
- Suporte a login de supervisor/dispositivo via Supabase Auth e **Identificação de Operador por Palavra-Chave (`palavra_chave`)** via RPC `public.rm_authenticate_operator_v1` (ou validação em cache seguro quando offline).
- Permita trocar rapidamente de operador no tablet sem limpar os dados sincronizados nem perder itens pendentes na `local_sync_outbox`.

### 2.3. As 8 Vistas Operacionais do `rm_mobile`
Construa todas as telas otimizadas para uso em Tablet e Smartphone industrial (botões amplos, alto contraste, feedback tátil):

1. **Vista `celula` (Hub de Células de Produção e Execução):**
   - Seleção da célula de produção (`rm_celulas` ordenadas por `indice`).
   - Listagem dos projetos alocados na célula (`rm_celulas_projeto`) com filtro por status (`Pendente`, `Executando`, `Atrasado`, `Ag. Aprovação`, `Finalizado`), busca por número de projeto/OS e indicador de atraso (`data_limite`).
   - **Checklist de Fotos Obrigatórias da Célula:** Exibe os slots de fotos previamente cadastrados pelo Desktop para aquele projeto/célula (`rm_fotos` onde `tipo_foto = 'Obrigatória'` com seu `titulo` pré-definido). O operador toca no slot, captura a foto pela câmera (ou galeria), adiciona descrição opcional e salva (offline no SQLite + `rm_record_cell_photo_v1`).
   - **Fotos Complementares da Célula:** Permite ao operador adicionar fotos extras (`tipo_foto = 'Complementar'`) informando título e descrição.
   - **Lista de Formulários da Célula:** Exibe os formulários vinculados ao par `(célula, tipo_equipamento)` (`rm_celula_form_tipo_equipamento` -> `rm_forms`), indicando se já foram preenchidos, se estão `Em Análise`, `Revisar` (com badge de alerta) ou `Concluído`.

2. **Vista `registro-form` (Motor Dinâmico de Preenchimento de Formulários):**
   - Renderiza qualquer formulário personalizado confeccionado no construtor Desktop (`rm_forms` + `rm_questoes` ordenadas por `indice` + `rm_itens_questoes`).
   - Suporte completo aos **15 tipos de `Tipo Questão`**:
     1. `Texto Curto`
     2. `Texto Longo`
     3. `Numero` (teclado numérico com máscara decimal)
     4. `Data` (DatePicker)
     5. `Hora` (TimePicker)
     6. `Intervalo de Data` (Início / Fim)
     7. `Lista Suspensa` (Dropdown single-select de `rm_itens_questoes`)
     8. `Lista Multi-Seleção` (Multi-select de `rm_itens_questoes`)
     9. `Escolha Única` (Radio buttons de `rm_itens_questoes` + exibição de instrução/ajuda quando houver)
     10. `Caixas de Seleção` (Checkboxes múltiplos de `rm_itens_questoes`)
     11. `Foto` (Múltiplas fotos por questão via câmera/galeria com preview e exclusão)
     12. `Foto Antes/Depois` (Slots dedicados para fotos de "Antes" e "Depois")
     13. `Assinatura` (Canvas de assinatura manuscrita digital exportando PNG para `rm-assinaturas`)
     14. `Colaborador` (Seletor de colaborador `rm_users`)
     15. `Cliente` (Seletor de cliente `rm_clientes`)
     16. `Subtítulo` (Divisor visual de seção)
   - **Botão "Preencher N/A":** Usa a função `buildDefaultNaAnswer` de `sqlite_schema.ts` (reproduzindo o workflow `Preenche NA` do Bubble) para preencher automaticamente questões não aplicáveis.
   - **Auto-Save Offline:** Cada alteração de resposta grava imediatamente em `local_respostas_draft`.
   - **Submissão Final:** Valida questões obrigatórias (`obrigatorio = true`), gera `client_submission_id` e envia via `public.rm_submit_form_inspection_v1`.

3. **Vista `revisao-form` (Correção de Formulários Devolvidos pelo Desktop):**
   - Lista os `rm_registros_formulario` com `status_execucao = 'Revisar'` (devolvidos pela engenharia/PCP na página Desktop `rm_planejamento`).
   - Exibe em destaque a observação de revisão (`revisao_texto`) enviada pelo revisor.
   - Carrega as respostas originais (`rm_respostas`), permite corrigir textos, números, seleções e fotos, e reenvia via `public.rm_submit_form_revision_v1` (que altera o status de volta para `Em Análise`).

4. **Vista `recebimento` (Check-in de Chegada de Motor na Fábrica):**
   - Wizard passo a passo para registrar a chegada de um equipamento: seleção/busca de cliente, número do projeto/OS, dados de placa do equipamento (`rm_equipamentos`), leitura/vinculação de QR Code e captura das fotos de recebimento.
   - Salva offline e executa `public.rm_submit_recebimento_v1` (que cria/atualiza `rm_projetos`, `rm_equipamentos`, `rm_fotos` e dispara o evento de e-mail para orçamentos).

5. **Vista `aprovacao` (Central de Liberação e Aprovação de Etapas):**
   - Permite a líderes/verificadores aprovar, liberar ou retornar para revisão etapas (`rm_aprovacao_etapas` / `rm_registros_formulario`) consumindo a RPC `public.rm_transition_stage_approval_v1` (`LIBERAR`, `RETORNAR`, `APROVAR`, `FINALIZAR_CICLO`).

6. **Vistas `confirmacao`, `formularios` (consulta de formulários registrados) e `peritagem` (acesso rápido aos formulários de peritagem da célula).**

---

## 3. ESPECIFICAÇÃO DO SCAFFOLD `/desktop` PARA O RAILWAY (FASE 1 — ESTRUTURA BASE)

Na pasta `/desktop`, crie a estrutura base do projeto **Next.js 15 (App Router, TypeScript)** configurada para rodar no **Railway**:
1. Adicione `Dockerfile` otimizado (Node 20 + suporte futuro a Chromium/Playwright ou `pdf-lib`/`docxtpl` para geração de PDFs sem depender do Render) e `railway.json`.
2. Crie a estrutura de rotas de API internas (`/api/webhooks/bubble`, `/api/reports/generate-pdf`, `/api/reports/compile-s3`, `/api/auth/totp`) que substituirão os serviços do Render (`Auth`, `PDF_Proposta`, `Insp`) e os 13 webhooks do `n8n` conforme documentado em `./rm-mobile-supabase/blueprint/01_integracoes_render_n8n_s3_contratos.md`.
3. Integre o worker de sincronização bidirecional (`rm-mobile-supabase/scripts/sync_worker_bubble_supabase.ts`) para que, enquanto o Desktop do Bubble ainda estiver ativo em paralelo, qualquer formulário ou título de foto criado no Bubble Desktop seja sincronizado com o Supabase e apareça imediatamente no `/mobile`, e qualquer resposta/foto registrada no `/mobile` retorne ao Bubble.

---

## 4. PASSO A PASSO DE EXECUÇÃO ESPERADO

1. Inspecione os arquivos existentes em `./rm-mobile-supabase/` e `../nr12-novo/`.
2. Estruture os diretórios `/mobile` e `/desktop` na raiz do workspace.
3. Implemente o aplicativo `/mobile` completo (banco SQLite offline-first, motor de sincronização bidirecional com Supabase Storage + RPCs, autenticação de operador, e as 8 vistas operacionais com suporte aos 15 tipos de questão e slots de fotos da célula).
4. Crie o scaffold do `/desktop` preparado para o Railway.
5. Valide a tipagem TypeScript (`tsc --noEmit`) em `/mobile` e `/desktop`.
6. Inicialize o Git, faça o commit estruturado e publique no repositório privado do GitHub.
```

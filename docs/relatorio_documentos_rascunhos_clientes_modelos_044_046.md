# Documentos, recebimento, clientes e modelos — 044 a 046

Solicitação de 16/11/2026, anexo `fd000e07-395c-4acb-b684-2f3f0aea7d90`. Evolução incremental do EM web e mobile, com o Supabase `oficina-em-mi-off` e o Railway EM. Esta entrega não altera o Bubble nem ativa a ponte de saída.

## Discovery e decisões

| Requisito | Estado encontrado | Estrutura reutilizada / evolução |
|---|---|---|
| Pastas hierárquicas | Não implementado | Dossiê com pesquisa/paginação 030, documentos gerados `rm_documentos`, anexos `rm_docs`, upload privado 029 e versões 033. Novas relações de diretório organizam os mesmos registros. |
| Autosave do recebimento | Parcialmente implementado | Rascunho SQLite por operador, UUID estável e fila idempotente existentes. Acrescentado snapshot privado no Supabase, com revisão, retomada e conflito explícito. |
| Cliente pelo nome do projeto | Não implementado | Campo `cliente_id`, catálogo paginado e criação existente com `em.projects.manage`. Correspondência local sobre o catálogo já autorizado, sem endpoint paralelo. |
| Exclusão de modelos | Não implementado | Builder 019 com famílias, rascunhos e publicações imutáveis; catálogo `rm_forms` e definições/questões existentes. Remoção protegida de modelos sem uso, bloqueio de dependências e recibo de auditoria existentes. |

As migrações aplicadas até 043 são preservadas. Não há conversão de respostas, reorganização retroativa de arquivos ou limpeza de trabalhos offline.

## Documentos e pastas

A raiz do projeto é a ausência de uma localização de pasta. Documentos existentes aparecem na raiz, com os mesmos UUIDs, arquivos, URLs e versões. Pastas usam `projeto_id`, `parent_id`, nome e autoria; o parentesco é persistente no banco. As relações compostas impedem pai, documento ou arquivo de outro projeto. A navegação usa breadcrumbs e diretórios clicáveis. Não há limitação de negócio a um nível de subpastas.

O upload reutiliza a reserva, a validação de conteúdo e o finalizador atuais. O destino selecionado fica congelado na intenção e a localização é publicada junto com o anexo; versões novas herdam a localização da origem. Mover um documento altera somente a organização do dossiê, preservando o objeto privado imutável. O endpoint autorizado de abertura/download continua controlando o acesso e emitindo assinatura temporária.

Criar, renomear e mover pastas e mover documentos utilizam a nova operação `manage_project_documents` no envelope SSO existente. Excluir pasta exige confirmação e pasta vazia; arquivos, subpastas ou reservas de upload impedem a remoção. Ciclos e associação entre projetos são bloqueados no banco. A exclusão individual de arquivos versionados permanece fora deste incremento, pois exigiria um fluxo próprio de retenção e descarte; não foi acrescentada uma remoção insegura de objetos privados.

Consulta exige as permissões atuais do dossiê e RLS; gestão reutiliza `em.projects.manage`, os perfis internos e as validações de projeto existentes. A estrutura não concede novas permissões. O fechamento de propriedade e a ordem de exclusão integral do projeto 039 incluem as novas relações, preservando projetos vizinhos e a coleta privada já existente.

## Recebimento mobile

O registro original continua em `local_meta.recebimento:<operador>`, no SQLite. Cada alteração é salva localmente; o sidecar de sincronização é atualizado na mesma transação. O envio do snapshot para o Supabase usa debounce de **1.200 ms**, com retomada por reconexão/retorno do aplicativo e tentativas existentes. O rascunho inicial ainda incompleto é aceito como rascunho; não é inserido na lista de recebimentos efetivos.

A tabela privada `rm_private.receiving_drafts` armazena o mesmo UUID, conta do dispositivo, operador, payload, revisão, último protocolo de autosave, estado e resultado final. O acesso ocorre exclusivamente por RPC delegada ao operador, sem acesso direto à tabela. O slot ativo é único por conta/operador.

Um request pendente é persistido antes da rede e repetido com o mesmo UUID e conteúdo se a resposta se perder. Edições posteriores aguardam esse reconhecimento. A retomada consulta o dispositivo e o banco; alterações locais pendentes não são sobrescritas. Conflitos exigem escolha explícita e guardam uma cópia de recuperação no SQLite antes de retomar a versão do banco. O feedback distingue salvamento no dispositivo, no banco e conflito. Mídias pendentes permanecem locais até que o upload existente produza URLs remotas; um envio incompleto é sinalizado e retomado.

Somente **Solicitar abertura** cria o envelope definitivo na FIFO existente. Novos envios levam o UUID e a revisão do draft; o gateway valida, executa o recebimento e finaliza o draft na mesma transação. Falhas revertem também a finalização. Repetições usam o recibo original, sem segundo recebimento. Clientes antigos continuam aceitos sem novos campos obrigatórios; identidades, payloads, hashes e recibos anteriores não são reescritos.

Contrato completo: [MOBILE_RECEIVING_DRAFTS.md](../rm-mobile-supabase/MOBILE_RECEIVING_DRAFTS.md).

## Identificação do cliente

Somente a criação de projeto tenta preencher o Cliente; a edição existente conserva a seleção. O índice de busca é compilado uma vez sobre o catálogo autorizado já carregado. Não há consulta a cada tecla nem segunda carga da base. O catálogo existente pagina em blocos e falha explicitamente ao ultrapassar seu limite de 20.000 registros, sem inferir resultados a partir de uma base truncada.

Após **400 ms**, o texto é normalizado por decomposição Unicode, remoção de marcas de acento, caixa, pontuação e espaços. A comparação usa palavras completas e o nome completo cadastrado. Um nome mais específico só vence se contiver todas as outras correspondências; clientes independentes e nomes normalizados iguais com UUIDs diferentes são ambíguos. Sem correspondência inequívoca, o campo permanece disponível para escolha manual.

O preenchimento usa o UUID real de `rm_clientes`. Campo já preenchido, seleção manual e limpeza manual são respeitados, inclusive quando o debounce ainda está pendente. Nenhum nome cadastrado é alterado. [Contrato e limites](../desktop/docs/project-client-autofill.md).

## Exclusão de modelos

**Excluir modelo** está disponível no rascunho e na consulta do formulário publicado para administradores com `em.form_templates.manage`. A confirmação apresenta o nome, exige ciência explícita e envia o ID, tipo e revisão exatos. O backend repete autorização, MFA/SSO e confirmação; requisições não confirmadas não executam a exclusão. Incerteza de rede mantém o mesmo corpo e protocolo para repetição.

Um rascunho não publicado pode ser removido sem apagar seu modelo de origem. Um formulário sem uso pode ter removidos apenas sua definição exclusiva, questões, itens, numeração ainda não utilizada e metadados exclusivos de publicação. A auditoria privada registra o snapshot anterior, e publicações relacionadas/famílias em uso permanecem protegidas.

Bloqueiam a exclusão: vínculos de célula/equipe, roteiro de tipo de equipamento, alocações atuais ou históricas, registros/respostas, respostas temporárias, referências a opções por arrays, templates de relatório, revisores, outras versões/rascunhos e histórico de utilização dos recibos. A inspeção de foreign keys inclui dependências com `CASCADE` e `SET NULL`, que não são executadas silenciosamente. Dependências futuras também bloqueiam a remoção, salvo os filhos exclusivos explicitamente identificados. Não é criado um soft delete novo; modelos em uso permanecem intactos.

Locks de identidade e registros, validação de arrays e repetição por recibo protegem a operação contra novas referências e recriação concorrente de identidades. Tombstones reutilizam a consulta do ETL para formulário, questões e itens, impedindo reimportação silenciosa do que foi excluído. As guardas de imutabilidade 019 continuam valendo para edição de versões publicadas.

As arrays legadas não foram convertidas em novas foreign keys. Identidades desconhecidas e elementos nulos já admitidos pela importação continuam disponíveis para a reconciliação existente; a guarda rejeita novas referências a identidades explicitamente excluídas. Modelos existentes recebem locks de chave para coordenar a criação de vínculos com a exclusão. IDs UUID são comparados em formato canônico, inclusive quando o pedido veio em letras maiúsculas.

## Alterações de banco

| Migração | Novas estruturas |
|---|---|
| `044_rm_web_project_document_folders.sql` | `rm_project_document_folders`, `rm_project_document_locations`; coluna nullable `folder_id` em `rm_private.project_attachment_uploads`; uniques de identidade projeto/arquivo; FKs compostas projeto/pai/pasta/arquivo; restrições de nome, autoparentesco e origem única; índices de nome por diretório e localização; RLS e operação SSO do dossiê. |
| `045_rm_mobile_receiving_drafts.sql` | `rm_private.receiving_drafts`; PK UUID, FKs restritivas para Auth/operador, revisão/estado/limite JSON/identidade/resultados coerentes; unique parcial por slot ativo e índice por dono/data; RPC delegada de snapshot e integração atômica no gateway existente. |
| `046_rm_web_form_template_delete.sql` | Sem nova tabela/coluna; guardas de referências em arrays e identidades removidas; operação `delete_form_template` com permissão existente; revisão no snapshot de consulta; consulta de tombstones ampliada. |

Os nomes completos e definições de índices, FKs e constraints estão nas três fontes novas, que são o contrato de instalação. As novas tabelas começam vazias; nenhum dado de negócio artificial é criado na produção.

## Arquivos e validação

Principais áreas: `desktop/src/components/web/project-document-*`, `project-dossier-*`, `project-client-*`, `form-template-*`; leitores/actions/policies correspondentes em `desktop/src/server/web`; páginas de modelos; `mobile/app/recebimento.tsx`, `mobile/src/core/receiving-drafts.ts` e `service.ts`; migrações e novas suítes SQL.

Principais arquivos para revisão:

- `desktop/src/components/web/project-document-folder-editor.tsx`, `project-document-folder-model.ts` e `project-document-folders.module.css`: navegação e operações de diretório.
- `desktop/src/components/web/project-dossier-editors.tsx`, `project-dossier-panels.tsx` e `project-dossier-search-model.ts`: destino do upload, integração e contexto da consulta.
- `desktop/src/server/web/project-document-folder-mutations.ts`, `project-document-folder-policy.ts` e `project-dossier-search-policy.ts`: autorização, validação e DTOs.
- `desktop/src/components/web/project-client-fields.tsx`, `project-client-match.ts` e `editor.tsx`: identificação do Cliente.
- `desktop/src/components/web/form-template-delete.tsx`, `form-template-save.tsx`, páginas de modelos e `desktop/src/server/web/form-template-mutations.ts`: exclusão confirmada, repetição e resposta sanitizada.
- `mobile/app/recebimento.tsx`, `mobile/src/core/receiving-drafts.ts`, `mobile/src/core/service.ts` e `mobile/app.json`: rascunho, sincronização, confirmação e instalador.
- `desktop/tests/project-document-folders.test.ts`, `project-client-match.test.ts`, `form-template-actions.test.ts`, `mobile/tests/receiving-drafts.test.ts` e as suítes SQL de pastas, upgrade, recebimento, exclusão e concorrência: validação.

| Verificação | Resultado |
|---|---|
| Web | **489 testes aprovados** |
| Mobile | **116 testes aprovados** |
| Contrato QR web/mobile | **2 testes aprovados** |
| PostgreSQL 18 isolado | **40 suítes completas aprovadas**, incluindo upgrades e oito novas disputas reais de exclusão de modelos |
| Tipos, build web e smokes | Aprovados; CI executado com Node 22 |
| Android/iOS e APK | Exportação das duas plataformas, build release Android, assinatura e assets aprovados |
| Interfaces | React/CSS reais em 1240 e 390 px: pastas/upload, cliente e exclusão de modelos; ações/HTTP simulados, sem escritas de negócio |
| Segredos | 81 JavaScripts do build local e sete assets do APK conferidos contra dez segredos locais conhecidos, sem ocorrências |
| Lint | Sem comando/configuração independente no repositório; `git diff --check` aprovado. Não se declara execução de ESLint inexistente. |

[CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/43887639406), consumidor **`6acadb548c8f3256ee0a0c1c3001e41ab0879aff`**. Railway **`97e1e44a-fff0-453e-ba0e-18447662ab5c`** com **SUCCESS**, publicado em 16/11/2026: [EM web](https://em-web-production.up.railway.app).

As migrações **044–046 estão aplicadas**. Ensaio com rollback e instalação preservaram as projeções de todas as **84 relações anteriores** (76 RM/privadas e oito de Storage), os **142 OIDs, proprietários e ACLs de funções**, colunas anteriores, policies, enums e histórico aplicado. A única substituição planejada de constraint existente é a ampliação do check de operações SSO; a coluna nullable de destino e as novas constraints/guardas são as adições descritas neste relatório. As três tabelas novas começaram vazias; o catálogo final tem **79 tabelas RM/privadas e 153 funções**. O ensaio independente também rejeitou sete adulterações deliberadas do envelope, todas somente em banco local descartável.

| Fonte aplicada, índice e commit conferidos | SHA256 |
|---|---|
| 044 | `699992e4eb49c93759406cf5ad9c966a313bbec2ac212763e4796a4557769c71` |
| 045 | `5aaf880adf24538aeb34ebeafbd6007e272409f4266af011e77b67a7833a1a87` |
| 046 | `b2f946d79acd4f1dcc2457156906ebed9af43f813b8518d3fde3c031bf194deb` |

A leitura posterior autenticada no banco conferiu um dossiê real, a navegação da raiz, a revisão do modelo e o isolamento da tabela de drafts. Essa verificação usou uma transação de leitura e o papel `authenticated`; não equivale a login humano pelo Microsoft. Após o deploy, health **200** e **126 recusas de acesso** aprovadas: 106 consultas em 53 URLs com anônimo/cookie forjado e 20 verificações de API. O início nativo do SSO foi observado até a navegação Microsoft, em contexto de QA próprio, encerrando somente esse fluxo. Não houve CRUD positivo/artificial de negócio em produção, alteração de concessões na Central, escrita no Bubble ou ativação da ponte. SSO, administradores, identidades legadas e `SYNC_OUTBOX_ENABLED=false` permanecem; o worker privado de limpeza autorizado anteriormente continua habilitado.

Instalador: [artifacts/em-mi-electric-brasil-internal.apk](../artifacts/em-mi-electric-brasil-internal.apk), **1.2.8/código 11**, pacote `br.com.mielectric.rmconnect`, ARM64/x86_64, **69.001.516 bytes**, SHA256 **`5daa93ec0efc77abbd175777a0490d5752784594e6b0248beb91341cfe7d72dd`**. Mesmo certificado SHA256 `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`, assinatura Android Debug para distribuição interna. APK 1.2.7 e fontes nativas anteriores foram conservados em backup ignorado pelo Git.

Nenhum dispositivo foi instalado, desinstalado ou limpo. Para homologar, atualizar a instalação existente com o APK, preservando os dados, e testar reconexão, retomada e recebimento com mídias no aparelho. Os testes automatizados não substituem essa homologação física. A organização de pastas está no portal web; o mobile conserva a consulta de documentos existente. Mídias ainda não enviadas e cópias de recuperação continuam no dispositivo; recuperar trabalho em outro aparelho exige que o snapshot e as mídias já tenham sido enviados ao banco/Storage. Exclusão de pasta com upload incompleto exige reconciliação da intenção, sem descarte automático.

Os quatro requisitos centrais foram concluídos. Exclusão física individual de arquivos versionados, novos tipos de arquivo, novas capacidades, geração de relatórios e coexistência Bubble não foram acrescentados a este escopo. A paridade geral do sistema continua conforme o plano.

## Inventário detalhado do schema

Gerado pela diferença entre os catálogos 043 e 046 compilados em PostgreSQL isolado, com as mesmas fontes de instalação.

### public.rm_project_document_folders

| Campo | Tipo | Obrigatório | Valor padrão |
|---|---|---|---|
| `id` | `uuid` | Sim | — |
| `projeto_id` | `uuid` | Sim | — |
| `parent_id` | `uuid` | Não | — |
| `nome` | `text` | Sim | — |
| `created_by` | `uuid` | Sim | — |
| `created_at` | `timestamp with time zone` | Sim | `clock_timestamp()` |
| `updated_at` | `timestamp with time zone` | Sim | `clock_timestamp()` |

### public.rm_project_document_locations

| Campo | Tipo | Obrigatório | Valor padrão |
|---|---|---|---|
| `id` | `uuid` | Sim | `gen_random_uuid()` |
| `projeto_id` | `uuid` | Sim | — |
| `folder_id` | `uuid` | Sim | — |
| `anexo_id` | `uuid` | Não | — |
| `documento_id` | `uuid` | Não | — |
| `updated_by` | `uuid` | Sim | — |
| `updated_at` | `timestamp with time zone` | Sim | `clock_timestamp()` |

### rm_private.receiving_drafts

| Campo | Tipo | Obrigatório | Valor padrão |
|---|---|---|---|
| `id` | `uuid` | Sim | — |
| `auth_user_id` | `uuid` | Sim | — |
| `operator_id` | `uuid` | Sim | — |
| `payload` | `jsonb` | Sim | — |
| `revision` | `bigint` | Sim | `1` |
| `last_save_id` | `uuid` | Sim | — |
| `state` | `text` | Sim | `'draft'::text` |
| `result` | `jsonb` | Não | — |
| `created_at` | `timestamp with time zone` | Sim | `clock_timestamp()` |
| `updated_at` | `timestamp with time zone` | Sim | `clock_timestamp()` |
| `finalized_at` | `timestamp with time zone` | Não | — |

Campo acrescentado a uma tabela existente: `rm_private.project_attachment_uploads.folder_id uuid`, nullable e sem default. Nenhuma coluna anterior é removida ou reescrita.

### Índices novos

Inclui os índices de PK/unique gerados por constraints.

- `public.rm_docs_project_identity_v1` — `CREATE UNIQUE INDEX rm_docs_project_identity_v1 ON public.rm_docs USING btree (projeto_id, id)`.
- `public.rm_documents_project_identity_v1` — `CREATE UNIQUE INDEX rm_documents_project_identity_v1 ON public.rm_documentos USING btree (projeto_id, id)`.
- `public.rm_document_folders_sibling_name_v1` — `CREATE UNIQUE INDEX rm_document_folders_sibling_name_v1 ON public.rm_project_document_folders USING btree (projeto_id, parent_id, lower(nome)) NULLS NOT DISTINCT`.
- `public.rm_project_document_folders_pkey` — `CREATE UNIQUE INDEX rm_project_document_folders_pkey ON public.rm_project_document_folders USING btree (id)`.
- `public.rm_project_document_folders_projeto_id_id_key` — `CREATE UNIQUE INDEX rm_project_document_folders_projeto_id_id_key ON public.rm_project_document_folders USING btree (projeto_id, id)`.
- `public.rm_document_locations_directory_v1` — `CREATE INDEX rm_document_locations_directory_v1 ON public.rm_project_document_locations USING btree (projeto_id, folder_id)`.
- `public.rm_project_document_locations_anexo_id_key` — `CREATE UNIQUE INDEX rm_project_document_locations_anexo_id_key ON public.rm_project_document_locations USING btree (anexo_id)`.
- `public.rm_project_document_locations_documento_id_key` — `CREATE UNIQUE INDEX rm_project_document_locations_documento_id_key ON public.rm_project_document_locations USING btree (documento_id)`.
- `public.rm_project_document_locations_pkey` — `CREATE UNIQUE INDEX rm_project_document_locations_pkey ON public.rm_project_document_locations USING btree (id)`.
- `rm_private.receiving_drafts_active_actor` — `CREATE UNIQUE INDEX receiving_drafts_active_actor ON rm_private.receiving_drafts USING btree (auth_user_id, operator_id) WHERE (state = 'draft'::text)`.
- `rm_private.receiving_drafts_actor_updated` — `CREATE INDEX receiving_drafts_actor_updated ON rm_private.receiving_drafts USING btree (auth_user_id, operator_id, updated_at DESC, id)`.
- `rm_private.receiving_drafts_pkey` — `CREATE UNIQUE INDEX receiving_drafts_pkey ON rm_private.receiving_drafts USING btree (id)`.

### Foreign keys e demais constraints novas

- `public.rm_docs.rm_docs_project_identity_v1` — `UNIQUE (projeto_id, id)`.
- `public.rm_documentos.rm_documents_project_identity_v1` — `UNIQUE (projeto_id, id)`.
- `public.rm_project_document_folders.rm_project_document_folders_check` — `CHECK ((parent_id IS DISTINCT FROM id))`.
- `public.rm_project_document_folders.rm_project_document_folders_created_by_fkey` — `FOREIGN KEY (created_by) REFERENCES public.rm_users(id) ON DELETE RESTRICT`.
- `public.rm_project_document_folders.rm_project_document_folders_nome_check` — `CHECK (((nome = btrim(nome)) AND ((length(nome) >= 1) AND (length(nome) <= 200)) AND (nome <> ALL (ARRAY['.'::text, '..'::text])) AND (nome !~ '[[:cntrl:]/\\]'::text)))`.
- `public.rm_project_document_folders.rm_project_document_folders_pkey` — `PRIMARY KEY (id)`.
- `public.rm_project_document_folders.rm_project_document_folders_projeto_id_fkey` — `FOREIGN KEY (projeto_id) REFERENCES public.rm_projetos(id) ON DELETE RESTRICT`.
- `public.rm_project_document_folders.rm_project_document_folders_projeto_id_id_key` — `UNIQUE (projeto_id, id)`.
- `public.rm_project_document_folders.rm_project_document_folders_projeto_id_parent_id_fkey` — `FOREIGN KEY (projeto_id, parent_id) REFERENCES public.rm_project_document_folders(projeto_id, id) ON DELETE CASCADE`.
- `public.rm_project_document_locations.rm_project_document_locations_anexo_id_key` — `UNIQUE (anexo_id)`.
- `public.rm_project_document_locations.rm_project_document_locations_check` — `CHECK ((num_nonnulls(anexo_id, documento_id) = 1))`.
- `public.rm_project_document_locations.rm_project_document_locations_documento_id_key` — `UNIQUE (documento_id)`.
- `public.rm_project_document_locations.rm_project_document_locations_pkey` — `PRIMARY KEY (id)`.
- `public.rm_project_document_locations.rm_project_document_locations_projeto_id_anexo_id_fkey` — `FOREIGN KEY (projeto_id, anexo_id) REFERENCES public.rm_docs(projeto_id, id) ON DELETE CASCADE`.
- `public.rm_project_document_locations.rm_project_document_locations_projeto_id_documento_id_fkey` — `FOREIGN KEY (projeto_id, documento_id) REFERENCES public.rm_documentos(projeto_id, id) ON DELETE CASCADE`.
- `public.rm_project_document_locations.rm_project_document_locations_projeto_id_fkey` — `FOREIGN KEY (projeto_id) REFERENCES public.rm_projetos(id) ON DELETE RESTRICT`.
- `public.rm_project_document_locations.rm_project_document_locations_projeto_id_folder_id_fkey` — `FOREIGN KEY (projeto_id, folder_id) REFERENCES public.rm_project_document_folders(projeto_id, id) ON DELETE RESTRICT`.
- `public.rm_project_document_locations.rm_project_document_locations_updated_by_fkey` — `FOREIGN KEY (updated_by) REFERENCES public.rm_users(id) ON DELETE RESTRICT`.
- `rm_private.project_attachment_uploads.project_attachment_upload_folder_v1` — `FOREIGN KEY (projeto_id, folder_id) REFERENCES public.rm_project_document_folders(projeto_id, id) ON DELETE RESTRICT`.
- `rm_private.receiving_drafts.receiving_drafts_auth_user_id_fkey` — `FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT`.
- `rm_private.receiving_drafts.receiving_drafts_check` — `CHECK (COALESCE(((payload ->> 'id'::text) = (id)::text), false))`.
- `rm_private.receiving_drafts.receiving_drafts_check1` — `CHECK ((((state = 'draft'::text) AND (result IS NULL) AND (finalized_at IS NULL)) OR ((state = 'finalized'::text) AND (result IS NOT NULL) AND (finalized_at IS NOT NULL))))`.
- `rm_private.receiving_drafts.receiving_drafts_operator_id_fkey` — `FOREIGN KEY (operator_id) REFERENCES public.rm_users(id) ON DELETE RESTRICT`.
- `rm_private.receiving_drafts.receiving_drafts_payload_check` — `CHECK (((jsonb_typeof(payload) = 'object'::text) AND (octet_length((payload)::text) <= 1048576)))`.
- `rm_private.receiving_drafts.receiving_drafts_pkey` — `PRIMARY KEY (id)`.
- `rm_private.receiving_drafts.receiving_drafts_revision_check` — `CHECK ((revision > 0))`.
- `rm_private.receiving_drafts.receiving_drafts_state_check` — `CHECK ((state = ANY (ARRAY['draft'::text, 'finalized'::text])))`.

O check existente `rm_private.sso_action_permits.sso_action_permits_operation_check` apenas acrescenta as operações `manage_project_documents` e `delete_form_template`; as operações anteriores permanecem admitidas. As colunas obrigatórias das tabelas novas constam acima.

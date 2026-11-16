# Pastas de documentos do projeto — evolução 044

## Discovery e classificação

| Requisito | Estado anterior | Estrutura reaproveitada / entrega |
| --- | --- | --- |
| Documentos do projeto | Implementado | `rm_documentos` (gerados) e `rm_docs` (anexos), consulta unificada e paginada `rm_web_project_documents_v1` da 030. |
| Arquivos privados | Implementado | Bucket `rm-documentos`; upload PDF/JPEG/PNG até 20 MiB, reserva e confirmação 029, URLs e nomes de objetos imutáveis. |
| Versões de anexo | Implementado | Publicação comprovada e versões lineares da 033, com confirmação, contexto e recibos idempotentes. |
| Hierarquia e destino do upload | Não implementado | Metadados relacionais persistentes da 044, integrados aos leitores, upload e recibos existentes. |
| Navegação por diretórios | Não implementado | Breadcrumbs, subpastas por clique e raiz explícita; filtros e paginação conservam a pasta atual. |
| Renomear/mover pasta e mover documento | Não implementado | Mesma operação autenticada e transacional `manage_project_documents`. |
| Exclusão individual do arquivo | Protegida por imutabilidade/versionamento | Mantida a regra existente: este incremento não apaga arquivos publicados nem reescreve seus metadados. Exclusão de pasta só é permitida quando vazia. |

## Modelo e integridade

`public.rm_project_document_folders` contém `id`, `projeto_id`, `parent_id`, `nome`, `created_by`, `created_at`, `updated_at`. `parent_id = NULL` representa uma pasta na raiz do projeto. A raiz não exige registro artificial.

`public.rm_project_document_locations` contém `id`, `projeto_id`, `folder_id`, `anexo_id`, `documento_id`, `updated_by`, `updated_at`. Exatamente uma referência de documento deve estar preenchida. A ausência de localização representa um arquivo na raiz; nenhum registro antigo precisa ser alterado ou copiado.

As FKs compostas associam a pasta, seu pai e cada documento ao mesmo projeto. Não há caminho textual usado como identidade. Índice único com `NULLS NOT DISTINCT` impede nomes de pasta duplicados, ignorando caixa, no mesmo pai, inclusive na raiz. Há índice de localização `(projeto_id, folder_id)`, unicidade individual de `anexo_id` e `documento_id` e unicidade de `(projeto_id, id)` nos dois catálogos documentais. Nomes não aceitam barras, controles, `.` e `..`.

Trigger bloqueia troca de identidade/projeto e ciclos de ascendência. O mesmo lock transacional do projeto usado por recebimentos, upload e exclusão serializa alterações concorrentes de diretórios. Não há limite de um nível ou profundidade fixa. A resposta de navegação limita a consulta a 10.000 pastas por projeto, com falha explícita acima desse volume; isso limita o tamanho da resposta, não a profundidade da hierarquia. Construção de caminhos no frontend é iterativa.

Excluir pasta requer confirmação e pasta sem subpastas, localizações ou reservas de upload pendentes. O bloqueio ocorre no backend, independentemente da interface. Mover pasta exige confirmação e validação de versão. Mover documento exige confirmação e diretório anterior esperado; um movimento concorrente causa conflito. Recibos guardam a alteração anterior para auditoria sem criar outro histórico de arquivos.

## Upload, versões e compatibilidade

O formulário existente permite escolher a pasta de destino, inicialmente a pasta aberta. `folder_id` é opcional no contrato existente de upload; clientes anteriores continuam enviando o mesmo payload. A 044 acrescenta `folder_id` nullable somente ao journal privado `rm_private.project_attachment_uploads`.

A reserva congela o destino e o reconhece no recibo. A confirmação grava a publicação e sua localização na mesma transação. Enquanto pendente, a FK e a validação de pasta vazia protegem o destino. Após publicação, a coluna transitória da reserva é limpa; a localização passa a pertencer ao documento, permitindo movimentá-lo e eventualmente excluir uma pasta já vazia. Retentativas usam os mesmos protocolos e não criam locais ou arquivos duplicados.

Novas versões herdam o diretório da versão de origem no momento da reserva. Movimentar localização não altera `rm_docs`, `rm_documentos`, nome do objeto, bucket, URL, conteúdo, hash ou provas de publicação. A projeção imutável da 033 exclui apenas a nova coluna transitória `folder_id`, preservando byte a byte a projeção anterior e os contextos de substituições já reservadas antes da migração.

O leitor existente permanece global quando `folder_id` é omitido, preservando consumidores antigos. `folder_id: null` seleciona a raiz; UUID seleciona uma pasta pertencente ao projeto. SQL `NULL` como objeto de filtros continua rejeitado como antes. A resposta inclui `navigation` somente para consultas com diretório explícito. Cada origem mantém seus IDs e sua autorização original. O mobile continua podendo ler os documentos existentes; não há alteração de seu contrato de leitura nem de seus dados offline.

## Autorização e exclusão do projeto

As duas novas tabelas têm RLS e somente SELECT para `authenticated`, condicionado ao acesso interno e ao projeto visível. Não há grants de INSERT/UPDATE/DELETE para clientes nem acesso anônimo aos metadados. A leitura web exige `em.portal.read`, `em.projects.read` e `em.documents.read`. Alterações acrescentam `em.projects.manage`, perfis internos `administrador`/`padr_o`, MFA quando configurado e o mesmo canal SSO de permissão vinculada ao payload. Auditor permanece somente leitura. Projetos encerrados permanecem consultáveis, sem alterações.

A closure de propriedade da 039 passa a incluir pastas e localizações no preflight e no token de contexto. Sua ordem de exclusão remove localizações e reservas antes das pastas, mantendo a confirmação, auditoria, tombstones e coleta de arquivos já existentes. Registros de outros projetos e catálogos globais permanecem fora da exclusão.

## Validação específica

- `web_project_document_folders_upgrade.sql`: cria publicação e substituição pendente ainda na 043, aplica a fonte exata 044, compara documentos, uploads pela projeção antiga, recibos e Storage, verifica token original inalterado e conclui a substituição com o protocolo antigo.
- `web_project_document_folders.sql`: raiz/subpastas, 42 níveis, navegabilidade, ambos os tipos de documento, recibos, nomenclatura, confirmação, ciclos, FKs de projeto, RLS/perfis, SSO real do banco, upload atomicamente localizado, versão com diretório herdado, reserva pendente impedindo exclusão, pasta vazia removível e exclusão completa de projeto preservando o vizinho.
- `project-document-folders.test.ts` e regressões do dossiê: 45 testes direcionados aprovados; typecheck aprovado. Incluem validação de metadados ausentes/cíclicos, confirmação do destino antes de gravar no Storage e percurso iterativo com 5.000 níveis.
- QA React/CSS real em 1240 e 390 px: breadcrumbs, links de subpasta, seleção do destino de upload, retentativa congelada, proteção ao sair com envio não confirmado, exclusão dos descendentes no destino de mover pasta, confirmação de exclusão, mensagem de pasta não vazia e ausência de overflow horizontal. Ações desse QA foram simuladas somente no servidor local, sem escritas de negócio.

Os resultados consolidados de build, suítes completas e publicação pertencem ao relatório da entrega conjunta 044–046.

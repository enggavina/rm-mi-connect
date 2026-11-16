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

## Alterações de banco

| Migração | Novas estruturas |
|---|---|
| `044_rm_web_project_document_folders.sql` | `rm_project_document_folders`, `rm_project_document_locations`; coluna nullable `folder_id` em `rm_private.project_attachment_uploads`; uniques de identidade projeto/arquivo; FKs compostas projeto/pai/pasta/arquivo; restrições de nome, autoparentesco e origem única; índices de nome por diretório e localização; RLS e operação SSO do dossiê. |
| `045_rm_mobile_receiving_drafts.sql` | `rm_private.receiving_drafts`; PK UUID, FKs restritivas para Auth/operador, revisão/estado/limite JSON/identidade/resultados coerentes; unique parcial por slot ativo e índice por dono/data; RPC delegada de snapshot e integração atômica no gateway existente. |
| `046_rm_web_form_template_delete.sql` | Sem nova tabela/coluna; guardas de referências em arrays e identidades removidas; operação `delete_form_template` com permissão existente; revisão no snapshot de consulta; consulta de tombstones ampliada. |

Os nomes completos e definições de índices, FKs e constraints estão nas três fontes novas, que são o contrato de instalação. As novas tabelas começam vazias; nenhum dado de negócio artificial é criado na produção.

## Arquivos e validação

Principais áreas: `desktop/src/components/web/project-document-*`, `project-dossier-*`, `project-client-*`, `form-template-*`; leitores/actions/policies correspondentes em `desktop/src/server/web`; páginas de modelos; `mobile/app/recebimento.tsx`, `mobile/src/core/receiving-drafts.ts` e `service.ts`; migrações e novas suítes SQL.

Resultados finais, referências de publicação e instalador serão registrados após a conclusão das validações integradas. O repositório não possui comando/configuração independente de lint; a verificação de whitespace usa `git diff --check`, além de typecheck, testes e build.

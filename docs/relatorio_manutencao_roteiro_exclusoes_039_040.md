# Manutenção do roteiro e exclusões de projetos

Solicitação do anexo `654ae4b0-f257-4dc7-8a23-54de0cda492d`, seção “Novo prompt (Tá quase lá)”, em 06/11/2026. Continuação do EM existente e dos incrementos 037–038. **Implementação validada e publicada em [EM web](https://em-web-production.up.railway.app), com as migrações 039 e 040 aplicadas.**

## Discovery e diferenças encontradas

| Requisito | Estado anterior | Reutilização e evolução |
| --- | --- | --- |
| Excluir projeto | Não implementado; várias FKs e guards impediam remoção inconsistente | Novo comando transacional no gateway atual, com preflight, confirmação, justificativa e evidência mínima. |
| Configurar roteiro na página do projeto | Parcialmente implementado: consulta em Roteiro; edição distribuída pelo Cronograma/Planejar | Mesmos editores de fotos e aprovação passam a atender Roteiro; vínculos de formulários ficam centralizados nessa aba. |
| Proteção granular | Parcialmente implementado: fotos e regras protegidas em parte; faltava cobrir rascunhos e escritas concorrentes | Proteção por foto, formulário e regra, incluindo conteúdo persistido ainda sem registro final. |
| Nova célula no projeto | Parcialmente implementado: alocação existente, sem os três editores no Roteiro | A alocação aparece no roteiro próprio e recebe configuração Projeto + Célula, sem alterar o modelo. |
| Remover célula sem uso | Parcialmente implementado: retirada 028 preservava IDs, mas exigia retirar as configurações separadamente | Retirada conjunta das configurações não utilizadas e da alocação, no mesmo comando. |
| Excluir tipos/títulos | Já implementado no backend, com permissões e confirmação; acesso pouco evidente nas listas | Atalhos Excluir nas listas abrem a confirmação existente; não há outro serviço de exclusão. |

O modelo continua **Projeto ↔ Equipamento → Tipo**, com roteiro próprio em `rm_celulas_projeto`, fotos e regras específicas. O modelo do tipo e os demais projetos não são editados por essas ações. O [discovery de catálogos](discovery_exclusao_catalogos_039.md) registra as exclusões que já existiam; os contratos 025, 027, 028, 037 e 038 foram reaproveitados.

## Exclusão do projeto

O administrador do EM, com a permissão atual de gestão de projetos, abre **Excluir projeto**. O diálogo identifica o projeto e apresenta suas dependências. Justificativa vazia ou composta somente por espaços não é aceita. A exclusão exige confirmação explícita; abrir o diálogo apenas consulta o preflight.

O comando revalida a versão e a prova do contexto, a autorização, o SSO/MFA e as dependências. Projeto, equipamento, roteiro, alocações, fotos, registros/respostas/rascunhos, avaliações, regras, comentários, notificações e documentos exclusivos são removidos em transação. Dependências comerciais e de laboratório só entram quando sua propriedade pelo projeto é comprovada. Vínculos cruzados com outro projeto impedem a operação; não são resolvidos por exclusão ou desvinculação silenciosa.

Clientes, usuários, células globais, tipos, títulos e definições de formulários são preservados. Não há cascade novo sobre entidades globais.

A evidência mínima utiliza o mecanismo de recibos existente: identificação e rótulo do projeto, ator, data, justificativa e protocolo, sem cópia integral do projeto. A prova também impede recriação pelo mesmo UUID ou identificador Bubble. Recibos exclusivos anteriores são reduzidos à identificação e hash necessários para reconhecer envios antigos; recibos compartilhados com outros projetos continuam privados para preservar sua idempotência.

Arquivos privados com propriedade comprovada pelo uploader do dossiê entram em uma fila durável de limpeza via Storage API após o commit. Falhas de rede não recriam o projeto e são retomadas pelo worker independente da ponte Bubble. Arquivos externos, de CDN ou sem exclusividade comprovada não são apagados por suposição.

## Edição granular do roteiro

| Recurso | Alteração permitida | Proteção de uso |
| --- | --- | --- |
| Fotos previstas | Adicionar, retirar/restaurar e substituir título, número, descrição e tag antes da captura | Captura ou seleção para relatório impede substituição/retirada destrutiva. A substituição cria outra previsão e preserva o identificador anterior retirado. |
| Formulários | Adicionar/remover vínculos ainda não utilizados | Registro iniciado, resposta parcial/final ou rascunho persistido relevante preserva o vínculo correspondente. Outros formulários continuam editáveis. |
| Aprovações | Criar, retirar/restaurar e substituir regras ainda não executadas | Configuração que produziu decisão permanece protegida; o fluxo legítimo de liberar/retornar/aprovar não é substituído. |
| Sequência | Reordenar células sem uso dentro dos intervalos permitidos | Células de origem/destino de aprovações executadas conservam sua posição. |

Tag de foto continua sendo um ajuste de metadado permitido pelo fluxo existente, quando não destrutivo. Projetos encerrados e contextos não aplicáveis mantêm suas regras anteriores de consulta. O avanço de outro recurso não impede configurar um formulário, foto ou aprovação ainda sem uso.

Os editores compartilham o contexto exato da célula e não permitem envios concorrentes de sequência, fotos, formulários, regras e remoção pela mesma tela. Falhas de transporte conservam o mesmo UUID e conteúdo na retentativa.

## Inclusão e remoção de células

Uma célula alocada em **Células e projetos** aparece no **Roteiro** e pode receber fotos, formulários e regras próprias. Não reaplica o modelo do tipo depois da inicialização.

**Remover do roteiro** exige confirmação e revalidação no banco. Sem uso operacional, desvincula formulários, retira previsões de fotos e regras não utilizadas e retira a alocação. Segue a regra existente de retirada lógica da célula, preservando IDs para envios offline; isso difere da exclusão física do projeto. Fotos capturadas, conteúdo de formulários, aprovações ou outras evidências relevantes impedem a remoção incompatível.

A seção **Formulários da célula** foi retirada do `CellEditor` de Planejar, inclusive nos consumidores de Cronograma e Fila. Salvar planejamento não envia `forms_ids` vazio nem altera vínculos por ausência dos controles. A gestão desses vínculos fica em **Projeto → Roteiro → Célula → Formulários**.

## Tipos e títulos de fotos

As listas oferecem **Excluir**, abrindo a confirmação já existente. A operação exige o nome confirmado, versão exata e autorização administrativa. Tipos com referências operacionais, modelos ou outras dependências são bloqueados. Títulos utilizados em modelos, previsões ou fotos — inclusive registros retirados necessários ao histórico/offline — também são protegidos. Um GET não executa exclusão.

## Banco e arquivos

Migrações novas [039](../rm-mobile-supabase/migrations/039_rm_web_project_delete.sql) e [040](../rm-mobile-supabase/migrations/040_rm_web_project_route_configuration.sql); as anteriores permanecem imutáveis. Não há nova migração para duplicar exclusões de catálogos já existentes. O [contrato de manutenção do roteiro](../rm-mobile-supabase/WEB_PROJECT_ROUTE_CONFIGURATION.md) detalha os payloads, limites, tratamento offline e reutilização dos fluxos anteriores.

A 039 cria a tabela privada `rm_private.project_delete_files`, sem FK para o projeto removido: os trabalhos de limpeza devem sobreviver ao commit da exclusão. Suas constraints exigem UUID de trabalho, protocolo de exclusão, bucket `rm-documentos`, caminho único no formato `web-dossier/<projeto>/<upload>.(pdf|jpg|png)`, estado permitido, tentativas não negativas e lease com token/prazo somente no estado `leased`. O índice parcial `rm_project_delete_files_due` atende trabalhos pendentes ou com lease; `rm_web_project_delete_tombstone` e `rm_web_project_delete_bubble` indexam os identificadores nos recibos existentes de exclusão. Não se cria uma tabela paralela com cópia do dossiê.

Não são acrescentadas FKs nem ampliados `ON DELETE CASCADE` nas duas migrações. A 039 consulta as FKs reais em `pg_constraint` para impedir dependências compartilhadas fora do conjunto comprovadamente exclusivo, remove os filhos em ordem explícita e mantém as proteções existentes. A exclusão final do projeto utiliza o cascade já existente de `rm_equipamentos.projeto_id`, depois de resolver as referências exclusivas. Novos vínculos por arrays de documentos e URLs de arquivos também recebem guards, pois não são cobertos por uma FK. O desvio dos guards de integridade durante a exclusão exige o recibo privado do mesmo ator e da mesma transação.

| Grupo de dependências | Tratamento no banco |
| --- | --- |
| Execução exclusiva do projeto | Remoção de alocações, fotos, registros, respostas/rascunhos, avaliações, logs, comentários, notificações, documentos, designações de avaliadores e decisões web, antes do projeto. |
| Comercial e laboratório | Propostas de controle/orçamento, ordens e componentes de serviço, fichas e itens de delineamento, desmontagem e ensaios entram somente quando a propriedade exclusiva pelo projeto/equipamento/ordem é comprovada. |
| Contexto privado exclusivo | Remoção de eventos de regras/disponibilidade/equipamento, instância do roteiro, revisões de comentários e registros de upload/versões de anexos; arquivos comprovados seguem para a fila de Storage após o commit. |
| Protocolos e integração | Recibo mínimo da exclusão permanece. Recibos exclusivos anteriores são reduzidos a identificadores/hash; recibos compartilhados ficam preservados. Eventos exclusivos da outbox são removidos, e identificadores Bubble excluídos passam a ser filtrados na importação. |
| Entidades globais ou compartilhadas | Clientes, usuários e identidades, células globais, tipos, títulos, definições de formulários/modelos e dados de outros projetos são preservados. Referência cruzada incompatível bloqueia toda a exclusão. |

As funções principais da 039 são `rm_web_project_delete_snapshot_v1`, `project_delete_scope_v1`, `project_delete_context_v1` e `project_delete_has_shared_fk_v1`, integradas ao `web_mutate_core_v1` existente. `project_deleted_v1` e os guards impedem recriação; `rm_deleted_bubble_ids_v1` atende o filtro da importação. `rm_project_delete_files_claim_v1`/`finish_v1` oferecem lease e retentativa ao worker por `service_role`, sem conceder acesso direto à tabela privada. O [contrato de exclusão](../rm-mobile-supabase/WEB_PROJECT_DELETE.md) documenta a propriedade dos registros, tratamento dos recibos e limites de arquivos/offline.

A 040 acrescenta somente a coluna operacional `rm_aprovacoes_etapas.configuracao_utilizada boolean not null default false`, sem backfill ou reconstrução de decisões antigas. O trigger de selo preserva uso anterior quando o estado de decisão é redefinido legitimamente. Outros quatro triggers protegem vínculos de formulários/rascunhos, configuração de fotos utilizadas e estado de regras utilizadas. A consulta nova `rm_web_project_route_cell_snapshot_v1` usa `route_cell_form_used_v1` e `route_cell_removal_metadata_v1`; os snapshots de roteiro/fotos, a prova de regras e a projeção de histórico existentes são estendidos. O gateway recebe `manage_project_route_cell` e a substituição de foto com UUID novo; retirar uma célula mantém suas identidades de recuperação, conforme a regra 028.

Nas duas migrações, `sso_action_permits_operation_check` é estendido para as novas operações. O mapa de SSO mantém as capabilities existentes: `delete_project → em.projects.manage` e `manage_project_route_cell → em.planning.manage`. As novas funções privadas de gestão não concedem execução aos papéis da aplicação; os RPCs públicos preservam suas verificações de perfil, SSO e MFA. Os helpers de leitura anteriores conservam seus ACLs.

Arquivos principais:

- Interface do projeto: [página do projeto](../desktop/src/app/(portal)/projetos/[id]/page.tsx), `project-delete-button.tsx`, `project-route-workspace.tsx`, `project-route-forms-editor.tsx`, `project-route-cell-removal.tsx` e os estilos correspondentes.
- Ações, leitura e validação: `desktop/src/server/web/project-delete-*`, `project-route-cell-*`, `operational-photo-*`, `project-route-*`, além de `mutation.ts` e das políticas existentes.
- Editores reutilizados: `desktop/src/components/web/operational-photo-editor.tsx`/`operational-photo-model.ts`, `operational-stage-rule-editor.tsx`, `project-route-editor.tsx`/`project-route-model.ts` e `editor.tsx`, que deixa de enviar vínculos de formulários no planejamento.
- Limpeza e importação: [worker de limpeza](../desktop/src/server/web/project-delete-cleanup.ts), [instrumentação](../desktop/src/instrumentation.ts), `desktop/src/server/bridge/deleted-projects.ts`, `batch-importer.ts`, `etl.ts` e `engine.ts`.
- Catálogos: páginas/listas de tipos e títulos, `catalog-editor.tsx`, `engineering-title-editor.tsx` e os testes dos comandos existentes; ver [discovery específico](discovery_exclusao_catalogos_039.md).
- Verificação: `desktop/tests/project-delete.test.ts`, `project-route-cell.test.ts`, testes de fotos/roteiro/catálogos/importação e `rm-mobile-supabase/tests/web_project_delete*.sql`, `web_project_route_configuration*.sql`, integrados ao runner isolado.

## Validação e publicação

| Verificação | Resultado |
| --- | --- |
| Testes web | 446 aprovados. |
| Testes mobile | 103 aprovados; sem alteração do código mobile ou geração de APK. |
| Contrato QR web/mobile | Dois testes integrados aprovados. |
| PostgreSQL | Suíte completa de 39 fontes de migração e 33 arquivos funcionais, incluindo upgrades e concorrência, aprovada em banco descartável. As migrações anteriores não foram editadas; todos os hashes ficaram estáveis durante a execução. |
| Novas disputas reais | 14 da exclusão e sete da manutenção do roteiro, além das disputas legadas preservadas. |
| Tipos e build | Typecheck web/mobile, build Next e dois smokes de runtime/autenticação aprovados. |
| Lint | O repositório não possui script/configuração de ESLint independente. `git diff --check` passou; não se declara execução de um lint inexistente. |
| Navegador | React e CSS reais em desktop e 390 px: confirmação/justificativa, retentativa, proteção granular, recursos sem uso, edição exclusiva e Planejar sem controles de formulários. Ações simuladas, sem excluir projetos reais. |
| Segredos no JavaScript | 79 arquivos do build local verificados contra dez segredos locais conhecidos, sem ocorrências. |
| CI | [Dois jobs aprovados](https://github.com/enggavina/rm-mi-connect/actions/runs/42288309896), Node 22, no commit `06227c0b44d17e4b56df7efba916baf0f72619b9`. |

O ensaio com rollback e a aplicação no Supabase preservaram integralmente as **83 tabelas anteriores** (75 RM/privadas e oito relações de Storage), comparando os valores de todas as colunas antigas. Também preservaram 113 OIDs, owners e ACLs de funções, policies, índices, triggers e constraints anteriores, exceto as alterações explicitamente previstas e conferidas contra o manifesto compilado independente. Os corpos alterados e as novas funções foram verificados nesse manifesto, totalizando 138 funções. A instalação deixou a fila de limpeza vazia e o selo novo falso nas linhas antigas, sem backfill ou DML operacional.

O histórico 001–017 já possuía somente metadados, com `statements=[]`; foi preservado exatamente assim. As fontes armazenadas de 018 em diante coincidiram com os hashes locais. Nenhuma linha antiga do histórico foi preenchida ou reescrita. As fontes novas, árvore local, índice Git, commit e histórico aplicado conferem:

- 039: `4a51278757e6f2e275c9dd3b0ca196f4c524611fb72b968783754f499ea7065f`.
- 040: `351b9fbd8d254b414406e466c06377c7549bc0abb95841a9d2283b44300ca8e6`.

Após instalar, a consulta observou 76 tabelas RM/privadas, 57 públicas RM com RLS, 180 projetos, 179 equipamentos, 1.449 alocações, 778 registros, 61.803 respostas, 14.737 fotos, 94 comentários, 102 usuários, outbox 4 e 21 recibos web. São contagens daquele instante; a prova de preservação é o snapshot transacional da instalação, sem presumir ausência de uso legítimo da produção. Os dois administradores EM, SSO e os três buckets/13 objetos permaneceram. Nove DTOs reais de roteiro/célula/preflight passaram em três projetos existentes, em transação somente leitura, sem excluir dados ou autenticar uma pessoa pela Microsoft.

Consumidor `06227c0b44d17e4b56df7efba916baf0f72619b9`; deploy Railway `8944f2f1-1a4e-44ba-8555-96991e70e822` com **SUCCESS**. Destino exclusivo: [portal EM](https://em-web-production.up.railway.app), Supabase `oficina-em-mi-off`. `EM_PROJECT_DELETE_CLEANUP_ENABLED=true` habilita somente a limpeza privada de anexos; `SYNC_OUTBOX_ENABLED=false` continua desativando a ponte Bubble.

Após o deploy, health 200 e **108 verificações públicas de acesso** passaram: 92 negações em 46 URLs com anônimo/cookie forjado e 16 recusas nas APIs. O início nativo do SSO conferiu origem, POST 303 e navegação até Microsoft. Somente o fluxo próprio de QA foi cancelado; nenhum login humano ou CRUD artificial de produção foi automatizado. A exclusão real de projetos foi validada no banco descartável, não em dados de clientes.

Provas locais ignoradas: `.tmp/maintenance-{ci,deployment,environment}-proof.json`, `maintenance-sql-full-proof.json`, `maintenance-manifest-proof.json`, `maintenance-envelope-local-proof.json`, `maintenance-039-040-{rehearse,apply}-proof.json`, `maintenance-prod-postflight.json`, `maintenance-prod-rpc-proof.json`, `maintenance-public-qa.json`, `maintenance-public-sso-qa.json`, `maintenance-browser-secret-audit.json` e logs `maintenance-*`.

## Limites preservados

Envios offline de um projeto excluído são recusados pelo servidor e permanecem no dispositivo, com protocolo, ator, conteúdo e arquivos preservados para reconciliação. A fila FIFO existente pode aguardar essa intervenção; não se apresenta uma exclusão como envio concluído nem se apagam rascunhos automaticamente. O catálogo local já possui reconciliação por manifesto de IDs para retirar registros apagados sem limpar os trabalhos locais.

Não há garantia de purga de arquivos externos ou de URLs legadas sem propriedade exclusiva comprovada. A revisão dos sete destinos de modelos identificados na entrega anterior continua sendo uma pendência de cadastro separada deste desenvolvimento.

Os requisitos funcionais deste prompt foram implementados. A retirada lógica da célula segue o contrato existente e preserva identificadores de recuperação; o projeto, por sua vez, é excluído fisicamente. A homologação por usuários reais e a reconciliação de envios offline recusados continuam sendo atividades operacionais, sem testes destrutivos artificiais em produção. A paridade global e o gerador visual de relatórios continuam no plano geral e não são declarados concluídos por esta entrega.

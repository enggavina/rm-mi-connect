# Discovery do roteiro próprio do projeto — 05/11/2026

Solicitação de referência: anexo `541c8159-217f-4325-8e3a-3d123ad27859`. Esta análise continua a aplicação EM existente; o Bubble `rmmi`, versão `live`, foi consultado somente para leitura.

## Evidência no Bubble

| Área | Evidência Live consultada | Regra encontrada |
| --- | --- | --- |
| Modelo de roteiro | `rm_gestao` / `coQKn0`; evento `conKI`, ação `conKO` | `Celula_Tipo_Equipamento`, vínculos de formulários e fotos, aprovação com listas de aprovadores na origem e no retorno. A criação de aprovação exige as duas listas não vazias. O modelo não é a alocação operacional. |
| Projeto | Página `projeto` / `coiiy`; grupos `comiK/comiR/comii` e `cojtC/cojtc` | Comentários usam a entidade `Comentarios`. Histórico e auditoria são outra seção. O histórico legado consulta alocações pelo projeto e ordena por Modified Date; isso não fornece automaticamente valores anteriores de todos os campos. |
| Fila e edição de alocação | `rm_planejamento` / `cnsnM`; popup `colsk`; evento `colzC`, ações `colzM` e `coqyU` | O registro editado é `Celula_Projeto`. `colzM` altera prazo, observação, status, posição, ordem do status, Modified By, início, fim real, prioridade, horas previstas, bloqueio e motivos de bloqueio/atraso, além de acrescentar o status à lista histórica. |
| Finalização legada | Ação `coqyU` | Oculta a alocação quando Finalizado e sem regras, com formulários e fotos obrigatórias atendidos. Essa condição não autoriza edição livre de status na nova arquitetura. |
| Campos da alocação | Tipo `custom.celula_projeto` | Inclui também responsáveis, horas realizadas, equipe, oficina, dependência textual, criticidade, progresso, perda Lean e datas/autor de replanejamento. Existência no tipo não significa que todo campo seja livremente editável no fluxo inspecionado. |

As evidências detalhadas anteriores continuam válidas em [discovery de planejamento](discovery_rmmi_planejamento.md) e nos contratos de Engenharia, fotos operacionais, regras de etapas, fila e disponibilidade em `rm-mobile-supabase`.

## Lacunas antes da alteração

| Requisito | Classificação encontrada | Reutilização |
| --- | --- | --- |
| Criação conjunta de projeto e equipamento | Implementado na 036 | `save_project_with_equipment`, `ProjectEditor`, validação e recibos existentes. |
| Tipo no equipamento durante o cadastro | Divergente | O tipo estava classificado no projeto antes da primeira alocação. A 037 adapta o mesmo fluxo, preservando o campo legado para compatibilidade. |
| Cópia de fotos, formulários e aprovações | Parcial | A 018 materializava dependências ao alocar uma célula. Faltava inicializar todo o roteiro no cadastro e congelar o contexto do modelo para novas células do projeto. |
| Ordem do roteiro próprio | Implementado | Snapshot/ação da 024, adaptados pela disponibilidade da 028, e `ProjectRouteEditor`; independentes de `posicao`, que pertence à fila. |
| Aba Roteiro | Não implementado na página do projeto | Reutiliza o editor de sequência existente e consulta os mesmos editores operacionais 025/027, em modo de leitura. |
| Comentários e auditoria | Divergente | O antigo painel Histórico combinava comentários e estados atuais de aprovação. Os comentários mantêm suas tabelas, autores, datas, filtros, notificações e detalhes. |
| Auditoria de alocações | Parcial | Existem recibos e eventos preservados. A 038 projeta essas evidências, sem criar uma segunda escrita de auditoria nem inventar valores antigos. |
| Edição na Fila da célula | Parcial | A fila editava prioridade e ordem. O mesmo `CellEditor`/`plan_cell` e `AllocationPlanningPanel` passam a atender o contexto selecionado da fila. |

## Composição web

- **Roteiro** apresenta exclusivamente as alocações ativas persistidas no projeto, em ordem de `indice`. A sequência conserva o mesmo comando transacional existente. Consultar uma célula mostra seus formulários vinculados, fotos previstas/capturadas e regras com origem, destino, aprovadores e estados, conforme as permissões específicas. O link de configuração abre o cronograma existente.
- **Células e projetos** mantém a gestão de alocações e inclui o histórico de alterações dessas relações, com paginação independente.
- **Comentários** contém somente a comunicação dos usuários. URLs e filtros passam a usar `tab=comentarios`; favoritos antigos com `tab=historico&comment_*` conservam a consulta de comentários.
- **Histórico** contém a auditoria operacional de fotos, formulários e aprovações. Não recebe cópias dos comentários.
- **Fila da célula** oferece “Dados da alocação” com o UUID da alocação. A seleção exige correspondência de ID, projeto, célula e revisão exata entre a fila e a alocação. Datas, responsável, horas previstas, prioridade, bloqueio, motivos, observação e vínculos de formulários usam `plan_cell`. Disponibilidade e retirada/restauração usam os comandos existentes. Enquanto o contexto da alocação está aberto, a edição global da ordem/prioridades da fila fica desabilitada para evitar dois envios simultâneos.

Status, fim real e horas realizadas continuam sob as regras de execução e aprovação. Não foi introduzido um dropdown capaz de ignorar formulários, fotos ou decisões. Equipe, oficina, dependências textuais e outros campos sem edição funcional confirmada permanecem preservados. O motivo do atraso foi incorporado à validação e ao comando de planejamento existentes.

## Compatibilidade e verificação da interface

A interface compara o conjunto completo de IDs/revisões do roteiro com o contexto do projeto antes de apresentar detalhes por célula. Um resultado parcial ou alterado solicita recarga. As consultas de fotos e regras têm validações próprias e não recorrem ao modelo do tipo. Projetos legados sem marcador de inicialização continuam exibindo suas alocações preservadas e não recebem aplicação automática de um modelo.

Testes direcionados verificam separação de abas, favoritos antigos, escopo exato da fila e reconciliação do roteiro. O ensaio local em Chromium com React e CSS reais verificou ordem por IDs, modo de consulta, payload de edição da alocação, motivo de atraso, links de contexto, comentários preservados e ausência de transbordamento horizontal em 375 px. As ações foram simuladas nesse ensaio; ele não substitui os testes SQL de integração nem um login humano em produção.

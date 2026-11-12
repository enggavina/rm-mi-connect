# Discovery — status da alocação, tipo do equipamento e Excel

Data: 12/11/2026. Continuação do EM no baseline `8ce19ad`, conforme anexo `c164945a-f17e-445d-9e20-a916326d756b`. Fonte funcional: Bubble `rmmi`, versão **Live**, somente leitura. Destino: portal EM existente e Supabase `oficina-em-mi-off`. Não houve edição do Bubble, execução dos workflows, criação de registros, chamada de exportador legado ou mudança de permissões.

## Consulta atual do Bubble

O primeiro `get_app_outline` teve timeout. As leituras seguintes de nós específicos funcionaram e confirmaram os IDs da análise anterior. A cobertura atual é dos 11 nós abaixo, não uma nova auditoria de toda a aplicação. Evidência bruta local ignorada pelo Git: `.tmp/discovery-planning-status-041.json`.

| Nó Live | Evidência relevante |
| --- | --- |
| `custom.celula_projeto` — `Celula_Projeto` | `Status` é `status_option_status_cel_proj`, uma referência ao Option Set `option.status_cel_proj`. `Projeto` é `projeto_custom_projeto_rm` e `Celula` é `celula_custom_celulas`; não se trata do status global do projeto. |
| `option.status_cel_proj` — `Status Cel Proj` | Dez valores atuais, com atributo numérico `ordem0`; os novos rótulos solicitados não estão presentes. |
| Página `cnsnM` / grupo `comJg` — `rm_planejamento` / `Gestao_projeto_redesign` | Composição de células por projeto: menu de alocação, projeto selecionado e lista de alocações. Não é apenas um Gantt. |
| `comBj` — `FloatingGroup Adicionar celula projeto` | Tipo de conteúdo `ProjetoRM`; é o contexto de criação da relação. |
| `comCZ` — `Dropdown Status` | Obrigatório; usa todos os valores de `Status Cel Proj`, filtrando `retornado` da criação. |
| `comCm` → `comCr` | Evento permite criar quando a célula ainda não pertence à lista do projeto. `NewThing` cria `Celula_Projeto`, gravando o valor de `comCZ` em `status_option_status_cel_proj`, junto das relações, datas e índice. Grava `visibilidade=false`. Não altera o projeto global. |
| `copEL` — `FloatingGroup Editar celula projeto` | Tipo de conteúdo `Celula_Projeto`; edita a relação selecionada. |
| `copFB` — `Dropdown Status edt` | Obrigatório; valor inicial é o status da alocação atual e oferece os dez valores, sem o filtro de `retornado` da criação. |
| `copGn` → `copGz` | `ChangeThing` altera início, limite, status e observação no `Celula_Projeto` de `copEL`. Não escreve o status global do projeto e não há condição adicional no evento inspecionado. |

Valores Live encontrados:

| Chave | Rótulo |
| --- | --- |
| `atrasado` | Atrasado |
| `para_execu__o` | Para execução |
| `em_dia` | Executando |
| `finalizado` | Finalizado |
| `n_a` | N/A |
| `pendente` | Pendente |
| `retornado` | Retornado |
| `liberado_para_ensaios_parciais` | Liberado para ensaios parciais |
| `liberado_para_impregna__o` | Liberado para impregnação |
| `liberado_para_montagem` | Liberado para montagem |

**Aguardando coleta** e **Coletado** são extensões solicitadas para o EM, não funcionalidades alegadamente encontradas no Live. O Bubble permanece intacto e a ponte de saída permanece desativada. A regra de visibilidade atual do EM não deve ser trocada pelo default legado como efeito colateral deste pedido.

## Modelo e componentes locais

O banco já usa `rm_celulas_projeto.status`, tipado por `rm_status_cel_proj_enum`, e `rm_option_sets` para rótulos/opções. `rm_projetos.status` e `status_pcp` são campos distintos. A criação/edição da alocação passa por `plan_cell`, com SSO/MFA, perfil operacional, versões e recibos existentes. A interface reutilizável é `CellEditor`; seus consumidores abrangem projeto, Cronograma e Fila. O status atual já era exibido por cards/listas, mas faltava seu controle no editor web.

O histórico 038 já projeta recibos de alocação como `allocation_created`/`allocation_changed`, e o componente `ProjectAuditPanel` já reconhece o campo `status` e os pares anterior/novo. A mudança deve estender esse mecanismo, sem criar outra tabela de auditoria. Regras de encerramento, disponibilidade, retirada, decisão de etapas e gravação mobile continuam sendo revalidadas pelo banco; o dropdown não concede permissão para contorná-las.

O projeto carrega seu equipamento por `rm_web_project_equipment_snapshot_v1`, que fornece o estado do vínculo e a relação bidirecional comprovada. O editor de classificação também possui um fallback legado para projetos sem equipamento. Esse fallback **não é apropriado para a nova informação exibida**: o pedido exige Projeto → Equipamento → Tipo. A leitura nova usa somente `snapshot.equipment.tipo_equipamento_id`, desde que o snapshot corresponda ao projeto atual e ao equipamento próprio. A busca de `rm_tipos_equipamento` seleciona apenas `id,nome,sigla`, por UUID exato, com JWT e permissões de leitura de projeto; utiliza `equipmentTypeLabel` para o formato `SIGLA - NOME`.

Projetos encerrados continuam mostrando o tipo se o vínculo for comprovado; essa leitura não depende de `can_edit`. Ausência de equipamento/tipo, vínculo compartilhado/inconsistente, snapshot divergente ou cadastro não encontrado produzem `Não informado`, sem usar a classificação global legada do projeto. Falha de consulta é apresentada como indisponibilidade, sem quebrar o dossiê ou substituir dados técnicos existentes.

O botão de nova alocação era imediatamente seguido pelo painel de histórico. O contêiner `allocationActions` aplica a distância de 24 px já utilizada nos painéis do design existente, inclusive quando o editor está recolhido. O espaçamento também foi conferido com o editor aberto. Não há novo estilo inline.

## Gap analysis do baseline

| Requisito | Classificação inicial | Evolução prevista |
| --- | --- | --- |
| Status na criação de alocação | Parcialmente implementado: coluna e comando já existem; editor e payload web não ofereciam status | Reutilizar `plan_cell` e `rm_celulas_projeto.status`, preservando os demais campos. |
| Status em Planejar | Parcialmente implementado: leitura e planejamento existentes | Mesmo `CellEditor` e gateway, com valor atual, controle de versão e revalidação. |
| Auditoria do status | Parcialmente implementado: infraestrutura e apresentação do campo já existem | Acrescentar a escrita ao recibo/contexto existente, com anterior/novo e ator do servidor. |
| Aguardando coleta / Coletado | Não implementado no enum/opções do baseline nem encontrado no Bubble Live | Migrações aditivas e atualização das listas/labels que utilizam o enum, sem remover valores atuais. |
| Espaçamento de alocação/histórico | Divergente: botão e painel sem distância própria | Wrapper CSS com espaçamento do sistema existente. |
| Tipo em Informações do projeto | Parcialmente implementado: relações e formatter existem; campo não aparecia | Leitura exata via equipamento, sem duplicação ou fallback global do projeto. |
| Excel configurável de alocações | Não implementado no baseline | Gerar XLSX real no servidor a partir de Projeto + Célula; seleções e autorização no backend; uma worksheet por célula. |

## Escopo da exportação

No baseline, `Planejamento` já oferece filtros/paginação de alocações, a lista de células e rótulos de status, e usa `em.planning.read`. Esses filtros da consulta não devem truncar silenciosamente uma exportação de todas as alocações das células escolhidas. A unidade de consulta é `rm_celulas_projeto`, mantendo linhas distintas do mesmo projeto quando ele está em duas células. O conjunto de campos deve vir das colunas reais de projeto, equipamento, tipo, célula e alocação, com representações legíveis.

O pedido de Excel é uma evolução do EM, não uma declaração de paridade com um exportador Bubble. Foram consultados a entidade, opções, fluxos de criação/edição e composição equivalente do planejamento. Não foi executada exportação no sistema original. O contrato final de seleção de campos, autorização, limites e geração XLSX e as provas da entrega integrada são documentados pelo relatório desta implementação.

## Validação desta parte

Testes direcionados de leitura/apresentação cobrem tipo canônico divergente da classificação legada, ausência de vínculo/tipo, vínculo incorreto/compartilhado/desatualizado, projeto encerrado, exigência das capacidades de leitura, consulta única com projeção mínima, referência inexistente e resposta inesperada sem exposição de detalhes privados. As alterações de enum/status e o exportador têm suítes próprias na mesma entrega. A publicação e os resultados completos ficam no relatório integrado, sem CRUD artificial de produção.

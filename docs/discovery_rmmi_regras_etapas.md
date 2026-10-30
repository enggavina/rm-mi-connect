# Regras operacionais de etapas — PL020, PL021 e PL022

Discovery em 30/10/2026. Bubble `rmmi` **Live somente leitura**; destino conferido por nome `oficina-em-mi-off` e referência `ellpxfbsrbhblyizvbbk`. Nenhum workflow foi executado, nenhuma carga foi preparada e nenhum dado foi alterado. O escopo é editar a configuração de instâncias de projeto; decisões e modelos de Engenharia continuam nos contratos existentes.

## Contrato Live confirmado

| Caminho | Comportamento efetivamente configurado |
| --- | --- |
| PL020: `conPF`, `conPL`, `conQT → conQY → conhK` | O primeiro toggle só exibe o formulário; não grava banco. Criar exige aprovador de origem e retorno não vazios. `conPw` exige status e exclui Retornado; `conPp` exige destino escolhido das células alocadas ao projeto. `contE` lista as Identidades dos vínculos Tablet_Celula_User da origem; `copnh`, as do destino. Não há filtro explícito de usuário ativo nesses dropdowns. |
| Criação `conQY` | Cria **uma regra forward** com projeto, origem, destino, status-alvo, lista geral e lista de retorno. Não define explicitamente status de decisão nem vínculo/bloqueio. `conhK` adiciona seu ID à lista da alocação de origem; depois reseta inputs. Não cria inversa nesse evento. |
| PL021: `conPY`, `contX`, `conPe`, `copoF` | Autobinding do status-alvo, aprovadores gerais, destino e aprovadores de retorno. PL021 controla a disponibilidade; linhas Retornado têm status/aprovadores/destino desabilitados e retorno oculto. A condição `status is not Nulo` está presente, mas tem **`overrides: []`**: ela não produz bloqueio efetivo nos quatro inputs. Não afirmar que o Bubble impede a edição de regra já aplicada. |
| PL020: `coqrl → coqsD/coqsP → coqsK/coqsU` | Eventos condicionados ao estado do toggle gravam vínculo true/false na regra. O toggle é ocultado quando falta PL020 ou o status-alvo é Retornado. Não há condição efetiva de decisão pendente para essa gravação. |
| PL022: `conRI → conQI` | Ícone indisponível sem PL022 e oculto em Retornado. `coqBA` apresenta erro se status diferente de Nulo. `coqAq` exclui a **primeira** inversa encontrada por mesmo projeto, origem/destino trocados e status-alvo Retornado; sua condição só verifica que a **regra atual** está Nulo. Não verifica o status da inversa nem sua unicidade. `conQN` exclui a atual somente se Nulo; `conQO` notifica. |

A privacidade de `custom.aprovador_projeto` concede autobinding dos campos de configuração a usuário logado e leitura ampla. Isso é evidência do legado, não um modelo de autorização para ampliar RLS/SSO no EM. A capacidade administrativa do editor deve ser explícita e independente de decidir uma etapa.

## Quando a inversa nasce e como o ciclo funciona

O workflow mobile **ativo** `copmq` (`workflow_disabled=false`) executa a liberação quando o status-alvo da regra corresponde ao status da alocação. Sua ação `copnU` cria uma regra de retorno com mesmo projeto, origem/destino trocados, status-alvo **Retornado** e lista de aprovadores igual à lista de retorno da forward. A condição de criação busca ausência de uma regra de par inverso com **status de decisão Reprovado**; não busca ausência de qualquer Retornado. Assim, a metadata permite criar outra inversa mesmo havendo uma pendente/aprovada. O status inicial não é escrito explicitamente nessa NewThing.

`copmx` adiciona o resultado à lista da alocação destino. `copqo` procura uma inversa Reprovada e reabre para Nulo, limpando autor/data. `coqrY`, quando vínculo=false, torna o destino visível e Pendente. Os caminhos de decisão também possuem logs e efeitos externos legados; o editor de configuração não deve executá-los.

O consumidor EM vigente é a transação da migração 011, preservada pela 020. Na liberação, busca a primeira inversa **Retornado** por `created_at,id`; cria apenas se não houver e reabre se estiver Reprovada. Isso já evita a duplicação específica da condição Bubble, mas não corrige ambiguidades históricas existentes. Ao retornar, reabre as forwards aprovadas do par e muda a alocação destino para Retornado; ao liberar, o vínculo governa a disponibilidade do destino. Não criar inversa antecipadamente ao salvar configuração nem alterar essa máquina de estados como efeito implícito do editor.

Uma regra Nulo hoje pode ter sido reaberta após decisão: os próprios fluxos limpam autor/data. Logo, “pendente no estado atual” não comprova “nunca utilizada”. Logs legados são por projeto/célula, sem vínculo exato à regra; não atribuir a cada etapa todo o histórico da célula.

## Estado real do destino

Snapshot de leitura: **2026-10-30 12:21:51 UTC**, sem PII textual. SHA-256 do arquivo de referências/estados: `4578fba01a5a4ab753ea52718d33bf232eab29bffa3d89c52ffb3d6fa3c2ea93`. Evidências detalhadas ficam no diretório ignorado `.tmp/stage-rules-discovery/`.

| Indicador | Quantidade |
| --- | ---: |
| Etapas totais / projetos / modelos | 945 / 875 / 70 |
| Projetos: Aprovado / Nulo / Reprovado | 467 / 407 / 1 |
| Modelos: Nulo | 70 |
| Status-alvo de projeto: Finalizado / Liberado para montagem / Pendente / Retornado | 747 / 21 / 12 / 95 |
| Forward / retorno | 780 / 95 |
| Forward pendentes / retornos pendentes | 349 / 58 |
| Etapas com vínculo direto `celula_projeto_id` nulo | 875 |
| Origem resolvida por projeto+célula / sem alocação de origem | 781 / 94 |
| Destino sem alocação / destino nulo | 88 / 0 |
| Projetos encerrados / etapas inativas / destino igual à origem | 0 / 0 / 0 |
| Decisões web com vínculo exato (`rm_web_stage_decisions`) | 0 |
| Forward com zero / uma / múltiplas inversas Retornado | 675 / 79 / 26 |
| Pares Retornado duplicados / suas linhas | 13 / 26 |
| Contextos projeto+origem+destino+status-alvo duplicados / suas linhas | 110 / 294 |
| Duplicatas com estados de decisão distintos | 5 |
| Retornos sem forward correspondente | 0 |
| Forward pendente com inversa atualmente decidida | 0 |
| Forward: vínculo false / true | 357 / 423 |

**A lista `cp.aprovacoes_etapas_ids` não existe no EM.** A inspeção de `information_schema.columns`, DDL002 e mapping confirmou zero colunas de aprovações em `rm_celulas_projeto`. A lista Bubble `celula_aprov_tipo_equipamento_list_custom_aprovador_projeto` não foi mapeada no ETL. O EM resolve pelo vínculo direto quando existente e pelo par único projeto+célula de origem para o legado. Isso não autoriza preencher os 875 vínculos nem criar uma lista por inferência. O novo editor pode reutilizar a resolução comprovada, preservando os IDs existentes.

Das 349 forward pendentes, 88 não têm alocação de origem e 81 não têm destino alocado; 104 têm lista geral vazia e 258 têm lista de retorno vazia. Só dez têm uma inversa existente; nenhuma tem múltiplas inversas no estado atual. Entre todas as 780 forward, 120 têm lista geral vazia, 532 têm lista de retorno vazia e 75 não têm aprovador individual nem lista geral. Há 322 com algum aprovador geral que não satisfaz hoje o critério de usuário ativo+Identidade vinculada à origem; nenhum aprovador de retorno existente falhou nesse critério. Isso descreve dados históricos, não um convite a apagar aprovadores ou fabricar vínculos.

Uma consulta Live mínima encontrou **2.363 registros** de Aprovaçao_etapas na origem, com modificação mais recente em 30/10/2026 11:27:19 UTC; o cache de export anterior possui 2.298. O EM contém o recorte importado de 945. Não concluir que os demais devam ser carregados neste módulo: a seleção de projetos e as referências de cada entidade exigem reconciliação própria.

Consulta agregada complementar em **12:25:49 UTC**: 523 logs legados (499 Aprovado, 24 Reprovado), três recibos mobile, dos quais um da transição de etapa, quatro recibos web e zero transições web, e quatro eventos totais de outbox. Nenhuma das 407 etapas pendentes aparece diretamente no recibo mobile de transição. Há logs da mesma origem/projeto para 26 pendentes, incluindo 14 forward, mas o log não contém `aprovacao_etapa_id`: isso não comprova que cada uma dessas regras foi usada. Das 349 forward pendentes, **257 possuem ambas as alocações**, um ponto de partida para o editor; não equivale a 257 regras já validadas para qualquer alteração, pois escolhas/duplicatas/versões ainda exigem conferência. Há 90 forward pendentes em contextos com outra regra de mesmo projeto/origem/destino/status-alvo. A consulta não retornou tokens, conteúdo dos recibos, observações ou payload da outbox.

## Recomendações para a entrega

1. Expor configuração por projeto/alocação, com leitura completa de forward e Retornado, preservando as duplicatas e mostrando inconsistências. Manter retorno e legado não resolvido somente para consulta.
2. Usar `em.planning.manage` com sessão RM/SSO/MFA e leituras necessárias; não reutilizar `em.approvals.decide` ou Engenharia para alterar instâncias. Novas escolhas devem usar usuário ativo e vínculo por **Identidade** à célula, sem criar Auth, usuário ou ACL.
3. Criar somente a forward, com status inicial Nulo e vínculo explicitamente definidos. Não materializar modelos de novo, não criar inversa no salvamento e não importar/backfill nesta entrega.
4. Tratar status Nulo apenas como estado atual. Recomenda-se uma proteção EM maior: regra decidida, com metadado/histórico exato de uso ou Retornado fica somente para consulta. Decidir explicitamente o comportamento de uma pendente reaberta antes de chamar essa política de “nunca usada”.
5. Não repetir a exclusão `first item` do Bubble. Remover somente a regra identificada e, se o contrato realmente permitir remover inversa, exigir par único, sem uso e sem compartilhamento por outra forward. Ambiguidade deve bloquear com motivo e preservar ambos os IDs. O editor não deve apagar logs/decisões.
6. Usar locks do projeto e das linhas afetadas, versões exatas do conjunto, recibo idempotente e disputa com mobile/liberação/modelos/materialização. Novo modelo de configuração não deve alterar status, visibilidade, filas, formulários, respostas ou decisões ao salvar.
7. No mobile, auditar consumidores de `rm_aprovacoes_etapas` que ainda não filtram `ativo`; eventual exclusão lógica precisa permanecer invisível às decisões/listagens sem apagar histórico. Validar esse ajuste e o APK separadamente do editor web.

As diferenças protetoras devem constar no contrato final do editor. Esta auditoria não implementa nem aprova uma normalização de pares, uma reimportação geral ou reativação da ponte de saída.

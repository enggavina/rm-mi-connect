# Status do projeto na célula

Incremento 041–042, solicitado em 12/11/2026. O status continua pertencendo a `rm_celulas_projeto.status`, do tipo `public.rm_status_cel_proj_enum`. Não há coluna ou status paralelo no projeto.

## Discovery e interface

No Bubble Live, `custom.celula_projeto.Status` aponta ao Option Set `option.status_cel_proj`. A criação escreve o dropdown `comCZ` na alocação, através da ação `comCr`; esse dropdown é obrigatório e exclui `retornado`. A edição `copGz` usa o dropdown obrigatório `copFB`, oferece todos os estados e preserva o valor atual como padrão. Essas ações não atualizam o status global do projeto. O documento de discovery geral registra a evidência completa.

O EM já possuía os dez estados originais, a alteração operacional pelo mobile, o array `status_historico` e a projeção de recibos no histórico de células. Faltavam o campo em `CellEditor` e a aceitação/persistência pelo comando `plan_cell`.

**Alocar célula** agora oferece o seletor obrigatório, com Pendente como padrão e sem Retornado na criação. **Planejar** mostra o valor atual e permite escolher qualquer estado existente, respeitando as restrições anteriores de projeto encerrado, alocação retirada e célula Finalizada/N/A. Uma escolha inalterada é omitida do payload ao editar; os demais campos de planejamento continuam funcionando. O frontend não envia status global nem vínculos de formulários por causa desse controle.

## Novos estados

| Chave canônica | Apresentação | Ordem |
| --- | --- | --- |
| `aguardando_coleta` | Aguardando coleta | 11 |
| `coletado` | Coletado | 12 |

As dez opções anteriores, seus OIDs e ordenação permanecem. A 041 acrescenta somente os dois valores ao enum; deve ser confirmada antes de operações usarem os valores novos. A 042 acrescenta as duas linhas correspondentes ao catálogo existente `rm_option_sets`, com `attributes.ordem0` e `sort_order` 11/12. Não existe backfill dos status das alocações.

Os dois novos estados não recebem semântica automática de conclusão: não encerram o projeto, não preenchem data final, não ocultam a célula nem pulam aprovações. Filtros baseados no catálogo e a configuração de liberação de etapas passam a oferecê-los; as listas tipadas, formatação desktop, histórico e opções/labels mobile foram estendidas. As regras especiais anteriores de `finalizado` e `n_a` continuam as mesmas.

## Persistência, autorização e histórico

O contrato continua sendo `rm_web_mutate_v1(..., 'plan_cell', payload)`, usando a capacidade existente `em.planning.manage`. `changes.status` é opcional para preservar clientes e recibos anteriores; quando presente, deve ser um valor enum válido e não nulo. `retornado` é recusado apenas na criação, conforme a regra Live. O comando não altera `rm_projetos.status` ou `status_pcp`.

`rm_private.apply_cell_status_v1` é o novo escritor privado comum. Ele conserva o código existente de validação de formulários/fotos obrigatórias, histórico, data final/visibilidade de Finalizado e contrato de outbox. O wrapper operacional `update_cell_status_v1` mantém autenticação, acesso do operador à célula, contexto e locks, chamando esse escritor após sua autorização. O core original de planejamento continua verificando perfil, projeto/célula, versão e restrições anteriores, e chama o mesmo escritor quando há mudança de status. O helper não tem EXECUTE para `public`, `anon`, `authenticated` ou `service_role`.

Na criação, o array `status_historico` começa no status efetivamente escolhido. Não inventa uma passagem por Pendente. A criação no estado Pendente não emite evento operacional adicional. Nas mudanças, o novo status é acrescentado uma vez ao histórico; o replay do mesmo UUID retorna o recibo existente sem duplicar histórico/outbox.

O recibo de `plan_cell` já continha os registros anterior e posterior. A auditoria 038 já projeta o campo `status` nesse recibo, com usuário, data, projeto/célula, valor anterior e novo. Portanto, não há outra tabela de auditoria ou mutação SSO paralela. As labels novas são usadas no histórico existente.

Toda alteração e seus efeitos são transacionais. Uma falha de conclusão desfaz os campos de planejamento alterados, seus timestamps, histórico, outbox e recibo. A ordem de locks original é preservada. Um planejamento web com versão antiga recebe PT409 após uma operação mobile concorrente. Uma intenção mobile posterior conserva o comportamento anterior do seu RPC, sem trocar UUID, ator ou conteúdo offline.

## Compatibilidade e validação

- `web_cell_status_values_upgrade.sql`: verifica as dez identidades/ordens originais do enum e colunas existentes; ensaia rollback e aplica a 041 em transação própria.
- `web_allocation_status_upgrade.sql`: preserva todas as linhas anteriores (permitindo somente as duas opções novas), OIDs/owners/ACLs e definições não relacionadas, policies/triggers/constraints. Confere callers web/mobile aquecidos, recibos anteriores e permissão SSO emitida antes da DDL.
- `web_allocation_status.sql`: criação e edição, auditoria antes/depois, estados novos, inexistentes/nulos, Retornado, autorização web/mobile, SSO, replay, proteção de formulários/fotos, rollback e isolamento do projeto global e de outro projeto na mesma célula.
- `web_allocation_status_concurrency.sql`: cinco disputas reais em duas conexões, com web/mobile nas duas ordens, dois editores, mesmo UUID e criação sem duplicidade.
- Testes TS verificam schema, opções/labels, uso pelo editor de regras e paridade do seletor mobile com o enum base e sua extensão.

A geração/distribuição do APK e a publicação web são registradas no relatório geral desta entrega. Nenhum teste desta vertical usa dados artificiais em produção. A ponte de saída Bubble permanece desativada.

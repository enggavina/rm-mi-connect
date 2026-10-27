# Carga operacional inicial — 27/10/2026

Destino: projeto Supabase `oficina-em-mi-off`, referência `ellpxfbsrbhblyizvbbk`. Origem: Bubble `rmmi`, live, exclusivamente leitura. A saída da ponte permaneceu desativada e a fila de saída terminou vazia. A conta administrativa inicial, seu vínculo com Supabase Auth e sua matrícula foram preservados.

A carga principal ocorreu entre 20:39:24 e 20:43:26 UTC. A migração `009` corrigiu índices de ordenação fracionários legítimos para `numeric`; o replay recuperou 87 questões e 40 itens sem arredondar valores nem reler o histórico completo. As aprovações foram carregadas de snapshot do conector live entre 20:44:25 e 20:44:34 UTC.

| Conteúdo | Registros no destino |
| --- | ---: |
| Clientes | 894 |
| Equipes | 6 |
| Tipos de equipamento | 18 |
| Células | 29 |
| Tablets / vínculos de tablet | 14 / 181 |
| Usuários | 100 (99 importados e 1 administrador provisionado) |
| Formulários | 57 |
| Questões / itens | 4.162 / 2.410 |
| Vínculos célula–tipo / célula–formulário–tipo | 116 / 139 |
| Projetos / equipamentos | 177 / 177 |
| Células dos projetos | 1.429 |
| Fotos | 13.631 |
| Cabeçalhos de formulários preenchidos | 778 |
| Respostas de registros em revisão | 147 |
| Aprovações dos projetos ativos | 875 |

O recorte considera projetos sem entrega real, exclui cancelados e finalizados para faturar e mantém status nulo. Foram examinados 600 projetos: 417 fora desse recorte, 177 válidos e 6 incompletos. Os cabeçalhos de registros dos projetos ativos foram importados, mas as respostas históricas aprovadas permanecem na origem. As 147 respostas carregadas pertencem às revisões; respostas novas criadas no mobile ficam disponíveis normalmente. O worker mantém esse recorte, incluindo reidratação após reativação.

Permanecem 276 registros em quarentena local, sem substitutos inventados:

| Tipo | Quantidade | Motivo |
| --- | ---: | --- |
| Questões | 98 | 91 sem tipo e 7 sem enunciado |
| Vínculos célula–tipo | 6 | Célula ou tipo obrigatório ausente |
| Vínculos célula–formulário–tipo | 5 | Formulário ausente ou vínculo inválido |
| Projetos | 6 | Número ausente |
| Células de projeto | 82 | Célula ausente |
| Fotos | 51 | Referência a célula inexistente na API |
| Registros de formulário | 28 | 25 sem formulário e 3 com usuário inexistente |

Os arquivos completos de auditoria e registros em quarentena estão em `.tmp/etl/`, ignorados pelo Git. Os tipos com falha conservaram seus checkpoints; os registros válidos posteriores continuam sendo processados. O polling poderá reler esses dados até o saneamento da origem.

O snapshot de aprovações contém 2.298 registros de origem, dos quais 875 pertencem aos projetos ativos. Todos os 875 foram importados. Seu checkpoint público **não avançou**, pois o endpoint Data API de aprovações continua retornando 404. A sincronização contínua desse tipo depende de habilitar ou confirmar o endpoint, conforme [registro do Bubble](bubble-preparation.md).

Para reprocessar uma quarentena após corrigir sua causa, executar a partir de `desktop`:

```sh
npx tsx src/server/bridge/replay-quarantine.ts ../.tmp/etl/<execucao>/quarantine.jsonl
```

Para importar um novo snapshot de aprovações lido pelo conector autorizado:

```sh
npx tsx src/server/bridge/import-approval-snapshot.ts ../.tmp/etl-source/approvals-live.json
```

Esses comandos usam o lease global, preservam vínculos Auth e conflitos da fila local e não avançam checkpoints de origem. A segunda operação deve ser tratada como snapshot pontual até que o endpoint público funcione.

O worker permanece desativado e não implantado. Antes da coexistência concorrente, implementar a importação transacional com uma trava compartilhada pelas gravações mobile. O guard atual consulta a fila e grava em chamadas separadas, sem atomicidade entre elas. O contador por formulário considera apenas o recorte importado; antes de criar registros nos dois sistemas, validar os máximos globais históricos e escolher uma única autoridade de numeração.

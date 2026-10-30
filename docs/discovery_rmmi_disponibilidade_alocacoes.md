# Disponibilidade e retirada protegida de alocações

Discovery do incremento 028 em 30/10/2026, baseline `422987e`, produção com 001–027. Esta rodada inspecionou somente o workspace: contratos, fontes web/mobile, migrações e metadata Bubble anteriormente consultada em Live. Não fez nova leitura de dados remotos, executou workflows ou alterou fontes de aplicação. Bubble continua referência somente para leitura; a ponte de saída permanece desativada.

## Origem Bubble e diferença já assumida pelo EM

| Caminho | Configuração comprovada na metadata |
| --- | --- |
| PL013, `comKY → comNF → comNK` | Marcar o checkbox grava visibilidade=true e posição=`count(alocações visíveis da mesma célula)+1`. A contagem não é o conjunto completo da fila EM. |
| `comNF → comNL/comNM` | Desmarcar grava visibilidade=false; depois decrementa posição de todas as alocações da mesma célula cuja posição era maior. A busca dessa segunda ação não limita a visíveis e não usa versão do conjunto. |
| PL014, `comKc → comNR`, `comAa`, `comAt → comAy/comAz/comBA` | Abre confirmação; confirmar executa DeleteThing da alocação, alerta e fecha. `comAy` não contém guarda de uso/referência. Cancelar apenas fecha. Esse caminho não demonstra preservação de trabalhos offline nem manutenção transacional da fila após o delete. |

Evidências locais: `.tmp/discovery-planning/comNF.json`, `comNK.json`, `comNL.json`, `comNM.json`, `comAy.json` e [discovery do Planejamento](discovery_rmmi_planejamento.md). São configuração estática, não prova de execução atual do Bubble.

O [contrato publicado da 021](../rm-mobile-supabase/WEB_PCP_QUEUES.md) é deliberadamente diferente: a fila contém trabalhos **abertos visíveis e ocultos**, em projetos abertos. Alterar prioridade conserva posição; somente mover/confirmar a sequência normaliza `posicao=1..N`. O roteiro do projeto usa `indice`, independentemente da fila. Copiar o contador de visíveis do Bubble pode criar posições coincidentes e renumerar projetos sem intenção explícita.

Decisão de escopo confirmada para 028: **visibilidade não altera ordem, posição, prioridade ou índice**. Retirada é um ciclo de vida distinto de ocultar. Retirada conserva ID e unicidade projeto+célula, impõe visibilidade=false e sai da fila/carga operacional. Restauração é explícita, no mesmo ID, sem rematerializar modelos e mantendo a posição histórica. Lacunas/empates de posição não autorizam normalização silenciosa; a ordenação explícita existente continua disponível.

## Por que não excluir fisicamente

| Dependência no schema vigente | Consequência de hard-delete / cuidado necessário |
| --- | --- |
| `rm_aprovacoes_etapas.celula_projeto_id`, 002 | FK com CASCADE: pode apagar etapas ligadas diretamente. Muitas etapas legadas têm vínculo direto nulo e usam projeto+origem, portanto só contar FKs também omite dependências. |
| `rm_fotos.celula_projeto_id`, 002 | FK SET NULL: mantém foto, mas perde a referência exata e passa a depender do contexto legado. Fotos podem ter URL principal, lista de arquivos, seleção para relatório, mídia offline ou vínculos de outro contexto. |
| `rm_web_stage_decisions.celula_projeto_id`, 020 | RESTRICT protege decisões web vinculadas, mas não representa todo o uso legado/mobile. |
| `rm_form_reviewer_assignments`, 026 | FK composta RESTRICT preserva a atribuição contextual projeto+célula+alocação. Metadado pré-registro não equivale a formulário executado e não deve ser apagado para viabilizar retirada. |
| Registros/respostas, logs, comentários, documentos e dossiê | Parte dos vínculos é por projeto+célula ou registro, sem FK para a alocação. Não concluir “sem uso” por ausência de FKs diretas. Não excluir esses dados como efeito da gestão de disponibilidade. |
| Journal/recibos/outbox, inclusive uso de etapas da 027 | Podem registrar intenção, autoria e efeitos já concluídos. Preservar envelopes e referências; não reescrever protocolo nem atribuir logs de outra etapa por suposição. |

Fontes: `002_rm_core_tables.sql`, `020_rm_web_stage_approvals.sql`, `026_rm_web_form_reviewer_assignments.sql` e `027_rm_web_stage_rules.sql`. A unicidade `(projeto_id,celula_id)` atual é uma proteção: após retirada, nova tentativa de alocar o mesmo par deve orientar restauração, sem fabricar outro ID.

O servidor não conhece rascunhos e filas de tablets desconectados. “Nenhuma execução encontrada no banco” nunca comprova ausência de trabalho offline. Recomenda-se bloquear retirada com uso/evidências relevantes e explicar os impedimentos; ainda assim, preservar a linha/filhos é necessário para recuperar uma tentativa atrasada. Política exata de impedimentos e estrutura do marcador/journal serão definidas no contrato backend 028, não inferidas por esta auditoria.

## Parâmetros e identidade do trabalho offline

| Operação mobile | Identidade enviada / contexto a resolver no banco |
| --- | --- |
| Inspeção nova | `p_projeto_id`, `p_celula_id`, `p_form_id`, respostas, tempo e protocolo; **não envia allocation ID**. Rascunho SQLite tem unicidade projeto+célula+form+operador. |
| Correção de formulário | `p_registro_formulario_id` e respostas corrigidas; resolver registro→projeto+célula e alocação real. Não confiar em um contexto alternativo fornecido pelo cliente. |
| Foto obrigatória | `p_foto_id`, projeto/célula e `p_celula_projeto_id`; usar o slot real e conferir contexto exato ou legado nulo. |
| Foto complementar | Projeto+célula, `p_celula_projeto_id` e protocolo; clientes anteriores podem omitir o ID, portanto resolver também pelo par único. |
| Status / comentário | `p_celula_projeto_id` e conteúdo da ação. Preservar o ID original, sem redirecionar para outra alocação. |
| Decisão de etapa | `p_aprovacao_etapa_id`, ação e observação; resolver a origem da etapa e os destinos afetados. A configuração da regra também deve continuar com a identidade imutável acordada na 027. |

Fontes: `mobile/src/core/service.ts` (`submitDraft`, `enqueue`, `pushMutations`), `mobile/src/core/schema.ts`, `mobile/src/ui/photo-editor.tsx`, `cell-status-action.tsx`, `mobile/app/comentarios.tsx` e `aprovacao.tsx`.

Excluir e recriar o mesmo projeto+célula pode fazer uma inspeção antiga, sem allocation ID, atingir a configuração nova. A retirada reversível com o mesmo ID, preservando formulários/filhos/configuração, evita essa substituição de identidade. Restauração não deve importar modelos novamente, limpar respostas, mover fotos nem produzir decisões novas.

## Guardas de servidor necessárias

O acesso à célula (`assert_cell_access`) autoriza o operador, mas não verifica ciclo de vida da alocação. A nova guarda deve participar das primitivas compartilhadas, além do envelope web/mobile, para impedir bypass por caminhos internos e efeitos indiretos.

| Caminho vigente | Guarda/serialização a conferir na 028 |
| --- | --- |
| `rm_submit_form_inspection_v1` e dispatch mobile | Resolver projeto+célula sob projeto11 e alocação; recusar retirada antes de criar registro/respostas/numeração. Preservar validação de formulário e herança de avaliador da 026. |
| `rm_submit_form_revision_v1` | Resolver a partir do registro; projeto11 já foi introduzido na 026. Conferir alocação retirada antes de alterar respostas/status. |
| `rm_record_cell_photo_v1` | Conferir retirada para slot e complementar, inclusive quando CP é legado nulo; não basta a guarda de `lixeira` da 025. Preservar captura/URL/protocolo para restauração e repetição. |
| `update_cell_status_v1` | Resolver ID exato sob projeto11; impedir alteração/reativação de retirada, mantendo validações existentes de finalização. |
| `add_cell_comment_v1` | Resolver ID exato e acrescentar serialização com projeto11/alocação: a função vigente consulta alocação e autoriza, mas não trava o projeto antes de inserir comentário. |
| `rm_transition_stage_approval_v1` / web020 / mobile | Guardar **origem e destinos efetivamente afetados** antes de decidir, criar/reabrir inversa, alterar visibilidade/status ou gravar log/journal/outbox. Não decidir parcialmente nem recolocar destino retirado em execução. A 027 já trava projeto/alocações/regras; preservar essa ordem. |
| `plan_cell`, materialização e cópia por tipo | Não transformar linha retirada em alocação nova/visível por UPSERT ou mudança de modelo. Exigir restauração explícita; manter tipos/vínculos históricos protegidos. |
| Fotos operacionais025, avaliadores026, regras027 e planejamento | Gestão de contexto retirado deve ser consultiva; novos comandos não podem usar outro editor como reativação implícita. Consultas históricas permanecem possíveis. |
| Fila021/carga, roteiro024, recebimentos e encerramento de projeto | Separar conjunto operacional de histórico e conferir todos os predicados. Retiradas saem de fila/carga conforme escopo acordado; contagens/hash e encerramento não devem tratar retirada pendente como execução obrigatória nem ocultar histórico. Não mudar `indice` ao gerenciar disponibilidade. |

**Ocultar não é retirar.** O comportamento atual permite sincronizar trabalho já salvo mesmo quando o planejamento ocultou a alocação. Não adicionar `visibilidade=true` como condição universal de mutação: a guarda nova deve testar retirada, preservando esse contrato.

Recibos concluídos precisam ser conferidos **antes** das novas guardas de estado, com autenticação/autoria/permissões atuais preservadas. Mesmo UUID/corpo retorna o resultado original; uma regra retirada depois não torna esse replay uma mutação nova. Envio ainda não concluído para contexto retirado deve falhar claramente, conservar fila/arquivo/ator/UUID/payload e permitir restauração/retry explícitos quando admissíveis. Não migrar o payload para outra alocação, dispensar autoria ou marcar envio como concluído artificialmente.

O FIFO atual pode bloquear mutações posteriores após uma rejeição; isso deve ser comunicado, não resolvido descartando a operação. `runSync` continua executando pull mesmo após falha de push, de modo que a retirada chega ao catálogo enquanto o envio fica preservado. Upload de mídia precede RPC: uma tentativa pode já ter arquivo remoto e ainda aguardar confirmação; não apagar essa mídia como efeito de retirada.

## Compatibilidade mobile 1.2.3, sem novo APK neste escopo

Dois helpers já exigem `visibilidade===true` em `mobile/src/domain/journey.ts`:

- `cellAllocations`: listas e contagens de células/projetos.
- `resolveJourneyContext`, usado por `useJourney`: projeto, informações, documentos, galeria, captura de foto, lista/leitura/correção de formulários, comentários e aprovação. Essas telas não abrem contexto oculto para revisão.

Exceções intencionais: `mobile/app/confirmacao.tsx` consulta `service.operation(id)` sem exigir jornada visível e volta à lista quando `visibilidade=false`. Core sync/recibos também não dependem da jornada. A galeria de outro contexto ativo pode continuar consultando fotos históricas do mesmo projeto, sem editar o contexto retirado.

`LocalDatabase.cache` preserva o JSON integral em `local_catalog`; novos campos do marcador de retirada cabem nesse payload sem migração SQLite. O cache concreto de alocação já armazena visibilidade. Pull/reconcile não devem filtrar retiradas por RLS/consulta: a linha atualizada deve chegar, substituir o cache antigo e conservar os IDs. `removeMissing` apaga apenas caches, não rascunhos/fila, mas não deve ser usado como mecanismo de retirada.

Conclusão de compatibilidade: **não é necessário novo APK** para o menor escopo confirmado, desde que retirada sempre implique visibilidade=false, essa invariável seja protegida em todos os writers e as guardas de servidor cubram os caminhos acima. O APK 1.2.3 ocultará o contexto após receber o tombstone. Cache desconectado pode continuar exibindo o estado antigo até sincronizar; nenhum APK elimina essa condição. Uma versão futura pode melhorar mensagens/consulta de retiradas, mas não é requisito para a segurança do servidor nem motivo para apagar dados locais nesta entrega.

## Validações recomendadas após o backend

Esta auditoria não alterou fontes nem executou testes de produto. A revisão da 028 deve conferir:

- Upgrade preservando colunas/dados anteriores, identidades, respostas, fotos, modelos, recibos e journals; nenhum backfill ou fixture em produção. Se houver coluna nova na alocação, comparar integralmente as colunas anteriores e validar separadamente o default aditivo.
- Ocultar/exibir sem alterar `posicao`, `prioridade` ou `indice`; retirada/restauração exclui/reinclui no conjunto operacional com posição histórica, sem normalização ou rematerialização.
- Cada variante de inspeção, correção, foto, status, comentário e decisão/efeito indireto contra retirada, com recibo concluído ainda aceitando replay.
- Disputas retirada/restauração×mobile, materialização, nova alocação, regra de etapa e fila completa; locks/versionamento sem lote parcial ou reativação silenciosa.
- APK 1.2.3 com cache verdadeiro antigo: rejeição segura, pull recebendo false, draft/mídia/fila intactos, confirmação acessível e retry exato após restauração permitida. Não apresentar simulação como homologação em aparelho real.

O contrato final, nomes de operação/colunas, política exata de impedimentos e provas de publicação serão documentados pelo responsável do backend. Esta nota não autoriza hard-delete nem um mecanismo paralelo de sincronização.

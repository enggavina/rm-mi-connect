# Operações de projeto no EM

Implementação de 28/10/2026, aplicada ao projeto Supabase `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`). Instalação nova exige as migrações `001`–`012`, em ordem. O Bubble foi consultado somente para leitura. O webhook legado de download foi usado para obter 11 PDFs já existentes. Nenhum worker, geração/compilação de PDF ou envio de e-mail foi executado.

## Contratos do aplicativo

Todas as alterações continuam passando por `rm_mobile_mutate_v1(p_client_submission_id, p_rpc_name, p_params, p_operator_token)`. A chave UUID é reutilizada nas tentativas do mesmo envio. O servidor obtém o autor da delegação, verifica as células cadastradas para essa identidade e impede a chamada autenticada direta às funções internas. Não há novo parâmetro obrigatório de versão.

| Operação | Parâmetros em `p_params` | Validação/resultado |
|---|---|---|
| `rm_submit_recebimento_v1` | `p_cliente_id`, `p_chegada_equipamento`, `p_nota_fiscal`, `p_arquivo_nota_fiscal_url`, `p_eventualidades`, `p_equipamento: {descricao, placa_motor}`, `p_fotos_recebimento` | Cliente obrigatório. Número de OS e tipo podem permanecer nulos até o planejamento. `placa_motor`: `c___placa` ou `s___placa`. Campos e payloads legados continuam aceitos. `p_projeto_id` atualiza um recebimento existente autorizado. |
| `rm_update_cell_status_v1` | `p_celula_projeto_id`, `p_status` | Status canônico do Option Set `status_cel_proj`. Finalizado exige os formulários vinculados preenchidos e as fotos obrigatórias registradas. Autor e histórico são gravados. |
| `rm_add_cell_comment_v1` | `p_celula_projeto_id`, `p_comentario` | Texto não vazio, até 10.000 caracteres. Retorna `comentario_id`, `projeto_id`, `celula_id`. |
| `rm_record_cell_photo_v1` | Parâmetros existentes + `p_cadastro_foto_id` | Catálogo pertence à célula pelo nome cadastrado (ou entrada global). O servidor resolve o título. Slots obrigatórios mantêm o título materializado; payloads legados continuam compatíveis. `p_legenda` é comentário opcional. |
| `rm_transition_stage_approval_v1` | `p_aprovacao_etapa_id`, `p_acao`, `p_observacao` opcional | Decisão somente de etapa `nulo`/sem decisão, com perfil/aprovador autorizado e acesso à célula. Ações descritas abaixo. |

`p_descricao_equipamento` também é aceito como conveniência e normalizado para `p_equipamento.descricao`. Fotos do recebimento preservam `foto_url`, `titulo`, `tipo_recebimento`, `legenda`, `numero` e `categoria_foto`.

## Aprovações verificadas no Bubble live

Em `rm_mobile` (`cnqvm`), `conSX` mostra Liberar nas etapas normais; `conue`/`copzi` mostram Retornar/Aprovar nas etapas de retorno. Os eventos `copmq`, `copmY` e `copzz` definem as transições:

- **Liberar**: `status_cel_proj` da etapa é diferente de `retornado` e corresponde ao status atual da célula. Registra `aprovado`, prepara/reabre a etapa de retorno e libera a célula de destino conforme o bloqueio entre células.
- **Retornar**: etapa de retorno e célula atualmente `retornado`. Registra `reprovado`, reabre a aprovação anterior e devolve a célula de destino para `retornado`.
- **Aprovar**: etapa de retorno. Registra `aprovado`; o evento original não exige que a célula ainda esteja em `retornado`.

Etapas aprovadas ou reprovadas não recebem uma segunda decisão. O replay idempotente de uma decisão já confirmada continua retornando o resultado original. A ação Finalizar foi removida. O status Finalizado no seletor de célula é uma operação distinta, validada conforme formulários e fotos obrigatórios.

O seletor `comfL` usa todos os valores do Option Set `status_cel_proj`; `cooEO` grava histórico e valida conclusão. `comhU` grava comentário com projeto, célula e identidade. `settings_rm` continua sendo a origem das permissões da identidade, documentada em [OPERATOR_CELL_PERMISSIONS.md](./OPERATOR_CELL_PERMISSIONS.md).

## Documentos e histórico

O aplicativo consulta `rm_docs`, `rm_documentos`, `rm_comentarios`, `rm_logs_aprovacao` e `rm_cadastro_fotos`, agora com Realtime. A importação preserva as duas categorias de documentos:

- `Docs.Arquivo` contém URL de anexo; `Observacao`, `Status` e `Data_vencimento` são preservados.
- `Documentos.PDF` pode conter URL ou nome/chave opaca. URL HTTP(S) vai para `arquivo_url`; a referência original também fica em `s3_key`. O workflow legado `cohee/cohfC` manda a referência para `Download_pdf_n8n_s3`, um POST de download de arquivo existente. Os 11 PDFs disponíveis foram obtidos por esse serviço, validados e copiados para o bucket privado `rm-documentos`, em `legacy/<documento_uuid>.pdf`. `arquivo_url` recebe a referência Storage autenticada, preservando `s3_key`. Alterações posteriores de metadados na origem preservam essa cópia quando a chave continua igual; uma chave nova exige importar seu novo arquivo.
- Documentos cujo arquivo ainda não existe preservam seus metadados com URL nula.

Novas notas fiscais usam o bucket privado `rm-documentos`, com PDF/JPEG/PNG e limite de 50 MB no servidor. Upload/alteração requerem a pasta do `auth.uid()` autenticado; leitura requer conta RM vinculada. O banco guarda a referência estável `/storage/v1/object/authenticated/rm-documentos/...`, nunca uma URL assinada com validade curta. O aplicativo emite a assinatura na leitura.

A `012` preserva respostas históricas cujo vínculo `Questao` foi removido no Bubble. `questao_id` nulo é permitido somente se houver `bubble_id` e origem `bubble`/`etl`. Texto, tipo, índice e valores originais permanecem disponíveis para consulta. O gateway continua rejeitando novos envios ou correções sem uma questão válida; esses snapshots não se tornam modelos novos nem respostas editáveis. A unicidade de resposta por registro/questão permanece preservada.

## Carga e validação

Reconciliação SQL após a carga de 28/10/2026:

| Dados no escopo operacional instalado | Quantidade |
|---|---:|
| Projetos | 177 |
| Registros de formulário, todos com respostas | 778 |
| Respostas preservadas | 61.803 |
| Respostas históricas sem vínculo de questão, incluídas no total | 1.719 |
| Títulos cadastrados para fotos | 173 |
| Comentários | 92 |
| Logs de aprovação | 522 |
| Anexos Docs com URL disponível | 15 |
| Documentos de relatório | 14 |

Dos 14 Documentos, 11 têm PDF importado no bucket privado e 3 ainda não têm referência de arquivo na origem. Nenhuma das 1.719 respostas sem questão está atualmente em um registro devolvido para revisão. Duas respostas extras do Bubble colidem com a unicidade `(registro_formulario_id, questao_id)` e permanecem em quarentena por seus IDs, sem sobrescrever a resposta já existente nem fabricar vínculo. Essa quarentena adicional é separada dos problemas do catálogo registrados na carga inicial.

A investigação não encontrou correspondência exata das 11 chaves com `Docs.Arquivo` do mesmo projeto, nem com a regra explícita de PDF final no Render. A ação de download `coZeU/cohec` do n8n retornou os arquivos existentes como binários; isso permitiu importá-los sem conhecer a base S3 ou presumir URLs de origem.

Relatórios locais ignorados pelo Git: `.tmp/etl/2026-10-28T17-10-59-160Z-mobile-history/summary.json` (varredura completa dos 778 registros) e `.tmp/etl/2026-10-28T17-19-29-897Z-mobile-history/summary.json` (replay após a `012`, recuperando 1.719 respostas e 11 Documentos). A reconciliação final confirmou zero eventos pendentes na outbox e preservação do vínculo Auth/perfil administrador inicial. Não há processo de carga ou PostgreSQL de teste deixado em execução.

O script [import_mobile_history.ts](./scripts/import_mobile_history.ts) restringe a carga aos projetos operacionais já instalados e seus registros de formulário. O cliente Bubble desse script recusa métodos diferentes de GET. Usa lease da ponte, cache de IDs, lote com isolamento de erros e proteção de alterações locais pendentes; não processa outbox. Execução padrão valida sem importar; `--apply` importa. `--replay-from=.tmp/etl/<diretório>` reprocessa somente IDs registrados na quarentena de documentos/respostas.

```powershell
node desktop/node_modules/tsx/dist/cli.mjs rm-mobile-supabase/scripts/import_mobile_history.ts --apply
powershell -NoProfile -ExecutionPolicy Bypass -File rm-mobile-supabase/tests/run-local-tests.ps1
```

Testes PostgreSQL isolados executaram `001`–`012` e transações com rollback: recebimento simplificado/NF, replay, acesso ao bucket, autoria de comentário, status e conclusão, catálogo de fotos, sequência Liberar→Retornar→Liberar→Aprovar, permissões do operador e snapshots sem questão somente para consulta. Os 36 testes do desktop e seu TypeScript passaram, incluindo os novos eventos, escopos de documento, validação dos downloads PDF e preservação das cópias privadas em reimportações de metadados.

No Supabase real, a conta inicial consultou os cinco novos catálogos; acesso anônimo não expôs registros. Um único objeto QA foi enviado à pasta própria, lido por URL assinada e comparado byte a byte. URL pública e upload em pasta alheia foram negados. Somente esse objeto QA foi removido, com ausência conferida. Nenhum dado operacional fictício foi criado.

Os 11 PDFs reais foram preservados no Storage. Um deles foi baixado pela conta inicial com URL assinada: HTTP 200, 167.843 bytes e SHA-256 idêntico ao download legado. Assinatura anônima foi negada e a URL pública retornou HTTP 400; o bucket permanece privado. O replay da importação encontrou os 11 vínculos já concluídos, sem repetir downloads ou uploads. Veja [registro dos arquivos existentes](../desktop/docs/existing-documents.md).

O worker permanece desligado. Antes de coexistência com escrita simultânea, continuam pendentes a trava transacional compartilhada de importação e a autoridade única de numeração descritas no relatório de carga inicial. Os novos eventos de status/comentário e as alterações de etapa, log e comentário já têm handlers testados; o contrato de notificação anterior é apenas enfileirado, nunca disparado diretamente pela RPC.

O histórico completo acima é o snapshot importado nesta execução. O worker incremental anterior ainda restringe respostas recebidas do Bubble aos registros em revisão; antes de ativar atualização contínua de todo o histórico, esse recorte precisa incluir também os demais registros ativos (e sua reidratação). O script de carga histórica permite uma nova leitura explícita sem ligar o worker.

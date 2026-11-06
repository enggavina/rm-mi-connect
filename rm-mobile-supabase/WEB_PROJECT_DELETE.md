# Exclusão explícita de um projeto

Contrato da migração 039, em 06/11/2026. Reutiliza o gateway, os recibos de escrita e a identidade do EM. Somente administrador RM ativo, com `em.portal.read`, `em.projects.read` e `em.projects.manage` no portal, pode executar o comando. SSO e MFA atuais são conferidos pelo gateway; a permissão não amplia acessos de outros sistemas.

## Confirmação e transação

`rm_web_project_delete_snapshot_v1(projeto)` fornece identificação, contagens de negócio e prova SHA256 do contexto. O diálogo mostra essas informações, exige justificativa de 1 a 2.000 caracteres e confirmação explícita. Abrir o diálogo não altera dados. Datas e hash são congelados com o UUID da tentativa; uma resposta incerta exige retentar esse mesmo corpo.

`delete_project` no `rm_web_mutate_v1` revalida autorização, confirmação, justificativa, timestamp do projeto e hash de todas as dependências. Espaços, tabs e quebras de linha isolados não são justificativa válida. Qualquer mudança concorrente exige nova consulta (`PT409`). Dependência compartilhada impede a exclusão (`PT424`). Não existe opção para ignorar vínculos ou permissões.

O projeto e todo seu grafo exclusivo são removidos em uma transação. Uma falha no último DELETE também desfaz os deletes anteriores, a reserva do protocolo, a redução de recibos e os trabalhos de limpeza.

## Propriedade e dependências

| Grupo | Linhas exclusivas incluídas |
| --- | --- |
| Projeto/equipamento | `rm_projetos`, equipamentos com `projeto_id` correspondente e a instância privada do roteiro. |
| Operação | Alocações, previsões/capturas de fotos, regras e logs de etapas, registros, respostas, rascunhos, avaliações de registros, notificações, comentários e designações de avaliadores. |
| Dossiê | `rm_docs`, `rm_documentos`, intenções de upload e versões privadas. |
| Comercial | Propostas de controle do projeto ou do seu equipamento quando ainda sem projeto próprio; propostas orçamentárias exclusivamente ligadas a elas ou ao projeto. |
| Oficina/laboratório | Ordens do projeto/equipamento, componentes, delineamentos e itens; fichas de desmontagem e ensaios exclusivos do projeto, equipamento ou ordem. |
| Diários privados | Eventos de regras, disponibilidade e equipamento; revisões de comentários; versões/intenção de anexo e origem do roteiro. Não ficam cópias completas desses históricos após a exclusão. |

A closure é explícita em `project_delete_scope_v1`. A inspeção de FKs verifica **as duas direções**: linha do grafo apontando a pai exclusivo de outro projeto, ou linha externa apontando a pai do grafo. Referências documentais em arrays também são verificadas. Relações comerciais/laboratoriais cruzadas não são inferidas como exclusivas somente porque uma FK admite `SET NULL`.

Clientes, pessoas, células globais, tipos, títulos e modelos/questões/opções de formulários permanecem. Nenhum cascade novo foi acrescentado sobre esses cadastros. As entradas de saída relacionadas exclusivamente ao projeto são retiradas; filas de outros contextos e a configuração da ponte são preservadas. `SYNC_OUTBOX_ENABLED=false` continua obrigatório nesta entrega.

O lock do projeto (chave 11), equipamentos (37) e locks NOWAIT das dependências acompanham a ordem existente. Referências documentais sem FK usam a chave 41; caminhos privados usam a chave 40. Esses locks impedem criar referências novas entre a validação e o commit. Não há GUC ou parâmetro de cliente que desative guards: o desvio de exclusão exige recibo privado do mesmo projeto, ator e transação.

## Auditoria mínima e envios antigos

O recibo de `delete_project` mantém protocolo, projeto/rótulo, autor, data, justificativa, contagens e resultado. Os identificadores documentais e Bubble dos recursos apagados formam tombstones, sem snapshot completo do projeto. O mesmo UUID/conteúdo retorna replay; ator ou conteúdo divergente continua rejeitado.

Recibos web/mobile exclusivos anteriores perdem o corpo e os snapshots completos. Conservam ator, operação, protocolo, hash do corpo original e identificação mínima do recurso excluído. Um replay válido recebe `PT410`, nunca falso sucesso nem recriação. Um recibo de fila compartilhada continua privado enquanto houver outro projeto vivo no seu contexto; quando o último for excluído, ele também é reduzido.

O UUID e Bubble ID do projeto permanecem reservados. A guarda impede reimportar o projeto, mesmo com novo UUID. O adaptador ETL consulta os tombstones de cada entidade e suas referências **antes** do mapeamento/resolução/upsert; um filho de projeto/registro excluído é contabilizado como excluído da importação, sem abortar os vizinhos válidos do lote. A guarda de banco continua protegendo a corrida posterior à consulta.

O mobile conserva os envios recusados, UUID, ator, conteúdo e arquivos locais para reconciliação. Sua fila FIFO pode aguardar intervenção; este pacote não inventa conclusão nem remove rascunhos no aparelho. O pull existente reconcilia o catálogo pelo manifesto de IDs. Não há novo APK nesta entrega.

## Limpeza física de arquivos

Banco e Storage não compartilham transação. A transação insere trabalhos duráveis em `rm_private.project_delete_files` antes de remover o dossiê. Somente uploads com proveniência registrada e caminho exato `rm-documentos/web-dossier/{projeto_UUID}/{upload_UUID}.{pdf|jpg|png}` entram nessa fila. URLs externas/CDN, arquivos globais e mídia legada/mobile/pública sem prova de propriedade exclusiva permanecem; a interface declara esse limite.

Uma referência sobrevivente em outra tabela pública/privada protege o arquivo e marca o trabalho `preserved_shared`. A comparação procura o próprio caminho, independentemente de endpoint autenticado, assinado ou público; uma passagem de decodificação URI ASCII também reconhece barras, UUIDs e pontuação codificados. Uma nova referência pública a caminho reservado para exclusão é recusada; o lock 40 resolve a disputa com escritores já em andamento. Não se apaga `storage.objects` diretamente.

As RPCs `rm_project_delete_files_claim_v1` e `rm_project_delete_files_finish_v1` são restritas ao `service_role`, sem acesso direto à tabela. Claim usa `FOR UPDATE SKIP LOCKED`, limite de 1–5 trabalhos, lease de 120 segundos e token novo. Ack precisa do token vigente; falha volta para pending com backoff limitado a uma hora. A remoção via Storage API aceita 404 como já removido. Jobs/leases/caminhos duplicados, caminhos inválidos e respostas fora do orçamento são rejeitados pelo worker antes de tocar Storage.

O servidor tenta um trabalho da própria exclusão imediatamente e deixa os demais para o worker. A inicialização Next só o habilita com `EM_PROJECT_DELETE_CLEANUP_ENABLED=true`, runtime Node, credenciais internas e destino EM exatos. Builds não o iniciam. A cada 30 segundos ele drena até três trabalhos, sem sobrepor execuções; o timer usa `unref`. O worker é independente de `SYNC_OUTBOX_ENABLED` e não publica mensagens no Bubble. Erros são genéricos, sem IDs, caminhos, URLs ou segredos em logs.

## Verificação

`web_project_delete.sql` cobre autorização, confirmação/justificativa, closure operacional/comercial/laboratorial, replay, tombstones e ack privado. `web_project_delete_upgrade.sql` verifica todas as linhas anteriores, OIDs/ACLs/owners, triggers/policies/constraints e SSO aquecido na atualização 038→039. `web_project_delete_integrity.sql` cobre vínculos nas duas direções, soft references, rollback de todas as tabelas na falha final, remoção de histórico privado, replay antigo web/mobile, recibos mistos, arquivos compartilhados e backoff. `web_project_delete_concurrency.sql` executa 12 disputas em conexões reais nas duas ordens: edição, foto, resposta, origem documental, caminho privado, mesmo protocolo e identidade Bubble. Os testes TS do serviço/worker e ETL usam dependências simuladas; nenhum teste exclui dados de produção.

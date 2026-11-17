# Recebimento mobile: rascunhos e abertura antecipada (045/052)

## Solicitação de abertura antes dos anexos — 052

No aplicativo 1.2.10/código 13, **Solicitar abertura** continua gravando primeiro o recebimento completo no SQLite, com UUID, autoria, token e conteúdo originais. Com conexão, um envio independente solicita a criação do projeto e equipamento antes dos uploads de fotos e nota fiscal, mesmo que outro lote de mídia esteja lento ou tenha falhado. Offline, o pedido permanece salvo e essa abertura é tentada quando a conexão retorna. O autosave continua sendo somente um rascunho e não cria projetos.

`rm_mobile_open_receiving_v1` recebe o protocolo e envelope originais, valida a delegação e a revisão do rascunho e retorna os IDs efetivos. O vínculo privado `receiving_openings` conserva conta, operador, hashes e IDs; retentativas, resposta perdida e reinício reutilizam o mesmo projeto. O protocolo fica reservado e não pode ser consumido por outra operação mobile. A ausência do projeto após exclusão retorna PT410, mantendo o trabalho local para conferência. A instalação é aditiva e não converte automaticamente rascunhos antigos em projetos.

O recibo de abertura é salvo separadamente em `local_meta`, isolado por conta/operador/protocolo, e **não conclui a fila de recebimento**. A confirmação diferencia projeto disponível no web de anexos ainda pendentes. A fila original conserva sua ordem e só termina depois do upload e da confirmação final. **Sincronizar agora** pode retentar a abertura mesmo durante outro upload, sem criar um segundo lote de mídia. O fluxo anterior de clientes sem abertura antecipada continua compatível.

A finalização dos recebimentos previamente abertos acrescenta fotos e nota fiscal ao projeto vinculado. Ela não repõe OS, cliente, tipo, dados do equipamento ou roteiro a partir do snapshot mobile antigo. Uma nota fiscal já consolidada no web é preservada; o arquivo recebido pelo aplicativo fica também nos documentos. A identidade da finalização desconsidera somente a substituição de URLs locais por remotas, mantendo IDs, títulos, comentários e demais dados originais. Depois da solicitação, um autosave divergente exige conferência em vez de alterar silenciosamente o protocolo.

Em **Recebimentos** no web, a consulta é atualizada a cada cinco segundos enquanto a aba está visível e conectada, ao voltar à aba/conexão e pelo botão **Atualizar agora**. Filtros, digitação e posição são preservados. Um recebimento sem OS e sem roteiro pode receber seu primeiro tipo de equipamento: fotos exclusivamente de recebimento, sem célula/alocação/modelo, deixam de ser consideradas uso do roteiro. Alocações, roteiros já copiados, fotos operacionais, formulários e aprovações mantêm a proteção do tipo. A classificação preserva o projeto, equipamento, fotos e documentos existentes.

Os testes usam banco e navegador isolados: abertura antes dos anexos, ausência de duplicação, alterações web durante upload, notas fiscais divergentes, revisão de draft, reserva de UUID, tombstones e concorrência. A publicação e o APK final são registrados em [web-platform.md](../desktop/docs/web-platform.md). As seções seguintes registram a base 045 reaproveitada, incluindo o instalador histórico 1.2.8.

## Estrutura encontrada e reaproveitada

A tela `mobile/app/recebimento.tsx` já possuía um rascunho durável no SQLite, na chave `local_meta.recebimento:<operador_id>`. Ela preservava campos legados, fotos, arquivos e o UUID original do protocolo. A fila `local_rpc_outbox` já capturava o operador e seu token, enviava mídias antes das mutações e reutilizava o recibo transacional de `rm_mobile_mutate_v1`. Faltava persistência do rascunho no Supabase; os drafts de formulários têm outro contexto e não servem para esse cadastro.

Essa estrutura foi mantida. Nenhum rascunho, fila ou instalação existente é apagado ou convertido em projeto durante o autosave. Não há nova tabela SQLite nem migração dos dados locais existentes.

## Autosave e retomada

- Cada alteração é gravada imediatamente na fila de escrita transacional já existente do SQLite. O mesmo UUID, campos legados e URIs de mídias permanecem no registro original.
- A chave auxiliar `receiving-sync:<operador_id>` guarda revisão do banco, versões locais, request em andamento, estado e erro. As duas chaves são atualizadas na mesma transação SQLite.
- O envio ao Supabase usa debounce de 1.200 ms. Retorno de conexão, retorno ao aplicativo e tentativas periódicas já existentes também retomam o envio. A saída para segundo plano faz uma tentativa sem bloquear a tela. O prazo de rede é de 8 segundos; falhar nunca apaga o rascunho local.
- As mídias usam a fila e os buckets existentes. O snapshot enviado ao banco recebe URLs remotas depois do upload; referências locais continuam no dispositivo. Uma mídia pendente mantém o snapshot local e informa o motivo do atraso.
- Um request de autosave é persistido antes da chamada de rede com UUID, conteúdo e revisão esperada. Se a resposta se perder, a próxima tentativa repete exatamente esse request antes de enviar alterações mais recentes. Digitar durante uma chamada não perde os novos dados.
- Ao abrir o recebimento, carrega-se o rascunho local e consulta-se o banco. Em outro dispositivo da mesma conta e do mesmo operador, um slot local vazio pode retomar o draft ativo do banco. Dados locais pendentes nunca são substituídos silenciosamente.
- A interface distingue `Salvando…`, `Salvo no dispositivo`, `Salvo no banco` e conflito. Em conflito, a ação explícita **Retomar versão do banco** exige confirmação e preserva uma cópia da versão local na chave `receiving-recovery:<operador>:<protocolo>:<uuid>`. Esse arquivo de recuperação está no próprio SQLite, não em logs ou no servidor.
- Se o banco informar que outro dispositivo já concluiu o recebimento, mantém-se o protocolo e os campos locais, preserva-se uma cópia do trabalho ainda não enviado e bloqueia-se uma nova confirmação desse draft.
- A retomada explícita bloqueia autosave/finalização concorrentes e compara novamente a versão local dentro da transação de substituição. Se outra tela editar durante a consulta, o novo conteúdo local é preservado e a retomada é recusada.

O serviço não consulta toda a base de projetos durante cada tecla: autosave tem RPC próprio e não dispara o pull completo de catálogos. Um recebimento já na fila tem prioridade; o próximo slot local aguarda a finalização anterior antes de tentar ocupar o slot ativo do banco.

## Banco e autorização

A migração aditiva `045_rm_mobile_receiving_drafts.sql` cria somente `rm_private.receiving_drafts`, com:

| Campo | Uso |
|---|---|
| `id` | UUID original do protocolo de recebimento; chave primária |
| `auth_user_id` | FK restritiva para `auth.users`; conta proprietária do dispositivo |
| `operator_id` | FK restritiva para `rm_users`; responsável original |
| `payload` | Snapshot JSON do rascunho, incluindo `projeto_id` quando já conhecido |
| `revision`, `last_save_id` | Concorrência otimista e repetição idempotente do autosave |
| `state`, `result` | `draft` separado de `finalized`; resultado do recebimento confirmado |
| `created_at`, `updated_at`, `finalized_at` | Ciclo de vida |

Há um índice único parcial de slot ativo por conta/operador, um índice de consulta por dono/data e constraints para estados, revisão positiva, UUID coerente com o JSON, tamanho de snapshot de até 1 MiB e resultado/data de finalização consistentes. O projeto conhecido é contexto do snapshot; não há cascata ou nova relação de propriedade com o dossiê de um projeto. Assim, apagar um projeto não elimina trabalho offline nem torna o draft uma via de recriação: todas as verificações de projeto e tombstones do gateway continuam aplicáveis.

A tabela privada não concede acesso direto a `anon`, `authenticated` ou `service_role`. A única RPC nova é `rm_receiving_draft_v1`, executável por `authenticated`, com ações `read` e `save`. Ela valida a conta ativa do tablet, token delegado vigente/não revogado e operador ativo, e restringe cada registro ao par conta/operador. Um operador no mesmo tablet também não lê o draft de outro operador. As funções auxiliares não têm grants para clientes.

## Confirmação e idempotência

Somente **Solicitar abertura** cria o envelope de recebimento na fila original. O autosave não cria projeto, equipamento, fotos efetivas, recibo de mutação ou evento Bubble.

O snapshot confirmado é comparado novamente dentro da transação SQLite que cria o envelope. Uma edição de outra tela durante a consulta de rede impede o enqueue e pede conferência dos dados. O marcador local `submitted` é gravado na mesma transação da fila, evitando uma janela em que outra tela continuaria alterando um envio já confirmado.

Novos envelopes acrescentam `p_receiving_draft_id`, `p_receiving_draft_revision`, `p_receiving_draft_save_id` e `p_receiving_draft_snapshot`. Clientes anteriores continuam enviando exatamente os seus payloads existentes, sem novos campos obrigatórios. Recibos e hashes já registrados não são reescritos.

Dentro da transação do gateway, o draft é bloqueado e a revisão validada antes de executar o recebimento existente. O ID do draft precisa ser o ID da submissão. A única revisão adicional aceitável é aquela cujo UUID de autosave pendente prova que a resposta anterior se perdeu. Depois de todas as validações e efeitos existentes passarem, o mesmo draft é marcado `finalized` com o resultado. Qualquer erro reverte também a alteração do draft. Um clique duplo ou retry usa o recibo original; um novo protocolo não pode finalizar o mesmo draft novamente.

Antes de enfileirar, o cliente verifica, quando conectado, se o banco já concluiu aquele protocolo. Falhas de conexão preservam a possibilidade de envio offline. Uma disputa ocorrida depois dessa consulta continua sendo recusada no banco, sem criar duplicidade. Envios que precisem de reconciliação permanecem visíveis na fila original com seu erro e conteúdo; não há descarte automático nem confirmação falsa.

## Validação

- `mobile/tests/receiving-drafts.test.ts`: início parcial, servidor separado da solicitação, retomada em outro armazenamento, reinício offline, identidade/mídias preservadas, resposta perdida, edição durante envio, conflito/reconciliação com cópia local, falha de mídia e confirmação concorrente na UI.
- `rm-mobile-supabase/tests/mobile_receiving_drafts.sql`: autosave parcial, revisão e repetição exata, slot único, autorização por conta e operador, token expirado, tabela privada, anônimo, rollback de confirmação inválida, recibo único, conclusão e bloqueio de repetição sob outro protocolo.
- A bateria mobile existente continua validando conversão legada, fila, mídia, identificações, formulários, QR e operações do projeto.

Os testes SQL usam apenas fixtures num banco isolado e fazem rollback. Nenhum dado artificial é inserido na produção.

## Instalador interno desta entrega

O APK interno foi recompilado como **1.2.8 / versionCode 11**, mantendo o pacote `br.com.mielectric.rmconnect` e o certificado do instalador anterior. Caminho: `artifacts/em-mi-electric-brasil-internal.apk`.

- Tamanho: **69.001.516 bytes**.
- SHA-256: `5daa93ec0efc77abbd175777a0490d5752784594e6b0248beb91341cfe7d72dd`.
- Certificado SHA-256: `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`.
- Android/iOS exportados; `assembleRelease` passou (702 tarefas, 18 executadas). O teste final comparou hashes de fontes durante a compilação.
- A verificação do APK confirmou API de drafts, snapshot, recuperação e guarda de confirmação no bundle, destino Supabase autorizado, apenas JWT público `anon`, nenhum dos 10 segredos locais pesquisados e nenhum arquivo `.env` empacotado.
- ARM64 e x86_64, permissões/compatibilidade anteriores preservadas, backup Android desativado e ausência de permissão de áudio.
- O instalador 1.2.7 e as fontes nativas anteriores foram copiados para backup local ignorado antes da substituição atômica. O único arquivo nativo alterado foi `android/app/build.gradle` com versão/código; assinatura foi preservada.
- Nenhum dispositivo foi instalado, desinstalado, apagado ou modificado. Para atualizar, instalar sobre a versão existente com a mesma conta, sem desinstalar o aplicativo.

Validação local do mobile: **116 testes aprovados e typecheck aprovado**, além do novo teste SQL de rascunhos aplicado em PostgreSQL isolado. A validação integrada e a publicação do servidor são registradas no relatório geral da entrega.

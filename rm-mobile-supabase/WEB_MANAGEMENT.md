# Contrato de gestão web — migrações 014–015

Estado: **014 e 015 aplicadas em 29/10/2026** ao projeto autorizado `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`), com histórico 001–015 registrado. Nome/organização, URL utilizada pela aplicação e sequência das migrações foram conferidos antes da aplicação transacional. A 014 não modifica o gateway, as delegações de operador ou as políticas de leitura usadas pelo mobile; a 015 corrige somente o código de conflito para HTTP409.

## Identidade e sessão

O portal usa a conta Supabase Auth existente. A função obtém `auth.uid()`, encontra o `rm_users.auth_user_id` correspondente e exige `status='ativo'`. Não existe tabela separada `rm_operadores`. Não recebe `actor_id`, matrícula, palavra-chave do operador ou token mobile. O usuário DIGITAL já está vinculado ao Auth e possui perfil administrador; os demais usuários legados não adquirem uma conta Auth automaticamente.

Se a conta possui fator TOTP `verified` em `auth.mfa_factors`, a RPC também exige `auth.jwt()->>'aal'='aal2'`, inclusive para replay de recibos. AAL1/claim ausente são rejeitados no banco, impedindo contornar a tela MFA por chamada REST direta. Sem TOTP verificado, o comportamento de login simples permanece. A regra é exclusiva da escrita web e não altera o gateway mobile.

O servidor Next deve criar o cliente Supabase por requisição com chave pública e JWT da sessão. O `service_role` existente em `server/config.ts` é reservado à infraestrutura/ponte; não participa destas ações. Rotas privadas exigem sessão validada no Auth, usam `no-store`, validam origem de POST e não devolvem tokens em JSON. Logout deve usar `scope:'local'` para não revogar o tablet. A autorização definitiva acontece no banco mesmo que alguém chame a RPC diretamente.

## Envelope e concorrência

```ts
rpc('rm_web_mutate_v1', {
  p_client_submission_id: string, // UUID estável até obter resultado definitivo
  p_operation: 'save_project' | 'plan_cell' | 'review_form',
  p_payload: object,
});
// retorno:
// { operation, id, projeto_id, updated_at, record, idempotent_replay }
```

O mesmo UUID, identidade, operação e JSON devolvem o recibo original, sem repetir a alteração. Reutilização com conteúdo/ator diferente falha. Recibo, ator, payload, registro anterior e resultado ficam em `rm_private.web_mutation_receipts`, inacessível a `anon`/`authenticated`; são gravados na mesma transação da alteração.

`expected_updated_at` é obrigatório: valor textual **exato recebido do banco**, incluindo microssegundos, para edição; `null` para criação. Não converter com `new Date(...).toISOString()`, que pode perder precisão. Campos omitidos de `changes` permanecem; `null` explícito limpa campo anulável. Não há endpoint de delete nem escrita genérica de tabela/coluna. Campos desconhecidos são rejeitados.

A RPC bloqueia o registro antes de comparar a versão. Projetos/planejamento também usam a trava de projeto já compartilhada com status/aprovações mobile. A revisão bloqueia o cabeçalho, como a correção mobile. Isso evita que o web sobrescreva uma atualização já confirmada desde sua leitura; não transforma o mobile legado nem a ponte Bubble em sistemas com controle otimista universal.

## `save_project`

Permissão: perfil ativo `administrador` ou `padr_o`, conforme a regra de PCP existente.

```json
{
  "id": "UUID do projeto, inclusive novo",
  "expected_updated_at": null,
  "changes": { "numero": "OS-123", "nome": "Projeto", "status_pcp": "executando" }
}
```

Campos permitidos em `changes`: `numero`, `nome`, `cliente_id`, `tipo_equipamento_id`, `descricao_equipamento`, `contato`, `proprietario`, `escopo_abreviado`, `eventualidades`, `gestor_responsavel_id`, `status`, `status_pcp`, `chegada_do_equipamento`, `data_prevista_inicio`, `data_prevista_final`, `data_contratual`, `data_renegociada`, `replanejamento_motivo`.

Exige número ou nome; responsável ativo, FKs/enums existentes e prazo coerente. O tipo de equipamento não pode mudar após alocar células. O número é atualizado também nas alocações existentes. Entrada em `finalizando_para_faturar` exige células concluídas/não aplicáveis, formulários vinculados preenchidos/aprovados, todos os registros aprovados e fotos obrigatórias preenchidas. Não materializa todas as células implicitamente nem altera dados de equipamento, identidade, credenciais ou metadados Bubble.

## `plan_cell`

Permissão: perfil ativo `administrador` ou `padr_o`.

```json
{
  "projeto_id": "UUID",
  "celula_id": "UUID",
  "expected_updated_at": null,
  "changes": { "visibilidade": true, "bloqueada": "n_o", "forms_ids": ["UUID"] }
}
```

Chave natural: projeto + célula. A versão pertence a `rm_celulas_projeto`, não ao projeto. Campos permitidos: `data_inicio`, `data_limite`, `bloqueada`, `motivo_bloqueio`, `visibilidade`, `prioridade`, `indice`, `posicao`, `horas_previstas`, `responsavel_id`, `observacao`, `forms_ids`.

Nova alocação copia formulários, slots de foto e aprovações dos templates existentes para aquela célula/tipo. A materialização antiga `rm_materialize_project_cells_v1` é somente serviço e faz UPSERT de todas as células, substituindo formulários/prazos; a 014 reaproveita suas regras de cópia apenas na alocação nova. Uma célula sem template pode ser alocada manualmente; nenhum template é inventado.

Bloqueio `sim` exige motivo. Responsável deve estar ativo; prazo/horas válidos; formulários existentes sem duplicatas e novas inclusões ativas. Formulário que já possui envio não pode ser desvinculado. Projetos cancelados, entregues ou em faturamento e células `finalizado`/`n_a` recusam planejamento. `status` operacional não é campo deste comando; portanto não contorna conclusão/aprovação do mobile. Não altera a ACL de operadores.

## `review_form`

Permissão: administrador ativo ou usuário ativo já cadastrado como `avaliador_user_id`/integrante de `aprovadores_ids` do registro. Perfil `padr_o` isoladamente não autoriza revisão.

```json
{
  "registro_formulario_id": "UUID",
  "expected_updated_at": "valor exato de updated_at",
  "decision": "return",
  "parecer": "Corrigir a medição indicada.",
  "resposta_ids": ["UUID da resposta"]
}
```

Somente registros preenchidos, com respostas e status `em_an_lise` podem receber decisão. `return` exige parecer não vazio e uma ou mais respostas distintas desse registro, vinculadas a questões reais do mesmo formulário; subtítulos e snapshots órfãos não são corrigíveis. Marca `revisar` nas respostas selecionadas e muda status para `direcionado`, consumido pelo fluxo mobile existente. Não altera conteúdo das respostas nem autor original. `approve` exige `resposta_ids:[]` e nenhuma revisão pendente; muda para `aprovado`. Cada decisão gera histórico em `rm_aprovacoes_registro`, cuja leitura autenticada é acrescentada pela 014. A correção mobile volta o registro para análise, permitindo nova decisão.

## Erros e operação

| SQLSTATE | Tratamento web |
| --- | --- |
| `42501` | Conta inativa/sem permissão: 403 |
| `PT409` | Versão divergente ou criação já existente: HTTP409; recarregar e pedir nova decisão |
| `23505` | UUID de envio reutilizado com outro conteúdo: 409 |
| `22023`, `22P02`, `22007`, `22008`, `23503` | Payload/regra/UUID/enum/data/FK inválido: 400 |
| `P0002` | Registro inexistente: 404 |

Falhas não deixam recibos nem alterações parciais. Não converter automaticamente um conflito em reenvio com versão nova. A interface deve conservar o UUID ao repetir a mesma tentativa após erro de transporte.

Esta entrega grava gestão web somente no Supabase e **não gera eventos para a ponte**. Nenhum email, webhook, worker ou escrita Bubble é acionado. A coexistência bidirecional continua bloqueada até existir contrato de saída para estas operações e proteção transacional da entrada da ponte; não iniciar o worker por causa do deploy web. O helper legado `rm_user_has_element_permission(p_user_id,...)` aceita identidade explícita e tem EXECUTE anônimo: não é usado para autorização deste portal e precisa de endurecimento separado antes de eventual uso. `rm_elementos_permissao` vazio não é tratado como concessão de acesso.

Validação: `tests/run-local-tests.ps1` aplica 001–015 em PostgreSQL temporário e executa quatro suítes transacionais. A suíte web cobre ator/roles/inatividade, escrita direta negada, FKs/enums, idempotência/rollback, versões, clonagem isolada, proteção de formulários enviados, devolução de órfãs negada, ciclo real web → correção mobile → aprovação web e TOTP verificado com AAL1 negado/AAL2 permitido (inclusive bloqueio de replay AAL1). Contas sem fator verificado continuam permitidas. O banco temporário é encerrado/removido; nenhum teste operacional é inserido no projeto remoto.

Na QA REST autenticada real, chamadas com operação inválida, versão ausente e tentativa de informar ator retornaram `400/22023`; enum inválido retornou `400/22P02`; versão desatualizada retornou `409/PT409`. A chamada anônima foi negada (`401/42501`) e a leitura de histórico retornou HTTP200. A conta existente não possui TOTP verificado; cenários AAL1/AAL2 foram testados no banco local, sem cadastrar fator fictício no Auth real. Auditoria e credenciais permaneceram privadas, os recibos web ficaram em zero e logout de QA usou somente `scope:'local'`.

A QA identificou que a combinação PostgREST/Supabase em uso repete indefinidamente `40001` quando uma função o usa como erro de negócio. Por isso a migração aditiva 015 substitui os três erros de versão por `PT409`, preservando a 014 já aplicada. A correção segue a [orientação oficial do Supabase](https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions). A repetição da QA após a correção terminou em aproximadamente um segundo, sem escrita operacional nem processo de teste pendente.

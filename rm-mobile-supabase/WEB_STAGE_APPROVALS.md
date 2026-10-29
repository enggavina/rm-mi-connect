# Aprovações de etapas no portal EM

Contrato do incremento **3A** do [plano de paridade](../plano_paridade_rmmi_web.md), em 29/10/2026. A entrega acrescenta uma fila web, detalhe e decisão das etapas de projetos, usando a transação operacional do mobile. Prioridades, capacidade, recebimentos e encerramento completo do PCP continuam em entregas posteriores. A publicação e as evidências finais são registradas no [portal web](../desktop/docs/web-platform.md).

## Jornada e permissões

- `/aprovacoes`: pendentes por padrão; filtros por projeto, célula, busca, situação e “Aguardando minha decisão”. A lista é paginada no servidor, com total real. “Minha decisão” significa uma ação operacional disponível agora, não apenas ter o nome no cadastro de aprovadores.
- `/aprovacoes/[id]`: contexto mínimo do projeto, cliente, equipamento, origem/destino e estado da célula; aprovadores, decisão atual e histórico. Links no projeto e no planejamento abrem a fila correspondente quando o acesso permite.
- A consulta exige `em.portal.read` e **`em.approvals.read`**. A ação exige **`em.approvals.decide`**, independente de `em.planning.manage` e `em.forms.review`. As permissões são conferidas novamente em cada requisição/ação. O construtor e as revisões de formulários mantêm os próprios escopos.
- O administrador RM ativo conserva a autorização operacional já existente no mobile. O perfil `padr_o` precisa do acesso à célula e da autorização de aprovador conforme o gateway mobile. O perfil `auditor` consulta. Nenhum cadastro de acesso operacional, identidade Auth ou permissão global é criado para viabilizar uma decisão.
- Sem capacidade de decidir, o BFF remove as ações da resposta. Sem autorização operacional ou estado compatível, o banco retorna o motivo da consulta sem ação. `mgavina` e `softdev05` continuam administradores do **EM**; essa condição não concede administração global da Central.

A regra de aprovador é a da migração 006: administrador; aprovador individual; integrante da lista de aprovadores; aprovador de retorno especificamente para `retornar`; ou perfil assinante `aprovador`/`aprovador_supervis_o` quando não há aprovador individual nem lista geral. O acesso operacional segue a migração 010. A interface não reimplementa essa autorização a partir de nomes ou emails.

As ações são exclusivas conforme o estado:

| Etapa | Ações possíveis, sujeitas à autorização |
| --- | --- |
| Liberação, com a célula no status configurado | **Liberar** |
| Etapa de retorno, com a célula em `retornado` | **Retornar** e/ou **Aprovar** |
| Etapa de retorno, com a célula em outro status | **Aprovar**, se autorizado como aprovador geral |
| Etapa já decidida, sem alocação compatível ou sem autorização | Consulta com motivo |

Não existe ação **Finalizar ciclo** nesta interface. O motivo do retorno é obrigatório, como no gateway mobile da 006. A observação de liberar/aprovar é opcional. O limite é 10.000 caracteres.

## Leitura atômica e dados legados

A migração **020** instala duas RPCs `STABLE SECURITY INVOKER`, executadas com o JWT local do usuário e RLS:

```text
rm_web_stage_approvals_v1(
  p_project_id uuid = null,
  p_cell_id uuid = null,
  p_state text = 'pending',
  p_mine boolean = false,
  p_search text = '',
  p_page integer = 1,
  p_page_size integer = 25
)

rm_web_stage_approval_snapshot_v1(p_id uuid)
```

A lista retorna `{items,total,page,page_size}`. As situações são `pending` (`null`/`nulo`), `approved` (`aprovado`), `returned` (`reprovado`) e `all`. Cada item contém `stage`, `allocation`, `project`, `origin`, `destination`, `available_actions` e `action_reason`. O detalhe acrescenta `approvers`, `return_approvers`, `decided_by`, `history` e `legacy_history`.

O detalhe lê a etapa e a alocação no mesmo comando. As duas versões `updated_at` permanecem como textos exatos do banco, inclusive microssegundos; o navegador não as converte em datas antes de enviar. Uma etapa sem `celula_projeto_id` é resolvida pelo par único **projeto + célula de origem**, preservando o ID legado. A ausência de alocação compatível permite consulta com motivo e nenhuma decisão; instalar a 020 não preenche esses vínculos automaticamente.

O preflight de produção encontrou 945 registros na tabela legada: 70 modelos e 875 etapas de projetos, sendo 407 pendentes. Todos tinham o vínculo direto legado vazio; 94 etapas de projetos estavam sem alocação de origem. A fila exclui os modelos. Esses números descrevem a leitura anterior à entrega, não um critério para alterar os dados. A instalação não reescreve etapas ou alocações existentes.

Os DTOs do BFF selecionam explicitamente os campos operacionais usados na tela. Não retornam emails, Auth IDs, tokens, URLs de fotos/documentos, metadados de sincronização ou recibos privados. Não exigem acesso a fotos/documentos para consultar a aprovação. O BFF também verifica a associação dos históricos à etapa/projeto/célula e a correspondência das linhas com os filtros solicitados.

As permissões corporativas são aplicadas pelo BFF; as policies de leitura legadas do RM verificam identidade RM ativa. A existência das RPCs não significa que um cliente REST legado passe a consultar as concessões da Central. Essa fronteira permanece explícita, como nos módulos anteriores.

## Decisão transacional

A Server Action `transitionStageApproval` usa `rm_web_mutate_v1` com a operação **`transition_stage_approval`**:

```json
{
  "submissionId": "UUID do envio",
  "aprovacao_etapa_id": "UUID da etapa",
  "expected_updated_at": "updated_at exato da etapa",
  "expected_cell_updated_at": "updated_at exato da alocação",
  "acao": "liberar | retornar | aprovar",
  "observacao": "texto ou null"
}
```

O `submissionId` é separado do payload no envelope. O autor vem da sessão autenticada; campos externos de operador/autor, alterações arbitrárias e ações adicionais são recusados. Uma permissão SSO de uso único vincula sessão, operação, UUID, conteúdo e capacidade `em.approvals.decide`. O perfil ativo, TOTP quando verificado e a autorização operacional são validados no banco.

A transação adquire o mesmo bloqueio de projeto utilizado pelo mobile e pelo planejamento antes de bloquear as linhas. As duas versões devem continuar iguais; uma alteração da célula ou etapa resulta em `PT409`, sem sobrescrever o operador ou outro planejador. Depois da validação, chama **`rm_transition_stage_approval_v1`**, preservando as regras existentes de liberação, reabertura, retorno, visibilidade e destinos.

Na interface, uma resposta de rede ambígua conserva o mesmo UUID, ação, observação e versões. A retentativa confirma o resultado do mesmo envio, sem duplicar decisão, comentários ou efeitos. Após conflito, é necessário atualizar a etapa; a tela não reaproveita uma intenção antiga sobre um estado novo. O sucesso provoca nova leitura completa da página, seguindo o comportamento do portal.

A transação compartilhada acrescenta apenas os IDs de log/comentário e etapas afetadas ao retorno interno, sem remover chaves usadas pelo mobile. Não modifica os IDs de formulários, respostas, filas offline, projetos ou credenciais existentes.

## Histórico e efeitos externos

A tabela nova **`rm_web_stage_decisions`** guarda o vínculo exato entre etapa, alocação, ator, ação, estados anterior/novo, observação, log/comentário e UUID do envio. A leitura segue RLS; INSERT/UPDATE/DELETE diretos ficam revogados, inclusive para o papel de serviço. A gravação ocorre somente pela transação autorizada.

- `history` contém decisões web com vínculo explícito à etapa e autoria. Não inventa ações a partir do texto de um status antigo.
- `legacy_history` reúne os logs da mesma célula/projeto que não possuem vínculo com uma nova decisão web. A tela os identifica como histórico da célula, incluindo decisões antigas/mobile, sem atribuí-los indevidamente a uma etapa específica. Logs já vinculados às novas decisões não aparecem duplicados.
- Os recibos privados preservam o envio original e seu resultado para replay idempotente. O BFF devolve somente IDs públicos, operação, versão e indicação de replay; não encaminha o envelope bruto para o navegador.

A transação mantém os eventos de saída históricos na outbox, como o mobile. O worker permanece **`SYNC_OUTBOX_ENABLED=false`**. Esta entrega não envia mensagens, emails, webhooks nem grava dados no Bubble. A ativação de coexistência continua uma entrega explícita e separada.

## Publicação e validação

Aplicar somente a nova migração **020**, após validar 001–020 em PostgreSQL isolado. As migrações 001–019 já publicadas são imutáveis. A instalação adiciona sua tabela vazia e contratos; não cria decisões artificiais em produção.

A ordem do acesso corporativo é: validar banco e aplicação; aplicar 020 com verificação dos dados preservados; publicar consumidor compatível com **18 capacidades**; confirmar deploy e rotas protegidas; só então registrar/conceder `em.approvals.read` e `em.approvals.decide` aos administradores EM aprovados. Sessões anteriores com 12/14/16 capacidades continuam aceitas, sem inferir as duas novas permissões.

Os testes do BFF verificam negações de acesso antes de consultas, escopos independentes, versões exatas, payload sem ator, obrigação de motivo no retorno, replay, DTO sem metadados privados, filtros/paginação, históricos cruzados e etapas legadas sem alocação. As provas SQL, navegador, CI, snapshots remotos e publicação final ficam registradas no plano e na documentação do portal; testes simulados não são apresentados como decisões reais ou login Microsoft de uma pessoa.

Referências: [migração 020](migrations/020_rm_web_stage_approvals.sql), [política BFF](../desktop/src/server/web/stage-approval-policy.ts), [leituras](../desktop/src/server/web/stage-approval-data.ts), [ações](../desktop/src/server/web/stage-approval-mutations.ts), [transação mobile](migrations/011_rm_project_operations.sql), [autorização do operador](migrations/010_rm_operator_cell_permissions.sql) e [ponte SSO](SSO_BRIDGE.md).

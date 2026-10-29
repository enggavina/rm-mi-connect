# Roteiro de células por projeto

Contrato e plano antes da implementação, em 29/10/2026. Referência: `rm_planejamento` → `Group Gestao_projeto_redesign/comJg`, conforme [discovery do planejamento](../docs/discovery_rmmi_planejamento.md). O comando organiza **células de um projeto por `indice`**. A fila da 021 organiza **projetos de uma célula por `posicao`**. São operações independentes.

## Plano do incremento

1. Leitor de snapshot atômico e mínimo do projeto e de todas as suas alocações, com versão do conjunto e limite de edição explícito.
2. Validação estrita/BFF reutilizando capacidades, perfis, permits SSO, recibos e revisões exatas existentes.
3. Comando transacional de permutação completa, gravando índice 1…N somente por confirmação explícita, sem reescrever estado operacional ou fila.
4. Editor reutilizando `useEngineeringSave`, avisos de erro/retry/conflito, congelamento do envio e controles acessíveis de subir/descer.
5. Testes de políticas/leitor/ações/modelo, PostgreSQL, upgrade e disputa entre escritores. Integração de página e publicação ficam com o responsável pelo incremento.

Não editar migrações aplicadas nem dados reais. A 023 de títulos deve estar estável antes de encadear o dispatcher na 024; instalar o incremento não deve alterar linhas existentes.

## Snapshot e componente de integração

RPC: **`rm_web_project_route_snapshot_v1(p_project_id uuid)`**, `STABLE SECURITY INVOKER`, leitura com JWT e RLS atuais. Projeto inexistente/inacessível retorna null. O BFF exige `em.portal.read`, **`em.planning.read`** e **`em.projects.read`** antes da query.

```text
ProjectRouteSnapshot {
  project: {
    id, numero: string|null, nome: string|null,
    status_pcp: string|null, data_real_de_entrega: timestamp|null,
    updated_at: timestamp, closed: boolean
  },
  items: [{
    id, celula_id: UUID|null, celula_nome: string|null,
    status: string|null, visibilidade: boolean,
    indice: integer|null, updated_at: timestamp
  }],
  route_version: SHA256 hex minúsculo,
  total: integer, complete: boolean
}
```

Inclui **todas** as alocações do projeto, inclusive ocultas e concluídas, ordenadas por `indice ASC NULLS LAST, id ASC`. Não filtra pelo conjunto da fila aberta da 021 nem exclui uma alocação por falta de rótulo de célula na leitura. O esquema atual exige célula vinculada; o DTO aceita rótulo ausente para não inventar um nome. Índices negativos, esparsos, repetidos e nulos são apresentados sem normalização automática.

O limite de edição é **2.000 alocações**. Acima dele, `complete=false`, `total` real e `items=[]`: não oferece subconjunto como se fosse o conjunto completo. O hash corresponde ao estado completo, incluindo projeto, membros, versões e ordem necessários à conferência. Os timestamps permanecem strings exatas do banco, sem conversão por `Date`.

Exportações locais para integração:

```tsx
getProjectRoute(projectId) // server/web/project-route-data.ts
<ProjectRouteEditor snapshot={snapshot} canEdit={canEdit} destination={destination} />
```

O responsável pela página passa `canEdit` segundo acesso atual e perfil. O componente também protege projeto encerrado e snapshot incompleto. `destination` é a rota interna para voltar/recarregar após sucesso/conflito, fornecida pela página.

## Escrita e autorização

Operação: **`save_project_route`**, capability de permit existente **`em.planning.manage`**. BFF também exige `em.projects.read` e `em.planning.read`, perfil RM ativo `administrador` ou `padr_o`; auditor consulta. Não altera concessões da Central nem identidades mobile.

```json
{
  "submissionId": "UUID do envio — separado do payload pelo envelope",
  "projeto_id": "UUID do projeto",
  "expected_project_updated_at": "timestamp exato do projeto",
  "expected_route_version": "SHA256 exato do snapshot",
  "items": [
    {"id": "UUID da alocação", "expected_updated_at": "timestamp exato da alocação"}
  ]
}
```

Payload e itens são estritos. IDs repetidos, campos adicionais, índices/posições/status arbitrários, versões ausentes, conjunto parcial ou com alocação de outro projeto são recusados. A lista possui entre 1 e 2.000 membros. O array completo expressa a ordem desejada, que será gravada em `indice=1..N` após a confirmação na UI.

O projeto deve existir e estar aberto segundo as regras atuais do EM: sem entrega realizada e sem status PCP `cancelado` ou `finalizando_para_faturar`. Projeto encerrado permanece consultável, mas não aceita nova ordem, inclusive um no-op com UUID novo. Isso é uma diferença deliberada em relação ao legado, alinhada à proteção já existente de planejamento. Replay exato de uma operação anterior continua retornando seu recibo, com autenticação/permit/MFA revalidados.

Somente índices realmente diferentes são atualizados, com autoria/replanejamento e `sync_source='supabase'` segundo o padrão de planejamento. Linhas já no índice solicitado conservam timestamps e demais metadados. Não escrever `posicao`, prioridade, status, visibilidade, formulários, datas, responsável ou conteúdo operacional. Se toda a sequência já for 1…N, o envio é no-op e conserva todas as linhas; ainda produz recibo.

## Concorrência e persistência

Sequência: recibo no namespace 14 → projeto no namespace 11 → linha do projeto → todas as alocações em ordem estável de ID. O conjunto completo/hash e versões são conferidos após os locks. Nova alocação/materialização, execução mobile, fila da célula e mudanças no projeto devem invalidar o snapshot antigo ou serializar sem sobrescrever o trabalho mais recente. Usar `PT409` para versão/conjunto divergente.

Reutilizar o envelope público atual, permit fresco em cada tentativa, MFA e recibo. Mesmo UUID+ator+operação+payload retorna replay sem repetir escritas; UUID reaproveitado com outra intenção/ator é recusado. O comando 024 deve delegar todas as operações anteriores, preservar os nomes dos cores anteriores e recompilar o wrapper público após o rename para evitar OID aquecido.

A 024 preserva o core da 023 como `rm_private.web_mutate_photo_title_core_v1`, acrescenta `save_project_route → em.planning.manage` à allowlist de 15 operações e recompila o wrapper. O leitor é a única RPC nova; não há nova tabela, capacidade ou concessão. O hash inclui a revisão do catálogo das células, para que uma mudança de rótulo durante a conferência também exija releitura.

O resultado do banco contém envelope padrão e `record` mínimo com `projeto_id`, `route_version` final e IDs de alocações alteradas. Snapshots privados de auditoria ficam no servidor. O BFF não devolve arquivos, dados Auth ou linhas completas.

## Aceitação e limites

- Abrir a tela não altera os índices legados; normalização exige “Confirmar sequência exibida” ou mover célula, mais conferência explícita antes de salvar.
- Trocar projeto reinicia o componente por chave de projeto/versão na página; o envio usa o projeto do snapshot e não outro estado de navegação.
- Erro de conexão congela UUID/payload e oferece retry do mesmo envio. Conflito exige releitura; acesso revogado bloqueia nova edição. Sair com edição pendente pede confirmação do navegador.
- Ordem do roteiro não deve mudar a fila `posicao` ou prioridades. A fila pode usar `indice` como fallback quando não há posição; a preferência continua sendo `posicao` e não se cria uma segunda fila automaticamente.
- Este incremento cobre ordenação. Remover alocação, editar status livremente, atribuir fotos/avaliadores e configurar etapas operacionais são entregas distintas do plano de paridade.
- Não há mudança no Bubble, ponte de saída ou integração do Report Building.

## Arquivos e validação

- Backend: `desktop/src/server/web/project-route-{policy,data,actions,mutations}.ts`.
- UI: `desktop/src/components/web/project-route-editor.tsx`, modelo e CSS próprios; reaproveita `useEngineeringSave`, estado de falha e funções de movimentação já existentes.
- Banco: `migrations/024_rm_web_project_route.sql`, `tests/web_project_route.sql`, `tests/web_project_route_upgrade.sql`; o runner integrado inclui a 024 após a 023.
- Testes TypeScript: políticas/ações, leitor/DTO e modelo do editor em `desktop/tests/project-route-*.test.ts`.

O ensaio de upgrade compara snapshots completos das 56 tabelas públicas RM e 11 privadas antes/depois, aquece o wrapper da 023 e testa despacho antigo/novo e replay, conservando posições da fila. A suíte funcional cobre escopo completo, índices nulos/negativos/esparsos, campos operacionais intactos, proteção de leitura/escrita, SSO/MFA/permit/sessão, fechado/no-op/conflito e conjunto acima do limite.

As disputas reais usam duas conexões PostgreSQL em 14 cenários: dois planejadores, mesmo UUID, execução mobile, planejamento de nova alocação, fila da célula, materialização, fechamento de projeto e inserção via FK, com os sentidos relevantes. Fixtures permanecem exclusivamente no PostgreSQL descartável.

**Validação local em 29/10/2026: aprovada.** Nove testes TypeScript próprios e `tsc --noEmit --incremental false` passaram. O runner integrado 001–024 encerrou com sucesso nas **13 suítes SQL**, incluindo os ensaios de upgrade; a 024 conservou os 67 snapshots e passou os 14 cenários de disputa reais. A rodada rápida isolada da 024 também passou antes do percurso final. Logs ignorados: `.tmp/project-route-sql-tests.log` e `.tmp/project-route-quick.log`. Houve correções na preparação de testes (ordem de lock na fixture 023 e precedência de um operador JSON na fixture 024); nenhuma flexibilização da regra de negócio foi necessária.

Build integrado, QA da página e publicação são registrados pelo responsável pelo incremento. Esta documentação não declara aplicação remota da 024 ou deploy por sua mera existência.

### Navegação de contexto no Cronograma

O QA do build anterior à publicação reproduziu cliques NextLink em seleção de célula/aba que recebiam RSC 200, mas não confirmavam URL/DOM. Não houve diálogo bloqueando, erro de console, `pageerror` ou React #418. A mesma URL por acesso direto e por clone nativo da âncora carregou corretamente; RSC solicitado diretamente também terminou com conteúdo correto. O controle interceptando somente origens externas manteve a falha, eliminando o callback de interceptação de localhost como explicação suficiente.

A correção usa navegação nativa nas mudanças de contexto/query do Cronograma (projeto, célula, abas, fechar/trocar e visão Gantt), seguindo o padrão já usado nas abas do dossiê. As URLs, capacidades, guardas e confirmação de saída do editor permanecem; links para outros caminhos e o Shell/Suspense não foram substituídos. Paginação e períodos Gantt já usavam âncoras nativas. A causa interna específica do caminho Next/React não foi demonstrada, portanto a correção é uma adaptação localizada de confiabilidade. O responsável repetirá o QA completo após reconstruir o build.

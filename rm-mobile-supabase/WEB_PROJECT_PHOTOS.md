# Fotos de projeto: seleção individual para relatório

Incremento da revisão de paridade de 29/10/2026. Origem funcional: [discovery de fotos e Report Building](../docs/discovery_rmmi_fotos_report_builder.md). A seleção persiste em **`rm_fotos.selecao_relatorio`**, campo booleano existente e já importado do Bubble. Não há tabela de seleções, cópia de arquivos ou nova lista de IDs.

## Comando e autorização

A ação do portal usa `rm_web_mutate_v1` com operação **`set_project_photo_selection`**. `submissionId` pertence ao envelope; o payload do banco contém exatamente:

```json
{
  "projeto_id": "UUID do projeto",
  "foto_id": "UUID da foto",
  "expected_updated_at": "2026-10-29T18:30:00.123456+00:00",
  "selected": true
}
```

`selected` deve ser booleano JSON; strings, números e null são recusados. Todos os quatro campos são obrigatórios, nenhum campo adicional é aceito. A versão exige timestamp ISO com fuso explícito, finito, e deve representar o instante exato retornado pelo banco. Não passar por `Date`/arredondamento de microssegundos. UUID/data inválidos geram `22023` e versão divergente **`PT409`**.

A capacidade de escrita é a existente **`em.projects.manage`**, com perfil RM ativo `administrador` ou `padr_o`. O BFF também verifica as capacidades de consulta `em.projects.read` e `em.photos.read` usadas pela página. Auditor continua somente consultando. Não há nova capacidade nem concessão na Central; a autoria vem da sessão e não pode ser enviada no payload.

O envelope atual de SSO é preservado: vínculo aprovado/ativo, sessão Auth exata, sessão opaca válida e permit fresco da operação+payload+capacidade, consumido atomicamente com a mutação. Mesmo replay exige novo permit autorizado. TOTP verificado exige AAL2 também no replay. O modo legado anterior à ativação SSO mantém suas regras existentes; este incremento não o ativa nem concede novos vínculos.

## Escopo e persistência

- O projeto deve existir e a foto deve pertencer exatamente a ele.
- Modelos têm `projeto_id IS NULL` no esquema atual; não existe coluna `is_template`. O vínculo obrigatório ao projeto exclui modelos sem criar outro marcador.
- Foto em lixeira, sem `foto_url` ou com URL em branco é recusada. A lista `fotos_arquivos_urls` não é convertida em arquivo principal artificialmente.
- Projetos cancelados, entregues ou em finalização continuam selecionáveis: relatórios históricos também usam esse indicador e o workflow original não impõe projeto aberto.
- Somente `selecao_relatorio`, `modified_by_id` e `sync_source='supabase'` são escritos; o trigger existente avança `updated_at`. Arquivos, ordem (`numero`), tag, título, categoria, legenda, criador e vínculos permanecem intactos.
- Se o estado solicitado já coincide com o salvo e a versão é atual, nenhuma linha de foto é atualizada: conserva inclusive versão/autoria. O envio ainda recebe recibo idempotente.

Resultado segue o envelope existente. O objeto `record` tem somente:

```json
{
  "foto_id": "UUID da foto",
  "projeto_id": "UUID do projeto",
  "selecao_relatorio": true,
  "updated_at": "versão exata atual da foto"
}
```

O envelope contém `operation`, `id` (foto), `projeto_id`, `updated_at`, `record` e `idempotent_replay`. Não retorna URL de arquivo nem outros campos privados. O recibo privado guarda payload, resultado e a linha anterior para auditoria. O mesmo UUID com outro ator/operação/payload é recusado; replay exato retorna o resultado anterior sem novo UPDATE, mesmo que a versão original já esteja desatualizada.

## Concorrência e upgrade

A migração **022** preserva o dispatcher 021 como `rm_private.web_mutate_pcp_core_v1`. O novo dispatcher trata somente a nova operação e delega as 12 anteriores. A allowlist de permits passa a 13 operações, mapeando seleção a `em.projects.manage`. O wrapper público é recompilado após o rename para evitar que uma sessão previamente aquecida continue chamando o OID antigo. Funções privadas continuam sem EXECUTE para `anon`, `authenticated` e `service_role`.

A sequência de locks é recibo/UUID no namespace 14 → projeto no namespace 11 → linha do projeto → linha da foto. O comando verifica a versão depois de obter os locks. Seleções concorrentes com UUIDs distintos não sobrescrevem a primeira; o segundo recebe conflito. Mesmo UUID serializa e gera um recibo. Alteração de metadados/referência ou exclusão concorrente é observada antes de gravar. Selecionar não bloqueia a alteração posterior de metadados nem muda o fechamento do projeto.

A instalação não altera registros existentes. As migrações 001–021 permanecem imutáveis. O ensaio de upgrade 021→022 compara snapshots completos das 56 tabelas públicas RM e 11 tabelas privadas e aquece o wrapper antes da instalação, verificando encaminhamento de operação antiga/nova, replay e no-op.

## Report Building e limites

Salvar a seleção não gera relatório nem troca o fornecedor de dados do Report Building. O consumidor atual permanece no fluxo legado/n8n. A futura fonte Supabase deverá filtrar `selecao_relatorio=true`, excluir modelos/lixeira e entregar fotos na ordem `numero`, com desempate estável por ID, preservando o contrato de URL/caption/tag/ordem. A ordenação visual por selecionadas primeiro não altera a ordem persistente do relatório.

A ponte de saída continua desativada. Coexistência/reimportação precisa reconciliar autoridade de seleção antes de sobrescrever decisões locais. As APIs de geração e compilação continuam fora deste incremento; compatibilidade do campo não comprova homologação de um PDF real.

## Validação automatizada

O runner `tests/run-local-tests.ps1` cria um PostgreSQL descartável, aplica 001–022 e executa a suíte existente mais `web_project_photo_selection.sql`. A 022 é instalada pelo ensaio `web_project_photo_selection_upgrade.sql` durante o percurso, comprovando preservação dos dados e do wrapper já compilado.

A suíte cobre formato e escopo, modelo/lixeira/arquivo ausente, vínculo com outro projeto, função/perfil/SSO/MFA, permit expirado e sessão divergente, replay exato e payload/ator trocado, conflito de versão, seleção/deseleção, projeto fechado, no-op e comparação dos demais campos. Duas conexões reais PostgreSQL disputam locks em sete cenários: seleções simultâneas, mesmo UUID, escritor de metadados antes/depois, fechamento do projeto, troca da referência de projeto e exclusão concorrente. Nenhum desses dados artificiais é enviado à produção.

**Execução local em 29/10/2026: aprovada.** O runner completo aplicou 001–022 e passou as 11 suítes SQL, os ensaios de upgrade e as sete novas disputas. O upgrade da 022 conservou os 67 snapshots completos e o wrapper aquecido encaminhou os comandos antigos e o novo. A primeira execução encontrou colisão de um identificador da fixture com outra suíte; a fixture foi isolada e o percurso completo foi executado novamente com sucesso. Log local ignorado: `.tmp/photo-selection-sql-tests.log`.

O resultado de publicação e os checks do BFF/UI são registrados pelo responsável pelo incremento no [plano de execução](../docs/plano_execucao_paridade_rmmi.md) e na documentação do portal. Este contrato não declara aplicação remota da migração nem deploy por sua mera existência.

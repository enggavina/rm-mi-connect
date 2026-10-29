# Fotos obrigatórias operacionais por alocação

Contrato definido antes da implementação em 29/10/2026. Complementa o [discovery do Group comJg](../docs/discovery_rmmi_planejamento.md). Reutiliza `rm_fotos`, `rm_cadastro_fotos`, `lixeira`, `tag`, campos de arquivo e gateway de mutação existentes; não cria entidade paralela nem usa a quantidade prevista de fotos.

## Contexto e snapshot

`rm_web_operational_photos_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_titles boolean default false)` é uma leitura STABLE/SECURITY INVOKER com JWT/RLS do usuário. A alocação deve pertencer ao projeto. Fotos abrangem projeto+célula com vínculo exato à alocação ou vínculo legado nulo; não incluem modelos ou fotos de outra alocação.

DTO sem URLs/credenciais:

- `project`: id, numero, status_pcp, data_real_de_entrega, updated_at, closed.
- `allocation`: id, projeto_id, celula_id, celula_nome, status, updated_at.
- `photos`: id, projeto_id, celula_id, celula_projeto_id, cadastro_foto_id, titulo, categoria_foto, tag, numero, updated_at, captured, selected_for_report, retired, can_edit_tag, can_retire, can_restore, action_reason.
- `titles`: id, titulo, numero, updated_at, assigned, retired_photo_id.
- `photos_version` (SHA256), `total`, `complete`, `titles_total`, `titles_complete`.

O hash cobre contexto/projeto/alocação/célula, todas as versões dos slots e títulos aplicáveis, inclusive quando a consulta omite títulos. Até 2.000 fotos e 1.000 títulos; acima disso a coleção correspondente é vazia e incompleta. Fotos incompletas bloqueiam todas as escritas; títulos incompletos bloqueiam somente adicionar, preservando correções/retiradas/restaurações de fotos cujo conjunto é completo. Os títulos são globais ou possuem nome de célula resolvido de forma única para a célula atual. A comparação de nomes/títulos segue o catálogo existente: minúsculas, whitespace consecutivo convertido em espaço e aparas nas bordas. Nome ambíguo não se torna global. Título em branco não é oferecido.

O BFF exige portal/projeto/planejamento/fotos para leitura. Somente escritor RM com `em.planning.manage` recebe choices (`p_include_titles=true`); não é concedido `em.engineering.read` nem exposto o catálogo inteiro. Auditor não recebe choices mesmo pedindo diretamente no RPC.

## Comando

Operação `manage_operational_photos`, capability existente `em.planning.manage`. Perfil ativo administrador/padrão, MFA e SSO frescos continuam obrigatórios, inclusive no replay. Envelope inclui UUID de submissão e payload fechado:

```text
common = {action, projeto_id, celula_projeto_id,
          expected_project_updated_at, expected_allocation_updated_at,
          expected_photos_version}
add     = common + {items:[{id,cadastro_foto_id}]}  // 1..100, UUIDs estáveis
tag     = common + {foto_id,expected_foto_updated_at,tag:string|null}
retire  = common + {foto_id,expected_foto_updated_at}
restore = common + {foto_id,expected_foto_updated_at}
```

Resultado público: `{operation:'manage_operational_photos',id:celula_projeto_id,projeto_id,updated_at,record:{projeto_id,celula_projeto_id,action,photos_version,changed_ids:uuid[]},idempotent_replay:boolean}`. `changed_ids` é vazio em no-op; no lote contém somente IDs enviados. Os campos privados do recibo não são projetados no resultado.

Datas são strings ISO com fuso e precisão preservada. `tag` aceita até 2.000 caracteres e não é trimada silenciosamente. Erros de versão/conjunto geram PT409; formato/escopo/duplicidade geram 22023. Não aceitar autoria, URLs, categoria ou estado de captura do cliente.

Adicionar cria somente slots obrigatórios, sem arquivo, no projeto/alocação atual. Título é snapshot do catálogo; `numero` continua uma sequência local de referência derivada do maior número da célula, sem mudar números anteriores. Não duplicar cadastro ou título normalizado em slots obrigatórios ativos **ou retirados**; uma retirada deve ser restaurada, não recriada com outro ID. Não alterar o modelo da Engenharia.

Tag pode ser editada em foto obrigatória ativa, inclusive capturada; o workflow original não guardava ausência de captura. Arquivos, seleção de relatório e número permanecem preservados. Retirar exige foto obrigatória vazia, não selecionada, sem arquivo principal nem entrada não vazia em `fotos_arquivos_urls`. A retirada usa `lixeira=true`, conservando ID/histórico. Restaurar exige slot obrigatório retirado vazio/não selecionado e ausência de cadastro/título ativo duplicado. Restaura o mesmo ID; nunca recria arquivos. Tag/retirar/restaurar sem mudança solicitada e com versões atuais são no-op e preservam timestamp/autoria, mas ganham recibo.

Projetos entregues/cancelados/finalizando e alocações finalizadas/N/A são somente consulta. O comando não altera status, formulários, visibilidade, datas, prioridade ou posições de fila/roteiro.

## Offline, concorrência e recuperação

O legado de captura forçava `lixeira=false`. Portanto aposentar um slot sem endurecer a captura permitiria restauração silenciosa. A 025 acrescenta guarda na RPC de captura existente: lock do projeto (namespace11) antes de linha do projeto/foto FOR UPDATE; slot retirado gera PT409 com orientação de restauração pelo gestor. A captura ativa continua com os mesmos parâmetros/resultado. Replay de captura já concluída segue vindo do recibo do envelope, antes de reavaliar o slot.

O mobile atual grava `last_error` e conserva payload/token/arquivo quando a RPC falha. A fila é FIFO e fica parada nessa tentativa; o gestor vê os itens retirados e pode restaurar o ID original. Depois a retentativa do **mesmo UUID** conclui sem apagar fila/arquivo ou atribuição do operador. Não foi necessário trocar o APK, reautenticar outra pessoa ou descartar capturas. Retirar e capturar disputam o mesmo projeto/foto: captura primeiro impede retirada; retirada primeiro exige restauração explícita. Não há hard-delete nem restauração automática.

Ordem de locks web: recibo14 → projeto11 → projeto/alocação → catálogo17 compartilhado → célula → títulos solicitados em SHARE → fotos por ID. Permissão/recibo/hash/versões são conferidos antes da escrita. Vínculos existentes e fotos legadas nulas são preservados. O before_record privado guarda snapshot anterior; resultado público mínimo contém contexto, ação, IDs afetados e hash atual. Replays não repetem inserções nem criam novo evento.

## Retirada de quantidade prevista

`numero_fotos` permanece na coluna histórica e no snapshot legado. Novos `save_engineering.changes.numero_fotos` são recusados pelo dispatcher 025; recibos anteriores dessa operação continuam delegados para replay exato, com autorização atual. Campo, projeção e payload novos do portal são removidos separadamente. Não zerar valores antigos nem editar migrações aplicadas.

## Reversão e limites

Retirada operacional é reversível pelo comando restore e pelo mesmo ID, com auditoria/versão. Uma reversão de implantação não deve apagar dados nem remover a proteção de captura enquanto existirem slots retirados: manter a 025 e voltar somente o consumidor web é a opção segura. Se for necessário substituir o contrato, fazê-lo em migração posterior preservando IDs/recibos; não executar DROP nem restaurar todas as lixeiras por lote.

Validação SQL: `tests/web_operational_photos.sql` cobre escopo, DTO sem mídia, escolhas contextuais, payload fechado, captura em lista de arquivos, preservação de metadados, retirada/restauração, no-op, limites, perfis/SSO/MFA e retentativa offline do mesmo UUID. Inclui 12 disputas reais por dblink: captura/retirada/tag, lotes e UUID concorrentes, escritor técnico de título sem advisory de catálogo nos dois sentidos, fechamento e tag tardia. `tests/web_operational_photos_upgrade.sql` compara integralmente as 67 tabelas públicas/privadas na instalação e aquece os callers web/mobile antes de atualizar, preservando recibos antigos, valor histórico e guarda nova de captura. `tests/run-local-tests.ps1` instala a 025 através dessa prova de upgrade e executa a suite junto das regressões existentes, sempre em PostgreSQL isolado.

Provas de execução/publicação ficam nos documentos de entrega. Nenhum dado artificial ou chamada de gravação no Bubble faz parte deste contrato.

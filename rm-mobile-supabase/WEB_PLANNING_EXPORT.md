# Exportação configurável das alocações para Excel

Contrato do incremento 043, em 12/11/2026. Continuação do Planejamento existente, com a relação `rm_celulas_projeto` como unidade operacional. Uma linha corresponde a uma alocação; o mesmo projeto pode aparecer em duas abas quando pertence a duas células selecionadas. Não cria campos, snapshots de negócio persistidos, auditoria paralela ou uma nova permissão.

## Jornada

Em **Planejamento → Exportar para Excel**, um diálogo oferece a escolha das células e das informações, agrupadas em Projeto, Equipamento e Célula/alocação. O catálogo tem 43 campos reais; nove vêm selecionados inicialmente. Uma célula filtrada na página pode iniciar selecionada, mas filtros de busca, status e paginação da lista não restringem o arquivo.

O usuário pode buscar células, selecionar as exibidas, limpar a seleção e marcar/desmarcar os campos. A busca preserva as células já selecionadas fora do filtro e mantém a contagem visível. Seleções vazias são recusadas com mensagem antes do envio. A seleção dos campos segue a ordem do catálogo, de forma consistente com a interface. O catálogo autorizado está em [allocation-export-policy.ts](../desktop/src/server/web/allocation-export-policy.ts).

A interface envia somente os IDs das células e chaves dos campos. Não carrega no navegador todos os projetos ou dados técnicos para montar o arquivo. Durante a geração, os controles ficam protegidos; cancelar, fechar ou usar Escape aborta a requisição de leitura. Uma resposta de login, erro, conteúdo de outro formato ou arquivo vazio não vira download. O arquivo usa o nome legível retornado pelo servidor, com fallback seguro sem caminhos ou extensões arbitrárias.

## Endpoint e autorização

`POST /api/web/planning/export`, runtime Node, recebe JSON fechado:

```json
{"cell_ids":["UUID da célula"],"fields":["project_number","equipment_type","cell_name","allocation_status"]}
```

A rota exige origem POST igual ao host, sessão atual, MFA quando cadastrada, perfil interno administrador/padrão/auditor e as capacidades existentes `em.portal.read`, `em.planning.read` e `em.projects.read`. O botão usa o mesmo conjunto de capacidades; a proteção do servidor independe desse controle visual. Não é feita concessão nova na Central.

O servidor consulta com o JWT do usuário, sem usar uma chave de serviço para ler dados de negócio. A RPC pública `rm_web_planning_export_snapshot_v1(uuid[],text[])` é **STABLE SECURITY INVOKER**, com execução concedida somente a `authenticated`. RLS continua governando células, alocações, projetos, clientes, usuários, equipamentos e tipos. Uma célula selecionada indisponível ou uma alocação visível cujo projeto esteja indisponível recusa a exportação completa; não retorna sucesso parcial. Equipamento/tipo escondido pela própria RLS fica vazio.

`rm_private.web_planning_export_allowed_v1()` confere identidade interna ativa e AAL. O único outro helper elevado é a validação opaca e em lote `rm_private.web_export_shared_equipment_v1(uuid[])`: devolve apenas um subconjunto dos IDs de equipamentos já fornecidos, para marcar vínculos compartilhados. Não retorna nomes, IDs ou informações dos projetos que usam esses equipamentos. Essa prova precisa enxergar referências ocultas por RLS para não interpretar um vínculo compartilhado como exclusivo. Todos os dados exibidos continuam vindo dos joins executados como o usuário.

Os erros são respostas JSON curtas e sem detalhes internos; o download usa `Content-Disposition: attachment`, MIME XLSX, `Cache-Control: private, no-store`, `Vary: Cookie` e `X-Content-Type-Options: nosniff`. Não são enviados e-mails, eventos Bubble ou gravações de negócio por uma exportação.

## Fonte e integridade

Uma chamada da RPC produz o snapshot completo, com a hora da leitura, os campos escolhidos e uma coleção por célula na ordem solicitada. Os joins e a prova opaca são feitos em lote, sem consulta por projeto. A função estável conserva a coerência de leitura dos seus resultados; não há paginação PostgREST de mil linhas ou deduplicação por projeto.

São incluídas as alocações `retirada=false`, conforme a lista atual de Planejamento: ocultas no mobile e projetos encerrados continuam incluídos. Retiradas ficam fora do arquivo. Uma célula selecionada sem alocações ainda produz sua própria aba com cabeçalho.

O vínculo de equipamento exige `projeto.equipamento_id = equipamento.id`, `equipamento.projeto_id = projeto.id` e ausência de compartilhamento com outro projeto. A prova em lote também identifica compartilhamento por projetos ocultos ao usuário. Vínculos ausentes, reversos divergentes ou compartilhados não escolhem o primeiro equipamento nem usam `projeto.tipo_equipamento_id`/descrições legadas como atalho. Um equipamento exato sem tipo mantém os outros dados permitidos e deixa o tipo vazio.

O tipo é apresentado como **SIGLA - NOME**, usando a relação Equipamento → Tipo. Status de projeto e status da célula permanecem separados. Status, prioridade e placa do motor usam os rótulos dos Option Sets existentes, incluindo **Aguardando coleta** e **Coletado**. Cliente, gestor e responsável usam representações legíveis. IDs, UUIDs e foreign keys do snapshot servem apenas à validação interna e não são colunas do arquivo.

## Workbook

ExcelJS gera um XLSX real no servidor, usando o writer de streaming e commit de cada linha. Cada célula selecionada gera uma worksheet, com somente os campos escolhidos. Os nomes técnicos das abas respeitam os 31 caracteres, caracteres proibidos, nomes vazios, `History`, Unicode e duplicações sem distinguir maiúsculas/minúsculas. O texto exibido nos dados não é renomeado para caber na aba.

O cabeçalho é destacado, a primeira linha fica congelada, há autofiltro e larguras por campo. Datas e horas válidas são tipadas para Excel e apresentadas no calendário de São Paulo; horas previstas/realizadas permanecem números. Texto, unidades e zeros à esquerda são preservados. Valores com aparência de fórmula continuam texto; não são criadas fórmulas, macros, hyperlinks ou consultas externas.

Nome do arquivo: `planejamento_alocacoes_YYYY-MM-DD.xlsx`, com data de São Paulo. Não é CSV renomeado. A biblioteca cuida da codificação XML dos conteúdos. O arquivo não é salvo em Storage ou em tabelas de documentos: a resposta é um download direto e privado.

## Limites e performance

- Requisição JSON de até 16 KiB, sem células ou campos repetidos.
- Uma a 200 células e um a 43 campos do catálogo.
- Até 20.000 alocações, inclusive; 20.001 recusa com `PT413`.
- Snapshot JSON de até 20 MiB e workbook limitado a 64 MiB no gerador.

Exceder um limite gera uma falha explícita, orientando reduzir a seleção, sem arquivo parcial. O snapshot em memória é limitado e as células do workbook são liberadas a cada commit de linha; o ZIP resultante é reunido para responder ao navegador. O cancelamento da requisição é observado durante a geração.

## Banco e validação

A migração [043](migrations/043_rm_web_planning_export.sql) acrescenta somente as três funções citadas. Não modifica tabelas, enums, seeds, dados, policies, índices, triggers, permissões anteriores ou os gateways de mutação. A extensão do status de alocação pertence às migrações 041/042, separadas deste contrato de leitura.

`tests/web_planning_export.sql` verifica uma/múltiplas células, o mesmo projeto em duas células, seleção de campos, valores reais, tipo exato e legados sem vínculo/tipo, compartilhamento visível/oculto, status novos, células vazias, alocações ocultas/encerradas/retiradas, perfis, inatividade, MFA, grants, RLS restritiva de células/projetos/alocações/equipamentos/tipos, mais de mil linhas, limite inclusivo de 20.000, 20.001 e limite em bytes. Fixtures de vínculos legados inconsistentes e volume usam somente PostgreSQL descartável em loopback e são desfeitas por rollback.

`tests/web_planning_export_upgrade.sql` aplica 043 sobre 001–042 com dados e caller/recibo aquecidos. Compara todas as linhas RM/privadas/Auth/Storage e os OIDs, definições, owners, ACLs, colunas, defaults, índices, constraints, triggers e policies anteriores; confere somente três funções novas e replay do recibo anterior. Nova leitura e replay também não alteram os dados registrados na prova.

Os testes de UI/modelo verificam seleção vazia, contexto permitido, limite, corpo mínimo, origem local, resposta de erro/login/formato, download e nome seguro. O ensaio de React/CSS em 1240 e 390 px usa o catálogo real, HTTP simulado e nenhum dado de produção. Testes do workbook/API, validação global, CI e publicação ficam registrados no relatório geral desta entrega; uma inspeção de UI simulada não é apresentada como uma exportação autenticada real de produção.

# Planejamento: status da célula, informações do equipamento e Excel

**Entrega publicada em 12/11/2026 no [EM web](https://em-web-production.up.railway.app).** Consumidor `eb8e1e9b8605cef46d33bb936be285d5bebf8b0b`, Railway `c6b73d2a-1749-4c01-8a10-d6e45c428fe4` com `SUCCESS`; [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/43248019046). Migrações 041, 042 e 043 aplicadas após ensaios com rollback.

Solicitação do anexo `c164945a-f17e-445d-9e20-a916326d756b`. Continuação do EM no baseline `8ce19ad`, no mesmo repositório e com destino ao Supabase `oficina-em-mi-off` e ao [portal EM existente](https://em-web-production.up.railway.app). A unidade operacional continua sendo **Projeto + Célula**, sem criar um status ou tipo paralelo no projeto.

## Discovery e diferenças encontradas

A consulta ao [Bubble rmmi / Live](https://bubble.io/page?id=rmmi&version=live&name=rm_planejamento) foi somente de leitura. Após um timeout inicial do outline, a leitura de 11 nós específicos confirmou a entidade `custom.celula_projeto`, o Option Set `option.status_cel_proj` e os fluxos de criação/edição da página `rm_planejamento` (`cnsnM`, grupo `comJg`). Não foram executados workflows, exportações, gravações ou alterações no Bubble. A cobertura é desses nós, não uma nova auditoria de toda a aplicação.

No Live, o dropdown obrigatório de criação `comCZ` oferece os estados exceto Retornado. A ação `comCr` cria `Celula_Projeto` e grava esse status na relação. A edição `copFB`/`copGz` oferece os dez estados originais e inicia no valor da alocação atual. Nenhum dos dois fluxos altera o status global do projeto. **Aguardando coleta** e **Coletado** são extensões solicitadas para o EM, ausentes no Option Set Live observado. O default legado de visibilidade não foi aplicado como mudança colateral ao EM.

O [discovery detalhado](discovery_planejamento_status_excel_041.md) contém a tabela de evidências, IDs, opções originais e diferenças locais. O banco já possuía `rm_celulas_projeto.status`, enum, catálogo de rótulos, planejamento, RPC operacional, recibos e histórico. Faltavam o controle web de status e sua escrita por `plan_cell`. Planejamento já consultava alocações com filtros/paginação, mas não possuía exportação configurável XLSX.

| Requisito | Classificação do baseline | Evolução implementada |
| --- | --- | --- |
| Status ao alocar célula | Parcialmente implementado: campo e RPC operacional existentes | Seletor obrigatório no mesmo `CellEditor`; persistência na alocação por `plan_cell`. |
| Status em Planejar | Parcialmente implementado: leitura e editor de planejamento existentes | Valor atual, alteração com versão exata e releitura após salvar, sem alterar o projeto global. |
| Histórico do status | Parcialmente implementado: infraestrutura e campo já reconhecidos | Recibo anterior/posterior projetado pela auditoria 038, com autor/data e pares De/Para. |
| Aguardando coleta / Coletado | Não implementado no enum/opções do baseline | Extensão aditiva do mesmo enum e catálogo, preservando os dez valores e regras anteriores. |
| Espaçamento alocação/histórico | Divergente: elementos visualmente próximos | Wrapper CSS com o espaçamento de 24 px já usado nos painéis. |
| Tipo em Informações do projeto | Parcialmente implementado: relações e formatter existentes | Leitura canônica Projeto → Equipamento → Tipo, sem duplicação ou fallback global legado. |
| Excel configurável | Não implementado | Seleção de células/campos, consulta autorizada em lote e XLSX real com uma aba por célula. |

## Status do projeto naquela célula

O modelo permanece `rm_celulas_projeto.status`, do tipo `public.rm_status_cel_proj_enum`. `rm_projetos.status` e `status_pcp` são conceitos separados. A interface não envia esses campos globais quando o usuário altera o status da célula.

**Alocar célula** oferece o status inicial, com Pendente como padrão e Retornado indisponível na criação, conforme a referência Live. **Planejar**, inclusive nos consumidores de projeto, Cronograma e Fila, mostra o status atual e permite a alteração pelo editor reutilizado. Uma escolha inalterada é omitida ao editar. Não voltam os controles de vínculos de formulários que já foram centralizados no Roteiro.

| Valor canônico novo | Rótulo | Ordem no catálogo |
| --- | --- | --- |
| `aguardando_coleta` | Aguardando coleta | 11 |
| `coletado` | Coletado | 12 |

Os novos valores são oferecidos nos filtros, labels, listas tipadas, regras que usam o mesmo status e no seletor/formatador mobile. Não encerram automaticamente o projeto, não preenchem a data final, não ocultam a célula e não dispensam aprovações. As regras anteriores de Finalizado e N/A permanecem, inclusive as verificações de formulários e fotos obrigatórias.

**Planejar continua recusando replanejamento de células já Finalizadas/N/A e de projetos encerrados**, conforme o contrato anterior. Os novos estados não são terminais. Liberar especificamente uma alteração de status nessas células seria uma mudança distinta das regras de conclusão existentes e não foi inferida nesta entrega.

### Escrita comum e auditoria

O comando continua sendo `rm_web_mutate_v1(..., 'plan_cell', payload)`, com `em.planning.manage`, perfil permitido, autorização atual, SSO/MFA, versão exata e os mesmos recibos idempotentes. `changes.status` é opcional para compatibilidade com clientes anteriores; um valor presente precisa ser enum válido e não nulo.

O escritor privado comum `rm_private.apply_cell_status_v1` conserva a validação e os efeitos operacionais que já existiam. O RPC mobile mantém suas verificações de operador/contexto e chama o mesmo escritor. O planejamento web continua com sua autorização própria e também o utiliza quando há uma mudança de status. O helper não recebe EXECUTE dos papéis de aplicação e não constitui outro caminho público de escrita.

Na criação, `status_historico` começa no status escolhido, sem inventar passagem por Pendente. Nas alterações, o histórico e a outbox seguem o contrato anterior; retentar o mesmo UUID não duplica seus efeitos. O status global e os outros projetos não são alterados por essa operação. Falhas na validação de conclusão desfazem também os demais campos de planejamento, timestamps, histórico, outbox e recibo da tentativa.

A auditoria 038 já lê os registros anterior e posterior do recibo de `plan_cell` e reconhece o campo `status`. Assim, o Histórico de alterações das células mostra usuário, data/hora, projeto/célula, valor anterior e novo sem criar outra tabela de auditoria. As duas labels novas também são legíveis nesse histórico. O [contrato de status](../rm-mobile-supabase/WEB_ALLOCATION_STATUS.md) registra as regras de compatibilidade, locks, replay e testes de concorrência.

## Informações do projeto e espaçamento

O novo campo **Tipo de Equipamento** em Informações do projeto usa o equipamento do snapshot exato e o seu `tipo_equipamento_id`, consultando somente `id,nome,sigla` do cadastro correspondente com o JWT do usuário. Reutiliza `equipmentTypeLabel` para `SIGLA - NOME`, ou somente o nome disponível. Não escreve nem duplica o tipo no projeto.

Ausência de equipamento/tipo, vínculo reverso incorreto, equipamento compartilhado, snapshot de outro contexto ou cadastro ausente produz **Não informado**. Falha de consulta é apresentada como indisponibilidade, sem quebrar o restante do projeto. O tipo continua visível em projetos encerrados quando o vínculo é comprovado; a leitura não depende de permissão para editar. Não é utilizado o fallback legado de classificação global do projeto.

O wrapper `allocationActions` separa Alocar célula do Histórico por 24 px, com o editor aberto ou recolhido, seguindo o padrão dos painéis existentes. A mudança utiliza CSS reutilizável, sem novo estilo inline.

## Exportar alocações para Excel

Em **Planejamento → Exportar para Excel**, o usuário escolhe uma ou mais células e os campos desejados. O diálogo agrupa **43 campos reais** em Projeto, Equipamento e Célula/alocação; nove vêm selecionados como ponto de partida. Há busca de células, seleção das exibidas, limpeza das seleções e contagem visível. Uma célula filtrada na lista pode iniciar selecionada, mas a busca, o status e a paginação da lista não reduzem silenciosamente o arquivo.

O frontend recebe somente metadados de células e do catálogo de campos. Envia apenas `cell_ids` e `fields` para o backend, sem carregar todos os projetos para gerar Excel no navegador. Seleções vazias são recusadas; durante a geração, os controles ficam protegidos e o usuário pode cancelar/fechar. Erro de autenticação, HTML de login, conteúdo de outro formato ou resposta vazia não é tratado como um arquivo válido.

### Fonte dos dados e segregação

`rm_celulas_projeto` é a origem da seleção. Uma worksheet é gerada para cada célula solicitada; cada uma contém somente suas alocações e as colunas selecionadas. O mesmo projeto alocado em duas células selecionadas aparece legitimamente nas duas abas. Não há deduplicação por `project_id`, inclusão de célula não selecionada ou truncamento pela página da interface.

São incluídas as alocações atuais `retirada=false`, como na lista de Planejamento, inclusive as ocultas no mobile e as de projetos encerrados. Retiradas ficam fora. Célula sem alocações mantém uma aba com cabeçalho. Uma alocação cujos campos escolhidos estejam todos vazios também conserva sua linha no XLSX, sem desaparecer por uma otimização do writer.

Campos de Projeto incluem número, nome, cliente, status global/PCP, datas, gestor e escopo existentes. Equipamento oferece tipo, descrição, fabricante, modelo, série, potência, placa do motor e dados técnicos reais. Alocação oferece célula, seu status, início/prazo/fim, responsável, prioridade, visibilidade/bloqueio, motivos, horas e observação. Não foram inventados campos a partir dos exemplos do prompt.

Status e outras opções usam os rótulos cadastrados; cliente, tipo, gestor e responsável têm representação legível. O tipo e os dados técnicos exigem vínculo exato, próprio e não compartilhado de equipamento, inclusive quando a referência conflitante está em um projeto oculto por RLS. Não há fallback para o tipo global legado do projeto. IDs, UUIDs e foreign keys do snapshot servem apenas à validação interna; não são colunas oferecidas no arquivo.

### Biblioteca, workbook e formato

A geração utiliza [ExcelJS 4.4.0, licença MIT](https://github.com/exceljs/exceljs), no runtime Node. O `override` de `uuid` para 11.1.1 está restrito à dependência do ExcelJS; a auditoria de dependências de produção executada nesta rodada retornou zero vulnerabilidades. A biblioteca não exige um serviço externo de geração de arquivos.

É um XLSX real, produzido pelo writer de streaming, com commit e liberação das linhas. O cabeçalho é destacado, há primeira linha congelada, autofiltro e larguras legíveis. As worksheets normalizam caracteres proibidos, limite de 31 caracteres, nomes vazios, duplicações sem distinguir maiúsculas/minúsculas, Unicode e o nome reservado History. Somente o nome técnico da aba é normalizado; o nome da célula nos dados é preservado.

Horas previstas/realizadas são números. Datas válidas são tipadas para Excel e apresentadas no calendário de São Paulo, com formatos de data/hora apropriados. Texto, unidades e zeros à esquerda permanecem texto; valores com aparência de fórmula não se transformam em fórmulas, macros, hyperlinks ou consultas externas. O arquivo recebe `planejamento_alocacoes_YYYY-MM-DD.xlsx`, usando a data de São Paulo. Não é CSV renomeado nem um documento salvo em Storage: é download privado direto.

### Segurança e performance

A rota `POST /api/web/planning/export` exige origem igual ao host, sessão atual, MFA quando cadastrado, perfil interno e as capacidades existentes `em.portal.read`, `em.planning.read` e `em.projects.read`. O botão aplica o mesmo conjunto, mas o backend revalida tudo. Não há nova concessão na Central, leitura com chave de serviço ou aceitação de ator/credencial no payload.

A RPC `rm_web_planning_export_snapshot_v1` é **STABLE SECURITY INVOKER**. RLS governa células, alocações, projetos e os relacionamentos que fornecem valores. Uma célula selecionada indisponível ou uma alocação visível cujo projeto não esteja disponível recusa o arquivo completo, sem sucesso parcial. Dados de equipamento/tipo ocultos pela própria RLS não são recuperados por esse caminho.

A autorização interna/MFA usa um helper específico. A única outra consulta elevada é a prova opaca em lote `web_export_shared_equipment_v1`: recebe IDs de equipamentos já encontrados no contexto permitido e devolve somente o subconjunto compartilhado. Não retorna IDs, nomes ou dados dos projetos que os referenciam. Isso evita interpretar como exclusivo um equipamento compartilhado por outro projeto oculto. Os valores exportados continuam vindo dos joins como o usuário.

Um único RPC obtém o snapshot coerente. Relações e prova de compartilhamento são carregadas em lote, sem N+1 ou consulta individual por projeto. A resposta é privada, sem cache, com MIME XLSX, `attachment`, `Vary: Cookie` e `nosniff`; erros não incluem conteúdo interno ou uma attachment de workbook.

| Limite | Comportamento |
| --- | --- |
| Células | Uma a 200, sem repetições. |
| Campos | Um a 43, somente do catálogo, sem repetições. |
| Corpo da requisição | Até 16 KiB de JSON. |
| Alocações | Até 20.000, inclusive; 20.001 recusa explicitamente. |
| Snapshot | Até 20 MiB de JSON. |
| Workbook | Até 64 MiB no gerador. |

Exceder limites informa a falha e orienta reduzir a seleção; não corta linhas nem devolve um arquivo parcial. O snapshot e o ZIP permanecem limitados em memória, enquanto os objetos de linhas são liberados pelo streaming. A geração observa o cancelamento da requisição. O [contrato de exportação](../rm-mobile-supabase/WEB_PLANNING_EXPORT.md) detalha campos, autorização, formato, limites e testes.

## Banco de dados

As migrações anteriores 001–033 e 035–040 não foram editadas; o incremento 034 não teve SQL. Não foram adicionadas colunas às entidades de projeto/equipamento/alocação.

| Migração | Alteração |
| --- | --- |
| 041 — `rm_cell_collection_status_values` | Dois valores novos no enum existente, preservando os dez anteriores e sua ordem/OIDs. Deve ser confirmada antes de operações que usem os novos valores. |
| 042 — `rm_web_allocation_status` | Duas opções no catálogo existente com ordem 11/12; escritor de status compartilhado e aceitação opcional de `changes.status` no planejamento, preservando autorização, auditoria e regras operacionais. |
| 043 — `rm_web_planning_export` | RPC de leitura invoker e dois helpers, sem tabelas, seeds, mudanças de policies ou alterações nos gateways de mutação. |

Hashes das fontes congeladas para a validação local:

- 041: `68d6fc785e11c8db56b2513b380544417ac009db772c1d82d61074fda2ba46b7`.
- 042: `e600304413daac1fb7a5c1c0c4b9571659a600b441517d72fad6c2981a40b3c1`.
- 043: `54a02f0778061639ffc076cb832e69d31880ffa5010f28907977cee56051d45d`.

O ensaio e a aplicação de produção devem preservar dados, funções e permissões existentes, permitindo somente as alterações previstas e as duas opções novas. **Nesta versão do relatório esses gates ainda estão pendentes de registro.**

## Arquivos principais

- Status/planejamento: `desktop/src/components/web/editor.tsx`, políticas, labels e constantes existentes; migrações 041/042 e suas suítes funcionais, de upgrade e concorrência; formatos/opções mobile correspondentes.
- Informações e espaçamento: `desktop/src/app/(portal)/projetos/[id]/page.tsx`, `desktop/src/server/web/project-equipment-type-data.ts`, `desktop/src/components/web/project-equipment-type-model.ts`/`project-equipment-type-display.ts`, formatter existente, wrapper CSS e testes da leitura/apresentação.
- Exportação: `desktop/src/server/web/allocation-export-policy.ts`, `allocation-export-data.ts`, `allocation-export-route.ts`, `allocation-export-workbook.ts` e `desktop/src/app/api/web/planning/export/route.ts`.
- Interface: `desktop/src/components/web/allocation-export-editor.tsx`, `allocation-export-model.ts`, `allocation-export.module.css` e integração em `desktop/src/app/(portal)/planejamento/page.tsx`.
- Verificação: `desktop/tests/allocation-export.test.ts`, `allocation-export-editor.test.ts`, smokes de runtime, `rm-mobile-supabase/tests/web_planning_export.sql`/`web_planning_export_upgrade.sql` e integração no runner isolado.
- Dependências: `desktop/package.json`/lockfile, com ExcelJS e override escopado de UUID. Documentação: [discovery](discovery_planejamento_status_excel_041.md), [status](../rm-mobile-supabase/WEB_ALLOCATION_STATUS.md) e [exportação](../rm-mobile-supabase/WEB_PLANNING_EXPORT.md).

## Validação em andamento

| Verificação | Resultado registrado no rascunho |
| --- | --- |
| Testes web | 467 aprovados, incluindo o caso de alocação com todos os campos selecionados ausentes. |
| Testes mobile | 104 aprovados. |
| Contrato QR | Dois testes integrados aprovados. |
| Typecheck | Web e mobile aprovados. |
| Build | Build final Next e dois smokes de runtime/autenticação aprovados, incluindo as recusas do novo endpoint Excel. |
| PostgreSQL | Suíte completa de 42 fontes de migração e 36 arquivos funcionais aprovada em banco descartável, com upgrades e concorrência. Todas as fontes ficaram estáveis durante a execução. |
| Concorrência | Cinco novas disputas reais de status aprovadas; a suíte completa também conserva as disputas anteriores. |
| Exportação SQL | RLS/MFA/perfis, equipamento exato, compartilhamento oculto, legado sem tipo, campos/células e limites aprovados: mais de mil linhas, 20.000 inclusivas, 20.001 e payload acima de 20 MiB. |
| Interface | React/CSS com catálogo real e HTTP simulado em 1240/390 px: seleções vazias, múltiplas células/campos, busca, download, erro 403, cancelamento/Escape e ausência de overflow aprovados. |
| Lint | Não há script/configuração de ESLint independente no repositório; `git diff --check` passou. Não se declara execução de lint inexistente. |
| Dependências | Auditoria de produção da rodada sem vulnerabilidades. |
| CI / deploy | Dois jobs Node 22 aprovados no commit consumidor; Railway confirmou `SUCCESS`. QA público posterior registrado abaixo. |

Os testes de upgrade verificam linhas anteriores, OIDs/owners/ACLs, definições não relacionadas, colunas, defaults, policies, triggers, constraints e índices, além de callers/recibos aquecidos. A exportação também verifica que leitura e replay não alteram os dados da prova. Fixtures artificiais e testes destrutivos usam somente PostgreSQL descartável em loopback, nunca produção.

O APK interno **1.2.7 / código 10** foi gerado e verificado em `artifacts/em-mi-electric-brasil-internal.apk`: **68.983.372 bytes**, SHA256 `6c18c39579e69076c69a8e79f6bb8915b550f46ccce789349fb576a51e0530ac`. Mantém `br.com.mielectric.rmconnect`, ARM64/x86_64 e o certificado SHA256 `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`, com assinatura Android Debug para distribuição interna, como o instalador anterior. SDK e permissões mantidos. Exportações Android/iOS, prebuild e Gradle Release passaram; os sete assets conferidos contêm os novos status/labels, QR e somente a configuração pública autorizada do Supabase. Dez segredos locais conhecidos foram procurados, sem ocorrências.

O instalador 1.2.6 e os arquivos nativos anteriores foram conservados em backups ignorados. O build final utilizou `mobile/android` gerado existente, após os isolamentos temporários encontrarem limitações de resolução do Metro; não se declara isolamento da fonte final. **Nenhum dispositivo foi instalado, desinstalado, limpo ou alterado.** A atualização no aparelho deve ocorrer sobre a instalação existente, sem remover catálogo, respostas, arquivos ou filas offline; a homologação em aparelho real permanece uma atividade operacional.

## Instalação e verificação em produção

A 041 acrescenta valores de enum e exige commit antes do uso na 042. Foram executadas quatro fases separadas: ensaio/rollback da 041, commit da 041, ensaio/rollback da 042–043 e commit da 042–043. As fases preservaram integralmente as **84 tabelas anteriores** (76 RM/privadas e oito de Storage), comparando todas as colunas/linhas antigas. Somente as duas linhas de catálogo explicitamente previstas foram acrescentadas; não houve DML de projetos, equipamentos, respostas, alocações ou outros dados operacionais.

Também foram preservados 138 OIDs, owners e ACLs de funções, todos os índices, triggers, policies, constraints e configurações anteriores. Os dois corpos de funções estendidos e os quatro novos helpers/RPCs foram conferidos contra manifesto compilado independente, totalizando 142 funções. Os dez valores anteriores do enum conservam seus OIDs e ordem; o tipo agora possui 12 valores. O histórico antigo foi mantido, inclusive os 17 registros iniciais com `statements=[]`; as fontes armazenadas de 018 em diante e as três novas correspondem aos arquivos locais, índice e commit. SSO e os dois administradores autorizados permanecem.

O destino foi exclusivamente o Supabase `oficina-em-mi-off` e o serviço Railway EM. `SYNC_OUTBOX_ENABLED=false` e a configuração anterior de limpeza privada de anexos continuam preservadas. Nenhum grant ou papel de outro sistema foi alterado. A inclusão dos novos estados é uma extensão do EM; o Bubble Live permanece sem essas duas opções e somente para leitura, com coexistência/ponte ainda não autorizada.

Uma consulta de produção em transação somente leitura, com o papel autenticado e contexto do administrador EM, exportou em memória **383 alocações reais de três células e nove campos**. O arquivo de 30.801 bytes foi reaberto e conferido: três worksheets, todas as linhas e somente as colunas selecionadas. Nenhum workbook com esses dados foi persistido ou publicado, nenhum dado de cliente foi alterado e isso não representa um login Microsoft humano automatizado.

Após o deploy, health 200 e **116 verificações públicas de acesso** passaram: 96 recusas em 48 URLs com anônimo/cookie forjado e 20 nas APIs, incluindo o novo export. O início nativo do login conferiu origem, POST 303 e navegação até Microsoft; somente o fluxo próprio de QA foi cancelado. Não houve login humano ou CRUD artificial em produção. A inicialização do runtime e o worker anterior de limpeza foram conferidos sem mensagens de retentativa por falha.

Foram verificados 81 JavaScripts do build contra dez segredos locais conhecidos, sem ocorrências. A nova dependência não alterou as versões das dependências anteriores; o `package-lock` e o consumidor foram validados no CI Node 22. As provas ignoradas ficam em `.tmp/planning-{validation,ci,environment,deployment}-proof.json`, `planning-prod-rpc-proof.json`, `planning-public-qa.json`, `planning-public-sso-qa.json`, `planning-browser-secret-audit.json`, `allocation-export-041-043-{rehearseenum,applyenum,rehearserest,applyrest}-proof.json`, `allocation-export-envelope-local-proof.json` e `allocation-status-127-apk-proof.json`, além dos logs correspondentes.

## Pendências e limites

Os requisitos foram implementados dentro das regras de autorização e conclusão existentes. Permanecem a homologação pelos usuários e a atualização controlada dos aparelhos com o APK disponibilizado; não foi feita instalação real nesta rodada. O QA funcional de escrita usa banco descartável, sem substituir dados de clientes por fixtures.

O pedido é atendido sem sincronizar status da célula com status global, sem criar campos paralelos, sem remover opções anteriores e sem alterar a regra de visibilidade do EM para imitar o default antigo do Bubble. A ponte `SYNC_OUTBOX_ENABLED=false` deve permanecer desativada. As identidades legadas do tablet e os papéis globais de outros sistemas não são modificados.

A exportação é um retrato autorizado no momento da solicitação, sem assinatura permanente, envio automático ou persistência em Storage. Limites geram falha explícita. Dados legados inconsistentes não são reconciliados silenciosamente nem compensados por um tipo global duplicado. O gerador visual de relatórios PDF e as demais lacunas de paridade continuam no plano geral e não são declarados concluídos por este incremento.

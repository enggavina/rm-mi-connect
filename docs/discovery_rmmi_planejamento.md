# Discovery funcional — Planejamento / Células por projeto

Data: 29/10/2026. Origem: Bubble `rmmi`, versão **Live**, página `rm_planejamento` (`cnsnM`), com foco no **Group Gestao_projeto_redesign** (`comJg`) solicitado pelo usuário. Destino: portal EM existente, Supabase `oficina-em-mi-off`, sem recriar a aplicação.

Esta análise é somente leitura. Não houve execução de workflows, edição do Bubble, gravação de dados de negócio, chamada de geradores, envio de mensagens ou publicação. A configuração de um workflow foi inspecionada; isso não comprova sua execução bem-sucedida com dados reais.

## Evidência e cobertura

Foram lidos os detalhes atuais de `comJg` e seus grupos, popups e floating groups agregados, com `get_node`, `expandChildren=true` e profundidades pequenas, subdivididas pelos IDs abaixo. O primeiro pedido com profundidade 10 excedeu o tempo do conector; a leitura com profundidade 3 e subdivisão funcionou. Limitações temporárias/rate limit não foram tratadas como funcionalidade ausente.

A composição reconciliada tem **266 elementos únicos** detalhados, **50 eventos do escopo**, dos quais **48 ativos e dois explicitamente desativados**, e **107 ações dos eventos ativos** inspecionadas individualmente. Também foram inspecionados os backends ligados à ordenação e criação de fotos e suas ações, a entrada do menu, o guard de logout e as regras de privacidade dos tipos `Celula_Projeto` e `Aprovaçao_etapas`. O índice da página contém 315 eventos; essa contagem mais ampla inclui módulos comerciais e outras áreas, cuja paridade não é declarada neste documento.

Evidência bruta local ignorada pelo Git: `.tmp/discovery-planning/`. A descoberta partiu do inventário Live atual, não de uma suposição baseada no cache anterior `.tmp/bubble-review`.

| Composição atual | IDs |
| --- | --- |
| Página, entrada e seção selecionada | `cnsnM`, `colzs`, `comAK`, `comAP`, `cnsoQ.custom.section_` |
| Group principal; pesquisa; projeto; lista de células | `comJg`, `comMP`, `comMQ`, `comMc`, `comMg`, `comQK`, `comJh`, `comKQ` |
| Pesquisa e seleção de OS | `colrz`, `colsE`, `colsG`, `colsK`, `colyA` |
| Alocação e edição | `comBj`, `comCS`, `comCZ`, `cooPB`, `cooAs`, `copEL`, `copEu`, `copFB`, `copFN`, `copFG`, `copHe` |
| Ordenação, ativação e exclusão | `copJI`, `copJK`, `comKW`, `comKY`, `comKc`, `comAa` |
| Abas e fotos da alocação | `comSC`, `comLq`, `comME`, `coooz`, `comMO`, `colpQ`, `copLM`, `colqS` |
| Formulários e aprovador individual | `comKq`, `comKu`, `comLM`, `comLI`, `comLH`, `coloh`, `copNM`, `colnr`, `coloI`, `colpw` |
| Regras de etapas da alocação | `conOt`, `conOy`, `conPF`, `conPL`, `conPk`, `conPR`, `conPY`, `contX`, `conPe`, `copoF`, `coqrl`, `conRI` |
| Backends ligados diretamente | `copKS` / `ordenacao_celula_projeto`; `copMO` / `Cria_fotos` |

## Resultado principal

O Group solicitado é uma operação de **Células por projeto**, e não um gráfico Gantt: escolher OS → consultar projeto → alocar/ordenar/ativar células → selecionar alocação → gerir fotos obrigatórias, formulários e regras de aprovação daquela célula no projeto. Um cronograma com barras de datas isolado não representa essa operação.

O EM já tem peças importantes e deve reutilizá-las: editor de projeto, editor de alocação, consulta de formulários, revisão, galeria, Engenharia e decisões de etapas. Faltam a composição no contexto do projeto, a ordenação do roteiro por `indice`, exceções operacionais de fotos e etapas e a atribuição prévia de avaliador de formulário. A ordem da fila por célula, entregue na 021, usa `posicao` e tem finalidade diferente.

## Estado atual do EM e pontos de extensão

| Destino existente | Comportamento verificado no código | Limite relevante |
| --- | --- | --- |
| `desktop/src/app/(portal)/cronograma/page.tsx`, `server/web/gantt.ts` | Gantt de 42 dias, datas em São Paulo, anterior/hoje/próximo, filtros por OS/célula/status/período, navegação ao planejamento do projeto | Sem editor do roteiro por projeto e sem as abas operacionais do Group solicitado |
| `app/(portal)/planejamento/page.tsx`, `components/web/pcp-navigation.tsx` | Lista de alocações, filtros, navegação para fila/carga/recebimentos/projeto | Não substitui Células por projeto |
| `app/(portal)/projetos/[id]/page.tsx`, `components/web/editor.tsx` | Dossiê com informações, células e planejamento, formulários, galeria, etapas, documentos e histórico; `ProjectEditor` e `CellEditor` reutilizáveis | A consulta é distribuída em abas do projeto; não há contexto único da alocação para os três conjuntos |
| `server/web/data.ts`, `policy.ts`, `actions.ts`, `mutation.ts` | BFF com projeções/capacidades; `save_project`, `plan_cell`, `review_form`; validação, conflito e idempotência | `planCellSchema` aceita `indice`/`posicao`, mas não há operação de permutação completa do roteiro; não aceita status de execução |
| `server/web/pcp-*`, migração `021_rm_web_pcp_queues.sql` | Snapshot completo/versionado da fila, prioridades independentes da ordem, ordem por `posicao`, proteção de concorrência | Ordena projetos numa célula, não células num projeto; não reutilizar o comando `save_cell_queue` para a segunda finalidade |
| `server/web/engineering-*`, migração `018_rm_web_engineering_management.sql` | Modelos por tipo × célula, formulários/fotos/etapas, títulos, cópia para **novas** alocações | Modelo não é configuração operacional de um projeto já alocado; não sobrescrever instâncias existentes ao salvar o modelo |
| `server/web/stage-approval-*`, `components/web/stage-approval-*`, migração `020_rm_web_stage_approvals.sql` | Consultar e decidir Liberar ou Retornar/Aprovar, duas versões exatas, histórico específico e autorização | Decide regras existentes; não cria/edita/exclui regras operacionais do projeto |
| Migração `014_rm_web_management.sql` | `plan_cell` valida datas/bloqueio/responsável/formulários e impede remover formulário com registro; novas alocações copiam os modelos | Visibilidade atual é alterada diretamente; não faz a manutenção de `posicao` observada no toggle legado |

Os caminhos abreviados na tabela são relativos a `desktop/src/`. As migrações 001–021 já aplicadas são referência imutável; alterações futuras exigem nova migração.

## Matriz de paridade e ordem recomendada

Classificações descrevem a cobertura funcional no baseline analisado. “Parcial” significa que há componentes/contratos utilizáveis, mas o fluxo inteiro não está equivalente; “divergente” aponta diferença concreta. Capacidades mencionadas são as existentes, não uma concessão nova implícita.

| Ordem | Funcionalidade e origem | Evento/condição; leitura → escrita; dependências | Destino/arquivos existentes | Classificação | Capacidade e risco |
| --- | --- | --- | --- | --- | --- |
| 0 | Entrada Células por projeto: `colzs`, `comAK → comAP → comJg` | Menu PL003 muda `cnsoQ.section` para `gestao_projeto_redesign`; Group aparece; logout `cntAD → cntAE` envia ao index | Navegação portal, `cronograma/page.tsx`, `pcp-navigation.tsx`, `auth-policy.ts`, `sso-policy.ts` | **Parcial**: navegação existe, composição não | `em.planning.read`; alta atenção ao mapeamento PL003 e aos demais PL abaixo |
| 1 | Selecionar projeto/OS: `comMc`, `comMg`, `colrz`, `colsG`, `colsK` | `comPI → comPK` abre busca; `colsG` busca `ProjetoRM.numero` contendo texto e não vazio, ordena número; `colyA → colyF/G/K` seleciona projeto, redefine input e fecha foco; `comPP → comPU` limpa seleção se texto vazio | Reutilizar busca de projetos/BFF, dossiê e `cronograma/page.tsx` | **Ausente** no cronograma | `em.projects.read` + `em.planning.read`; médio: seleção deve usar ID, não depender da unicidade do número |
| 1 | Contexto do projeto: `comQK`, `comJh` | Exibe nome/número, descrição, chegada e status PCP; `comQK` procura número exatamente igual ao input | Dossiê e `ProjectEditor` existentes | **Parcial** | Leitura projeto; baixo para exibição; evitar consulta duplicada por número |
| 2 | Alterar status PCP: `comJt`, `comMn → comMs` | Dropdown obrigatório, todos Status PCP; PL011 desabilita; altera `ProjetoRM.status_pcp1` | `ProjectEditor`, `saveProject`, `save_project` | **Implementada** em outra jornada, **parcial** na composição pedida | `em.projects.manage`; médio: preservar encerramento, versão e auditoria existentes |
| 2 | Alocar célula: `comKk → comNc`, `comBj`, `comCm/comou` | Sem projeto mostra erro; com projeto abre floating group; célula obrigatória, status exclui Retornado; duplicidade da célula bloqueia; `comCr` cria alocação com projeto/célula/status/datas, descrição/número, `visibilidade=false`, `indice=último+1` | `CellEditor`, `planCell`, `plan_cell`, cópia da 018 | **Parcial / divergente**: EM cria pendente, copia modelo e UI inicia visível | `em.planning.manage`; alto: datas, materialização somente nova alocação, tipo legado, diferença de defaults deve ser explícita |
| 3 | Ordem das células do projeto: `comKQ`, `copJI`, `copJz` | Lista por projeto e célula não vazia ordenada `indice`; drop guarda índice alvo, altera índice da célula arrastada e agenda normalização recursiva `copKS` | `policy.ts` aceita índice; componentes de ordenação PCP reutilizáveis; precisa comando/snapshot de roteiro por projeto | **Ausente** como fluxo completo | `em.planning.manage`; alto: permutação completa, concorrência, não tocar `posicao` |
| 3 | Ativar/ocultar célula: `comKY`, `comNF → comNK/NL/NM` | PL013; ativar grava visível e `posicao=count(visíveis mesma célula)+1`; ocultar grava false e decrementa posições posteriores da mesma célula | `CellEditor`, `plan_cell`, fila 021 | **Parcial / divergente**: checkbox existe sem normalização da fila | `em.planning.manage`; alto: novo efeito atinge outros projetos e deve respeitar locks e versão da fila |
| 3 | Selecionar alocação e editar datas/status/observação: `comKW → comMu`, `copEL`, `copGn → copGz` | Seta alocação nos estados de fotos/forms/etapas e abre editor; célula fixa/desabilitada; altera início, prazo, **status** e observação; fechar `copGb → copGi` | `CellEditor`, `plan_cell`; comandos de execução mobile e decisões 020 | **Parcial / divergente**: datas/observação existem; status não é editável por `plan_cell` | `em.planning.manage`; alto: status livre do legado pode contornar aprovações; reutilizar máquina de estados, não adicionar coluna ao payload indiscriminadamente |
| 4 | Excluir alocação: `comKc → comNR`, `comAa`, `comAt → comAy/Az/BA` | PL014 abre confirmação; confirmar deleta `Celula_Projeto`, alerta sucesso e fecha; cancelar `comBF → comBK`; não há guarda no evento nem na ação de exclusão | Não existe comando web de remover alocação; considerar operação protegida em nova migração | **Ausente**; legado com inconsistência documentada | `em.planning.manage`; crítico: registros, fotos, etapas, fila e trabalho offline podem depender da alocação; bloquear remoção com uso, preservar histórico |
| 4 | Alternar conteúdo por célula: `comSC`, `comSP/comSa/conQr` | Estado `current` inicial=fotos, alterna fotos/formularios/aprovacoes e visibilidade dos grupos | Dossiê, abas existentes, componentes reutilizáveis | **Parcial** | Combinar leituras específicas; médio: negar subconjunto sem vazar dados por payload |
| 5 | Fotos previstas/obrigatórias da alocação: `comME`, `colpQ`, `copLM`, `copLr → copMJ` | Selecionar célula; PL015; catálogo por **nome textual da célula**; multisseleção sem título já atribuído; backend `copMO` cria `Fotos RM` de projeto/célula/título e adiciona à lista da alocação; itera todos os títulos | `rm_fotos`, `rm_cadastro_fotos`, editor Engenharia e schema de fotos existentes | **Ausente** operacional; modelos e galeria existentes são **parciais** | Leitura fotos/catálogo e alteração planejamento autorizada; alto: não duplicar entidade nem slot por retry; usar FK de célula/cadastro quando possível |
| 5 | Editar tag da foto: `coooz`, `coopG → coopQ` | InputChanged altera `Fotos RM.tag_text`; nenhum PL específico observado nesse input | `rm_fotos.tag`; editor de fotos operacionais a estender | **Ausente** no web | Necessita autorização de escrita explícita; médio: tag não é flag de seleção de relatório |
| 5 | Desatribuir foto: `comMO → comOw`, `colqS`; `colwl/conDw`; também `colwB/conDY` dentro de `colpQ` | PL016; só remove se `foto` vazia, remove referência e deleta slot; se capturada mostra erro e conserva registro; confirmação/cancelamento | `rm_fotos`, proteção semelhante a Engenharia, BFF de planejamento | **Ausente** operacional | Alta: preservar foto capturada, seleção de relatório e fila offline; usar transação e guarda no banco |
| 6 | Vincular/remover formulários da alocação: `comKu`, `comLZ`, `coloh`, `copNW/copNk`, `colpw` | PL017/018; multisseleção não pode intersectar lista existente; `copNY` adiciona; `colvc/colwN` removem só quando **nenhum** Registro_Formulario para projeto/célula/form; caso contrário erro | `CellEditor.forms_ids`, `planCell`, `plan_cell`, modelos publicados 019 | **Parcial**: vínculo e proteção já implementados; falta composição contextual/indicadores | `em.planning.manage` e leitura de forms; médio: versões antigas preservadas, nenhuma alteração de respostas |
| 6 | Indicadores de formulário e avaliação: `comLM` e itens de `comKu` | Busca registro por projeto/célula/form; mostra preenchido, validado/aprovado, revisão, data/autor e aprovador AprovacaoForm | Abas formulários, `getProject`, `getFormRecord`, revisão existente | **Parcial** | `em.forms.read/review`; médio: distinguir atribuição prévia de avaliador e histórico de decisões |
| 7 | Atribuir/trocar aprovador individual: `comLI → comOA`, `colnr`, `coluP/coluh` | PL019; aprovado bloqueia abertura; elegíveis são identidades vinculadas à célula; cria/atualiza AprovacaoForm de projeto×célula×form; se registro existe, também altera `avaliador`; trocar exige confirmação | Campo `rm_registros_formulario.avaliador_user_id` existe, mas atribuição antes do registro não tem equivalente confirmado | **Dependente / ausente** | Alta: definir contrato de atribuição e integridade; histórico `rm_aprovacoes_registro` não serve como atribuição prévia |
| 7 | Criar regra de etapa operacional: `conPF`, `conPk`, `conPq → conQT → conQY/conhK` | Toggle PL020 apenas exibe configuração quando não há regra; novo status exceto Retornado, destino entre células do projeto, aprovadores da origem e de retorno do destino; exige ambas listas não vazias; cria regra e adiciona na alocação; reseta inputs | `rm_aprovacoes_etapas`, Engenharia 018, consumidor/decisões 020 | **Ausente** para projetos existentes | Alta: capacidade administrativa distinta de decidir, relações válidas do projeto, pares de retorno, estado inicial nulo explícito |
| 7 | Editar regra operacional: `conPY`, `contX`, `conPe`, `copoF` | PL021; **autobinding** de status-alvo, aprovadores, destino e aprovadores de retorno; campos Retornado bloqueados; aprovs retorno ocultos para Retornado | Modelos Engenharia não alteram instâncias; nenhum editor operacional existente | **Ausente** | Alta: usar transação/versionamento; não ampliar autorizações herdadas só porque regra legada permitia autobinding |
| 7 | Vínculo e exclusão de etapa: `coqrl → coqsD/P → coqsK/U`; `conRI → conQI` | PL020 altera `bloquear_avanco_sem_aprov`; PL022 exclusão apenas status Nulo; deleta regra inversa Retornado achada por projeto/origem/destino e a própria; aplicada mostra erro | `rm_aprovacoes_etapas`, máquina de estados 020 | **Ausente** para configuração; decisões existentes **implementadas** | Alto: não apagar etapa/log aplicado; validar par inverso exato e todos os vínculos |
| 8 | Gantt existente e fila por célula | Filtros, período e datas; fila 021 ordena projetos da célula por posição; consultas e comandos já têm versões, guardas e capacidades | `gantt.ts`, cronograma atual, `pcp-*` | **Implementados**, reutilizar | Não remover para introduzir Células por projeto; risco de regressão médio |
| — | Eventos antigos de atribuição unitária | `colvp` e `colvR` possuem `workflow_disabled=true`; substituídos por multisseleção `copLr`/`copNW` | Não migrar como rota ativa | **Obsoletos no caminho inspecionado** | Nenhuma lacuna ativa atribuída a esses dois eventos |

## Fluxos completos confirmados

### Projeto e alocação

`colzs` → `comAK/comAP` → seção `gestao_projeto_redesign` → pesquisa `comPI/comPK` → `colrz/colsG` → `colyA` seleciona ProjetoRM → cabeçalho e `comKQ` passam a consultar o projeto. Limpar o input dispara `comPP/comPU` e limpa o projeto selecionado.

O botão alocar `comNc` usa condições **nas ações**: `comNe` mostra erro se não houver projeto; `comNi/comNj` só abrem `comBj` quando há projeto. Os eventos de salvar duplicado e não duplicado são separados (`comCm/comou`). A operação de criação escreve nove campos: célula, equipamento/escopo, projeto, status, visibilidade false, número, prazo, início e índice. Não copia formulários/fotos/etapas nesse evento de criação. No EM a materialização por Engenharia é uma regra já implementada e não deve ser removida inadvertidamente.

Selecionar `comKW` dispara cinco ações: seleciona a mesma alocação em `comKu`, `comME`, `conPR`, envia dados a `copEL` e o anima. O editor altera somente início, prazo, status e observação; o campo célula `copEu` está desabilitado. As ações `copHE/copHu` notificam e fecham o editor; o botão de fechamento tem o fluxo próprio `copGb/copGi`.

### Duas ordenações independentes

1. **Roteiro do projeto**: `comKQ` ordena `indice_number`; `copJz` usa `copKG`, `copKL`, `copKQ`. Backend `copKS` recebe lista de alocações daquele projeto ordenada pelo novo índice e iteração 1. `copKX` grava índice=iteração no item correspondente; `copKY` agenda o próximo enquanto ainda há itens. O resultado pretendido é sequência 1…N.
2. **Fila da célula**: `comNF` ativa/oculta e mantém `posi_ao_number` entre projetos da mesma célula. A 021 já possui snapshot/versionamento e reordenação explícita dessa fila. Não gravar `indice` na operação de fila e não gravar `posicao` para reorganizar roteiro do projeto.

O mecanismo legado primeiro faz uma escrita parcial e depois agenda normalização. Na nova arquitetura o efeito equivalente deve ocorrer atomicamente, com snapshot do conjunto completo e proteção contra nova alocação, alteração mobile ou alteração concorrente. A 021 fornece padrão reutilizável, não o mesmo comando.

### Fotos previstas e catálogo

`comLy/comOa` → `comOg/comOk` → `colpQ` com alocação selecionada → `copLM` busca `Cadastro Fotos` cujo campo `celula_text` coincide com o nome da célula → `copLr` valida interseção de títulos vazia e seleção não vazia → `copMJ` agenda `copMO`.

`copMO` recebe títulos/projeto/célula/contador/alocação. `copMW` cria `Fotos RM` com projeto, célula e o título atual; `copMb` adiciona o novo slot à lista `Celula_Fotos_Tipo_Equipamento` da alocação; `copMg` repete enquanto contador < quantidade. No caminho inspecionado não preenche explicitamente `CadastroFoto`, categoria, número ou tag na criação. Não presumir que um título textual equivale à identidade do cadastro. O EM já tem esses campos/relacionamentos e deve evitar a ambiguidade sem duplicar dados.

A notificação `copMi` é executada depois de **agendar** o backend, e não depois de comprovar a criação de todos os slots. A nova UI deve mostrar sucesso somente após confirmar a transação. Duplicidade `copMs/copMy`, seleção vazia e falha devem conservar os dados do formulário.

`coopG/coopQ` altera tag. A exclusão é protegida em dois locais: no popup de atribuição (`colwB` remove, `conDY` nega quando capturada) e no popup de confirmação (`colwl` remove, `conDw` nega). Cancelar `colwy/colxD` só fecha. Fotos já capturadas não são removidas por esse fluxo.

### Formulários e atribuição prévia de avaliador

`comLZ/comOO` → alocação em `coloh` → `copNM` lista Forms → `copNW` exige interseção vazia e seleção não vazia → `copNY` adiciona a lista → notificação/reset. Se algum selecionado já pertence à lista, `copNk/copNq` nega o lote inteiro. Os eventos unitários anteriores estão explicitamente desativados.

Remover formulário só desvincula a definição, não exclui a definição nem respostas. Tanto `colvc` no popup de atribuição quanto `colwN` na confirmação consultam Registro_Formulario por projeto+célula+form; havendo registro, `conDK/conDk` notificam o impedimento. A SQL atual do EM já preserva esse invariante.

`comLI/comOA` consulta o registro; se Aprovado, `comOC` impede abrir. Caso contrário, envia registro (pode estar vazio), formulário e alocação para `colnr`. `coloI` oferece identidades do vínculo operacional Tablet_Celula_User da célula. Sem atribuição anterior, `coluV` cria AprovacaoForm com projeto/célula/form/aprovador; `coluU` também atualiza `Registro_Formulario.avaliador` **somente se o registro existir**. Havendo atribuição, `colun` altera AprovacaoForm e `colum` altera o avaliador do registro existente. As ações de fechar/notificar e a confirmação de troca `coluz/colvK` foram inspecionadas.

**Dependência de esquema**: `rm_aprovacoes_registro` atual exige `registro_formulario_id NOT NULL` e registra histórico de decisão. Não representa a atribuição prévia do Bubble, que existe antes do primeiro preenchimento. `rm_registros_formulario.avaliador_user_id` cobre apenas a atribuição após existir registro. Verificar importação e contrato do gateway antes de escolher extensão/tabela; não criar registro de formulário fictício para suprir essa ausência.

### Regras de etapas operacionais

O toggle `conPF` não possui ação de banco. Ele controla a exibição de `conPL`; se já houver regra na lista, o toggle some e o grupo permanece visível. `conQT` exige ao menos um aprovador da origem e um do retorno; status e destino são obrigatórios nos inputs. `conQY` cria a regra com projeto, origem, destino, status de execução alvo e as duas listas. `conhK` adiciona a referência à alocação. O evento não grava explicitamente o estado de decisão Nulo; o contrato Supabase deve garantir o estado inicial, sem inferir um default da ausência de campo na metadata.

Aprovadores da origem vêm dos vínculos da célula atual; aprovadores de retorno vêm dos vínculos da célula destino selecionada. Destinos são células já alocadas no mesmo projeto. A configuração existente é gravada por autobinding nos campos citados na matriz, não por botão salvar; isso também é persistência e não deve ser ignorado por uma auditoria que conte apenas workflows de clique.

`coqrl` altera o vínculo/bloqueio por dois eventos condicionais, gravando true ou false. `conQI` só exclui quando status=Nulo: `coqAq` procura a regra inversa Retornado no mesmo projeto, `conQN` exclui a atual, e `conQO` notifica. Caso aplicada, `coqBA` mostra erro. Linhas Retornado têm os campos principais desabilitados, retorno oculto e exclusão escondida.

Foram inspecionados ainda os backends `coqsy` (`vinculo_entre_celulas` → `coqtK`, força vínculo=true) e `coquk` (`Altera_celula` → `coqur`, altera célula de uma alocação). Não há chamada direta a eles nas 107 ações ativas deste Group; não são apresentados como dependências executadas deste caminho. A criação automática de uma regra inversa não está no evento `conQT` e não deve ser inventada a partir do nome dos campos. O consumidor de decisões da 020 já trata o ciclo de retorno e precisa ser usado como referência adicional antes do editor operacional.

## Permissões: conservar sem copiar falhas

No Group, os controles consultam `Elemento.codigo` e verificam `permissoes` contendo o Current User. Esses códigos constituem informação de autorização individual relevante e não são equivalentes a um único perfil genérico de PCP.

| Código Live | Controle observado | Capacidade EM relacionada atualmente |
| --- | --- | --- |
| PL003 | Entrada Células por projeto | `em.planning.read` |
| PL011 | Status PCP do projeto | `em.projects.manage` |
| PL012 | Botão adicionar célula | `em.planning.manage` |
| PL013 | Ativação/visibilidade | `em.planning.manage` |
| PL014 | Remover célula do projeto | `em.planning.manage` |
| PL015 / PL016 | Atribuir / desatribuir foto prevista | Não há capacidade `em.photos.manage` atual; definir comando autorizado e mapeamento de ação |
| PL017 / PL018 | Atribuir / desatribuir formulário | `em.planning.manage` |
| PL019 | Atribuir aprovador de formulário | Atribuição ausente; `em.forms.review` autoriza decisão, não implica permissão administrativa de atribuir |
| PL020 / PL021 / PL022 | Habilitar/vincular, alterar, excluir regra de etapa | `em.approvals.decide` decide; `em.engineering.manage` altera modelos, nenhum deles comprova por si só o direito de alterar instância |

A estrutura `rm_elementos_permissao` e helper `rm_user_has_element_permission` já existem na migração 005; não duplicar o cadastro. O mapeamento entre a autorização individual legada e capacidades SSO precisa ser reconciliado com o discovery de autorização antes de afirmar paridade de concessões. Os dois administradores EM autorizados não se tornam administradores globais da Central. A proteção deve estar no servidor e no banco, além de esconder/desabilitar controles.

Inconsistências da origem a não reproduzir automaticamente:

- `copKS` está exposto como API, `auth_unecessary=true`, `ignore_privacy_rules=true`; a nova operação de ordem deve exigir usuário e autorização, validar o projeto e nunca aceitar lista arbitrária.
- A regra de privacidade de `Aprovaçao_etapas` permite autobinding dos campos de configuração a qualquer usuário logado, enquanto a UI testa PL021. A regra everyone expõe leitura. `Celula_Projeto` também tem leitura ampla na regra everyone. Não ampliar RLS do EM para espelhar isso.
- Nos inputs de regra há condição “status não é Nulo” com **overrides vazios**. Ela não comprova bloqueio de edição após aplicação. O botão excluir tem uma guarda efetiva. A nova regra deve preservar decisões/histórico e rejeitar mudança perigosa após uso.
- `comAy` deleta alocação sem guarda efetiva no fluxo inspecionado. Exigir checagem de referências e trabalhos offline antes de permitir remoção.
- A seleção de outro projeto `colyA` não limpa os três estados `celulaAtual` no mesmo evento. O EM deve redefinir a alocação ao trocar projeto e verificar projeto+célula em cada comando, evitando contexto antigo.
- Ativar define posição por contagem de visíveis; a fila EM atual inclui trabalhos abertos visíveis e ocultos. A normalização não pode eliminar/renumerar outros trabalhos silenciosamente sem reconciliar esse contrato.
- A tela legada mostra “Desmontar para orçar” do equipamento. O usuário já removeu isso da jornada de recebimento mobile; não restaurar a etapa/campo rejeitados ao migrar PCP.

## Sequência de implementação verificável

1. **Contrato compartilhado de autorização e snapshot**: reconciliar PL003/011–022 com RBAC existente; manter SSO, guardas/RLS, idempotência e revisões exatas. Snapshot do roteiro do projeto deve usar `indice` com IDs estáveis, conter conjunto completo e separar posição da fila. Reutilizar infraestrutura da 021 e os componentes atuais, sem duplicar gateway.
2. **Composição de Células por projeto no Cronograma**: seleção por ID, resumo do projeto, lista ordenada, seleção única da alocação, fechar/voltar e estados vazios. Reutilizar editores e mostrar o Gantt como visão adicional preservada. Cada painel recebe só os dados autorizados.
3. **Roteiro e alocação**: transação para reordenação completa; definir diferenças de defaults e status explicitamente; ligar criação/edição existente à nova composição. Tratar concorrência com fila, criação e execução mobile. Remover alocação somente com guarda concreta; manter motivos/auditoria.
4. **Exceções operacionais de fotos**: usar `rm_fotos` e `rm_cadastro_fotos`; adicionar slots, editar tag e remover somente slots sem captura. Confirmar atomicamente a inclusão do lote. Não confundir seleção para relatório (entrega independente do dossiê) com tag, título ou slot obrigatório.
5. **Formulários**: incorporar a seleção e proteção já existentes, indicadores e links da alocação ao registro correto; manter versões publicadas e respostas. Modelos futuros e exceção operacional devem permanecer separados.
6. **Atribuição de avaliador**: resolver contrato pré-registro, importar/reconciliar os vínculos reais necessários, aplicar elegibilidade por célula e bloqueio após aprovado; não inserir registros artificiais.
7. **Regras operacionais de etapas**: reutilizar os DTOs/validações da Engenharia onde forem equivalentes, com escopo projeto/alocação, sem alterar modelos; novas regras, edição antes de uso, bloqueio/vínculo e exclusão segura dos pares. Reutilizar decisões 020; confirmar ciclo completo de avanço/retorno e identidade operacional.
8. **Validação e publicação por incremento**: testes de política/BFF, integração PostgreSQL e disputa de escritores nos comandos de conjunto, cenários de UI de seleção/troca/negativa/erro/retry, typecheck/build e smokes aplicáveis. Publicar somente após checks aprovados no Railway EM, conforme autorização permanente. Não há publicação de aplicação neste discovery.

Casos essenciais de aceitação: ordenar células do projeto não muda fila da célula; ordenar fila não muda roteiro; trocar projeto limpa seleção; adicionar repetido é negado ou idempotente sem duplicação; remover formulário respondido/foto capturada/alocação usada é negado; não alterar instâncias existentes ao editar modelo; origem/destino/aprovadores devem pertencer aos vínculos corretos; leitura e mutação sem capacidade são recusadas no servidor; conflito preserva edição e retentativa usa o mesmo protocolo; registros e pendências offline permanecem intactos.

## Limites e questões ainda reais

- Atribuição individual anterior ao primeiro registro tem estrutura Bubble confirmada, mas não há equivalente completo identificado no Supabase atual. É uma dependência de implementação/mapeamento, não uma razão para inventar dados.
- Regras inversas de retorno não são criadas no evento de adição deste Group. Antes de editar instâncias, validar o ciclo junto aos consumidores mobile e 020 e ao restante do discovery de aprovação/autorização.
- As diferenças entre defaults de alocação/visibilidade do legado e o EM, status de execução livre e edição de configuração após decisão precisam ser resolvidas com regras explícitas e documentadas. Não declarar equivalência enquanto essas diferenças permanecerem.
- Este documento cobre o Group solicitado e suas dependências diretas. Não declara migração integral de `rm_planejamento`, Propostas, `rm_gestao`, `autorizacao` ou `settings_rm`; esses módulos exigem suas matrizes próprias.

## Decisão de extensão — composição do Cronograma (29/10/2026)

O incremento reutiliza a rota existente `/cronograma`: visão padrão Células por projeto para quem possui leitura de projetos e planejamento; Gantt preservado em `view=gantt`, incluindo filtros, período e paginação anteriores. URLs antigas com início/célula/status e sem projeto continuam abrindo Gantt. A seleção usa UUID do projeto e da alocação; mudar projeto remove a alocação da URL e o servidor rejeita vínculo de outro projeto.

A composição reaproveita `getProject`, `listProjects`, `CellEditor`, `editorChoices`, `Status`, `Details` e `StageApprovalTable`. As alocações são ordenadas por `indice` e ID, sem alterar `posicao`. Criação/edição mantêm as guardas existentes de perfil, capacidades, encerramento e estado da alocação. O painel reserva uma composição de controle de ordem, sem botão inativo ou CRUD fictício; a transação de reordenação será incremento separado.

As abas são independentes por capacidade. Formulários e registros são os instanciados na alocação/célula do projeto, com links para a revisão existente. Fotos previstas usam leitor próprio paginado de metadados, incluindo slots sem captura e sem transportar URLs de mídia. Etapas reutilizam o leitor/decisão existente, filtrando vínculo de alocação e preservando a compatibilidade dos vínculos legados nulos. Não são implementados neste incremento atribuição de avaliador pré-registro, CRUD operacional de fotos ou regras de etapa, exclusão de alocação ou status de execução livre.

Validações previstas: resolução da visão/URL, troca de projeto, rejeição de alocação alheia, ordem por índice estável, isolamento de slots/registros/etapas e negação de leitura sem capacidade; testes próprios e typecheck compartilhado antes da publicação pelo responsável pela entrega.

Checkpoint da composição: implementados `cronograma/page.tsx`, `gantt-schedule.tsx`, `project-schedule.tsx` e CSS próprio, `project-schedule-policy.ts`, `project-schedule-data.ts` e `project-schedule.test.ts`. A consulta do projeto usa a fábrica existente sem capacidades de fotos/documentos/histórico desnecessárias nesta composição; fotos previstas são consultadas separadamente, com DTO Zod explícito e identificação de captura sem URL. As etapas reutilizam o RPC existente com filtro de vínculo aplicado antes da paginação apresentada. Os seis testes próprios e 13 regressões de Gantt/etapas passaram; typecheck e build passaram no checkpoint anterior à integração da ordem. O reader/editor transacional de roteiro foi integrado em painel expansível, com chave projeto+versão e guardas existentes; sua migration 024 e validação integrada são coordenadas pelo responsável da entrega. Nenhum CRUD operacional ausente é representado como pronto.

## Registro de eventos inspecionados

Os 48 eventos ativos do escopo e todas as suas 107 ações foram lidos; a tabela agrupa os efeitos para tornar a trilha auditável sem tratar metadata como teste de execução.

| Área | Eventos ativos |
| --- | --- |
| Busca, seleção e contexto | `comPI`, `comPP`, `colyA`, `comMu` |
| Abas | `comSP`, `comSa`, `conQr` |
| Projeto e alocação | `comMn`, `comNc`, `comCm`, `comou`, `comCf`, `copGn`, `copGb`, `copJz`, `comNF`, `comNR`, `comAt`, `comBF` |
| Fotos | `comOa`, `comOm`, `coopG`, `comOw`, `copLr`, `copMs`, `colwB`, `conDY`, `colwl`, `conDw`, `colwy` |
| Formulários | `comOO`, `comNo`, `copNW`, `copNk`, `colvc`, `conDK`, `colwN`, `conDk`, `colwe` |
| Aprovador individual | `comOA`, `coluP`, `coluh`, `coluz`, `colvK` |
| Configuração de etapas | `conQT`, `coqsD`, `coqsP`, `conQI` |

Adicionais de entrada/guarda lidos: `comAK/comAP`, `cntAD/cntAE`. Desativados: `colvp`, `colvR`. Backends diretamente ligados e suas ações: `copKS → copKX/copKY`, `copMO → copMW/copMb/copMg`. Os campos com autobinding são persistência adicional às ações explícitas.

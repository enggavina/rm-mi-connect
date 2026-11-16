# Gantt de planejamento — contratos 047 e 049

O portal oferece Gantt geral, por célula e por projeto em `/cronograma?view=gantt`. Uma etapa representa a alocação existente de uma célula em um projeto. Não há duplicação de projetos, atividades ou identificadores mobile.

## Jornada

- O menu **Gantt e cronograma** abre a visão geral. Projeto e fila da célula têm atalhos diretos para seus respectivos Gantts.
- A escala oferece 14, 42 ou 90 dias, navegação entre períodos, Hoje, ajuste às datas, pesquisa, status e agrupamento. Etapas sem datas ou com intervalos inválidos continuam acessíveis.
- Selecionar uma etapa abre início e prazo. Arrastar a barra desloca o intervalo; as extremidades e as setas do teclado ajustam as datas. No celular, os campos e botões oferecem o mesmo planejamento.
- Alterações ficam em uma prévia, com datas anteriores/novas e motivo obrigatório. Confirmar salva o conjunto de forma transacional; uma recusa não salva parte do lote.
- A visão de projeto permite dependências término-início, com espera de 0 a 3.650 dias do calendário de trabalho. A sucessora inicia no primeiro dia de trabalho após o término da predecessora, acrescido da espera. Sem configuração, todos os dias são considerados de trabalho. Dependências entre projetos, ligações consigo mesmo e ciclos são recusados.
- **Reprogramar dependentes** propõe deslocamentos para a frente, preservando a duração. A proposta é revisada antes de salvar. Datas ausentes impedem a cascata; o vínculo pode ser registrado enquanto os prazos estão em elaboração.
- A referência do plano registra os prazos atuais do projeto. A interface compara a referência mais recente; as anteriores ficam preservadas, sem editor ou seletor de histórico nesta entrega.

## Leitura e limites

`rm_web_gantt_snapshot_v1` recebe projeto ou célula opcionais e inclusão de encerrados. A consulta de projeto inclui todo o roteiro não retirado, também as etapas finalizadas. Geral/célula mostram abertos por padrão, com opção de incluir encerrados. A filtragem por período ocorre depois do snapshot completo; não há paginação parcial de 50 alocações.

Até 2.000 alocações e 4.000 vínculos podem compor o snapshot, limitado a 10 MiB. Acima do limite de alocações, a resposta sinaliza incompletude e não fornece linhas editáveis. O usuário deve reduzir o escopo. Projetos são escolhidos por busca paginada de 25 registros. A versão do plano inclui projeto, alocações ativas, vínculos e referência, inclusive alocações fora da célula consultada.

O BFF valida formato, completude, unicidade e pertencimento dos registros; não entrega tokens ou dados de recibos. Consulta exige perfil RM interno, MFA quando aplicável e `em.portal.read`/`em.planning.read`. A visão de projeto requer também `em.projects.read`. Escrita exige perfil administrador/padrão e `em.planning.manage`, além das leituras. SSO e autorização são revalidados no servidor inclusive em replay.

## Escrita, consistência e preservação

`save_gantt_plan` passa pela fachada `rm_web_mutate_v1`. O protocolo inclui UUID, motivo, versões exatas de todos os projetos afetados, versões das alocações e somente campos de data alterados. Dependências e referência pertencem a um único projeto; registrar referência exige um envio separado, sem mudanças pendentes.

A operação bloqueia os projetos em ordem estável, confere versões e usa o escritor `plan_cell` existente para cada alteração, com recibos filhos determinísticos. A mesma transação verifica as dependências e grava o recibo externo. Em falha, datas, vínculos, referência e recibos novos são revertidos juntos. Retry conserva o UUID e o corpo original; conflito exige nova consulta. A interface protege navegação com prévia pendente ou resultado de rede desconhecido.

As datas são dias civis de São Paulo, com extremos inclusivos. Apenas campos efetivamente alterados são convertidos para meio-dia local; timestamps omitidos, incluindo precisão e fuso, são preservados. Novas datas ficam entre 1900 e 2200; datas históricas fora desse intervalo continuam consultáveis. Etapas finalizadas/não aplicáveis e projetos encerrados não recebem edição de prazos. Coletado mantém a semântica operacional existente.

As tabelas privadas `gantt_project_plans` e `gantt_baselines` não permitem escrita direta dos clientes. Referências são imutáveis. Vínculos de etapas retiradas são conservados ao substituir os vínculos ativos; restaurar a mesma alocação recupera esses vínculos. O grafo armazenado inteiro deve permanecer sem ciclos. A exclusão confirmada de projeto inclui esses metadados na mesma verificação de dependências e transação existentes.

A instalação 047 é aditiva, sem backfill ou dados de demonstração. Não altera posição de fila, ordem do roteiro, status, aprovações, respostas, arquivos ou intenções offline. Não edita migrações anteriores nem ativa a ponte Bubble.

## Limites funcionais desta entrega

Os vínculos orientam o planejamento de datas. Não representam liberação de etapas, reservas de pessoas/máquinas ou cálculo de capacidade. O calendário é diário por projeto. Turnos e horas, calendários de recursos, dependências entre projetos e nivelamento de capacidade permanecem pendentes. O caminho crítico descreve a rede de durações planejadas, sem prever disponibilidade ou execução restante.

Os outros editores e envios offline mantêm suas regras atuais. Uma alteração de datas por esses fluxos pode gerar divergência de dependência, mostrada na próxima consulta do Gantt; eles não são bloqueados por um novo vínculo de planejamento. O salvamento pelo Gantt revalida o grafo dos projetos afetados, inclusive etapas fora da célula selecionada. Para ajustar as predecessoras/sucessoras, abrir o Gantt completo do projeto.

O gráfico não calcula percentual de execução nem promete uma previsão baseada em horas realizadas. A confiabilidade desse acompanhamento depende dos apontamentos operacionais e permanece como evolução separada. Não há novo APK ou CLI nesta entrega.

## Verificação e publicação

Testes puros cobrem datas, movimentos, dependências e cascata; testes do BFF cobrem capacidades e snapshots; PostgreSQL cobre permissões, atomicidade, idempotência e preservação. O ensaio de upgrade e as disputas entre sessões complementam os testes de interface e os smokes de produção. O registro de entrega reúne os resultados efetivamente observados.

Destino exclusivo: Supabase `oficina-em-mi-off` e [portal EM](https://em-web-production.up.railway.app/cronograma?view=gantt). Reverter o consumidor não exige apagar vínculos, referências, recibos ou histórico.

## Calendários, marcos e caminho crítico — 049

No Gantt do projeto, **Calendário e marcos** configura os dias de trabalho da semana, até 366 exceções datadas (dia útil ou não útil, com identificação) e até 100 marcos personalizados. A equipe cadastra os feriados aplicáveis. Marcos podem cair em qualquer dia civil, são indicadores visuais e não viram nós de dependência. Datas do projeto também aparecem como referências, sem edição por esse painel.

Projetos sem configuração mantêm exatamente a versão e a semântica anterior de sete dias corridos. Salvar calendário preserva as datas existentes. A interface avisa quando um prazo legado cair em dia não útil. Somente um extremo efetivamente alterado precisa respeitar o calendário; o extremo omitido mantém o timestamp original. Arrastar uma barra encaixa o início em um dia de trabalho e conserva a duração em dias de trabalho. A cascata propõe ajustes para a frente e exige revisão; etapas encerradas permanecem preservadas.

A configuração é separada da prévia de datas e vínculos. É preciso salvar ou descartar uma antes de editar a outra. Revisão anterior/nova, motivo, protocolo congelado para resultado desconhecido, proteção de navegação e conflito de versão atendem ambos os fluxos. O novo escritor **save_gantt_settings** usa a fachada autenticada, as mesmas capacidades de planejamento, MFA, bloqueio estável por projeto e recibo idempotente. A tabela privada **gantt_project_settings** não permite escrita direta. Configuração salva entra na versão do plano e na exclusão confirmada do projeto. A instalação 049 deixa todos os projetos sem configuração nova.

O snapshot acrescenta **settings**, somente dos projetos retornados. O limite total continua em 10 MiB. Quando o consumidor não tem leitura de projetos, marcos são omitidos pelo BFF. O calendário continua disponível para interpretar as datas. A revalidação do salvamento de datas cobre todo o grafo ativo dos projetos afetados, inclusive fora da visão de célula. Uma falha reverte também datas e recibos filhos. Repetições já confirmadas antes da 049 continuam válidas.

A análise CPM usa o roteiro completo de um único projeto, antes dos filtros visuais. O início planejado do projeto é a âncora, ou o primeiro início de etapa quando ausente. Duração é a quantidade inclusiva de dias de trabalho entre início e prazo; esperas de vínculos entram na rede. Inícios programados não são restrições ocultas: sua diferença para as datas calculadas aparece como margem do programado. Etapas finalizadas participam pela duração planejada, com aviso de que não é previsão da execução restante. Etapas N/A ficam fora; se houver vínculo ligado a elas, o cálculo é incompleto até revisar o vínculo.

O contorno das barras destaca as etapas com folga zero na rede até seu término mais cedo. Uma opção de consulta compara as folgas ao prazo renegociado, ou contratual quando não há renegociação. Essa opção não altera os prazos e começa desmarcada. Folga negativa indica que o alvo é anterior ao término viável da rede; um alvo folgado pode deixar todas as folgas totais positivas, preservando a identificação do caminho estrutural mais longo. A tabela oferece início/término mais cedo, início/término limite, duração, folga total e margem do programado. Sem datas válidas, com ciclos ou intervalos em dias não úteis, a interface informa análise incompleta.

As referências registradas pela 047 continuam guardando somente datas de etapas; não são cópias históricas de calendários e marcos. Os editores operacionais/offline mantêm suas regras. Apontamentos reais, recursos/capacidade e CLI continuam como entregas separadas. Esta entrega não gera novo APK.

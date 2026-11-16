# Demonstração EM: aplicativo, sincronização, portal e Gantt

Preparado em 16/11/2026, por solicitação explícita de dois projetos de exemplo no ambiente EM existente. Todos os novos projetos, cliente, materiais e estados simulados estão identificados como demonstração. As identidades, permissões e os registros anteriores foram preservados.

## Projetos disponíveis

| Projeto | Cenário | Planejamento | Abrir |
| --- | --- | --- | --- |
| DEMO-EM-001 | Motor trifásico de 75 kW / 440 V; desmontagem simulada concluída; peritagem mecânica e elétrica para execução | 13/11 a 14/12/2026; 16 etapas | [Projeto](https://em-web-production.up.railway.app/projetos/06c27ff7-ba05-4945-8f90-ae66dbab388f) · [Gantt](https://em-web-production.up.railway.app/cronograma?view=gantt&scope=project&project=06c27ff7-ba05-4945-8f90-ae66dbab388f) |
| DEMO-EM-002 | Motor trifásico de 150 kW / 440 V; 11 etapas simuladas concluídas; montagem para execução | 25/10 a 25/11/2026; 16 etapas | [Projeto](https://em-web-production.up.railway.app/projetos/686a08d0-8872-4193-8672-c4ec144649ee) · [Gantt](https://em-web-production.up.railway.app/cronograma?view=gantt&scope=project&project=686a08d0-8872-4193-8672-c4ec144649ee) |

Cliente: **Oficina de Demonstracao EM**. Cada projeto tem equipamento próprio, roteiro copiado do tipo Motor AC-BT Standard, 16 etapas visíveis, início/prazo/horas previstas/responsável, 15 vínculos término-início e uma referência do plano. As posições das filas reais não foram reorganizadas. Os estados concluídos são configuração inicial simulada, sem respostas ou decisões de aprovação fabricadas.

Cada projeto recebeu duas imagens PNG ilustrativas, frontal e lateral, e uma pasta **Demonstracao e treinamento**, com ficha técnica e roteiro em PDF. As imagens estão claramente identificadas como ilustrações, sem alegação de fotografia de um equipamento real. As fotos reais devem ser capturadas no teste. As 130 posições de fotos obrigatórias por projeto foram copiadas dos modelos reais e permanecem pendentes; o roteiro curto abaixo exige apenas uma captura para demonstrar o fluxo, sem concluir todo o serviço.

## Preparação — 3 minutos

1. No portal, entrar com uma conta administradora autorizada do EM e abrir os dois links acima. Pesquisar `DEMO-EM` também localiza ambos na lista de projetos.
2. No aplicativo, manter a conta do dispositivo existente e conectar à internet para atualizar o catálogo. Usar a sincronização/carregamento normal do aplicativo; não limpar os dados locais nem reinstalar.
3. Identificar um operador que já tenha acesso à célula usada. A identidade administradora **DIGITAL**, já existente, pode acessar todas as células; usar sua palavra-chave atual. Nenhuma credencial ou concessão foi criada ou alterada nesta preparação.
4. Para DEMO-EM-001, escolher **Peritagem Elétrica** ou **Peritagem Mecânica**. Para DEMO-EM-002, escolher **Montagem**.

Resultado esperado: os projetos aparecem nas células permitidas, com cliente, equipamento e imagem frontal. Caso não apareçam, verificar conexão, atualização do catálogo e identidade/célula selecionadas.

## Teste 1 — preencher e enviar pelo aplicativo, 5 a 10 minutos

1. Abrir **DEMO-EM-001** na célula **Peritagem Elétrica**.
2. Abrir Formulários e selecionar **DEMO - Inspecao rapida mobile/web**. Os formulários técnicos originais também estão vinculados; este modelo curto evita preencher um formulário extenso durante a apresentação.
3. Expandir o primeiro subtítulo. Informar a identificação `DEMO-EM-001`, uma descrição como `Inspeção visual realizada para demonstração` e a leitura simulada `440`.
4. Expandir o segundo subtítulo. Capturar uma foto do objeto usado na demonstração. Opcionalmente acrescentar uma observação. Não usar os valores simulados como orientação para ensaiar um equipamento real.
5. Conferir as respostas e enviar. A questão de foto é obrigatória: sem ela o envio deve ser recusado pela validação.
6. Aguardar a confirmação do envio e verificar que não restaram pendências dessa operação.

Resultado esperado: registro novo, respostas e imagem registrados para o projeto/célula corretos, com a identidade de quem realizou o teste. O avaliador do modelo curto já está definido como o administrador EM `mgavina`; a decisão de revisão ocorrerá no portal.

## Teste 2 — fotos obrigatória e complementar, 3 minutos

1. No mesmo projeto/célula, entrar em **Registro de fotos** e escolher a aba de fotos obrigatórias.
2. Selecionar uma posição/título pendente da célula, capturar a foto e acrescentar um comentário de demonstração.
3. Na aba complementar, informar livremente o título `DEMO - detalhe observado`, capturar outra imagem e adicionar comentário opcional.
4. Abrir a Galeria e ampliar as imagens registradas. Conferir a distinção entre o material ilustrativo inicial e as novas capturas.

Resultado esperado: ambas as fotos aparecem no projeto depois da confirmação de sincronização. Uma nova captura obrigatória não deve substituir a imagem complementar de apoio.

## Teste 3 — conferir e revisar no portal, 5 minutos

1. Abrir DEMO-EM-001 no portal e atualizar a consulta após a confirmação do envio mobile.
2. Em Fotos, localizar e ampliar as duas capturas do teste. Conferir o título livre e o comentário.
3. Em Formulários, abrir o registro do modelo curto e conferir as respostas, a imagem e o autor. Também é possível acessar o contexto da célula no Cronograma → Roteiro e registros.
4. Como administrador/avaliador, devolver uma questão textual para correção, com justificativa. No aplicativo, sincronizar, abrir o registro retornado, corrigir a questão e reenviar. No portal, conferir a correção e o histórico antes de aprovar.
5. Em Documentos, abrir a pasta **Demonstracao e treinamento** e baixar os dois PDFs. O acesso exige sessão autorizada; não compartilhar URLs assinadas.

Resultado esperado: as respostas corrigidas pertencem ao mesmo fluxo de revisão, o histórico permanece consultável e os documentos abrem como arquivos PDF reais.

## Teste 4 — projeto em outra etapa, 3 minutos

Escolher **Montagem** no aplicativo e abrir **DEMO-EM-002**. Repetir o modelo curto usando a identificação `DEMO-EM-002`, outra descrição e uma nova foto. Conferir no portal que o envio pertence ao segundo projeto e à célula Montagem, sem misturar os registros do primeiro.

## Teste 5 — Gantt completo, 5 minutos

1. Abrir o Gantt do DEMO-EM-001. Usar a escala de 42 dias e **Todas deste escopo** para consultar as 16 etapas. Se necessário, usar Ajustar às datas.
2. Habilitar Mostrar dependências e Mostrar referência. Selecionar Peritagem Elétrica; conferir início, prazo, responsável, horas pela área de planejamento e as ligações entre etapas.
3. Adiar o prazo da etapa por dois dias. Conferir que a barra alterada é uma prévia e que a relação com a etapa seguinte pode entrar em conflito.
4. Usar **Reprogramar dependentes**, conferir as datas anteriores/novas e informar `DEMONSTRACAO - ajuste de prazo`. Confirmar o salvamento.
5. Reabrir o plano. Conferir a variação em relação à referência inicial e verificar as mesmas datas no Gantt da célula e no Gantt geral.
6. Abrir DEMO-EM-002 para comparar o projeto mais avançado. Etapas simuladas concluídas ficam em consulta. Antes de uma segunda apresentação, revisar as datas alteradas pelo primeiro teste; não executar novamente a preparação nem apagar o trabalho dos participantes.

Resultado esperado: dependentes deslocados respeitam a ordem e a duração; as três visões mostram o mesmo plano salvo; o ajuste mantém status operacionais e aprovações em seus fluxos próprios.

## Teste 6 — offline e reconexão, 5 minutos

Após carregar o catálogo e abrir o projeto online, desativar a conexão do dispositivo. Preparar um novo formulário curto e capturar uma foto. Enviar e observar a retenção local do trabalho. Reativar a conexão, aguardar a recuperação/sincronização e conferir o registro no portal. O indicador de sincronização deve refletir esse retorno com possíveis pendências.

Não trocar de identidade com trabalho pendente, apagar o armazenamento ou repetir envios com um protocolo diferente. Uma operação confirmada deve aparecer uma vez no servidor. A comparação deve usar o projeto/célula, o autor e o registro, não apenas uma contagem global.

## Verificação da preparação

Ensaio transacional com rollback e aplicação concluídos, com comparação dos registros anteriores de 13 tabelas operacionais/cadastros. Oito arquivos foram enviados somente aos caminhos novos desses dois projetos e baixados para conferir seus hashes. Leituras sob papel authenticated confirmaram os dois Gantts completos, 32 intervalos válidos, 30 dependências, duas referências, imagens frontais, quatro PDFs acessíveis por RLS, formulários vinculados e ausência de registros respondidos durante a preparação.

O roteiro de interação humana no dispositivo e a revisão no portal devem ser executados pelos participantes; a preparação não declara esses envios como realizados. Nenhum novo APK, migração ou alteração do código do produto foi necessário. Os dados de demonstração já estão no banco usado pela produção; atualizar o catálogo e a consulta do portal é suficiente.

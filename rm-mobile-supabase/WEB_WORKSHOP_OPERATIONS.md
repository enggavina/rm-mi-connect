# Consultas de projetos e planejamento por oficina

O O12 estende a autorização de leitura da 059 a seis recursos da operação. O servidor confirma a oficina em Acessos e emite uma autorização de uso único vinculada à sessão, ao recurso e aos filtros. UUIDs da URL identificam o projeto ou a célula consultada. A oficina vem do vínculo confirmado pelo servidor.

| Consulta | Escopo aplicado no banco |
| --- | --- |
| Projetos | Propriedade ativa antes de busca, contagem e paginação. Seletores de clientes e células seguem o mesmo escopo. A descrição alternativa exige vínculo do equipamento de volta ao projeto. |
| Entrada do projeto | Propriedade antes da leitura da raiz, do cliente e do catálogo de células. O portal só carrega as seções dependentes após confirmar a raiz. |
| Planejamento | Propriedade do projeto e da célula antes de busca, contagem e paginação de alocações. Detalhes de projeto exigem sua capacidade de leitura. |
| Gantt | Geral, célula e projeto usam etapas cujas duas raízes pertencem à oficina. Seletores, dependências, referência do plano e calendários seguem o escopo. Uma seleção de outra oficina recebe a mesma resposta que uma seleção inexistente. |

A migração 060 estende o emissor e o leitor da 059 e mantém seus nomes, assinaturas e permissões. Os leitores operacionais são privados. O servidor verifica as capacidades de cada projeção antes de emitir a autorização. Desde a 095, as três visões do Gantt consultam a oficina no SSO e quem tem as capacidades exigidas pode editar dentro da própria oficina.

## Ativação

A produção exige desde a 095 que cada alocação confirme a origem do projeto e da célula na mesma oficina ao encerrar a transação. A consulta antiga do Gantt deixou de ser acessível diretamente por contas autenticadas. As autorizações de gravação de datas, dependências, referências, calendário e ações preparadas de planejamento exigem o contexto atual. Um recebimento aberto por um cliente legado pode aguardar conferência de origem antes da alocação. Na ativação, todos os 182 projetos, as 29 células e as 1.495 alocações do acervo conferiram com a BMA.

Desde a 102, as sessões Microsoft usam a oficina confirmada para lista e detalhe de Projetos, Recebimentos, Planejamento, Acompanhamento da operação e gêmeo digital. O leitor legado de Recebimentos passou a negar acesso direto às contas autenticadas. A leitura inicial do projeto verifica a raiz e os seletores. As seções detalhadas e subrotas têm controles próprios. A variável `EM_WORKSHOP_OPERATION_READS` continua reservada à próxima ativação de edições de projeto e célula. A adoção geral depende da compatibilidade com os escritores antigos, do primeiro recebimento real do Android e da homologação com SSO. BRJ e BBH continuam inativas.

## Verificação

O teste `tests/web_workshop_operations.sql` exercita o emissor e o leitor em PostgreSQL descartável, com duas oficinas e registros sem classificação. Os testes web cobrem os consumidores e as recusas de identidade, contexto e paginação. O ensaio `tests/workshop_restore.sql` percorre o recebimento, a alocação e as três visões do Gantt em quatro oficinas antes e depois de restaurar a base. Testa datas, dependências, calendário, linha de base, reenvio e recusas cruzadas. Para a conferência em produção com sessão Microsoft real da BMA, use `node desktop/tests/workshop-pilot.browser.cjs .tmp/oficinas-piloto-bma-planejamento.json`.

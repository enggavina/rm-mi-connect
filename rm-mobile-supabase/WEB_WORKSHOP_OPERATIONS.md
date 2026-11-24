# Consultas de projetos e planejamento por oficina

O O12 estende a autorização de leitura da 059 a seis recursos da operação. O servidor confirma a oficina em Acessos e emite uma autorização de uso único vinculada à sessão, ao recurso e aos filtros. UUIDs da URL identificam o projeto ou a célula consultada. A oficina vem do vínculo confirmado pelo servidor.

| Consulta | Escopo aplicado no banco |
| --- | --- |
| Projetos | Propriedade ativa antes de busca, contagem e paginação. Seletores de clientes e células seguem o mesmo escopo. A descrição alternativa exige vínculo do equipamento de volta ao projeto. |
| Entrada do projeto | Propriedade antes da leitura da raiz, do cliente e do catálogo de células. O portal só carrega as seções dependentes após confirmar a raiz. |
| Planejamento | Propriedade do projeto e da célula antes de busca, contagem e paginação de alocações. Detalhes de projeto exigem sua capacidade de leitura. |
| Gantt | Geral, célula e projeto usam etapas cujas duas raízes pertencem à oficina. Seletores, dependências, referência do plano e calendários seguem o escopo. Uma seleção de outra oficina recebe a mesma resposta que uma seleção inexistente. |

A migração 060 estende o emissor e o leitor da 059 e mantém seus nomes, assinaturas e permissões. Os leitores operacionais são privados. O servidor verifica as capacidades de cada projeção antes de emitir a autorização. A edição do Gantt na modalidade com escopo aguarda a migração das gravações.

## Ativação

O portal usa os leitores operacionais quando `EM_WORKSHOP_OPERATION_READS=true` no servidor. A publicação inicial mantém a variável ausente. As criações web e mobile atuais ainda podem gerar projetos sem propriedade, inclusive recebimentos sem OS sincronizados. Ativar as leituras agora poderia ocultar esses projetos do fluxo de trabalho. A conferência de 24/11 encontrou 182 projetos e 29 células já classificados, com zero pendências de propriedade naquele instante.

A próxima etapa é registrar a origem ao gravar, tratar as pendências com evidência e homologar os novos leitores com acesso real da BMA. A autorização cruzada ainda precisa abranger os consumidores legados, inclusive arquivos e anexos, formulários da operação, filas, capacidade, apontamentos, gêmeo digital e as demais APIs. A leitura inicial do projeto valida a raiz e os seletores. A autorização das seções detalhadas e subrotas independentes continua a cargo dos fluxos anteriores. BRJ e BBH devem permanecer inativas até a homologação do isolamento completo.

## Verificação

O teste `tests/web_workshop_operations.sql` exercita o emissor e o leitor em PostgreSQL descartável, com duas oficinas e registros sem classificação. Os testes web cobrem os consumidores e as recusas de identidade, contexto e paginação. A homologação autenticada usa uma sessão real sem cadastro de dados de teste na operação.

# Histórico de projeto e células

Incremento 038. O histórico é uma projeção de leitura das evidências que os comandos já persistem. Não há uma segunda tabela de auditoria, cópia de recibos, trigger de coleta ou backfill de eventos.

## Modelo encontrado

- `rm_comentarios`: conversas da equipe, com autor, contexto e data original; sua revisão continua em `rm_private.project_comment_revisions` (032).
- `rm_private.web_mutation_receipts`: comandos web confirmados, autor, payload, resultado e, quando disponível, snapshot anterior.
- `rm_private.mobile_mutation_receipts`: comandos mobile confirmados e identidade do operador delegado. A conta do tablet não substitui esse autor.
- `rm_logs_aprovacao` e `rm_web_stage_decisions`: decisão de etapa e detalhamento da decisão web.
- `rm_aprovacoes_registro`: avaliações de formulários, incluindo registros legados.
- `rm_private.project_route_instances` (037): origem e instante da criação inicial do roteiro próprio.

O Bubble Live distingue Comentários de Histórico RM. A referência legada de células mostra registros de `Celula_Projeto` ordenados por modificação e seu `ModifiedBy`; isso não constitui prova de todos os valores anteriores. O portal usa os comprovantes transacionais existentes para apresentar diferenças efetivamente demonstráveis.

## Projeções

`public.rm_web_project_audit_v1(project_id, kind, page, topics)` retorna uma página de 25 eventos. `kind` aceita `cells` ou `operations`; `topics` restringe os assuntos operacionais antes da contagem e da paginação. A ordenação é data decrescente e ID estável como desempate. Páginas além do fim são ajustadas à última página.

| Evidência | Evento apresentado |
| --- | --- |
| Instância do roteiro 037 | Criação do roteiro, tipo de origem e quantidade de células do snapshot de origem |
| `plan_cell` | Criação/alteração da alocação e diferenças dos campos permitidos |
| `save_cell_queue` | Prioridade e posição de cada alocação alterada, filtrada pelo projeto |
| `save_project_route` | Ordem da célula no roteiro do projeto |
| `manage_cell_availability` | Visibilidade, retirada e restauração |
| Mobile `rm_update_cell_status_v1` | Novo status registrado, sem inventar o status anterior |
| `plan_cell.forms_ids` | Inclusão/remoção dos vínculos de formulários |
| `manage_operational_photos` | Inclusão, tag, retirada e restauração de fotos obrigatórias previstas |
| `set_project_photo_selection` | Seleção/desmarcação para relatório |
| Mobile captura/recebimento | Foto registrada ou grupo de fotos registrado no recebimento |
| Mobile envio/correção de formulário | Envio e correção confirmados, sem conteúdo das respostas |
| `assign_form_reviewer` | Mudança do avaliador padrão e efeitos distintos nos registros existentes |
| `rm_aprovacoes_registro` | Avaliação e justificativa preservada |
| `manage_stage_rules` | Criação, substituição, retirada e restauração da configuração |
| `rm_logs_aprovacao` | Uma ação por log; decisão web ou recibo mobile apenas enriquecem a mesma ação |

O snapshot de `assign_form_reviewer` é aninhado: o avaliador padrão anterior vem de `before_record.assignment`; os avaliadores anteriores de cada registro vêm de `before_record.records`. Uma reaplicação pode alterar registros sem mudar o padrão, por isso os efeitos usam entidades separadas. Ausência de uma designação anterior não é interpretada como prova do avaliador que existia em registros legados.

O mesmo recibo de alocação pode ser consultado no histórico da célula e no histórico operacional de vínculos de formulários. Isso não gera outro registro no banco.

## Segurança e compatibilidade

- A RPC exige conta RM interna ativa (`administrador`, `padr_o` ou `auditor`) e MFA quando já configurado. Ela não concede leitura privada ao perfil de tablet/mobile.
- O serviço web também exige `em.portal.read`, `em.projects.read` e `em.history.read`; células exigem `em.planning.read`. Fotos, formulários e aprovações são filtrados pelas permissões de leitura correspondentes.
- Funções auxiliares e recibos continuam inacessíveis diretamente às contas autenticadas. A RPC retorna somente a lista explícita de campos operacionais.
- IDs públicos de eventos são hashes estáveis; protocolos privados dos recibos não são publicados.
- Não são retornados URLs de fotos, conteúdo de respostas, tokens, Auth IDs, corpos completos de payloads ou metadados de sincronização.
- A consulta de uma fila com vários projetos filtra cada item pelo projeto e pela alocação correspondente. Não retorna o snapshot inteiro da fila.
- Não há alteração de filas offline, UUIDs, identidade do operador, recibos, comentários, regras, fotos ou respostas existentes.

## Limites da evidência

Eventos anteriores sem recibo ou journal correspondente não são reconstruídos a partir do estado atual. Um valor anterior ausente é identificado como sem evidência. Autor desconhecido permanece desconhecido. Nomes de usuários, células e formulários exibidos como auxílio são os cadastros atuais; IDs nos comprovantes permanecem preservados.

Uma avaliação histórica sem prova do canal aparece como “Registro preservado”. O instante de um comando mobile é o instante de confirmação no banco, não uma estimativa do momento em que o operador trabalhou offline. Rascunhos ainda somente no dispositivo não entram neste histórico do servidor.

## Migração e validação

038 adiciona três funções (`project_audit_changes_v1`, `project_audit_events_v1` privadas e `rm_web_project_audit_v1` pública) e três índices de consulta nos recibos privados. Não adiciona colunas, relacionamentos ou constraints e não altera funções já existentes.

Os testes SQL verificam diffs reais de planejamento, fila com dois projetos, seleção de fotos, replay, identidade delegada, separação de comentários, ausência de URLs/respostas, decisão sem duplicação, atribuição real de avaliador e paginação. A suíte de upgrade compara todas as linhas preservadas e as definições/ACLs de funções, políticas, triggers, constraints e catálogo das tabelas, além de repetir um recibo já confirmado antes da migração.

Os testes do serviço web verificam permissões, assuntos permitidos, escopo do projeto, forma dos DTOs, timestamps e erros genéricos. A interface possui estados de indisponibilidade, autor ausente e ausência de evidência anterior; a validação local de navegador utiliza dados sintéticos e não realiza login nem gravações externas.

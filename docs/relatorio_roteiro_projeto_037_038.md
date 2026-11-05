# Roteiro independente, histórico e fila do projeto

Solicitação do anexo `541c8159-217f-4325-8e3a-3d123ad27859`, entregue em 05/11/2026 no [portal EM](https://em-web-production.up.railway.app), com o mesmo Supabase `oficina-em-mi-off`. Consumidor **`501137b32d7e9ed79f4f7e7c5dae11a3b823cef0`**, Railway **`d1ff5dc5-f3cd-490f-97a4-ed0659b6140d`** com `SUCCESS` e [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/42098449477).

## Discovery e modelo final

O [discovery no código e no Bubble Live](discovery_roteiro_projeto_037.md) classificou o cadastro conjunto como existente, a cópia por célula como parcial e a classificação do tipo, as abas de comentários/histórico e a edição na fila como divergentes ou incompletas. Bubble foi somente consultado; não houve alteração do aplicativo original.

O vínculo canônico é **Projeto ↔ Equipamento → Tipo de Equipamento**. O tipo do equipamento é um UUID com FK. A coluna direta de tipo no projeto já existia e permanece para compatibilidade; novas classificações não são duplicadas nela.

O modelo continua em `rm_celula_tipos_equipamento` e seus vínculos, fotos e regras. O roteiro do projeto usa `rm_celulas_projeto`, com fotos e regras próprias. A ordem `indice` do roteiro é independente da posição `posicao` na fila da célula.

## Cadastro, cópia e independência

A operação existente de cadastro conjunto foi estendida. Projeto, equipamento, tipo, cópias e recibos são persistidos em uma transação; erros desfazem o conjunto. Novas criações web sem tipo não são aceitas. Replays comprovados e atualizações compatíveis dos projetos anteriores continuam atendidos; os RPCs de recebimento mobile não foram substituídos.

A cópia inclui:

- Alocações por célula, visibilidade, vínculos de formulários e sequência própria.
- Configuração das fotos: título, categoria, etapa, tag, número, descrição e demais campos existentes; novos IDs por projeto/alocação.
- Regras de aprovação: origem, destino, status-alvo, bloqueio, aprovador individual e listas de origem/retorno; novos IDs e decisões ainda não executadas.

Formulários conservam referências às definições e versões do catálogo; a lista de vínculos é copiada para cada alocação. Não são clonadas respostas, arquivos já capturados, seleções de relatório ou decisões anteriores.

Uma consulta captura o modelo completo em um snapshot consistente. O marcador privado e a chave única por projeto impedem reaplicação, inclusive para um modelo vazio. Mudar o modelo não reconfigura um projeto existente; acrescentar uma célula depois da inicialização usa configuração própria do projeto. As guardas também impedem trocar tipo ou equipamento de uma instância já inicializada e apontar outro projeto para esse equipamento.

Projetos legados com trabalho existente mantêm seu roteiro. Um projeto sem equipamento, mas com alocações, continua aceitando edição apenas cadastral; não é completado silenciosamente com outro vínculo. A correção desse vínculo exige reconciliação explícita.

## Página do projeto e planejamento

| Área | Resultado |
| --- | --- |
| Roteiro | Sequência persistida do projeto, com consulta de formulários, fotos, origem/destino e aprovadores, reutilizando os componentes operacionais. |
| Células e projetos | Gestão existente das alocações e histórico de diferenças por célula. |
| Comentários | Comunicação da equipe, com autores, datas, conteúdo, vínculos, filtros e revisões preservados. |
| Histórico | Ações operacionais de fotos, formulários e aprovações, separadas dos comentários. |
| Fila da célula | Seleção pelo ID exato de `celula_projeto` e edição de datas, responsável, horas previstas, prioridade, bloqueio, motivos, observação e formulários na própria alocação. |

Status, fim real e horas realizadas continuam sujeitos aos fluxos de execução e aprovação existentes. Abrir a edição de uma alocação suspende a edição da ordem geral da fila até fechar esse contexto.

## Auditoria e autorização

O histórico consulta os recibos e registros de decisão já persistidos; não cria outro sistema de coleta. Mostra autor, instante, célula, campos e valores anterior/novo quando comprovados. Ausência de evidência anterior ou autoria é indicada, sem reconstrução a partir do estado atual. Ações mobile usam o operador delegado e o instante de confirmação no banco.

As permissões atuais de projetos, planejamento, fotos, formulários, aprovações e histórico são verificadas nos serviços. Escritas mantêm o gateway SSO, MFA, perfil operacional, versões exatas e protocolo idempotente. URLs de mídia, respostas e recibos privados completos não entram no DTO do histórico.

## Banco e arquivos principais

- **037:** tabela privada `rm_private.project_route_instances`, com sete colunas, PK por projeto, equipamento único, quatro FKs restritivas e check do snapshot; dois índices de unicidade e dois triggers novos de proteção de vínculo. Adapta os comandos e snapshots existentes. Nenhuma coluna nova nas tabelas de negócio.
- **038:** três funções de projeção e três índices de consulta nos recibos privados; nenhuma nova escrita operacional ou tabela de auditoria.
- Migrações aplicadas anteriores permanecem imutáveis; não há backfill de roteiros ou eventos antigos.

Os principais arquivos são `components/web/editor.tsx`, `project-route-editor.tsx`, `project-tabs.ts`, `project-audit-panel.tsx`, `project-equipment-type-model.ts`, `queue-allocation-model.ts`, as páginas de projeto/cronograma/fila, os serviços `project-audit-data.ts`, `project-equipment-data.ts` e `project-route-data.ts`, as migrações 037/038 e as suítes correspondentes em `rm-mobile-supabase/tests`.

Contratos detalhados: [roteiro e equipamento](../rm-mobile-supabase/WEB_PROJECT_ROUTE_INSTANCES.md) e [histórico](../rm-mobile-supabase/WEB_PROJECT_AUDIT.md).

## Validação e publicação

**422 testes web e 103 mobile aprovados**, além de tipos, build web e smokes de runtime/SSO. O CI também aprovou o contrato integrado de QR e a compatibilidade de dependências do Expo. O repositório não possui script/configuração de lint independente; a validação de compilação e tipos não é uma execução de ESLint.

O PostgreSQL isolado executou 66 scripts: bootstrap, 37 migrações e 28 suítes, com upgrades que aquecem chamadas anteriores, permits SSO e recibos mobile. As cinco disputas reais novas cobrem reenvio simultâneo, duas inicializações, mudança do modelo, referência inversa concorrente e um escritor externo que já segura a linha do projeto. Os hashes das fontes permaneceram iguais durante a execução final.

QA em Chromium verificou a seleção relacional, campo obrigatório, edição isolada, vínculo legado ausente com trabalho existente, retentativa congelada, abas, contexto exato da fila, motivo de atraso e apresentação do histórico. As capturas com CSS real foram conferidas em desktop e 375/390 px; as ações desse ensaio usaram dados locais simulados. O build local de referência foi `z3M6wz5143_Gn4L-SnXKd`; 79 JavaScripts do navegador foram confrontados com dez segredos locais conhecidos, sem ocorrências.

037 e 038 foram aplicadas em uma transação, após ensaio com rollback. Ambos confrontaram os estados anteriores e preservaram integralmente 74 tabelas RM/privadas e duas de Storage, 76 estruturas/ACLs/RLS, 105 OIDs/proprietários/ACLs de funções, 46 políticas, 425 constraints, 756 triggers e 237 índices anteriores. As 113 funções finais foram verificadas contra o manifesto local, preservando as concessões de produção dos OIDs existentes. O marcador novo ficou vazio; não houve backfill de roteiros ou alteração das identidades, respostas, fotos, comentários e recibos anteriores. SSO e os dois administradores do EM foram mantidos; a ponte Bubble continua desativada.

As fontes aplicadas têm SHA256:

- 037: `2b2a13efb6bf92f494541722153b2c8cc6b1ec080c9dd2d3343a2396634e7bfc`.
- 038: `25f1297b1e238b473f13df732cc5ec138438385a377c4efa5708cd1196497491`.

Depois da publicação, o health respondeu 200; 82 acessos a 41 caminhos e 16 verificações de API recusaram acessos sem sessão ou com cookie forjado. O POST nativo SSO chegou à Microsoft, sem login humano. Doze DTOs foram validados em três projetos reais, em transação somente leitura sob o papel autenticado: roteiros com 16, 19 e 17 células e 78 eventos operacionais existentes ao todo. Essa amostragem verifica consultas reais e seus contratos; não representa execução humana de todos os fluxos nem CRUD artificial em produção.

## Pendências e limites

A leitura do catálogo real encontrou **sete regras em quatro tipos** cujo destino não pertence ao roteiro ativo. Os cadastros foram preservados. A criação com esses modelos é recusada atomicamente, com orientação para revisar células e destinos na Engenharia; ativar células por suposição alteraria o modelo de trabalho.

| Tipo encontrado | Regras que exigem revisão |
| --- | --- |
| Motor elétrico de média tensão corrente alternada | Desmontagem → Peritagem Mecânica e Peritagem Elétrica (duas). |
| Motor elétrico de média tensão corrente contínua | Desmontagem → Peritagem Mecânica e Peritagem Elétrica (duas). |
| TIPO PARA TESTE | Peritagem Elétrica e Peritagem Mecânica → Double-check Peritagem (duas). |
| MOTOR FAST - AC-BT - STANDARD | Testes Finais → Relatórios De Reparo (uma). |

Eventos antigos sem comprovante detalhado não ganham histórico fictício. Nomes auxiliares são os cadastros atuais, não snapshots históricos dos nomes. Não foi executado CRUD artificial em produção nem homologação humana de todos os fluxos. A busca web por descrição armazenada somente no equipamento e as demais funcionalidades fora deste anexo continuam no plano de paridade.

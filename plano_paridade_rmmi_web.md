# Revisão de paridade RMMI → EM e plano de implementação

Revisão: 29/10/2026. Referência funcional: aplicativo Bubble `rmmi`, versão **Live**, consultado somente para leitura. Destino: este repositório EM, Supabase `oficina-em-mi-off` e portal Railway existente. Baseline local: `bf41b04`, migrações 001–016, SSO Microsoft validado pelo titular.

## Diagnóstico

A recriação ainda não tem paridade com o conjunto do RMMI. O portal possui seis áreas navegáveis, mas somente três comandos transacionais: salvar projeto, planejar célula e revisar formulário. Muitos dados foram importados e já podem ser consultados, porém seus fluxos de gestão não foram implementados. A existência de uma tabela SQL não comprova que seu módulo esteja pronto.

Os três documentos anteriores focam sobretudo o desacoplamento do mobile. Foram usados como referência, confrontados com as decisões posteriores do usuário e com metadata Live atual. Não se deve restaurar o recebimento antigo de sete etapas, a seleção automática de célula, o botão Finalizar Ciclo ou a mistura entre galeria e captura: esses comportamentos foram alterados deliberadamente pelo usuário.

## Evidências e limites da revisão

Foram revisados o inventário de **27 páginas web, três views nativas e nove reutilizáveis**, as entradas de navegação das páginas principais, os índices de eventos/ações e ações específicas dos módulos abaixo. A revisão inclui código desktop/mobile, migrações e os três documentos originais. A leitura de metadata comprova configuração e vínculos; não equivale à execução de todos os fluxos do legado. Não foram gravados dados no Bubble, gerados PDFs ou enviados emails.

| Área de origem Live | IDs principais | Evidência funcional |
| --- | --- | --- |
| Entrada e painel | `index/bTGYf`, `painel/cmpUO`, `login/coaAC`, `check_desktop/coaDb`, `reset_pw/AAL` | Painel encaminha para PCP, engenharia, configurações e propostas. Login web do EM foi substituído pelo SSO aprovado. |
| PCP | `rm_planejamento/cnsnM` | Alocação/alteração de células, atribuição de formulários, fotos/aprovadores, requisições, aprovações e projetos. Entradas do dossiê: `cntEq`, `colmi`, `comXH`. |
| Engenharia | `rm_gestao/coQKn0` | 187 eventos. Criar/editar células `coQgM0/coQjo0`; tipos `coaaf/coabu`; vínculos célula-tipo `coaXw`; modelos/perguntas/itens `coTmR/coTne/coTpX`; ordenação e títulos de fotos. |
| Configurações RM | `settings_rm/cnwZQ` | 212 eventos. Clientes `cnxIQ/cnxCI`, contatos `cnxGM/cnxGo`, usuários, acesso operador-célula, vendedores, materiais e precificação. |
| Dossiê | `project_rm/cnpGY`, `projeto/coiiy` | Geração individual `cohaC/cojAs`; compilação `cohfe0/cojDU`; anexos `copWo/copZM/copYW`; comentário `coqwp/coqww`; seleção de foto `cojAb/cojAc`; QR `cojvC0`. |
| Comercial | `proposta/coczM`, `projetos/cnnrX`, `rmclientselect/cnqcX` | Proposta firme/estimada, versões, PT/EN, arquivo, requisições, precificação e materiais. Precificação `coeVQ/coeVp`; materiais `coecH/coebp`. |
| Laboratório | `formulario/coAOy0` | Salvamentos reais de desmontagem `coIVI`, teste final `coIVW` e inicial `coIWE`. Entrada na navegação atual ainda não demonstrada. |
| Operação mobile | `rm_mobile/cnqvm`, `identify/coZum`, `check_mobile/cnyVs0`, `projeto_mobile/cokxq` | `rm_mobile`: 181 eventos/462 ações. Prioridade `conAq/conAw/conBB/conBG`; painel da célula `coRkn`; recebimentos `cnqzt/coedh0`; consulta protegida por QR. |
| Complementares | `settings/cnVvq0`, `autorizacao/cnCcs`, `miit/coTXK`, `tutoriais/cnyIe0`, `gestao_gantt/cooGA`, `visualizar-documento/copdm` | Administração compartilhada, autorização de elementos, suporte, tutoriais e integração externa. Separar capacidades EM de funções compartilhadas/NR-12. |
| Artefatos sem paridade obrigatória demonstrada | `rmtemplate/cnqdZ`, `testando/cnXxu`, `404/AAU`; views `mobile_rm/coXpw`, `update_app/coZgK`, `reset_password/cogWW` | `rmtemplate` ainda tem workflows, inclusive criação vazia; não classificá-lo como produto ativo só pelo nome. `mobile_rm` tem zero workflows; não é a operação mobile real. |

Os módulos NR-12 são outro produto e não integram automaticamente este plano EM. Não foi identificado um módulo financeiro completo: nota fiscal, valores/condições de proposta e status para faturamento não comprovam contas a pagar/receber ou conciliação.

Fluxos explicitamente desativados no Bubble, como relatório fotográfico `project_rm/cohYq` e pipelines antigos `coXYn/coXku/coizS/coizg`, não serão apresentados como funcionalidades Live ativas a copiar. Geração individual e compilação têm outros fluxos ativos e continuam sendo lacunas reais.

## Matriz de lacunas

| Módulo | Existente no EM | Trabalho restante |
| --- | --- | --- |
| Cadastros | Consulta de clientes, células, tipos, equipe e modelos | Criar/editar/excluir com proteção de referências; contatos, imagens, equipes, usuários e permissões operacionais com regras próprias. |
| Engenharia | Tabelas e materialização de modelos na nova alocação | Matriz tipo × célula, formulários, fotos obrigatórias, títulos, aprovadores e configuração do roteiro. |
| Modelos de formulário | Consulta dos modelos e revisão dos registros preenchidos | Construtor de subtítulos/perguntas/itens, tipos, obrigatoriedade, ordem, cópia, publicação/versionamento. Proteger registros enviados e rascunhos offline. |
| PCP | Alocação, prazo, responsável, bloqueio, visibilidade, formulários, cronograma | Prioridades/lotes, capacidade, dashboards, fila de recebimentos/requisições, atribuição e decisão de aprovações de etapas no web, atrasos e encerramento completo. |
| Dossiê | Consulta de dados, fotos, registros, comentários e documentos; download privado | Edição técnica do equipamento, novos comentários, metadados/upload de anexos, seleção de fotos para relatório, QR e histórico de decisões completo. |
| Relatórios | Leitura dos PDFs existentes | Templates, geração individual/técnica/fotográfica, compilação ordenada, execução durável, resultado/falha e auditoria. As APIs atuais de geração/compilação retornam 501. |
| Comercial | Algumas tabelas SQL, sem módulo web | Reconciliar contrato real, importar dados, precificação, materiais, propostas firme/estimada, versões, aprovação, PT/EN, PDFs e indicadores. |
| Laboratório | Tabelas e grupos de medições em JSON | Relacionamento explícito com projeto/equipamento; desmontagem, ensaios inicial/final, unidades, validação técnica, revisão e laudos. |
| Mobile complementar | Jornada principal/offline, fotos, formulários e etapas | Recebimentos autorizados sem alocação, prioridade/painel de célula, QR integrado, política MFA/tablet e verificar incidência de fotos armazenadas somente em listas de arquivos. |
| Coexistência | Importação histórica e infraestrutura da ponte | Resolver contratos ainda pendentes, importação transacional/concorrência, autoridade dos números e deduplicação externa antes de ativar o worker. Não ativar por consequência deste plano. |

## Sequência de implementação

| Pacote | Prioridade / dependências | Entrega e critérios de aceite |
| --- | --- | --- |
| **1A — dados cadastrais básicos** | **Primeiro incremento iniciado nesta solicitação.** | Criar/editar clientes, células e tipos; exclusão somente sem referências; validação no servidor, autoria, idempotência, versão otimista e capacidade `em.catalogs.manage`. Auditor continua somente leitura. Renomear célula preserva ou protege os vínculos legados de títulos por nome. Imagens e contatos ficam no pacote seguinte, sem prometer CRUD completo desses campos. |
| 1B — cadastros e engenharia | Após 1A | Contatos, títulos de foto, matriz tipo/célula/formulário/foto/aprovador e roteiros. Não alterar retroativamente alocações em execução. Gerir usuários e permissões fora de um CRUD genérico; Central continua autoridade do acesso web. |
| 2 — construtor de formulários | Após engenharia | Editor de blocos/perguntas/itens e prévia; tipos/unidades/opções; ordem fracionária preservada; cópia e versão publicada. Registros antigos não mudam quando um modelo evolui; modelos usados não podem perder perguntas por exclusão destrutiva. |
| 3 — PCP e aprovações | Aproveita roteiro/modelos e estados atuais | Fila de recebimentos, prioridades e capacidade; fila/decisão de etapas com autorização do aprovador e exclusividade Liberar versus Retornar/Aprovar; histórico; bloqueios e encerramento validados por formulários/fotos obrigatórias. Web e mobile observam a mesma transação. |
| 4 — dossiê operacional | Pode avançar após 1A | Equipamento técnico, comentários e anexos privados, seleção/legenda de fotos, QR autenticado e histórico completo. Downloads exigem permissão atual; uploads possuem limites e acesso privado. |
| 5 — relatórios | Após validar templates/contratos de geração | Gerar um registro; depois técnico/fotográfico e compilação. Job persistido com estados, idempotência, recuperação e falha explícita; arquivo gerado e autorizado no projeto. Não exibir sucesso enquanto houver 501 ou arquivo ausente. |
| 6 — comercial | Exige reconciliação do contrato real e carga própria | Precificação/material antes de proposta; valores e revisão auditados; propostas PT/EN e aprovação/PDF conforme regras verificadas. Não inventar espanhol ou cálculos a partir de colunas aproximadas. |
| 7 — laboratório | Exige revisão técnica e vínculo relacional | Captura dos ensaios e desmontagem ligada ao projeto correto; contrato tipado para medições/unidades e critérios de revisão; amostras reais autorizadas comparadas antes de liberar os laudos. |
| 8 — complementos mobile/cliente | Priorização pelo impacto operacional | Recebimentos, dashboard/prioridade e QR; política MFA de tablet; consulta de cliente com escopo próprio, sem herdar o perfil interno. Medir fotos em lista antes de decidir migração/renderização. |
| 9 — coexistência e corte | Depois dos contratos e homologação | Outbox/importador transacional, autoridade de numeração, reconciliação, deduplicação, observabilidade e plano de reversão. Ativação do worker é uma entrega explícita. |

Os pacotes são dependências e critérios de conclusão, não uma promessa de duração sem estimativa. Cada incremento deve conter interface, regras, persistência, autorização e teste do fluxo completo.

## Regras transversais da execução

- Bubble será fonte de consulta nesta revisão. O desenvolvimento ocorre no EM; nenhuma alteração do Bubble é necessária para o pacote 1A.
- Migrações novas e aditivas; não editar 001–016 já aplicadas. Novas mutações mantêm o envelope web e a permissão SSO de uso único, com UUID, conteúdo e sessão vinculados. Nenhum JWT administrativo vai ao navegador.
- Registrar a nova capacidade na Central separadamente da concessão. Atualizar primeiro o contrato EM que aceita a capacidade; depois conceder somente ao administrador autorizado. `softdev05` não recebe gestão de cadastros.
- Não apagar cadastro referenciado por projeto, modelo, usuário, foto ou outro histórico. Exclusão não pode causar cascatas silenciosas ou invalidar o offline. Não limpar dados reais para testar.
- Comercial precisa corrigir a divergência entre os campos Live de precificação (serviço, polos, motor, área, valor e potência) e o modelo aproximado da 005. Laboratório precisa resolver os vínculos por número textual e a desmontagem sem projeto explícito na ação legada.
- Validar PostgreSQL isolado, tipos/testes/build, runtime sem credenciais, negações de acesso e concorrência. Confirmar a publicação e registrar separadamente validação automatizada e teste feito pelo titular.

## Arquivos de referência do destino

`desktop/src/server/web/actions.ts`, `data.ts`, `sso-policy.ts`, `sso-bridge.ts`; `desktop/src/app/(portal)`; `rm-mobile-supabase/migrations/002_rm_core_tables.sql`, `005_rm_commercial_proposals_and_legacy_forms.sql`, `011_rm_project_operations.sql`, `014_rm_web_management.sql`, `016_rm_web_sso_bridge.sql`; `mobile/src/domain/journey.ts`, `gallery.ts`, `mobile/src/core/service.ts`.

Os três documentos de entrada permanecem como histórico: `analise_rmmi_rm_mobile.md`, `pacote_recriacao_completa_rmmi.md`, `plano_migracao_supabase_rm_mobile.md`. Este plano registra a diferença entre esse baseline e a operação Live verificada agora.

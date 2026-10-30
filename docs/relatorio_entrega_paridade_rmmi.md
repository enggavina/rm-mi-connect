# Relatório de execução — revisão de paridade RMMI

Revisão iniciada em 29/10/2026; atualização de entrega em 30/10/2026. Complemento ao [plano de execução](plano_execucao_paridade_rmmi.md) e ao [plano geral](../plano_paridade_rmmi_web.md). A recriação continua no mesmo repositório, no Supabase `oficina-em-mi-off` e no Railway EM.

## Situação

**Último incremento publicado em [EM web](https://em-web-production.up.railway.app): regras operacionais de etapas, em 30/10/2026.** Consumidor **`bdf182671fd2188331827eb38f973bad0d70fd82`**, Railway **`6a67b5a4-de4e-49a2-ba28-926f13b7fed4`** com `SUCCESS`; migração **027 aplicada** após ensaio com rollback. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41062212110). A paridade global não está concluída; 026 e as entregas anteriores permanecem nas seções históricas.

## Incremento 027 publicado: regras operacionais de etapas

- No Cronograma → projeto → célula → Etapas, configuração recolhida ao abrir e tabela de decisões preservada. Criação de regra forward com destino alocado, status-alvo e aprovadores por Identidade ativa nas células corretas. Correção, inclusive do vínculo/bloqueio, cria UUID novo e retira a versão anterior sem alterar sua configuração.
- Retirada/restauração conserva IDs e linhagem. Regra usada, reaberta com evidências, retorno gerado ou histórico ambíguo permanece consultivo; restauração não concorre com sucessora ativa nem reabre destino incompatível. Não apaga inversas pelo primeiro item, decisões ou logs. Nenhum backfill dos 875 vínculos diretos legados.
- `manage_stage_rules` usa planejamento autorizado, SSO/MFA, confirmação, versões/hash e recibo exato; decidir continua no escopo próprio. Journal privado registra configuração e uso sem inserir dados antigos na instalação. Consumidores web/mobile e predicados de avanço, bloqueio, retorno, visibilidade e conclusão ignoram regras inativas. Pull mantém tombstones e fila offline preserva autor/UUID/payload/recibo. [Contrato](../rm-mobile-supabase/WEB_STAGE_RULES.md) e [discovery](discovery_rmmi_regras_etapas.md).
- Consumidor **`bdf182671fd2188331827eb38f973bad0d70fd82`**; **262 testes desktop, 87 mobile, 16 suítes PostgreSQL, 20 disputas reais novas, tipos, build e dois smokes aprovados**. Os **21 cenários de navegador** usaram build `j1nTKm9Lc-tWg_izGKCrf`, HTTP/autenticação simulados e DOM real; zero erros de página/origens externas, com capturas desktop/390 px inspecionadas. Não equivale a login Microsoft humano ou CRUD artificial em produção. Auditoria dos 70 JavaScripts sem os dez segredos locais conhecidos. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41062212110).
- Ensaio remoto com rollback preservou **68 snapshots integrais**, 102 usuários, 945 etapas, outbox 4, quatro recibos web, 486 seleções, 57 tabelas RM com RLS e SSO ativo; journal novo vazio. SHA256 final da 027: `09a6e89f3795fb8bd3f15cd65c984297f1e4ad19a5cb095104e2271bb6d734db` (LF; conteúdo SQL preservado). Aplicação definitiva, pós-aplicação e publicação Railway aprovados.
- APK **1.2.3 / versionCode 6**, 68.974.460 bytes, SHA256 `586e453ad2432de94350f9a9d3eadd72c824a9079926b3a9ca8770697dd898bf`, mesmo pacote/certificado e dados offline preservados no contrato. Não instalado em dispositivo real nesta validação. Nenhuma nova capacidade, grant ou alteração da Central; ponte desativada.
- Pós-aplicação 027: 69 tabelas RM/privadas no total, 57 com RLS; 102 usuários, 778 registros, 14.595 fotos, 945 etapas, 101 atribuições, outbox 4 e quatro recibos preservados; journal novo vazio. SSO/dois administradores e envelope mobile preservados, snapshot anônimo/serviço e journal privado recusados. Histórico 001–027 aplicado e imutável. Railway **`6a67b5a4-de4e-49a2-ba28-926f13b7fed4`** com `SUCCESS`; health 200, 30 negações em 15 URLs com anônimo/cookie forjado, `no-store` e login preservados. Microsoft-only, CSRF, cookie opaco HttpOnly/Secure, callback estrito e início PKCE real até Microsoft aprovados; apenas o fluxo próprio de QA foi cancelado, sem autenticação humana ou CRUD positivo em produção.

Próxima prioridade: exclusão/retirada protegida de alocação e reconciliação de visibilidade/fila. A paridade global permanece em andamento.

Provas locais ignoradas: `stage-rules-027-{rehearse,apply}-proof.json`, `stage-rules-027-source-proof.json`, `operational-stage-rule-qa-summary.json`, `stage-rules-browser-secret-audit.json` e logs `stage-rules-{final,desktop-tests,build}.log`. CI, aplicação, pós-aplicação e publicação confirmados em `stage-rules-ci-proof.json`, `stage-rules-027-apply-proof.json`, `stage-rules-postflight.json`, `stage-rules-deployment.json`, `stage-rules-public-qa.json` e `public-sso-qa.json`.

## Histórico do incremento 026: avaliadores e recuperação histórica

- No Cronograma por projeto/célula, atribuição por formulário antes do primeiro registro; troca e reaplicação com confirmação. Escolhas por identidade ativa vinculada à célula, com homônimos diferenciados pela matrícula. Contextos aprovados/encerrados ou formulários fora do vínculo atual ficam somente leitura.
- Atribuição contextual, avaliador do registro e ator da decisão permanecem distintos. O gestor aplica explicitamente aos não aprovados; novos envios herdam no servidor somente um alvo ainda elegível. Não fabricar formulário/decisão, não alterar respostas, status, lista de aprovadores ou histórico. Mesmo UUID preserva a tentativa e recibos antigos continuam válidos.
- Leitor/ações/controle de envio usam SSO/MFA, capacidades existentes, hash e versões exatas. Todos os controles ficam bloqueados em conflito, tentativa incerta ou divergência entre SSR e snapshot, até confirmação/recarga. Nenhuma concessão na Central e nenhum novo APK. [Contrato](../rm-mobile-supabase/WEB_FORM_REVIEWER_ASSIGNMENTS.md).
- **248 testes desktop, 15 suítes PostgreSQL, 18 cenários de navegador, tipos, build e dois smokes aprovados**. Os cenários usaram o build local `s7ZvqnDxEDg5_RfuOclMl`, HTTP/autenticação simulados e DOM real, com zero erros de página ou origens externas; capturas desktop/390 px inspecionadas. PostgreSQL incluiu 20 disputas reais novas, callers aquecidos e replay de recibos anteriores. Não foi automatizado login Microsoft humano nem CRUD artificial em produção. Os dois smokes e o CI são do mesmo consumidor; não existe lint próprio configurado. Auditoria de 424 fontes e 70 JavaScripts sem os dez segredos locais conhecidos.
- Recuperadas **101 atribuições reais de 103 IDs Bubble**, sem alterar os 778 registros de formulário existentes: 100 contextos vinculados e um histórico fora do vínculo atual, somente consulta. Doze contextos com registro aprovado permanecem bloqueados. As 442 fontes sem contexto/aprovador ou fora dos projetos importados ficaram em relatório de reconciliação; nenhum vínculo ou identidade foi inventado. A carga passou ensaio, aplicação e repetição idêntica: 67 tabelas anteriores preservadas na inserção e 68 snapshots integrais no replay, com zero novas inserções. [Discovery e ferramenta](../rm-mobile-supabase/WEB_FORM_REVIEWER_BOOTSTRAP.md). A origem permaneceu somente leitura, sem emails ou chamadas ao worker.
- Aplicação 026 comparou 67 tabelas anteriores integralmente e deixou a nova vazia; a carga contextual foi uma operação separada. Pós-aplicação confirmou 57 tabelas RM com RLS e fonte SHA256 `a3758ce8311785df8685723109d207d8730a68593ab03d897f94d74022378eaa`. Preservados 102 usuários, 778 registros (sem preenchimento retroativo de avaliador), 14.595 fotos, 945 etapas,outbox 4 e quatro recibos.
- Railway `SUCCESS`, health 200, 24 negações em 12 URLs, Microsoft-only/CSRF/cookie seguro/PKCE até Microsoft verificados; só o fluxo próprio de QA foi cancelado. Nenhum CRUD artificial ou login humano automatizado em produção.

Prioridade registrada após a 026: editor das regras de etapas operacionais por projeto/célula. Continuam pendentes exclusão protegida de alocação, visibilidade com manutenção de fila, cadastros complementares e os demais módulos do plano.

Provas locais ignoradas: `evaluator-026-{rehearse,apply}-proof.json`, `evaluator-bootstrap-{rehearse,apply,replay}-proof.json`, `evaluator-postflight.json`, `evaluator-ci-proof.json`, `evaluator-deployment.json`, `evaluator-public-qa.json`, `form-reviewer-qa-summary.json`, `evaluator-browser-secret-audit.json`, `reviewer-final.log` e `form-reviewer-bootstrap/2026-10-30-initial/`.

## Histórico do incremento 025: ajustes e fotos operacionais

- Retirada da funcionalidade “Quantidade prevista de fotos” da interface, DTO e novas escritas. Coluna/116 valores históricos e replay de recibos anteriores preservados.
- Retirada da aba “Aprovações de etapas” no detalhe do projeto; módulo próprio e aba da célula no Cronograma preservados. Nova alocação utiliza formulários dos modelos sem checkbox/payload manual; edição das alocações existentes conserva vínculos/proteções.
- Fotos obrigatórias da alocação: incluir títulos aplicáveis em lote, editar tag, retirar previsão vazia/não selecionada e restaurar o mesmo ID. Arquivo principal ou qualquer arquivo de lista bloqueia retirada. SQL/JWT/RLS, SSO/MFA, versões, recibos e replay; nenhuma nova capacidade/concessão na Central. [Contrato](../rm-mobile-supabase/WEB_OPERATIONAL_PHOTOS.md).
- **227 testes desktop, 14 suítes PostgreSQL, 32 verificações de navegador, tipos, build e dois smokes aprovados**. Os 19 cenários novos e 13 da galeria usaram o build `xdXK03Qwidz_57ktbm0MH`, HTTP/autenticação simulados e DOM real; zero erros de página ou origens externas. As capturas desktop/390 px foram inspecionadas. Não houve CRUD artificial em produção nem login Microsoft humano automatizado. PostgreSQL inclui 12 disputas reais novas, retentativa offline do mesmo UUID, upgrade com 67 snapshots e callers web/mobile aquecidos. Nenhum APK novo necessário.
- Ensaio com rollback e aplicação definitiva conservaram integralmente 67 snapshots. Pós-aplicação: 102 usuários, 14.595 fotos, 945 etapas, outbox 4, quatro recibos e 486 seleções. `require_sso=true`, 56 tabelas RM com RLS, dispatcher privado e leitura anônima recusados. SHA256 aplicado/versionado: `acdb4c09275801d456af88c0895eb5f9b744b761ba86b046e78a03adaa6fcfe7`.
- Railway `SUCCESS`, health 200, 20 negações em dez URLs, Microsoft-only/CSRF/PKCE até Microsoft confirmados; só o fluxo próprio de QA foi cancelado. Ponte de saída desativada, Bubble somente leitura e nenhum serviço de outro sistema alterado.

Próxima prioridade: atribuição de avaliador antes do primeiro registro, depois regras de etapas operacionais. Essa atribuição exige contrato próprio; o histórico `rm_aprovacoes_registro` não será usado para fabricar um registro de formulário.

Provas locais ignoradas: `operational-025-{rehearse,apply}-proof.json`, `operational-postflight.json`, `operational-ci-proof.json`, `operational-deployment.json`, `operational-public-qa.json`, `operational-photos-qa-summary.json`, `project-photo-qa-summary.json` e `operational-final.log`. Auditoria final dos fontes e dos 70 JavaScripts sem os dez segredos locais conhecidos.

## Cobertura da análise

| Escopo | Evidência estática e limite |
| --- | --- |
| `Group Gestao_projeto_redesign` / `rm_planejamento` | 266 elementos detalhados, 50 eventos (48 ativos/dois desativados), 107 ações ativas e backends ligados inspecionados. Contrato do Group e suas dependências diretas fechado; não representa todas as áreas da página. [Discovery](discovery_rmmi_planejamento.md). |
| `proposta` / Comercial | 225/225 eventos completos, 209 ativos/16 desativados e **453/453 ações ativas** lidas individualmente, incluindo 103 ações dos oito ramos de geração. Workflows de requisição/encaminhamento/e-mail desativados não foram tratados como operação atual. Essa cobertura não equivale a execução de PDF ou migração do módulo. [Discovery](discovery_rmmi_comercial.md). |
| `rm_gestao`, `settings_rm`, `autorizacao` | 194/431 eventos e 49 ações individuais inspecionados, grupos/popups/tipos/backends críticos detalhados. Os 237 eventos restantes foram classificados localmente, sem aumentar a leitura Live declarada; 51 se relacionam a entregas 018/019. A análise minuciosa dessas páginas ainda tem pendências explícitas. [Discovery](discovery_rmmi_cadastros_autorizacao.md), [classificação](classificacao_eventos_pendentes_rmmi.md), [contrato de autorização](contrato_autorizacao_elementos_em.md). |
| Fotos / Report Building | Checkbox, dois workflows de persistência, mapeamento SQL/ETL, galeria e código do consumidor local comparados. Sem chamada de webhook, geração ou alteração do aplicativo Report Building. [Discovery](discovery_rmmi_fotos_report_builder.md). |

Foi criado o plano com origem/destino, dependências, arquivos, riscos e ordem antes das alterações maiores. A matriz distingue funcionalidades já implementadas, parciais, ausentes, divergentes, desativadas ou dependentes; tabela existente ou botão visível não foi usado como prova de migração concluída.

## Implementado

| Funcionalidade | Comportamento entregue | Persistência / autorização |
| --- | --- | --- |
| Seleção individual de fotos | Marcar/desmarcar cada captura na galeria; consultar estado salvo; filtrar selecionadas e ordenar selecionadas primeiro; ampliação independente; paginação conserva filtros. | Campo existente `rm_fotos.selecao_relatorio`; operação `set_project_photo_selection`, versão exata, autoria, recibo/replay e SSO. Escrita exige `em.projects.manage`, leitura projeto/fotos e perfil de escrita. Nenhum arquivo/número/tag é reescrito. |
| Cronograma por projeto | Buscar e selecionar projeto por ID, resumo do projeto, roteiro de células por `indice`, contexto de uma alocação, fechar/trocar seleção, fotos previstas inclusive sem captura, formulários/registros e aprovações de etapas daquela célula. Edição/alocação usa o editor existente. | Leituras com projeções/capacidades e vínculos exatos. Trocar projeto limpa alocação anterior. As ações reaproveitadas mantêm seus controles transacionais existentes. |
| Ordem das células do projeto | Subir/descer, conferir conjunto completo e salvar a sequência; consulta dos índices anteriores; normalização somente explícita; proteção de saída com edição pendente; conflito e retentativa. | `save_project_route`, snapshot atômico com hash e versões, conjunto completo até 2.000 alocações. Altera `indice` e auditoria; conserva `posicao`, prioridade, status, visibilidade, formulários e datas. Projeto encerrado permanece somente consulta. |
| Exclusão de título de foto | Confirmação pelo título exato, exclusão de item sem referência, recusa de item usado, retorno à lista e resposta sanitizada. Salvar/excluir compartilham uma única tentativa; resultado incerto não permite comando paralelo. | `delete_photo_title`, administrador RM com `em.engineering.manage`, versão/recibo/SSO/MFA, FK RESTRICT inclusive modelos aposentados/fotos em lixeira. Não limpa referências nem apaga fotos. |
| Organização de navegação | Entradas existentes agrupadas em Planejamento e Cadastros; títulos, matriz de tipos e gestão de formulários reutilizam suas rotas. Atalhos nos Cadastros; navegação lateral rola preservando saída da conta. | Cada entrada exige sua capacidade própria. Tipos de equipamento, matriz e construtor continuam distintos; menus pendentes não são apresentados como módulos prontos. |
| Regras operacionais de etapas (027) | Criar forward, corrigir por substituição com novo UUID e retirar/restaurar conservando família e histórico; tabela de decisões preservada. Uso, ambiguidade, retorno gerado e destino incompatível bloqueiam gestão. | `manage_stage_rules`, `em.planning.manage` e leituras existentes, SSO/MFA, hash/versões, recibos e journal privado. Mobile filtra regras retiradas sem alterar pull/fila. Nenhum backfill ou novo grant. |

## Reutilizado e preservado

- Mesmo campo de seleção, entidades de fotos/títulos, arquivos, tags, números e relacionamentos. Não foi criada tabela de seleção, segundo catálogo ou nova entidade de formulário.
- Leitores de projeto, `CellEditor`, editor de projeto, componentes de foto/ampliação, formulários e decisões de etapas. O Gantt de 42 dias permanece na visão própria, com filtros, período, paginação e reconhecimento das URLs legadas com período/célula/status. O endereço base passa à visão de projeto solicitada.
- BFF/mutação transacional, permits SSO, recibos, códigos de conflito, controle por versão e hook de envio congelado. A pequena extensão do destino do hook preserva o uso anterior por string.
- Capacidades atuais; nenhuma nova concessão na Central. As identidades legadas de tablet/operadores e os administradores EM permanecem separados da administração global.
- No incremento 022–024, migrações anteriores 001–021 foram preservadas; novas 022–024 aditivas, sem reescrever projetos/respostas ou alterar o aplicativo mobile. A ponte de saída não foi ativada.

## O que permanece pendente

| Área | Lacuna real / dependência |
| --- | --- |
| Group comJg completo | Regras operacionais publicadas com 027; permanecem exclusão/retirada protegida de alocação e reconciliação da visibilidade com a fila. |
| Formulários e aprovações | Atribuição prévia e recuperação contextual publicadas com 026; homologação operacional e integração com relatórios continuam no plano. `rm_aprovacoes_registro` permanece histórico de decisões, sem preenchimentos fictícios. |
| Títulos/tipos/células | Escopo do título continua imutável no editor, ao contrário do legado; transferência precisa reconciliar vínculos textuais/IDs. Complementos de imagens/contatos/equipes e gestão operacional de usuários ainda incompletos. |
| Templates Word | Contrato distinto de Form, com criação/exclusão externa e Google ID. `rm_templates_word` existe, mas faltam reconciliação/importação, armazenamento, jobs e fluxo completo de falha/retentativa. |
| Autorizações | Gestão de elementos e gestão individual ainda exigem contrato/carga de Elemento, identidade exata e integração com a autoridade Central; o helper005 não representa equivalência funcional. |
| Comercial | Precificação, materiais, associação vendedor-cliente, propostas/revisões, numeração transacional e PDFs PT/EN não estão implementados. A 005 aproxima campos divergentes; é necessária reconciliação aditiva e carga própria antes do módulo. |
| Relatórios | A seleção é persistente e compatível com o campo legado. O aplicativo Report Building continua consumindo seu fornecedor n8n; não foi alterado nem homologado um relatório real. Geração e compilação EM continuam pendentes, sem sucesso simulado enquanto suas APIs retornam 501. |
| Demais pacotes | Comentários/anexos novos, edição técnica, QR, laboratório, liberação/requisições comerciais, capacidade/calendários/lotes e coexistência continuam no plano geral. Recebimentos não foi renomeado como uma liberação comercial sem o respectivo workflow. |

## Comportamentos da origem não copiados literalmente

- APIs de ordenação sem autenticação, privacidade ampla/autobinding e exclusões sem proteção foram documentadas. A implementação conserva o efeito legítimo com autorização, versões e proteção de histórico.
- O roteiro do projeto usa `indice`; a fila da célula usa `posicao`. O EM não os trata como sinônimos nem reorganiza a fila ao salvar roteiro.
- A seleção da alocação é limpa ao trocar projeto, corrigindo o risco de contexto antigo observado no fluxo Bubble.
- Resets legados por senha estática/fraca, busca de identidade por nome/e-mail e promoção global não foram reproduzidos.
- Contratos comerciais divergentes da 005, fatores diferentes PT/EN, condição KW textual e nomes de PDF potencialmente colidentes foram registrados para decisão explícita. A diferença de fatores não prova, isoladamente, erro de unidade; a impressão final não foi executada. Nenhum cálculo financeiro foi inventado para “corrigir” o legado.
- O recebimento mobile continua com a jornada aprovada anteriormente, sem restaurar etapas/campos removidos pelo usuário.

## Arquivos principais

- `desktop/src/app/(portal)/cronograma/page.tsx`, `projetos/[id]/page.tsx`, `cadastros/page.tsx` e lista de títulos.
- `desktop/src/components/web/project-photo-gallery.tsx`, `project-schedule*`, `gantt-schedule.tsx`, `project-route-*`, `engineering-title-editor.tsx`, `engineering-save.tsx`, `navigation.ts` e `shell.tsx`.
- `desktop/src/server/web/project-photo-*`, `project-schedule-*`, `project-route-*`, `data.ts`, `engineering-*` e `mutation.ts`.
- Migrações novas `022_rm_web_project_photo_selection.sql`, `023_rm_web_photo_title_deletion.sql`, `024_rm_web_project_route.sql`; seis arquivos de teste SQL e runner existente; testes TS de domínio/BFF/leitores/navegação/hook.
- Contratos [fotos](../rm-mobile-supabase/WEB_PROJECT_PHOTOS.md), [roteiro](../rm-mobile-supabase/WEB_PROJECT_ROUTE.md), [Engenharia](../rm-mobile-supabase/WEB_ENGINEERING.md); quatro discoveries e plano desta revisão.

## Verificação histórica do incremento 022–024

- **214 testes desktop aprovados**, typecheck e build Next aprovados. Não há comando/configuração lint próprio no projeto; não foi declarada uma execução separada de ESLint. O build executou sua etapa de validação configurada e a verificação de tipos.
- **13 suítes PostgreSQL isoladas**, migrações 001–024 e upgrades 017/020/021/022/023/024 aprovados; comparação de 67 snapshots e wrapper aquecido. Sete disputas novas de fotos e 14 de roteiro, além da disputa de exclusão/vínculo de título e das suítes anteriores. Ajustes nas fixtures de testes foram feitos antes de aceitar o resultado.
- Ensaio remoto com **rollback** e aplicação definitiva: **67 snapshots completos iguais** em cada execução, 102 usuários, 945 etapas, outbox 4 e 486 capturas selecionadas preservados; 56 tabelas RM com RLS. O ensaio tinha dois recibos; a aplicação preservou os quatro existentes naquele momento, sem gerar recibo ou dado artificial. A diferença de contagem entre as verificações foi preservada no snapshot da aplicação.
- Auditoria de **392 arquivos de fonte e 70 JavaScripts do navegador**, comparados aos dez segredos locais conhecidos, sem ocorrências. Não houve alteração de dependências.
- **33 cenários de navegador aprovados no mesmo build `r4geICbtcHtt4lIgZQzTz`**: 20 de Cronograma/títulos e 13 de fotos, além de 15 navegações entre módulos e 20 ciclos adicionais nas abas dos projetos. Sem erros de página ou rede externa; HTTP/dados simulados em memória, DOM/build reais. Foram inspecionadas capturas desktop e 390 px; a inspeção encontrou e corrigiu compressão dos botões no cabeçalho móvel, e o novo teste confere seus limites dentro do card.
- **Dois smokes de runtime aprovados**: health/login/assets, redirecionamentos, cookie forjado, endpoints protegidos, CSRF/callback e rotas reservadas sem sucesso fictício. Nenhum CRUD artificial em produção ou login Microsoft humano foi automatizado.

A navegação SPA de contexto foi reproduzida sem mudança de URL/DOM apesar de resposta RSC correta. Controles com os mesmos hrefs e navegação nativa funcionaram; retirar a interceptação de localhost do teste não mudou o diagnóstico. Os links de contexto agora usam o padrão nativo já empregado nas abas do projeto; Shell/Suspense e links para outros caminhos foram preservados. A causa interna do framework não foi determinada e nenhum erro de hidratação foi suprimido. O novo build passou os 33 cenários após a alteração.

## Publicação e verificação pública do incremento 022–024

- Railway EM, mesmo projeto/serviço/ambiente: `SUCCESS`, health 200. Sete URLs alteradas foram verificadas em **14 negações** de anônimo/cookie forjado, mantendo `no-store` e redirecionamento para login.
- Entrada Microsoft-only, cookie opaco seguro, CSRF/callback e início PKCE real até Microsoft aprovados; apenas o fluxo próprio de QA foi cancelado. Não foi automatizado login de pessoa nem CRUD em produção.
- Pós-aplicação confirmou histórico **001–024**, fontes aplicadas iguais às versionadas e `require_sso=true`. Não houve nova capacidade, concessão Central, alteração de identidades ou ativação da ponte.
- SHA256: 022 `eb092c7b375515b44c115ea3690c5f73fa214d863bfd79019587e30e85deb65c`; 023 `c10c9aafc192a738065c35df1f9ecfb4edc7e5337c31b554986c4280489c1d69`; 024 `b8a4b56bc880cc8c04bb9d1e10ed18cbbee568b9d4d3ba5e30c7b9f1d60cabdf`.

As provas locais detalhadas ficam em `.tmp/` ignorada pelo Git: `parity-022-024-{rehearse,apply}-proof.json`, `parity-022-024-postflight.json`, `parity-ci-proof.json`, `parity-public-qa.json`, `public-sso-qa.json`, `parity-qa-summary.json`, `project-photo-qa-summary.json` e logs SQL. São evidência de validação, não parte do produto.

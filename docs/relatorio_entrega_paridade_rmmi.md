# Relatório de execução — revisão de paridade RMMI

Data: 29/10/2026. Complemento ao [plano de execução](plano_execucao_paridade_rmmi.md) e ao [plano geral](../plano_paridade_rmmi_web.md). A recriação continua no mesmo repositório, no Supabase `oficina-em-mi-off` e no Railway EM.

## Situação

**Incremento publicado em [EM web](https://em-web-production.up.railway.app).** Consumidor **`675649e6caf5c664f9888e3b5f2bcd8d42d50904`**, deployment Railway **`65221686-f149-4917-aa1e-f5e1c3b234f8`** com `SUCCESS`; migrações **022–024 aplicadas**, após ensaio com rollback. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/40939109207). A paridade global solicitada não está concluída.

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

## Reutilizado e preservado

- Mesmo campo de seleção, entidades de fotos/títulos, arquivos, tags, números e relacionamentos. Não foi criada tabela de seleção, segundo catálogo ou nova entidade de formulário.
- Leitores de projeto, `CellEditor`, editor de projeto, componentes de foto/ampliação, formulários e decisões de etapas. O Gantt de 42 dias permanece na visão própria, com filtros, período, paginação e reconhecimento das URLs legadas com período/célula/status. O endereço base passa à visão de projeto solicitada.
- BFF/mutação transacional, permits SSO, recibos, códigos de conflito, controle por versão e hook de envio congelado. A pequena extensão do destino do hook preserva o uso anterior por string.
- Capacidades atuais; nenhuma nova concessão na Central. As identidades legadas de tablet/operadores e os administradores EM permanecem separados da administração global.
- Migrações anteriores 001–021 preservadas; novas 022–024 aditivas, sem reescrever projetos/respostas ou alterar o aplicativo mobile. A ponte de saída não foi ativada.

## O que permanece pendente

| Área | Lacuna real / dependência |
| --- | --- |
| Group comJg completo | CRUD de fotos previstas/exceções e tags; atribuição de avaliador antes do primeiro registro; editor das regras operacionais de etapas; exclusão protegida de alocação; reconciliação da visibilidade com a fila. A nova composição não torna esses comandos existentes por si só. |
| Formulários e aprovações | Consulta/revisão/decisão existentes foram reutilizadas. Atribuição prévia Bubble `AprovacaoForm` não equivale a `rm_aprovacoes_registro`, que é histórico e exige um registro. Não criar preenchimento fictício para suprir essa diferença. |
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

## Verificação realizada até aqui

- **214 testes desktop aprovados**, typecheck e build Next aprovados. Não há comando/configuração lint próprio no projeto; não foi declarada uma execução separada de ESLint. O build executou sua etapa de validação configurada e a verificação de tipos.
- **13 suítes PostgreSQL isoladas**, migrações 001–024 e upgrades 017/020/021/022/023/024 aprovados; comparação de 67 snapshots e wrapper aquecido. Sete disputas novas de fotos e 14 de roteiro, além da disputa de exclusão/vínculo de título e das suítes anteriores. Ajustes nas fixtures de testes foram feitos antes de aceitar o resultado.
- Ensaio remoto com **rollback** e aplicação definitiva: **67 snapshots completos iguais** em cada execução, 102 usuários, 945 etapas, outbox 4 e 486 capturas selecionadas preservados; 56 tabelas RM com RLS. O ensaio tinha dois recibos; a aplicação preservou os quatro existentes naquele momento, sem gerar recibo ou dado artificial. A diferença de contagem entre as verificações foi preservada no snapshot da aplicação.
- Auditoria de **392 arquivos de fonte e 70 JavaScripts do navegador**, comparados aos dez segredos locais conhecidos, sem ocorrências. Não houve alteração de dependências.
- **33 cenários de navegador aprovados no mesmo build `r4geICbtcHtt4lIgZQzTz`**: 20 de Cronograma/títulos e 13 de fotos, além de 15 navegações entre módulos e 20 ciclos adicionais nas abas dos projetos. Sem erros de página ou rede externa; HTTP/dados simulados em memória, DOM/build reais. Foram inspecionadas capturas desktop e 390 px; a inspeção encontrou e corrigiu compressão dos botões no cabeçalho móvel, e o novo teste confere seus limites dentro do card.
- **Dois smokes de runtime aprovados**: health/login/assets, redirecionamentos, cookie forjado, endpoints protegidos, CSRF/callback e rotas reservadas sem sucesso fictício. Nenhum CRUD artificial em produção ou login Microsoft humano foi automatizado.

A navegação SPA de contexto foi reproduzida sem mudança de URL/DOM apesar de resposta RSC correta. Controles com os mesmos hrefs e navegação nativa funcionaram; retirar a interceptação de localhost do teste não mudou o diagnóstico. Os links de contexto agora usam o padrão nativo já empregado nas abas do projeto; Shell/Suspense e links para outros caminhos foram preservados. A causa interna do framework não foi determinada e nenhum erro de hidratação foi suprimido. O novo build passou os 33 cenários após a alteração.

## Publicação e verificação pública

- Railway EM, mesmo projeto/serviço/ambiente: `SUCCESS`, health 200. Sete URLs alteradas foram verificadas em **14 negações** de anônimo/cookie forjado, mantendo `no-store` e redirecionamento para login.
- Entrada Microsoft-only, cookie opaco seguro, CSRF/callback e início PKCE real até Microsoft aprovados; apenas o fluxo próprio de QA foi cancelado. Não foi automatizado login de pessoa nem CRUD em produção.
- Pós-aplicação confirmou histórico **001–024**, fontes aplicadas iguais às versionadas e `require_sso=true`. Não houve nova capacidade, concessão Central, alteração de identidades ou ativação da ponte.
- SHA256: 022 `eb092c7b375515b44c115ea3690c5f73fa214d863bfd79019587e30e85deb65c`; 023 `c10c9aafc192a738065c35df1f9ecfb4edc7e5337c31b554986c4280489c1d69`; 024 `b8a4b56bc880cc8c04bb9d1e10ed18cbbee568b9d4d3ba5e30c7b9f1d60cabdf`.

As provas locais detalhadas ficam em `.tmp/` ignorada pelo Git: `parity-022-024-{rehearse,apply}-proof.json`, `parity-022-024-postflight.json`, `parity-ci-proof.json`, `parity-public-qa.json`, `public-sso-qa.json`, `parity-qa-summary.json`, `project-photo-qa-summary.json` e logs SQL. São evidência de validação, não parte do produto.

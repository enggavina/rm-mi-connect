# Portal web EM · MI Electric Brasil

Primeira entrega de gestão web, em 29/10/2026. O portal Next.js usa o mesmo projeto Supabase `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`) do aplicativo EM. O worker Bubble continua desativado; publicar a interface web não ativa a ponte nem envia emails.

## Áreas disponíveis

- **Visão geral:** contagens reais de projetos ativos, formulários em análise, células com prazo vencido e documentos; acesso aos projetos recentes e pendências.
- **Projetos:** busca, filtros por cliente/célula/status, paginação, criação e edição dos dados do projeto. Detalhe com informações do equipamento, células, registros, galeria, documentos privados, notas fiscais, comentários e aprovações já existentes. A galeria permite seleção individual persistente para relatório, filtro de selecionadas e ordenação visual; a ampliação permanece independente. Usa `rm_fotos.selecao_relatorio`, sem mudar arquivos, tags ou números. [Contrato de fotos](../../rm-mobile-supabase/WEB_PROJECT_PHOTOS.md).
- **Planejamento:** consulta das alocações e edição de prazos, responsável, horas, visibilidade, bloqueio e formulários. Nova alocação materializa apenas os modelos daquela célula e tipo de equipamento. O tipo não pode ser alterado depois da alocação; formulários já enviados não são removidos.
- **Fila da célula:** seleção explícita da célula, trabalhos abertos visíveis/ocultos, prioridade e controles acessíveis de posição. Alterar prioridade conserva a ordem; mover ou confirmar a sequência é uma decisão explícita. O lote salva a fila completa com versões, autoria e idempotência, sem reescrever status/formulários/visibilidade.
- **Recebimentos:** triagem paginada de projetos ativos sem OS/tipo/alocação, busca e filtros com indicadores globais. Usa os editores existentes para identificação e planejamento. Projetos legados sem tipo já alocados são sinalizados para revisão, mantendo a proteção dos registros.
- **Carga planejada:** contagens por célula, bloqueios, prazos vencidos pelo dia local inclusivo e horas informadas. Ausência de estimativa difere de zero; não há capacidade disponível ou percentual de ocupação inferido desses dados. [Contrato PCP](../../rm-mobile-supabase/WEB_PCP_QUEUES.md).
- **Cronograma:** visão Células por projeto baseada no Group `Gestao_projeto_redesign`: pesquisa/seleção, resumo, roteiro por `indice`, contexto da alocação, fotos previstas/registradas, formulários e etapas. A ordenação acessível usa snapshot/versionamento e salva o conjunto completo, preservando a fila por `posicao`; projetos encerrados e conjuntos acima de 2.000 não permitem edição. Troca/fechamento de contexto usa navegação SSR nativa, com proteção de edição pendente. A visão Gantt preserva a janela de 42 dias, filtros, paginação e intervalos reais; datas ausentes/inválidas/fora do período são indicadas. CRUD operacional de slots, atribuição prévia de avaliador e regras de etapas ainda constam no plano. [Contrato do roteiro](../../rm-mobile-supabase/WEB_PROJECT_ROUTE.md).
- **Aprovações de etapas:** fila paginada com filtros por projeto/célula/situação e ações disponíveis ao usuário; detalhe e aba do projeto com Liberar ou Retornar/Aprovar, conforme regras do mobile. Histórico web vinculado à etapa, separado dos logs de célula sem vínculo; duas versões exatas e protocolo idempotente protegem disputas com o mobile. Exige `em.approvals.read` para consulta e `em.approvals.decide` para decisão, além da autorização operacional. [Contrato completo](../../rm-mobile-supabase/WEB_STAGE_APPROVALS.md).
- **Formulários:** consulta das respostas com seções recolhidas, imagens, assinaturas e histórico; aprovação ou devolução de questões específicas para correção pelo fluxo mobile existente. Respostas históricas sem questão continuam somente para consulta.
- **Modelos de formulário:** criação vazia, cópia de uma base ou nova versão; editor de subtítulos/perguntas/opções, tipos, unidades, intervalos, obrigatoriedade, prévia e publicação. Rascunhos incompletos podem ser salvos; a publicação usa somente o conteúdo salvo e cria uma versão imutável com IDs e numeração próprios. Modelos anteriores e trabalhos offline permanecem preservados. Consulta exige `em.form_templates.read`; gestão exige `em.form_templates.manage` e administrador RM. [Contrato completo](../../rm-mobile-supabase/WEB_FORM_TEMPLATES.md).
- **Cadastros:** consulta paginada de clientes, células, tipos de equipamento, equipe e modelos de formulário. Criação/edição e exclusão protegida dos dados básicos de clientes, células e tipos, restrita ao administrador com `em.catalogs.manage`. Atalhos reutilizam títulos de fotos, matriz de tipos e construtor conforme suas capacidades próprias; esses módulos continuam distintos. O catálogo de títulos permite exclusão somente sem referência, com administrador RM e `em.engineering.manage`. Imagens, contatos, transferência de escopo de título, Templates Word e gestão própria de acessos operacionais permanecem no [plano de paridade](../../plano_paridade_rmmi_web.md).
- **Engenharia:** roteiros de células por tipo de equipamento, formulários vinculados com identificação da versão, modelos de fotos obrigatórias, etapas/destinos/aprovadores e catálogo de títulos de fotos. Consulta exige `em.engineering.read`; criação/edição exige `em.engineering.manage` e administrador RM. As alterações configuram futuras alocações e preservam os projetos já alocados. A decisão de etapas está no módulo de Aprovações; editar atribuições em projetos já alocados continua no plano. Consulte o [contrato e a recuperação dos modelos](../../rm-mobile-supabase/WEB_ENGINEERING.md).

A consulta e abertura dos documentos existentes estão nesta entrega. Geração/compilação de novos relatórios, orçamento comercial, laboratório e administração de contas não são apresentados como funcionalidades prontas. As rotas internas anteriores de relatórios/TOTP continuam reservadas e protegidas por Bearer; o login web usa a MFA nativa do Supabase quando há TOTP verificado.

## Acesso e autorização

O portal usa Microsoft SSO com a Central de Acessos. Os perfis web dedicados de `mgavina@mielectric.com.br` e `softdev05@mielectric.com.br` são administradores do EM por aprovação explícita. O papel global da Central não é promovido por essa decisão. O login por senha fica desativado quando `EM_SSO_ENABLED=true`. O [contrato SSO](sso.md) descreve configuração, perfis e limites. Contas legadas não são vinculadas automaticamente por email e o administrador do tablet permanece preservado.

Sessões SSO usam um cookie opaco HttpOnly, SameSite Lax e Secure em produção, com tokens cifrados apenas no servidor. Cada requisição verifica identidade, perfil e permissões atuais; TOTP cadastrado exige `aal2` no emissor correspondente. Logout POST verifica origem e encerra somente este acesso (`scope:'local'`), preservando o tablet. O navegador não recebe tokens ou chave de serviço. A implementação SSR por senha permanece somente para modo legado com SSO desativado.

As leituras e downloads usam o JWT do usuário e as policies do banco. Dados sensíveis de `rm_private` nunca são consultados para montar a interface. As ações passam por `rm_web_mutate_v1` com autorização, recibo idempotente e `expected_updated_at` exato. Conflitos exigem uma nova leitura, sem sobrescrever silenciosamente as alterações de outro usuário ou operador. Retentativa após resposta de rede ambígua conserva o mesmo UUID e conteúdo.

Migrações necessárias: **001–024**. O contrato de gestão está em [WEB_MANAGEMENT.md](../../rm-mobile-supabase/WEB_MANAGEMENT.md), a Engenharia em [WEB_ENGINEERING.md](../../rm-mobile-supabase/WEB_ENGINEERING.md), o construtor em [WEB_FORM_TEMPLATES.md](../../rm-mobile-supabase/WEB_FORM_TEMPLATES.md), as aprovações em [WEB_STAGE_APPROVALS.md](../../rm-mobile-supabase/WEB_STAGE_APPROVALS.md), as filas em [WEB_PCP_QUEUES.md](../../rm-mobile-supabase/WEB_PCP_QUEUES.md) e a ponte privada em [SSO_BRIDGE.md](../../rm-mobile-supabase/SSO_BRIDGE.md). A 015 usa `PT409` para conflito de versão porque `40001` provoca retentativas transacionais no PostgREST, inadequadas para um conflito deliberado do usuário.

## Executar e verificar

Node **22** ou superior. As instalações mobile e desktop são independentes.

```sh
cd desktop
npm ci
npm run dev
npm test
npm run build
npm run test:smoke
```

Para a aplicação web, definir `SUPABASE_URL`, `SUPABASE_ANON_KEY` e as variáveis server-side do [SSO](sso.md). A chave privada `EM_SSO_BRIDGE_SERVICE_ROLE_KEY` é necessária somente à ponte de identidade e sessões do EM. Tokens administrativos da Central e tokens Bubble não são usados no runtime web. O build funciona sem credenciais e `SYNC_OUTBOX_ENABLED=false` continua desativado.

O Dockerfile usa Node 22, saída standalone e usuário não-root. O serviço web deve publicar `0.0.0.0:$PORT`; Railway fornece a porta. O healthcheck `/api/health` testa o processo, não a disponibilidade do banco. A configuração mantém `Root Directory=/desktop` quando a origem é o repositório completo; ao enviar somente a pasta desktop pela CLI, o Dockerfile e `railway.json` ficam na raiz do pacote enviado.

Publicação concluída em 29/10/2026: **[EM web](https://em-web-production.up.railway.app)**, no projeto Railway `em-mi-electric-brasil` (`472ac09b-a1b2-4b2f-b561-b43d0b471b06`), serviço `em-web` (`c26e7026-429b-4965-a8a0-b0c91a1665de`), ambiente `production` (`b6f8a871-027c-49eb-adac-43ad8586fbc9`). Os serviços de outros sistemas foram preservados.

Publicação inicial anterior ao SSO: deploy `97c7230c-be56-4aeb-a93c-0eb34bcd36f7`, origem CLI a partir de `desktop/`, commit `cd2e520`, com URL/chave pública Supabase, porta e `SYNC_OUTBOX_ENABLED=false`. A integração SSO requer as novas variáveis privadas documentadas acima. O serviço não está conectado a autodeploy do GitHub; uma conexão futura deve usar Root Directory `/desktop`.

Engenharia publicada: deploy **`603e3698-8698-4f8c-a7fb-1dc2495881ca`**, commit **`36f2fc5125f5ee708fb6a83223458a0f2a58746f`**. Railway confirmou `SUCCESS`; `/api/health` respondeu 200 e as sete novas rotas recusaram acesso anônimo e cookie forjado. A entrada PKCE real continuou chegando à Microsoft; o fluxo de QA foi cancelado sem autenticar uma pessoa ou gravar dados de teste.

Construtor publicado: deploy **`21c95a5e-2f82-4f64-9f92-4fe676324e16`**, consumidor **`934f8bc1fd45ba9287666c7371a79c7b00ba1c83`** (mudança funcional `a023538`). Railway confirmou `SUCCESS`; health 200 e as quatro novas rotas negaram anônimo/cookie forjado. As novas capacidades foram registradas e concedidas depois dessa confirmação: **16 para cada administrador**, `mgavina` e `softdev05`. A promoção de `softdev05` ficou restrita ao EM; demais contas, identidades, permissões e papel global foram preservados. Registro reproduzível da Central no [PR #1](https://github.com/enggavina/mi-central-acessos/pull/1), commit `0508cd83ec3b5cabcb906901f64e0e297089a95b`.

Aprovações publicadas: deploy **`77018942-bc21-496a-8a0b-f1bd24b6b64d`**, consumidor **`ac4b3b4d9facb1e2242064390bd5adf0dd6ba679`**. Railway confirmou `SUCCESS`; [CI web/mobile](https://github.com/enggavina/rm-mi-connect/actions/runs/40918576982) aprovado, health 200 e as duas rotas novas recusaram anônimo/cookie forjado. Depois desses gates foram registradas/concedidas `em.approvals.read/decide`: **18 funções/36 concessões**, 18 para cada administrador do EM. O papel global de SOFTDEV05 continua `user`; nenhuma outra aplicação ou identidade foi alterada. Procedimentos reproduzíveis no [PR #1 da Central](https://github.com/enggavina/mi-central-acessos/pull/1), commit `e601454cc68f3e7fb98128d2a1990d8d70f5434b`; sem deploy do runtime da Central.

PCP 3B.1 publicado: consumidor **`37b54866762022da6b0d5fe44dd663ee3dba2fa0`**, deploy **`9d06331d-6764-4cc8-ab0c-f1197fe3cb88`** com `SUCCESS`, [CI web/mobile](https://github.com/enggavina/rm-mi-connect/actions/runs/40926891591) aprovado. Health 200, seis negações para as três novas rotas e início SSO/PKCE até Microsoft conferidos. Sem nova capacidade ou alteração na Central: permanecem 18 capacidades e 36 concessões, com os dois administradores EM existentes.

## Validação das filas PCP

- **188 testes desktop**, tipos, build, dois smokes e auditoria npm sem vulnerabilidades. 70 arquivos JavaScript do navegador sem as seis chaves privadas locais; fontes sem dez segredos conhecidos.
- **001–021 e dez suítes PostgreSQL**. Upgrade preservou 56 tabelas públicas e 11 privadas; oito disputas reais cobrem novas alocações/materialização antes/depois do lote, encerramento/reativação, mudança mobile e replay simultâneo. Fila de 2.001 itens não permite edição parcial; prioridade sem ordem e no-op não normalizam posições/timestamps.
- **17 cenários e 30 navegações finais** no build `PeWQVPyEXPqDUP9aigml0`, DOM real e HTTP simulado, sem interceptação do JavaScript, erros de página ou rede externa. Nove capturas desktop/390 px inspecionadas. Fluxos positivos não alteraram dados reais nem simularam login Microsoft humano.
- React `#418` foi reproduzido e localizado no limite entre o shell cliente e o slot RSC/carregamento, com o cursor dentro de main antes de o shell hidratar a tag. Main/footer agora pertencem ao layout servidor e há Suspense explícito antes de main, mantendo SSR e loading. Apenas transferir main não resolveu o controle; a variante completa passou duas execuções de 17 cenários e 100 navegações adicionais, com os erros preservados e sem supressão.
- Aplicação remota da 021 preservou **67 snapshots completos**, 102 usuários, 945 registros de etapas, outbox 4 e receipts 2. As **56 tabelas RM mantêm RLS**. Fonte aplicada/versionada SHA256 `ca096c9fffa82693776226fd0e09309ee6a65ab61aa74836708279f1f6bec417`; nenhum registro artificial ou correção de tipo legado em produção. O worker permanece desativado.

## Validação das aprovações

- **173 testes desktop**, tipos, build, dois smokes e auditoria npm sem vulnerabilidades. 67 arquivos JavaScript do navegador sem as seis chaves privadas locais; auditoria dos fontes sem dez segredos conhecidos.
- **001–020 e nove suítes PostgreSQL isoladas**: concorrência web/mobile nos dois sentidos, mesmo UUID simultâneo, SSO/MFA, autoria, regras de aprovador, vínculo legado e upgrade com dados anteriores preservados.
- **Doze cenários Chromium**, build real e HTTP/dados simulados, incluindo as três ações, motivo de retorno, replay exato, conflitos de etapa/célula, perfis sem decisão, aba do projeto e 390 px. Execuções finais sem erros de página ou rede externa. As capturas foram refeitas após aguardar o fim da navegação; não houve alteração de produto por esse ajuste do teste.
- Instalação da 020 com **66 snapshots completos iguais** (55 tabelas públicas e 11 privadas), 102 usuários, 945 registros de etapas, outbox 4 e receipts 2 preservados. A tabela de decisões estava vazia; **56 tabelas RM com RLS**. SHA256 da fonte aplicada e versionada: `47a13366213e8e59ca35f904a1a1afa7c741d04fc7c98fbb0121717fd364cf7e`.
- Em produção: quatro negações HTTP para as duas rotas, health 200 e início SSO com PKCE até Microsoft, cancelando somente o próprio fluxo de QA. Concessões centrais ensaiadas, aplicadas com SHA real e repetidas sem novas auditorias; identidade trocada recusada e hashes dos demais acessos preservados. Não houve decisão artificial nem login Microsoft humano automatizado. O worker permanece desativado.

## Validação do construtor

- **158 testes desktop**, tipos, build, dois smokes e auditoria npm sem vulnerabilidades; [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/40885669392).
- **001–019 e oito suítes PostgreSQL isoladas**, incluindo duas publicações por dois administradores na mesma família, disputa de edição com `PT409`, replay, imutabilidade e envio/revisão mobile com os IDs antigos após publicar uma nova versão.
- **Dez cenários Chrome**, DOM/build reais e HTTP/dados simulados em memória: editor/prévia dos 15 tipos, frações/textos alternativos, normalização explícita, salvar incompleto, publicar somente o salvo, retry de save/publish, conflito, saída com alterações não salvas, permissões e 390 px. Duas execuções finais sem erros de página ou rede externa. Um alerta React `#418` em execução preliminar não voltou nas duas repetições instrumentadas; nenhuma correção de produto foi atribuída a esse evento.
- Migração remota com **53 snapshots completos iguais**, 102 usuários preservados, outbox 4 e receipts 0. As 55 tabelas RM têm RLS, e as três tabelas do construtor estavam vazias após instalar a migração. [Contrato e provas](../../rm-mobile-supabase/WEB_FORM_TEMPLATES.md).
- 65 arquivos JavaScript do navegador sem as chaves privadas locais. PKCE real continuou chegando à Microsoft, com cancelamento somente do fluxo de QA. Não houve CRUD artificial em produção nem teste de autenticação humana automatizado. O worker permanece desativado.

## Validação da Engenharia

- **133 testes desktop**, tipos, build, dois smokes e auditoria npm sem vulnerabilidades; [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/40877488375).
- Migrações **001–018 e sete suítes PostgreSQL isoladas**, incluindo concorrência entre duas conexões, autorizações, modelos legados, materialização futura e preservação das alocações existentes.
- **Dez cenários Chrome**, desktop e 390 px: roteiros, títulos, vínculos, aprovadores, edição explícita de legado, retirada de item, conflito, retry exato e perfis sem gestão. DOM/build reais; dados e HTTP simulados em memória, sem rede externa ou erros de página. Não equivalem a login Microsoft humano ou CRUD no banco de produção.
- Migração remota com **53 snapshots das colunas anteriores preservados**. Bootstrap real de 963 modelos de fotos/70 de aprovação em 100 matrizes com 53 snapshots protegidos iguais; replay completo sem duplicatas nem mudança de timestamps. [Contrato e comprovação](../../rm-mobile-supabase/WEB_ENGINEERING.md).
- 59 arquivos JavaScript do navegador verificados sem as chaves privadas locais. O worker permanece desativado.

## Validação inicial do portal

- 61 testes desktop, TypeScript, build de produção e auditoria npm sem vulnerabilidades conhecidas.
- CI do commit de aplicação aprovado, incluindo os 84 testes mobile e o smoke de runtime web sem credenciais reais.
- Migrações 001–015 e quatro suítes PostgreSQL isoladas, incluindo planejamento, idempotência, conflitos, MFA e devolução web → correção mobile → aprovação web.
- Navegador Chrome local e no endereço Railway: login, cookie HttpOnly/Secure/SameSite, busca, abas de projeto, ampliação da galeria, abertura/cancelamento de editor, cronograma, consulta de 136 respostas, seleção para devolução sem submeter, leitura de PDF privado, cadastros, rejeição de criação vazia, navegação em 390 px e logout local. Nenhum erro de execução do navegador.
- Ambiente público sem sessão: login e health 200, painel redirecionando ao login e APIs de dados retornando 401. Os testes de navegador não aprovaram, devolveram ou editaram registros operacionais reais; operações positivas foram verificadas no PostgreSQL isolado.

Abas, filtros de query e paginação usam navegação HTTP para garantir a leitura atual da seleção. No runtime Next 15 instalado, a transição cliente de query atualizou o cache interno sem confirmar a interface; o fallback nativo foi reproduzido e validado. Login e MFA redirecionam diretamente a `/painel`, evitando a resposta intermediária da rota `/` em Server Actions. Retornos bem-sucedidos de edição/revisão também fazem uma leitura completa da tela atualizada.

Referências de implementação: [sessões SSR Supabase/Next](https://supabase.com/docs/guides/auth/server-side/creating-a-client?queryGroups=framework&framework=nextjs), [CLI Railway](https://docs.railway.com/guides/cli).

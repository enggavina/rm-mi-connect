# Portal web EM · MI Electric Brasil

Primeira entrega de gestão web, em 29/10/2026. O portal Next.js usa o mesmo projeto Supabase `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`) do aplicativo EM. O worker Bubble continua desativado; publicar a interface web não ativa a ponte nem envia emails.

## Áreas disponíveis

- **Visão geral:** contagens reais de projetos ativos, formulários em análise, células com prazo vencido e documentos; acesso aos projetos recentes e pendências.
- **Projetos:** busca, filtros por cliente/célula/status, paginação, criação e edição dos dados do projeto. Detalhe com informações do equipamento, células, registros, galeria, documentos privados, notas fiscais, comentários e aprovações já existentes.
- **Planejamento:** consulta das alocações e edição de prazos, responsável, horas, visibilidade, bloqueio e formulários. Nova alocação materializa apenas os modelos daquela célula e tipo de equipamento. O tipo não pode ser alterado depois da alocação; formulários já enviados não são removidos.
- **Cronograma:** janela de 42 dias, filtros e paginação, intervalos reais e identificação de prazos vencidos. Datas ausentes, inválidas ou fora do período são indicadas sem inventar barras.
- **Formulários:** consulta das respostas com seções recolhidas, imagens, assinaturas e histórico; aprovação ou devolução de questões específicas para correção pelo fluxo mobile existente. Respostas históricas sem questão continuam somente para consulta.
- **Cadastros:** consulta paginada de clientes, células, tipos de equipamento, equipe e modelos de formulário. Criação/edição e exclusão protegida dos dados básicos de clientes, células e tipos, restrita ao administrador com `em.catalogs.manage`. Imagens, contatos e gestão própria de acessos operacionais permanecem no [plano de paridade](../../plano_paridade_rmmi_web.md).
- **Engenharia:** roteiros de células por tipo de equipamento, formulários existentes vinculados, modelos de fotos obrigatórias, etapas/destinos/aprovadores e catálogo de títulos de fotos. Consulta exige `em.engineering.read`; criação/edição exige `em.engineering.manage` e administrador RM. As alterações configuram futuras alocações e preservam os projetos já alocados. O construtor de perguntas e a decisão de etapas pelo web são entregas separadas. Consulte o [contrato e a recuperação dos modelos](../../rm-mobile-supabase/WEB_ENGINEERING.md).

A consulta e abertura dos documentos existentes estão nesta entrega. Geração/compilação de novos relatórios, orçamento comercial, laboratório e administração de contas não são apresentados como funcionalidades prontas. As rotas internas anteriores de relatórios/TOTP continuam reservadas e protegidas por Bearer; o login web usa a MFA nativa do Supabase quando há TOTP verificado.

## Acesso e autorização

O portal passa a usar Microsoft SSO com a Central de Acessos. Foram aprovados perfis web dedicados para `mgavina@mielectric.com.br` (administrador) e `softdev05@mielectric.com.br` (consulta). O login por senha fica desativado quando `EM_SSO_ENABLED=true`. O [contrato SSO](sso.md) descreve configuração, perfis e limites. Contas legadas não são vinculadas automaticamente por email e o administrador do tablet permanece preservado.

Sessões SSO usam um cookie opaco HttpOnly, SameSite Lax e Secure em produção, com tokens cifrados apenas no servidor. Cada requisição verifica identidade, perfil e permissões atuais; TOTP cadastrado exige `aal2` no emissor correspondente. Logout POST verifica origem e encerra somente este acesso (`scope:'local'`), preservando o tablet. O navegador não recebe tokens ou chave de serviço. A implementação SSR por senha permanece somente para modo legado com SSO desativado.

As leituras e downloads usam o JWT do usuário e as policies do banco. Dados sensíveis de `rm_private` nunca são consultados para montar a interface. As ações passam por `rm_web_mutate_v1` com autorização, recibo idempotente e `expected_updated_at` exato. Conflitos exigem uma nova leitura, sem sobrescrever silenciosamente as alterações de outro usuário ou operador. Retentativa após resposta de rede ambígua conserva o mesmo UUID e conteúdo.

Migrações necessárias: **001–018**. O contrato de gestão está em [WEB_MANAGEMENT.md](../../rm-mobile-supabase/WEB_MANAGEMENT.md), a Engenharia em [WEB_ENGINEERING.md](../../rm-mobile-supabase/WEB_ENGINEERING.md) e a ponte privada em [SSO_BRIDGE.md](../../rm-mobile-supabase/SSO_BRIDGE.md). A 015 usa `PT409` para conflito de versão porque `40001` provoca retentativas transacionais no PostgREST, inadequadas para um conflito deliberado do usuário.

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

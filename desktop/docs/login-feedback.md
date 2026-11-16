# Feedback de entrada e loader MI

O login corporativo agora informa imediatamente o envio em andamento, com o botão desabilitado e o loader da MI em primeiro plano. O símbolo usa a geometria original de `public/mi-electric-brasil.svg`: os arcos giram ao redor do centro original e somente as letras MI pulsam. A marca permanece vetorial; não há imagem remota ou dependência nova para a animação.

`MiLoader` é compartilhado com o login por senha, quando esse modo está habilitado, e com o carregamento das páginas do portal. Oferece status textual acessível e versão estática quando o sistema solicita movimento reduzido. A região de status fica fora do formulário marcado como ocupado, permitindo o anúncio imediato por leitores de tela.

O login Microsoft continua enviando um formulário nativo `POST /auth/sso/start`, com a política de referência `same-origin` e o redirecionamento existentes. A interface não substitui esse envio por fetch, não recebe tokens e não altera sessão, permissões ou provedor. Uma referência síncrona impede envios repetidos antes da atualização visual do botão.

Ao retornar pelo histórico com o documento em cache, `pageshow.persisted` restaura o estado de entrada. Um `pageshow` inicial tardio não libera outro envio enquanto a navegação está pendente. **Cancelar entrada** ou **Escape** interrompe a navegação nativa antes de restaurar o botão; a interface não envia uma segunda solicitação automaticamente. O login por senha conserva o ciclo de vida da Server Action e não oferece um cancelamento que apenas esconda uma requisição ainda em andamento.

Arquivos principais: `app/login/sso-login-form.tsx`, `app/login/login-form.tsx`, `app/login/page.tsx`, `app/(portal)/loading.tsx`, `components/web/login-progress.tsx`, `login-progress.module.css`, `mi-loader.tsx` e `mi-loader.module.css`.

A validação usa o navegador real com formulários e respostas locais controladas: envio nativo, headers, redirecionamento, envio único, retorno/erro/cancelamento, movimento reduzido e telas de 1240/390 px. A animação durante o POST é conferida com capturas do compositor; não se usa uma pausa na navegação real para inferir que ela está travada. Os testes de estado detalhados usam um observador de submit local, e os testes de integração do POST são executados separadamente.

Esta entrega é somente web, sem alteração de banco, migrações, contas ou aplicativo Android. O Bubble permanece somente leitura e a ponte de saída continua desativada.

## Validação

489 testes web, typecheck, build e os dois smokes oficiais de produção local aprovados. O [CI com Node 22](https://github.com/enggavina/rm-mi-connect/actions/runs/43928119829) também aprovou os 116 testes mobile e os dois contratos QR existentes. A alteração não exige migração nem geração de outro APK.

O navegador Chromium conferiu **16 grupos de cenários**, com nove POSTs nativos locais e cinco cancelamentos que encerraram a conexão antes da resposta. Foram verificados botão/teclado, envio único, retorno do histórico, erro do servidor, movimento reduzido, ausência de JavaScript e telas de 1240/390 px. Duas capturas durante o mesmo POST retido, separadas por 400 ms, confirmaram a animação no compositor. Nenhum erro React ou acesso externo ocorreu nessa bateria. As capturas e o resultado detalhado ficam ignorados em `.tmp/login-loader-qa/`.

A auditoria do build local conferiu 81 JavaScripts contra dez segredos locais conhecidos, sem ocorrências. As migrações aplicadas 001–033 e 035–046 permanecem intactas. Não há novo comando de lint; `git diff --check` também foi executado.

## Publicação

Publicado em 16/11/2026 no [EM web](https://em-web-production.up.railway.app), consumidor **`b065e67bd0a7e8a237d1a2888efc2a3c12a1d3bd`**, Railway **`e2249c1b-49a7-4ae6-8a30-5302a2d75ee8`** com **SUCCESS**.

A página publicada respondeu 200 com o formulário corporativo nativo e as animações CSS novas. Health 200; cinco verificações públicas negaram entrada sem sessão/cookie válido ou método permitido. Em um contexto novo de navegador, sem credenciais, o próprio código publicado exibiu o loader durante um POST nativo retido brevemente; dois frames de 390×844 confirmaram movimento. A mesma requisição foi então liberada sem alterar método/headers, recebeu 303 e chegou à Microsoft com Origin e política de referência preservados. Somente o fluxo criado para essa verificação foi encerrado, com logout 303 confirmado; não houve seleção de conta, login humano automatizado ou CRUD de negócio.

Provas locais ignoradas: `.tmp/login-loader-{ci-proof,deployment-proof,environment-proof,browser-secret-audit,public-checks}.json`, `.tmp/login-loader-qa/result.json` e `.tmp/login-loader-production-qa/proof.json`. Os PNGs de produção foram revisados e ficam ao lado dessa última prova. O destino Supabase, o SSO e os estados dos workers existentes foram conferidos sem alteração.

# Início, acompanhamento e gêmeo digital

O Início (`/painel`) concentra os 12 cards de trabalho existentes. Indicadores, projetos atualizados recentemente e pendências foram movidos para **Acompanhamento da operação** (`/acompanhamento`), acessível pelo menu lateral. O Início não chama mais `getOverview`; o atalho dessa consulta tem prefetch desabilitado para não antecipar as agregações.

A nova página reutiliza o mesmo leitor, contagens e limites anteriores: consultas com JWT/RLS, contagens sem carregar registros completos e até oito registros recentes por consulta. As capacidades atuais de projetos, formulários, planejamento e documentos continuam independentes. Quem possui somente acesso ao portal recebe uma explicação de ausência de indicadores, sem valores fictícios nem acesso adicional.

O catálogo compartilhado de navegação agora oferece até sete atalhos, preservando os cinco anteriores e acrescentando **Acompanhamento da operação** e **Gêmeo digital 3D**. Esses dois itens ficam separados dos cards de trabalho. O item ativo considera somente rotas internas; o link externo tem indicação de nova aba. O menu mantém a rolagem existente e o perfil visível em telas baixas, além do comportamento de teclado e foco no celular.

## Workshop 3D existente

O gêmeo digital já publicado está em [Workshop 3D](https://workshop-production-46d3.up.railway.app), projeto `EM-Dashboard-Tycoon` / `enggavina/mi-workshop`. O atalho abre essa aplicação real em uma nova aba com `rel="noopener noreferrer"`; a página de acompanhamento oferece o mesmo acesso. Não há iframe, proxy de sessão ou cópia de tokens. O serviço do Workshop bloqueia incorporação por iframe.

O Workshop tem SSO e autorização próprios. O papel de administrador do EM não concede acesso automaticamente à outra aplicação, e nenhuma concessão foi alterada nesta entrega. A verificação pública encontrou a página/health disponíveis e a API protegida contra acesso anônimo.

**Fonte de dados:** o Workshop atual continua consultando o Bubble em leitura. O EM continua no Supabase `oficina-em-mi-off`, com a ponte de saída desativada. Incluir o atalho não migra nem sincroniza essas fontes; projetos ou alterações novos do EM podem não aparecer no Workshop. Não houve alteração ou deploy do outro serviço.

## Validação

Os testes de navegação conferem os 12 cards originais, os sete atalhos, as capacidades, o endereço externo e o estado ativo. Os testes existentes do leitor de indicadores mantêm as verificações de autorização, contagens e limites. A rota nova integra os dois smokes de autenticação.

O QA com React/CSS reais cobriu nove cenários em desktop, celular e orientação horizontal. A renderização das páginas foi conferida em quatro escopos: legado, somente portal, somente documentos e somente formulários. Na home, o leitor de indicadores não é chamado; no acompanhamento, é chamado uma vez. Os artefatos ficam ignorados em `desktop/.tmp/overview-navigation-qa/`.

Esta entrega não altera tabelas, migrações, usuários, recebimentos, respostas ou trabalhos offline, nem exige um novo APK.

## Publicação

Publicado em 16/11/2026 no [EM web](https://em-web-production.up.railway.app), consumidor **`760630a5b003cec1ab51cc9f8fd8246fbf60bae6`**, Railway **`c39f392d-712f-423f-aa65-3c5211bd5384`** com **SUCCESS**. O [CI Node 22](https://github.com/enggavina/rm-mi-connect/actions/runs/43933609545) aprovou 490 testes web, 116 mobile, dois contratos QR, tipos, build e os dois smokes. Os mesmos gates web foram aprovados localmente; não há comando independente de lint e `git diff --check` passou.

A conferência de produção validou health/login 200 e seis recusas com redirecionamento ao login para Início/Acompanhamento, incluindo cookie forjado e query string. As páginas privadas preservam `no-store`. O endereço externo do Workshop respondeu 200, a API anônima continuou 401 e a proteção de iframe permaneceu ativa. Não houve login humano automatizado, uso de credenciais ou escrita de negócio na produção. A auditoria conferiu 82 JavaScripts do build local contra dez segredos locais conhecidos, sem ocorrências.

Provas ignoradas: `.tmp/operation-overview-{ci-proof,deployment-proof,environment-proof,browser-secret-audit,public-checks}.json`, `.tmp/operation-overview-web-tests.log`, `desktop/.tmp/operation-overview-*-final.log` e os resultados/screenshots em `desktop/.tmp/overview-navigation-qa/`.

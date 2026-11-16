# Identidade visual EM e Workshop 3D

O EM reutiliza a paleta do gêmeo digital Workshop 3D. A referência consultada foi `EM-Dashboard-Tycoon/src/theme.css`, somente para leitura. O arquivo `src/app/mi-theme.css`, importado depois dos estilos globais, reúne o tema do portal. Os componentes de navegação, cards e Gantt consomem as variáveis de marca.

| Uso | Cor |
| --- | --- |
| Faixa lateral MI | `#ec3c44` |
| Botões, links e texto de seleção | `#b92332` |
| Hover dos controles principais | `#981b28` |
| Fundo suave de seleção | `#fff0f1` |
| Borda de marca | `#e8a1a8` |
| Texto principal | `#0e1724` |
| Texto secundário | `#5b6777` |
| Fundo da aplicação | `#f3f5f7` |
| Superfícies | `#ffffff` |
| Divisórias | `#d9dfe6` |

## Menu e acesso

No desktop, o menu inicia como faixa de 70 px, com ícones claros, símbolo MI branco e item ativo em superfície clara. O botão **Expandir navegação**, no cabeçalho, mostra os nomes dos mesmos atalhos; **Recolher navegação** retorna ao modo compacto. Os nomes acessíveis e títulos dos links continuam disponíveis quando o menu está recolhido. O modo escolhido acompanha a navegação enquanto o layout permanece montado; não há nova preferência gravada no banco.

No celular, o botão abre o menu completo de 254 px, com fechamento pelo botão, Escape ou área externa. O foco fica no menu durante a abertura e retorna ao acionador ao fechar. O menu fechado fica oculto também para a navegação por teclado. A rolagem dos atalhos conserva o perfil e a saída acessíveis em telas baixas.

O símbolo vetorial branco em `public/mi-symbol-white.svg` é idêntico ao já usado no Workshop, derivado da marca original fornecida pelo usuário. A tela de login também usa o vermelho MI e esse símbolo; o botão Microsoft e o loader conservam seus fluxos anteriores.

O vermelho vivo é usado na faixa e nos ícones grandes. Os nomes pequenos do menu aberto ficam sobre o vermelho forte, que oferece contraste de 6,27:1 com branco. O texto do item ativo tem contraste de 5,86:1 na superfície clara. Os textos escuros sobre a faixa viva têm contraste de 4,54:1. Os estados operacionais e as cores de execução/prazo do Gantt continuam distintos da seleção da navegação.

## Validação

522 testes web e 116 mobile no CI Node 22 aprovado, dois contratos QR, tipos, build de produção e os dois smokes aprovados. O smoke também confere a presença do novo SVG no pacote standalone. QA com React/CSS reais: 12 cenários do Shell, 16 do Gantt e dois tamanhos da tela de login no servidor standalone, sem erros JavaScript ou requisições externas. Inclui modos compacto/expandido, sete atalhos, capacidades limitadas, foco, Escape, fechamento externo, contraste, rolagem, 390–1440 px e reflow equivalente a zoom de 200%.

Os cabeçalhos com nomes longos também foram conferidos em 720 px e no limite de 651 px, com menu expandido, sem overflow. Capturas desktop/mobile foram inspecionadas. Auditoria dos 82 JavaScripts do build contra dez segredos locais conhecidos sem ocorrências.

Esta alteração é visual e de apresentação da navegação. Nenhuma migração, escrita no Supabase, alteração de identidade, concessão de acesso ou publicação no serviço do Workshop foi realizada. Os projetos de demonstração e trabalhos offline não são modificados.

## Publicação

Consumidor `566f92908653fb609f16f89c37fa2cd24b5d9fa0`. Railway EM `9da20075-cfa8-4633-975c-1a85731a4314`, com **SUCCESS**, em 16/11/2026. [Portal EM](https://em-web-production.up.railway.app) e [CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/43953826731).

O login público em produção foi conferido em 1440 e 390 px: paleta e botão com as cores esperadas, SVG idêntico ao arquivo publicado, sem overflow ou erros JavaScript. O POST nativo de login continuou chegando à Microsoft, sem autenticar uma pessoa; somente o fluxo próprio de QA foi cancelado. A sessão, as capacidades e as políticas de acesso continuam sendo aplicadas no servidor.

Health 200 e 138 verificações de acesso aprovadas em produção: 118 recusas para anônimo/cookie forjado em 59 URLs e 20 recusas nas APIs. Não houve escrita de dados de negócio.

Evidências locais ignoradas: `desktop/.tmp/brand-shell-qa/{results,contrast}.json`, `.tmp/gantt-brand-qa/results.json`, `.tmp/mi-theme-login-proof.json`, `.tmp/mi-theme-browser-secret-audit.json`, `.tmp/mi-theme-environment-proof.json`, `.tmp/mi-theme-ci-proof.json`, `.tmp/mi-theme-deployment-proof.json`, `.tmp/mi-theme-public-{brand,qa,sso-qa}.json` e logs `.tmp/mi-theme-{tests,build,smoke,sso-smoke}.log`.

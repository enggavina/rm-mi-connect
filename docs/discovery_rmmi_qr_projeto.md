# QR Code de identificação do projeto — incremento 034

Discovery em 30/10/2026, baseline `f2e1207`, Supabase com 001–033. A consulta ao Bubble `rmmi`, versão `live`, leu somente metadata com `get_node`; não executou workflows, gerou QR remoto ou alterou dados/configurações. A ponte de saída continua desativada.

## Comportamento comprovado no Bubble Live

| Evidência | Configuração observada |
| --- | --- |
| Página `projeto` (`coiiy`), botão `cojuW0`, evento `cojvC0` | O botão Gerar QR Code aparece quando `Current Page ProjetoRM.qrcode_image` está vazio. |
| Ação `cojvs0`, Generate QR Code (Serverside) | O conteúdo codificado é `https://rm.miconnect.app.br/version-{AppVersion}/projeto_mobile/{CurrentPageItem._id}`. O identificador é o ID nativo Bubble; não é o número da OS nem o UUID Supabase. |
| Ação `cojvx0`, Make changes to ProjetoRM | Grava o retorno `URLQRCode` da ação anterior em `qrcode_image`. Esse campo, caption `qrcode`, é do tipo **image**. Logo, o legado `qrcode_url` é uma URL do arquivo de imagem, não o texto identificador a codificar novamente. |
| Página `projeto_mobile` (`cokxq`), Group All (`cokys`) | Lê um objeto `ProjetoRM` do caminho da URL. Não há resolução Supabase nesse caminho legado. |
| PageLoaded `colcW`, ação `colcc` | Se o usuário não estiver logado, redireciona para `index`, levando o unique ID obtido do caminho. Essa configuração demonstra o fluxo de login legado; não comprova, por si, a autorização por célula nem uma execução bem-sucedida. |

Evidências locais ignoradas pelo Git: `.tmp/discovery-project-qr/bubble-live-workflow.json` (nós completos do workflow) e `bubble-live-identity-fields.json` (campos e origem da página/grupo). São configuração estática, sem execução de ações no Bubble.

## Lacuna encontrada no mobile existente

No baseline, `mobile/src/domain/forms.ts` exportava `qrProjectValue`, que aceita UUID, OS e partes de URLs, e `mobile/src/ui/media.tsx` exportava `QrScanner`. Nenhum dos dois tinha consumidor em `mobile/app` ou `mobile/src`. A lista de projetos oferecia busca textual e abria `/projeto` com os parâmetros explícitos `celula` e `projeto`; o recebimento também não usava scanner ou resolvedor de QR.

`service.ts` e `database.ts` não continham resolução por QR/número/Bubble ID. `receivingPayload` apenas preserva campos legados opcionais `qr`/`projeto_id`; a RPC de recebimento recebe `p_projeto_id` já resolvido, com suas próprias guardas. Isso não forma uma jornada de leitura. Emitir uma imagem no portal, isoladamente, não permitiria ao APK 1.2.3/code 6 abrir o projeto por QR. A integração requer o novo runtime e a entrega do APK 1.2.4/code 7 pelo responsável da publicação.

O helper permissivo legado permanece preservado para não mudar contratos anteriores; a entrada nova não o utiliza.

## Contrato da etiqueta EM e resolução implementada

O payload novo contém **somente `rm_projetos.id`, UUID canônico de 36 caracteres em minúsculas**, com hífens. Não contém URL, número da OS, nome/cliente, Bubble ID, credencial, sessão, token ou célula. O servidor gera a imagem localmente; não reaproveita nem sobrescreve `qrcode_url` legado. A identificação não concede acesso.

O operador identifica-se e escolhe uma célula como antes. Na lista de projetos dessa célula, **Ler QR Code** abre a câmera; **Digitar código do projeto** oferece a mesma validação para colar o UUID da etiqueta quando a câmera não estiver disponível. URLs, números, texto adicional, maiúsculas e espaços são recusados, sem busca aproximada ou consulta global por aliases.

`mobile/src/domain/project-qr.ts` resolve apenas dados de `service.list`, isto é, o SQLite já existente. Reutiliza `resolveJourneyContext` e exige:

- Sessão do dispositivo e operador com política de células atual (versão 2), identificação de turno válida e célula explicitamente permitida; preserva a regra normal do administrador EM.
- Célula e projeto presentes no catálogo; projeto ativo segundo a jornada atual (sem entrega, cancelamento ou finalização para faturar).
- Exatamente uma alocação do par projeto+célula com `visibilidade === true` e `retirada !== true`. Duas alocações elegíveis são ambíguas e falham; alocações históricas retiradas e de outras células não selecionam contexto automaticamente.
- Mesmo proprietário de sessão, operador, permissões, célula, foco e revisão do catálogo antes/depois da leitura e imediatamente antes da navegação. Catálogo em sincronização não autoriza uma leitura parcial; a interface orienta tentar novamente quando terminar.

O sucesso navega exclusivamente à rota já existente `/projeto`, com `{ celula, projeto }`. Uma alocação bloqueada mantém a consulta normal; as permissões de edição continuam na jornada existente. Busca e abertura manual permanecem disponíveis.

Sem conexão, um projeto previamente carregado e permitido pode ser aberto. Projeto ausente, de outra célula, oculto, retirado, encerrado ou ambíguo produz uma mensagem genérica sem revelar seus metadados. O QR não inicia sincronização, faz RPC, salva recebimento, muda rascunhos/fotos, envia fila ou troca a autoria/protocolo de trabalho existente. Se o catálogo local estiver desatualizado, a leitura não tem como conhecer uma revogação ainda não recebida; as guardas de servidor existentes continuam determinando as mutações após reconexão. Não há promessa de revogação remota instantânea offline.

Cancelar, voltar do leitor, negar permissão ou falhar a câmera mantém a lista utilizável. O leitor invalida uma permissão pendente quando perde o contexto e permite tentar novamente ou digitar o código.

## Validação local desta implementação

`npm run typecheck` e `npm test` no diretório `mobile` passaram (99 testes, dos quais 12 novos para QR). Os testes cobrem UUID estrito; leitura offline sem alterar trabalhos; acesso/expiração/política; projeto ausente/de outra célula/oculto/retirado/encerrado; ambiguidades; consulta bloqueada; erro de SQLite sem vazar detalhes; mudança de operador, proprietário, célula, permissão, foco ou catálogo durante a leitura; e a guarda final antes de navegar.

A prova da imagem real SVG → decodificador independente → parser/resolução mobile pertence à validação conjunta do incremento. Os testes de domínio não comprovam leitura óptica em câmera física. A geração, assinatura, instalação e verificação do novo APK, assim como a publicação Railway, ficam registradas no relatório de entrega pelo responsável da publicação; este documento não declara essas etapas concluídas.

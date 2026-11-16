# Feedback de entrada e loader MI

O login corporativo agora informa imediatamente o envio em andamento, com o botão desabilitado e o loader da MI em primeiro plano. O símbolo usa a geometria original de `public/mi-electric-brasil.svg`: os arcos giram ao redor do centro original e somente as letras MI pulsam. A marca permanece vetorial; não há imagem remota ou dependência nova para a animação.

`MiLoader` é compartilhado com o login por senha, quando esse modo está habilitado, e com o carregamento das páginas do portal. Oferece status textual acessível e versão estática quando o sistema solicita movimento reduzido. A região de status fica fora do formulário marcado como ocupado, permitindo o anúncio imediato por leitores de tela.

O login Microsoft continua enviando um formulário nativo `POST /auth/sso/start`, com a política de referência `same-origin` e o redirecionamento existentes. A interface não substitui esse envio por fetch, não recebe tokens e não altera sessão, permissões ou provedor. Uma referência síncrona impede envios repetidos antes da atualização visual do botão.

Ao retornar pelo histórico com o documento em cache, `pageshow.persisted` restaura o estado de entrada. Um `pageshow` inicial tardio não libera outro envio enquanto a navegação está pendente. **Cancelar entrada** ou **Escape** interrompe a navegação nativa antes de restaurar o botão; a interface não envia uma segunda solicitação automaticamente. O login por senha conserva o ciclo de vida da Server Action e não oferece um cancelamento que apenas esconda uma requisição ainda em andamento.

Arquivos principais: `app/login/sso-login-form.tsx`, `app/login/login-form.tsx`, `app/login/page.tsx`, `app/(portal)/loading.tsx`, `components/web/login-progress.tsx`, `login-progress.module.css`, `mi-loader.tsx` e `mi-loader.module.css`.

A validação usa o navegador real com formulários e respostas locais controladas: envio nativo, headers, redirecionamento, envio único, retorno/erro/cancelamento, movimento reduzido e telas de 1240/390 px. A animação durante o POST é conferida com capturas do compositor; não se usa uma pausa na navegação real para inferir que ela está travada. Os testes de estado detalhados usam um observador de submit local, e os testes de integração do POST são executados separadamente.

Esta entrega é somente web, sem alteração de banco, migrações, contas ou aplicativo Android. O Bubble permanece somente leitura e a ponte de saída continua desativada.

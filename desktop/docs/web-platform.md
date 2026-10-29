# Portal web EM · MI Electric Brasil

Primeira entrega de gestão web, em 29/10/2026. O portal Next.js usa o mesmo projeto Supabase `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`) do aplicativo EM. O worker Bubble continua desativado; publicar a interface web não ativa a ponte nem envia emails.

## Áreas disponíveis

- **Visão geral:** contagens reais de projetos ativos, formulários em análise, células com prazo vencido e documentos; acesso aos projetos recentes e pendências.
- **Projetos:** busca, filtros por cliente/célula/status, paginação, criação e edição dos dados do projeto. Detalhe com informações do equipamento, células, registros, galeria, documentos privados, notas fiscais, comentários e aprovações já existentes.
- **Planejamento:** consulta das alocações e edição de prazos, responsável, horas, visibilidade, bloqueio e formulários. Nova alocação materializa apenas os modelos daquela célula e tipo de equipamento. O tipo não pode ser alterado depois da alocação; formulários já enviados não são removidos.
- **Cronograma:** janela de 42 dias, filtros e paginação, intervalos reais e identificação de prazos vencidos. Datas ausentes, inválidas ou fora do período são indicadas sem inventar barras.
- **Formulários:** consulta das respostas com seções recolhidas, imagens, assinaturas e histórico; aprovação ou devolução de questões específicas para correção pelo fluxo mobile existente. Respostas históricas sem questão continuam somente para consulta.
- **Cadastros:** consulta paginada de clientes, células, tipos de equipamento, equipe e modelos de formulário. A administração completa de cadastros, o construtor de formulários e o comercial são módulos posteriores.

A consulta e abertura dos documentos existentes estão nesta entrega. Geração/compilação de novos relatórios, orçamento comercial, laboratório e administração de contas não são apresentados como funcionalidades prontas. As rotas internas anteriores de relatórios/TOTP continuam reservadas e protegidas por Bearer; o login web usa a MFA nativa do Supabase quando há TOTP verificado.

## Acesso e autorização

O login utiliza email e senha da conta Supabase vinculada a um usuário RM ativo. Nesta entrega de gestão interna entram os perfis `administrador`, `padr_o` e `auditor`; clientes, operadores mobile e vendedores não ganham acesso ao portal de gestão por terem uma conta. Contas legadas sem vínculo `auth_user_id` não são provisionadas automaticamente. O administrador inicial existente pode acessar com as credenciais locais já provisionadas.

Sessões usam `@supabase/ssr`, cookies HttpOnly, SameSite Lax, Secure em produção e respostas privadas sem cache. O middleware Next 15 renova a sessão. Cada requisição é validada com `getUser` e perfil atual; TOTP cadastrado exige `aal2`. Logout POST verifica origem e encerra somente a sessão web (`scope:'local'`), preservando o tablet. O navegador não recebe a chave de serviço.

As leituras e downloads usam o JWT do usuário e as policies do banco. Dados sensíveis de `rm_private` nunca são consultados para montar a interface. As ações passam por `rm_web_mutate_v1` com autorização, recibo idempotente e `expected_updated_at` exato. Conflitos exigem uma nova leitura, sem sobrescrever silenciosamente as alterações de outro usuário ou operador. Retentativa após resposta de rede ambígua conserva o mesmo UUID e conteúdo.

Migrações necessárias: **001–015**. O contrato, as regras e os testes SQL estão em [WEB_MANAGEMENT.md](../../rm-mobile-supabase/WEB_MANAGEMENT.md). A 015 usa `PT409` para conflito de versão porque `40001` provoca retentativas transacionais no PostgREST, inadequadas para um conflito deliberado do usuário.

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

Para a aplicação web, definir no ambiente do servidor `SUPABASE_URL` e `SUPABASE_ANON_KEY`. O build funciona sem essas credenciais; a conexão é resolvida em runtime. `SUPABASE_SERVICE_ROLE_KEY`, tokens Bubble e segredos da ponte não são necessários ao serviço web e não devem ser adicionados por conveniência. `SYNC_OUTBOX_ENABLED=false` deve continuar desativado.

O Dockerfile usa Node 22, saída standalone e usuário não-root. O serviço web deve publicar `0.0.0.0:$PORT`; Railway fornece a porta. O healthcheck `/api/health` testa o processo, não a disponibilidade do banco. A configuração mantém `Root Directory=/desktop` quando a origem é o repositório completo; ao enviar somente a pasta desktop pela CLI, o Dockerfile e `railway.json` ficam na raiz do pacote enviado.

Publicação concluída em 29/10/2026: **[EM web](https://em-web-production.up.railway.app)**, no projeto Railway `em-mi-electric-brasil` (`472ac09b-a1b2-4b2f-b561-b43d0b471b06`), serviço `em-web` (`c26e7026-429b-4965-a8a0-b0c91a1665de`), ambiente `production` (`b6f8a871-027c-49eb-adac-43ad8586fbc9`). Os serviços de outros sistemas foram preservados.

Deploy `97c7230c-be56-4aeb-a93c-0eb34bcd36f7`, origem CLI a partir de `desktop/`, commit de aplicação `cd2e520`. A imagem usa Node 22 e o serviço recebeu somente URL/chave pública Supabase, porta e `SYNC_OUTBOX_ENABLED=false`; nenhuma chave de serviço ou token Bubble foi configurado. Esta primeira publicação não está conectada a autodeploy do GitHub. Uma conexão futura ao repositório deve usar Root Directory `/desktop`.

## Validação da entrega

- 61 testes desktop, TypeScript, build de produção e auditoria npm sem vulnerabilidades conhecidas.
- CI do commit de aplicação aprovado, incluindo os 84 testes mobile e o smoke de runtime web sem credenciais reais.
- Migrações 001–015 e quatro suítes PostgreSQL isoladas, incluindo planejamento, idempotência, conflitos, MFA e devolução web → correção mobile → aprovação web.
- Navegador Chrome local e no endereço Railway: login, cookie HttpOnly/Secure/SameSite, busca, abas de projeto, ampliação da galeria, abertura/cancelamento de editor, cronograma, consulta de 136 respostas, seleção para devolução sem submeter, leitura de PDF privado, cadastros, rejeição de criação vazia, navegação em 390 px e logout local. Nenhum erro de execução do navegador.
- Ambiente público sem sessão: login e health 200, painel redirecionando ao login e APIs de dados retornando 401. Os testes de navegador não aprovaram, devolveram ou editaram registros operacionais reais; operações positivas foram verificadas no PostgreSQL isolado.

Abas, filtros de query e paginação usam navegação HTTP para garantir a leitura atual da seleção. No runtime Next 15 instalado, a transição cliente de query atualizou o cache interno sem confirmar a interface; o fallback nativo foi reproduzido e validado. Login e MFA redirecionam diretamente a `/painel`, evitando a resposta intermediária da rota `/` em Server Actions. Retornos bem-sucedidos de edição/revisão também fazem uma leitura completa da tela atualizada.

Referências de implementação: [sessões SSR Supabase/Next](https://supabase.com/docs/guides/auth/server-side/creating-a-client?queryGroups=framework&framework=nextjs), [CLI Railway](https://docs.railway.com/guides/cli).

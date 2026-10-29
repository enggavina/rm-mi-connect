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

Não reutilizar os serviços de outros sistemas. O EM terá projeto e serviço próprios no Railway. O endereço e os identificadores efetivamente publicados serão registrados após o deploy e a verificação autenticada.

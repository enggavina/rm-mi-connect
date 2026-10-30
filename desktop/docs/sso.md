# SSO corporativo do EM

O portal usa Microsoft Azure pelo Supabase corporativo da Central de Acessos (`kxoriwvzmxhatzqcgnht`), aplicativo `em`. A base operacional continua no Supabase EM (`ellpxfbsrbhblyizvbbk`). O endereço do portal é https://em-web-production.up.railway.app. A Central administra concessões; sua interface atual não oferece um lançador de aplicativos.

## Identidades autorizadas

| Conta Microsoft | Perfil EM dedicado | Permissões na Central |
| --- | --- | --- |
| mgavina@mielectric.com.br | WEB-MGAVINA · administrador | 18 capacidades EM, incluindo cadastros, Engenharia, modelos de formulário e aprovações de etapas |
| softdev05@mielectric.com.br | WEB-SOFTDEV05 · administrador | As mesmas 18 capacidades EM; papel global da Central permanece `user` |

Esses vínculos foram aprovados explicitamente pelo solicitante. O login não cria usuários, não associa contas por email e não converte um papel corporativo em administrador RM. Os cadastros mobile anteriores, inclusive DIGITAL e o cadastro legado de Igor Nascimento, permanecem preservados.

O [plano de paridade](../../plano_paridade_rmmi_web.md) acrescentou cadastros, Engenharia, modelos de formulário e aprovações de etapas. O consumidor atual aceita **18 capacidades**, incluindo `em.approvals.read` e `em.approvals.decide`, e foi publicado antes do registro/concessão dessas novas permissões. Gestão de cadastros/modelos continua exigindo administrador RM; decisões de etapas seguem a autorização operacional existente do mobile, além da capacidade específica. Sessões anteriores com 12/14/16 capacidades continuam aceitas sem inferir permissões novas; as concessões são consultadas novamente em cada requisição.

A concessão atual foi aplicada após a migração 020, deploy `77018942-bc21-496a-8a0b-f1bd24b6b64d`, consumidor `ac4b3b4d9facb1e2242064390bd5adf0dd6ba679`, quatro negações públicas das duas rotas novas e [CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/40918576982). Resultado central: **18 funções ativas e 36 concessões EM**, 18 para cada administrador. A promoção anterior de `softdev05` teve autorização explícita e script separado com identidades exatas; não houve promoção global da Central. As demais aplicações, contas, identidades Auth, permissões e cadastros mobile foram preservados. Replay não criou auditorias adicionais; identidade trocada foi recusada. A auditoria registra operação técnica e o SHA real do consumidor, sem declarar login humano ou MFA pelo operador técnico.

## Fluxo e autorização

1. `POST /auth/sso/start` verifica a origem fixa do EM e cria PKCE S256. Um cookie opaco aponta para o fluxo cifrado, com validade de dez minutos.
2. O callback exato `/auth/sso/callback` consome o fluxo uma única vez. O servidor verifica o usuário no emissor corporativo, identidade Azure recente, cadastro ativo e concessões atuais do aplicativo `em`. TOTP corporativo verificado exige AAL2.
3. Um vínculo previamente aprovado de emissor/UUID corporativo resolve o UUID Auth local. O servidor gera e verifica um magic link sem enviar email, exclusivamente para esse UUID local. TOTP local, se cadastrado, também precisa ser confirmado; o MFA Microsoft não produz artificialmente AAL2 local.
4. O navegador recebe apenas `em-sso-session`, aleatório, HttpOnly, Secure em produção e SameSite Lax. Tokens ficam cifrados com AES-256-GCM no banco privado, sem refresh token persistido. A sessão dura no máximo uma hora, limitada também pelos dois tokens. A nova entrada usa novamente o SSO.
5. Cada requisição autenticada consulta novamente a identidade e as permissões da Central. Leituras usam o JWT local e RLS, com capacidades por domínio. Escritas exigem tanto a capacidade central quanto o perfil/regras locais. A ponte emite uma permissão SQL de uso único, vinculada à sessão, operação, UUID do envio e conteúdo, válida por até quinze segundos. Idempotência, autoria e conflitos PT409 permanecem no core existente.

Com `EM_SSO_ENABLED=true`, o formulário e a ação de login por senha do portal ficam desativados. Não existe fallback automático quando a Central está indisponível. O middleware também não renova a antiga sessão por senha nesse modo. Logout POST encerra somente as sessões deste acesso e remove seus cookies.

O controle central cobre o portal e suas ações. Credenciais e leituras legadas do aplicativo mobile continuam sujeitas às regras próprias do EM; esta entrega não muda o mecanismo offline nem promete revogação global desses acessos.

## Configuração e implantação

As variáveis estão em [.env.example](../.env.example). Além da URL/chave pública EM, configurar no servidor `EM_SSO_ENABLED`, `EM_CORPORATE_SUPABASE_URL`, `EM_CORPORATE_PUBLISHABLE_KEY`, `EM_CORPORATE_APP_SLUG`, `EM_PUBLIC_ORIGIN`, `EM_SSO_ENCRYPTION_KEY` e `EM_SSO_BRIDGE_SERVICE_ROLE_KEY`. As duas últimas são privadas e nunca recebem prefixo público. A chave da ponte é do projeto EM; nenhuma chave administrativa corporativa é usada no runtime do portal. O uploader do dossiê também usa essa chave somente no servidor para gravar/verificar objetos imutáveis no namespace derivado `rm-documentos/web-dossier/`; não a usa para executar mutações de negócio ou para buscar URLs arbitrárias. Reserva/finalização e downloads mantêm o JWT, a identidade e a autorização atual do usuário.

Aplicar 001–016, provisionar os vínculos e conferir o callback autorizado antes de ativar. A 016 inicia com `require_sso=false` para permitir implantação gradual. Após publicar o BFF com SSO ativo e validar o início do fluxo, ativar `rm_private.sso_settings.require_sso=true` por operação administrativa. Isso bloqueia escrita web legada sem permissão de sessão SSO; não altera a RPC mobile. O contrato SQL e a auditoria de provisionamento estão em [SSO_BRIDGE.md](../../rm-mobile-supabase/SSO_BRIDGE.md).

O worker Bubble permanece desativado (`SYNC_OUTBOX_ENABLED=false`). A publicação do EM não exige deploy da Central: registro, capacidades, concessões e callback foram operações administrativas específicas. O material reproduzível dessa integração está no [PR da Central](https://github.com/enggavina/mi-central-acessos/pull/1).

Publicação em 29/10/2026: deploy Railway `669d7c9b-14b5-4358-8dd9-0df2b41c125c`, commit de aplicação `0bd6793`, no serviço existente `em-web`. As sete variáveis SSO foram conferidas sem imprimir seus valores. O endpoint público confirmou login somente Microsoft, bloqueio do portal sem SSO e com cookie malformado, POSTs de outra origem recusados, callback restrito e início real PKCE S256 com redirecionamento ao `login.microsoftonline.com`. O fluxo de QA foi cancelado pelo logout e removido.

Atualização publicada: deploy `87aeb8cb-079c-432f-b2de-07a7075f2708`, commit `36075d1`. O primeiro teste do usuário revelou que `Referrer-Policy: no-referrer` na página de login fazia o Chrome enviar `Origin: null` no POST nativo. Login e tela MFA passaram a usar `same-origin` no header e metadata; as rotas `/auth/*`, inclusive o callback com código OAuth, mantêm `no-referrer`. A validação de origem permanece estrita e continua recusando `null` e origens externas. O teste Chrome com perfil vazio confirmou o clique real aceito pelo EM e a navegação até a Microsoft, sem preencher credenciais. Os dois smokes e os 97 testes passaram novamente, assim como o [CI da correção](https://github.com/enggavina/rm-mi-connect/actions/runs/40829078053).

## Verificação

Testes de política exercitam PKCE real do SDK, troca de identidade, emissor/audiência, conta revogada, permissões atuais, falhas de rede, MFA e payloads inválidos. Testes de HTTP cobrem origem, callback, destinos fixos e bloqueio da ação manual. A suíte PostgreSQL aplica 001–016 e verifica o isolamento dos RPCs privados, TTL, consumo, sessão/conteúdo divergentes, replay, MFA e preservação mobile. `npm run test:smoke` e `npm run test:sso-smoke` testam o servidor standalone sem credenciais reais. Um login Microsoft interativo completo exige a autenticação do titular da conta e deve ser registrado separadamente dos testes automatizados.

Na entrega, passaram 97 testes desktop, TypeScript, build, os dois smokes, cinco suítes PostgreSQL e auditoria npm sem vulnerabilidades. O [CI do commit de aplicação](https://github.com/enggavina/rm-mi-connect/actions/runs/40827656339) passou para web e mobile. A auditoria local não encontrou dez segredos conhecidos nos fontes nem chaves privadas nos 48 arquivos estáticos do navegador.

**Login completo confirmado pelo titular:** após a correção `36075d1`, o usuário entrou com `mgavina@mielectric.com.br` e confirmou que o painel abriu. A autenticação Microsoft foi realizada pelo próprio titular; nenhuma senha ou MFA foi automatizada. O teste SSO interativo de `softdev05` ainda não foi executado. Seu vínculo dedicado e a promoção posterior a administrador foram conferidos administrativamente com replay, teste de identidade divergente e hashes dos demais dados; isso não substitui login interativo. Papéis somente leitura continuam exercitados por fixtures sintéticas nos testes.

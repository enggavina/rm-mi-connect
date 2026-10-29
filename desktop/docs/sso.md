# SSO corporativo do EM

O portal usa Microsoft Azure pelo Supabase corporativo da Central de Acessos (`kxoriwvzmxhatzqcgnht`), aplicativo `em`. A base operacional continua no Supabase EM (`ellpxfbsrbhblyizvbbk`). O endereço do portal é https://em-web-production.up.railway.app. A Central administra concessões; sua interface atual não oferece um lançador de aplicativos.

## Identidades autorizadas

| Conta Microsoft | Perfil EM dedicado | Permissões na Central |
| --- | --- | --- |
| mgavina@mielectric.com.br | WEB-MGAVINA · administrador | Todas as 11 capacidades EM |
| softdev05@mielectric.com.br | WEB-SOFTDEV05 · auditor | Entrada e consultas; sem editar projetos, planejar ou revisar formulários |

Esses vínculos foram aprovados explicitamente pelo solicitante. O login não cria usuários, não associa contas por email e não converte um papel corporativo em administrador RM. Os cadastros mobile anteriores, inclusive DIGITAL e o cadastro legado de Igor Nascimento, permanecem preservados.

## Fluxo e autorização

1. `POST /auth/sso/start` verifica a origem fixa do EM e cria PKCE S256. Um cookie opaco aponta para o fluxo cifrado, com validade de dez minutos.
2. O callback exato `/auth/sso/callback` consome o fluxo uma única vez. O servidor verifica o usuário no emissor corporativo, identidade Azure recente, cadastro ativo e concessões atuais do aplicativo `em`. TOTP corporativo verificado exige AAL2.
3. Um vínculo previamente aprovado de emissor/UUID corporativo resolve o UUID Auth local. O servidor gera e verifica um magic link sem enviar email, exclusivamente para esse UUID local. TOTP local, se cadastrado, também precisa ser confirmado; o MFA Microsoft não produz artificialmente AAL2 local.
4. O navegador recebe apenas `em-sso-session`, aleatório, HttpOnly, Secure em produção e SameSite Lax. Tokens ficam cifrados com AES-256-GCM no banco privado, sem refresh token persistido. A sessão dura no máximo uma hora, limitada também pelos dois tokens. A nova entrada usa novamente o SSO.
5. Cada requisição autenticada consulta novamente a identidade e as permissões da Central. Leituras usam o JWT local e RLS, com capacidades por domínio. Escritas exigem tanto a capacidade central quanto o perfil/regras locais. A ponte emite uma permissão SQL de uso único, vinculada à sessão, operação, UUID do envio e conteúdo, válida por até quinze segundos. Idempotência, autoria e conflitos PT409 permanecem no core existente.

Com `EM_SSO_ENABLED=true`, o formulário e a ação de login por senha do portal ficam desativados. Não existe fallback automático quando a Central está indisponível. O middleware também não renova a antiga sessão por senha nesse modo. Logout POST encerra somente as sessões deste acesso e remove seus cookies.

O controle central cobre o portal e suas ações. Credenciais e leituras legadas do aplicativo mobile continuam sujeitas às regras próprias do EM; esta entrega não muda o mecanismo offline nem promete revogação global desses acessos.

## Configuração e implantação

As variáveis estão em [.env.example](../.env.example). Além da URL/chave pública EM, configurar no servidor `EM_SSO_ENABLED`, `EM_CORPORATE_SUPABASE_URL`, `EM_CORPORATE_PUBLISHABLE_KEY`, `EM_CORPORATE_APP_SLUG`, `EM_PUBLIC_ORIGIN`, `EM_SSO_ENCRYPTION_KEY` e `EM_SSO_BRIDGE_SERVICE_ROLE_KEY`. As duas últimas são privadas e nunca recebem prefixo público. A chave da ponte é do projeto EM; nenhuma chave administrativa corporativa é usada no runtime do portal.

Aplicar 001–016, provisionar os vínculos e conferir o callback autorizado antes de ativar. A 016 inicia com `require_sso=false` para permitir implantação gradual. Após publicar o BFF com SSO ativo e validar o início do fluxo, ativar `rm_private.sso_settings.require_sso=true` por operação administrativa. Isso bloqueia escrita web legada sem permissão de sessão SSO; não altera a RPC mobile. O contrato SQL e a auditoria de provisionamento estão em [SSO_BRIDGE.md](../../rm-mobile-supabase/SSO_BRIDGE.md).

O worker Bubble permanece desativado (`SYNC_OUTBOX_ENABLED=false`). A publicação do EM não exige deploy da Central: registro, capacidades, concessões e callback foram operações administrativas específicas. O material reproduzível dessa integração está no [PR da Central](https://github.com/enggavina/mi-central-acessos/pull/1).

## Verificação

Testes de política exercitam PKCE real do SDK, troca de identidade, emissor/audiência, conta revogada, permissões atuais, falhas de rede, MFA e payloads inválidos. Testes de HTTP cobrem origem, callback, destinos fixos e bloqueio da ação manual. A suíte PostgreSQL aplica 001–016 e verifica o isolamento dos RPCs privados, TTL, consumo, sessão/conteúdo divergentes, replay, MFA e preservação mobile. `npm run test:smoke` e `npm run test:sso-smoke` testam o servidor standalone sem credenciais reais. Um login Microsoft interativo completo exige a autenticação do titular da conta e deve ser registrado separadamente dos testes automatizados.

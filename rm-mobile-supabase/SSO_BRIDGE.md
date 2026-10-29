# Ponte SSO web — migração 016 ativa em produção

Estado: **016 aplicada e SSO obrigatório ativado em produção em 29/10/2026** no projeto `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`), com histórico 001–016 e `rm_private.sso_settings.require_sso=true`. A migração foi inicialmente aplicada com o valor falso; a ativação ocorreu somente após implantação e verificação pública do BFF. Nenhum vínculo ou usuário é criado pelo SQL da migração; o provisionamento administrativo separado dos dois usuários autorizados foi concluído antes da ativação.

## Identidade e fronteiras

Emissor único: `https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1`. Aplicativo central: `em`. O BFF valida a sessão corporativa e `cp_my_permissions_v1` a cada ação; emissor, sujeito e aplicação devem corresponder exatamente. Permissões ausentes, expiradas ou indisponibilidade negam acesso. `app_access` não concede capacidades de gestão. Email, nome, metadata editável e `app_role` não vinculam identidades nem concedem perfil RM.

`rm_private.sso_identity_bindings` associa explicitamente `issuer + subject` a `rm_user_id + auth_user_id`, ambos únicos e previamente existentes. Vínculo começa desativado; ativação exige `approved_by` e `approved_at`. A resolução exige perfil web ativo (`administrador`, `padr_o` ou `auditor`) e correspondência atual entre os UUIDs RM/Auth. Não há RPC pública de criação/ativação de vínculo. Provisionamento administrativo é separado do callback.

O BFF armazena somente um identificador aleatório opaco no cookie `HttpOnly/Secure/SameSite`; os RPCs recebem seu SHA256 hexadecimal. Tokens corporativos e EM ficam em envelope AES-GCM cifrado com chave do servidor. A chave nunca entra no banco. O SQL trata o envelope como texto opaco; **a criptografia é responsabilidade do BFF**, incluindo nonce único, versão de chave e autenticação do contexto. Nenhuma RPC retorna token ao navegador. As operações de negócio continuam usando chave pública + JWT EM, com RLS, perfis e MFA existentes.

## RPCs de infraestrutura

Todas as funções abaixo são `SECURITY DEFINER`, `search_path=''` e têm EXECUTE **exclusivamente para `service_role`**. `anon` e `authenticated` não podem chamá-las. As tabelas privadas também não possuem acesso direto por esses papéis nem por `service_role`.

| Função e parâmetros exatos | Retorno |
| --- | --- |
| `rm_sso_binding_v1(p_issuer text,p_subject uuid)` | `{binding_id,rm_user_id,auth_user_id,profile}` ou `null` |
| `rm_sso_flow_put_v1(p_hash text,p_ciphertext text,p_expires_at timestamptz)` | `void` |
| `rm_sso_flow_take_v1(p_hash text)` | `ciphertext` string ou `null` |
| `rm_sso_flow_get_v1(p_hash text)` | `ciphertext` string ou `null`, leitura sem consumo para MFA pendente |
| `rm_sso_session_put_v1(p_hash text,p_binding_id uuid,p_local_session_id uuid,p_ciphertext text,p_expires_at timestamptz)` | `void` |
| `rm_sso_session_get_v1(p_hash text)` | `{ciphertext,binding_id,rm_user_id,auth_user_id,local_session_id,expires_at,issuer,subject,profile}` ou `null` |
| `rm_sso_session_delete_v1(p_hash text)` | `void` |
| `rm_sso_action_permit_v1(p_session_hash text,p_submission_id uuid,p_operation text,p_payload jsonb,p_capability text)` | `void` |

`profile` tem `{id,nome,perfil,cargo,matricula}` obtido do cadastro RM atual. Hashes têm exatamente 64 caracteres hexadecimais minúsculos. Ciphertext é string opaca com tamanho entre 16 e 65.536 bytes. Datas são UTC/ISO com fuso. Não imprimir envelopes, tokens, identificadores de cookie ou código PKCE em logs.

Fluxo OAuth: expiração futura de no máximo **10 minutos**. `put` rejeita hash duplicado; `take` remove atomicamente antes de retornar, inclusive removendo fluxo expirado (retorna `null`). Repetir `take` não recupera o fluxo. `put` também elimina fluxos já expirados.

`flow_get` permite ao Server Component consultar o estado de MFA pendente sem consumir o envelope. Exige o mesmo papel de servidor e devolve `null` após expiração/consumo. A conclusão do fluxo continua usando `take`; o navegador nunca recebe o envelope.

Sessão BFF: expiração futura de no máximo **1 hora** a partir da gravação, além do limite mais curto dos tokens que o BFF deve aplicar. Pode renovar o ciphertext/expiração do mesmo hash e mesmo vínculo/sessão Auth. Não pode transferir hash entre identidades/sessões. `local_session_id` precisa existir em `auth.sessions` e pertencer ao Auth vinculado. `get` exige sessão não expirada e vínculo/RM ainda ativos. `delete` elimina também suas permissões pendentes; não executa logout global nem revoga o tablet. O BFF deve fazer logout `scope:'local'` nas duas sessões quando apropriado. Sessões expiradas ficam inacessíveis; a limpeza de retenção de registros expirados pode ser executada por operação administrativa dedicada.

## Permissões de ação

O BFF só chama `rm_sso_action_permit_v1` **depois** de validar a identidade corporativa e a capacidade atual. A RPC privada não consulta a Central e não transforma o texto `p_capability` em prova: confia exclusivamente no componente de servidor autorizado a chamá-la.

| Operação | Capacidade exata |
| --- | --- |
| `save_project` | `em.projects.manage` |
| `plan_cell` | `em.planning.manage` |
| `review_form` | `em.forms.review` |
| `save_catalog`, `delete_catalog` | `em.catalogs.manage` |
| `save_engineering`, `save_photo_title` | `em.engineering.manage` |
| `create_form_template`, `save_form_template`, `publish_form_template` | `em.form_templates.manage` |
| `transition_stage_approval` | `em.approvals.decide` |

O estado atual, após 020, tem onze operações e dezoito capacidades corporativas no consumidor. As duas novas capacidades `em.approvals.read/decide` foram registradas/concedidas somente após migração, deploy Railway `77018942-bc21-496a-8a0b-f1bd24b6b64d` e CI `40918576982` aprovados. A Central contém 18 funções e 36 concessões EM, 18 para cada administrador nominal, sem promoção global de SOFTDEV05.

A permissão dura no máximo **15 segundos**, limitada também pela expiração da sessão. Fica vinculada ao hash de sessão BFF, UUID de envio, operação e SHA256 de `p_payload::jsonb::text`, calculado no banco. O BFF envia o mesmo objeto à emissão e à mutação. JSONB normaliza ordem das chaves; não calcular um hash independente com `JSON.stringify`.

Reemitir a mesma permissão ainda pendente exige os mesmos dados e uma nova validação central pelo BFF. Um UUID pendente com outra sessão/operação/payload falha com `23505`. Não renovar permissões por rotina, cache positivo ou repetição automática sem decisão central atual.

## Wrapper de negócio e ativação

O core atual é movido para `rm_private.web_mutate_core_v1(uuid,text,jsonb)` e seu EXECUTE é revogado dos clientes, inclusive `service_role`. O contrato público `rm_web_mutate_v1` permanece igual. Seu wrapper verifica vínculo, sessão Auth indicada por `auth.jwt()->>'session_id'`, expiração, operação, UUID e hash do payload; consome a permissão na mesma transação do core. O core mantém autor por `auth.uid()`, perfil, MFA/AAL2, validações, PT409 e idempotência.

Mesmo um replay idempotente exige permissão nova, obtida após revalidar a Central. A ausência, expiração, sessão divergente ou payload adulterado geram `42501`. Se o core falhar, consumo e mutação são revertidos juntos; a permissão nunca autoriza outro conteúdo. Uma ação já autorizada pode concluir dentro da janela máxima de 15 segundos; isso não constitui revogação central instantânea de transações em andamento.

Com `require_sso=false`, apenas contas **sem nenhum vínculo SSO** mantêm a escrita web legada. Contas vinculadas, inclusive vínculos desativados ou UUID Auth divergente, não caem nesse caminho. Com `require_sso=true`, **toda** escrita web exige permissão SSO, inclusive a conta DIGITAL. Nenhuma mudança ocorre em `rm_mobile_mutate_v1`, delegações offline, leitura RLS ou credenciais do tablet. Esta arquitetura não promete revogar globalmente acessos legados/mobile às leituras públicas autorizadas por RLS.

## Provisionamento autorizado concluído

Foram aprovados dois perfis **web dedicados**, sem rebaixar/remapear cadastros mobile:

- `mgavina@mielectric.com.br` (Mauricio Gavina, nome conferido no cadastro autorizado): sujeito corporativo `01316705-7361-459f-ba3b-9971777aa607`; novo RM `administrador`, matrícula `WEB-MGAVINA`.
- `softdev05@mielectric.com.br` (Igor Nascimento, nome conferido no cadastro autorizado): sujeito corporativo `a9e45880-1924-4b2d-a2b1-dc12fd029bff`; RM dedicado `WEB-SOFTDEV05`, inicialmente auditor e promovido a **administrador do EM** em 29/10/2026 por novo pedido explícito do usuário. A promoção não altera a administração global da Central.

O email Auth local é `em-sso-<subject>@identity.invalid`, confirmado pela API administrativa, sem email enviado ou senha informada/distribuída. O email corporativo serve apenas como display do novo RM. O legado softdev05 é administrador mobile e permanece intacto; DIGITAL também permanece intacto. O callback nunca faz esse provisionamento.

| Perfil web | RM UUID | Auth UUID | Vínculo UUID |
| --- | --- | --- | --- |
| WEB-MGAVINA / administrador | `e80d9dd1-372c-40fc-a980-fe00067806df` | `54dd446f-d458-42cf-9f7c-b826aab87b51` | `cf815974-5d88-4e5c-8639-71139300ea1a` |
| WEB-SOFTDEV05 / administrador | `2e70c7e9-3ed2-47fa-9860-9501aeac96cc` | `7dfa16ac-55ac-4631-b138-7b1c1234ca6a` | `ae29e9a9-9c50-4d25-81eb-6a01202bc20a` |

`approved_by` usa o administrador DIGITAL como **ator técnico do bootstrap**, por instrução explícita, sem simular autenticação humana. `approval_metadata` registra `approved_by_kind=technical_bootstrap_actor`, `authorization_source=explicit_user_request`, método administrativo e login autorizado. A aprovação não depende de claims recebidos no callback.

Antes/depois foram preservados localmente em `.tmp/sso-provisioning-016-before.json` e `.tmp/sso-provisioning-016-after.json`, ignorados pelo Git e sem tokens, senhas ou links. Os hashes de **todos os 100 registros RM preexistentes permaneceram iguais**; somente dois perfis novos foram acrescentados. Reexecução administrativa confirmou os mesmos UUIDs sem duplicar nem sobrescrever vínculos. A conta Auth inicial permaneceu vinculada ao DIGITAL.

QA da primitiva EM: para cada identidade nova, `auth.admin.generateLink(type:'magiclink')` seguido de `verifyOtp(type:'magiclink',token_hash)` produziu o Auth UUID esperado, perfil RM correto, JWT AAL1 e `session_id` existente em `auth.sessions`. Isso valida somente a ponte Auth local, **não simula login Microsoft nem atesta o SSO corporativo completo**. Logout usou `scope:'local'`; nenhum token/hash/link foi impresso e nenhum projeto ou formulário foi alterado. Resultado não secreto em `.tmp/sso-auth-primitive-result.json`.

Ativação: [scripts/activate_web_sso.sql](scripts/activate_web_sso.sql) foi executado remotamente com `SET LOCAL em.sso_bff_verified='true'` na mesma transação, após verificar o BFF em produção, callback e concessões centrais. O script conferiu 016, os dois vínculos e as permissões RPC antes de ativar `require_sso=true`. O teste local confirma que sua execução acidental sem essa marca é recusada.

## Validação da implantação e estado final

Deploy Railway `669d7c9b-14b5-4358-8dd9-0df2b41c125c` concluído com sucesso no commit `0bd6793`. CI `40827656339` passou para web e mobile; a entrega registrou 97 testes desktop, build e dois smoke tests aprovados.

A QA HTTP pública confirmou: login somente Microsoft, portal negado sem SSO, cookie forjado negado, POST de outra origem recusado com 403, callback estrito, cookie de fluxo opaco com Secure/HttpOnly/SameSite=Lax, PKCE S256, redirecionamento real Supabase corporativo → `login.microsoftonline.com` e consumo do fluxo pelo logout. Prova local sem segredos: `.tmp/public-sso-qa.json`.

Após a ativação, a consulta de conferência registrou `require_sso=true`, exatamente dois vínculos ativos, **zero sessões BFF, zero fluxos pendentes, zero permissões de ação e zero mutações web de negócio**. DIGITAL continuou ativo, administrador e associado ao mesmo Auth UUID; o gateway mobile manteve EXECUTE autenticado. O core privado, a emissão de permissões e as tabelas de sessão permaneceram indisponíveis aos clientes. Prova local: `.tmp/sso-strict-activation-proof.json`.

A correção posterior `36075d1` foi publicada no deploy Railway `87aeb8cb-079c-432f-b2de-07a7075f2708`, com CI `40829078053` aprovado. Ela ajustou a política de referência das páginas de login/MFA para que o formulário nativo envie a origem correta, preservando a validação CSRF estrita. O clique nativo em Chrome sem credenciais passou a receber 303 e seguir até Microsoft.

Em 29/10/2026, após esse deploy, o titular de **mgavina confirmou o login Microsoft completo e a abertura do painel**. A consulta final, somente leitura, confirmou `require_sso=true`, `WEB-MGAVINA` com perfil `administrador`, status ativo, vínculo ativo e **duas sessões BFF vigentes**. Nenhuma dessas sessões legítimas foi removida ou alterada; hashes, tokens e ciphertext não foram exibidos.

O login SSO interativo real de **softdev05 ainda não foi executado**. A promoção posterior a administrador do EM foi conferida administrativamente nos dois bancos, com replay idempotente e comparação dos demais perfis, identidades, permissões, vínculos de tablet, credenciais e outbox. O papel global da Central permaneceu `user`; somente o papel do aplicativo EM e o perfil RM dedicado passaram a administrador. O [script de promoção](scripts/promote_approved_web_administrator.sql) mantém rollback como padrão. A auditoria registra a autorização explícita e o ator técnico, sem afirmar login humano ou MFA; não substitui a autenticação interativa pelo titular.

## Validação local

A validação inicial do SSO aplicou 001–016 em PostgreSQL isolado e executou cinco suítes. `sso_bridge.sql` cobre vínculos explícitos, papéis de execução, TTLs, leitura não consumidora para MFA, fluxo de uso único, corpo/sessão divergentes, consumo e replay, expiração, MFA com permissão válida, vínculo desativado sem fallback, modo global e preservação da leitura mobile. A validação atual de `tests/run-local-tests.ps1` aplica **001–020 e nove suítes**, acrescentando cadastros, Engenharia, [construtor de formulários](WEB_FORM_TEMPLATES.md) e [aprovações de etapas](WEB_STAGE_APPROVALS.md). Inclui concorrência web/mobile nos dois sentidos, mesmo UUID simultâneo, upgrade com dados preservados e compatibilidade com envios/revisões offline antigos. O bloqueio da ativação sem marca de prontidão permanece testado. Nenhuma fixture ou mutação de negócio de QA foi inserida no ambiente remoto.

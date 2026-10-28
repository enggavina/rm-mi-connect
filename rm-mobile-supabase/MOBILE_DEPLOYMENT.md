# EM · MI Electric Brasil — Banco para a Fase 1 mobile

## Projeto provisionado em 27/10/2026

Foi criado, por solicitação do usuário, o projeto **[oficina-em-mi-off](https://supabase.com/dashboard/project/ellpxfbsrbhblyizvbbk)** (`ellpxfbsrbhblyizvbbk`) na organização MI Electric Brasil de plano **Pro** (`rdqixfbnsgawcgrvqegw`), região **São Paulo / sa-east-1**, compute **Micro**, sem adicionais. Nenhum projeto anterior foi alterado.

As migrations **001..010 foram aplicadas**, com cada migration e seu registro em `supabase_migrations.schema_migrations` na mesma transação. A instalação começou em banco vazio; a 009 corrigiu a ordenação fracionária identificada durante a carga real. A verificação encontrou **52 tabelas RM, todas com RLS**, os três buckets e as policies de mídia. A API negou leitura operacional anônima com HTTP 401; execução direta de RPCs legadas, acesso às credenciais privadas e operação da ponte também estão restritos.

Os arquivos locais `.env` de mobile, desktop e infraestrutura foram configurados e estão ignorados pelo Git. O mobile contém apenas URL e chave pública. Senha do banco e chaves de serviço ficam apenas nos arquivos de servidor/infraestrutura. Não foram inseridos dados operacionais fictícios. A conta inicial real descrita abaixo foi provisionada a pedido do usuário. Consulte os relatórios de ETL para o estado atual da carga do catálogo Bubble.

## Conta inicial real

Foi criada a conta **digital@mielectric.com.br** com perfil RM `administrador`, matrícula de operador **DIGITAL** e perfil de assinatura `aprovador_supervis_o`. O mesmo registro real representa a conta inicial de supervisor/tablet e a identidade inicial do operador, com **senhas diferentes** para cada etapa. O usuário não estava entre os 99 usuários consultados no Bubble; um futuro vínculo pelo email deve preservar `auth_user_id` e a credencial privada local.

As credenciais geradas estão somente no arquivo local **`rm-mobile-supabase/.env.initial-admin`**, ignorado pelo Git. Na tela de login, usar `ADMIN_EMAIL` e `ADMIN_PASSWORD`; na identificação de operador, usar `OPERATOR_MATRICULA` e `OPERATOR_PALAVRA_CHAVE`. As senhas não foram publicadas nem enviadas por email. No banco, a palavra-chave está armazenada em bcrypt no schema privado, sem cópia em texto claro.

Foram verificados login real no Supabase Auth, leitura do vínculo RM ativo e identificação pela RPC com emissão de delegação para o operador correto. A verificação não criou projetos, formulários, fotos ou itens de sincronização.

## Ordem de instalação em outro ambiente

Aplicar **001 até 010, em ordem**, pelo SQL Editor ou pipeline de migrations. O aplicativo depende da 006, o worker depende da 007, a 008 completa a publicação Realtime e a 009 preserva índices fracionários dos catálogos; não usar apenas 001..005. O script de testes descrito abaixo sempre usa um cluster local isolado e não configura o Supabase remoto.

- `006_rm_mobile_delegation_and_idempotency.sql` mantém os contratos legados e restringe sua execução direta ao backend. A conta autenticada do tablet chama `rm_authenticate_operator_v1`, recebe `operator_token` e `token_expires_at` (sete dias) e envia mutações por `rm_mobile_mutate_v1`. A chave UUID de envio deve permanecer a mesma em toda retentativa. O servidor valida operador, dispositivo, célula e permissão de aprovação; impede duplicação mesmo se a resposta se perder após o commit. A função também valida respostas obrigatórias, preserva N/A, permite limpar campos em revisão e atualiza IDs das opções selecionadas.
- `007_rm_bridge_leases_and_checkpoints.sql` adiciona checkpoints duráveis, exclusão entre workers, claims por evento, recuperação após queda, retentativa exponencial e `dead_letter` após o limite. Somente `service_role` pode operar a ponte.
- `008_rm_realtime_mobile_catalogs.sql` publica as 17 tabelas consumidas pelo mobile, incluindo definições de formulários, questões, títulos de fotos e projetos. A 004 publicava somente os registros de execução; a 008 permite que mudanças no catálogo também acionem o pull automático.
- `009_rm_fractional_question_indices.sql` converte `indice` para `numeric` em questões, itens, respostas e rascunhos, preservando valores como `1.5` e `156.5` encontrados na origem. Corrige os casts das RPCs de importação e envio sem mudar assinaturas ou permissões. A suíte local verificou importação, submissão com questão `1.5` e revisão da resposta sem arredondamento.
- `010_rm_operator_cell_permissions.sql` corrige o escopo por operador: usa `identidade_id` do cadastro, remove a alteração destrutiva dos vínculos no login e impede herança de permissões administrativas da conta compartilhada. A nova RPC de contexto atualiza permissões sem renovar o turno offline. Os 181 vínculos foram preservados; veja [evidência do cadastro e validação](OPERATOR_CELL_PERMISSIONS.md).
- Foi corrigido em `005` o literal de perfil `Administrador` para a chave existente `administrador`. O original não compilava em PostgreSQL porque esse valor não existe no enum de `001`.

## Provisionamento

1. Criar a conta de supervisor/dispositivo no **Supabase Auth**. Vincular seu `auth.users.id` em `public.rm_users.auth_user_id`, com `status='ativo'`.
2. Importar operadores, clientes, tipos, células, formulários, questões e vínculos pelo ETL. As palavras-chave ficam exclusivamente em `rm_private.user_credentials`; nunca incluir uma chave `service_role` no mobile. Credenciais legadas são convertidas para bcrypt no primeiro login bem-sucedido.
3. Cadastrar as células permitidas para o **operador** em `rm_tablet_celula_users.identidade_id/celula_id`. `usuario_id` identifica a conta de login do tablet e não concede suas permissões aos operadores. O login preserva o cadastro. Somente o próprio operador com `perfil='administrador'` tem acesso administrativo a todas as células. `rm_celulas_projeto.forms_ids` deve conter os formulários disponíveis no projeto e célula selecionados.
4. Configurar aprovadores por etapa em `aprovador_id`, `aprovadores_ids` e `aprovadores_retorno_ids`. Sem atribuição específica, os perfis de assinatura canônicos `aprovador` e `aprovador_supervis_o` podem aprovar. Um operador comum não pode aprovar apenas porque usa um tablet compartilhado.
5. Os uploads usam `auth.users.id/arquivo` no bucket `rm-fotos` ou `rm-assinaturas`. As policies da 006 restringem gravação à pasta da conta autenticada. Os buckets de imagem permanecem públicos conforme a 004 original; as URLs são duráveis para o Bubble/relatórios. Uma política de mídia privada exige adaptar o consumo dos relatórios e emitir URLs temporárias na leitura.
6. A identificação inicial e o primeiro download exigem internet. Offline usa credencial derivada no armazenamento seguro, com prazo menor que a delegação. Ao expirar uma delegação pendente, identificar novamente **o mesmo operador** permite retomar a fila com o novo token e o mesmo UUID, sem trocar a autoria.

Falhas de identificação retornam `{ authenticated: false, error, retry_after_seconds? }`, em vez de lançar uma exceção, para que o contador de tentativas persista na transação. Cinco falhas bloqueiam novas tentativas daquela conta de dispositivo por quinze minutos. Erros de autorização ou mutação retornam erros RPC normais.

`p_params.p_projeto_id` é opcional no recebimento: ausente cria um projeto; presente atualiza atomicamente projeto, equipamento e fotos vinculados ao QR lido. A atualização exige um operador administrador, vínculo cadastrado entre o operador e uma célula do projeto, ou que o operador seja o criador do recebimento. `p_qrcode_value` opcional é registrado como comentário de auditoria. O campo de imagem de QR do projeto não é sobrescrito por texto do leitor.

Para revogar uma delegação perdida, o administrador pode marcar `rm_private.operator_delegations.revoked=true` pelo backend/SQL administrativo. Desativar operador ou conta de tablet também bloqueia suas mutações. Não expor essas tabelas via PostgREST.

## Validação local

Com PostgreSQL instalado e seus binários no PATH:

```powershell
powershell -ExecutionPolicy Bypass -File rm-mobile-supabase/tests/run-local-tests.ps1
```

O script cria um cluster temporário ligado somente a `127.0.0.1`, em porta livre, aplica todas as migrations com stubs locais de Auth/Storage, executa testes de comportamento e remove o cluster ao terminar. Os testes cobrem autorização, isolamento de dispositivo, policies de mídia, criação/atualização por QR, idempotência, respostas obrigatórias, correção em revisão, lockout e recuperação do worker. Os stubs verificam PostgreSQL e policies; não substituem uma homologação com Supabase Auth, Storage e Realtime reais nem um teste em tablet.

No Supabase real, o teste de Storage com a conta inicial enviou a imagem `icon.png` (43.042 bytes) à pasta da própria conta e leu sua URL com HTTP 200, confirmando bytes idênticos. O envio em pasta de outra identidade foi negado com HTTP 403. O único objeto de QA foi removido após o teste, com ausência confirmada nos metadados; nenhum objeto operacional ou outbox foi alterado. A publicação Realtime foi conferida para todas as tabelas de pull do mobile.

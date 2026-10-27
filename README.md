# RM · MI Connect

Fase 1 da recriação do RM: aplicativo operacional nativo em Expo SDK 54 e estrutura do backend/desktop em Next.js 15. As aplicações têm instalações, dependências e builds separados.

Repositório privado: [enggavina/rm-mi-connect](https://github.com/enggavina/rm-mi-connect).

| Diretório | Conteúdo |
| --- | --- |
| `mobile/` | SQLite, autenticação do tablet e operador, mídia persistente, sincronização e oito vistas operacionais |
| `desktop/` | Next.js, APIs protegidas, worker Bubble/Supabase, ETL e Docker/Railway |
| `rm-mobile-supabase/` | Migrações, contratos, schema offline original e testes PostgreSQL |

## Mobile

O mobile e seus testes requerem Node 22.13+; o desktop usa Node 20.19+. O build Android local exige SDK/JDK, ou EAS Build para compilação remota.

```sh
cd mobile
npm ci
# Copiar .env.example para .env e preencher URL/chave pública Supabase.
npm start
npm run typecheck
npm test
npm run export:native
```

Para gerar APK corporativo com EAS, configure sua conta/projeto Expo e execute `npx eas-cli build --platform android --profile preview`. O perfil `production` gera AAB. Para build local, `npx expo prebuild --platform android` gera o projeto nativo e `npm run android` compila/instala a versão de desenvolvimento. iOS exige macOS/Xcode ou EAS. As credenciais de assinatura de distribuição devem ser configuradas pela equipe; nunca entram no Git.

Nesta estação foi gerado `artifacts/rm-mi-connect-internal.apk` (65,5 MiB), já configurado para o novo Supabase: Android 7+, ARM64/x86_64, pacote `br.com.mielectric.rmconnect`, versão 1.0.0. O APK usa assinatura Android Debug e destina-se à homologação interna. O arquivo fica fora do Git. O build Android e os bundles Android/iOS passaram; câmera, assinatura e operação offline ainda precisam de homologação em um tablet real. As credenciais iniciais estão no arquivo local `rm-mobile-supabase/.env.initial-admin`; consulte o [provisionamento](rm-mobile-supabase/MOBILE_DEPLOYMENT.md).

O primeiro login e a primeira identificação de cada operador precisam de conexão. Depois, o catálogo e os rascunhos permanecem no SQLite; palavras-chave são verificadas por PBKDF2 em cache protegido pelo SecureStore, válido por 24 horas. A identidade da fila é preservada ao trocar de operador. A delegação do servidor dura até 7 dias; um item vencido exige nova identificação do responsável, sem apagar o trabalho. A sincronização automática funciona com o app aberto ou ao voltar ao primeiro plano: sistemas móveis não garantem execução contínua com o app encerrado.

Vistas: `celula`, `registro-form`, `revisao-form`, `recebimento`, `aprovacao`, `confirmacao`, `formularios` e `peritagem`. Há também `login` e `identify`. Intervalos de datas/horas usam os subtipos reais do SQL; os rótulos visuais não substituem slugs como `direcionado` e `em_an_lise`.

Fotos são copiadas para armazenamento persistente e comprimidas. A fila envia mídia antes de qualquer RPC, substitui referências locais e usa UUID fixo para repetição idempotente. Falhas permanecem visíveis e recebem retry exponencial. Catálogos são atualizados por paginação incremental; reconciliação de IDs remove registros remotos apagados sem apagar rascunhos nem a fila.

## Banco e integração

O ambiente inicial está no projeto **[oficina-em-mi-off](https://supabase.com/dashboard/project/ellpxfbsrbhblyizvbbk)**, criado na organização Pro, região São Paulo, com compute Micro. As migrações 001–009 já foram aplicadas e as 52 tabelas RM estão protegidas por RLS. Os arquivos `.env` locais apontam para esse ambiente e permanecem fora do repositório.

A carga inicial contém 177 projetos operacionais e seus catálogos. O [relatório da carga](desktop/docs/initial-load.md) detalha volumes, registros legados pendentes e condições para ativar a coexistência. O worker permanece desativado; o desktop está preparado como scaffold para a próxima etapa.

Aplicar as migrações **001 a 009**, em ordem, em ambiente previamente conferido. As cinco primeiras preservam o modelo recebido. `005` contém uma correção necessária: o enum é `administrador`, e não `Administrador`. `006` acrescenta autenticação delegada, limitação de tentativas, permissões de mídia e idempotência para todas as mutações. `007` acrescenta leases, checkpoints e recuperação de falhas do worker. `008` publica no Realtime as 17 tabelas de catálogo/execução consumidas pelo mobile, incluindo formulários, questões e títulos de fotos. `009` preserva os índices fracionários usados na ordenação de questões e opções no Bubble, inclusive no envio e na revisão de respostas.

As RPCs originais são chamadas pelo gateway `rm_mobile_mutate_v1`; o aplicativo não recebe a chave `service_role`. Uma autorização de dispositivo não autoriza forjar outro operador. Campos obrigatórios, revisão e permissão de aprovação também são validados no servidor.

O pacote original configura `rm-fotos` e `rm-assinaturas` como buckets públicos; os objetos usam caminhos aleatórios com prefixo do dispositivo. O app preserva esse contrato legado de URLs duráveis. A alteração para buckets privados requer adaptar os consumidores de relatórios/Bubble e a resolução de URLs.

Veja [operação e credenciais do banco](rm-mobile-supabase/MOBILE_DEPLOYMENT.md) e [configuração da ponte/Railway](desktop/README.md). Antes da coexistência, os tipos exportados ao Bubble precisam de um campo texto `supabase_id`, além da Data API habilitada para os catálogos auxiliares. O webhook n8n precisa deduplicar `Idempotency-Key`; um HTTP externo sem dedupe não oferece garantia de envio único de e-mail.

## Validação

```sh
npm run typecheck --prefix mobile
npm test --prefix mobile
npm run typecheck --prefix desktop
npm test --prefix desktop
npm run build --prefix desktop
```

No Windows, com as ferramentas PostgreSQL no `PATH`, execute `powershell -File rm-mobile-supabase/tests/run-local-tests.ps1`. O script cria um PostgreSQL temporário em loopback, aplica as migrações, verifica as regras transacionais e encerra a instância. Os stubs Supabase usados nesses testes são exclusivos do banco temporário.

Homologação operacional: preencher em modo avião, reiniciar o app, trocar operador, reconectar, confirmar que foto e formulário chegam uma única vez; devolver uma resposta para revisão e verificar o reenvio; repetir uma aprovação sem duplicar os efeitos. Testes de código e bundles não substituem câmera, assinatura e perda de conectividade em um tablet real.

## Referências

Os três documentos originais da raiz e os blueprints em `rm-mobile-supabase/blueprint` foram usados como especificação. Em divergências, prevalecem os nomes e os contratos SQL: `rm_aprovacoes_etapas`, `rm_celula_form_tipos_equipamento`, `status`, `parecer`, `categoria_foto` e os slugs dos enums.

Documentação oficial consultada: [Expo SDK 54 ImagePicker](https://docs.expo.dev/versions/v54.0.0/sdk/imagepicker/), [SQLite](https://docs.expo.dev/versions/v54.0.0/sdk/sqlite/) e [DateTimePicker](https://docs.expo.dev/versions/v54.0.0/sdk/date-time-picker/).

# EM · MI Electric Brasil

**EM**, plataforma operacional da **MI Electric Brasil**: aplicativo mobile nativo em Expo SDK 54 e portal web de gestão em Next.js 15, sobre o mesmo Supabase. As aplicações têm instalações, dependências e builds separados. Os nomes técnicos herdados, como tabelas `rm_*`, identificadores de pacote e endereços de infraestrutura, permanecem preservados.

A jornada começa na célula disponível ao operador. Dentro dela, ele escolhe um projeto e acessa seus formulários ou a galeria de fotos. Essa organização mantém respostas e evidências no contexto do trabalho em execução.

Repositório privado: [enggavina/rm-mi-connect](https://github.com/enggavina/rm-mi-connect).

| Diretório | Conteúdo |
| --- | --- |
| `mobile/` | SQLite, identificação do operador, seleção de células permitidas, projetos, formulários e galeria offline |
| `desktop/` | Next.js, APIs protegidas, worker Bubble/Supabase, ETL e Docker/Railway |
| `rm-mobile-supabase/` | Migrações, contratos, schema offline original e testes PostgreSQL |

## Mobile

O mobile requer Node 22.13+; o portal web usa Node 22. O build Android local exige SDK/JDK, ou EAS Build para compilação remota.

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

Nesta estação foi gerado `artifacts/em-mi-electric-brasil-internal.apk`, configurado para o Supabase: Android 7+, ARM64/x86_64, nome **EM**, pacote `br.com.mielectric.rmconnect`, versão 1.2.2 / código 5. O identificador Android foi preservado para atualizar a instalação existente e seus dados. O APK usa assinatura Android Debug e destina-se à homologação interna. O arquivo fica fora do Git. O build Android e os bundles Android/iOS passaram; câmera, assinatura e operação offline ainda precisam de homologação em um tablet real. As credenciais iniciais estão no arquivo local `rm-mobile-supabase/.env.initial-admin`; consulte o [provisionamento](rm-mobile-supabase/MOBILE_DEPLOYMENT.md).

O primeiro login e a primeira identificação de cada operador precisam de conexão. Depois, o catálogo e os rascunhos permanecem no SQLite; palavras-chave são verificadas por PBKDF2 em cache protegido pelo SecureStore, válido por 24 horas. A identidade da fila é preservada ao trocar de operador. A delegação do servidor dura até 7 dias; um item vencido exige nova identificação do responsável, sem apagar o trabalho. A sincronização automática funciona com o app aberto ou ao voltar ao primeiro plano: sistemas móveis não garantem execução contínua com o app encerrado.

A sincronização automática permanece silenciosa enquanto o aplicativo está online. A faixa de recuperação informa a falta de conexão e, após o retorno, aparece apenas enquanto houver arquivos ou registros pendentes. Ela desaparece assim que o envio dessas filas é confirmado, sem esperar os downloads do catálogo. Pendências encontradas ao reabrir o app e falhas de transporte também entram nessa recuperação; os protocolos e a autoria dos registros são preservados.

A jornada principal é `identify` → `celula` → `projetos` → `projeto`. A célula é escolhida explicitamente entre as permissões do operador. O projeto reúne informações, formulários, galeria, registro de fotos, aprovações, documentos e comentários. Os cartões da lista de projetos identificam o cliente, mostram a foto frontal existente quando disponível e oferecem acesso ao status e aos comentários da célula.

Os formulários vêm exclusivamente do vínculo projeto–célula. Os subtítulos organizam o preenchimento em seções recolhidas, com uma seção aberta por vez; a validação abre a primeira seção com erro. “Visualizar respostas” consulta o registro enviado sem criar rascunho. “Corrigir revisão” permite alterar somente as respostas devolvidas com `revisar=true` em registro `direcionado`. Intervalos de datas/horas usam os subtipos reais do SQL; os rótulos visuais não substituem os slugs dos enums.

“Galeria” consulta as fotos já registradas de todo o projeto, com ampliação e filtro entre todas, obrigatórias e complementares. A captura fica em “Registrar fotos”, separando os títulos obrigatórios das fotos complementares, cujo título é digitado livremente. Rascunhos existentes mantêm o título preenchido; operações já enfileiradas preservam o payload original. As seleções oferecem uma saída visível, e a seleção múltipla só aplica alterações ao confirmar. Aprovações e comentários também exigem o contexto de projeto e célula; ações indisponíveis pelo perfil ou pelo estado da etapa não são oferecidas. Uma decisão concluída é exibida para consulta, sem botão para repeti-la.

O recebimento tem três etapas: **Cliente e projeto**, **Fotos** e **Conferência**. A primeira registra cliente, chegada com data/hora, número e arquivo da nota fiscal, descrição do equipamento, presença de placa e eventualidades. Não solicita número de projeto, tipo de equipamento, nome, contato ou proprietário; a numeração permanece pendente de atribuição no planejamento. Fotos usam os oito títulos canônicos de recebimento, com comentário opcional por imagem. Os rascunhos antigos preservam seu protocolo, dados já preenchidos e arquivos; fotos antigas sem classificação precisam receber um título antes de um novo envio. Operações já enfileiradas mantêm seu protocolo original.

A identidade usa a logo SVG fornecida pela MI Electric Brasil, preservada em `mobile/assets/brand/mi-electric-brasil.svg`, com símbolo recortado do vetor e versões PNG para o aplicativo. As cores base são vermelho `#E73E42`, grafite `#0E1724` e branco; botões usam um vermelho mais escuro para manter contraste com o texto branco.

Fotos são copiadas para armazenamento persistente e comprimidas. O anexo de NF aceita PDF, JPG ou PNG, até 20 MB, e é copiado para o dispositivo sem conversão. A fila envia os arquivos antes de qualquer RPC, substitui referências locais e usa UUID fixo para repetição idempotente. A atualização do SQLite preserva filas, autoria, tentativas e rascunhos existentes. Falhas permanecem visíveis e recebem retry exponencial. Catálogos são atualizados por paginação incremental; reconciliação de IDs remove registros remotos apagados sem apagar rascunhos nem a fila.

Documentos remotos são baixados ao abrir e ficam disponíveis offline após esse primeiro acesso com conexão. Arquivos ainda não baixados informam essa condição. As novas notas fiscais usam Storage privado: o banco guarda uma referência estável e o aplicativo obtém uma URL temporária apenas para baixar o arquivo. URLs assinadas não são persistidas na fila. A abertura usa um visualizador instalado no dispositivo.

## Plataforma web

A [revisão de paridade com o Bubble Live e o plano de implementação](plano_paridade_rmmi_web.md) registra as funcionalidades ainda ausentes e a ordem dos próximos incrementos. Os pacotes publicados acrescentam gestão dos dados básicos, matriz de Engenharia, construtor de formulários e aprovações de etapas na web, com a mesma transação operacional do mobile. Contatos, prioridades/capacidade do PCP, comercial e laboratório permanecem no plano.

Endereço publicado: **[Abrir EM web](https://em-web-production.up.railway.app)**. Login Microsoft SSO pela Central de Acessos: `mgavina@mielectric.com.br` e `softdev05@mielectric.com.br` como administradores do EM, conforme autorização explícita. Esse perfil não concede administração global da Central. O login por senha do portal está desativado; as credenciais do tablet permanecem preservadas. Consulte [configuração, permissões e validação do SSO](desktop/docs/sso.md).

O portal de gestão em `desktop/` compartilha a base do mobile: visão geral, projetos, planejamento de células, cronograma, consulta/revisão de formulários, galeria, documentos e consulta de cadastros. O acesso verifica a identidade Microsoft, as concessões atuais da Central e o perfil RM vinculado. A ponte privada fica exclusivamente no servidor; consultas e alterações de negócio usam JWT local e RLS. As migrações 014–016 preservam autoria, idempotência e conflito de versão, acrescentando sessões opacas e permissões SSO de uso único para as escritas. Consulte [funcionalidades, execução e operação da plataforma](desktop/docs/web-platform.md).

## Banco e integração

O ambiente inicial está no projeto **[oficina-em-mi-off](https://supabase.com/dashboard/project/ellpxfbsrbhblyizvbbk)**, criado na organização Pro, região São Paulo, com compute Micro. As migrações 001–020 já foram aplicadas e as 56 tabelas RM estão protegidas por RLS. Os arquivos `.env` locais apontam para esse ambiente e permanecem fora do repositório.

A carga contém 177 projetos operacionais e seus catálogos. A complementação histórica preservou 61.803 respostas dos 778 registros de formulário, incluindo 1.719 snapshots sem vínculo de questão disponíveis somente para consulta. Foram recuperados 11 PDFs existentes para o bucket privado; três documentos continuam sem arquivo na origem. Consulte o [relatório da carga inicial](desktop/docs/initial-load.md), a [reconciliação histórica e os contratos atuais](rm-mobile-supabase/PROJECT_OPERATIONS.md) e a [validação dos PDFs importados](desktop/docs/existing-documents.md). O worker permanece desativado. A gestão web compartilha os dados e a operação do aplicativo.

Aplicar as migrações **001 a 020**, em ordem, em ambiente previamente conferido. As cinco primeiras preservam o modelo recebido. `005` contém uma correção necessária: o enum é `administrador`, e não `Administrador`. `006` acrescenta autenticação delegada, limitação de tentativas, permissões de mídia e idempotência para todas as mutações. `007` acrescenta leases, checkpoints e recuperação de falhas do worker. `008` publica no Realtime as 17 tabelas de catálogo/execução consumidas pelo mobile, incluindo formulários, questões e títulos de fotos. `009` preserva os índices fracionários usados na ordenação de questões e opções no Bubble, inclusive no envio e na revisão de respostas. `011` acrescenta as operações contextuais de projeto/célula, documentos e recebimento com NF, permitindo número de projeto pendente sem alterar as filas antigas. `012` preserva respostas históricas importadas cuja questão foi removida na origem, sem permitir novos envios ou correções sem uma questão válida.

A `013` otimiza a paginação dos catálogos por data e identificador, preservando as regras de acesso. A leitura autenticada das 61.803 respostas foi validada em 248 páginas, sem timeout ou perda de registros.

A `018` acrescenta a [gestão de Engenharia](rm-mobile-supabase/WEB_ENGINEERING.md). Os modelos são copiados somente para novas alocações; editar ou aposentar um modelo não reescreve projetos existentes. A recuperação complementar trouxe 963 modelos de fotos e 70 de aprovação que a carga de projetos não abrangia, preservando tags e vínculos legados sem conceder permissões operacionais.

A `019` acrescenta o [construtor de formulários](rm-mobile-supabase/WEB_FORM_TEMPLATES.md). Rascunhos ficam fora do catálogo mobile. Publicar cria um formulário e perguntas/opções com novos IDs, preservando a versão anterior e os trabalhos offline. As versões são diferenciadas nas escolhas web; sua adoção em Engenharia é explícita e afeta novas alocações. Cada formulário publicado tem sequência de registros própria.

A `020` acrescenta [aprovações de etapas na web](rm-mobile-supabase/WEB_STAGE_APPROVALS.md): fila, detalhe e aba no projeto, com Liberar ou Retornar/Aprovar conforme regras existentes. Etapa e alocação têm versões verificadas na mesma transação; protocolo e conteúdo permanecem no retry. O histórico web tem vínculo exato à etapa, e os logs antigos/mobile continuam como contexto da célula, sem atribuição inventada. A instalação preservou 66 snapshots completos de dados existentes.

As RPCs originais são chamadas pelo gateway `rm_mobile_mutate_v1`; o aplicativo não recebe a chave `service_role`. Uma autorização de dispositivo não autoriza forjar outro operador. Campos obrigatórios, revisão e permissão de aprovação também são validados no servidor. A `010` usa os vínculos cadastrados para a identidade do operador, preserva o cadastro durante o login e impede herdar células ou privilégios da conta do tablet; [evidência e validação](rm-mobile-supabase/OPERATOR_CELL_PERMISSIONS.md).

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

Homologação operacional: preencher em modo avião, reiniciar o app, trocar operador, reconectar, confirmar que foto e formulário chegam uma única vez; devolver uma resposta para revisão e verificar o reenvio; repetir uma aprovação sem duplicar os efeitos. No recebimento, retomar um rascunho antigo, anexar NF e fotos com comentários, reiniciar antes do envio e confirmar a criação sem número de OS inventado. Abrir um documento com conexão e reabri-lo em modo avião; um arquivo ainda não baixado deve informar a necessidade de conexão. Testes de código e bundles não substituem câmera, documentos, assinatura e perda de conectividade em um tablet real.

## Referências

Os três documentos originais da raiz e os blueprints em `rm-mobile-supabase/blueprint` foram usados como especificação. Em divergências, prevalecem os nomes e os contratos SQL: `rm_aprovacoes_etapas`, `rm_celula_form_tipos_equipamento`, `status`, `parecer`, `categoria_foto` e os slugs dos enums.

Documentação oficial consultada: [Expo SDK 54 ImagePicker](https://docs.expo.dev/versions/v54.0.0/sdk/imagepicker/), [SQLite](https://docs.expo.dev/versions/v54.0.0/sdk/sqlite/) e [DateTimePicker](https://docs.expo.dev/versions/v54.0.0/sdk/date-time-picker/).

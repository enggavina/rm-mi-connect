# EM · MI Electric Brasil — Desktop e ponte Bubble

Scaffold Next.js 15 com App Router e runtime Node. A página inicial apresenta o EM, da MI Electric Brasil, com a jornada célula → projeto → formulários ou galeria. O desktop operacional e as rotas de relatórios/TOTP estão reservados para a Fase 2. A identidade usa o logo original fornecido e as cores vermelho `#e73e42`, grafite `#0e1724` e branco.

## Executar localmente

Requer Node 20.19+ (a imagem usa Node 20 conforme a especificação).

```sh
cd desktop
npm ci
# Copiar .env.example para .env e preencher os valores no ambiente local.
npm run dev
npm run typecheck
npm test
npm run build
```

O build não exige credenciais. As APIs e o worker só constroem o cliente Supabase no momento da execução. As chaves de serviço ficam exclusivamente no servidor.

## Preparar a coexistência

1. Aplicar as migrações `001` a `010` em ordem no Supabase. `006` adiciona delegação/idempotência do mobile, `007` adiciona leases/checkpoints do worker, `008` completa a publicação Realtime, `009` preserva índices fracionários de questões e opções e `010` aplica as células cadastradas para a identidade do operador.
2. Habilitar a Data API no Bubble para os tipos de `src/server/bridge/mapping.ts`. Os endpoints dos catálogos, projetos, fotos e formulários foram validados com leitura live. O endpoint de aprovações ainda retorna 404; os nomes públicos tentados e o Swagger indisponível estão registrados em `docs/bubble-preparation.md`. Se o nome público divergir, configurar `BUBBLE_ENDPOINT_OVERRIDES` somente após conferir o nome efetivamente exposto.
3. O campo **texto `supabase_id`** já foi preparado em **Main/test** nos cinco tipos criados pela ponte: `projetorm`, `equipamento`, `fotosrm`, `registro_formulario` e `respostas`. Ver [registro da preparação](docs/bubble-preparation.md). Publicar o schema no Bubble antes de apontar ao ambiente live. O campo é configurável em `BUBBLE_SYNC_ID_FIELD`. Um POST com resposta perdida é reconciliado por esse UUID antes da nova tentativa. Sem o campo, a fila falha e preserva o evento para correção; não há fallback inseguro para criação cega. Atualizações de células/aprovações com `bubble_id` já conhecido usam PATCH e dispensam campos novos.
4. Os campos em `mapping.ts` foram confrontados com o Swagger local e com os schemas atuais do editor Main/test, incluindo tipos auxiliares e aprovações. Conferir os nomes públicos dos endpoints auxiliares após habilitar a Data API do ambiente escolhido.
5. Configurar segredos distintos, cada um com pelo menos 32 caracteres, para `INTERNAL_API_SECRET` e `BUBBLE_WEBHOOK_SECRET`. Credenciais de operador, TOTP, CPF e campos de autenticação do Bubble **não são importados**. Vincular as contas Supabase em `rm_users.auth_user_id` e provisionar as credenciais privadas pelo processo administrativo descrito no pacote de banco.
6. Executar `npm run etl -- --dry-run --sample=100 --scope=active` para preflight limitado. Ele lê todos os projetos para delimitar o recorte e valida campos, formatos e opções contra `rm_option_sets`; FKs são verificadas na importação real. Executar `npm run etl -- --scope=active` para importar em lotes. Registros inválidos são isolados em `.tmp/etl/<data>/quarantine.jsonl`, fora do Git, e os válidos continuam. A execução termina com erro parcial e conserva o checkpoint dos tipos com falha. O contador de formulário avança monotonamente até o maior código importado.
7. Configurar `SYNC_WEBHOOK_ALLOWLIST` com as URLs HTTPS exatas permitidas para os eventos legados de e-mail. O remetente envia `Idempotency-Key: rm-outbox-<id>`; o n8n precisa deduplicar esse identificador para evitar e-mails repetidos após uma resposta perdida. Não é possível garantir exactly-once com um webhook externo que não deduplica.
8. Após homologar a leitura e autorizar a ativação da ponte de saída, definir `SYNC_OUTBOX_ENABLED=true` e iniciar `npm run worker`. O padrão `false` permite importar sem executar mutações no Bubble nem enviar e-mails. O worker preserva checkpoints no Supabase, recupera leases expirados e marca falhas como `failed`/`dead_letter`, com tentativas limitadas. Tipos/eventos desconhecidos nunca são marcados como concluídos.

## Railway

Criar o serviço web com **Root Directory `/desktop`**, Dockerfile e `railway.json`. Injetar variáveis server-side no Railway. Criar um segundo serviço a partir do mesmo diretório, usando `railway.worker.json` como config e `npm run worker` como comando; o worker não oferece endpoint HTTP nem healthcheck web. A imagem inclui o runtime TypeScript para esse processo separado. Para desenvolvimento, um ciclo também pode ser acionado com `npm run worker:once` ou a rota protegida abaixo.

O projeto Supabase `oficina-em-mi-off` foi provisionado, recebeu as migrações `001..010` e a carga operacional inicial foi concluída com 177 projetos, 13.631 fotos, 778 cabeçalhos de formulários e 875 aprovações, mantendo a saída desativada. Há 276 registros legados inválidos em quarentena; consulte [volumes, recorte e limitações](docs/initial-load.md). Não houve deploy no Railway. No Bubble, somente os cinco campos de sincronização em Main/test foram adicionados; a versão live foi usada apenas como origem de leitura.

## Recorte operacional da carga e do worker

O padrão importa os catálogos e projetos sem entrega real, excluindo `cancelado` e `finalizando_para_faturar` e preservando status nulo. Inclui equipamentos, células, fotos e cabeçalhos de formulários desses projetos. Nesta fase, importa respostas completas apenas dos formulários em revisão (`direcionado`/`Revisar`). Respostas de registros aprovados históricos permanecem na origem; o mobile indica explicitamente quando esse conteúdo não foi carregado. A opção explícita `--scope=all` permite uma carga histórica posterior e pode envolver mais de 202 mil respostas.

O worker aplica o fechamento ou cancelamento de projetos já importados antes de excluí-los do recorte. Reativações reidratam os filhos antigos: os projetos são relidos desde o menor checkpoint dos filhos, mantendo a tentativa após falhas parciais. Respostas de revisões são relidas integralmente dentro desse recorte para cobrir respostas antigas cujo formulário mudou de status. Registros inválidos não impedem os posteriores válidos, mas conservam o checkpoint; enquanto a origem não for saneada, esse backlog será revisto em cada ciclo. O worker não varre respostas históricas fora das revisões.

As aprovações exigem habilitar/conferir seu endpoint live para sincronização contínua. Um snapshot lido pelo conector pode preparar o catálogo inicial, mas não resolve esse bloqueio do polling. `SYNC_OUTBOX_ENABLED=false` permanece obrigatório até homologar os contratos de saída e publicar os campos Main no Bubble.

O lease serializa os workers, e o importador consulta a fila pendente antes de sobrescrever registros ou seus filhos. Essa consulta e o upsert ainda são chamadas separadas. Antes da coexistência concorrente, a importação precisa ser transacional com uma trava compartilhada pelas mutações mobile; o guard atual não oferece essa atomicidade. A carga inicial foi executada sem concorrência, e o worker Railway permanece desativado e sem implantação.

O contador por formulário foi inicializado pelo maior código do recorte importado. Antes de permitir que os dois sistemas criem registros, validar o máximo global no histórico do Bubble e definir uma única autoridade para alocar os próximos códigos. O incremento monotônico do Supabase evita regressão local, mas não coordena dois geradores independentes.

## Contratos HTTP

| Rota | Autenticação | Comportamento |
| --- | --- | --- |
| `GET /api/health` | Pública | Healthcheck do processo, sem segredos nem teste de conexão |
| `POST /api/webhooks/bubble` | Bearer `BUBBLE_WEBHOOK_SECRET` | JSON `{ "entity_type": "Form", "bubble_id": "..." }`; busca registro canônico na Data API e aplica com referências resolvidas |
| `POST /api/sync/run` | Bearer `INTERNAL_API_SECRET` | Executa um ciclo; HTTP 207 se houver falhas parciais |
| `POST /api/reports/generate-pdf` | Bearer interno | HTTP 501: geração de relatórios da Fase 2 |
| `POST /api/reports/compile-s3` | Bearer interno | HTTP 501: composição de dossiê da Fase 2 |
| `POST /api/auth/totp` | Bearer interno | HTTP 501: adaptação do contrato legado da Fase 2 |

Webhooks retornam 409 quando outro ciclo tem o lease; o remetente deve repetir com atraso. O polling usa intervalo padrão de 15 segundos, defasagem de 60 segundos e sobreposição de 2 minutos para timestamps. Para atualização imediata, configurar o webhook por registro no Bubble. A Data API não oferece snapshot transacional de paginação; o overlap reduz o risco de alterações concorrentes, e uma reconciliação completa periódica deve fazer parte da operação. Exclusões físicas no Bubble não aparecem em `Modified Date`; usar exclusão lógica ou um processo de reconciliação antes de apagar dados definitivamente. Nenhuma exclusão remota é inferida pelo worker.

## Validação e manutenção

Os testes cobrem paginação, página inválida, recuperação de POST ambíguo, rejeição de chaves duplicadas, bundles completos, falhas de eventos desconhecidos, autenticação, limite de payload e URLs autorizadas. O build usa Next 15.5.28 e override PostCSS 8.5.32, mantendo a linha de versão solicitada. Atualizar patches antes de cada deploy e executar `npm audit` novamente. Referência oficial: [atualizações de segurança do Next](https://nextjs.org/blog/security-update-2025-12-11).

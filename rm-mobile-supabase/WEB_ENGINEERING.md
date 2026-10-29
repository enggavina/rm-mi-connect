# Matriz de engenharia — contrato 018

Estado: **018 aplicada em 29/10/2026, às 12:50:01 UTC**, ao projeto autorizado `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`), com histórico 001–018 e SSO obrigatório preservado. Modelos reais recuperados separadamente conforme a comprovação abaixo. A 018 configura modelos para futuras alocações, sem reescrever células/projetos em andamento, respostas, fotos capturadas ou aprovações realizadas. Não gera outbox, emails ou chamadas Bubble. O editor de perguntas/formulários e a execução das aprovações web pertencem a outras entregas.

Interface publicada em [Engenharia](https://em-web-production.up.railway.app/engenharia), inicialmente no commit `36f2fc5125f5ee708fb6a83223458a0f2a58746f`, deploy `603e3698-8698-4f8c-a7fb-1dc2495881ca` com `SUCCESS`. A entrega posterior do construtor (`934f8bc`, deploy `21c95a5e-2f82-4f64-9f92-4fe676324e16`) identifica as versões dos formulários nas escolhas. Por nova autorização explícita, **`mgavina` e `softdev05` podem consultar/gerir o EM**; isso não promove o papel global da Central. O contrato atual aceita 16 capacidades, preservando sessões anteriores. Concessões são aplicadas somente após publicar um consumidor compatível.

Evidência Live somente leitura: `rm_gestao/coaXw` cria o vínculo célula × tipo; `cofwG` grava `numero_fotos`; `copON/copOq` chama `copOY/copOa` e copia o título do Cadastro Fotos para um modelo; `conKI/conKO` cria as regras de aprovação; `coqsi/coqss` alteram o bloqueio de avanço. A seleção de aprovadores usa `Tablet_Celula_User.identidade_id` da origem e do destino. O contador de fotos não gera slots: a materialização copia as linhas de modelo reais.

As duas operações usam `rm_web_mutate_v1`, UUID de envio fixo, versão exata, recibo idempotente, conta RM ativa **administrador** e MFA quando configurado. Com `require_sso=true` em produção, exigem permit curto/sessão SSO e capability **`em.engineering.manage`**. A exceção de staging da 016 continua intacta: `require_sso=false` admite contas legadas sem binding, ainda sujeitas a perfil/MFA/validações; binding desativado nunca ganha fallback. A consulta no BFF exige `em.engineering.read`; o banco preserva o RLS de leitura RM ativa compartilhado com o mobile.

`save_engineering`:

```ts
{
  id: UUID,
  celula_id: UUID,
  tipo_equipamento_id: UUID,
  expected_updated_at: string | null,
  changes: {
    ativo?: boolean,
    visibilidade?: boolean,
    numero_fotos?: number,
    form_ids?: UUID[],
    photos?: [{id: UUID, cadastro_foto_id: UUID | null, numero: number | null, descricao: string | null}],
    stages?: [{
      id: UUID, celula_destino_id: UUID | null, status_cel_proj: string | null,
      bloquear_avanco_sem_aprov: boolean, aprovadores_ids: UUID[], aprovadores_retorno_ids: UUID[]
    }]
  }
}
```

- O par célula/tipo é único e imutável depois de criado. `ativo=false` aposenta o vínculo: novas alocações que encontrem esse vínculo são recusadas, com orientação para habilitá-lo. `visibilidade` continua sendo a visibilidade inicial da nova alocação, independente de `ativo`.
- `numero_fotos` aceita inteiro 0–1000 e permanece um metadado separado da quantidade de slots. Campos/arrays omitidos são preservados; `changes` precisa ter ao menos um campo. Arrays enviados representam o conjunto ativo desejado: ausentes são aposentados, nunca excluídos fisicamente.
- `form_ids`: no máximo 200 IDs distintos. Novos vínculos exigem formulário existente/ativo. Formulários legados inativos já vinculados podem permanecer sem alteração. A remoção marca o vínculo CFTE inativo e não muda `forms_ids` de nenhuma alocação existente.
- `photos`: no máximo 1000 linhas com UUIDs distintos. Item novo/modificado exige título cadastrado para a célula ou global, número inteiro 1–1000 e descrição de até 4000 caracteres. O servidor copia o título e grava categoria obrigatória; não recebe URLs, projeto, autoria, `identificador_foto_key` ou categoria pelo cliente. Multiplicidade é representada por linhas distintas, inclusive títulos repetidos. Item legado exatamente inalterado pode manter número nulo/negativo, título sem cadastro e identificador antigo. Remoção marca `lixeira=true` somente no modelo.
- `stages`: no máximo 100 linhas. Novo/modificado exige célula destino existente e diferente da origem, status canônico diferente de `retornado`, booleano de bloqueio e 1–100 aprovadores distintos em cada lista. Aprovadores precisam estar ativos e vinculados por `identidade_id` à origem; aprovadores de retorno, ao destino. A origem é derivada da matriz. Item legado exatamente inalterado preserva valores incompletos e aprovador singular. Reconfiguração explícita limpa `aprovador_id`, mantendo somente as listas escolhidas, e reinicia apenas o modelo como `nulo`. Remoção marca o modelo inativo. A geração operacional da etapa de retorno permanece com a lógica anterior.

IDs de fotos/etapas existentes precisam pertencer à mesma matriz e ter **ambos** `projeto_id` e `celula_projeto_id` nulos. Não é possível fornecer ID operacional, de outra matriz ou campos de decisão. A comparação de legado usa os campos mutáveis do DTO contra a linha real; nenhum fingerprint fornecido pelo navegador participa da autorização.

`save_photo_title`:

```ts
{id: UUID, expected_updated_at: string | null,
 changes: {titulo?: string, numero?: number | null, celula_id?: UUID | null}}
```

Criação exige `titulo` e `celula_id` explícito, com null significando global. Título recebe trim e aceita 1–200 caracteres; número é inteiro 0–1000 ou null. O escopo continua armazenado em `celula_nome`, sem migração especulativa do legado. Nome de célula ambíguo não permite criar/atribuir escopo. Na edição, omitir escopo preserva inclusive um texto legado sem correspondência; enviá-lo exige a mesma célula inequívoca/global já cadastrada. Alterar o título não reescreve o texto das fotos de modelo ou de projeto. A operação `delete_photo_title` foi acrescentada na migração023 e segue o contrato abaixo. `rm_fotos.cadastro_foto_id` tem FK `RESTRICT`; os clones podem conservar esse ID, mantendo `titulo` como snapshot.

Retorno: `{operation,id,projeto_id:null,updated_at,record,idempotent_replay}`. Para matriz, `record` é o DTO do pai e o retorno também inclui `snapshot`. `updated_at` é lido **depois** de todos os filhos e triggers. Replay exato retorna a primeira resposta; em produção exige nova autorização SSO. Outro ator, operação ou corpo não pode reutilizar o envio.

Leitura atômica: `rm_web_engineering_snapshot_v1(p_id uuid)` é uma única expressão SQL `STABLE SECURITY INVOKER`, executável somente por `authenticated`, retornando null se a linha não estiver visível no RLS. Retorna:

- `matrix`: `id, celula_id, tipo_equipamento_id, ativo, visibilidade, numero_fotos, updated_at`;
- `form_ids`: relacionamentos ativos;
- `photos`: modelos ativos com `id, cadastro_foto_id, numero, descricao, titulo, identificador_foto_key, categoria_foto`;
- `stages`: modelos ativos com os campos do DTO de edição mais `celula_origem_id` e `aprovador_id`, para diagnosticar origem/singular legados sem corrigi-los automaticamente.

Os DTOs não expõem mídia, autoria de decisão ou metadados de autenticação. A query lê pai/filhos da mesma versão MVCC, evitando combinar um timestamp antigo com filhos novos.

Concorrência e importação técnica:

- `rm_private.engineering_pair_lock(p_cell uuid,p_type uuid,p_exclusive bool)` usa advisory transacional com `hashtextextended(cell::text||':'||type::text,18)`; a escrita toma exclusivo, a cópia toma compartilhado antes de procurar o vínculo. Assim também protege uma matriz ainda inexistente. `plan_cell` com tipo nulo conserva a exceção manual, sem chamar esse lock.
- Triggers `rm_engineering_parent_lock`, `rm_engineering_forms_version`, `rm_engineering_photos_version`, `rm_engineering_stages_version` integram alterações técnicas ao protocolo. Apenas filhos de modelo atualizam a versão agregada do pai; mudanças operacionais não a alteram.
- Importadores devem adquirir o lock exclusivo do par **antes dos upserts de filhos**, em uma única transação por matriz. Isso evita inversão entre locks de linhas e locks de engenharia. Triggers são defesa adicional, não autorização para ignorar essa ordem. Para mais de um par, ordenar por célula/tipo.
- Edição de título usa o advisory exclusivo de catálogo da 017; edição de fotos toma o mesmo lock compartilhado antes do par. Assim, renomear célula não cria impasse com o vínculo textual dos títulos.
- O timeout de lock é 10 segundos; erros de contenção/deadlock desfazem a transação e não são engolidos. Stale version retorna `PT409`; payload inválido `22023`; referência/ID de outro escopo `42501`; identidade/capability/MFA sem autorização `42501`; UUID/conflito natural `23505`.

Os dois materializadores consomem somente vínculos/filhos ativos. O materializador geral legado agora usa `ON CONFLICT DO NOTHING`: somente cria/copía alocações novas, preservando integralmente prazos/forms/fotos/aprovações existentes. Não reaplica modelos a um projeto em andamento. O gateway mobile e a transição operacional Liberar/Retornar/Aprovar não são modificados.

A cópia de foto também preserva `tag`, utilizado por relatórios legados, separadamente de `identificador_foto_key`. Importação e cópia não inferem um identificador a partir de tags ou títulos.

Validação local: 001–018 e sete suítes PostgreSQL passaram. Engenharia cobre snapshots, versão agregada de import, distinção modelo/instância, aposentadoria sem exclusão, preservação de legado, escopo imutável de título, título de projeto imutável, cópia de tag sem inferir identificador, regras de aprovadores, materialização futura e geral sem sobrescrita, RLS/SSO/MFA, replay e locks reais entre duas conexões. Inclui alocação manual quando o projeto ainda não tem tipo e escopo global legado formado somente por espaços/tabs. Nenhum modelo artificial foi criado em produção pela migration ou pelos testes.

A aplicação remota comparou 53 snapshots: as 52 tabelas públicas RM e os recibos web privados. A comparação excluiu apenas as quatro colunas adicionadas (`ativo` em CTE/CFTE/etapas e `cadastro_foto_id` em fotos), mantendo todas as colunas anteriores e contagens idênticas. Foram preservados 102 usuários RM, quatro registros preexistentes da outbox e zero recibos de mutação web. A fonte completa da migration foi registrada em `supabase_migrations.schema_migrations.statements[1]`; seu SHA-256 confere com o arquivo local congelado. O pós-teste confirmou os quatro triggers, RLS, helpers privados, snapshot `STABLE SECURITY INVOKER` restrito a authenticated, sete operações no permit, capability exata das duas novas operações, FK de título `RESTRICT`, credenciais privadas, gateway mobile e `require_sso=true`. Prova local sem segredos: `.tmp/engineering-018-application-proof.json`.

Recuperação dos modelos reais:

- O escopo inicial do ETL de projetos excluía fotos/aprovações com `ProjetoRM` vazio. Uma exportação Live somente para leitura, com cutoff `2026-10-29T12:29:50.085Z`, identificou **963 modelos de fotos e 70 de aprovação**, distribuídos em **100 matrizes** já existentes. Não foram importadas novas identidades ou permissões.
- O conversor estrito [engineering-bootstrap.ts](../desktop/src/server/bridge/engineering-bootstrap.ts) resolve todas as referências previamente carregadas e recusa projeto/alocação, mídia capturada, aprovação executada, opção desconhecida, duplicidade ou propriedade local. Preserva os 962 números de foto ausentes como nulos, 527 tags de relatório e os aprovadores singulares/listas originais. Não infere título cadastrado ou identificador pela semelhança de texto.
- Há **26 referências de aprovadores sem vínculo operacional com a célula exigida**. Permanecem legadas, visíveis para revisão explícita no editor; a importação não lhes concede acesso. Não representam necessariamente 26 pessoas distintas.
- [prepare_engineering_bootstrap.ts](scripts/prepare_engineering_bootstrap.ts) prepara um plano e SQL por matriz. O SQL padrão termina em `ROLLBACK`; o arquivo de aplicação é explícito. Cada transação toma o lock exclusivo do par antes de ler/inserir filhos, confere a versão agregada se houver inclusão e aceita registros existentes somente quando forem exatamente iguais. É um bootstrap **somente de inserção**, não um importador incremental que sobrescreve modelos.
- Os **100 grupos foram ensaiados com rollback**, aplicados e repetidos integralmente. Aplicação às **12:55:32 UTC**: 963 fotos/70 etapas; **53 snapshots protegidos iguais**, incluindo todas as linhas fora do conjunto de novos modelos, todas as colunas dos pais exceto sua versão agregada e os recibos web. Nenhum projeto, formulário respondido, foto capturada, decisão, usuário ou evento de outbox foi modificado.
- Repetição às **12:56:30 UTC**: **53 snapshots completos iguais**, agora incluindo os modelos e os timestamps dos pais. Portanto, não houve novas linhas nem alteração de versão no replay. SSO obrigatório permaneceu ativo; a ponte Bubble não foi habilitada.

Os exports, lookup IDs e SQLs por grupo permanecem locais/ignorados em `.tmp/engineering-bootstrap`. Provas sem segredos: `rehearse-proof.json`, `apply-proof.json`, `replay-proof.json` e snapshots correspondentes. O hash SHA-256 do JSON de origem serializado pelo conversor é `df7d2f49179f43b9782834f50df5e6400a9244f2f7884c4e40b377e825e0c040`.
# Exclusão protegida de títulos — migração023

`delete_photo_title` reutiliza `rm_cadastro_fotos`, o BFF/permit `em.engineering.manage` e a autenticação RM ativa de administrador/MFA. Payload: `{id, expected_updated_at}` com UUID de submissão externo. A versão é obrigatória, ISO com timezone, preservada com precisão do banco. Registro ausente/alterado retorna PT409. Sob lock do recibo (14), lock exclusivo do catálogo (17) e título `FOR UPDATE`, a operação exclui apenas um título sem referências. A FK `rm_fotos.cadastro_foto_id ON DELETE RESTRICT` continua impedindo exclusão inclusive para foto de modelo aposentada/lixeira ou projeto. Tanto23503 quanto23001 retornam23503 com mensagem de título em uso; nenhum vínculo é removido, nenhum snapshot é reescrito.

Recibo grava ator Auth/RM, payload exato, resultado e registro anterior. Replay exato após exclusão retorna o resultado inicial, exigindo novo permit SSO pelo envelope público; outro corpo/ator/operação não pode reutilizar o UUID. Respostas do delete são validadas novamente no BFF (operação, IDs, projeto nulo, timestamp, replay booleano) e expõem apenas `record:{id}` ao cliente. Envelope inválido vira UNAVAILABLE para preservar o envio pendente. Core e escrita direta continuam inacessíveis ao cliente; a migração não altera dados, não cria capacidade Central ou trabalho de ponte.

O editor mantém uma única tentativa discriminada `save|delete`, congelada durante envio incerto. Não permite salvar enquanto exclusão não foi confirmada. Excluir exige confirmação do título e exibe resultado ao voltar à lista; Cadastros oferece atalhos às rotas já existentes de títulos, matriz e modelos de formulário conforme capacidades de leitura. Rotas antigas da Engenharia continuam funcionando.

Diferenças documentadas com o Live: `coqll` permite editar a célula do título; EM preserva escopo imutável da018 até existir contrato de transferência seguro. `coqnQ` do Live não demonstra proteção de referência; o EM protege histórico por FK. Portanto a conclusão da operação de exclusão não declara paridade total de campos ou autorização legada.

Validação: `web_photo_title_deletion_upgrade.sql` aquece a sessão022 e comprova despacho antigo/novo após023; `web_photo_title_deletion.sql` cobre versão, injeções, referências antigas, perfis/SSO/MFA, replay/corpo/ator, auditoria e lock compartilhado de escrita de modelo. A execução integrada001–024 passou com 13 suítes SQL em PostgreSQL isolado. Os17 testes TS de Engenharia passaram, cobrindo schemas, BFF, envelopes e o hook real via React SSR. A publicação é registrada pelo processo integrado do portal.

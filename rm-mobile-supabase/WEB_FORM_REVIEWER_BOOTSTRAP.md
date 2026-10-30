# Atribuições de avaliador: discovery e recuperação contextual

Revisão em 30/10/2026, Bubble `rmmi` **Live somente leitura** e Supabase EM `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`) consultado por GET. Esta ferramenta prepara uma carga contextual insert-only da 026. Não integra o ETL genérico, não preenche avaliadores retroativamente nos registros e não ativa a ponte de saída.

## Contrato confirmado no Bubble

`custom.aprovacao_form` (**Aprovacao Form**) contém `Aprovador` (User), `Celula`, `Form`, `ProjetoRM`, `Registro_Formulario` opcional, `Status`, `Historico_status`, `Parecer` e metadados. É uma entidade heterogênea: parte dos registros representa atribuição por contexto antes do primeiro preenchimento; outra parte contém somente referência ao registro e estado de decisão. Não importar indiscriminadamente como uma lista uniforme de atribuições.

O controle PL019 `comLI → comOA` abre `colnr` para a tupla projeto+célula+form. `comOC` avisa e impede abertura quando o primeiro registro consultado está Aprovado. Sem aprovação, envia registro opcional, formulário e alocação ao popup. `coloI` lista **Identidades** de `Tablet_Celula_User` daquela célula; a origem não filtra explicitamente ativo/perfil nesse dropdown. O EM preserva a elegibilidade operacional e acrescenta verificação de usuário ativo para novas atribuições.

`coluP → coluV` cria AprovacaoForm com projeto/célula/form/aprovador; `coluU` altera o avaliador do registro apenas se ele já existe. `coluh → colun` troca o aprovador da primeira AprovacaoForm encontrada; `colum` também altera o registro existente. O popup exige confirmação para troca (`coluz/colvK`). Não existe remoção de atribuição nesse caminho. A busca usa primeiro item sem unicidade garantida; a nova tabela possui contexto único e a carga não escolhe arbitrariamente entre aprovadores conflitantes.

Os workflows mobile atuais **ativos** `conTa → conTg` e `coVuI → coVuO` copiam o avaliador da AprovacaoForm correspondente na criação do Registro_Formulario, por projeto/célula/form. A correção `cofgY → cofkw` retorna Status/Historico da AprovacaoForm para Em análise; não altera o avaliador. A notificação `conTl` destina-se ao operador atual, não ao avaliador. Não inferir envio de email ou nova notificação ao atribuir.

No EM anterior à 026, `rm_submit_form_v1` não preenche `avaliador_user_id` na criação. O ETL não mapeia `Aprovacao Form` e também não mapeia o avaliador/lista de aprovadores do Registro_Formulario. `rm_aprovacoes_registro` é histórico de decisão e exige registro existente; não substitui atribuição prévia. `review_form` pode gravar o próprio decisor como avaliador do registro; por isso atribuição contextual e autoria de decisão devem ser apresentados separadamente.

O EM bloqueia novas atribuições se **qualquer** registro da tupla estiver aprovado, em vez de depender apenas do primeiro item do Bubble. O administrador/PCP pode aplicar explicitamente o avaliador a registros não aprovados existentes e aos futuros. A importação inicial recupera somente o contexto e não executa essa aplicação retroativa.

## Leitura real e reconciliação

Export Live completo: **545 AprovacaoForms**, com IDs únicos, obtidos em seis páginas. Há 383 linhas com contexto completo, 302 delas com Aprovador; 162 não possuem todos os três campos de contexto. Há duas tuplas duplicadas (sete linhas), sem conflito de aprovador entre seus membros. Um ponteiro Registro_Formulario não é usado para inventar contexto ausente.

Leitura do destino em 30/10/2026: 178 projetos, 29 células, 57 formulários, 102 usuários, 181 vínculos Tablet_Celula_User, 1.429 alocações, 778 registros de formulário e zero linhas em `rm_aprovacoes_registro`. Os 778 registros estavam sem `avaliador_user_id` e sem lista de aprovadores. Essa ausência não significa que o Bubble não possuía atribuições: o mapeamento estava incompleto.

Crosswalk estrito por Bubble ID, sem email/nome:

- **103 linhas da origem → 101 contextos preserváveis**, após agrupar três fontes da mesma tupla/aprovador.
- **100 contextos** estão vinculados aos formulários atuais da alocação; **um contexto adicional** tem formulário conhecido, mas fora do vínculo atual. Este é importado como metadado histórico consultável, sem fabricar `forms_ids`.
- Todos os 101 avaliadores resolvidos estavam ativos e vinculados pela Identidade à célula; nenhum projeto estava encerrado. A ferramenta também suporta preservar metadado histórico fechado/inativo, sempre sem concessão de acesso ou alteração do registro.
- Entre os 100 contextos vinculados, 12 tinham registro Aprovado, 92 tinham um registro atual e oito ainda não tinham registro. O campo Registro_Formulario estava vazio em 27 fontes elegíveis, mas 19 delas já possuíam um registro no EM; portanto “fonte sem ponteiro” difere de “nenhum registro atual”.
- 262 linhas de contexto referem-se a projetos fora da carga EM, 18 contextos locais não têm Aprovador, e 162 linhas não têm contexto completo. Permanecem em quarentena, totalizando 442 linhas. Não criar projetos, alocações, usuários ou vínculos para reduzir a quarentena.

As contagens são diagnóstico de um snapshot, não parâmetros do sistema. O plano compilado registra cutoff/hash, versões exatas e motivos de quarentena; novas leituras podem mudar os números. Os arquivos brutos e detalhes de IDs ficam somente em `.tmp` ignorado.

## Preparação offline e contrato

Fonte de entrada:

```text
{cutoff: timestamp ISO com fuso, assignments: [export completo Aprovacao Form]}
```

Lookups de entrada: `projects`, `allocations`, `cells`, `forms`, `users`, `links`, `records`, `assignments`. Projetos e alocações precisam de `updated_at` exato. A lista `assignments` deve refletir o conteúdo completo atual da nova tabela; no primeiro preparo antes da 026 ela é vazia e o ensaio/aplicação recusam conflitos surgidos depois. Nenhum token/segredo integra esses arquivos.

O planner `desktop/src/server/bridge/form-reviewer-bootstrap.ts` agrupa a tupla explícita, exige um único aprovador coincidente em todas as fontes e preserva todos os IDs em `legacy_source_ids`, ordenados. Usa o menor ID como `bubble_id`, primeira data de criação e última modificação, mantendo microssegundos. UUID novo é determinístico pela tupla local; atribuição importada idêntica preserva seu UUID existente. Referência ambígua ou conflito local nunca é sobrescrito.

O payload da primitiva service-only `rm_bootstrap_form_reviewer_assignment_v1` possui exatamente: `id`, `bubble_id`, `legacy_source_ids`, `projeto_id`, `celula_id`, `celula_projeto_id`, `form_id`, `avaliador_user_id`, `expected_project_updated_at`, `expected_allocation_updated_at`, `created_at`, `bubble_modified_at`. O banco confere contexto/FKs, versões, proveniência e lock de projeto. Não há ator fabricado; autoria permanece nullable no metadado importado. O estado `sync_source='bubble'` distingue essa proveniência de alterações locais.

Preparar, a partir da raiz do repositório:

```powershell
node desktop/node_modules/tsx/dist/cli.mjs rm-mobile-supabase/scripts/prepare_form_reviewer_bootstrap.ts source.json lookups.json .tmp/form-reviewer-bootstrap/<run>
```

O script **não carrega `.env`, não abre conexão e não aplica SQL**. Gera `plan.json`, `summary.json`, `quarantine.json`, `rehearsal.sql`, `apply.sql` e `manifest.json` com SHA-256 dos arquivos brutos/versões/plano/SQL. O diretório de saída é restrito a `.tmp/form-reviewer-bootstrap` ignorado. O leitor opcional de origem aceita apenas GET na API Live de `rmmi`; se o tipo não estiver exposto na Data API, usa-se export autorizado pelo conector, sem fallback de escrita.

O SQL de ensaio termina em ROLLBACK; o arquivo de aplicação em COMMIT, para uso exclusivo pelo responsável após conferir o alvo/hash. Antes/depois compara integralmente as 67 tabelas RM/privadas anteriores e todas as atribuições já existentes. Depois verifica o conjunto exato das novas atribuições contra o plano: contexto, alvo, IDs e datas de proveniência, nenhuma linha extra e contagem anterior + novas. O relatório final consulta o banco para imprimir contagem real de assignments/contextos/source IDs e inserções. Replay integral idêntico deve preservar também a tabela de atribuições: 68 snapshots, nenhuma atualização.

Os arquivos revisados ficam congelados pelo `manifest.json`: conferir o SHA-256 da fonte bruta, dos lookups com as versões reais e dos dois SQL antes de executar o ensaio e a carga. Se projeto/alocação mudarem, a primitiva recusa a versão; preparar um novo plano para revisão, sem substituir silenciosamente o arquivo aprovado. O hash lógico da fonte considera os campos de atribuição e o cutoff; o hash bruto também cobre os demais campos exportados. Um grupo com mais de 100 origens e uma atribuição com autoria local entram em quarentena, em vez de perder proveniência ou falhar parcialmente.

## Validação local

Em PostgreSQL isolado com as migrações 001–026, o SQL produzido pelo mesmo compilador passou ensaio com rollback, aplicação e dois replays idênticos. A fixture inclui registro aprovado sem avaliador e uma atribuição local preexistente: ambos permaneceram integralmente iguais. A aplicação informou uma inserção e 67 snapshots preservados; cada replay informou zero inserções, as duas atribuições existentes preservadas e 68 snapshots. Esse teste usa somente dados sintéticos locais. Os sete testes TypeScript cobrem reconciliação, duplicatas, conflito/quarentena, microssegundos, proveniência, GET restrito e SQL de preservação. Isso não constitui execução remota da carga.

## Limites

Histórico Status/Historico_status/Parecer do Bubble não é transformado em decisões novas nesta carga. Nenhum registro de formulário, resposta, recibo, identidade, ACL ou modelo é criado/alterado por ela. Contexto histórico unlinked/inativo/encerrado continua somente para consulta nas operações normais; importação não é permissão para decidir ou atribuir novamente. Reimportações futuras exigem reconciliação da autoridade dos campos, não atualização automática pela ponte desativada.

## Aplicação confirmada em 30/10/2026

Após CI e ensaio026, a carga passou ROLLBACK, COMMIT e repetição idêntica no Supabase EM. Resultado real: 101 atribuições, 103 IDs de origem, 67 snapshots anteriores iguais na inserção; replay com zero inserções e 68 snapshots preservados. Os 778 registros existentes continuaram sem avaliador retroativo, incluindo os contextos aprovados. Nenhum dado fora do plano foi criado.

Cutoff `2026-10-30T11:39:10.178Z`; hash lógico da origem `25ac7a4ef4096b8464e4b9da9ea8c82050cd3f31f302c603cdeb88bcd884d606`. SQL de aplicação revisado SHA256 `2055a3020bd9f4d316955558a0228dbfb0264bd1f3566b6350efa4a052424a82`. O relatório de reconciliação conserva 442 fontes excluídas, sem apagar a origem nem extrapolar os projetos importados. [Entrega e validação](../docs/relatorio_entrega_paridade_rmmi.md).

# Atribuição de avaliador antes do registro

Contrato acordado em 30/10/2026, antes da implementação da026. Referência: [PL019 no discovery](../docs/discovery_rmmi_planejamento.md). Atribuição contextual não é decisão/histórico e não fabrica preenchimentos.

## Entidade e importação

`rm_form_reviewer_assignments` representa projeto×célula×form, com uma linha única por contexto. Guarda UUID, alocação real, avaliador designado, autoria e timestamps. FK composta com a alocação impede mudar projeto/célula silenciosamente; referências usam RESTRICT para conservar atribuição/trabalho. Proveniência: `bubble_id` canônico opcional único, `legacy_source_ids text[]`, `bubble_modified_at`, `sync_source`. Nenhuma carga é executada pela migração.

O legado AprovacaoForm não está mapeado no ETL atual; o mapping de Registro_Formulario também não importa Avaliador. Portanto NULL local não prova ausência histórica, e autor/revisor não pode ser convertido em designado por inferência. Importação separada GET-only, insert-only e com referências estritas por bubble_id resolve projeto/célula/form/avaliador/alocação existentes. Duplicatas da mesma tupla e mesmo avaliador podem ser consolidadas conservando todos os IDs de origem; contexto incompleto, divergência de avaliadores ou falta de alocação real vão para quarentena. Não criar registros, usuários, alocações, vínculos ou grants. A importação não altera registros existentes nem sobrepõe designação local. Pode preservar metadado real encerrado, aprovado, fora da lista atual ou inelegível; isso não autoriza editar/revisar nem torna o alvo elegível. Ponte de saída continua desativada.

Primitiva específica `rm_bootstrap_form_reviewer_assignment_v1(p_payload jsonb)`, execute somente service_role, com payload fechado obrigatório `id,bubble_id,legacy_source_ids,projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id,expected_project_updated_at,expected_allocation_updated_at,created_at,bubble_modified_at`. IDs de origem são únicos/não vazios e incluem o bubble_id canônico; timestamps são os reais do legado. Usa projeto11 e FKs/versões. Resultado `{status:'inserted'|'existing',id,projeto_id,celula_projeto_id,form_id}`. Existing exige alvo/contexto/proveniência idênticos e source bubble; qualquer atribuição local/conflitante gera PT409 sem atualização. Não altera registros ou cria autoria fictícia.

## Leitura

`rm_web_form_reviewer_assignments_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_eligible boolean default false)` usa JWT/RLS e DTO sem Auth/e-mail/credenciais:

- `project`: id, numero, status_pcp, data_real_de_entrega, updated_at, closed.
- `allocation`: id, projeto_id, celula_id, celula_nome, status, updated_at.
- `forms`: id, titulo, linked, assignment ou null, records, can_assign, action_reason, context_version.
- `assignment`: id, avaliador_user_id, avaliador_nome, updated_at, eligible.
- `records`: id, status, preenchido, avaliador_user_id, avaliador_nome, updated_at.
- `eligible_users`: id, nome, matricula (nullable), deduplicados e ordenados.
- `total`, `complete`, `records_total`, `records_complete`, `eligible_total`, `eligible_complete`.

Forms é a união dos formulários ligados, atribuições existentes e registros legados do projeto/célula. Formulário não ligado é consulta. Limites completos:1.000forms,2.000registros totais e1.000elegíveis. Incompletude de forms/registros devolve forms[]; elegíveis incompletos devolvem choices[]. Qualquer incompletude bloqueia o comando. Leitor sem gestão não recebe choices. Auditor não recebe choices mesmo pedindo diretamente.

Elegibilidade exige rm_user ativo com `rm_tablet_celula_users.identidade_id` na célula exata. `usuario_id` do tablet e bypass por administrador não tornam alguém candidato. A designação não concede login, capacidade, aprovação ou acesso na Central. Um designado legado inativo/desvinculado continua visível, com eligible=false.

O hash por formulário cobre versões de projeto/alocação/célula/formulário, atribuição (incluindo ausência), todos os registros desse formulário e todas as identidades/vínculos da célula, incluindo inativos que afetem elegibilidade. Não depende da exposição de choices ao cliente.

## Comando

Operação `assign_form_reviewer`, capability existente `em.planning.manage`, escritor RM ativo administrador/padrão, MFA e autorização SSO frescos inclusive no replay. O BFF exige portal/projetos/planejamento/formulários read; `forms.review` é decisão separada e não concede atribuição. Payload fechado:

```text
{projeto_id,celula_projeto_id,form_id,avaliador_user_id,
 expected_project_updated_at,expected_allocation_updated_at,
 expected_context_version,confirm_replace:boolean}
```

Não há remoção neste incremento. Versões ISO com fuso/precisão preservados; contexto/hash incorreto gera PT409. Candidato inelegível ou contexto inválido é recusado. Projeto encerrado, alocação finalizada/N/A, formulário não ligado ou QUALQUER registro aprovado tornam toda a atribuição somente leitura.

Definir/trocar aplica o designado a todos os registros existentes não aprovados e às criações futuras elegíveis. A UI mostra quantidade e divergências antes de confirmar. `confirm_replace=true` é obrigatório quando já existe atribuição OU algum registro tem avaliador não nulo diferente do novo. Reaplicar o mesmo designado pode reconciliar divergências; não mexe em respostas/status/decisões. Mesmo alvo e registros já coincidentes é no-op: preserva timestamps/autoria e grava novo recibo, sem reescrever linhas.

Resultado fechado:

```text
{operation:'assign_form_reviewer',id:assignment.id,projeto_id,
 updated_at:assignment.updated_at,
 record:{assignment_id,projeto_id,celula_projeto_id,celula_id,form_id,
         avaliador_user_id,context_version,records_updated_ids:uuid[]},
 idempotent_replay:boolean}
```

UUID da submissão permanece no envelope existente. Replay exato retorna resposta inicial com autorização atual; outro ator/corpo/operação não pode reutilizar o UUID.

## Offline, decisões e concorrência

Criação de registro consulta a atribuição no servidor e só herda avaliador ainda ativo e vinculado pela identidade à célula. Se ausente/revogado/inativo, cria normalmente sem avaliador, preservando fila/rascunho/arquivo; snapshot sinaliza atribuição desatualizada. Mobile não fornece avaliador e não precisa novo APK/tabela de pull. Recibo concluído é retornado antes de reaplicar qualquer regra nova. Novas criações continuam admitindo múltiplos registros do mesmo formulário, cada qual com seu UUID.

`review_form` mantém semântica existente: ator da decisão também vira avaliador do registro e é gravado no histórico; designação contextual é independente e não é sobrescrita pela decisão. Isso pode produzir divergência explícita após devolução administrativa, reconciliável com nova atribuição confirmada. Correção mobile mantém status/respostas/autoria/receipt existentes.

Ordem comum: autorização/recibo14(web) ou0(mobile) → projeto11 → projeto/alocação → vínculos/usuários e atribuição → registros ordenados → respostas. Criação adquire projeto11 antes da sequência do formulário. Review e correção obtêm projeto11 antes do registro; não inverter a ordem com atribuição. Locks de identidade/vínculo escolhido evitam revogação no meio da herança/atribuição. Conjuntos completos, hash e versões são reavaliados sob locks antes da escrita. Aprovação primeiro bloqueia atribuição; atribuição primeiro torna revisão antiga obsoleta. Capturas/outros trabalhos offline não são apagados.

## Reversão e validação

Reverter consumidor web sem excluir tabela/dados/recibos é seguro. Não voltar a primitiva antiga de criação enquanto houver designações usadas, nem apagar histórico para recriar atribuições. Evoluções exigem migração posterior; não editar001–025. Testes isolados devem comprovar preservação integral das67tabelas antigas no upgrade, novo destino vazio, callers aquecidos, receipts antigos, múltiplos registros, herança/revogação offline e disputas reais de atribuição/review/criação/correção.

`tests/web_form_reviewer_assignments.sql` exercita o DTO contextual, isolamento por projeto/célula/form, perfis/SSO/MFA, payload fechado e confirmação, múltiplos registros, reaplicação sem alterar respostas/status, no-op, bloqueio após aprovado, herança/revogação/UUID offline e limites completos1.000/2.000/1.000. Bootstrap tem provas de insert-only/proveniência, FK RESTRICT, preservação de aprovados e metadados closed/unlinked/inativos sem concessões.20disputas reais por dblink cobrem atribuição versus decisão/criação/correção, mesmo UUID, revogação de usuário/vínculo, bootstrap concorrente, escritor técnico de aprovação/novo registro e nome de célula nos dois sentidos. `tests/web_form_reviewer_assignments_upgrade.sql` aquece os dispatchers e primitivas antes da026, compara integralmente as67tabelas anteriores e comprova que o destino novo nasce vazio e que os receipts antigos continuam exatos. O runner isolado inclui esse upgrade e a suite junto das regressões históricas.

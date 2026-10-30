# Regras operacionais de etapas por alocação

Contrato027 acordado em30/10/2026 antes da implementação. Complementa [PL020–022](../docs/discovery_rmmi_planejamento.md) e o [consumo020](WEB_STAGE_APPROVALS.md). Reutiliza rm_aprovacoes_etapas e a transação compartilhada; não cria etapas ou decisões artificiais na instalação e não altera001–026.

## Identidade, histórico e offline

A configuração de uma regra é imutável por ID. Criar usa UUID novo. Editar qualquer configuração, inclusive bloquear avanço, cria outra regra com UUID novo e retira a anterior com ativo=false. A anterior conserva projeto/origem/destino/status/aprovadores e ID; nenhuma fila antiga será reinterpretada com destino ou autorização novos. Retirar/restaurar preserva o mesmo ID, sem hard-delete. Restore exige família inteira sem outra versão ativa, ausência de configuração efetiva ativa duplicada e destino/status original ainda compatíveis com alocação real, sem reabrir destino finalizado/N/A. Se uma sucessora já usada impedir retirada, não prometer recuperação automática de uma intenção antiga: a fila permanece preservada e exige reconciliação operacional explícita.

Um journal privado vazio stage_rule_events grava create/replace/retire/restore/use com FKs RESTRICT, projeto, etapa, relacionada, ator, log, protocolo e timestamp. Replace define arestas de linhagem, percorridas nos dois sentidos. Use registra todos os IDs efetivamente afetados pela decisão e o log disparador, de forma irreversível; não significa que todos tenham recebido uma decisão direta. Não duplica atributos da regra. Nada é gravado em tabelas antigas ao instalar027; os68snapshots anteriores permanecem íntegros.

Nulo não comprova ausência de uso: retorno pode reabrir uma liberação aprovada e limpar data/ator. Proteção considera estado/markers, decisões exatas, receipts web/mobile, outbox e journal. Logs legados da célula posteriores à criação da regra, sem vínculo exato a decisão/receipt/outbox/journal, tornam o histórico ambíguo e a regra consultiva. Não atribuir log de outra regra a esta por suposição; logs anteriores à criação não congelam uma regra nova. Retornado e regras com qualquer evidência de uso/ambiguidade não podem ser substituídos, retirados ou restaurados pelo editor.

Não existe cp.aprovacoes_etapas_ids no schema atual. As regras são vinculadas por projeto/origem e celula_projeto_id exato ou legadoNULL. Retorno não possui par1:1: consumo011 escolhe a primeira inversa Retornado e pode compartilhá-la entre liberações do mesmo trajeto. related_return_ids mostra todos os candidatos do trajeto; pair_ambiguous sinaliza ambiguidade. Regra legada com retorno relacionado não é editada/retirada por este editor; não excluir ou criar pares presumidos. managed_birth indica nascimento real pelo journal027; regra nova ainda sem uso pode corrigir/retirar a si própria mesmo se o trajeto já tiver retorno antigo, sem tocar nesse retorno. O próprio consumo existente continua criando retorno quando ocorre a liberação.

## Leitura

RPC rm_web_stage_rules_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_choices boolean default false), STABLE SECURITY INVOKER/JWT/RLS. Helper definer de leitura valida RM ativo e resume evidência/linhagem sem conceder SELECT em envelopes privados.

- project/allocation: DTOs mínimos da026, incluindo numero/celula_nome, versões, status e closed.
- rules: id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,celula_destino_nome,status_cel_proj,status,bloquear_avanco_sem_aprov,aprovador_id,aprovadores_ids,aprovadores_retorno_ids,aprovado_por_id,data_aprovacao,ativo,created_at,updated_at; approvers/return_approvers[{id,nome,matricula,eligible}]; used,history_ambiguous,managed_birth,related_return_ids,pair_ambiguous,family_ids,supersedes_id,can_edit,can_retire,can_restore,action_reason.
- Choices somente escritor: statuses[{key,label}],destinations[{allocation_id,celula_id,nome,status,updated_at,can_select,reason}],eligible_users[{id,nome,matricula,celula_ids}].
- rules_version; total (todas as regras do projeto),selected_total (origem atual),complete (total<=1000); allocations_total/allocations_complete (1000); eligible_total/eligible_complete (1000); memberships_total/memberships_complete (5000).

Rules inclui retiradas e retornos da origem. Incompletude de regras do projeto/alocações devolve rules[]; overflow de identidades/vínculos mantém consulta sem gestão e choices[]. Qualquer conjunto incompleto bloqueia comandos. Leitor sem gestão recebe choices[]. Hash cobre projeto/alocações/células, todas as regras do projeto, uso/linhagem, usuários/vínculos, inclusive inativos, sem expor dados privados.

Origem n_a e projeto encerrado são consulta. Origem finalizado continua configurável quando não há uso: existem regras que aguardam precisamente esse status. Novo destino deve ser outra célula realmente alocada no projeto, não finalizada/n_a. Aprovadores são identidades ativas TCU da origem; aprovadores de retorno vêm da célula destino. Conta usuario_id do tablet e bypass administrador não tornam candidato elegível. Listas são não vazias, sem duplicatas, com1..100IDs. Status de disparo aceita enum existente exceto Retornado; retorno é gerido pelo consumo.

## Comando e retorno

Operação manage_stage_rules, capability existente em.planning.manage, escritor RM administrador/padrão, com leituras portal/projects/planning/approvals. Decidir usa approvals.decide separadamente; configurar não concede decisão ou acesso corporativo. SSO/MFA/ator/receipt atuais são conferidos inclusive no replay. Payload fechado:

```text
common={projeto_id,celula_projeto_id,expected_project_updated_at,
        expected_allocation_updated_at,expected_rules_version}
config={celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov,
        aprovadores_ids,aprovadores_retorno_ids}
create=common+{action:'create',id,config}
replace=common+{action:'replace',etapa_id,expected_etapa_updated_at,
                replacement_id,config,confirm_change:true}
retire/restore=common+{action:'retire'|'restore',etapa_id,
                     expected_etapa_updated_at,confirm_change:true}
```

Não aceitar estado/ator/autoria/vínculos de engenharia do browser. Datas ISO preservam microssegundos. Configuração efetiva duplicada compara origem,destino,status,bloqueio e aprovadores como conjuntos, incorporando aprovador singular legado. Não impede aprovações distintas do mesmo trajeto, mas impede cópia igual ativa. Replace sempre usa ID novo; origem e projeto são fixos. No limite1000, não cabe nova versão create/replace; retire/restore permanecem disponíveis quando seguros. UUID já visto em histórico offline não pode ser reutilizado após exclusão antiga. Retire/restore sem mudança e versões atuais são no-op, preservando timestamps e gravando só recibo.

Resultado: {operation:'manage_stage_rules',id:etapa_id,projeto_id,updated_at,record:{projeto_id,celula_projeto_id,action,etapa_id,previous_etapa_id,rules_version,changed_ids},idempotent_replay}. Previous só existe no replace (null nas demais). Changed é[new] emcreate,[old,new] emreplace,[target] emretire/restore, ou[]no-op. Replay exato mantém resposta original; outro ator/corpo/operação não reutiliza o protocolo.

## Consumo, concorrência e reversão

Todos os consumidores devem reconhecer ativo=false: guardas de decisão, lista/contexto web, avanço/bloqueio de destino, seleção inversa, ocultação da origem e finalização de célula. Nenhuma decisão restaura regra silenciosamente. Snapshot detalhe retirado é consultivo; fila normal ignora retiradas. Mobile recebe tombstones pelo pull normal e apresenta somente regras ativas; não filtrar RLS ou remover registros do catálogo incremental. APK antigo pode possuir regra em cache, mas gateway recusa tentativa nova retirada com PT409 e orientação de restauração/reconciliação. Receipts já concluídos continuam replay antes da guarda; fila FIFO mantém payload/protocolo/arquivo na falha.

Ordem: autorização/receipt14(web) ou0(mobile)→projeto11→projeto/alocações→células/usuários/vínculos→regras ordenadas→journal/logs/efeitos. Executor compartilhado e envelope de decisão web participam da ordem antes de travar regra; criação/materialização respeita projeto11. Hash e provas são relidos sob locks. Mudanças não acionam Bubble/email/webhook; outbox permanece desativada e contratos de efeitos existentes são preservados.

Reversão mantém schema/journal/receipts e guardas de decisão; pode voltar consumidor web sem apagar regras/retiradas. Não remover guardas enquanto houver retiradas, reativar família por lote ou apagar histórico para liberar edição. Evoluções usam migração posterior. Validação isolada deve cobrir upgrade68snapshots e callers aquecidos, proteção por evidências, linhagem/família, confirmação, completação/limites, oldmobile/replay/restauração e disputas reais entre editor, consumo web/mobile, status, elegibilidade e inserções técnicas.

As suites `tests/web_stage_rules.sql` e `tests/web_stage_rules_upgrade.sql` cobrem esses contratos, incluindo limites1.000/1.000/1.000/5.000, autorização/SSO/MFA e confirmação literal, retiradas nos predicados de bloqueio/avanço/retorno/visibilidade/finalização, restore com destino incompatível e UUID histórico canônico.20disputas reais por dblink exercitam editor×decisão web/mobile, retry, status, revogação, inserçãoFK, tentativa de UPDATE técnico de configuração, família/restauração e fechamento. A instalação compara os68snapshots antigos integralmente e deixa o journal vazio. Nenhuma fixture é inserida em produção; os testes usam banco descartável isolado com guardas habilitadas.

## Publicação e comprovação — 30/10/2026

Consumidor `bdf182671fd2188331827eb38f973bad0d70fd82`, [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41062212110), Railway `6a67b5a4-de4e-49a2-ba28-926f13b7fed4` com `SUCCESS`. Disponível no [portal EM](https://em-web-production.up.railway.app), em **Cronograma → projeto → célula → Aprovações de etapas → Configurar regras de etapas**. O editor inicia recolhido; a tabela de decisões permanece separada e segue sua autorização própria.

A 027 foi ensaiada com rollback e aplicada no Supabase `oficina-em-mi-off`, preservando integralmente os 68 snapshots anteriores. Fonte aplicada e Git têm SHA256 `09a6e89f3795fb8bd3f15cd65c984297f1e4ad19a5cb095104e2271bb6d734db`; os finais de linha foram normalizados para LF antes do commit, sem mudar o SQL validado. Pós-aplicação: 69 tabelas públicas/privadas, 57 tabelas RM com RLS, journal novo vazio, 102 usuários, 778 registros de formulário, 14.595 fotos, 945 etapas, 101 atribuições de avaliadores, outbox 4 e quatro recibos web. SSO obrigatório, dois administradores EM, capacidades e demais identidades preservados. Nenhum backfill das regras legadas foi executado.

Passaram 262 testes desktop, 87 mobile, tipos, build, dois smokes e 16 suítes PostgreSQL, incluindo 20 disputas reais novas. Os 21 cenários de navegador usaram DOM/build real `j1nTKm9Lc-tWg_izGKCrf` e HTTP/dados simulados, sem erros de página ou rede externa; cinco capturas desktop/390 px foram inspecionadas. Em produção: health 200, 30 negações em 15 URLs e início PKCE até Microsoft, cancelando apenas o fluxo de QA. Não houve login Microsoft humano automatizado nem CRUD artificial em produção.

O [APK interno 1.2.3, código 6](MOBILE_DEPLOYMENT.md) incorpora o filtro de regras retiradas, mantendo pacote, certificado e dados locais da versão anterior. O arquivo foi validado, sem nova instalação ou homologação em tablet físico nesta rodada. A ponte de saída continua desativada. A próxima prioridade é a retirada protegida de alocações e a reconciliação entre visibilidade e filas.

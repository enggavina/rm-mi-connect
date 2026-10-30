# Disponibilidade e retirada protegida de alocações

Contrato 028 acordado antes da implementação. Reutiliza rm_celulas_projeto e os envelopes existentes. Não altera 001–027 nem grava dados artificiais em produção.

## Estado e identidade

A alocação ganha retirada:boolean NOT NULL DEFAULT false e a condição retirada implica visibilidade=false. Instalação preserva todas as colunas antigas das 69 tabelas; somente a projeção nova retirada=false é adicionada. Journal privado cell_availability_events nasce vazio e registra transições reais, autoria/protocolo e estado anterior/novo. Nenhuma permissão global ou grant de SELECT em envelopes é criado.

Retirar mantém ID e UNIQUE(projeto_id,celula_id), status, posicao, indice, prioridade, formulários, fotos, atribuições e regras. Restaurar reativa o MESMO ID sempre oculto, sem rematerializar/clonar filhos ou reaproveitar o par com outra identidade. DELETE físico e troca de ID/projeto/célula são recusados. Uma alocação retirada não aceita edição genérica ou reativação por plan_cell/materialização/ETL.

## Visibilidade e as duas ordens

A fila 021 inclui alocações abertas visíveis E ocultas, ordenadas por coalesce(posicao,indice,0),id. Finalizado/N/A e projetos encerrados saem da fila, mas uma célula finalizada ainda pode permanecer visível por aprovações pendentes. Visibilidade não é guarda de escrita e não equivale a retirada.

set_visibility altera somente a disponibilidade no mobile, sem renumerar ou reordenar outros projetos. Retirada sai da fila/carga/Gantt/roteiro ativos; restauração conserva posição/índice/prioridade e reentra apenas se preencher os mesmos critérios de abertura 021. Empates continuam determinísticos por ID. A reordenação continua exclusiva de save_cell_queue e save_project_route. Não copiar count(visíveis)+1/decremento do Bubble, pois isso conflita com a fila 021 que inclui ocultos.

## Critérios de proteção

Retirar exige projeto aberto, alocação ativa em pendente, sem histórico de status além de pendente, sem horas realizadas diferentes de zero e sem fim real. Finalizado, N/A e demais estados são consulta para retirada.

Também bloqueiam retirada:

- Qualquer registro de formulário do projeto/célula, inclusive parcial, não preenchido ou fora da lista atual.
- Rascunho de servidor compatível com projeto/formulários, ou vinculado a um registro do contexto; como o rascunho legado não tem célula, compatibilidade ambígua é protegida.
- Foto com arquivo principal ou entrada não vazia na lista de arquivos, ou selecionada para relatório, incluindo lixeira. Vínculos incoerentes são protegidos.
- Comentário/log da célula, decisão, recibo ou evento de saída de uso operacional; não atribuir comentário genérico do projeto à célula por suposição.
- Regra ativa de etapa entrando ou saindo da célula, até retirada explícita pela 027. Uso exato ou histórico ambíguo de regra relacionada bloqueia mesmo quando já retirada.

Configuração pura pode permanecer: forms_ids, slots vazios, avaliador prévio sem registro e regras retiradas ainda sem uso. Nada é apagado em cascata. Rascunhos e filas que só existem no aparelho são desconhecidos do servidor: a retirada não afirma que foram enviados. Tentativa nova posterior à retirada recebe PT409 e preserva UUID/payload/arquivo; restore do mesmo ID oculto permite retry se o contexto/filhos originais ainda forem compatíveis.

can_set_visibility exige projeto aberto e alocação ativa. Finalizado continua permitido porque pode aguardar aprovações; N/A permanece somente para consulta de disponibilidade. Restore exige projeto aberto e alocação retirada, sempre sem mudar o status original. Uma tentativa nova de restore sobre item já ativo e oculto é no-op; sobre item ativo e visível deve usar set_visibility e recebe 22023. Razões são genéricas e não expõem respostas, mídia ou identidades pelos três escopos de planejamento.

## Snapshot e comando

RPC rm_web_cell_availability_snapshot_v1(p_project_id uuid,p_allocation_id uuid), STABLE/JWT/RLS, com evidência resumida por helper definer que valida RM ativo:

- project:{id,numero,status_pcp,data_real_de_entrega,updated_at,closed}.
- allocation:{id,projeto_id,celula_id,celula_nome,status,visibilidade,retirada,indice,posicao,prioridade,updated_at}.
- TOP can_set_visibility,can_retire,can_restore,visibility_reason,retire_reason,restore_reason,in_queue,context_version.

Sem contagens/IDs/conteúdo de filhos, Auth, e-mail, URLs ou fila inteira. Context_version cobre contexto, disponibilidade e evidências/dependências relevantes, além da participação na fila, sem exigir reordenação.

Operação manage_cell_availability, em.planning.manage, escritor RM administrador/padrão e leituras portal/projects/planning. Não exige ler conteúdo de formulários/fotos/aprovações. SSO/MFA/ator/receipt são atuais inclusive no replay. Payload fechado:

```text
common={projeto_id,celula_projeto_id,expected_project_updated_at,
 expected_allocation_updated_at,expected_context_version,confirm_change:true}
set_visibility=common+{action:'set_visibility',visibilidade:boolean}
retire=common+{action:'retire'}
restore=common+{action:'restore'}
```

Resultado: {operation:'manage_cell_availability',id:allocationID,projeto_id,updated_at,record:{projeto_id,celula_projeto_id,action,visibilidade,retirada,context_version,changed_ids},idempotent_replay}. Changed é [target] ou [] no-op. No-op preserva timestamp/journal e grava só recibo. Datas mantêm precisão original. Replay exato precede as novas guardas; outro ator/corpo/operação não reutiliza UUID.

## Consumidores e serialização

plan_cell novo conserva checkbox/default de visibilidade e materialização existente. Em alocação já existente, visibilidade só é aceita se igual à atual (compatibilidade de clientes antigos); uma alteração deve usar o novo comando. Alocação retirada não aceita novos writes por esse caminho. Wrappers conferem recibos antes das guardas. Payload inválido/projeto encerrado recebe 22023; evidência de uso, contexto retirado ou versão concorrente recebem PT409.

Guardas nas primitivas compartilhadas cobrem status/comentário, criação/correção/revisão de formulário, foto com vínculo legadoNULL/opcional e decisões/efeitos de etapas em origem E destino. Ocultar uma alocação ativa não bloqueia uma tentativa offline válida. Retirar bloqueia novas mutações; receipts concluídos continuam replay. Não filtrar o pull ou RLS: visibilidade=false chega como atualização normal ao SQLite 1.2.3 e esconde a alocação sem apagar rascunhos/fila/operation(id). Não é necessário novo APK.

Ordem de locks respeita receipt14(web)/0(mobile), projeto11 antes de linhas, projeto/alocações e células em ordem compatível com 021/027. Não travar alocações de outros projetos após adquirir célula exclusiva: isso inverteria a ordem do editor 027. Não há renumeração cruzada na operação de disponibilidade. Fila021 mantém descoberta de todos os projetos da célula antes de seus locks, inclusive retirados, para detectar restauração/materialização concorrente.

Fila/carga/recebimentos/roteiro ativos excluem retiradas; consulta histórica permanece acessível para restore. hasAllocations e proteção de tipo de equipamento contam TODAS as alocações, inclusive retiradas. Recebimento sem alocação conta só ativas, mas tipo legado protegido usa a contagem histórica. Faturamento ignora obrigações puramente planejadas de pais retirados, mantendo qualquer trabalho real protegido pelo critério de retirada.

## Validação e reversão

Provar 69 projeções antigas intactas, retirada=false em todas existentes e journal vazio na instalação; sem presumir stage_rule_events vazio. Testes devem cobrir todos os bloqueios, ambos arquivos de foto, fila oculta/retirada/restaurada e posições preservadas, recibo antes de guarda, escopos/ator/MFA, replays, trigger de identidade/reativação e concorrência real com fila/roteiro/plan_cell/materialização, criação de trabalho e decisões de etapas.

Reversão conserva schema, flags, journal, IDs e guardas; pode reverter a interface mantendo leitores, lifecycle e guardas 028 compatíveis. Não remover guardas ou reativar retiradas por lote. Migração posterior é necessária para mudar o contrato.

# Manutenção da configuração do roteiro por projeto

Contrato da migração 040, em 06/11/2026. Complementa [fotos operacionais](WEB_OPERATIONAL_PHOTOS.md), [regras de etapas](WEB_STAGE_RULES.md), retirada de alocações 028, roteiro próprio 037 e histórico 038. A 039 deve estar instalada antes da 040. Os modelos dos tipos, catálogos globais e outros projetos não são modificados.

## Reutilização e proteção granular

O roteiro permanece em `rm_celulas_projeto`; fotos em `rm_fotos`, formulários em `forms_ids` e regras em `rm_aprovacoes_etapas`. A gestão de formulários reutiliza a validação de `plan_cell`, acrescentando a proteção de rascunhos e a limpeza de designações de avaliadores dos vínculos removidos. Fotos e regras mantêm os editores e gateways 025/027.

| Recurso | Evidência que preserva sua configuração | Efeito sobre outros recursos |
| --- | --- | --- |
| Vínculo de formulário | Registro iniciado, resposta parcial/final, avaliação contextual ou rascunho persistido do formulário no projeto | Outros vínculos sem uso podem ser acrescentados ou removidos. |
| Previsão de foto | Arquivo capturado ou seleção para relatório | Outra previsão sem captura pode ser substituída. Tag continua sendo metadado não destrutivo permitido. |
| Regra de aprovação | Decisão, selo de uso, journal, recibos, outbox, linhagem utilizada ou histórico legado ambíguo | Outra regra sem uso continua configurável, conforme as regras 027. |
| Ordem do roteiro | Origem e destino de aprovação utilizada/ambígua | Células sem uso podem ser reordenadas dentro dos intervalos que não deslocam posições protegidas. |

As posições protegidas são ordinais na ordem `indice nulls last, id`; não dependem de índices legados contíguos. Normalizar índices com lacunas não altera a posição operacional de uma célula protegida.

A coluna nova `rm_aprovacoes_etapas.configuracao_utilizada boolean not null default false` é um selo monotônico. Não há backfill ou inferência de decisões antigas na instalação. Em uma escrita futura, o trigger preserva qualquer evidência presente em OLD ou NEW antes de permitir a limpeza legítima do estado de decisão. Retornar/liberar pode continuar redefinindo o estado atual, sem tornar a configuração utilizada novamente editável. Tentar gravar o selo como falso não apaga uma marca já existente.

Guardas também cobrem escritas técnicas: remoção de vínculo usado, alteração destrutiva de foto capturada e desativação de regra utilizada são recusadas. O último arquivo de uma foto não pode ser apagado para simular ausência de uso. A exclusão física de um projeto pela 039 apresenta sua prova transacional privada aos guards; nenhum parâmetro de browser ou GUC habilita esse desvio.

## Consulta por alocação

RPC `rm_web_project_route_cell_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_choices boolean default false)`, restrita ao leitor interno do dossiê. Não expõe respostas, arquivos ou envelopes privados.

```text
{
  project: {id, numero, status_pcp, data_real_de_entrega, updated_at, closed},
  allocation: {id, projeto_id, celula_id, celula_nome, status,
               retirada, updated_at, forms_ids},
  forms: [{id, titulo, ativo, assigned, can_remove, reason}],
  context_version, can_edit_forms, forms_reason,
  can_remove_cell, remove_reason,
  removal_counts: {photos, rules, reviewer_assignments},
  complete
}
```

Sem choices, a lista contém os formulários atribuídos; com choices, inclui também os formulários ativos. Catálogo e vínculos têm limite de leitura de 2.000 itens; salvar aceita até 500 IDs. Um vínculo legado sem definição encontrada no catálogo preserva seu UUID em `allocation.forms_ids`, devolve `complete=false` e bloqueia edição/remoção até reconciliação. Nenhuma lista parcial é salva como se estivesse completa. Projetos encerrados, células retiradas e condições finais mantêm as restrições aplicáveis de consulta.

`context_version` cobre as versões do projeto/alocação, catálogo e provas de uso relevantes. A nova consulta de roteiro conserva o contrato anterior e acrescenta `can_reorder`/`reorder_reason` a cada item; a versão também incorpora as provas das aprovações.

## Comandos

`manage_project_route_cell` usa a capability existente `em.planning.manage`, perfil RM administrador/padrão, SSO, MFA e os recibos idempotentes atuais. O payload é fechado; não aceita ator, autoria, decisões ou alteração do modelo do tipo.

```text
common = {
  projeto_id, celula_projeto_id,
  expected_project_updated_at, expected_allocation_updated_at,
  expected_context_version, confirm_change: true
}

forms = common + {action: 'forms', forms_ids: uuid[0..500]}
remove = common + {action: 'remove'}
```

Resultado: `{operation, id: allocation_id, projeto_id, updated_at, idempotent_replay, record: {projeto_id, celula_projeto_id, action, context_version, changed_ids, retirada, forms_ids, retired_photo_ids, retired_rule_ids}}`.

O `action: 'forms'` reaproveita `plan_cell` para validar os vínculos e atualizar a alocação. Não permite remover um formulário já iniciado mesmo que ainda não tenha sido enviado como final. Rascunhos sem registro persistido também são protegidos; como não têm célula inequívoca, preservam os vínculos compatíveis do mesmo projeto/formulário.

`manage_operational_photos` ganha a ação `replace`, mantendo os campos comuns da 025 e exigindo:

```text
{
  action: 'replace', foto_id, expected_foto_updated_at,
  new_id, cadastro_foto_id, numero, descricao, tag,
  confirm_change: true
}
```

`descricao` aceita null ou até 4.000 caracteres; `tag`, null ou até 2.000. A foto deve ser uma previsão obrigatória ativa, sem captura/seleção, com título aplicável e sem duplicidade ativa. A troca retira o UUID anterior e insere um novo UUID, atomicamente. Não reinterpreta uma captura offline que ainda conheça a configuração antiga. A consulta 025 acrescenta `descricao`, `can_replace` e `replace_reason`; os demais contratos permanecem.

## Remover célula do roteiro

A operação aplica a regra existente de retirada lógica da 028. Exige confirmação e ausência de execução, incluindo status/histórico/horas, registros e rascunhos relevantes, capturas, comentários, avaliações, logs, decisões, recibos/outbox e vínculos divergentes. Regras que chegam à célula também são verificadas. Histórico estrutural de uma regra ainda não utilizada não bloqueia a remoção por si só.

Em uma única transação:

1. Retira previsões de fotos não utilizadas (`lixeira=true`).
2. Desativa regras não utilizadas relacionadas à origem/destino e registra os eventos 027 correspondentes.
3. Remove designações de avaliadores não utilizadas da alocação.
4. Limpa seus vínculos de formulários e marca a alocação `retirada=true`, `visibilidade=false`.
5. Registra o evento existente de disponibilidade e o recibo da ação.

IDs e tombstones permanecem para reconciliação offline. Entidades globais e alocações de outro projeto não são apagadas. Isso não representa a exclusão física de projeto da 039. Restaurar a alocação posteriormente não restaura automaticamente todos os vínculos retirados; exige conferência do contexto preservado.

O servidor não conhece intenções guardadas somente em um dispositivo desconectado. Se uma captura/resposta ainda não enviada encontrar uma configuração retirada, recebe conflito e conserva seu protocolo, ator, payload e arquivo locais; não é anexada silenciosamente a outra previsão/regra. Recibos concluídos continuam com replay exato. Após exclusão física do projeto pela 039, recibos redigidos são encaminhados ao guard de exclusão e retornam PT410, sem recriação.

## Transação, histórico e segurança

Ordem compartilhada: autorização → protocolo web 14 → projeto 11 → linha do projeto → alocações ordenadas → filhos ordenados → efeitos/recibo. Guards de escritas técnicas usam `FOR UPDATE NOWAIT` no projeto para evitar inversão de locks; contenção retorna PT409 e orienta reenviar o mesmo protocolo. O novo guard de rascunhos cobre também linhas sem `registro_formulario_id`, que antes não adquiriam esse lock.

Cada versão é relida sob locks antes do efeito. Uma falha após retirar filhos desfaz também essas alterações e o recibo. Outro ator, corpo ou operação não pode reutilizar o UUID. O SSO mantém seu mapa atual e acrescenta somente `manage_project_route_cell → em.planning.manage`; novas funções privadas de gestão permanecem sem EXECUTE para os papéis de aplicação; as concessões anteriores de consulta são preservadas.

O histórico 038 projeta os mesmos recibos e nomes existentes: `allocation_retire`, `form_links_changed`, `photo_retire`, `photo_add`, `stage_rule_retire`. A substituição de foto projeta retirada e inclusão separadas, usando o título gravado no contexto original; não inventa uma retirada para o novo item. Não há segunda tabela de auditoria, ponte Bubble, envio de e-mail ou webhook nesta alteração.

## Validação isolada

- `tests/web_project_route_configuration.sql`: uso parcial/rascunhos, recurso sem uso em célula já utilizada por outro recurso, troca de foto com UUID novo, proteção de configuração capturada, selo de decisão, âncoras ordinais, confirmação, rollback integral após falha entre filhos e alocação, remoção conjunta, isolamento de outro projeto/catálogos, autorização, replay, histórico e vínculo legado indisponível.
- `tests/web_project_route_configuration_upgrade.sql`: aplicação sobre estado legado com chamadas aquecidas, integridade dos dados/ACL/OIDs/policies/triggers existentes, selo sem backfill, contexto e autorização SSO anterior/novo. A instalação não insere fixtures operacionais.
- `tests/web_project_route_configuration_concurrency.sql`: sete disputas reais por duas conexões dblink: rascunho × remoção de vínculo nos dois sentidos, captura × remoção de célula nos dois sentidos, início de registro × remoção de vínculo nos dois sentidos e remoções simultâneas com o mesmo protocolo.

As suítes usam PostgreSQL descartável em loopback. Nenhum teste deve usar o Supabase de produção. A validação/publicação integrada e seus identificadores são registrados no relatório geral desta entrega.


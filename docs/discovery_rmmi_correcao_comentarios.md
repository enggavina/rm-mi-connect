# Discovery funcional — correção de comentários

Data: 30/10/2026. Referência: Bubble `rmmi`, versão **Live**, e contrato EM até a migração **031**. Foram relidos o tipo `custom.comentarios`, o grupo `comij` com seus filhos, o evento `comnJ`, a ação `comnP` e o popup `commg` da página `projeto` (`coiiy`). A inspeção foi somente leitura de metadata: nenhum workflow, binding, exclusão, envio ou mudança de branch foi executado. A configuração não comprova uma execução humana com dados reais.

## Comportamento configurado no Live

| Evidência | Comportamento observado | Consequência para o EM |
| --- | --- | --- |
| `custom.comentarios` | Quatro campos personalizados: autor (`cadastrado_por1_user`), célula, texto (`evento_text`) e projeto; sem versão, justificativa ou histórico de correções no tipo lido. | Reutilizar o comentário existente e acrescentar histórico próprio; não reatribuir sua autoria ou criar uma segunda conversa. |
| Regra `comments_rule_` | Permite auto-binding somente de `evento_text`, com condição `This Comentarios's Evento is not empty`. A regra não compara autor com usuário atual. | A permissão ampla do legado não constitui autorização EM para corrigir qualquer texto. |
| Grupo `comij`, input filho `comlu` | A linha aponta para `Current cell's Comentarios`; o MultiLineInput possui `auto_binding=true`, `bind_field=evento_text` e alerta “Feito! Comentário alterado com sucesso.”. Os condicionais lidos tratam hover e validade, sem condição de autoria. | O alvo é o comentário da linha. O EM deve usar ID/projeto exatos e confirmação explícita, com servidor verificando acesso e versão. |
| Evento `comnJ`, ação `comnP`, popup `commg` | Exclui fisicamente `Parent group's Comentarios` após confirmação; o popup informa perda definitiva. | Não reproduzir essa exclusão no incremento de correção. |

A leitura dos nós acima não equivale à auditoria integral das guardas dos ancestrais da página ou de todas as suas ações. Não foi encontrado, nesses nós, protocolo de concorrência, justificativa, histórico ou restrição por autoria que pudesse ser copiado como contrato de correção. O novo fluxo EM deve declarar suas diferenças deliberadas em relação ao auto-binding.

## Entidade e escritores atuais no EM

`rm_comentarios` (002) possui ID estável, `bubble_id`, projeto obrigatório, célula e autor opcionais, `evento` obrigatório, slug, datas, origem de sincronização e data Bubble. O campo não distingue, sozinho, comentário manual, comentário automático e observação de decisão. A edição exclusiva de texto não pode modificar projeto, destinatário, autor, data de criação ou identificadores de origem. `sync_source` é metadado do último escritor, não prova suficiente de origem funcional.

| Consumidor | Contrato existente | Proteção necessária |
| --- | --- | --- |
| Web `add_project_comment` (029) | Cria ID igual ao protocolo; autoria do servidor; célula ativa do próprio projeto; texto até 10.000; recibo privado com operação e resultado. | O recibo é evidência durável de criação manual. Preservar o comentário e o recibo original após corrigir o texto. |
| Mobile `rm_add_cell_comment_v1` / helper `add_cell_comment_v1` (011, envelopado e protegido em 028) | Cria comentário para a célula acessível, com autoria RM delegada, protocolo e resultado com `comentario_id`. Não há operação mobile de edição. | Um recibo mobile concluído pode provar criação manual quando ID, operação, projeto/célula e autor concordam. Corrigir texto não exige limpar ou reescrever filas/rascunhos. |
| Observação de etapa (011/020) | Decidir etapa pode criar comentário. `rm_web_stage_decisions.comentario_id` liga algumas observações à decisão e mantém a observação original no registro de decisão. | Comentários vinculados a decisões devem permanecer somente para consulta; uma correção genérica não pode reescrever a evidência de aprovação. O vínculo cobre decisões web, não classifica por si só todo o legado. |
| Recebimento/QR (006) | O envelope pode acrescentar comentário geral `QR do recebimento: …`, sem célula, após concluir o recebimento. | Não tratar todo comentário sem célula como manual; não classificar pela aparência do texto. |
| Bridge/importação | O mapping `comentarios` transporta projeto, célula, autor, evento e criação. A entidade também é exportada por `Comentario_Celula`. | Importações e gravações externas podem disputar o texto. Depois de uma correção protegida, escritores externos precisam respeitar o histórico e devolver conflito em vez de sobrescrever. A ponte permanece desativada. |

O mobile consulta comentários por projeto/célula e ordena por `created_at`. Mantendo ID, projeto, célula, autor e criação, a correção preserva a identidade da conversa; `updated_at` permite a atualização pelo pull existente. O consumidor atual não representa histórico de correções e não deve receber uma lista artificial de comentários duplicados como substituto de versões.

## Integridade, acesso e limites

- A 011 revoga INSERT/UPDATE/DELETE diretos de `authenticated`; os comandos passam pelos envelopes autorizados. Não abrir escrita direta, auto-binding ou acesso ao diário privado para implantar a correção.
- A guarda `rm_guard_allocation_child` da 028 já atua em `rm_comentarios` para inserção, atualização e exclusão. Alocação retirada bloqueia novas mudanças; célula apenas oculta continua ativa. Preservar essa guarda e a ordem de locks usada pelos escritores de projeto.
- A 030 consulta comentários com busca/filtros/paginação no servidor e DTO mínimo, sem `updated_at`, protocolo ou origem. Acrescentar um snapshot contextual de um comentário selecionado evita alterar o contrato do leitor paginado aplicado.
- `em.projects.manage`, leituras de portal/projeto/histórico e os perfis RM atuais são a base de autorização. A existência de um botão não substitui SSO/MFA e capacidade atuais no servidor, inclusive para recuperar um recibo.
- O autor original é diferente do autor da correção. Exibir essa distinção, preservar a autoria original e registrar editor/data/justificativa no histórico. Uma política conservadora é autor corrigir seus próprios comentários manuais e administrador corrigir os demais com justificativa; esse recorte é uma decisão EM, não uma restrição comprovada do Bubble.

## Direção recomendada para o incremento 032

1. **Delimitar os comentários corrigíveis por evidência de origem.** Recibos de criação manual web/mobile podem comprovar a intenção; textos importados, registros sem prova e observações de decisão permanecem legíveis. Não inferir origem por prefixo, autor, célula ou `sync_source` isoladamente. Se o incremento inicial aceitar somente os comentários web criados pela 029, registrar esse limite explicitamente.
2. **Corrigir somente `evento`.** Preservar ID, projeto, destinatário, autor/criação e metadados de identidade. Não oferecer exclusão ou troca de destinatário. Exigir texto não vazio até 10.000 caracteres, confirmação e justificativa conforme o contrato final.
3. **Versionar e auditar a mudança.** Revalidar comentário, projeto, alocação e versões dentro de locks compatíveis; registrar antes/depois, editor e protocolo em diário privado. Consulta do histórico deve retornar apenas dados permitidos e rótulos de autoria, sem Auth UID, tokens ou recibos privados.
4. **Preservar a intenção na retentativa.** Mesmo ator/UUID/corpo retornam o recibo concluído após autorização atual. Conflitos exigem nova consulta; nunca criar outro protocolo ou descartar a intenção pendente automaticamente. Sem mudança efetiva, não inventar edição ou timestamp.
5. **Cobrir escritores externos e consumidores anteriores.** Uma atualização fora do comando não pode apagar texto corrigido/histórico. Testar importação concorrente, duas correções, encerramento, retirada da alocação, replay, negações de acesso e comentários automáticos. Manter creation/pull/offline anteriores e os dados de produção intactos.

As recomendações acima não são declaração de funcionalidade pronta. O contrato final, a implantação da migração 032 e as provas de publicação pertencem à entrega de implementação.

Fontes locais: migrações 002/004/006/011/020/028/029/030, `desktop/src/server/bridge/mapping.ts`, `desktop/src/server/bridge/engine.ts`, `mobile/src/core/types.ts`, `mobile/src/domain/project-actions.ts`. Evidências Live relidas e ignoradas pelo Git: `.tmp/discovery-comment-correction/`; revisão anterior de criação: [discovery_rmmi_dossie_operacional.md](discovery_rmmi_dossie_operacional.md).

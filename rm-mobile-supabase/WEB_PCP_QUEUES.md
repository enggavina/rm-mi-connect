# PCP: filas de células, recebimentos e carga informada

Contrato do incremento **3B.1** do [plano de paridade](../plano_paridade_rmmi_web.md), em 29/10/2026. A entrega acrescenta priorização/ordenação explícita dos trabalhos abertos de cada célula, triagem dos projetos ativos com pendências de identificação/alocação e consulta das estimativas de horas existentes. Capacidade disponível, distribuição diária, lotes de produção e encerramento completo permanecem fora deste incremento. A publicação final é registrada no [portal web](../desktop/docs/web-platform.md).

## Jornada e autorização

- `/planejamento/fila?cell=UUID`: o usuário escolhe a célula, confere a fila completa e altera prioridades ou posições. A seleção é explícita; o editor não usa uma página parcial, busca ou filtro para definir o conjunto a salvar.
- `/recebimentos`: projetos ativos sem número de OS, sem tipo de equipamento ou sem célula alocada. Busca e filtros têm paginação/total reais. Links abrem a consulta, a edição de identificação ou o planejamento já existentes, conforme as permissões atuais.
- `/planejamento/carga`: trabalhos abertos por célula, visíveis/ocultos, bloqueados, com prazo vencido, com/sem estimativa e horas informadas. Ausência de horas é exibida como ausência de estimativa, preservando a diferença para uma estimativa real de zero.

Fila, carga e escolhas de células exigem `em.portal.read` e **`em.planning.read`**. Salvar a fila exige **`em.planning.manage`** e perfil RM ativo `administrador` ou `padr_o`, como o planejamento existente; auditor consulta. Recebimentos exigem **`em.projects.read`**. Editar identificação e alocar continuam usando as capacidades e regras específicas já existentes.

Não há capacidade nova nem alteração de concessões na Central. O consumidor permanece com 18 capacidades; `mgavina` e `softdev05` continuam administradores do EM, sem mudança de papel global. A identidade do autor vem da sessão; o navegador não pode informar outro operador.

O DTO da fila contém somente os campos operacionais da alocação e seus rótulos exportados de OS/cliente/tipo, sem carregar um DTO completo de projeto. Um leitor do planejamento não herda acesso a fotos, documentos, dados Auth ou demais detalhes do projeto. Links de projeto dependem também de `em.projects.read`.

## Prioridade e sequência são decisões separadas

As cinco prioridades canônicas são `muito_baixa`, `baixa`, `media`, `alta` e `muito_alta`, além de `null` para ausência de classificação. Alterar prioridade **não** reorganiza automaticamente a sequência. O mobile já consome a ordenação por `posicao`, usando `indice` como alternativa; o editor mantém esses campos até uma confirmação explícita de nova ordem.

O conjunto da fila inclui as alocações da célula que não estão `finalizado`/`n_a`, pertencentes a projetos sem entrega realizada e sem status `cancelado`/`finalizando_para_faturar`. Alocações visíveis e ocultas entram no mesmo conjunto e são identificadas na tela. Estados nulos não são tratados como concluídos.

Ao alterar somente prioridades, `apply_order=false`: a ordem do array deve permanecer igual à lida, as posições continuam intactas e somente as prioridades realmente alteradas provocam UPDATE. Ao mover um trabalho ou confirmar expressamente a sequência exibida, `apply_order=true`: a ordem do array define `posicao=1..N`. Mesmo nesse caso, linhas sem alteração de prioridade ou posição não têm seus timestamps alterados.

Índices legados, status, visibilidade, bloqueios, responsáveis, formulários e trabalhos concluídos não são reescritos pelo lote. Trabalhos concluídos que ainda aparecem no mobile por necessidade de aprovação permanecem sujeitos ao fluxo operacional existente; o editor organiza os trabalhos **abertos**, sem remover os demais.

A fila tem limite explícito de **2.000 alocações**. Se o total ultrapassar esse limite, o snapshot retorna `complete=false` e nenhum item editável; a interface oferece consulta do planejamento. Um subconjunto nunca é apresentado como a fila completa.

## Leitura consistente

A migração **021** acrescenta três RPCs `STABLE SECURITY INVOKER`, executadas com o JWT local e RLS:

```text
rm_web_cell_queue_snapshot_v1(p_cell_id uuid)
  → {cell:{id,nome,updated_at},items,total,queue_version,complete}

rm_web_planning_load_v1()
  → {as_of,cells:[contagens e horas informadas por célula]}

rm_web_receivings_v1(
  p_reason text='all',p_search text='',p_page integer=1,p_page_size integer=25
)
  → {items,total,page,page_size,summary}
```

O snapshot da fila associa os membros e suas versões em um único comando. `queue_version` é um hash opaco do estado da célula, da sequência de membros e dos timestamps das alocações/projetos. `updated_at` continua como texto exato, inclusive microssegundos; o BFF e o navegador não fazem uma conversão por `Date` antes do envio.

As horas são strings decimais no contrato de leitura. Totais e contagens vêm do banco sobre o conjunto completo de trabalhos abertos; não são a soma de uma página de alocações. `planned_hours=null` significa que nenhuma estimativa foi informada naquele conjunto. Uma soma de horas conhecidas não comprova uma carga completa quando há alocações sem estimativa, nem fornece um denominador de capacidade. Não há percentual de ocupação ou horas disponíveis inventados.

O prazo considera o dia local de São Paulo inclusive, como o cronograma: uma alocação com prazo hoje não é contada como vencida durante o próprio dia. O banco compara os dias locais, não o horário de meio-dia usado pelos inputs de planejamento.

Os DTOs do BFF selecionam campos explícitos, verificam célula/membros únicos/completude, coerência das contagens e filtros e removem metadados privados ou URLs adicionais. As capacidades corporativas são verificadas pelo BFF a cada requisição; as leituras REST legadas continuam seguindo a identidade RM ativa e RLS, como nos demais módulos.

## Triagem de recebimentos

Os filtros são `all`, `without_number`, `without_type`, `without_allocation`, `awaiting_arrival` e `legacy_type_locked`. A base de `all` contém somente projetos ativos com pelo menos uma das três pendências de OS/tipo/alocação. Ausência de chegada é uma indicação/filtro dentro dessa base; não insere projetos já identificados e alocados na fila apenas por faltar uma data histórica.

`summary` conta a base ativa completa antes de busca/filtro/página. Os motivos podem coexistir e suas contagens não devem ser somadas como se fossem projetos distintos. `items` e `total` correspondem aos filtros atuais. A lista não inclui URLs de NF, fotos ou documentos.

Sem chegada registrada, a tela informa **Aguardando chegada**. Sem tipo em um projeto já alocado, informa **Tipo legado exige revisão**: a proteção existente impede mudar o tipo depois de alocar células, para preservar modelos, fotos, etapas e registros. A entrega não desbloqueia esse campo nem atribui um tipo automaticamente.

O preflight dos dados ativos encontrou 178 projetos, 107 com alguma dessas pendências: zero sem OS, 96 sem tipo e 14 sem alocação; 93 faltas de tipo já tinham alocações. Nenhum deles foi corrigido artificialmente. O inventário encontrou 29 células, 1.429 alocações, 757 trabalhos abertos, 115 posições ausentes e nenhuma estimativa de horas. Esses números descrevem o estado anterior à entrega, não parâmetros fixos da aplicação.

## Escrita transacional e concorrência

A Server Action `saveCellQueue` usa a operação **`save_cell_queue`** no envelope `rm_web_mutate_v1`:

```json
{
  "submissionId": "UUID do envio",
  "celula_id": "UUID da célula",
  "expected_queue_version": "hash exato do snapshot",
  "apply_order": false,
  "items": [
    {"id": "UUID da alocação", "expected_updated_at": "versão exata", "prioridade": "alta"}
  ]
}
```

O envelope separa `submissionId` do payload. Itens repetidos, campos de autor/status/posição arbitrária, prioridades desconhecidas, versões ausentes e listas parciais são recusados. A prioridade pode ser `null`; cada item deve constar uma única vez. A ordem completa somente é aplicada quando `apply_order=true`.

O core verifica perfil ativo, MFA/TOTP quando cadastrada e a permissão SSO de uso único vinculada à sessão, UUID, operação, conteúdo e **`em.planning.manage`**. Um replay também exige nova validação central e permissão, preservando o mesmo UUID/conteúdo.

Os bloqueios seguem a ordem dos escritores existentes: projetos relacionados à célula, em ordem UUID e com a chave operacional `project11`; proteção dos projetos, inclusive os atualmente encerrados; célula pai e linhas de alocação. A proteção da FK serializa novas alocações, e as versões são relidas antes de qualquer alteração. Mudanças de composição, estado, projeto, célula ou versão resultam em `PT409`, sem sobrescrever o mobile ou outro planejador. Uma inserção que ocorra depois do ponto de serialização permanece uma nova alocação, sem ser alterada pelo lote anterior.

O recibo privado conserva payload, snapshot anterior, resultado e autoria. A interface congela o lote inteiro após falha de transporte ambígua, permitindo confirmar o mesmo envio sem duplicar efeitos. Após conflito, exige uma nova leitura; não reaplica uma intenção antiga sobre a fila nova. O BFF devolve somente o envelope público mínimo, sem enviar os snapshots privados ao navegador.

Instalar a 021 não altera dados de negócio nem cria tabelas públicas ou registros de fila. Não muda credenciais, identidades, delegações ou o schema SQLite. Eventos normais dos UPDATEs continuam seguindo os contratos existentes, e o worker permanece **`SYNC_OUTBOX_ENABLED=false`**. Esta entrega não envia emails, chama webhooks ou grava no Bubble.

## Validação e publicação

Aplicar somente a migração nova **021** após validar o upgrade e as suítes PostgreSQL isoladas. As migrações 001–020 já aplicadas não devem ser editadas. A aplicação remota usa snapshots completos das tabelas públicas RM e privadas para comprovar ausência de mudanças de negócio durante a instalação.

Os testes BFF cobrem escopos independentes, DTOs mínimos, completude/overflow da fila, datas exatas, motivos consistentes, paginação real, ausência de estimativas versus zero, proteção do ator e do protocolo, replay e resultados sanitizados. Os testes SQL exercitam as transações, os conflitos e os efeitos reais do lote em banco isolado. As provas finais de CI, interface, migração e deploy serão registradas no plano e na documentação do portal; não equivalem a login humano Microsoft ou mudanças artificiais de prioridade em produção.

Na QA de produção local foi reproduzido React `#418`: o shell cliente esperava `<main>` enquanto o cursor já estava no marcador Suspense do carregamento dentro desse elemento. A correção mantém main/footer no layout servidor e estabelece um limite Suspense **antes** de main, preservando SSR e o indicador de carregamento. Apenas transferir main para o servidor não foi suficiente no controle. A variante completa passou duas execuções de 17 cenários e 100 navegações; o build principal final passou 17 cenários e 30 navegações adicionais, sem interceptação de JavaScript, erros de página ou rede externa. As provas de controle que falharam foram preservadas; os erros não foram suprimidos.

Referências: [migração 021](migrations/021_rm_web_pcp_queues.sql), [leituras BFF](../desktop/src/server/web/pcp-data.ts), [política](../desktop/src/server/web/pcp-policy.ts), [ações](../desktop/src/server/web/pcp-mutations.ts), [planejamento existente](migrations/014_rm_web_management.sql) e [ponte SSO](SSO_BRIDGE.md).

Publicado em 29/10/2026 no consumidor `37b54866762022da6b0d5fe44dd663ee3dba2fa0`, Railway `9d06331d-6764-4cc8-ab0c-f1197fe3cb88` com `SUCCESS` e [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/40926891591). Passaram 188 testes desktop, tipos, build, dois smokes, dez suítes PostgreSQL e a validação de interface descrita acima. A 021 preservou 67 snapshots completos, 102 usuários, 945 registros de etapas, outbox 4 e receipts 2. Fonte SHA256 `ca096c9fffa82693776226fd0e09309ee6a65ab61aa74836708279f1f6bec417`, aplicada e imutável. Em produção: health 200, três rotas com seis negações anônimo/cookie forjado e SSO/PKCE até Microsoft, cancelando apenas o fluxo de QA. Sem novas concessões ou deploy da Central, login humano automatizado ou CRUD artificial.

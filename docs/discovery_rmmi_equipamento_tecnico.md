# Discovery funcional — dados técnicos do equipamento

Data: 30/10/2026. Fonte principal: metadata **Live** do Bubble `rmmi`, comparada ao EM até a migração **030**. Foram consultados os tipos `custom.dados_equipamento` e `custom.projeto_rm`, os option sets, os fluxos de cadastro/edição de `rm_planejamento` e os fluxos de recebimento de `rm_mobile`. As páginas `projeto`, `project_rm`, `projeto_mobile` e `proposta` foram consultadas para localizar consumidores e distinguir dados persistidos de edição efetivamente configurada.

A revisão foi somente leitura. Não foram executados workflows, alterados registros, enviados arquivos/mensagens ou feitas mudanças de branch no Bubble. Metadata ativa comprova a configuração, mas não comprova que um usuário executou o fluxo com sucesso em produção. Os IDs abaixo são IDs de nós, não dados de teste.

## Fluxos observados no Live

| Fluxo | Evidências | Comportamento configurado |
| --- | --- | --- |
| Abrir edição pela lista de projetos | Página `rm_planejamento` (`cnsnM`), ícone `coeqW`, evento `coeqq`, ação `coerB`, popup `cnwVc0` | O ícone “Editar” leva `Parent group's ProjetoRM` ao popup `PopUp Formulario projeto`. A origem é a linha exata da lista, não uma busca por número/nome. |
| Salvar equipamento existente | Evento `cnxYY`, ação `coerT` | Quando o ProjetoRM do popup não está vazio, altera o **Equipamento referenciado pelo ProjetoRM**: série, descrição, placa, fabricante, modelo e potência. `workflow_disabled=false`. O workflow também altera dados do projeto em outra ação. |
| Criar projeto/equipamento pelo popup | Evento `coerG`, ações `coerI/coerM/coerN` | Quando o popup está vazio, cria projeto e equipamento, preenche `Equipamento.ProjetoRM` e liga `ProjetoRM.Equipamento`. A ação de criação `coerM` preenche somente projeto, série, descrição e placa. Fabricante/modelo/potência aparecem como inputs, mas não estão nessa ação de criação: assimetria observada, não requisito a reproduzir. |
| Editar dados básicos na requisição | Evento `coenu0`, ação `coeoC0` | Altera série, descrição e placa do equipamento apontado por `FloatingGroup Nova requisição de numero de projeto's projetoRM`. |
| Cadastro antigo em `proposta` | Evento `codrj`, ações `codrk/codro/codrp` | Evento explicitamente habilitado; cria projeto, equipamento e vínculo reverso. `codro` recebe série, modelo, tensão, tipo de tensão, corrente e componentes. Não foi comprovado o acesso operacional completo a esse popup nesta revisão. |
| Tipo ao liberar requisição em `proposta` | Ações `coeBx/coeGp` | Altera `tipo_equipamento_custom_tipo_equipamento` do equipamento já referenciado pelo projeto. É classificação ligada ao planejamento, distinta da correção de placa/dados técnicos. |
| Recebimento atual no mobile Bubble | Grupo `cnqwP`; evento `cojXG`, ações `cojXI/cojXM/cojXN` | Os inputs atuais são cliente, chegada, nota fiscal/arquivo, descrição, placa, eventualidades e fotos. `cojXM` cria equipamento apenas com projeto, descrição e placa, se o estado do projeto estiver vazio. Não contém as antigas etapas elétricas/construtivas. |

O ícone `coeqW` consulta `Elementos.codigo = PL009` e verifica se `permissoes` contém `Current User`; quando não contém, aplica `button_disabled=true`. Isso é evidência de uma permissão legada da interface. Não autoriza copiar concessões por nome/e-mail, abrir acesso geral ou administrar a Central de Acessos. O EM deve usar suas capacidades e vínculos atuais, com verificação no servidor.

Os seis inputs de equipamento do popup de planejamento são `coaQR` (série), `coaQL` (descrição), `coepW` (placa), `coosW` (fabricante), `coosu` (modelo) e `cootS` (potência). Os inputs de texto explicitam `content_format=text` e não são obrigatórios. Em particular, a potência é **texto livre**, sem seletor de unidade, mínimo, máximo ou conversão numérica demonstrados no nó. O dropdown de placa não é obrigatório nesse popup; no recebimento mobile Live (`coegg`), está configurado como obrigatório. Não transplantar essa diferença silenciosamente entre jornadas.

## Contrato de campos e unidades

O tipo Live `custom.dados_equipamento` possui **31 campos personalizados**, todos escalares (`isList=false`): 22 textos, três números, quatro opções e duas referências. Os campos nativos de criador, datas e slug são adicionais. Não há unidade separada nem lista oficial de potências/tensões nesse tipo. Os valores textuais devem preservar unidades, separadores, intervalos e símbolos já armazenados; não escolher automaticamente CV/kW, V, A, Hz, rpm ou kg.

| Coluna EM (002) | Chave Bubble Live | Caption Live | Tipo e limite verificados |
| --- | --- | --- | --- |
| `descricao` | `descri_ao_text` | Descriçao | `text`; editável no popup ativo |
| `numero_serie` | `n__serie_text` | N° serie | `text`; editável no popup ativo |
| `placa_motor` | `placa_motor_option_placa_motor` | Placa_motor | Opção; editável no popup ativo |
| `fabricante` | `fabricante_text` | Fabricante | `text`; editável no popup ativo |
| `modelo` | `modelo_text` | Modelo | `text`; editável no popup ativo |
| `potencia` | `potencia_text` | Potencia | `text`; editável no popup ativo; nenhuma unidade imposta |
| `embarcacao` | `embarca__o_text` | Embarcação | `text`; persistência comprovada; editor ativo completo não comprovado |
| `certificado` | `certificado_text` | Certificado | `text`; persistência comprovada |
| `norma` | `norma_text` | Norma | `text`; persistência comprovada |
| `rotacao` | `rota_ao_text` | Rotaçao | `text`; persistência comprovada |
| `tensao_estator` | `tensao_estator_text` | Tensao | `text`; cadastro antigo `codro`; caption não contém “estator” |
| `tipo_tensao` | `tipo_tensao_text` | Tipo tensao | `text` livre; não foi demonstrado catálogo CA/CC |
| `corrente_estator` | `corrente_estator_text` | Corrente estator | `text`; persistência comprovada |
| `corrente_partida` | `corrente_partida_text` | Corrente | `text`; cadastro antigo `codro`; caption não prova que o usuário entendia “partida” |
| `frequencia` | `frequencia_text` | Frequencia | `text`; persistência comprovada |
| `classe_isolamento` | `classe_isolamento_text` | Classe isolamento | `text`; sem catálogo demonstrado |
| `grau_ip` | `grau_ip_text` | Grau IP | `text`; sem máscara demonstrada |
| `forma` | `forma_text` | Forma | `text`; persistência comprovada |
| `regime` | `regime_text` | Regime | `text`; persistência comprovada |
| `peso` | `peso_text` | Peso | `text`; nenhuma unidade imposta |
| `ligacao` | `liga_ao_text` | Ligaçao | `text`; persistência comprovada |
| `componentes` | `componentes_text` | Componentes | `text`; cadastro antigo `codro` |
| `fp` | `fp_number` | Fp | Bubble `number`, SQL `numeric`; faixa de domínio não demonstrada |
| `fs` | `fs_number` | Fs | Bubble `number`, SQL `numeric`; faixa de domínio não demonstrada |
| `numero_cabos` | `n__cabos_number` | N° cabos | Bubble `number`, SQL `integer`; diferença de contrato já existente |

Não foi comprovada uma interface Live ativa que edite todos os 25 campos acima. Exibi-los num editor técnico completo do EM é uma ampliação deliberada dos consumidores dos dados existentes, não uma afirmação de paridade de tela já demonstrada. Limites de texto e validações novos devem ser declarados como contrato EM; não atribuí-los ao Bubble sem evidência.

Os outros campos personalizados são vínculos/compatibilidade:

- `projetorm_custom_projeto_rm` → `rm_equipamentos.projeto_id`: referência a ProjetoRM, sem lista. Não deve ser editável como dado técnico.
- `tipo_equipamento_custom_tipo_equipamento` → `tipo_equipamento_id`: referência ao catálogo. Mudança pode afetar células/formulários/fotos e requer o fluxo próprio de classificação/planejamento.
- `supabase_id_text`: texto de integração presente no Bubble; não é o ID de equipamento que o usuário deve escolher e não tem coluna de negócio homônima em 002.
- `desmontar_para_or_ar_option_sim_ou_nao`, `ensaiar_antes_desmontar_option_sim_ou_nao` e `teste_intermediario_option_sim_ou_nao` → flags legadas. Permanecem armazenadas; o usuário pediu removê-las do recebimento mobile. Sua existência no schema não autoriza reintroduzi-las na jornada.

`option.placa_motor` contém exatamente `c___placa` → **C / placa** e `s___placa` → **S / placa**. `option.sim_ou_nao` contém `sim` → **Sim** e `n_o` → **Não**. Os enums EM de 001 usam esses mesmos slugs. Ausência de opção é `null`, não uma terceira opção presumida.

## Vínculo canônico e cardinalidade

Em 002, `rm_equipamentos.projeto_id` é uma FK opcional com `UNIQUE`, e `rm_projetos.equipamento_id` é outra FK opcional, na direção inversa. O banco impede dois equipamentos com o mesmo `projeto_id` não nulo. Essas duas constraints, isoladamente, **não** garantem que as direções concordem: permitem equipamento sem proprietário, projeto apontando para equipamento de outro projeto e vários projetos apontando para o mesmo equipamento. “Um equipamento por projeto” é intenção observada nos workflows, não uma integridade integralmente imposta pela 002.

O leitor web anterior à 031, em `desktop/src/server/web/data.ts`, consulta equipamentos filtrando `projeto_id=id` e resolve `find(row.id === project.equipamento_id) || equipmentRows[0] || null`. O fallback pode exibir outra linha quando o vínculo reverso diverge e nem consulta o alvo reverso que pertence a outro projeto. Não usar essa seleção implícita para autorizar edição.

O contrato de edição deve resolver o par explicitamente e revalidá-lo sob bloqueio na transação: ID do projeto, ID exato do equipamento e propriedade nos dois sentidos. Referência ausente, divergente ou compartilhada deve gerar estado legível de indisponibilidade/conflito; não reparar vínculos, criar equipamento, substituir ID ou escolher a primeira linha como efeito lateral de salvar. Projetos sem equipamento precisam de uma entrega própria de cadastro/reconciliação. Não copiar esse fallback para fotos, documentos, formulários ou ensaios.

O preflight somente leitura da implementação 031, restrito ao Supabase `oficina-em-mi-off`, mediu **178 projetos e 178 equipamentos**, com **178 pares bidirecionais próprios e não compartilhados**. Encontrou zero projetos sem os dois vínculos, equipamentos próprios sem vínculo reverso, ponteiros estrangeiros, equipamentos órfãos e referências reversas compartilhadas. Evidência agregada: `.tmp/equipment-inventory.json`; não são reproduzidos registros de clientes neste documento. A ausência de divergências nessa fotografia não elimina a necessidade das guardas transacionais. A comparação complementar de tipos encontrou divergências entre a classificação no projeto e no equipamento; por isso esses IDs não devem ser sincronizados como efeito lateral da edição técnica.

## Comparação com bridge, recebimento e offline

| Consumidor existente | Evidência local | Consequência |
| --- | --- | --- |
| Mapping Bubble → EM | `desktop/src/server/bridge/mapping.ts` | `Tensao` → `tensao_estator` e `Corrente` → `corrente_partida` **estão coerentes com os captions Live**, apesar dos nomes internos diferentes. Não trocar esses aliases por inferência. `embarcacao` existe em Live/SQL e está ausente desse mapping. |
| Importação de equipamento | `bridge/engine.ts`, `batch-importer.ts` | Traduz referência e opções; os campos textuais não têm conversão numérica específica. Depois da importação, recompõe `ProjetoRM.equipamento_id`. Isso é comportamento do importador, não autorização para ativar a ponte ou reimportar registros após edição local. |
| Recebimento inicial | `003_rm_workflows_rpcs_and_triggers.sql`, alterada aditivamente por 006/011 | Cria projeto/equipamento e o vínculo reverso; extrai campos textuais de `p_equipamento` por `->>`. `fp/fs` fazem cast numeric e cabos integer. Um valor JSON composto indevido pode terminar como texto; schema escalar não prova que toda carga histórica é um texto simples. |
| Atualização por QR/recebimento | `rm_private.update_recebimento_v1`, 006, com alterações da 011 | Procura equipamento pelo `projeto_id`, ordena/limita a primeira linha e regrava o vínculo reverso; aceita patch por presença de chave numa allowlist técnica. Não possui, nessa definição-base, protocolo de versão da edição técnica web. |
| Rascunho mobile atual | `mobile/src/domain/receiving.ts` | `restoreReceiving` preserva `equipamento` e snapshot legado; `receivingPayload` envia `{ ...data.equipamento, descricao, placa_motor }`. Novos rascunhos não fabricam campos removidos, mas antigos ainda podem enviar dados técnicos. Não descartar esse patrimônio nem limpar filas locais. |
| Envelope numérico legado mobile | `receivingPayload` | Converte vírgula decimal apenas para `fp/fs/numero_cabos` preservados; exige cabos inteiro não negativo para converter. Não transforma potência, tensão ou corrente em número. |
| Descrição duplicada | `011_rm_project_operations.sql` | O gateway injeta `p_descricao_equipamento` em `p_equipamento.descricao` e também atualiza `rm_projetos.descricao_equipamento`. A edição web de descrição precisa definir a consistência entre esses dois consumidores sem atualizar silenciosamente os demais campos do projeto. |

Nenhum campo técnico é lista no tipo Bubble inspecionado. Se o inventário encontrar strings JSON como `[...]` ou `{...}`, elas são **representação histórica a preservar**, não um catálogo de unidades nem autorização para usar somente o primeiro item. Não parsear, juntar, converter ou regravar um valor legado apenas por abrir/salvar outro campo. Uma mudança intencional nesse valor deve ser explícita e auditada.

O risco de concorrência inclui tablet offline com uma versão antiga do recebimento e importações históricas. Um `updated_at` só no cliente web não impede que outro escritor sobrescreva valores. A 031 deve proteger todas as vias que atingem a linha, com política explícita para payload antigo: preservar o envelope e devolver um conflito recuperável quando necessário, em vez de apresentar sucesso e perder a correção técnica. A solução não deve exigir reintrodução das etapas removidas, reatribuição de autor legado ou um APK novo apenas para abrir a página web.

## Direção do incremento

1. Reutilizar `rm_equipamentos`; consultar todos os dados técnicos necessários, mantendo valores originais e os IDs de origem.
2. Resolver propriedade canônica antes de oferecer edição; salvar exclusivamente o equipamento correspondente ao projeto solicitado.
3. Usar capacidade EM no servidor, autoria RM existente, motivo quando exigido, versão, idempotência e histórico antes/depois por campo alterado. Não herdar a privacidade geral do tipo Bubble (`viewAll/searchFor`), nem depender da visibilidade do botão.
4. Enviar somente o patch dos campos alterados. Chave ausente conserva o valor; limpeza é intencional; campos de vínculo, integração, tipo e flags removidas ficam fora do patch técnico.
5. Preservar respostas, registros, documentos, projetos e trabalhos offline. Uma correção técnica não deve recriar equipamento nem alterar células/templates/formulários/fotos.
6. Validar especialmente conflito de dois editores, repetição de protocolo, vínculo divergente, ausência de capacidade, limpezas, valores com unidades/vírgulas e payload offline antigo. A ponte Bubble continua desativada.

Evidências brutas locais ignoradas: `.tmp/discovery-equipment/` (`equipraw1.json`, `custom_projeto_rm.json`, option sets, eventos/ações nomeados pelos IDs acima e `inputs.json`). Não contêm credenciais nem amostras de registros de clientes. Fontes locais de comparação: migrações 001/002/003/006/011 e código citado; as migrações aplicadas não foram modificadas por esta revisão.

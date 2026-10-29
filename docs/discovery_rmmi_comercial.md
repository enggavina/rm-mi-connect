# Discovery comercial RMMI → EM

Data: 29/10/2026. Referência: Bubble `rmmi`, versão `live`, consultada com `get_app_outline`, `get_node` e leitura da configuração do API Connector. Nenhum workflow, e-mail, agendamento, alteração de dados ou chamada ao gerador PDF foi executado.

Este documento registra evidência estática do editor, não validação funcional em execução. **Cobertura desta inspeção: 225/225 eventos completos**, sendo **209 ativos e 16 explicitamente desativados**; **453/453 ações ativas lidas individualmente**, incluindo as expressões aninhadas. Os oito ramos de geração estão fechados estaticamente (103/103 ações). Nenhum PDF ou CRUD comercial foi executado. Essa cobertura não equivale a implementação, teste em runtime ou paridade integral de todos os elementos/páginas do RMMI; dependências e limites remanescentes estão discriminados abaixo.

## Situação do projeto atual

O EM reutiliza Next.js, BFF em `desktop/src/server/web`, autenticação SSO em `auth.ts/auth-policy.ts/sso-policy.ts`, cliente Supabase e componentes `desktop/src/components/web`. A busca em rotas, serviços e scripts não encontrou módulo comercial funcional. A mera existência das tabelas da migration 005 não representa implementação.

- `rm-mobile-supabase/migrations/005_rm_commercial_proposals_and_legacy_forms.sql` já cria tabelas comerciais aproximadas.
- `desktop/src/server/bridge/mapping.ts` não mapeia Material, Precificação, Proposta_controle, Proposta_motor_Budgetaria, Template_Proposta ou VendedorCliente.
- Os scripts de ETL operacionais não realizam uma carga comercial completa.
- O campo operacional de projeto “Data Envio para Comercial” e o rótulo de status “Revisão comercial” já existentes não equivalem a um fluxo de propostas.
- `desktop/docs/web-platform.md` já informa que orçamento comercial não é funcionalidade pronta.
- Não alterar a migration 005 aplicada. Uma reconciliação deverá ser aditiva, preservando IDs Bubble e dados eventualmente presentes.

Preflight agregado de produção em 29/10/2026, evidência `.tmp/parity-unmigrated-data-counts.json`: `rm_materiais=0`, `rm_precificacao_orcamentaria=0`, `rm_propostas_controle=0`, `rm_propostas_budgetarias=0`, `rm_vendedores_clientes=0`. Também estão vazios Elementos e Templates Word. Portanto contrato e **carga real** são dependências concretas; não há catálogo comercial migrado que possa ser declarado funcional nem se devem criar linhas fictícias para simular a migração.

## Contrato Live confirmado e divergências da 005

| Entidade Live | Contrato observado | Modelo EM e classificação |
| --- | --- | --- |
| `custom.material_rm` (Material) | `pe_a_text` (Peça), `pre_o_number` (Valor), `tipo_pe_a_option_tipo_pe_a` (Tipo peça) | `rm_materiais` possui nome/código/unidade/valor_unitário; não preserva o tipo de peça. **Divergente**. |
| `custom.precifica_ao_or_amentaria` | CV textual e numérico; KW textual e numérico; área, fator, polos, motor, tipo orçamento, serviço e valor final normal | A 005 aproxima por carcaça, tensão, horas, custo, valores de vários serviços e fator EX. Os atributos necessários à busca real não têm correspondência fiel. **Divergente**. |
| `custom.proposta_controle` | Número textual; polos; CV/KW textual e numérico; Rev_Recente; Revisao_vigente; tipo de motor | `rm_propostas_controle` incorpora cliente, equipamento, aprovação, preço e PDF que não existem nessa entidade Live. **Divergente**. |
| `custom.proposta` (Proposta_motor_Budgetaria) | Área; cliente; componentes (lista de Material); contato; data; e-mail; número; prazo textual; controle; responsável User; serviço; valor; vendedor User; revisão | `rm_propostas_budgetarias` não representa os vínculos/atributos necessários. Não é apenas arquivo de PDF. **Divergente**. |
| `custom.vendedorcliente` | Associação `cliente_custom_cliente` ↔ `vendedor_user` | `rm_vendedores_clientes` foi definida como ficha nome/e-mail/telefone/cliente. **Divergente**. |
| `custom.template_proposta` | Nome, body_html_text, css_text, idioma_option_l_nguas | A 005 modela pasta de template/configuração de renderização em vez de HTML/CSS. **Divergente**. |
| `custom.pe_a_rm` (Peça RM) | Somente nome_text, além dos campos built-in | A 005 adiciona quantidade, custos e FK de Material sem correspondência nesse tipo. **Divergente**. |
| `custom.precifica__o_or_amentaria` (Escopo RM) | cv_text, motor_option_tipo_motor_rm, polos_option_polos_rm, pre_o_number | Não é o cadastro de textos de escopo PT/EN/ES criado na 005; é outro tipo, distinto de Precificação apesar do identificador semelhante. **Divergente**. |

Campos precisos da precificação Live: `_cv_text` (“ Potencia Cv”), `_potencia_cv_number`, `area_de_atua_ao_option_area_atua_ao`, `fator_number`, `numero_polos_option_polos_rm`, `potencia_cv_text` (**legenda “Potencia Kw”**, apesar do nome técnico), `potencia_kw_number`, `tipo_motor_option_tipo_motor_rm`, `tipo_or_amento_option_tipo_or_amento`, `tipo_servi_o_option_tipo_servi_o`, `valor_number`.

Opções confirmadas: polos II/IV/VI/VIII; serviço Manutenção básica/Rebobinamento; motor Standard/EX; área Industria/O&G; orçamento Budgetaria/Firme; línguas `por_br` e `eng_us`. A existência de enums ou colunas em espanhol na 005 **não autoriza** apresentar esse idioma como paridade. Não foi constatada neste recorte uma fórmula de carcaça, mão de obra, desconto, impostos ou interpolação.

## Composição e navegação

Página comercial `proposta/coczM`:

| Grupo ou elemento | Identificador | Papel e dependências |
| --- | --- | --- |
| Menu lateral | `codAb` | Estado `section` seleciona as áreas. Menu Proposta `cocze`, precificação `coeIE`, materiais `coeIP`, projetos `coczw`, requisições `codAC`, arquivo `coczk`, dashboard `coczq`. |
| Propostas estimadas | `codMy` | Invisível inicialmente, visível com `section=proposta`. Pesquisa/filtros `codJz`; lista `codMc`; paginação `codLN`. |
| Formulário estimada | `codYJ` | Invisível inicialmente, visível com `section=formulario`. Estados `State_Proposta_controle`, `State_proposta_motor`, `kw_Number` e `botoesidiomas`. |
| Precificação | `coeIy` | Visível com `section=precificaçao`. Filtros `coeIz`, lista `coeLD`, paginação `coeKB`. |
| Materiais | `coeLc` | Visível com `section=materiais`. Filtros `coeLh`, lista `coeMW`, paginação `coeMk`. |
| Requisições | `codik` | Lista `codjx`; depende de ProjetoRM e do encaminhamento para oficina. |
| Arquivo | `codhE` | Lista `codiR`; regras completas de arquivo ainda pendentes. |
| Dashboard / Projetos | `codfE` / `codfF` | Dependem de ProjetoRM e status; não presumir métricas somente pelos rótulos. |
| Grupos “S/uso” | `codDE/codEk/codFS/codHK` | Nomes sugerem legado, mas não permitem declarar obsolescência sem concluir visibilidade, referências e workflows. |

A lista estimada contém filtros por vendedor `codKW`, serviço `codKL`, cliente `codKK`, contato `codKX`, data `codKQ/codKR`, ordenação `codKc`, busca fuzzy `codKd` e faixa de valor `codMQ/codMV/codMW/codMU`. A consulta base de `codMc` ignora filtros vazios, aplica serviço, vendedor, cliente, contato, data >=/<= e valor >=/<=; ordena Created Date decrescente. Ordenações alternativas são data2_date, numero_text e valor1_number, todas decrescentes. Número é texto no legado; não reinterpretar silenciosamente como ordem numérica. Busca não vazia troca a fonte para matches do plugin Search&Autocorrect; a composição do plugin com os demais filtros ainda precisa de confirmação. Linhas por página:10/20/50, padrão10; página inicial1.

O formulário usa quatro etapas: cliente/contato `codUM`, serviço/prazo/vendedor `codUa`, potência/polos/motor `codVc`, valor e geração `codWY`. A paginação `codUS` possui estado Etapas; Avançar `codUT` e Retornar `codUY` têm eventos distintos por etapa (`codui/coduo/codvH` e `coduu/codvB/codvN`). Não substituir essa jornada por um formulário genérico sem preservar as dependências.


Validações e estados confirmados em codYJ expandido: serviço, prazo textual, potência decimal de 2 casas, polos e motor são obrigatórios. Radio CV/KW inicia CV; se o controle não tem CV numérico passa a KW; se ambas potências estão vazias volta a CV. Input potência inicia por CV e troca conteúdo para KW quando CV está vazio; trocar unidade altera o placeholder. Há dropdown textual de potência antigo codVt invisível e obrigatório, com fonte em valores textuais de precificação; não substitui input numérico ativo codVs. Avançar/Retornar dependem da etapa nas condições lidas; não foi confirmada condição agregada de “todos inputs válidos”. Containers dos idiomas só aparecem na etapa 4 com estado botoesidiomas=unificado/separado. Defaults de serviço/prazo vêm da versão carregada; defaults de potência/polos/motor vêm do controle.

## CRUD de precificação e materiais

| Fluxo | Evento → ações | Leitura / escrita / efeito |
| --- | --- | --- |
| Cadastrar precificação | `coeVL` → `coeVQ`, `coeVR`, `coeVS` | Cria `custom.precifica_ao_or_amentaria` com serviço, polos, valor, motor, área, CV numérico e KW numérico; mostra sucesso e reseta inputs. |
| Alterar precificação | `coeVk` → `coeVp`, `coeVq` | Altera o registro carregado no popup `coeSv`, usando os mesmos sete atributos; sucesso. |
| Excluir precificação | `coeWC` → `coeWH`, `coeWI`, `coeWM` | Exclui `usertodelete` do popup `coeUs`, alerta e fecha. Não há condição explícita no evento ou ação de exclusão lidos. A restrição visual ainda deve ser auditada. |
| Cadastrar material | `coecC` → `coecH`, `coecI`, `coecM` | Cria Material com tipo de peça, valor e peça; sucesso e reset. |
| Alterar material | `coebk` → `coebp`, `coebq` | Altera Material carregado no popup `coeZA`; sucesso. |
| Excluir material | `coebL` → `coebQ`, `coebR`, `coebS` | Exclui `usertodelete` do popup `coeYe`, alerta e fecha. Não foi comprovado bloqueio por proposta dependente. |

Popups de precificação: criar `coeQy` (inputs/dropdowns `coeRQ/coeRb/coeRm/coeSW/coeSL/coeSY/coeSq`, confirmar `coeRo`, fechar `coeRu`); editar `coeSv` (confirmar `coeTl`, fechar `coeTr`); excluir `coeUs` (confirmar `coeUz`, cancelar `coeVE`).

Popups de materiais: criar `coeaE` (inputs/dropdowns `coeaW/coebG/coeas`, confirmar `coeab`, fechar `coeah`); editar `coeZA` (inputs/dropdowns `coeZS/coeZr/coeZw`, confirmar `coeZU`, fechar `coeZa`); excluir `coeYe` (confirmar `coeYo`, cancelar `coeYq`).

O acesso aos popups usa estados de seleção antes de exibir (`coeNU/coeOs/coePA` para precificação; `coePL/coePW/coePe` para material). Os controles de fechar/cancelar têm eventos próprios. Nos popups de precificação, polos/motor/serviço/área são obrigatórios; CV/KW são decimais de 2 casas opcionais; valor monetário é opcional. Nos materiais, peça é obrigatória na criação e opcional na edição; tipo de peça é obrigatório; valor monetário é opcional em ambos. Não foram observados limites mínimos/máximos ou bloqueio condicional nos botões confirmar lidos. Essa assimetria é registrada, não corrigida automaticamente. Duplicidade, dependências e autorização nas ações ainda precisam de fechamento.

`settings_rm/cnwZQ` também contém esses fluxos: precificação `cnwmG`, lista `cnwni`, popups `cnwoE/cnwpZ/cnwuk`; material `cnwsg/cnwti/cnwvB`; associação vendedor-cliente `cnxlH`. Foram lidos integralmente os oito eventos `cnxEk/cnxIh/cnxJF/cnxFC/cnxFO/cnxFh/cnxoG/cnxom` e as sete mutações ativas, além do toast de exclusão. Há divergência efetiva: `cnxEl/cnxIi` escrevem **potências textuais** `_cv_text/potencia_cv_text`, sem atualizar os campos numéricos; `coeVQ/coeVp` da página proposta escrevem somente os numéricos. Nenhum dos eventos settings agenda o backend de conversão. Uma edição por settings pode deixar os números usados pelo cálculo ausentes/desatualizados até manutenção posterior. Material tem os mesmos três atributos nas duas telas (`cnxFD/cnxFP/cnxFi`). `cnxoG` (cadastrar VendedorCliente) está desativado; `cnxom → cnxos/cnxow` permanece ativo para excluir a associação da linha e avisar sucesso. Reutilizar serviço canônico com contrato explícito; não duplicar as inconsistências.

## Regra de cálculo realmente observada

Botão Calcular `codWi`, evento `codva`, escreve `State_valor` em `Group Valores final[s]/codWk`, então reseta o grupo `codvl`. Ações `codve/codvf/codvg/codvk`:

1. Filtra sempre por polos (`codVy`), motor (`codWG`), serviço (`codUk`) e área (`codSK`).
2. Se unidade CV (`codWW`) e houver preço com potência exata (`codVs`), usa o primeiro `valor_number` (`codvf`).
3. Se CV não tiver potência exata, busca preços com potência **maior**, ordena CV crescente e usa o primeiro (`codve`).
4. Se KW não tiver potência exata, busca potência KW **maior**, ordena KW crescente e usa o primeiro (`codvg`).
5. O caso KW exato (`codvk`) consulta potência numérica exata no valor atribuído, **mas a condição de execução exige simultaneamente** `potencia_kw_number` igual e `potencia_cv_text` igual ao input convertido em texto. A ação fallback usa somente ausência do numérico exato. Assim, havendo registro numérico exato sem o texto correspondente, nenhuma das duas atribuições KW pode executar.

A regra de preço é seleção de linha de tabela, não interpolação, soma de componentes ou fator EX. A ação lida não multiplica pelo campo Fator nem filtra pelo tipo de orçamento. O resultado sem uma faixa superior e a escolha entre linhas duplicadas não estão resolvidos por regra adicional observada. Não “corrigir” automaticamente a anomalia KW nem inventar fallback; registrar decisão de negócio e teste separado antes da implementação. O valor final da proposta vem do input, portanto existe possibilidade de intervenção humana que deve ser preservada e auditada.

## Propostas, revisão e persistência

Há oito eventos ativos para quatro botões de geração, separando **controle existente (>0)** e **novo (=0)** por consulta de `Proposta_controle.numero_text` igual ao número de `State_proposta_motor`:

| Formato / língua | Existente | Novo | Ações de geração |
| --- | --- | --- | --- |
| Unificada EN | `codvm` | `codwJ` | Duas agendas PDF condicionais, pausa e abertura de URL. |
| Unificada PT | `coeAK` | `codzi` | Duas agendas PDF condicionais, pausa e abertura de URL. |
| Separada EN | `codzb` | `codxk` | Quatro agendas PDF condicionais, duas pausas e duas aberturas de URL. |
| Separada PT | `codyS` | `codyx` | Quatro agendas PDF condicionais, duas pausas e duas aberturas de URL. |

**Fechamento dos oito ramos**: os oito eventos e todas as suas **103 ações** foram lidos integralmente, incluindo expressões JSON aninhadas dos 24 agendamentos PDF, 12 pausas/aberturas e estados pós-geração. Não houve execução. A equivalência e as diferenças abaixo resultam da comparação das propriedades completas, não da semelhança das legendas.

- Controle novo: duas ações mutuamente condicionadas por CV/KW. Define Rev_Recente=0, Revisao_vigente=0, polos, tipo motor, potência da unidade escolhida. Número = último número de controle convertido em número +1. O critério preciso de “último” e concorrência precisam ser reconciliados, sem reproduzir incremento inseguro em leitura/escrita separadas.
- Controle existente: CV ou KW incrementa Rev_Recente em 1 e atualiza polos, motor e potência escolhida. As quatro ações CV são equivalentes; três das quatro KW atualizam somente a potência numérica. A exceção é `codxp` (PT separada existente), que também escreve potencia_kw_text. A potência da outra unidade não é explicitamente limpa. Revisao_vigente não é avançada nesses oito ramos.
- Nova versão de Proposta_motor_Budgetaria: cliente, contato, data atual, e-mail do contato, controle, usuário responsável, serviço, valor do input, prazo textual, vendedor, número e área. Revisão nova=0; existente lê Rev_Recente da pesquisa. Não foi observada sobrescrita da versão anterior nesses ramos.
- Campo número da proposta é composto pela concatenação dos resultados condicionais CV/KW. No ramo novo, o primeiro vínculo usa resultado CV; `codzs` altera a proposta recém-criada para o resultado KW exclusivamente quando unidade=KW. Portanto os dois passos compõem o vínculo, não dois controles por proposta.
- Após gerar, os eventos retornam seção do menu, limpam estado de idioma e atualizam a lista. Todos os oito ramos escrevem section=proposta, limpam botoesidiomas e exibem nova busca de Proposta_motor_Budgetaria na lista. O refresh dos oito ramos consulta apenas o texto _all de codKG, ignora vazio e ordena Created Date decrescente; não replica os demais filtros da consulta declarativa da lista. Essa diferença pós-geração deve ser preservada como evidência e resolvida explicitamente, junto com a ausência de captura de erro do gerador.
- Alguns ramos disparam custom event Debug_api (`codxE`), parâmetro Json_tags:text obrigatório e retorno Json_tags:text. A ação tecnicamente chamada `TerminateWorkflow/codxF` tem legenda **Return data** e devolve o parâmetro; não é evidência de que termina a geração chamadora. `codzt` passa texto arbitrário com o payload. Rastrear como retorno de evento personalizado, não como API de debug externa.

Eventos antigos `codru/codtE/codtt` estão explicitamente **desativados**. Não usá-los como especificação ativa. O evento `codrj` do formulário antigo cria **ProjetoRM** (`codrk`: número, status PCP, status=Peritagem, parceiro, escopo, chegada), cria Equipamento (`codro`: projeto, série, modelo, tensão/tipo, corrente/componentes) e vincula o equipamento ao projeto (`codrp`), então alerta sucesso (`codrq`). Não cria controle/proposta. Permanece ativo no editor e sua alcançabilidade pelo popup antigo exige fechar a navegação. Reutilizar o recebimento/projeto existente no EM se o fluxo estiver alcançável; não duplicar um cadastro comercial por causa do nome do botão. Não declarar grupo S/uso obsoleto só pelo nome.

## PDF e backend

Backend `generate_pdf_proposta/cnxTq`: não exposto, parâmetro obrigatório `Json_tags:text`, ação `cnxUP` passa esse texto como corpo JSON ao API Connector `cnxTy/cnxUC` (“PDF_Proposta - Gerar pdf”). Configuração lida:

- POST `https://pdf-generator-ppu2.onrender.com/generate-generic-pdf`.
- Corpo suporta template_folder, pdf_file_name, orientation, margens, zoom e tags N_proposta, revisao, Data_atual, Nome_cliente, cliente_contato, email_cliente, potencia, Nome_vendedor, Telefone_vendedor, email_vendedor, Tipo_proposta, ref_potencia, N_polos, Valor e N_dias.
- Configuração inicial contém exemplo de template comercial EX/manutenção básica/PT-BR. As 24 ações chamadoras dos oito ramos confirmam portrait, margem superior 44mm, inferior 18.5mm, laterais 0 e zoom 1.0.
- Retorno tipado: message, file_path, returned_an_error, status_code/status_message/body, headers. Nenhuma gravação do retorno aparece na ação backend única; os eventos de tela usam agendamento/pausa/URL. Todos os oito ramos aguardam 4000ms por documento e abrem nova aba em /download-pdf/{arquivo}.pdf no mesmo Render; constroem o caminho sem aguardar resultado do job. Unificada tem uma pausa/abertura; separada faz comercial → pausa/abertura → técnico → pausa/abertura. Não há condição ou tratamento de erro explícito nessas 12 pausas/aberturas.
- Não executar inicialização do conector nem gerar documento fictício em produção.


### Payloads PDF confirmados nas ações chamadoras

A propriedade renderizada apenas como “Arbitrary text” contém uma expressão aninhada completa; foi lida a árvore da expressão, não inferida pela legenda.

- codzu/codzy (PT unificada nova) e codvw/codvx (EN unificada existente) agendam imediatamente cnxTq sem ignorar regras de privacidade; CV e KW são condições mutuamente exclusivas.
- Template unificado: proposta_tecnica_comercial_{motor_minúsculo}_{serviço_normalizado}_{pt-br|en-us}. Serviço vem do Display em português, substitui á/ã por a e espaços por underscore, depois minúsculas. Não traduz automaticamente o serviço no nome da pasta EN.
- Nome unificado: {nome_cliente}-{numero}-{revisao}.pdf; sem língua ou unidade no nome. Gerar outro idioma da mesma revisão pode reutilizar o mesmo caminho; o comportamento de colisão no Render não foi executado/verificado.
- PT usa data dd/mm/yyyy; EN mm/dd/yyyy. Valor EN observado permanece moeda R$ com decimal vírgula/milhar ponto; não é conversão de moeda.
- As tags unificadas incluem **Tipo_proposta** (T maiúsculo), polos pelo Display e prazo textual. CV envia potência e ref_potencia iguais ao input. **KW multiplica ambas as tags por 1,34 em EN e por 1,36 em PT**. O técnico separado converte apenas ref_potencia; o comercial separado converte as duas. A diferença entre coeficientes está confirmada em todos os ramos; o significado da unidade impressa nos templates não foi validado. A diferença, isoladamente, não comprova erro de negócio e não deve ser uniformizada silenciosamente. A precificação continua usando a potência/unidade original; esta conversão existe no PDF, não é fator de preço. Não foi observada tag exclusiva da unidade.
- Separada PT existente: codxv cria documento comercial, template proposta_comercial_{motor}_{serviço}_pt-br, nome Comercial_{cliente}-{numero}-{revisao}.pdf; usa a tag **tipo_proposta** em minúsculas (difere da unificada). codyC gera técnico, template proposta_tecnica_{motor}_{serviço}_pt-br, nome Tecnica_{cliente}-{numero}-{revisao}.pdf, payload sem Valor/Tipo_proposta/N_polos, com ref_potencia e N_dias.
- O contrato usa interpolação textual manual de JSON. Escapes de aspas, barras e quebras em nome/contato precisam ser garantidos pelo adaptador novo usando serialização JSON; preservar tags e documentar divergências por template. Não emitir requests reais apenas para investigar.

Outros backends lidos integralmente:

| Backend | Exposição | Efeito |
| --- | --- | --- |
| `transferencia_valor/coShj` → `coSho` | Não exposto | Converte “Valor antigo - deleted” para number e escreve valor1_number de Proposta_motor_Budgetaria. Parece manutenção histórica, mas não declarar obsoleto sem localizar chamadores. |
| `alimentar_potencia_pc/cohei0` → `coheq0` | Exposto | Converte CV/KW textuais de Proposta_controle para os campos numéricos. |
| `alimentar potencia po/cohgO0` → `cohgQ0` | Exposto | Converte CV/KW textuais de Precificação para os campos numéricos. |

Esses backends não constituem um motor de cálculo novo. Conversão textual histórica deve ser realizada por ETL validado, não por endpoint público genérico.

## Dependências CRM, projetos e permissões

Eventos `coeAe/coeAp` criam contato/cliente dentro do formulário. `codwi` associa vendedor-cliente somente quando a pesquisa Cliente+User não encontra vínculo; `codws` trata o caso de existência. A entidade deve reaproveitar `rm_users`, não criar segundo diretório independente de vendedores.

Requisições/encaminhamento: a leitura completa dos eventos confirmou **desativados** `coeBs/coeGk` (Nova requisição), `coeCO/coeGX` (Encaminhar serviço) e `coeBN/coeCt` (comentários). Suas mutações, agendas backend e ações Brevo são dependências históricas, não um fluxo ativo comprovado desta página; nenhum e-mail ativo foi encontrado no inventário. `coeCb` (Retornar cliente) é ativo: `coeCc` altera ProjetoRM do floating group para Status=Peritagem e Status PCP=Retornado; ações seguintes fecham/limpam o grupo e alertam sucesso. Sua alcançabilidade e estados de navegação ainda devem ser fechados. Não reativar integrações desativadas para obter uma suposta paridade.

As entidades comerciais Live consultadas permitem busca/visualização no perfil Everyone e não permitem CRUD por Data API nesse perfil. Isso é evidência da configuração legada, **não** autorização para copiar leitura pública para o EM. Botões com rótulos GT001/elementos individuais precisam ser cruzados com o módulo `autorizacao`, permissões por usuário/menu/elemento e as condições de execução. Uma simples capacidade global “comercial” não foi confirmada como equivalente. SSO e autorização BFF existentes devem ser reutilizados e estendidos com regras rastreadas, preservando o acesso legado do tablet.


A leitura expandida fechou os onze códigos: CM001=Proposta (cocze), CM002=Precificação (coeIE), CM003=Materiais (coeIP), CM004=Nova proposta (codLH), CM005=abrir/revisar linha de proposta (codMg), CM006/007/008=criar/editar/excluir preço (coeJv/coeLV/coeLW), CM009/010/011=criar/editar/excluir material (coeMA/coeMi/coeMj). Cada condição pesquisa Elemento por codigo_text e desabilita o controle quando sua lista permissoes não contém Current User. Não há bypass administrador/herança de perfil explícitos nessas onze condições. Os rótulos visuais GT001/002/003 dos controles são reaproveitados, mas a busca de autorização usa os códigos CM reais; não mapear pela legenda GT. Projetos/Requisições só ficam visíveis com parâmetro URL app=rm; Estimado com app=proposta; Firme/Arquivo/Dashboard estão invisíveis inicialmente sem condição de exibição nos menus lidos. Isso não prova que os grupos estejam inalcançáveis por outros eventos.

Sessão antiga: `codtV/coduE/coduG/coduL` e os eventos mais recentes `coeFy/coeGE/coeGK` estão explicitamente desativados. O inventário ativo contém um LogOut, cuja cadeia será fechada com as ações de navegação. O SSO aprovado do EM não deve ser substituído pelo TOTP Bubble por aparência de paridade.

## Plano de implementação recomendado

| Ordem | Entrega / classificação atual | Origem | Destino e arquivos principais | Dependências / risco |
| --- | --- | --- | --- | --- |
| 1 | Reconciliar contrato e mapeamento; **divergente** | Tipos Live acima | Migration aditiva, tipos TS, `desktop/src/server/bridge/mapping.ts`, ETL específico | Auditar dados existentes antes de ALTER. Não preencher modelo aproximado por analogia. Alto. |
| 2 | Permissões comerciais; **dependente** | Elementos e condições de proposta/settings/autorizacao | SSO policy, autorização BFF e regras de banco existentes | Fechar herança/negação/ação. Evitar leitura aberta legada. Alto. |
| 3 | Material CRUD; **não implementado** | `coeLc`, popups e seis ações CRUD | Serviço comercial, ações web e menus reaproveitando componentes de catálogos | Tipo de peça, regras de validação/exclusão, carga real. Médio. |
| 4 | Precificação CRUD e busca; **não implementado** | `coeIy`, `coeVQ/coeVp/coeWH`, cálculo `codva` | Serviço tipado e UI compartilhada com catálogo | Unidades, dados duplicados, anomalia KW, faixa inexistente; testes de fronteira necessários. Alto. |
| 5 | Vendedor-cliente e contatos; **parcial/dependente** | `codwi`, `cnxlH`, CRM já existente | Reutilizar clientes/contatos/usuários e adicionar associação fiel | Não duplicar usuários. Verificar contatos inline e permissões. Médio. |
| 6 | Jornada de proposta e versões; **não implementado** | `codYJ`, oito ramos | Serviço transacional, ações web, tela comercial com quatro etapas | Numeração concorrente, revisão, edição de valor, estado inicial por unidade. Alto. |
| 7 | PDF PT/EN unificado/separado; **dependente** | `cnxTq/cnxUP`, ações chamadoras | Adaptador backend, job rastreável, retorno/erro e armazenamento conforme contrato confirmado | Pastas/margens/URLs/templates ainda não fechados. Não usar mocks permanentes. Alto. |
| 8 | Requisições e abertura de projeto; **dependente** | `codJC`, `coeBs/coeGk/coeCO/coeGX` | Serviços de projeto/PCP existentes + integração de e-mail | Descobrir todos status, dados, destinos, backend e idempotência. Alto. |
| 9 | Arquivo, dashboard, firme e filtros restantes; **não implementado** | `codhE/codfE/codfF` e grupos legados | Menus comerciais e consultas reutilizando componentes | Não prometer proposta firme, aprovação comercial ou indicadores sem auditoria dos ramos. Alto. |

Nenhuma funcionalidade comercial deve ser marcada migrada só após renderizar tela ou criar tabela. Validar CRUD, consultas, valores, estados, navegação, permissões, revisão, concorrência e falha de integração com dados reais de teste autorizados em ambiente adequado, sem inventar registros em produção.

## Cobertura e próximos fechamentos

Inventário final desta inspeção: **225/225 eventos**, **209 ativos**, **16 desativados**, **453/453 ações ativas lidas**. Os 12 eventos ativos sem ações são identificados no anexo. Não há ação ativa desse inventário omitida da contagem; os corpos dos eventos desativados não são apresentados como contratos atuais.

Pendências objetivas antes do desenvolvimento do módulo comercial:

1. Os oito ramos e suas 103 ações estão fechados estaticamente. Resta validar execução autorizada do gerador/arquivos e decidir explicitamente como tratar conversão KW dependente do idioma, numeração concorrente, JSON interpolado e colisão de nomes; não executar geração no discovery.
2. Cliente/contato ainda exigem o último nível de leitura. Valor final codWv é obrigatório, moeda R$, inicia da proposta carregada e muda para State_valor quando há resultado do cálculo. Área e vendedor foram confirmados obrigatórios; serviço/prazo/potência/polos/motor e popups CRUD já foram fechados. O dropdown de vendedores lista por padrão todos os Users presentes em VendedorCliente, ordenados por Nome. Quando o ícone de filtro colorido fica visível, restringe a associação ao cliente selecionado. Não é a lista de todos os usuários e o estado do filtro precisa ser preservado.
3. Fechar fuzzysearch/paginação e linha de proposta após a consulta base e ordenação já lidas: revisão vigente, ações de abrir/revisar/arquivar e variantes.
4. Aprofundar a alcançabilidade e eventuais autobindings dos grupos legados S/uso/popup antigo antes de replicar a totalidade visual da página. A leitura dos eventos e das 453 ações ativas está concluída; essa pendência é de composição/alcance e dependências externas aos comandos explícitos.
5. Fechar os fluxos auxiliares de settings_rm além dos oito eventos CRUD/vendedor lidos e suas condições herdadas. Os CM001–CM011 e as divergências de escrita de potência entre telas já foram confirmados.
6. Os tipos Template_Proposta/Peça RM/Escopo RM tiveram seus campos confirmados e divergências registradas acima. Nenhuma das 453 ações ativas consulta esses três tipos; não inventar custos por peças ou dependência de template HTML nos 24 agendamentos que usam pastas calculadas. Verificar outras páginas antes de declarar esses tipos obsoletos ou importar tabelas aproximadas da 005.
7. Fechar os chamadores externos dos backends de manutenção alimentar_Potencia_PC/PO antes de decidir sua desativação/substituição. Os dois foram lidos, não invocados; não há chamada a eles nas 453 ações ativas desta página.

Nenhuma implementação comercial, SQL ou alteração de dados Bubble/Supabase, Railway ou Central de Acessos foi realizada por esta auditoria. A composição operacional do Cronograma desenvolvida em paralelo é registrada no discovery de Planejamento e não representa implementação comercial.

## Fechamento funcional dos demais workflows ativos

A análise das 453 ações inclui os comandos de interface, sem tratá-los como CRUD implícito. Seus efeitos foram agrupados abaixo; todos os eventos e o total de ações por evento estão no anexo.

| Conjunto / origem | Evento, condição e encadeamento confirmado | Leituras / persistência | Destino e classificação |
| --- | --- | --- | --- |
| Nova estimada e revisão de versão | codqo limpa cliente, contato, controle, proposta carregada, idioma e valor calculado; reseta formulário; muda section=formulario e Etapas=1. codsm carrega proposta da linha, seu controle/cliente/contato, limpa valor calculado, reseta e abre Etapas=1 | Estado transitório. Nenhuma escrita de banco até geração | Jornada comercial a implementar sobre serviço versionado; **não implementada** |
| Cliente e contato | codrQ seleciona Cliente, limpa contato e reseta ambos os inputs; codrc seleciona Contatos Cliente nos dois estados e fecha a lista. coduX abre clientes; coduc limpa cliente se o input estiver vazio e abre contatos | Cliente/contato selecionados permanecem distintos do texto de pesquisa; criação inline não seleciona automaticamente o registro novo nas ações lidas | Reutilizar CRM e seletores existentes; **parcial/dependente** |
| Avançar, retornar, modo de PDF | codui/coduo/codvH avançam1→2→3→4; coduu/codvB/codvN retornam e limpam filtro de vendedor ou idioma quando aplicável. codvU escolhe unificado; codzc escolhe separado. Ambos apenas exibem idiomas, não geram PDF | Estados Etapas, botoesidiomas e filtervisible, animações100ms. Não há condição agregada de validade adicional nas ações de navegação | Componente de etapas reutilizável com validação equivalente; **não implementado** |
| Filtro de vendedor | codwu/codwz ligam/desligam filtervisible. Dropdown padrão usa todos os Users já vinculados em VendedorCliente, ordenados por Nome; estado de filtro restringe ao Cliente selecionado | Não cria usuário. Excluir a última associação pode retirar o vendedor da lista padrão; o cadastro settings está desativado | Associação CRM e elegibilidade precisam de dados reais; **divergente/dependente** |
| Popups de CRUD | coeNU limpa seleção e abre preço novo; coeOs carrega preço da linha e abre editar; coePA guarda usertodelete e abre excluir. Material repete em coePL/coePW/coePe. Fechar/cancelar apenas ocultam seus popups | Estados de registro selecionado são tipos corretos apesar de nomes genéricos precificaçao/funcionario. Não há exclusão ao cancelar | Serviço/componente único de catálogo; **não implementado** |
| Listas de preços e materiais | Preço filtra serviço, motor, polos, CV numérico e faixa de valor; ignora vazios; padrão Created Date desc, alternativas CV asc/valor asc. Não há filtro de área nessa consulta, embora área participe do cálculo. Material pesquisa _all e tipo de peça; padrão Created Date desc e Peça asc | Apenas consultas a Precificação e Material; sem somar materiais ao preço | Leitor paginado e filtros próprios, reaproveitando UI atual; **não implementado** |
| Paginação | 58 ListGoToPage em dez listas, estados de página/linhas, primeiro/último, anterior/próximo, salto +5 e página do miolo. Anterior testa resultado diferente de0; próximo compara total; total=ceiling(count/linhas). Seleções10/20/50 alteram número de linhas e fecham o seletor | Estado de interface, não dados de negócio. Não assumir reset de página ao mudar linhas onde não existe comando explícito | Reutilizar Pagination/URLs, preservando filtros e tratando limites; **não implementado no comercial** |
| Menu e contexto | section aceita proposta/formulario/precificaçao/materiais/projetos/requisiçoes/firme/estimado/arquivo/dashboard. Estimado limpa filtro/idioma. Menu orçamento firme usa option=requisicao/peritagem/calculo | Consultas e estados; visibilidade dos menus depende também do app da URL. Firme/Arquivo/Dashboard não foram comprovados como acessíveis por seus menus invisíveis | Módulos pendentes, não criar botões mortos nem presumir obsolescência |
| Projeto, pré-cálculo e requisição legados | codpx seleciona ProjetoRM e consulta Celula_Projeto/Celulas no floating group de requisição; coeAw abre contexto Peritagem; coeBZ abre Cálculo; coeHG abre projeto na requisição. Retorno coeCb é a única mudança ativa desse contexto, Peritagem/Retornado | O restante dos comandos de nova requisição/encaminhamento/e-mail está desativado. coeFE somente mostra Documento importado, sem gravação ou importação de arquivo nas ações | Reutilizar projeto/recebimento/PCP; **parcial/dependente de alcance/autobinding**, não declarar importação funcional pelo toast |
| Navegação operacional | Oito ChangePage: painel cmpUO com Current User; index bTGYf no LoggedOut; project_rm cnpGY em nova aba com ProjetoRM da linha. codlW→codlX é o único LogOut ativo | Navegação e sessão, não CRUD. Sequência A…G do formulário antigo e seleção múltipla de StatusRm são apenas estados | Reaproveitar rotas EM e SSO; **parcial**, respeitando as alterações de jornada já autorizadas pelo usuário |
| JavaScript | Sete ações Run javascript chamam somente disableScroll()/enableScroll(). HTML A/codij define as funções como alteração de document.body.style.overflow | Sem fetch, API ou escrita de banco nessas definições. Preservar abrir/fechar/scroll por componentes React existentes | **Dependência visual substituível**, sem copiar Toolbox desnecessariamente |

Os 12 eventos ativos sem ações são codkt, codmk, codnu, codpH, codsT, codta, coduW, coeDo, coeEe, coeOm, coeVX e coebe. São controles sem comportamento configurado neste inventário, não funcionalidades a simular no EM.

Tipos de peça Live confirmados: rolamento/Rolamento; rolamento_especial/Rolamento especial; helice/Helice; v_ring/V’ring; retentor/Retentor; ptc_thermistor/PTC-Thermistor; trava_elastica/Trava elastica. Preservar as chaves, sem criar opções fictícias.

## Decisões e dependências antes da próxima implementação comercial

| Prioridade | Dependência / divergência real | Critério para avançar |
| --- | --- | --- |
| 1 | Todas as tabelas comerciais alvo estão vazias e a 005 tem contratos divergentes, inclusive entidades auxiliares | Migration aditiva canônica, mapeamento por IDs/aliases verificados e carga de dados reais validada; nenhum seed de demonstração em produção |
| 1 | CM001–CM011 são concessões individuais de Elemento e não constam das18 capacidades corporativas atuais; Elementos alvo também vazio | Reconciliar fonte de autorização com o discovery de Cadastros/Autorização, guardas no BFF/banco e escopo EM, preservando os administradores autorizados sem conceder administração global |
| 2 | Potências são escritas como texto em settings e número em proposta; cálculo depende do número e ramo KW testa também texto | Definir representação canônica e conversão/importação auditável, com testes de potência exata/faixa superior/sem faixa/duplicidade e KW textual divergente; registrar diferenças corrigidas explicitamente |
| 2 | Material não é Peça RM e componentes da proposta não participam do cálculo observado | CRUD fiel de Material+tipo/preço; não criar motor de custo/quantidade a partir das colunas aproximadas da005 |
| 3 | Numeração lê último controle sem ordenação explícita e incrementa fora de transação; revisão altera controle compartilhado | Comando transacional/versionado, preservação dos números/revisões reais e decisão sobre snapshots históricos; não inventar primeiro número ou usar count+1 |
| 3 | PDF converte KW de forma dependente de idioma, usa JSON interpolado, nome sem idioma e pausa fixa | Confirmar unidade/textos dos templates e contrato do Render, preservar coeficientes até decisão explícita, serializar JSON, rastrear sucesso/erro e resolver colisão sem acionar produção no discovery |
| 4 | Grupos legados/contextos podem ter campos com autobinding ou dependências fora das453 ações explícitas; vários menus estão invisíveis | Aprofundar somente a composição a ser implementada, cruzar outras páginas/backends e não reativar workflows desativados nem restaurar etapas de recebimento já removidas pelo usuário |

Esta inspeção fecha o inventário de eventos e ações ativas da página proposta, e os oito eventos settings explicitados. **Não declara execução validada nem paridade comercial entregue**. O próximo incremento pode começar por contrato/carga/autorização e CRUD de Materiais/Precificação, reutilizando a arquitetura atual; geração, revisão e integrações seguem a ordem e as dependências acima.


## Anexo — inventário de eventos da página proposta

Todos os 225 nós de evento e as 453 ações dos 209 eventos ativos foram lidos. Desativados não são somados às453 ações ativas e seus corpos não são contratos atuais. Ativos sem ações não representam funcionalidades implementadas.

| Evento | Nome | Estado | Ações lidas / total |
| --- | --- | --- | ---: |
| `codkJ` | Group Menu opções is clicked | Ativo | 1 / 1 |
| `codkO` | Group Menu Firme is clicked | Ativo | 1 / 1 |
| `codkQ` | Group Menu 20 requisiçoes is clicked | Ativo | 2 / 2 |
| `codkW` | Text registros por pág treinamento is clicked | Ativo | 1 / 1 |
| `codkb` | Back Page is clicked | Ativo | 2 / 2 |
| `codkh` | Group E is clicked | Ativo | 2 / 2 |
| `codkn` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `codkt` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `codku` | Foward page is clicked | Ativo | 2 / 2 |
| `codlA` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `codlG` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `codlM` | Group B is clicked | Ativo | 1 / 1 |
| `codlR` | User is logged out | Ativo | 1 / 1 |
| `codlW` | Group Menu sair is clicked | Ativo | 1 / 1 |
| `codlY` | Every time condition | Ativo | 1 / 1 |
| `codld` | Group Menu 10 requisiçoes is clicked | Ativo | 2 / 2 |
| `codlj` | Group Menu 50 requisiçoes is clicked | Ativo | 2 / 2 |
| `codlp` | Group BZZZZZ is clicked | Ativo | 1 / 1 |
| `codlu` | Group Menu Estimado is clicked | Ativo | 3 / 3 |
| `codmB` | Group Menu Proposta is clicked | Ativo | 1 / 1 |
| `codmG` | Group Menu Arquivo is clicked | Ativo | 1 / 1 |
| `codmI` | Group Menu dashboard is clicked | Ativo | 1 / 1 |
| `codmN` | Text registros por pág peritagem is clicked | Ativo | 1 / 1 |
| `codmS` | Back Page is clicked | Ativo | 2 / 2 |
| `codmY` | Group V is clicked | Ativo | 2 / 2 |
| `codme` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `codmk` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `codml` | Foward page is clicked | Ativo | 2 / 2 |
| `codmr` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `codmx` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `codnD` | Every time condition | Ativo | 1 / 1 |
| `codnI` | Group Menu 10 peritagem is clicked | Ativo | 2 / 2 |
| `codnO` | Group Menu 20 peritagem is clicked | Ativo | 2 / 2 |
| `codnU` | Group Menu 50 peritagem is clicked | Ativo | 2 / 2 |
| `codna` | Text registros por pág  Pré Cálculo is clicked | Ativo | 1 / 1 |
| `codnc` | Back Page is clicked | Ativo | 2 / 2 |
| `codni` | Group X is clicked | Ativo | 2 / 2 |
| `codno` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `codnu` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `codny` | Foward page is clicked | Ativo | 2 / 2 |
| `codoE` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `codoK` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `codoQ` | Group Menu 10  Pré Cálculo is clicked | Ativo | 2 / 2 |
| `codoW` | Group Menu 20  Pré Cálculo is clicked | Ativo | 2 / 2 |
| `codoc` | Group Menu 50  Pré Cálculo is clicked | Ativo | 2 / 2 |
| `codoi` | Every time condition | Ativo | 1 / 1 |
| `codok` | Text registros por pág Proposta is clicked | Ativo | 1 / 1 |
| `codop` | Back Page is clicked | Ativo | 2 / 2 |
| `codov` | Group DZ is clicked | Ativo | 2 / 2 |
| `codpB` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `codpH` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `codpI` | Foward page is clicked | Ativo | 2 / 2 |
| `codpO` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `codpU` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `codpa` | Group Menu 10 Proposta is clicked | Ativo | 2 / 2 |
| `codpg` | Group Menu 20 Proposta is clicked | Ativo | 2 / 2 |
| `codpm` | Group Menu 50 Proposta is clicked | Ativo | 2 / 2 |
| `codps` | Do when RepeatingGroup Proposta's List of ProjetoRMs:count / RepeatingGroup Proposta's numero de linhas:ceiling  is not ListofNumbers A Proposta's numero total de paginas | Ativo | 1 / 1 |
| `codpx` | Group E is clicked | Ativo | 5 / 5 |
| `codqJ` | Group V is clicked | Ativo | 1 / 1 |
| `codqO` | Group X is clicked | Ativo | 1 / 1 |
| `codqQ` | Group DZ is clicked | Ativo | 1 / 1 |
| `codqV` | Group Botão novo projeto is clicked | Ativo | 1 / 1 |
| `codqa` | Group MZ is clicked | Ativo | 1 / 1 |
| `codqc` | Group NZ is clicked | Ativo | 1 / 1 |
| `codqh` | Group OZ is clicked | Ativo | 1 / 1 |
| `codqm` | Icon B is clicked | Ativo | 1 / 1 |
| `codqo` | Group Botão novo projeto is clicked | Ativo | 8 / 8 |
| `codrG` | Text registros por pág peritagem is clicked | Ativo | 1 / 1 |
| `codsB` | Back Page is clicked | Ativo | 2 / 2 |
| `codsH` | Group QZ is clicked | Ativo | 2 / 2 |
| `codsN` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `codsT` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `codsU` | Foward page is clicked | Ativo | 2 / 2 |
| `codsa` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `codsg` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `codsm` | Group Proposta_motor_Budgetaria is clicked | Ativo | 8 / 8 |
| `codrL` | Group pesquisa cliente[s] is clicked | Ativo | 1 / 1 |
| `codrQ` | Group EZZ is clicked | Ativo | 5 / 5 |
| `codrc` | Group HZZ is clicked | Ativo | 4 / 4 |
| `codrj` | Group Botão Cadastrar is clicked | Ativo | 4 / 4 |
| `codru` | An element  is clicked | Desativado | 0 / 3 |
| `codtE` | An element  is clicked | Desativado | 0 / 3 |
| `codtO` | Group pesquisa contato[s] is clicked | Ativo | 1 / 1 |
| `codtt` | Group Botão novo projeto is clicked | Desativado | 0 / 4 |
| `codtQ` | Group Menu home is clicked | Ativo | 1 / 1 |
| `codtV` | Recurring | Desativado | 0 / 1 |
| `coduE` | Just once condition | Desativado | 0 / 1 |
| `coduG` | Just once condition | Desativado | 0 / 1 |
| `coduL` | Detect A user has become Inactive | Desativado | 0 / 1 |
| `codta` | IonicIcon F is clicked | Ativo sem ações | 0 / 0 |
| `codtb` | Group Botão Cadastrar is clicked | Ativo | 2 / 2 |
| `codth` | Group Button Fechar is clicked | Ativo | 2 / 2 |
| `codtn` | Group Botão Cadastrar is clicked | Ativo | 2 / 2 |
| `coduQ` | Group Button Fechar is clicked | Ativo | 2 / 2 |
| `coduW` | Group select client on dropdown is clicked | Ativo sem ações | 0 / 0 |
| `coduX` | Group pesquisar cliente[s] is clicked | Ativo | 1 / 1 |
| `coduc` | Group pesquisar contato[s] is clicked | Ativo | 2 / 2 |
| `codui` | Group Botão Avançar is clicked | Ativo | 2 / 2 |
| `coduo` | Group Botão Avançar is clicked | Ativo | 2 / 2 |
| `coduu` | Group Botão Retornar is clicked | Ativo | 3 / 3 |
| `codvB` | Group Botão Retornar is clicked | Ativo | 2 / 2 |
| `codvH` | Group Botão Avançar is clicked | Ativo | 2 / 2 |
| `codvN` | Group Botão Retornar is clicked | Ativo | 3 / 3 |
| `codvU` | Group Botão Gerar proposta Tecnica/Comercial is clicked | Ativo | 2 / 2 |
| `codva` | Group Botão Calcular is clicked | Ativo | 5 / 5 |
| `codvm` | Group Botão Gerar Proposta unificada Inglês is clicked | Ativo | 10 / 10 |
| `codwJ` | Group Botão Gerar Proposta unificada Inglês is clicked | Ativo | 12 / 12 |
| `codwi` | Icon E is clicked | Ativo | 3 / 3 |
| `codws` | Icon E is clicked | Ativo | 1 / 1 |
| `codwu` | Icon F is clicked | Ativo | 1 / 1 |
| `codwz` | Icon ionic outline filter color is clicked | Ativo | 1 / 1 |
| `codxE` | Debug_api | Ativo | 1 / 1 |
| `codzb` | Group Botão Gerar Proposta separada Inglês is clicked | Ativo | 14 / 14 |
| `codzc` | Group Botão Gerar proposta Tecnica&Comercial is clicked | Ativo | 2 / 2 |
| `codxk` | Group Botão Gerar Proposta separada Inglês is clicked | Ativo | 15 / 15 |
| `codyS` | Group Botão Gerar Proposta separada Portugues is clicked | Ativo | 15 / 15 |
| `codyx` | Group Botão Gerar Proposta separada Portugues is clicked | Ativo | 15 / 15 |
| `codzi` | Group Botão Gerar Proposta unificada Portugues is clicked | Ativo | 12 / 12 |
| `coeAK` | Group Botão Gerar Proposta unificada Portugues is clicked | Ativo | 10 / 10 |
| `coeAe` | Group Botão cadastrar contato cliente is clicked | Ativo | 4 / 4 |
| `coeAp` | Group Botão Criar Cliente is clicked | Ativo | 3 / 3 |
| `coeAw` | Group E is clicked | Ativo | 4 / 4 |
| `coeBH` | Icon J is clicked | Ativo | 2 / 2 |
| `coeBN` | Group Novo comentário SOL.VAGAS is clicked | Desativado | 0 / 5 |
| `coeBZ` | Group E is clicked | Ativo | 3 / 3 |
| `coeBg` | Icon A is clicked | Ativo | 2 / 2 |
| `coeBm` | Icon K is clicked | Ativo | 2 / 2 |
| `coeBs` | Group Nova requsição projeto is clicked | Desativado | 0 / 9 |
| `coeCO` | Group Encaminhar para serviço is clicked | Desativado | 0 / 6 |
| `coeCb` | Group Retornar para o cliente is clicked | Ativo | 4 / 4 |
| `coeCm` | Icon fa fa-angle-right is clicked | Ativo | 1 / 1 |
| `coeCo` | Icon K is clicked | Ativo | 1 / 1 |
| `coeCt` | Group Novo comentário SOL.VAGAS is clicked | Desativado | 0 / 5 |
| `coeDF` | Group ProjetoRM is clicked | Ativo | 1 / 1 |
| `coeDK` | IonicCheckbox A value changed | Ativo | 1 / 1 |
| `coeDM` | IonicCheckbox A value changed | Ativo | 1 / 1 |
| `coeDR` | Text registros por pág  Pré Cálculo is clicked | Ativo | 1 / 1 |
| `coeDW` | Back Page is clicked | Ativo | 2 / 2 |
| `coeDc` | Group IZZZZ is clicked | Ativo | 2 / 2 |
| `coeDi` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `coeDo` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `coeDp` | Foward page is clicked | Ativo | 2 / 2 |
| `coeDv` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `coeEB` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `coeEH` | Text registros por pág Proposta is clicked | Ativo | 1 / 1 |
| `coeEM` | Back Page is clicked | Ativo | 2 / 2 |
| `coeES` | Group JZZZZ is clicked | Ativo | 2 / 2 |
| `coeEY` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `coeEe` | Text paginas do miolo is clicked | Ativo sem ações | 0 / 0 |
| `coeEf` | Foward page is clicked | Ativo | 2 / 2 |
| `coeEl` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `coeEr` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `coeEx` | Group JZZZZ is clicked | Ativo | 1 / 1 |
| `coeFC` | Group Menu Projetos is clicked | Ativo | 1 / 1 |
| `coeFE` | Group botão solicitar - abertura de projeto copy is clicked | Ativo | 1 / 1 |
| `coeFJ` | Icon fa fa-angle-right is clicked | Ativo | 1 / 1 |
| `coeFO` | Icon fa fa-angle-right is clicked | Ativo | 1 / 1 |
| `coeFQ` | Icon fa fa-angle-right is clicked | Ativo | 1 / 1 |
| `coeFV` | Icon fa fa-angle-right is clicked | Ativo | 1 / 1 |
| `coeFa` | Icon K is clicked | Ativo | 1 / 1 |
| `coeFc` | Icon K is clicked | Ativo | 1 / 1 |
| `coeFh` | Icon K is clicked | Ativo | 1 / 1 |
| `coeFm` | Icon K is clicked | Ativo | 1 / 1 |
| `coeFo` | Icon back is clicked | Ativo | 1 / 1 |
| `coeFt` | Icon  advance is clicked | Ativo | 1 / 1 |
| `coeFy` | Recurring | Desativado | 0 / 2 |
| `coeGE` | Detect A user has become Inactive | Desativado | 0 / 2 |
| `coeGK` | Group Menu sair is clicked | Desativado | 0 / 2 |
| `coeGQ` | Icon fa fa-angle-right is clicked | Ativo | 1 / 1 |
| `coeGS` | Icon K is clicked | Ativo | 1 / 1 |
| `coeGX` | Group Encaminhar para serviço is clicked | Desativado | 0 / 6 |
| `coeGk` | Group Nova requsição projeto is clicked | Desativado | 0 / 7 |
| `coeHB` | Group Menu requisições is clicked | Ativo | 1 / 1 |
| `coeHG` | Group ProjetoRM is clicked | Ativo | 3 / 3 |
| `coeHN` | Group VZZZZ is clicked | Ativo | 3 / 3 |
| `coeHU` | Foward page is clicked | Ativo | 2 / 2 |
| `coeHa` | Back Page is clicked | Ativo | 2 / 2 |
| `coeHg` | Text registros por pág treinamento is clicked | Ativo | 1 / 1 |
| `coeHl` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `coeHr` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `coeHx` | [GT001] Group Novo funcionario is clicked | Ativo | 1 / 1 |
| `coeIa` | Group Menu Precificaçao is clicked | Ativo | 1 / 1 |
| `coeIh` | Group Menu Materiais is clicked | Ativo | 1 / 1 |
| `coeNU` | [GT001] Group Nova precificaçao is clicked | Ativo | 2 / 2 |
| `coeNf` | Text registros por pág 2 is clicked | Ativo | 1 / 1 |
| `coeNm` | Back Page is clicked | Ativo | 2 / 2 |
| `coeNx` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `coeOI` | Foward page is clicked | Ativo | 2 / 2 |
| `coeOQ` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `coeOb` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `coeOm` | Group Precificaçao is clicked | Ativo sem ações | 0 / 0 |
| `coeOs` | [GT002] MaterialIcon Alterar precificaçao is clicked | Ativo | 2 / 2 |
| `coePA` | [GT003] MaterialIcon Excluir precificaçao is clicked | Ativo | 2 / 2 |
| `coePL` | [GT001] Group Novo material is clicked | Ativo | 2 / 2 |
| `coePW` | [GT002] MaterialIcon Alterar material is clicked | Ativo | 2 / 2 |
| `coePe` | [GT003] MaterialIcon Excluir material is clicked | Ativo | 2 / 2 |
| `coePp` | Back Page is clicked | Ativo | 2 / 2 |
| `coeQA` | Text paginas do miolo is clicked | Ativo | 2 / 2 |
| `coeQI` | Foward page is clicked | Ativo | 2 / 2 |
| `coeQT` | Group ultima pagina is clicked | Ativo | 2 / 2 |
| `coeQe` | Group primeira pagina is clicked | Ativo | 2 / 2 |
| `coeQm` | Text registros por pág 2 is clicked | Ativo | 1 / 1 |
| `coeVL` | Group Botão cadastrar preficicaçao is clicked | Ativo | 3 / 3 |
| `coeVX` | IonicIcon Q is clicked | Ativo sem ações | 0 / 0 |
| `coeVd` | Group Button Fechar is clicked | Ativo | 1 / 1 |
| `coeVk` | Group Botão alterar preficicaçao is clicked | Ativo | 2 / 2 |
| `coeVv` | Group Button Fechar is clicked | Ativo | 1 / 1 |
| `coeWC` | Group Botão excluir precificaçao is clicked | Ativo | 3 / 3 |
| `coeWO` | Group Botão cancelar excluir precificaçao is clicked | Ativo | 1 / 1 |
| `coeXW` | Group Menu home 10 precificaçao is clicked | Ativo | 2 / 2 |
| `coeXh` | Group Menu home 20 precificaçao is clicked | Ativo | 2 / 2 |
| `coeXs` | Group Menu home 50 precificaçao is clicked | Ativo | 2 / 2 |
| `coeYA` | Group Menu home 10 material is clicked | Ativo | 2 / 2 |
| `coeYL` | Group Menu home 20 material is clicked | Ativo | 2 / 2 |
| `coeYW` | Group Menu home 50 material is clicked | Ativo | 2 / 2 |
| `coebL` | Group Botão excluir material is clicked | Ativo | 3 / 3 |
| `coebX` | Group Botão cancelar excluir material is clicked | Ativo | 1 / 1 |
| `coebe` | PopUp Altera material is clicked | Ativo sem ações | 0 / 0 |
| `coebk` | Group Botão alterar material is clicked | Ativo | 2 / 2 |
| `coebv` | Group Button Fechar is clicked | Ativo | 1 / 1 |
| `coecC` | Group Botão cadastrar preficicaçao is clicked | Ativo | 3 / 3 |
| `coecO` | Group Button Fechar is clicked | Ativo | 1 / 1 |
| `cofDM` | Every time condition | Ativo | 1 / 1 |
| `cofDY` | Every time condition | Ativo | 1 / 1 |

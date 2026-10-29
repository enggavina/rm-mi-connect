# Execução da revisão de paridade RMMI

Pedido de 29/10/2026. Complementa [o plano de paridade](../plano_paridade_rmmi_web.md), sem substituir o histórico das entregas. O sistema existente é a base; a implementação ocorre no EM e o Bubble permanece somente para leitura.

Primeiro incremento desta revisão **publicado**: seleção de fotos (A), composição do Cronograma e ordem do roteiro (parte de B/C), exclusão protegida de títulos e organização de menus (D/E/F). Migrações 022–024, consumidor `675649e`, Railway `65221686-f149-4917-aa1e-f5e1c3b234f8` com `SUCCESS`. [Relatório com validações, diferenças e pendências](relatorio_entrega_paridade_rmmi.md). A tabela abaixo registra o baseline e a ordem definida **antes** das alterações; não declara todos os itens concluídos.

## Discovery e classificação

Fontes detalhadas: [fotos/Report Building](discovery_rmmi_fotos_report_builder.md), [Planejamento](discovery_rmmi_planejamento.md), [Cadastros e Autorizações](discovery_rmmi_cadastros_autorizacao.md), [Comercial](discovery_rmmi_comercial.md). Cada relatório explicita cobertura, IDs e lacunas; inventariar eventos não significa ter lido suas ações, nem executar uma query prova um workflow completo. A revisão das páginas críticas continua até cobrir seus fluxos ativos relevantes.

Infraestrutura reutilizada: App Router/SSR e shell EM, componentes de formulário/galeria/tabela/paginação, JWT/RLS, SSO Central, `rm_web_mutate_v1`, permits de uso único, recibos idempotentes, controle por versão, leitores e editores existentes. Não remover o limite Suspense que protege a hidratação do shell. Migrações 001–021 são aplicadas e imutáveis.

## Ordem objetiva antes das alterações

| Ordem / funcionalidade | Origem | Estado e destino EM | Dependências / arquivos principais | Risco e critério |
| --- | --- | --- | --- | --- |
| A. Seleção individual de fotos | `projeto/coiiy`, `coiln/coimF/cojAc/cojAh` | Parcial: bool já persistido/importado; falta comando/UI em `/projetos/[id]`. | `data.ts`, nova policy/action de fotos, galeria existente, migração 022 e testes. | Médio: preservar arquivos/ordem, autorização atual, replay, conflito; seleção sobrevive à recarga. Report Building continua fornecedor legado até integração posterior. |
| B. Cronograma orientado a projeto e células | `rm_planejamento/cnsnM`, `Group Gestao_projeto_redesign/comJg` | Divergente: Gantt existente não representa o grupo. Reutilizar detalhe/editores em jornada por projeto e célula; manter Gantt como outra visualização. | Leitores compartilhados, `/cronograma`, CellEditor, rotas projeto/PCP, operações transacionais. | Alto: `indice` do roteiro ≠ `posicao` da fila; troca de projeto deve limpar alocação. Exibição mobile também depende da visibilidade. |
| C. Gestão de alocações existentes | `comCr/copGz/comNF/comAy` e abas do `comJg` | Parcial: criar/editar existe; visibilidade não recompõe fila; ordenação/retirada e atribuições de execução incompletas. | Gateway/locks de projeto+célula, snapshots e versões, modelos de Engenharia e dados operacionais. | Alto: não copiar delete sem proteção. Não apagar registros enviados/fotos capturadas/trabalho offline. Contratos e concorrência antes da UI. |
| D. CRUD de Títulos de Fotos | `Group Gestão de Titulos de fotos`; condições GT001/005/006/007 (rótulos antigos divergem) | Parcial: criar/editar na Engenharia; adicionar acesso Cadastros e exclusão protegida reutilizando entidade/editor. | `engineering-*`, `rm_cadastro_fotos`, Cadastros, migração 023 e testes. | Médio: referências de modelos e fotos operacionais impedem exclusão; permissões não podem depender só do botão. |
| E. Tipos de equipamentos e gestão de tipos | `Group Tipos equipamentos`, matriz em `rm_gestao` | Básico implementado; matriz tipo×célula/formulários/fotos/aprovadores implementada na Engenharia. Preservar menus distintos apontando consumidores existentes. | Cadastros, Engenharia, form builder; complementar campos/ações após contrato dos grupos. | Médio: não criar segundo catálogo nem confundir editar tipo com reescrever alocações. |
| F. Modelos de formulários | `rm_gestao`, Form/Subtitle/Question/Item | Já implementado em `/modelos-formularios`; complementar somente diferenças comprovadas. | Construtor e versões publicadas existentes; relatórios. | Alto se alterar IDs usados pelo offline. Manter publicação imutável. |
| G. Templates Word | `Group Templates`, GT004, `custom.templates` | Não implementado: `rm_templates_word` existe na 005, sem fluxo web/importador demonstrado. | Reconciliação/importação do catálogo real, DOCX/Google Docs, permissões, armazenamento e contratos de geração. | Alto: não substituir por Form. Não afirmar integração pronta com APIs 501. |
| H. Células, equipe e usuários | `Group Botão nova celula`, `Group Gestão dos usuários`, `settings_rm` | Célula básica pronta; imagens/equipe/acesso operador-célula e usuários parciais. | Identidades legadas, `rm_tablet_celula_users.identidade_id`, delegação e MFA, SSO; leitores/CRUD existentes. | Alto: admin web não promove operador/global; não criar vínculo por nome ou email automaticamente. |
| I. Autorização: elementos e individual | `autorizacao/cnCcs`, Elemento/usuarios permitidos | Produção com 0 elementos; catálogo e membership explícita compreendidos, sem herança demonstrada. [Contrato proposto](contrato_autorizacao_elementos_em.md) e [classificação dos 237 eventos](classificacao_eventos_pendentes_rmmi.md) documentam reuso/bloqueios. | Reconciliar schema005, importar dados reais, resolver identidades por ID/binding aprovado e mapear consumidores; propor `em.authorization.read/manage` após consumidor compatível, sem alterar Central nesta etapa. | Crítico: tabela vazia não ativa enforcement; helper005 não é autoridade web. Sem autoelevação, vínculo por email, promoção global ou alteração das identidades mobile. |
| J. Precificação e materiais | `settings_rm`, proposta, Pricing/Material | Não implementado; 005 aproxima contrato e não basta. | Migração aditiva dos campos reais, carga própria, novas capacidades comerciais após consumidor, cálculo CV/KW/polos/motor/serviço/área. | Alto: fallback é menor potência superior; divergência textual KW deve ser documentada e resolvida explicitamente. |
| K. Propostas estimadas/firme e revisões | `proposta/coczM`, Proposta_controle/Proposta_motor_Budgetaria | Não implementado; depende de J. | Cliente/contato/vendedor/responsável, componentes, numeração/revisão, PT/EN, PDF e armazenamento. | Alto: não inventar espanhol, estados/valores ou substituir vendedor User por texto. Resultado externo com falha explícita. |
| L. Complementos e relatórios | Dossiê, comentários/anexos, geração/compilação | Consulta existente; criação/edição, jobs e geração pendentes. | A/G, autorização/armazenamento privado, contratos existentes, idempotência externa e auditoria. | Alto: sem sucesso fictício, mocks permanentes ou ativação da ponte de saída. |

## Organização de menus

- **Planejamento:** Projetos a liberar para Oficina (reutilizar Recebimentos e preservar critério real), Projetos, Células por projeto (jornada comJg), Planejamento, Aprovações de formulários. Fila/carga, Gantt e aprovações de etapas continuam acessíveis, distinguindo decisões de etapas da revisão de formulários.
- **Cadastros:** Título de Fotos; Tipos de Equipamentos (catálogo); Gestão de Tipo de Equipamentos (matriz de Engenharia); Gestão de Formulários (construtor); Gestão de Templates (Word, entrega própria). Não anunciar um item como funcional enquanto não houver seu fluxo.
- **Autorização:** Gestão de elementos e Gestão individual; implementação dependente do contrato/identidades, com autorização de execução no servidor.
- **Orçamentação:** Gerador de propostas estimadas, Precificação orçamentária, Materiais; implementar infraestrutura/dados/cálculo antes da jornada de proposta.

## Inconsistências a tratar explicitamente

- O grupo comJg não é Gantt. Ordem do roteiro e fila da célula são conceitos independentes.
- Bubble permite apagar alocação sem proteger histórico; APIs de ordenação expostas/sem autenticação e autobinding amplo não serão copiados. Preservar o efeito legítimo com escopo/autorização/versões.
- Troca de projeto não limpa célula atual em um fluxo legado; o EM deve limpar para impedir ações sobre outra alocação.
- `AprovacaoForm` atribui avaliador antes do registro existir; `rm_aprovacoes_registro` é histórico de decisão e não serve como substituto.
- Templates Word são entidade distinta de Form. Tipo de equipamento é catálogo distinto da matriz.
- Elemento usa aplicação textual (PAINEL/COMERCIAL/GESTÃO etc.), divergindo do comentário aproximado005. Gestão individual pode buscar perfil pelo primeiro nome coincidente; adotar identidade exata, sem replicar colisão de nomes.
- Pricing/propostas precisam contrato aditivo real; não construir regras financeiras sobre colunas aproximadas005.

## Validação e publicação

### Incremento 025 publicado: ajustes e fotos operacionais

Pedido posterior à publicação 024: remover a funcionalidade “Quantidade prevista de fotos”, a aba de Aprovações de etapas do dossiê do projeto e o checkbox de definição manual de formulários na nova alocação. A coluna histórica de quantidade não será apagada; novas escritas serão recusadas e os recibos anteriores preservarão seu replay. A nova alocação sempre usará os modelos, enquanto a edição das alocações existentes conservará os vínculos e proteções de registros enviados. Aprovações continuam no módulo próprio e no Cronograma; o mobile não muda.

O contrato definido antes da implementação previu completar fotos obrigatórias da alocação no Cronograma: adicionar títulos aplicáveis em lote, editar tag, retirar slot vazio e restaurar explicitamente o mesmo ID quando necessário. Reutilizar `rm_fotos`, `rm_cadastro_fotos`, `lixeira`, o gateway web, SSO e o hook de envio; nenhuma tabela paralela ou contador previsto será criado. Migração nova 025, leitores/ações `operational-photo-*` e editor reutilizável na aba de fotos.

Risco identificado antes da implementação: a RPC mobile anterior atualiza a captura com `lixeira=false`, podendo restaurar silenciosamente uma foto retirada. A nova versão precisa serializar projeto/foto e recusar esse caso com mensagem clara. A fila mobile conserva arquivo, parâmetros e protocolo; o gestor poderá restaurar o slot original para que o operador repita o mesmo envio. Não haverá exclusão física, descarte automático da fila ou recriação de ID para resolver a disputa.

Adicionar exige escolhas limitadas à célula/global e planejamento autorizado; isso não concede acesso ao catálogo completo de Engenharia. Capturas em URL principal ou lista, seleção para relatório e vínculos de outro contexto impedem retirada. Versões exatas e hash do conjunto protegem alterações concorrentes com web/mobile; repetição exata exige autorização atual e não duplica fotos. Validar também retirada seguida de envio offline, restauração e retry do mesmo UUID, incluindo efeitos em snapshots, fila e dados existentes, antes de aplicar no Supabase e publicar no Railway EM.

Cada incremento precisa de persistência real, acesso atual, estados de espera/erro, replay após resultado ambíguo e conflito explícito. Usar testes de domínio/BFF e PostgreSQL isolado, incluindo disputa quando necessária; tipos, build e smokes; navegador com fixtures exclusivamente locais e negações públicas após deploy. Não existe comando lint configurado atualmente: declarar essa limitação, sem fingir execução. Não criar dados artificiais em produção.

Aplicar somente novas migrações ao Supabase `oficina-em-mi-off`, com verificação de alvo e preservação das tabelas anteriores. Publicar no Railway EM após validações, conforme autorização permanente. Registrar commit, migração, deploy, provas, limites e pendências no relatório final. Entregas parciais não significam conclusão da paridade global.

## Resultado do incremento 025

Consumidor **`801bb589d083cd270e45e3318dfad9912b44bf96`**, Railway **`8debd02e-4f6e-44e9-8e6a-22fc43a44216`** com `SUCCESS`, migração **025 aplicada** após ensaio com rollback. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/40946936615). As três remoções e a gestão operacional de fotos foram concluídas. **227 testes desktop, 14 suítes PostgreSQL, 32 verificações de navegador, tipos, build e dois smokes aprovados**. Os 19 cenários novos e 13 da galeria usaram o build `xdXK03Qwidz_57ktbm0MH`, HTTP/autenticação simulados e DOM real; zero erros de página ou origens externas. As capturas desktop/390 px foram inspecionadas. Não houve CRUD artificial em produção nem login Microsoft humano automatizado. A aplicação definitiva preservou 67 snapshots completos; histórico 001–025 confirmado, todas essas migrações agora são imutáveis. Health 200, 20 negações e PKCE até Microsoft conferidos. [Relatório atualizado](relatorio_entrega_paridade_rmmi.md).

Próxima prioridade objetiva: atribuição de avaliador antes do primeiro registro de formulário; depois, editor das regras operacionais de etapas. Continuam pendentes exclusão protegida de alocação, visibilidade com manutenção de fila, cadastros complementares, Word/relatórios, autorização por elementos e comercial, conforme dependências da matriz.

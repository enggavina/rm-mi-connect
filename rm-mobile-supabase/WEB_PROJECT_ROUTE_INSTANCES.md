# Projeto, equipamento e roteiro independente — 037

Continuação da 036, em 05/11/2026. A operação continua sendo `save_project_with_equipment`, pelo gateway, sessão RM/SSO, MFA e capacidade `em.projects.manage` existentes. Não há uma segunda API de cadastro, importação de projetos nem atualização automática de dados antigos.

## Discovery e diferenças encontradas

O Bubble `rmmi` Live foi consultado somente para leitura nesta entrega. `custom.dados_equipamento` confirma os relacionamentos **Equipamento → ProjetoRM** e **Equipamento → Tipo_equipamento**. `custom.projeto_rm` também possui a referência de equipamento e um campo direto legado de tipo. `custom.celula_tipo_equipamento` contém célula, tipo e visibilidade; não possui ordem própria do roteiro. A ordem do modelo no EM vem do cadastro de células. O workflow `copKS` (`ordenacao_celula_projeto`) confirma a ordem específica de `Celula_Projeto`; as opções inseguras de API pública e ignorar privacidade do Bubble não foram reproduzidas.

As dependências de planejamento e aprovações já haviam sido inspecionadas em [discovery de planejamento](../docs/discovery_rmmi_planejamento.md) e [discovery de regras](../docs/discovery_rmmi_regras_etapas.md). A 037 reutiliza suas entidades e os comandos de instâncias 024–027.

| Requisito antes da 037 | Estado encontrado | Implementação |
| --- | --- | --- |
| Projeto e equipamento atômicos | Implementado na 036 | Estendido, sem duplicar o cadastro |
| Tipo no equipamento | Coluna e FK existentes; ausente no novo editor | Campo relacional no contrato existente |
| Cópia de fotos, formulários e etapas | Parcial: 018 copiava por nova alocação; cadastro 036 não inicializava roteiro | Snapshot integral e materialização única na transação do cadastro |
| Independência das configurações existentes | Já preservada nos editores de instâncias | Marcador impede reaplicar o modelo ou consultá-lo para novas exceções do projeto |
| Ordem do projeto | Implementada na 024 | Ordinais próprios congelam a ordem inicial exibida pelo modelo |
| Migração automática de projetos antigos | Inadequada: há vínculos e configurações legados ambíguos | Nenhum backfill; inicialização explícita somente sem operação existente |

## Relações finais

```text
rm_projetos.equipamento_id ↔ rm_equipamentos.projeto_id
rm_equipamentos.tipo_equipamento_id → rm_tipos_equipamento

Modelo: tipo → rm_celula_tipos_equipamento
              → vínculos de formulários, fotos-modelo e regras-modelo

Instância: projeto → rm_celulas_projeto
                    → forms_ids copiados
                    → rm_fotos do projeto/alocação
                    → rm_aprovacoes_etapas do projeto/alocação
```

`rm_projetos.tipo_equipamento_id` é uma coluna legada preexistente. A entrega não a elimina, normaliza nem duplica novas classificações nela. A classificação efetiva usa o equipamento vinculado de forma bidirecional e única; quando esse equipamento não tem tipo, ou quando não existe equipamento nem vínculo reverso, a projeção pode consultar o valor legado. Vínculos ambíguos não escolhem um equipamento arbitrariamente. O recebimento PCP usa a mesma projeção para nome, filtros, totais e paginação.

## Contrato e transação

O payload existente recebe `equipment.tipo_equipamento_id`, UUID ou `null` em um equipamento legado já sem classificação. Para criar projeto ou completar um vínculo ausente pelo contrato novo, o tipo precisa ser um UUID existente. `equipment.changes` continua restrito aos dados técnicos da 031; não recebe essa classificação como texto ou campo técnico paralelo.

O novo wrapper valida papel, MFA, UUID do envio e replay. Adquire o lock de projeto 11, a linha do projeto, o lock do equipamento 37 e a linha do equipamento. Reutiliza a 036 com um recibo interno, preservando a validação de versões exatas, o vínculo canônico, os dados técnicos e o journal de proteção offline da 031. A alteração de tipo também usa esse journal. Depois inicializa o roteiro e grava o recibo externo do payload completo. Uma falha em qualquer etapa desfaz projeto, equipamento, cópias e recibos da transação.

Payloads antigos da 036, sem o campo novo, preservam replays de recibos concluídos e atualizações de projetos existentes; não recebem uma classificação ou roteiro por inferência. Uma tentativa nova de criar projeto por esse payload, ou por `save_project` isoladamente, é recusada na fronteira SQL com `PT423`, mesmo com permit SSO válido. O editor orienta recarregar e selecionar o tipo. O cadastro novo sempre usa o bundle com o campo relacional, equipamento e roteiro atômicos. O recebimento mobile continua no seu RPC anterior.

## Conteúdo clonado

Uma única consulta MVCC captura todas as matrizes ativas do tipo e seus filhos, após os locks de engenharia existentes. Todas as inserções posteriores leem esse JSON imutável:

- **Alocações:** célula, visibilidade, links de formulários e ordem. A ordem segue `célula.ordem`, `célula.indice`, `matriz.id`, com nulos ao final; a instância recebe ordinais sequenciais próprios. Datas e horas operacionais não são inventadas a partir do modelo.
- **Fotos:** cadastro, categoria, etapa, tipo legado, identificador, título, descrição, legenda, tag e número. Quando o título legado está vazio, o título vigente do cadastro é resolvido no mesmo snapshot e congelado na cópia. Recebem IDs e vínculos de projeto/alocação próprios. Arquivos capturados, seleção para relatório e lixeira não são copiados.
- **Aprovações:** origem, destino, status-alvo, bloqueio, aprovador individual, listas de origem e de retorno. Recebem IDs próprios e estado de decisão inicial Nulo, sem autor ou data de aprovação anteriores.

As definições de formulário são o catálogo compartilhado existente: a cópia é do vínculo `forms_ids`, não uma duplicação das perguntas ou de respostas. Versões publicadas pelo editor 019 mantêm os IDs congelados; a edição de um roteiro altera seus vínculos, sem alterar esse catálogo. Respostas já existentes continuam protegidas pelos comandos e snapshots anteriores.

O marcador privado guarda a origem e prova a inicialização mesmo quando o modelo está vazio. A chave primária por projeto impede clonar duas vezes. As referências de origem de fotos e regras já existentes continuam sendo usadas; não foram criadas colunas de origem redundantes nessas entidades.

Modelos com aprovação apontando para célula ausente do conjunto ativo são rejeitados com `PT422`, antes de gravar a instância. A interface orienta revisar a Engenharia. Não se ativam células ou corrigem destinos automaticamente para contornar esse dado inválido.

## Independência e compatibilidade

Depois da inicialização, `plan_cell` cria uma célula adicional como exceção do projeto, com suas configurações explícitas; não consulta novamente o modelo vigente. O materializador de serviço retorna zero alterações para um projeto inicializado. Os editores existentes de fotos, formulários, regras e ordem continuam alterando apenas instâncias.

Mudar o tipo é recusado quando há marcador, alocação, foto, registro de formulário, regra ou histórico de aprovação. O roteiro e seus dados são preservados. Projetos antigos com operação existente não recebem um roteiro novo nem reconciliação silenciosa. Projetos legados sem operação podem ser completados explicitamente pelo editor, inclusive quando ainda não possuem equipamento.

Os dois triggers novos protegem o vínculo canônico de projeto/equipamento e o tipo de uma instância, inclusive contra escrita direta, mobile e ETL. A proteção também vale quando o equipamento legado já tinha o tipo correto e nenhuma edição técnica era necessária. Inserir outro projeto apontando para esse equipamento é recusado. O lock 37 existe mesmo antes de uma nova linha de equipamento ficar visível, fechando a disputa entre clone e inserção concorrente de referência inversa.

Não se alteram payloads, UUIDs, atores, filas SQLite ou recibos mobile. Uma escrita antiga conflitante retorna conflito e mantém seu envio para reconciliação.

## Banco e autorização

Migração nova: `037_rm_web_project_route_instances.sql`; migrações aplicadas anteriores permanecem intactas.

Nova tabela **privada** `rm_private.project_route_instances`: `projeto_id` PK/FK, `equipamento_id` único/FK, `tipo_equipamento_id` FK, ator, UUID do envio, snapshot de origem e data. Há dois índices de unicidade, FKs com exclusão restrita e uma constraint de JSON array. Não há coluna nova nas entidades de negócio existentes.

Funções novas: projeção de tipo efetivo, metadados mínimos de inicialização, inicializador interno, guard de vínculos e wrapper de mutação. Os RPCs de equipamento, roteiro, recebimentos e materialização mantêm seus nomes e limites. `plan_cell` também passa a aceitar `motivo_atraso` na mesma entidade de alocação, com a validação do gateway existente.

O marcador e o inicializador não têm acesso direto para clientes ou `service_role`. Os helpers chamados pelos RPCs `SECURITY INVOKER` possuem apenas o `EXECUTE` necessário; a consulta de metadados exige sessão RM ativa. Não se alteram RLS, capacidades SSO, papéis de usuário nem permissões globais da Central de Acessos.

## Verificação

As suítes `web_project_route_instances.sql`, `web_project_route_instances_upgrade.sql` e `web_project_route_instances_concurrency.sql` cobrem cadastro, equipamento/tipo, cópia integral de configuração, IDs independentes, reenvio, edição isolada entre projetos, mudanças futuras de modelo, projeto legado, modelo vazio/inválido, permissões e preservação de dados no upgrade 036→037. O upgrade aquece chamadas anteriores, mantém um permit SSO emitido antes da DDL, recusa os dois cadastros web antigos com permit válido sem consumir recibo nem deixar dados parciais, e verifica replay e novos recebimentos mobile de projeto existente.

Cinco disputas reais com duas conexões PostgreSQL verificam replay simultâneo, duas inicializações concorrentes, edição do modelo, inserção inversa durante clone ainda não confirmado e um escritor externo que já segura a linha do projeto. O runner rastreado inclui as novas suítes, além dos testes anteriores de 035 e 036.

A validação consolidada e a publicação em produção são registradas no [plano de paridade](../plano_paridade_rmmi_web.md) e na [documentação do portal](../desktop/docs/web-platform.md).

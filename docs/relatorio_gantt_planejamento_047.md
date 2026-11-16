# Gantt de projeto, célula e oficina — entrega 047

Data: 16/11/2026. Prioridade zero definida pelo usuário: trabalhar prazos e etapas nas três visões do Gantt. Esta entrega avança o planejamento existente, mantendo o mesmo Supabase, SSO, projetos, células e identificadores do mobile.

## O que foi implementado

O menu **Gantt e cronograma** passa a abrir o Gantt geral. A tela oferece seleção de célula ou projeto, com atalhos também no projeto e na fila da célula. O roteiro, os registros, as fotos, os formulários e as aprovações permanecem acessíveis pelos contextos existentes.

As três visões permitem pesquisar e filtrar etapas, consultar períodos de 14/42/90 dias e trabalhar os prazos por campos, movimento das barras ou ajuste de suas extremidades. Há suporte a teclado e aos campos em tela de celular. Etapas sem programação ou com datas inconsistentes aparecem explicitamente.

Uma alteração cria uma prévia. A revisão mostra datas anteriores e propostas, exige motivo e salva o conjunto em uma única transação. Uma edição concorrente exige recarregar os dados; uma resposta de rede desconhecida permite reenviar o mesmo protocolo sem duplicar o trabalho. A consulta geral deixa de depender das primeiras 50 linhas: o snapshot completo comporta até 2.000 alocações. Acima disso, o usuário precisa selecionar um projeto ou célula.

No projeto, é possível criar/remover dependências término-início, definir espera em dias corridos e propor a reprogramação das sucessoras. A cascata preserva durações e só altera o plano depois da revisão. Ciclos, vínculos entre projetos e alterações que exigiriam mover etapas encerradas são recusados. Etapas retiradas conservam seus vínculos para uma restauração futura.

A referência do plano registra os prazos para comparar variações. A interface apresenta a referência mais recente; as anteriores permanecem preservadas. A instalação não cria referências, dependências ou datas artificiais para os projetos existentes.

## Consistência e autorização

A migração 047 acrescenta duas tabelas privadas e o snapshot do Gantt. O novo envio usa a fachada existente de mutação, SSO/MFA e capacidades de planejamento/projetos. Não há escrita direta nas tabelas pelo cliente. O lote verifica as versões dos projetos e alocações e reutiliza `plan_cell`, preservando auditoria e regras operacionais. Dados, dependências, referência e recibos são revertidos juntos se qualquer etapa falhar.

O ensaio remoto com rollback e a aplicação verificaram as **87 relações RM/private/Storage anteriores**, seus dados, estrutura e permissões, além dos **153 OIDs/owners/ACLs de funções existentes** e histórico de migrações. O catálogo final tem **81 tabelas RM/privadas e 159 funções**. SSO e os dois administradores EM permanecem preservados. As duas tabelas novas estavam vazias ao instalar.

As leituras autorizadas após a instalação confirmaram snapshots completos nas três visões: **774 etapas em 104 projetos e 25 células** na visão geral, **19 etapas** no projeto consultado e **34 projetos** na célula consultada. São contagens observadas naquele instante, não dados de demonstração nem garantia de que o planejamento histórico já esteja completo.

## Validação

- **522 testes web e 116 mobile** no CI aprovado, tipos, build de produção e os dois smokes aprovados; dois contratos QR web/mobile aprovados.
- **41 suítes SQL** no runner completo, além de bootstrap e 46 migrações; sete disputas novas entre sessões, executadas separadamente. Incluem dois planejadores, replay, mobile antes/depois, planejamento legado, retirada e nova alocação.
- Ensaio de upgrade, rollback/commit locais e sete testes de adulteração do envelope aprovados.
- **16 cenários de interface real local**, com React/CSS do produto e ação de salvamento simulada: três escopos, filtros, zoom, drag, resize, teclado, dependências, cascata, referência, retry, projeto encerrado, conflitos, navegação e largura de 390 px. Nenhum erro JavaScript ou requisição externa. Esses testes não equivalem a um login humano em produção.
- Auditoria dos **82 arquivos JavaScript** do build contra dez segredos locais conhecidos sem ocorrência.
- Os três snapshots reais foram validados também pelo schema e BFF do produto, incluindo campos, tipos, timestamps exatos, escopos e restrições de leitura. O payload privado temporário foi removido após gerar a prova sanitizada.

## Publicação

Consumidor: `605f0abad5a3c7e300122ac9e85906248eeedec7`. Migração 047 aplicada no Supabase `oficina-em-mi-off`, SHA256 `29da54afed20e6f016861359a7265cb77389db751f9d7f1059b5c4c4613cf2f4`. Migrações anteriores permanecem imutáveis.

Railway EM: `bdc48c7c-6cf3-4ff0-a29b-6536e4aebbcd`, com **SUCCESS**. [Gantt no portal](https://em-web-production.up.railway.app/cronograma?view=gantt) e [CI do consumidor aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/43946420070). Health 200, **118 recusas de acesso anônimo/cookie forjado em 59 URLs e 20 recusas nas APIs**, total de 138 verificações de acesso aprovadas. Login Microsoft-only e navegação SSO até a Microsoft conferidos, sem autenticar uma pessoa.

Não houve CRUD artificial de projetos em produção, alteração de dispositivo, novo APK, mudança na Central/Microsoft ou escrita no Bubble. `SYNC_OUTBOX_ENABLED=false` permanece.

## Próximas evoluções da prioridade zero

1. Calendários de trabalho por célula, turnos, feriados e durações em horas/dias úteis, com revisão antes de recalcular datas.
2. Marcos contratuais no gráfico, caminho crítico e folgas, usando dependências conferidas e separando duração planejada de execução real.
3. Capacidade de pessoas/equipamentos, conflitos de recursos e comparação de cenários antes de publicar um replanejamento.
4. Histórico selecionável de referências e comparação das revisões; acompanhamento confiável do realizado com apontamentos de execução.

O Gantt atual trabalha dias corridos e dependências dentro do projeto. Não calcula caminho crítico, capacidade ou percentual de execução. Outros editores e envios offline conservam suas regras: podem produzir uma divergência de dependência que será mostrada no Gantt. A gravação pelo Gantt valida todos os vínculos dos projetos alterados, inclusive etapas fora da célula consultada. A CLI permanece planejada, sem implementação nesta entrega.

[Contrato técnico e funcional](../rm-mobile-supabase/WEB_GANTT_PLANNING.md). Evidências locais ignoradas: `.tmp/gantt-{desktop-tests,build,smoke,sso-smoke,full-sql,races}.log`, `.tmp/gantt-ui-qa/results.json`, `.tmp/gantt-{rehearse,apply}-proof.json`, `.tmp/gantt-envelope-local-proof.json`, `.tmp/gantt-production-read-qa.json`, `.tmp/gantt-production-bff-proof.json`, `.tmp/gantt-browser-secret-audit.json`, `.tmp/gantt-environment-proof.json`, `.tmp/gantt-ci-proof.json`, `.tmp/gantt-deployment-proof.json`, `.tmp/gantt-public-qa.json` e `.tmp/gantt-public-sso-qa.json`.

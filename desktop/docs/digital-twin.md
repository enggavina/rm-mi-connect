# Gêmeo digital integrado ao EM — 048

O gêmeo digital está em `/gemeo-digital`, dentro do portal EM. A cena, a visão gerencial e a API usam a mesma origem, login, serviço Railway e base operacional Supabase do restante do sistema. O item do menu lateral abre uma rota interna, com estado ativo e a navegação do portal; o acesso em Acompanhamento segue o mesmo caminho.

## Acesso do Igor

A identidade corporativa de Igor Nascimento foi conferida como `softdev05@mielectric.com.br`. O cadastro corporativo está ativo, vinculado ao Azure, com vínculo profissional vigente. O vínculo SSO dedicado do EM está ativo e resolve o perfil `WEB-SOFTDEV05`, já administrador do EM com as 18 capacidades existentes. As três leituras necessárias — `em.portal.read`, `em.projects.read` e `em.planning.read` — já estavam concedidas.

Não foi necessário promover usuário, conceder administração global, modificar credenciais ou alterar a identidade mobile legada do Igor. O serviço antigo do Workshop aplicava uma lista nominal separada, mesmo com uma concessão central ativa; a rota interna usa a sessão do EM e elimina essa segunda barreira para este acesso.

Os testes administrativos confirmam o cadastro e as leituras sob o papel autorizado; não substituem o login Microsoft interativo do próprio titular. Nenhuma senha ou MFA de uma pessoa foi automatizada.

## Aplicação e dados

A cena original do repositório Workshop foi adaptada para componentes do portal, com carregamento separado do módulo 3D. Os controles de câmera, cobertura, camadas, pessoas/logística ilustrativas, mapa PCP, células, filtros, detalhes de equipamento, prazos, bloqueios e visão gerencial foram preservados. A página não carrega a autenticação, a demonstração fictícia ou o cliente Bubble da aplicação anterior. Fontes e texturas são locais; não há dependência de CDN para a cena.

O CSS fica restrito ao contêiner `.em-workshop`, preservando o Shell e as outras telas do portal. Sem suporte a WebGL2, a página oferece a visão gerencial dos mesmos dados. Falhas, expiração ou recusa da API retiram a leitura anterior da tela; não substituem dados por uma demonstração. Atualizar consulta imediatamente; enquanto a aba estiver visível, a consulta é refeita a cada dois minutos.

`GET /api/web/workshop` exige sessão atual e as três capacidades de leitura. A consulta usa o JWT local do usuário e RLS, sem chave de serviço. Respostas privadas têm `no-store`, `nosniff` e `no-referrer`. O navegador recebe somente o DTO necessário; não recebe tokens, emails, contatos, documentos, respostas de formulário ou credenciais.

A migração **048** acrescenta somente `rm_web_workshop_snapshot_v1()`, estável e `SECURITY INVOKER`, com `search_path` vazio. Perfil RM ativo e MFA quando cadastrada continuam obrigatórios. A função tem execução concedida apenas a `authenticated`; o gateway do portal verifica também SSO e capacidades. Nenhuma tabela, registro de negócio, policy existente ou identidade é regravada.

O snapshot tem um único instante de referência e lê projetos, equipamentos, clientes, responsáveis, alocações e catálogo de células em um statement consistente. São até 2.000 projetos, 20.000 alocações, 2.000 células e 10 MiB; excesso é recusado, sem indicadores calculados sobre uma página incompleta. A cena pagina até 32 equipamentos; filtros, diretório e indicadores usam o conjunto completo recebido.

## Critérios e limites

Entram os projetos com chegada registrada, não futura pelo dia civil de São Paulo, sem entrega real e com um dos status PCP operacionais reconhecidos. Cancelados, finalizando para faturar e aguardando chegada ficam fora. Todas as alocações não retiradas do conjunto são lidas, inclusive as ocultas no mobile e as encerradas para contexto.

Somente `em_dia` (**Executando**), sem fim real, gera etapa em execução. Para execução, pendências e liberações permanecem em espera. Etapas encerradas não geram bloqueio atual; campos de bloqueio desconhecidos permanecem desconhecidos. Um projeto pode executar em mais de uma célula.

O tipo usa a projeção canônica existente de Projeto/Equipamento, sem escolher a coluna legada divergente. Dados técnicos exigem vínculo bidirecional inequívoco. Tipos não suportados recebem representação genérica identificada como ilustrativa. Potência e rotação numéricas só são derivadas quando a unidade está explícita; os valores originais permanecem disponíveis para consulta.

O prazo do equipamento usa a **data contratual**, conforme o critério do Workshop. Prazo previsto ou renegociado não substitui esse compromisso silenciosamente. O Gantt continua sendo a ferramenta de edição dos prazos das células; cada indicador deve ser interpretado de acordo com seu campo de origem.

O mapa PCP representa o processo, não uma localização física medida. Arquitetura, pessoas, logística, ponte rolante e bancadas são ilustrativas. `resources=[]`, localização não registrada e capacidade real não cadastrada permanecem explícitos; nenhum vínculo físico, capacidade ou histórico foi inventado. Os projetos de demonstração do EM continuam identificados como tais e não são recriados nesta entrega.

O serviço antigo do Workshop não foi alterado nem desligado; pode ainda atender seus usuários anteriores com sua própria fonte. O menu do EM passa a abrir exclusivamente a integração interna. A ponte de saída Bubble permanece desativada.

## Verificação e publicação

539 testes web e 116 mobile no CI Node 22 aprovado, tipos, build de produção, dois contratos QR e os dois smokes aprovados. O runner PostgreSQL completou 91 etapas: bootstrap, 47 migrações e 43 suítes. O envelope de implantação passou por rollback, commit e oito adulterações recusadas. QA local com React/CSS e Canvas WebGL reais: oito cenários, incluindo desktop/celular, gerencial, filtros/fonte, recusa 401/403/503, contrato inválido e ausência de WebGL2; nenhum erro JavaScript ou pedido externo.

Ensaio remoto e aplicação da 048 preservaram dados e estrutura das **91 relações RM/private/Storage observadas**, **159 funções anteriores com seus OIDs, definições e ACLs**, catálogo e histórico. A nova função é a única adição. SHA256 aplicado: `bbf8af8681ed6184cb126205ffd6fa23c7add5a0d99fee9f50930fe32ea519ec`.

Após a aplicação, leituras autorizadas de mgavina e Igor produziram snapshots completos e válidos no leitor e schema da interface: **180 projetos, 1.461 alocações e 29 células**. Ambos os projetos DEMO estavam presentes. Datas exatas e referências internas foram conferidas; a captura privada temporária foi removida. Essas contagens representam o instante da consulta, não uma garantia de que todos os dados históricos estão preenchidos.

Auditoria dos **91 JavaScripts** do build contra dez segredos locais conhecidos sem ocorrências. As novas dependências 3D foram fixadas no lockfile, com auditoria de produção sem vulnerabilidades conhecidas na instalação.

Consumidor `813d34acc2f99f6084d41b35751f754b60254662`; Railway EM `1be51db3-9e73-4007-9192-b888660e3cb2`, com **SUCCESS**, em 16/11/2026. [Gêmeo digital no EM](https://em-web-production.up.railway.app/gemeo-digital) e [CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/43958506200). Os quatro SVGs da cena responderam 200 com conteúdo idêntico ao publicado; o início do SSO continuou chegando à Microsoft, sem autenticar uma pessoa.

Health 200 e **144 verificações de acesso aprovadas**: 122 recusas para anônimo/cookie forjado em 61 URLs e 22 recusas nas APIs, incluindo a nova API da oficina. Não houve CRUD de negócio artificial em produção nesta integração.

Evidências locais ignoradas: `.tmp/igor-access-internal-twin-proof.json`, `.tmp/workshop-{envelope-local,rehearse,apply}-proof.json`, `.tmp/workshop-production-bff-proof.json`, `.tmp/workshop-browser-secret-audit.json`, `.tmp/workshop-ui-qa/results.json`, `.tmp/workshop-ci-proof.json`, `.tmp/workshop-deployment-proof.json`, `.tmp/workshop-public-qa.json`, `.tmp/workshop-public-sso-qa.json`, `.tmp/workshop-public-assets.json` e logs `.tmp/workshop-{web-tests,types,build,smoke,sso-smoke,full-sql}.log`.

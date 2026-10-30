# Consulta do dossiê por projeto — 030

Incremento somente de leitura, sobre as entidades e permissões existentes. Acrescenta duas RPCs `STABLE SECURITY INVOKER`, três índices não exclusivos e um normalizador puro de filtros. Não altera linhas, tabelas, políticas antigas, Storage, comandos ou recibos de 001–029. Total RM permanece 71 tabelas, das quais 57 públicas com RLS.

## Leitores e escopo

`rm_web_project_comments_v1(p_project_id uuid,p_filters jsonb default '{}')` e `rm_web_project_documents_v1(p_project_id uuid,p_filters jsonb default '{}')` exigem JWT de identidade RM ativa administrador/padrão/auditor, respeitam RLS e são executáveis somente por `authenticated`. Cliente, inativo, anônimo e `service_role` não recebem esse catálogo web. Projeto inexistente/invisível retorna nulo. O BFF exige separadamente portal/projetos/histórico ou documentos; nenhuma capacidade ou concessão nova na Central.

As facetas são calculadas somente das linhas visíveis do projeto, independentemente do filtro ativo. Não são um diretório global de usuários ou células: incluem somente IDs citados no histórico e nomes/matrículas públicos efetivamente legíveis. Autor/célula nulos continuam nulos. Células históricas sem alocação atual não são removidas da consulta nem restauradas por ela.

## Filtros e paginação

Ambos aceitam `search` (até 200 caracteres), `author_id` nulo/UUID, `from_date`/`to_date` nulos ou datas ISO reais `YYYY-MM-DD` e `page` inteiro de 1 a 100.000. Comentários também aceitam `cell_id` nulo/UUID; documentos aceitam `source` all/documents/docs e `status` all/No prazo/Vencido/other. Chaves desconhecidas, tipos incoerentes, datas inválidas ou início posterior ao fim recebem `22023`. UUID válido de outro contexto produz resultado vazio e não acrescenta uma identidade às facetas.

Busca é literal, sem interpretar `%`, `_`, `*` ou aspas como operadores. Comentários pesquisam o texto do evento; documentos pesquisam nome e observação. Período refere-se à **criação**, com início inclusivo e o fim completo inclusivo no fuso `America/Sao_Paulo`, independentemente do fuso do processo/banco.

Tamanho fixo de 25, ordenado por criação decrescente e UUID decrescente; na união de documentos, origem é o último desempate. A página efetiva é limitada à última disponível, ou 1 quando vazia. Resultado: `project_id`, `items`, `total` filtrado, `unfiltered_total` do projeto, `page`, `page_size`, `filters` canônicos sem página e `facets`. A composição, contagem e página usam o mesmo snapshot SQL. As páginas não prometem congelar um histórico que recebe novos registros entre requisições.

## Metadados documentais

`rm_documentos` e `rm_docs` são unidos com `UNION ALL`, sem deduplicar UUIDs iguais entre tabelas. A identidade é origem + UUID. `created_by` é real nas duas entidades. Campos exclusivos de anexo permanecem nulos nos documentos gerados; não são inferidos MIME, status, vencimento, visibilidade ou observação inexistentes.

Situações No prazo/Vencido são manuais, preservando a 029. O filtro other agrupa situações históricas diferentes e ausência de situação nos **anexos**; é uma categoria de pesquisa, não um status salvo. Selecionar situação restringe a anexos; um documento gerado não recebe estado artificial. Facetas de situações refletem somente grupos realmente presentes no projeto.

Os DTOs não incluem URL, caminho de Storage, token, chave S3, hash, metadados de reserva ou envelope privado. `has_file` informa somente se existe uma referência não vazia. Abrir continua pelo endpoint existente que verifica a sessão/permissão atual e assina por 60 segundos; a consulta não cria link permanente nem acessa arquivos pendentes. As proteções internas do perfil cliente e de uploads incompletos da 029 permanecem.

## Validação e reversão

Testar escopo entre projetos/perfis, texto literal, filtros combinados antes da paginação, autores reais, empates e colisão de UUID entre origens, vazio filtrado versus projeto vazio, limites de datas de São Paulo e ausência de URL/segredos. Upgrade compara integralmente as 71 tabelas RM e buckets/objetos, todas as políticas e funções/grants anteriores, além de replay aquecido de comentários, reservas e envio mobile.

Reversão da interface pode manter os leitores e índices aditivos; não remover a proteção de Storage/RLS/imutabilidade da 029 nem reescrever consultas históricas para corrigir dados. Nenhuma escrita no Bubble, novo APK, ativação de ponte ou registro artificial em produção faz parte deste incremento.

## Incremento 030 publicado: consulta do dossiê e acessos

**Início** concentra os acessos em **12 cards**, agrupados em Operação, Planejamento e Cadastros para quem possui todas as capacidades correspondentes. A lateral mantém **até cinco atalhos**: Início, Projetos, Cronograma, Formulários e aprovações e Aprovações de etapas. Cada conta vê somente seus módulos autorizados; atalhos removidos continuam acessíveis pelos cards e os endereços/guardas existentes. Indicadores, projetos recentes e pendências permanecem abaixo dos acessos. O catálogo de permissões é único; o shell/limite servidor-Suspense foi preservado. Menu móvel com foco, teclado, Escape, fechamento por botão/fundo/atalho e restauração de foco.

**Projetos → abrir projeto → Histórico/Documentos** oferece busca literal, filtros e **25 itens por página**, com contagem filtrada e total do projeto. Comentários: texto, autor, célula e período de criação; documentos/anexos: nome/observação, origem, situação, autor e período. Datas inicial/final inclusivas no fuso de São Paulo. Autores/células/opções vêm somente do histórico visível do próprio projeto, incluindo células históricas; autor ausente não é inventado. Documentos e anexos usam uma só paginação e identidade origem + UUID, mantendo IDs iguais entre tabelas sem deduplicação. Status de anexo continua manual; documentos gerados não recebem situação artificial.

A 030 acrescenta dois leitores `STABLE SECURITY INVOKER` executáveis somente por `authenticated`, um normalizador puro e três índices não exclusivos. Gate de identidade RM interna ativa e RLS permanecem; o BFF exige as capacidades atuais da consulta. Apenas a aba ativa consulta o leitor correspondente, substituindo as cargas integrais antigas de comentários/documentos/anexos. Filtros inválidos são corrigíveis e falhas/respostas de outro contexto não viram um histórico vazio fictício. Os DTOs não contêm URL, caminho, token ou segredo de arquivo; abrir continua pelo endpoint autorizado com assinatura de 60 segundos. Criação, arquivo/protocolo congelados, SSO/MFA, replay e proteções de upload/imutabilidade da 029 foram preservados.

**324 testes desktop, 87 mobile no CI, 19 suítes PostgreSQL, tipos, build e dois smokes aprovados**. Duas conexões reais validaram a consistência de snapshots de leitura durante commits concorrentes; não são novas disputas de escrita do produto. Navegador: **9 cenários da página inicial e 17 de consulta do dossiê**, build `yd6vgvVrM5CUVCwWZa9wR`, DOM real e HTTP/autenticação simulados, zero erros/origens externas. Os 12 cards foram navegados e o menu foi inspecionado em desktop/390 px. Auditoria de **72 JavaScripts** sem os dez segredos locais conhecidos. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41101711224).

Ensaio com rollback e aplicação preservaram integralmente **71 tabelas RM públicas/privadas e dois snapshots de Storage**, **88 definições/grants de funções anteriores e 46 políticas RM/Storage**. Sem nova tabela, journal ou registro de negócio. Pós-aplicação: **71 tabelas RM/privadas, 57 públicas com RLS**, 102 usuários, 778 registros, 14.595 fotos, 945 etapas, 94 comentários, 15 anexos, 14 documentos, outbox 4 e 4 recibos web. Conferência: 0 reservas/0 conclusões, 3 buckets/13 objetos. Os journals e reservas anteriores foram comparados sem presumir que estavam vazios; SSO, os dois administradores EM, guardas operacionais e envelope mobile preservados.

Fonte SQL, índice e commit conferidos com SHA256 `e06b720eb340d7af11bbf0fa4d1ea0651571ba35c0ee97be33fa8e4a18a0a266`; a fonte aplicada tem o mesmo hash. Migrações **001–030 aplicadas e imutáveis**.

Consumidor **`e3f37d7711849ef6ecb9221e027d0188667c41db`**, Railway **`73d3a4e6-a953-4c5a-b782-cb954caa3305`** com `SUCCESS`; health 200, **58 negações em 29 URLs e seis verificações de API, total de 64 bloqueios**, com anônimo/cookie forjado e POST de origem não autorizada. Microsoft-only, CSRF, callback estrito, cookie opaco HttpOnly/Secure e início PKCE real até Microsoft aprovados; cancelado somente o fluxo próprio de QA.

O emulador **Excalibur_API_35 / emulator-5554** foi aberto para o teste solicitado. O instalador existente **1.2.3 / versionCode 6**, SHA256 `586e453ad2432de94350f9a9d3eadd72c824a9079926b3a9ca8770697dd898bf`, foi atualizado com `adb install -r` e a MainActivity foi iniciada. Não houve wipe, limpeza de dados, desinstalação ou automação de credenciais; não se declara comparação de hash dos dados do usuário nem homologação de toda a jornada em aparelho real. Nenhum APK novo foi gerado pelo incremento 030.

Não houve CRUD artificial em produção nem login Microsoft humano automatizado. Nenhuma capacidade/concessão Central, promoção global, escrita no Bubble, reconfiguração de bucket ou ativação da ponte; `SYNC_OUTBOX_ENABLED=false` permanece. Dados, respostas e trabalhos offline existentes foram preservados. Criação da 029 continua; edição/exclusão de comentários, substituição/exclusão/versionamento de anexos, Word/relatórios e QR permanecem pendentes.

**Próxima prioridade:** edição técnica do equipamento, com contrato dos campos, autorização, histórico e proteção das respostas e trabalhos offline existentes. Edição/exclusão/versionamento do dossiê, Word/relatórios, QR, cadastros complementares, capacidade/calendários/lotes, comercial, laboratório e coexistência continuam no plano; a paridade global permanece em andamento.

Provas locais ignoradas: `dossier-search-030-{rehearse,apply}-proof.json`, `dossier-search-postflight.json`, `dossier-search-ci-proof.json`, `dossier-search-deployment.json`, `dossier-search-public-qa.json`, `public-sso-qa.json`, `home-qa-summary.json`, `dossier-search-qa-summary.json`, `dossier-search-browser-secret-audit.json`, `em-emulator-open-proof.json` e logs `dossier-search-{desktop-tests,build,full}.log`.

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

# Substituição de anexos privados com versões — incremento 033

A 033 acrescenta uma nova publicação imutável a cada substituição. O arquivo e a linha `rm_docs` anteriores permanecem intactos. A série usa uma intenção privada explícita; não reescreve URLs, não remove arquivos, não altera as migrações 001–032 e não cria versões retroativas nos dados existentes.

## Origem e leitura

`rm_web_project_attachment_snapshot_v1(p_project_id uuid,p_attachment_id uuid,p_history_page integer default 1)` é `STABLE SECURITY INVOKER`, aplica as RLS existentes e exige identidade RM interna ativa. Somente `authenticated` executa. Projeto/anexo ausente ou de outro projeto retorna `null`.

O helper `project_attachment_version_context_v1` é `SECURITY DEFINER` com gate interno e projeto/anexo exatos. Ele projeta somente metadados de negócio; não devolve reservas, Auth UID, protocolos privados, SHA256, caminhos de Storage, URLs ou linhas completas do diário. O helper de prova completa `project_attachment_publication_v1` não é executável por clientes.

O snapshot contém `project`, `attachment`, `series`, `can_replace`, `reason`, `context_version` e `history`. `attachment` identifica ID/projeto, título/descrição, MIME, situação/vencimento, autor e datas, visibilidade, nome original do arquivo e tamanho quando comprovados, além de disponibilidade. `series` informa raiz, versão selecionada e cabeça atual; pode ser `null` quando a origem não é comprovada. `history` possui itens em revisão decrescente, total, página ajustada e tamanho 25. Cada item contém os mesmos metadados, revisão, motivo e indicador de versão atual.

Somente publicações internas comprovadas pela reserva finalizada da 029 participam: os metadados, projeto, autoria, URL/caminho canônicos e publicação devem corresponder exatamente. Registros externos/legados sem essa prova e documentos gerados permanecem no consumidor anterior. Um prefixo de URL não prova origem. A publicação original aparece como versão virtual 1, sem inserir histórico retroativo; novas versões publicadas formam uma sequência contínua. Reservas incompletas não entram na história.

O arquivo atual precisa ter objeto e prova de tamanho/MIME/SHA compatíveis com a reserva. Objetos indisponíveis em versões históricas são identificados sem inventar disponibilidade; o histórico conhecido permanece legível. A versão selecionada antiga não oferece substituição e aponta a cabeça atual. Projetos encerrados permanecem em consulta. O detalhe não reagrupa a lista de Documentos da 030: todas as linhas e contagens existentes continuam preservadas.

## Reserva e publicação

Novas operações no envelope `rm_web_mutate_v1`:

- `reserve_project_attachment_version`: `upload_id`, `projeto_id`, `source_attachment_id`, versões exatas de projeto/anexo, `expected_context_version`, título, descrição, filename, MIME, tamanho, SHA256, vencimento/situação, motivo e `confirm_change=true`.
- `finalize_project_attachment_version`: somente `projeto_id` e `upload_id`; o protocolo deve ser o próprio `upload_id`.

A reserva possui protocolo distinto do upload/publicação. Campos são estritos. Reutilizam-se PDF/JPEG/PNG, até 20 MiB, título de até 200 caracteres, descrição/motivo de até 2000, filename de até 180 sem separadores/controles, SHA256 hexadecimal e situação manual `No prazo`/`Vencido`. Motivo e confirmação são obrigatórios. O nome e a extensão são conferidos pelo servidor junto com assinatura, bytes e hash. Um arquivo de bytes iguais pode formar uma nova versão somente como intenção explícita confirmada; a retentativa do mesmo protocolo não duplica a publicação.

A escrita exige perfil RM administrador/padrão e `em.projects.manage`, com leituras atuais de portal/projeto/documentos na camada web. Não exige ser o autor do arquivo anterior. A reserva e sua finalização pertencem ao mesmo ator RM/Auth; outro administrador não assume a intenção pendente. Identidade, SSO/MFA e autorização atuais precedem inclusive o replay.

A reserva cria uma linha em `project_attachment_uploads` e uma intenção em `project_attachment_versions`, contendo raiz, predecessor, próxima revisão, autoria, motivo, versões/hash e `before_record`. Nenhum documento novo fica visível nessa fase. O servidor armazena os bytes no mesmo namespace privado `web-dossier/{projeto}/{upload}` da 029, sempre com `upsert=false`; os caminhos anteriores não são reutilizados.

A finalização revalida projeto aberto, versão atual exata, origem, objeto anterior e contexto congelado. Confere o objeto novo e publica uma nova linha `rm_docs`, sempre interna, antes de concluir a reserva e registrar `after_record`. Uma única transação torna a nova linha e a publicação da versão legíveis; a política existente mantém objetos pendentes privados. O trigger imutável da 029 protege os registros dos anexos publicados, inclusive os novos; as políticas de Storage e o envio com `upsert=false` impedem sobrescrita pelo fluxo do aplicativo.

## Concorrência, comando correto e repetição

Ordem dos locks: protocolo `14`, tipo da reserva por upload `33`, projeto `11`, linha do projeto, intenção/reserva, anexo anterior e objeto anterior; a finalização confere também o objeto novo. O lock de tipo também envolve todos os comandos antigos `finalize_project_attachment`, antes de delegá-los ao fluxo da 029. Assim, uma reserva 033 ainda não confirmada não pode ser publicada pelo comando antigo depois de ele aguardar o projeto.

A operação antiga continua publicando suas reservas ordinárias e recuperando seus recibos originais. Para uma reserva versionada, exige-se o comando de versão original; o comando antigo é recusado sem criar documento, recibo final ou ligação parcial. A nova operação também não assume reservas ordinárias antigas.

Somente um filho publicado é permitido por predecessor e por revisão da raiz. Duas reservas pendentes podem coexistir, mas depois da primeira publicação a segunda fica com conflito e mantém seus bytes e intenção privados. O hash inclui projeto, anexo, prova de publicação, identidade/geração do objeto e tamanho/MIME/SHA, além da série publicada. Não inclui reservas pendentes nem objetos novos ainda não publicados, evitando invalidar a própria intenção; acessos e metadados incidentais de Storage não invalidam conteúdo inalterado. Alterações de geração/ETag fazem parte da prova de conteúdo.

Resposta incerta repete o mesmo UUID, arquivo, motivo e corpo. Recibo concluído corresponde exatamente ao ator/operação/corpo e é retornado antes de novas guardas de encerramento/cabeça. Não há descarte, sobrescrita ou reenvio automático com outro protocolo. Se o contexto muda após o upload, o objeto e a reserva permanecem privados para reconciliação explícita; banco e Storage não formam uma transação única.

## Resultado, preservação e limites

O recibo de reserva identifica upload/projeto, caminho exclusivamente server-side, MIME/tamanho/SHA, predecessor, raiz, próxima revisão e hash congelado. O recibo final identifica novo anexo, predecessor/raiz/revisão, metadados publicados, versão do projeto e contexto posterior. O navegador recebe a projeção mínima apropriada; não recebe prova privada, URL ou caminho reservado.

O diário privado guarda o anexo anterior e o novo, autor da substituição, motivo e protocolos. Nenhum cliente, inclusive `service_role`, tem acesso direto às intenções. Abrir qualquer versão publicada usa o endpoint autorizado existente `documents/{id}?source=docs`, com assinatura curta e permissão vigente. A publicação de uma nova versão não revoga ou substitui o ID anterior.

Não há nova política pública, bucket, concessão da Central, APK, alteração de filas/respostas offline ou evento na outbox. A ponte Bubble permanece desativada. Exclusão, limpeza de pendências, restauração automática de cabeça, reclassificação de anexos legados e geração de documentos exigem entregas próprias.

## Validação e publicação

`web_project_attachment_versions_upgrade.sql` aplica a fonte exata sobre 032, com chamadas anteriores aquecidas, comparando 73 tabelas RM e duas de Storage, políticas e funções não alteradas. A instalação cria somente a tabela privada vazia. `web_project_attachment_versions.sql` cobre origem, privacidade, versões, 27 itens de histórico, protocolo/tipo correto, bytes/provas, perfis, MFA/SSO, retentativas e disputas reais entre conexões. O executor usa um PostgreSQL local descartável. Produção deve receber somente a 033 no Supabase `oficina-em-mi-off` e o consumidor EM no Railway após a validação, sem dados de negócio artificiais em produção.

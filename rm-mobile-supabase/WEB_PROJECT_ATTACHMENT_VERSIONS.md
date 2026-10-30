# Substituição de anexos privados com versões — incremento 033

**Status:** 033 aplicada no Supabase `oficina-em-mi-off` e consumidor publicado em [EM web](https://em-web-production.up.railway.app), commit `7f03ed157b3a1c41b3596426fac36b37fb9117d1`, Railway `60867f4c-6c3a-4205-87a8-91db3cab7b50` com `SUCCESS`. [CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41129901612).

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

`web_project_attachment_versions_upgrade.sql` aplica a fonte exata sobre 032, com chamadas anteriores aquecidas, comparando 73 tabelas RM e duas de Storage, políticas e funções não alteradas. A instalação cria somente a tabela privada vazia. `web_project_attachment_versions.sql` cobre origem, privacidade, versões, 27 itens de histórico, protocolo/tipo correto, bytes/provas, perfis, MFA/SSO, retentativas e disputas reais entre conexões. O executor usa um PostgreSQL local descartável. A 033 foi aplicada somente no Supabase `oficina-em-mi-off`, seguida do consumidor EM no Railway após as validações. Migrações **001–033 aplicadas e imutáveis**; nenhum dado de negócio artificial foi gerado em produção.

## Incremento 033 publicado: evidências e limites

**Projetos → abrir projeto → Documentos → Versões do anexo → Enviar nova versão** permite registrar um novo arquivo com motivo, revisão dos dados e confirmação. Somente a versão atual de um anexo interno com publicação privada comprovada pode originar a substituição; projeto encerrado e versões anteriores permanecem em consulta. PDF, JPEG ou PNG de até 20 MiB, com título, observação, status manual e vencimento; uma escolha explícita pode reutilizar bytes iguais, sempre criando novo ID e caminho. Os arquivos, URLs, IDs, autores e datas anteriores são preservados.

O detalhe mostra versão selecionada, versão atual e histórico por 25, com autor, data, motivo e download de cada arquivo pelo próprio ID. A lista paginada da 030 continua mostrando todas as linhas existentes e as novas versões como registros individuais; não há deduplicação por título nem ocultação automática de versões antigas. Anexos legados sem prova de publicação privada, URLs externas e documentos gerados ficam em consulta, sem família ou histórico artificial.

A operação reserva uma intenção, valida tamanho/tipo/extensão/assinatura/SHA256 dos bytes, envia um objeto privado imutável e publica uma nova linha rm_docs ligada à anterior. Reutiliza as guardas, o bucket privado e o caminho derivado web-dossier da 029; não altera nem exclui arquivos antigos. O banco confere ator, projeto, origem, versão atual, contexto e metadados do objeto na conclusão. Locks de protocolo, tipo da reserva e projeto, além das constraints da cadeia publicada, impedem ramificações e o uso do finalizador comum para contornar o fluxo versionado, inclusive com a reserva ainda não confirmada em outra transação. A prova de conteúdo inclui tamanho/MIME/SHA, geração e eTag; atualizações apenas de acesso não invalidam uma intenção sem mudança de conteúdo.

Banco e Storage não formam uma transação única. Arquivo/protocolos/corpo ficam congelados para retentativa; resposta incerta não vira sucesso. Se o contexto muda após o upload, o objeto e a intenção incompletos permanecem privados e fora da cadeia publicada, aguardando reconciliação explícita. Não há sobrescrita, exclusão, limpeza automática ou novo UUID silencioso. Recibos concluídos continuam com replay autenticado, com SSO/MFA e autorização atuais verificados antes da recuperação. A escrita reutiliza em.projects.manage e leituras de portal/projeto/documentos, com perfis RM administrador/padrão; não amplia concessões.

**385 testes desktop, 87 mobile no CI, 22 suítes PostgreSQL e 13 novas disputas reais aprovados**, além de tipos, build e dois smokes. Navegador: **16 cenários**, build `A2vgpERD_ZFJvN6JvTo-1`, DOM real com HTTP/autenticação simulados, sem banco ou SSO reais; zero erros/origens externas e capturas desktop/390 px inspecionadas, incluindo título de 200 caracteres e controles de confirmação sem overflow. Auditoria de **76 JavaScripts** sem os dez segredos locais conhecidos. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41129901612).

Ensaio com rollback e aplicação preservaram **73 tabelas RM anteriores e dois snapshots de Storage**, todas as colunas/contagens/hashes e **75 definições de colunas/ACLs**, **100 OIDs/ACLs de funções anteriores** — 98 definições idênticas e duas alterações exatas revisadas — e **46 políticas RM/Storage**. As exceções são renomear o core anterior sem mudar corpo/OID/ACL e acrescentar as duas operações ao mapa SSO. Após instalar: **74 tabelas RM/privadas, 57 públicas com RLS, 104 funções RM e nova tabela de versões vazia**; 178 projetos, 15 anexos, 14 documentos, 778 registros e 61.803 respostas preservados, 102 usuários, outbox 4, 4 recibos web e 3 buckets/13 objetos. Reservas, diários e filas anteriores foram comparados sem presumir que estivessem vazios; SSO, administradores, policies e guardas anteriores permanecem.

Fonte SQL local, índice, commit e fonte aplicada conferidos com SHA256 `ae2b343e4619d79e34b0056ec02d39afdbeb93d4b354ed1ef014aade4fd8b6e4`. Migrações **001–033 aplicadas e imutáveis**; a instalação não altera arquivos, cria famílias de versões artificiais ou reescreve o histórico existente.

Consumidor **`7f03ed157b3a1c41b3596426fac36b37fb9117d1`**, Railway **`60867f4c-6c3a-4205-87a8-91db3cab7b50`** com `SUCCESS`; [EM web](https://em-web-production.up.railway.app) com health 200. QA público: **68 negações em 34 URLs e dez verificações de API, total de 78 bloqueios**, com anônimo/cookie forjado e POST de origem indevida. Login Microsoft-only, CSRF, callback estrito, cookie opaco HttpOnly/Secure e início PKCE até Microsoft conferidos; somente o fluxo próprio de QA foi cancelado, sem autenticação humana automatizada ou CRUD artificial em produção.

Nenhum novo APK, identidade/grant na Central, escrita no Bubble, evento novo na outbox ou ativação da ponte; SYNC_OUTBOX_ENABLED=false permanece. Dados, arquivos, intenções, respostas e trabalhos offline anteriores foram preservados. O Live observado edita a mesma linha e oferece exclusão; o histórico privado com retenção é uma decisão explícita do EM. Exclusão de anexos/comentários, compartilhamento com cliente e reconciliação de documentos legados não fazem parte desta entrega.

**Próxima prioridade:** QR de identificação do projeto, integrado à jornada mobile existente, com contrato próprio e preservação dos vínculos e trabalhos offline. QR ainda não foi implementado por este incremento. Word/relatórios, cadastros complementares, capacidade/calendários/lotes, comercial, laboratório e coexistência continuam no plano; a paridade global permanece em andamento.

[Discovery Live](../docs/discovery_rmmi_versoes_anexos.md). Provas locais ignoradas: `attachment-versions-033-{rehearse,apply}-proof.json`, `attachment-versions-postflight.json`, `attachment-versions-ci-proof.json`, `attachment-versions-deployment.json`, `attachment-versions-public-qa.json`, `public-sso-qa.json`, `project-attachment-version-qa-summary.json`, `attachment-versions-browser-secret-audit.json` e logs `attachment-versions-{desktop-tests,build,smoke,sso-smoke,final-full}.log`.

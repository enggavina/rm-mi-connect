# Comentários e anexos privados do projeto — 029

Contrato definido antes da implementação do incremento. Reutiliza `rm_comentarios` e `rm_docs`; `rm_documentos` continua dedicado aos relatórios/compilados. O Bubble é referência somente de leitura, sem ativação da ponte ou alteração de dados existentes. Migrações 001–028 permanecem imutáveis.

## Comentários

`add_project_comment` recebe `projeto_id`, `celula_projeto_id`, `expected_project_updated_at`, `expected_allocation_updated_at` e `evento`. A célula destinatária deve pertencer ao projeto e não estar retirada; estar oculta não impede comentário. Projeto encerrado permite somente consulta. O texto é aparado e deve ter entre 1 e 10.000 caracteres. Identidade e data são definidas no servidor; o ID é o UUID do envio. Não há alteração ou exclusão de comentário nesta entrega.

Usa o envelope web/SSO existente, `em.projects.manage`, escritor RM administrador/padrão e leituras de portal, projetos, planejamento e histórico. Comentários mobile, recebimento e decisões já registrados mantêm sua origem e não são reclassificados. O evento de saída do novo comentário reutiliza `Comentario_Celula`, sem executar a ponte.

## Reserva e conclusão de anexo

Arquivos PDF, JPEG e PNG, de 1 byte a 20 MiB. Nome de apresentação até 200 caracteres; descrição opcional até 2.000; nome original do arquivo até 180, sem separadores ou caracteres de controle. MIME/assinatura e SHA256 são verificados pelo BFF. `status` é explicitamente `No prazo` ou `Vencido`, conforme o legado, sem cálculo automático pela data. `data_vencimento` é nula ou um timestamp ISO finito com fuso explícito. Não há alteração/exclusão de anexos nesta entrega.

`reserve_project_attachment` recebe `upload_id`, `projeto_id`, `expected_project_updated_at`, `nome`, `descricao`, `filename`, `mime_type`, `byte_size`, `sha256`, `data_vencimento` e `status`. O UUID de protocolo da reserva é derivado de `em-dossier-reserve:` mais o UUID final. A reserva imutável fica em `rm_private.project_attachment_uploads`, sem linha parcial em `rm_docs`. O caminho é gerado no SQL: `web-dossier/<projeto UUID>/<upload UUID>.<extensão derivada do MIME>`.

Resultado da reserva, além do envelope: `record:{upload_id,projeto_id,path,mime_type,byte_size,sha256}`. A repetição exata retorna o mesmo caminho/metadados sem criar nova reserva. Outro ator, corpo ou operação não reutiliza um protocolo. A mesma identidade de upload não pode ser reservada por outro protocolo.

O BFF usa a chave de serviço EM somente para Storage, no bucket `rm-documentos` e no caminho reservado. Nunca envia a chave ao navegador nem usa a chave para o envelope de mutação. O upload é privado e `upsert=false`. Um arquivo já existente somente é reutilizado após verificar o conteúdo, tamanho e hash; nunca é sobrescrito. O prefixo `web-dossier/` não é autorizado pelas políticas legadas de INSERT/UPDATE, cujo primeiro segmento exige `auth.uid()`.

`finalize_project_attachment` recebe apenas `projeto_id` e `upload_id`; o UUID do protocolo é o próprio `upload_id`. Exige a mesma identidade/ator da reserva, projeto ainda aberto, objeto no caminho exato e metadados de Storage de tamanho, MIME e SHA256 iguais à reserva. O hash em `user_metadata` é confiável apenas porque esse prefixo é escrito pelo BFF autorizado; não substitui a verificação dos bytes pelo BFF. A versão original do projeto é conferida na reserva; concluir não regrava dados do projeto e valida novamente seu estado aberto.

Só então é criada uma linha `rm_docs` com ID igual ao upload, autor do servidor, status/vencimento reservados, `visivel_cliente=false` e URL autenticada do projeto Supabase autorizado `oficina-em-mi-off`. A URL usa o prefixo fixo `https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/`, mantendo compatibilidade com o download web e o mobile 1.2.3. Não é aceita uma URL informada pelo cliente.

Uma política SELECT restritiva adicional em `rm_docs` limita somente esses novos anexos a identidades internas ativas (administrador, padrão ou auditor). Um perfil `cliente` com JWT direto não consegue consultar a nova linha nem seu objeto, apesar da leitura legada ampla do bucket. O helper booleano não expõe identidades ou dados da reserva. Linhas/objetos anteriores mantêm suas políticas e comportamento existentes.

Resultado final `record:{upload_id,projeto_id,attachment_id,nome,descricao,tipo_arquivo,status,data_vencimento,visivel_cliente:false,updated_at}`. O resultado público do BFF pode reduzir esse conjunto. Downloads continuam exigindo permissão atual e URL assinada curta; um anexo não vira um documento de cliente público.

## Fronteiras, falhas e preservação

As três operações usam `em.projects.manage`; anexos também exigem leituras de portal/projeto/documentos no BFF. Não há nova capacidade ou concessão na Central. Toda tentativa, inclusive replay, exige vínculo SSO/RM ativo e MFA atual antes do recibo. O recibo concluído precede as guardas de encerramento/retirada e permite confirmar uma operação já concluída com o protocolo original. Uma intenção nova com contexto alterado recebe conflito sem reescrever seu conteúdo.

Reserva, arquivo e finalização não são uma única transação entre banco e Storage. Uma interrupção mantém reserva e arquivo privados; a retentativa conserva UUID, metadados e arquivo selecionado. Uma política SELECT restritiva só para `web-dossier/` impede que o leitor autenticado legado consulte/lista arquivos incompletos antes de existir `rm_docs` final. As permissões e nomes legados de Storage permanecem. Não há remoção física, expiração ou limpeza automática de reservas/arquivos; reconciliação futura exige ação explícita.

Objeto ainda ausente na confirmação recebe `PT503`, conservando a tentativa para retry exato. Objeto duplicado ou metadados incompatíveis recebem conflito para reconciliação, sem publicação parcial. Um trigger nega UPDATE e DELETE de qualquer anexo já publicado por esse fluxo, inclusive mudança de ID/projeto/arquivo ou um no-op que alteraria o timestamp. Escritas antigas e ETL não reinterpretam silenciosamente um arquivo web. Os anexos legados não referenciados pela reserva permanecem fora dessa guarda.

A migração instala somente o novo journal privado vazio, código e política restritiva. Provar todas as 70 tabelas RM públicas/privadas anteriores e Storage preservados; total final 71 tabelas, com as mesmas 57 tabelas públicas RM com RLS. Preservar respostas, usuários, comentários, documentos, arquivos, recibos, outbox e os dados offline existentes. Não gerar documentos, testar CRUD artificial em produção ou ativar Report Building/Word nesta entrega.

Reversão de interface mantém schema, journal, recibos e política que protege uploads pendentes. Não voltar a expor arquivos incompletos nem apagar anexos, reservas ou tentativas para desfazer a publicação.

## Incremento 029 publicado: comentários e anexos privados

**Projetos → abrir projeto → Histórico → Adicionar comentário**: escolher célula destinatária ativa do próprio projeto e registrar até 10.000 caracteres. Célula oculta continua elegível; retirada não recebe novos comentários. Autor e data vêm do servidor. Em **Documentos → Adicionar anexo privado**, selecionar PDF, JPEG ou PNG de até 20 MiB, preencher título e situação documental manual No prazo/Vencido; vencimento e observação são opcionais.

Comentários são acrescentados ao histórico existente, com contexto/versionamento e autoria preservados. O anexo só aparece após reserva da intenção, verificação dos bytes/assinatura/SHA256, upload privado imutável e confirmação no banco. UUID, conteúdo, arquivo e protocolos de reserva/publicação permanecem os mesmos na retentativa; nenhuma resposta incerta é apresentada como sucesso. Download exige permissão atual e assinatura curta. Abertura de links em outra aba conserva o arquivo e a proteção de saída da aba atual, inclusive com envio incerto. Novos anexos são internos, com `visivel_cliente=false`, RLS negando o perfil cliente e bloqueio de alteração/exclusão da linha publicada.

As operações reutilizam `em.projects.manage`, perfis RM de escrita e leituras de projeto/histórico/planejamento ou documentos conforme o comando, com SSO/MFA e recibos atuais inclusive no replay. A chave privada EM é reutilizada somente no servidor, pelo adaptador de Storage do bucket/caminho reservados; mutações de negócio continuam com JWT do usuário. Não há chave no navegador, nova capacidade/concessão na Central ou promoção global.

Banco e Storage não formam uma transação única. Se a conexão ou o contexto mudar após o upload, a reserva e o objeto incompletos permanecem privados, fora de `rm_docs`; repetir exige a intenção e o arquivo originais. Não há sobrescrita, descarte ou limpeza automática: situações pendentes exigem reconciliação explícita. Arquivos e URLs antigos, inclusive CDN Bubble, continuam como estavam; não foram copiados, re-hospedados ou apagados.

**310 testes desktop, 87 testes mobile no CI, 18 suítes PostgreSQL e 9 disputas reais novas aprovados**, além de tipos, build e dois smokes. Os **20 cenários de navegador** usaram build `kJYesPUzmlDFI56ByvnDz`, DOM real e HTTP/autenticação simulados, com capturas desktop/390 px inspecionadas e zero erros de página/origens externas. Auditoria de **72 JavaScripts** sem os dez segredos locais conhecidos. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41097259016).

Ensaio com rollback e aplicação preservaram **70 tabelas RM públicas/privadas e dois snapshots integrais de Storage**, incluindo configurações de buckets, objetos, comentários, anexos, journals e recibos anteriores; reservas novas vazias na instalação e namespace previamente livre. Pós-aplicação: **71 tabelas RM/privadas, 57 públicas com RLS**, 102 usuários, 778 registros de formulário, 14.595 fotos, 945 etapas, 94 comentários, 15 anexos, 14 documentos, outbox 4 e 4 recibos web. Na conferência havia 0 reservas/0 conclusões, 3 buckets/13 objetos; SSO, os dois administradores EM, guards 028 e envelope mobile preservados. Os journals antigos foram comparados sem presumir que estavam vazios.

Fonte SQL, índice e commit conferidos com SHA256 `e3487be74dd56830d4f57d7d6bf29ee5f64022eac15d78fcb02d76cd582903cb`; a fonte aplicada tem o mesmo hash. Migrações **001–029 aplicadas e imutáveis**.

Consumidor **`fb439d8bf210a619117fa9d3a3e7f99ad3edfb61`**, Railway **`5a9a036f-888f-4585-908b-3b0c6749d69f`** com `SUCCESS`; health 200, **44 negações em 22 URLs e seis verificações de API, total de 50 bloqueios** para anônimo/cookie forjado e POST sem origem autorizada. Login Microsoft-only, CSRF, callback estrito, cookie opaco HttpOnly/Secure e início PKCE real até Microsoft aprovados, cancelando somente o fluxo próprio de QA.

Não houve CRUD positivo/artificial em produção, login Microsoft humano automatizado ou homologação em aparelho real. **APK 1.2.3 / versionCode 6 permanece inalterado e compatível**; pull/RLS, respostas, rascunhos, arquivos, fila e recibos offline existentes foram preservados. Nenhuma escrita no Bubble, ativação da ponte, reconfiguração de bucket ou execução de Word/Report Building; `SYNC_OUTBOX_ENABLED=false` permanece. Edição/exclusão de comentários, substituição/exclusão/versionamento de anexos, compartilhamento com cliente, edição técnica, QR e geração/compilação continuam pendentes.

**Próxima prioridade:** consulta do dossiê com busca, filtros por autor/célula/período nos comentários e por metadados nos documentos, com paginação e escopo aplicados no backend. Edição técnica, Word/relatórios, QR, cadastros complementares, capacidade/calendários/lotes, comercial, laboratório e coexistência continuam no plano; a paridade global permanece em andamento.

Políticas restritivas `rm_web_dossier_internal_read` e `rm_web_dossier_published_read` preservam caminhos antigos e impedem leitura de objetos novos incompletos ou pelo perfil cliente. `rm_guard_web_dossier` conserva os metadados do arquivo publicado. Não houve recarga de dados antigos ou migração de arquivos CDN.

Provas locais ignoradas: `dossier-029-{rehearse,apply}-proof.json`, `dossier-postflight.json`, `dossier-ci-proof.json`, `dossier-deployment.json`, `dossier-public-qa.json`, `public-sso-qa.json`, `dossier-qa-summary.json`, `dossier-browser-secret-audit.json` e logs `dossier-{desktop-tests,build,full}.log`.

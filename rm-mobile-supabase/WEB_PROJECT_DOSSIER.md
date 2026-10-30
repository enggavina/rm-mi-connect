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

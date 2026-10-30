# Discovery funcional — versões de anexos privados

Data: 30/10/2026. Fonte: metadata **Live** do Bubble `rmmi`, comparada ao EM até a migração **032**. A leitura inspecionou os tipos `custom.docs` e `custom.documentos`, o popup de anexos da página `projeto`, as ações de criação/edição/exclusão e o uploader. Nenhum workflow, upload, download de arquivo de cliente, registro ou mudança de branch foi executado no Bubble. Metadata comprova a configuração, não a execução operacional de cada fluxo.

## Entidades e ações Live

| Evidência | Comportamento configurado |
| --- | --- |
| `custom.docs` — Docs | Seis campos personalizados escalares: `Arquivo` (`file`), `Nome`, `Observacao`, `Projeto_rm`, `Data_vencimento` e `Status`. Criador e datas são campos nativos. Não há referência a documento anterior, revisão, família ou motivo de substituição nesse tipo. |
| `option.statusdocs` | Duas opções: `vencido` → Vencido e `no_prazo` → No prazo. O campo de status e a data de vencimento são independentes; não foi demonstrada uma regra que derive um do outro neste recorte. |
| `custom.documentos` — Documentos | Entidade diferente: `Nome`, `PDF` em texto, `Projeto` e `Seleçao_documento`, além dos campos nativos. Não deve ser confundida com os anexos Docs nem receber uma situação documental inventada. |
| Página `projeto` (`coiiy`), popup Docs `copTw` | O popup recebe um Docs existente ou vazio. O mesmo botão `copVc` aparece como Criar ou Editar conforme o conteúdo. Os campos recebem os valores do Docs carregado. |
| Criar: evento `copWo`, ação `copWv` | Quando o Docs do popup está vazio, cria uma linha com projeto atual, nome, arquivo, vencimento, status e observação; depois mostra sucesso e fecha o popup. |
| Editar: `copYy → copZF/copZK`, depois `copZM → copZc` | Abre o Docs da linha no popup. Quando não está vazio, muda **a mesma linha**: arquivo, nome, vencimento, status e observação. Não foi observado registro de versão anterior ou motivo nessa ação. |
| Uploader `copUO` | Conteúdo inicial é a URL do arquivo atual. A propriedade `private` está explicitamente falsa. Não foi demonstrado nesta leitura um contrato equivalente aos tipos/tamanho/SHA256 da implementação EM. |
| Exclusão: `copYW → copYi → copYg` | A confirmação executa primeiro `DeleteUploadedFile` na URL do Docs e depois `DeleteThing` no Docs, seguida de mensagem e fechamento. Esse comportamento destrutivo não deve ser copiado para a entrega de versionamento. |

As condições lidas de criar/editar verificam somente Docs vazio/não vazio; o evento de confirmação de exclusão lido não mostra condição adicional. Isso não constitui autorização para ampliar permissões no EM, nem prova ausência de todas as guardas em páginas ou fluxos que ficaram fora deste recorte. As regras de privacidade default dos dois tipos permitem `viewAll`, busca e visualização de anexos para everyone, sem auto-binding e sem escrita pela Data API. O EM conserva seu acesso interno e downloads autorizados, sem reproduzir essa abertura.

## Contratos já existentes no EM

| Consumidor | Contrato e consequência |
| --- | --- |
| `rm_docs` / mapping `bridge/mapping.ts` | Representa Docs e recebe `Projeto_rm`, `Nome`, `Arquivo`, `Observacao`, `Status` e `Data_vencimento`. As linhas antigas e URLs externas continuam históricas; `sync_source` não comprova publicação privada pelo EM. |
| `rm_documentos` / mapping do endpoint `documentos` | Representa a outra entidade, com PDF/arquivo gerado e seleção para compilação. Não converter esses documentos em anexos editáveis por inferência. |
| Migração 029 — `project_attachment_uploads` | Reserva privada contém ator/Auth, projeto, dados e tamanho/hash do arquivo, caminho, protocolo, documento publicado e conclusão. É a prova durável de publicação interna do novo anexo; nenhuma identidade deve ser inferida por e-mail/nome ou só por URL. |
| Guarda `rm_guard_web_dossier` | Anexos publicados a partir de reservas 029 não aceitam UPDATE ou DELETE em `rm_docs`. Versionar exige uma nova linha; não desativar a guarda para trocar a URL da anterior. |
| `project-dossier-storage.ts` | Destino pinado ao Supabase `oficina-em-mi-off`, bucket `rm-documentos`, caminho derivado `web-dossier/{projeto}/{upload}.{ext}`. Confere bytes, assinatura e SHA256; usa `upsert:false`. Resposta perdida permite confirmar o mesmo objeto por download/hash, sem sobrescrever um objeto existente. |
| `project-dossier-upload.ts` | POST de mesma origem, autorização atual, multipart limitado, duas partes exatas, arquivo PDF/JPEG/PNG de até 20 MiB e validação de tamanho/nome/MIME/hash. Reserva e conclusão usam recibos distintos e determinísticos; o corpo e o arquivo permanecem congelados na retentativa. |
| Policies Storage 029 | Objeto `web-dossier/` incompleto não fica legível pela policy até existir `rm_docs` com a URL publicada. Upload e banco não são uma transação única: arquivo já enviado pode permanecer privado após conflito, sem exclusão automática. |
| Consulta 030 | Documentos e anexos compartilham uma lista paginada por 25, identificada por origem + ID, sem URLs no DTO. Status dos anexos é manual. Preservar o leitor e seus filtros; não deduplicar versões pelo título nem esconder linhas históricas sem contrato próprio. |
| Download `/api/web/documents/[id]?source=docs` | Consulta a linha com JWT/RLS e permissão atual de documentos, valida o destino e emite redirecionamento. Arquivo privado recebe URL assinada curta de 60 segundos. O servidor não faz fetch de URL arbitrária armazenada. Versões antigas devem continuar acessíveis pelo próprio ID. |
| Mobile e importação | `rm_docs` e `rm_documentos` já integram o conjunto sincronizado. Preservar os IDs e arquivos antigos evita invalidar consultas e trabalhos offline. A ponte de saída permanece desativada; não reimportar nem executar exportação como efeito de versionar. |

## Direção segura do incremento 033

1. Acrescentar uma nova versão como **novo anexo privado**, com novo ID/caminho, preservando todas as linhas, URLs, autores e arquivos anteriores. Não executar exclusão física, sobrescrita de bytes ou atualização do arquivo antigo.
2. Habilitar substituição somente de anexos internos publicados cuja reserva concluída corresponda exatamente ao projeto e ao documento. Documentos gerados, arquivos externos, registros de origem não comprovada e pendências não devem receber uma família de versões artificial.
3. Registrar família, versão anterior, nova versão, autor, motivo e estado atual em estrutura privada autorizada. Uma consulta específica pode mostrar a cadeia paginada e os downloads por ID, sem expor caminho, URL, Auth UID, reserva ou recibo privado completo.
4. Somente a versão atual deve originar uma substituição. Conferir versão do projeto, documento/cadeia e intenção congelada tanto na reserva quanto na conclusão, sob locks compatíveis. Duas reservas concorrentes não podem confirmar dois sucessores do mesmo documento; resposta incerta repete o protocolo original.
5. Manter os limites de arquivo, a verificação efetiva de bytes e o armazenamento imutável da 029. Se o contexto mudar após o upload, conservar a reserva e o objeto privado pendentes; não retornar sucesso, sobrescrever o arquivo, criar outro UUID automaticamente ou limpar a intenção.
6. Reutilizar permissões EM atuais de projeto/documentos e gestão, SSO/MFA e autoria RM. A regra exata de quem pode substituir, os nomes de operações e os DTOs finais devem constar do contrato técnico antes da implementação.
7. Validar banco isolado e disputas reais entre conclusões, projeto encerrado, escritores externos e retentativas; comprovar preservação de todas as tabelas e Storage no ensaio/aplicação. Não criar documentos artificiais em produção.

O versionamento privado com retenção é uma decisão explícita do EM. O Live observado edita a linha e oferece exclusão; não foi demonstrado um sistema de versões equivalente. A entrega não declara paridade visual/funcional completa dos módulos documentais, geração, compilação ou Templates Word.

Evidências locais ignoradas: `.tmp/discovery-attachment-versions/` contém as leituras dos nós citados; `copTw.json` é uma projeção sem o boilerplate visual de layout/estilo, preservando propriedades semânticas, condições e filhos. Os demais arquivos guardam os nós específicos lidos. Não incluem dados de registros de clientes, arquivos baixados ou credenciais. Fontes locais: migrações 029/030, os leitores e adaptadores acima, `desktop/src/server/bridge/mapping.ts` e os tipos de sincronização mobile.

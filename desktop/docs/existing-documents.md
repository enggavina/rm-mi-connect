# EM — Leitura dos documentos existentes

Verificação e importação de 28/10/2026 a partir do Bubble `rmmi`, versão live. A origem foi usada somente para leitura, incluindo o download dos PDFs existentes pelo serviço legado. Não houve geração/compilação de PDF, envio de e-mail ou alteração no Bubble. Os arquivos foram copiados apenas para o novo Supabase autorizado.

No recorte dos 177 projetos instalados, os 15 registros `Docs` têm uma URL de arquivo. Os 14 registros `Documentos` são diferentes: 11 contêm nome/chave textual no campo `PDF`, e três não têm referência de arquivo na origem. Os 11 arquivos existentes foram importados com sucesso para `rm-documentos/legacy/<documento_uuid>.pdf`. A chave original fica em `rm_documentos.s3_key` e `arquivo_url` contém a referência canônica `/storage/v1/object/authenticated/rm-documentos/legacy/<documento_uuid>.pdf`, com a base HTTPS do projeto Supabase. Os três registros sem arquivo mantêm URL nula.

## Caminhos comprovados no aplicativo

- `Documentos`: na página `projeto_rm` (`cnpGY`), o evento de download `cohee` chama `cohfC`, ação `Download_pdf_n8n_s3` (`coZeU/cohec`). Ela faz POST com corpo `{"pdf":"<pdflink>"}` e recebe `Parent group's Documentos's PDF` como parâmetro. A resposta é um arquivo, baixado pela ação seguinte `cohfH`. A configuração do API Connector não expõe bucket, base S3 ou URL direta do objeto. A reprodução desse download retornou HTTP 200 e `application/pdf`, permitindo copiar os arquivos existentes sem gerar relatórios.
- `Docs`: a ação `copTY` da página `projeto` (`coiiy`) baixa diretamente `Docs.Arquivo.URL`. A navegação `copdk` abre `visualizar-documento` (`copdm`), cujo iframe `copeo` usa o mesmo campo de arquivo. Esse visualizador não resolve as chaves de `Documentos.PDF`.
- Gerador Render legado: a ação `coizs` abre `/download-pdf/Relatório_Técnico_Final-{ProjetoRM.Nome}.pdf` no serviço de PDF. O código local desse serviço implementa a leitura de arquivos do próprio diretório de saída; não contém resolução de objetos S3. Esse caminho pertence a outro fluxo e não demonstra uma correspondência com as chaves importadas.

Não houve correspondência exata das 11 chaves com nome, URL ou nome de arquivo dos anexos `Docs` do mesmo projeto. Nenhuma corresponde à fórmula de nome do download Render observada no workflow. Portanto, não foi feito backfill de URL com base em semelhança ou caminhos presumidos.

## Importação e validação

O script [import_existing_document_pdfs.ts](../../rm-mobile-supabase/scripts/import_existing_document_pdfs.ts) exige o destino autorizado e os 11 registros observados; sem `--apply`, apenas verifica os candidatos. Com `--apply`, usa lease da ponte, verifica a ausência de alterações pendentes, baixa somente arquivos existentes, exige conteúdo PDF, valida cabeçalho `%PDF-`, terminador `%%EOF` e tamanho de até 50 MB. O primeiro arquivo de prova foi reutilizado, sem segundo download. Os nomes no Storage usam UUID, sem incorporar nomes/chaves da origem. O script não sobrescreve objetos: se já houver arquivo, compara SHA-256 antes de vincular. A atualização do registro exige que a chave original continue igual e a URL permaneça nula.

Resultado: **11 importados, zero falhas**. O replay terminou com **11 inalterados, zero novos downloads e zero falhas**. Os arquivos reais permanecem no bucket privado. O ETL normal preserva a referência privada em mudanças de metadados com a mesma chave; uma nova chave não reutiliza o PDF anterior.

Na verificação real com a conta inicial, o download por URL assinada retornou HTTP 200 e 167.843 bytes, com SHA-256 idêntico ao arquivo original. Um cliente anônimo não obteve assinatura e a URL pública retornou HTTP 400. A outbox permaneceu sem eventos pendentes. Nenhuma chave de serviço, credencial ou URL assinada foi incluída nos registros versionados.

Auditoria local ignorada pelo Git: `.tmp/etl/*-existing-pdfs/summary.json`, cache de arquivos em `.tmp/existing-document-pdfs/` e verificação de acesso em `.tmp/download-probe/storage-verification.json`. Os três documentos sem arquivo ainda dependem de uma referência na origem; seus metadados continuam disponíveis.

```powershell
node desktop/node_modules/tsx/dist/cli.mjs rm-mobile-supabase/scripts/import_existing_document_pdfs.ts
node desktop/node_modules/tsx/dist/cli.mjs rm-mobile-supabase/scripts/import_existing_document_pdfs.ts --apply
```

Consulte [operações e reconciliação da carga](../../rm-mobile-supabase/PROJECT_OPERATIONS.md) para os volumes e limites completos.

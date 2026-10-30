# Discovery funcional — comentários e anexos do projeto

Data: 30/10/2026. Origem: Bubble `rmmi`, versão **Live**, página `projeto` (`coiiy`), comparada ao portal EM e às migrações **001–028**. A página `project_rm` (`cnpGY`) e a visualização `visualizar-documento` (`copdm`) foram consultadas para distinguir anexos gerais de relatórios gerados.

A inspeção foi somente leitura de metadata. Nenhum workflow foi executado, arquivo enviado ou excluído, dado de negócio alterado ou mensagem enviada. Não houve mudança de branch, escrita no Bubble ou chamada de APIs de geração. A configuração lida não comprova a execução com dados reais.

## Cobertura e evidências

Foram lidos os eventos e ações de criação de comentário, criação/edição/exclusão de Docs, exclusão de comentário, abertura e download de anexo; os inputs correspondentes; os tipos `custom.comentarios` e `custom.docs`, suas regras de privacidade e o option set `option.statusdocs`. A árvore de `projeto` tem 74 eventos; esse inventário não significa que todos os seus fluxos foram analisados nesta entrega. As leituras desta seção são específicas do dossiê.

| Fluxo | IDs lidos | Efeito observado |
| --- | --- | --- |
| Abrir e criar comentário | `coqwd/coqwk`, `coqwp/coqww`, `coqvK`, `coqwA`, `coqwF`, `coqxZ` | Abre popup; cria `Comentarios` com usuário atual, texto, projeto da página e célula destinatária; mostra sucesso e fecha. |
| Consultar comentários | `comiK`, `comii`, `comij` | Busca por projeto, texto, período de criação, autor e célula, ignorando filtros vazios; ordena por criação decrescente. Exibe matrícula/nome, célula, texto e data/hora. |
| Editar/excluir comentário | `comij/comlu`, `comnJ/comnP`, `commg` | Texto tem auto-binding. Exclusão remove fisicamente `Comentarios` depois de confirmação. |
| Criar anexo | `copWo/copWv`, `copTw`, `copVc` | Quando o Docs do popup está vazio, cria um `Docs` do projeto atual com nome, arquivo, vencimento, status e observação. |
| Editar anexo | `copZM/copZc` | Quando já há Docs no popup, altera arquivo, nome, vencimento, status e observação na mesma linha. Não foi encontrada versionagem nesse comando. |
| Excluir anexo | `copYW/copYi/copYg`, `copXf` | Apaga o arquivo pela URL e depois o registro `Docs`; mostra sucesso e fecha o popup. |
| Listar, baixar e visualizar | `copRZ`, `copRa`, `copaS`, `copTR/copTY`, `copdU/copdk`, `copdm` | Lista Docs do projeto por criação decrescente. Download usa URL e nome do registro; visualizar envia esse Docs a outra página em nova aba. |

Evidências brutas locais ignoradas: `.tmp/discovery-dossier/`. Os IDs são referências de metadata do Bubble; não identificam registros de negócio criados para teste.

## Contrato observado no Bubble

O comentário usa `cadastrado_por1_user = Current User`, `evento_text`, `projeto_custom_projeto_rm = Current page's ProjetoRM` e `celula_custom_celulas`. O dropdown `coqxZ` é **obrigatório** e consulta somente células presentes nas alocações daquele projeto. O texto `coqwA` não apresenta configuração explícita de limite no nó lido; isso não equivale a uma autorização para texto ilimitado no EM. Os eventos inspecionados de criação não possuem ação de e-mail ou notificação externa.

A privacidade de `custom.comentarios` permite consulta geral e auto-binding de `evento_text` quando o evento não está vazio. O input de consulta `comlu` usa esse binding. Essa configuração não oferece o protocolo de autoria, conflito, confirmação e auditoria exigido pelo EM e não deve ser copiada como autorização de edição livre.

O tipo `custom.docs` contém `arquivo_file`, `nome_text`, `observacao_text`, `data_vencimento_date`, `projeto_rm_custom_projeto_rm` e `status_option_statusdocs`, além dos campos nativos de criador e datas. **StatusDocs é um estado documental, não uma categoria**: as opções atuais são exatamente **Vencido** (`vencido`) e **No prazo** (`no_prazo`). Não foi demonstrada derivação automática desse status pelo vencimento. O nome (`copUU`) e o status (`copcM`) são obrigatórios; o vencimento (`copcF`) e a observação (`copck`) não apresentam obrigatoriedade nos nós lidos.

O `FileUploader` `copUO` tem `private=false`. O tipo Docs permite leitura, pesquisa e acesso aos anexos na regra geral. Não há limite de tamanho nem allowlist de tipo explícitos nas propriedades desse uploader lidas aqui. A entrega de anexos privados no EM é uma diferença deliberada em relação ao legado, não uma reprodução de sua exposição de arquivos.

`Docs` é distinto de `Documentos`. A página `project_rm` possui fluxos de upload S3, geração individual e compilação associados a `Documentos`; eles não serão apresentados como implementados pelo simples envio de um anexo geral. Não foram chamados esses serviços durante a revisão.

## Entidades e consumidores existentes no EM

| Peça existente | Contrato verificado | Consequência para o incremento |
| --- | --- | --- |
| `rm_comentarios`, migração 002 | Projeto obrigatório; célula opcional; autor por identidade RM; texto, datas e origem. | Reutilizar a entidade. Não criar uma segunda lista de comentários nem reatribuir autores históricos. |
| `rm_private.add_cell_comment_v1`, migrações 011/028 | Comentário operacional da célula, limite de 10.000 caracteres, delegação/idempotência mobile e guarda contra alocação retirada. | Preservar o fluxo e a fila offline. Um comentário web destinado a célula deve respeitar a mesma alocação exata e suas proteções. |
| `rm_docs`, migrações 005 e 011 | `nome`, `descricao`, `arquivo_url`, projeto, criador e datas; **011 já acrescentou `status` e `data_vencimento`**, além de campos de origem. | Não duplicar colunas por olhar somente a 005. `descricao` representa `Observacao`; o bridge já mapeia status e vencimento. |
| `rm_docs.visivel_cliente` | Campo aproximado da 005; não existe no tipo Docs Live lido. | Não tratar esse campo como prova de compartilhamento com cliente nem introduzir essa opção por inferência. |
| `rm_documentos` | Registros de relatórios/templates/compilação, consultados separadamente. | Preservar; anexar arquivo geral não gera relatório nem compilação. |
| Bucket `rm-documentos`, 004/011 | Privado; teto de 50 MiB; PDF, JPEG e PNG. Leitura a RM autenticado; inserção/atualização com primeiro segmento igual ao Auth UID. | Reutilizar bucket e política compatível com mobile. Não tornar público nem alterar objetos antigos. |
| Política de documentos mobile | Limite do aplicativo de **20 MiB**, PDF/JPEG/PNG; armazenamento e cópia local para abertura offline. | Preferir o mesmo limite no novo upload web, preservando o teto do bucket. Não exige novo APK apenas para esses metadados existentes. |
| `desktop/src/server/web/data.ts` | Histórico já consulta comentários por projeto e autor; anexos consultados com projeção sem status/vencimento/criador. | Expandir a projeção mínima necessária, com as capacidades correspondentes; manter histórico anterior. |
| `/api/web/documents/[id]` e `policy.ts` | Revalida usuário/`em.documents.read`; consulta arquivo cadastrado; assina por 60 segundos somente caminho autenticado do bucket desse Supabase, ou redireciona para CDN Bubble permitida. Nunca busca URL arbitrária no servidor. | Reutilizar abertura/download por ID e autorização atual. Novos uploads não devem aceitar URL arbitrária ou expor chave de serviço. |
| `mobile/app/documentos.tsx` | Já apresenta `status`, `data_vencimento` e descrição se presentes no catálogo; consulta anexos e relatórios por projeto. | Manter pull/RLS e formato compatíveis. Arquivo privado continua sujeito ao mecanismo atual de assinatura/cache. |

Fontes locais principais: `rm-mobile-supabase/migrations/002_rm_core_tables.sql`, `011_rm_project_operations.sql`, `028_rm_web_cell_availability.sql`; `desktop/src/server/bridge/mapping.ts`; `desktop/src/server/web/data.ts`, `policy.ts`; `desktop/src/app/api/web/documents/[id]/route.ts`; `mobile/src/core/document-policy.ts` e `mobile/src/ui/documents.tsx`.

## Direção recomendada e limites

1. **Criar comentários e anexos reutilizando as entidades existentes.** O contrato do incremento deve declarar se aceita comentário geral do projeto sem célula. Isso seria uma extensão deliberada do fluxo Live que exige destinatário, preservando a distinção entre comentário do projeto e operação de uma célula.
2. **Usar autoria e autorização atuais no servidor.** Reutilizar `em.projects.manage`, leituras de projeto/histórico/documentos conforme a operação e perfis RM de escrita, com SSO/MFA, protocolo idempotente e versões. Não conceder administração global nem alterar identidades mobile. As capacidades finais devem ser fixadas no contrato técnico antes da implementação.
3. **Publicar somente arquivo privado verificado.** Limitar tipo/tamanho, verificar o conteúdo recebido, construir o caminho no servidor e vincular ao projeto/ator/protocolo. A retentativa deve conservar a intenção e distinguir arquivo recebido de metadados confirmados. Não aceitar sucesso fictício, arquivo substituído por outro, URL livre ou chave de serviço no navegador.
4. **Preservar a compatibilidade.** Comentários destinados à célula não podem contornar a guarda 028. Leituras históricas continuam disponíveis; arquivos/rascunhos/filas mobile não serão apagados como efeito da criação web. O worker de saída permanece desativado.
5. **Manter explícito o que não está entregue.** Edição por auto-binding, exclusão física de comentário/anexo, substituição destrutiva de arquivo, compartilhamento com cliente, QR, geração/compilação Word/PDF e migração de arquivos antigos precisam de contratos próprios. Não copiar os deletes do Bubble nesta criação inicial.

Essas recomendações são propostas de implementação a partir das evidências acima. O contrato técnico final, os testes de persistência/autorização/concorrência e as provas de publicação pertencem à entrega 029; este discovery, isoladamente, não declara essas funcionalidades prontas.

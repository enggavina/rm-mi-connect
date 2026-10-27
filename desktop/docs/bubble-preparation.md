# Preparação do Bubble para coexistência — 27/10/2026

Aplicativo `rmmi`, branch **Main (`test`)**. Nenhum deploy em `live` foi realizado. O plano consultado permite zero branches adicionais; as mudanças aditivas foram feitas em Main.

Savepoint anterior à alteração: `1793131868209`.

| Tipo | ID do tipo no editor | Campo visível/Data API | Chave interna | Tipo |
| --- | --- | --- | --- | --- |
| ProjetoRM | `custom.projeto_rm` | `supabase_id` | `supabase_id_text` | texto simples |
| Equipamento | `custom.dados_equipamento` | `supabase_id` | `supabase_id_text` | texto simples |
| Fotos RM | `custom.foto_rm` | `supabase_id` | `supabase_id_text` | texto simples |
| Registro_Formulario | `custom.registro_formulario1` | `supabase_id` | `supabase_id_text` | texto simples |
| Respostas | `custom.respostas2` | `supabase_id` | `supabase_id_text` | texto simples |

As cinco criações e as cinco verificações de consistência dos tipos retornaram lista de issues vazia e verificação completa. As regras de privacidade, workflows, conteúdo dos registros e telas existentes não foram alterados. Nenhum campo existente representava um UUID externo recuperável para essas entidades; `Respostas.ID_Registro` guarda o ID do formulário pai e o `Slug` embutido tem finalidade de roteamento.

O worker usa `BUBBLE_SYNC_ID_FIELD=supabase_id`, nome de exibição usado pela Data API. `supabase_id_text` é a chave do editor para expressões/workflows, não a configuração padrão do cliente Data API. O tipo é confirmado pelo retorno das operações do editor. Buscas somente-leitura com constraint `supabase_id equals 00000000-0000-4000-8000-000000000000` foram aceitas nos cinco tipos, todas com zero resultados. Não houve POST de registro de teste nem envio de dados operacionais.

`Celula_Projeto` e `Aprovaçao_etapas` não receberam campos novos: na Fase 1 o mobile apenas altera registros existentes com `bubble_id` conhecido. Se uma fase posterior começar a criá-los a partir do Supabase, adicionar o mesmo identificador antes de permitir novos POSTs.

Os nomes de campo das aprovações foram conferidos no editor: `celula_origem`, `celula_destino`, `status`, `status_cel_proj`, `Vinculo_entre_celulas`, `Aprovado por`, `data_aprovação`. O mapeamento local foi ajustado. Também foram conferidos `Numero fotos` e `Celula_tipo_equipamento` nos vínculos de engenharia.

Antes de apontar a ponte ao endpoint de produção, revisar e publicar o schema Main no Bubble, habilitar a Data API dos tipos auxiliares e conferir seus nomes públicos. O conector não expõe uma operação para habilitar Data API por tipo. A obtenção do link de preview foi recusada pelo conector com `Insufficient scope`; não foi construído um link manual.

## Leitura live e limitação de aprovações

Os catálogos e dados operacionais foram lidos de `https://rm.miconnect.app.br/api/1.1` usando a credencial já existente no projeto de integração autorizado. A credencial foi preservada somente no `.env` local ignorado pelo Git. Nenhuma escrita na API live foi executada.

Em 27/10/2026, os endpoints `aprovacao_etapas`, `aprovador_projeto` e o nome exato do display `Aprovaçao_etapas` em minúsculas/URL-encoded retornaram 404. O metadata `meta/swagger.json` também retornou 404. O conector, usando o tipo interno `aprovador_projeto` no ambiente live, conseguiu ler 2.298 registros; esse snapshot ficou em arquivo local ignorado. Ele permite uma carga inicial filtrada por projetos ativos, mas não comprova que o tipo está exposto para polling pela Data API pública. É necessário habilitar ou confirmar o nome desse endpoint antes de considerar as aprovações sincronizadas continuamente.

Editor confirmado pelo conector: [aplicativo rmmi](https://bubble.io/page?id=rmmi).

# Fotos do projeto e Report Building

Discovery em 29/10/2026, somente leitura. Bubble Live, código do EM e consumidor local `E:/MI Electric/APIs/rm_report` foram comparados; nenhuma geração, chamada de webhook ou alteração no consumidor foi executada.

## Contrato confirmado

| Origem | Comportamento | Destino existente |
| --- | --- | --- |
| `projeto/coiiy`, galeria `coiln`, checkbox `coimF` | Mostra seleção de cada foto. Eventos `cojAb/cojAg` executam `cojAc/cojAh`, gravando `sele__o_relatorio_boolean=true/false`. | `rm_fotos.selecao_relatorio`, boolean não nulo criado na 002; mapeamento já existe em `desktop/src/server/bridge/mapping.ts`. |
| Galeria `coiln` | Alterna obrigatórias/complementares; ordena selecionadas primeiro. | Categoria, número e seleção já existem; a galeria web ainda não oferece seleção. |
| Fotos RM | Projeto, célula/alocação, título, descrição/legenda, tag, número e arquivos. | `rm_fotos`; não criar tabela de seleções nem segunda lista de IDs. |
| Consumidor `src/rm_report_builder/app.py` | Recebe `tables.photos` ou `photos` do fornecedor; percorre a lista na ordem recebida, sem filtrar seleção localmente. | A futura fonte Supabase deve filtrar `selecao_relatorio=true`, excluir lixeira/modelos e conservar a ordem explícita. |
| Consumidor de fotos | Aceita URL ou objeto com `url`/`base64`; utiliza `caption`, `tag`, `ordem`. | `foto_url`, legenda/descrição/título, `tag`, `numero`. Não criar campo de ordem por analogia. |

O consumidor atual chama webhooks n8n, enviando `project_id`, `report_type`, `include_photos` e, para fotos, `projeto`. Não consome diretamente o EM e não troca de fonte em consequência de salvar a seleção. O contrato futuro deve entregar `tables.photos` na ordem `numero`, com desempate estável por ID, utilizando os campos existentes. A ordenação por seleção do Bubble é apresentação da galeria, não uma ordenação persistente do relatório.

## Implementação inicial e decisões

1. Acrescentar ação individual à galeria existente e exibir o estado persistido também para usuários somente de consulta. Reutilizar a ampliação de foto existente.
2. A seleção é metadado do dossiê do projeto: exigir `em.projects.manage`, `em.projects.read` e `em.photos.read`, além do perfil operacional de escrita. Não criar capacidade paralela de geração de relatórios. Esta decisão não autoriza gerar ou baixar relatórios indiscriminadamente.
3. Usar o gateway transacional existente com recibo, autoria, permit SSO e versão exata da foto. Payload: `projeto_id`, `foto_id`, `expected_updated_at`, `selected`. A retentativa conserva o UUID e o conteúdo. Conflito exige releitura.
4. Validar vínculo com o projeto, existência de arquivo, ausência de lixeira/modelo. Alterar somente seleção e metadados de auditoria; preservar número, tag, arquivos, título, categoria e vínculos. No-op não altera a versão.
5. Não restringir a seleção a projetos abertos: o workflow original não contém essa condição e relatórios históricos precisam continuar selecionáveis.
6. Não apresentar geração como concluída: as APIs atuais de geração/compilação continuam pendentes e o aplicativo Report Building permanece na fonte legada até integração explícita e validada.

## Limites e inconsistências

- Blueprint antigo referencia um ID de API ausente no Live; não foi tratado como integração ativa.
- Fotos armazenadas apenas na lista `fotos_arquivos_urls`, sem `foto_url`, exigem revisão da migração/renderização antes de fazer parte desta galeria. A seleção inicial não inventa uma URL nem duplica o registro.
- A ponte de saída continua desativada. Uma futura reimportação deve reconciliar autoridade dos campos de seleção; isso integra o pacote de coexistência, não autoriza sobrescrever decisões locais silenciosamente.
- A compatibilidade do formato foi conferida no código; não equivale a homologação de um relatório real ou troca do fornecedor do consumidor.

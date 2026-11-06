# Exclusão de Tipos de Equipamento e Títulos de Fotos

Revisão incremental de 06/11/2026, conforme o novo pedido do anexo `654ae4b0-f257-4dc7-8a23-54de0cda492d`. Nenhum cadastro real foi removido nesta validação.

## Implementação encontrada

As duas exclusões já estavam implementadas, mas só eram apresentadas dentro de **Editar**. Não foi criada outra API ou regra de exclusão.

| Cadastro | Fluxo reutilizado | Proteção no servidor |
| --- | --- | --- |
| Tipos de Equipamento | `CatalogEditor` → `deleteCatalog` → `delete_catalog` (017) | Administrador RM, capacidade `em.catalogs.manage`, MFA, permit SSO, versão exata e replay idempotente. Toda FK para o tipo bloqueia, inclusive FKs privadas e regras de CASCADE/SET NULL. Arrays de UUID e referências textuais/nomes anteriores também bloqueiam. |
| Títulos de Fotos | `EngineeringTitleEditor` → `deletePhotoTitle` → `delete_photo_title` (023) | Administrador RM, capacidade `em.engineering.manage`, MFA, permit SSO, versão exata e replay. A FK `rm_fotos.cadastro_foto_id` é `ON DELETE RESTRICT`; modelos, fotos de projeto, fotos capturadas e registros retirados continuam impedindo exclusão. |

O roteiro próprio 037 acrescentou uma FK privada para o tipo de origem em `rm_private.project_route_instances`. A varredura da 017 já a encontra; não foi necessário alterar a migração aplicada. Definições e fotos compartilhadas não são apagadas para liberar uma exclusão.

O modelo atual de documentos/relatórios não possui outro vínculo relacional direto com Títulos de Fotos. Fotos vinculadas ao título permanecem protegidas, inclusive quando usadas em relatórios. O snapshot de título já copiado não é apagado nem reescrito para permitir excluir o cadastro.

## Ajuste da interface

**Excluir** passa a ficar visível na lista de Tipos de Equipamento e na lista de Títulos de Fotos para os administradores autorizados. O link abre a confirmação existente no mesmo editor, por `acao=excluir`; o GET não executa uma mutação.

A confirmação identifica o registro, exige digitar exatamente o nome/título exibido e oferece **Manter cadastro/título**. O envio só ocorre após a confirmação. Resposta de rede incerta mantém o protocolo, a versão e o payload originais; outro salvamento fica bloqueado até confirmar o resultado. A recusa de exclusão de um tipo em uso explica que equipamentos, projetos, roteiros ou outros vínculos foram preservados.

Não há migração 041 para esses ajustes, novas capacidades, alterações de cascade, grants ou conexões externas.

## Validação

Quinze testes direcionados de políticas, ações e modelos de catálogo/Engenharia passaram. A suíte SQL de catálogos foi ampliada para confirmar exclusão de tipo sem uso e recusa de tipo usado apenas por FK privada, incluindo CASCADE, além de equipamento canônico de projeto cuja coluna direta de tipo está vazia. As suítes SQL de catálogos e exclusão de títulos passaram sobre 001–033/035–038 em PostgreSQL isolado.

O ensaio Chromium com React e CSS reais verificou ações visíveis apenas para administrador, nome obrigatório, navegação GET sem envio, consulta com parâmetro inválido, recusa por uso, retentativa congelada e ausência de botão de exclusão em cadastro novo. Capturas 1240 px e 390 px foram inspecionadas, sem erros de página ou transbordamento horizontal. Ações e dados eram locais simulados.

Arquivos principais: páginas de lista/edição de Cadastros e Títulos de Fotos, `catalog-editor.tsx`, `engineering-title-editor.tsx`, `catalog-mutations.ts`, `icons.tsx`, `catalog-actions.test.ts` e `web_catalogs.sql`.

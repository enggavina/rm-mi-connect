# Prova inicial do gerador de relatórios PDF

O objetivo é oferecer no portal EM um editor visual sem código, modelos versionados atribuíveis a tipos de equipamento e geração de PDF usando os dados autorizados do projeto. Os modelos de relatório são distintos dos modelos de formulário. Os documentos emitidos precisam preservar a versão do modelo, os dados utilizados, a autoria e o resultado em armazenamento privado.

## Ensaio isolado

Em 05/11/2026, uma instalação npm normal em diretório temporário utilizou pdfme 6.2.8 com dados sintéticos. A geração produziu seis páginas A4 contendo 40 linhas identificadas e imagens; `pdfinfo`, `pdfimages` e `pdftotext` confirmaram as páginas, imagens e identificadores. A mesma imagem pequena foi repetida: o resultado não demonstra desempenho com fotos reais.

O teste de integração do Designer no Next.js não foi concluído. A instalação colocou React 19.1.10 no projeto de teste e React 19.3.1 aninhado em `@pdfme/ui`: montagem, hidratação e comportamento visual precisam ser verificados antes de acrescentar qualquer dependência ao portal.

O pdfme documenta a paginação dinâmica para uma página base em branco. Cabeçalhos/rodapés repetidos requerem configuração específica, e imagens de tabela precisam ser validadas antes da geração. Usar as mesmas fontes locais no editor e no worker; imagens inacessíveis não podem ser omitidas silenciosamente. Fontes: [tabelas](https://pdfme.com/docs/tables), [cabeçalhos e rodapés](https://pdfme.com/docs/headers-and-footers) e [fontes](https://pdfme.com/docs/custom-fonts).

## Próximas verificações

- Validar o Designer com Next/React do EM, sem atualizar dependências de produção para contornar incompatibilidades não compreendidas.
- Ensaiar templates representativos com dados sintéticos, tabelas longas, imagens distintas e ausentes, múltiplas páginas e prévia comparada ao PDF final.
- Mapear respostas por versão de formulário, preservando respostas históricas sem vínculo atual e a seleção e ordem de fotos do projeto.
- Definir permissões, atribuição por tipo de equipamento, snapshots, fila durável, retentativas e armazenamento privado antes da emissão real.
- Instruções de trabalho são destinadas ao preenchimento: sua presença no PDF deve ser uma decisão explícita de produto.

Nenhum pacote foi instalado no produto, nenhum dado de produção foi usado na prova e a geração no portal continua pendente.

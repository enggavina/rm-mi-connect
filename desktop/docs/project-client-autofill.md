# Identificação de cliente no cadastro do projeto

O cadastro existente usa `rm_projetos.cliente_id → rm_clientes.id`. `ProjectEditor` recebe os clientes por `createWebData().editorChoices('project')`, com a mesma sessão/RLS e as permissões `em.portal.read` e `em.projects.manage`. A consulta traz somente `id,nome`, em páginas de 500; um catálogo que exceda o limite atual da tela causa erro explícito, sem usar uma lista truncada para sugerir clientes.

## Comportamento

- No cadastro de **novo projeto**, após 400 ms sem alteração no nome, o sistema procura um nome completo de cliente cadastrado dentro do texto.
- A comparação usa NFKD, remove marcas de acento, converte para minúsculas e separa pontuação/símbolos/espaços em tokens. O nome original do cliente não é modificado.
- O índice de tokens é construído uma vez por catálogo já carregado. Não há consulta a cada tecla nem nova API de busca.
- A correspondência respeita os limites das palavras: `ABC` não corresponde a `XABC` ou `ABCDEF`.
- Um cliente mais específico só é escolhido quando seu nome contém todos os outros nomes correspondentes e seu registro é único. `ABC ENGENHARIA` prevalece sobre `ABC`. Clientes independentes citados no mesmo texto, ou registros diferentes com o mesmo nome normalizado mais específico, exigem seleção manual.
- O preenchimento automático ocorre somente se o cliente estiver vazio e o usuário ainda não tiver alterado a seleção. Qualquer seleção manual, inclusive limpar o campo, cancela a ajuda automática pelo restante desse cadastro.
- Um cliente já preenchido permanece preservado se o nome do projeto for alterado. A edição de projetos existentes mantém a seleção manual original e não aplica preenchimento automático.
- O campo continua enviando o UUID real em `cliente_id` pelo mesmo formulário e pelas mesmas operações de salvamento existentes. A mensagem discreta pede conferência antes de salvar.
- Timers são cancelados ao alterar o texto, sair do componente ou iniciar/proteger o salvamento; um timer pendente também verifica a intervenção manual antes de preencher.

## Estruturas e validação

Não há migração, nova tabela, campo, índice, foreign key ou permissão. A associação continua sendo validada pelo fluxo existente de criação do projeto/equipamento.

Arquivos principais:

- `src/components/web/project-client-match.ts`: índice e decisão de correspondência.
- `src/components/web/project-client-fields.tsx`: campos e debounce.
- `src/components/web/editor.tsx`: integração exclusivamente nos campos Nome/Cliente.
- `tests/project-client-match.test.ts`: oito cenários, incluindo 20.000 clientes em memória.
- `tests/web-data.test.ts`: catálogo autorizado com mais de 1.000 registros e falha explícita no limite de consulta.

A validação específica executou 34 testes de correspondência/dados com sucesso. A interface React/CSS foi verificada em Chromium nos tamanhos 1240 e 390, com 11 cenários: vínculo UUID no FormData, debounce, intervenção manual antes do timer, limpeza manual, seleção inicial, edição existente, cancelamento de resultado antigo, ambiguidades, bloqueio durante salvamento e ausência de novas requisições de negócio. Esses cenários usam fixtures locais e não criam registros em produção. Os testes gerais, typecheck, build e publicação são registrados no relatório da entrega conjunta.

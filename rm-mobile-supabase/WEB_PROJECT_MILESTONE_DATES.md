# Prazos de peritagem e reparo

O cadastro e a edição de projetos oferecem quatro datas opcionais: início e fim de peritagem e início e fim de reparo. A seção Informações apresenta os mesmos valores como dias de calendário em português do Brasil.

A migração aditiva 035 acrescenta quatro colunas `DATE` a `rm_projetos` e duas restrições independentes: quando as duas datas de uma etapa existem, o início não pode ser posterior ao fim. Não é imposta ordem entre peritagem e reparo. As regras valem também para chamadas diretas ao gateway, que aceita datas ISO ou nulas e preserva os campos omitidos por clientes anteriores.

A gravação usa `save_project` e mantém autorização, versão exata, idempotência e tratamento de conflito existentes. Ao editar, o portal envia somente alterações; limpar um campo envia `null`. A publicação deve instalar a 035 antes do novo portal, pois as consultas do portal selecionam as novas colunas. As migrações anteriores, respostas, filas e dados offline permanecem intactos.

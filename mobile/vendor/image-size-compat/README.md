# Adaptador image-size para Metro do Expo SDK 54

Metro 0.83 chama `image-size` com um caminho de arquivo em `getAssetData` e com bytes em `getAssetSize`. A versão 2.0.4 corrigida aceita somente bytes. Este adaptador mantém o parser 2.0.4 sem alterações e converte o caminho local em bytes antes da chamada.

A substituição em `package.json` é deliberadamente local e cobre somente a API síncrona usada pelo Metro. Os testes de dependências exercitam os dois caminhos reais. Remover o adaptador ao migrar para uma versão do Metro que adote a API v2.

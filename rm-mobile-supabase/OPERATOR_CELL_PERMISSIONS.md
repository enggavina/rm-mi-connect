# Células permitidas por operador

A migration `010` usa `rm_tablet_celula_users.identidade_id` como identidade do operador autorizado para `celula_id`. `usuario_id` identifica a conta de login compartilhada, e `tablet_id` identifica o equipamento. Identificar ou trocar o operador não modifica esses vínculos. O gateway valida a célula usando o operador delegado; somente o perfil `administrador` do próprio operador mantém acesso administrativo a todas as células.

A regra foi verificada diretamente no cadastro Bubble live `settings_rm` (`cnwZQ`):

- O popup `coZnf` recebe o usuário cujo cadastro está sendo editado. A lista `cofzH` busca `Tablet_Celula_User` por `identidade_user = usuário do popup`.
- A ação de cadastro `cogSo` grava `Identidade = Parent group's User`, a célula e o tablet selecionados. `Usuario` vem de um dropdown restrito a contas do tipo `Login`.
- A ação de edição `cogAa` altera célula/tablet/conta de login e preserva a identidade do operador.
- O workflow de identificação `coZyv` registra o evento e navega com a identidade validada. O `UPDATE` que substituía as identidades nos vínculos do tablet veio do SQL original `003`; não reproduzia esse cadastro.

A leitura dos dados encontrou 181 vínculos iguais entre Bubble e Supabase. Desses, 175 têm conta de login, correspondendo a 19 contas com perfil administrador; 133 têm identidade, correspondendo a 62 operadores. A migration e a verificação real de login preservaram os 181 registros integralmente. Nenhum vínculo foi criado para `DIGITAL`: seu acesso administrativo decorre do perfil já provisionado.

O contexto retornado pelo login contém `cell_access_policy_version=2`. O aplicativo exige uma nova identificação online para caches anteriores. A RPC `rm_operator_context_v1(p_operator_token)` atualiza células e perfil durante a sincronização, verifica token/dispositivo/validade e não renova o prazo do turno nem a validade offline. Uma remoção de permissão aparece na próxima sincronização; o servidor verifica o cadastro atual em cada nova mutação. Rascunhos e operações pendentes mantêm sua autoria.

Os testes PostgreSQL cobrem operadores distintos no mesmo tablet administrador, bloqueio de formulário/foto em célula de outro operador, preservação do cadastro durante o login, contexto ligado ao dispositivo correto, remoção de vínculo e acesso do operador administrador. A verificação real confirmou login/contexto da conta inicial, 29 células por seu perfil administrativo, acesso anônimo negado e os 181 vínculos intactos. Nenhum dado operacional fictício foi inserido.

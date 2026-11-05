# Projeto e equipamento — incremento 036

O cadastro web oferece abas Projeto e Equipamento. O novo comando `save_project_with_equipment` cria ou edita o projeto e seu equipamento na mesma transação, com IDs próprios, autorização `em.projects.manage`, validação SSO e protocolo idempotente. As informações técnicas são gravadas em `rm_equipamentos`; o campo histórico `rm_projetos.descricao_equipamento` não é reescrito por essa operação.

Para um projeto existente, o snapshot 031 e suas versões precisam corresponder. Um vínculo bidirecional inequívoco é editado no mesmo equipamento; vínculo ausente permite criar um equipamento; vínculo ambíguo ou snapshot indisponível mantém a edição técnica bloqueada. Dados gerais do projeto continuam editáveis pelo comando antigo quando a confirmação do equipamento não é possível. A edição técnica usa a auditoria e a guarda contra sobrescrita offline/ETL da 031, com confirmação e revisão antes/depois.

O comando mantém a ordem de locks de projeto e equipamento da 031. As operações internas de projeto e equipamento usam seus recibos e regras existentes; esses recibos, a mutação composta e seu recibo externo fazem parte da mesma transação. Replay externo não repete a operação. A ponte de saída permanece desativada; eventual coexistência futura precisa reconciliar os eventos e recibos internos.

O tipo que determina a cópia de modelos continua no relacionamento de planejamento existente. A seleção foi retirada do CRUD do projeto e é oferecida antes da primeira alocação no Cronograma e na aba Células e planejamento, reutilizando `save_project`, sua permissão e sua trava de tipo após qualquer alocação. Sem tipo, os modelos não são copiados automaticamente.

Na exibição, a descrição histórica do projeto tem prioridade; quando ausente, a descrição do equipamento é usada somente com vínculo consistente nos dois sentidos. O aplicativo sincroniza o equipamento existente e aplica a mesma verificação; registros legados ambíguos não são escolhidos arbitrariamente. A busca web continua usando os campos históricos do projeto: ainda não pesquisa a descrição armazenada apenas no equipamento novo. A migração não faz backfill nem altera dados antigos para contornar essa limitação.

Os roteiros de Engenharia mantêm listas de aprovadores por identidade vinculada à célula de origem e à célula de retorno; a interface oferece seleção e remoção sem criar vínculos de usuário. Fotos, formulários e regras operacionais continuam associados à alocação de projeto e célula existente.

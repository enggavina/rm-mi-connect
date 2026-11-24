# EM Operacional Web

O acesso em `/operacao` atende o operador no navegador pelo mesmo serviço Railway do EM. Este incremento oferece login e consulta de células, projetos e modelos de formulário vinculados à célula do projeto.

## Identidade e oficina

O navegador envia as credenciais ao servidor HTTPS do EM. Supabase Auth valida a conta do dispositivo, e o RPC de identificação do aplicativo valida a matrícula e a palavra-chave. O servidor guarda a sessão num cookie próprio, cifrado e `HttpOnly`, limitado ao caminho `/operacao`. A sessão dura até uma hora e também respeita as expirações do JWT e da delegação. Dispositivos com MFA configurado precisam satisfazer esse controle para entrar.

A cada consulta, o servidor revalida a sessão e confirma a oficina em Acessos pelo par verificado. Na Central, cadastrar o **UUID do usuário em Supabase Auth** como identidade `device` e o **UUID do operador em `rm_users`** como identidade `operator`. Ambos devem estar vinculados à mesma oficina ativa. O EM usa o vínculo confirmado e orienta a regularização quando ele está ausente, revogado ou divergente.

A migração `061` acrescenta consultas exclusivas do servidor. O banco revalida a sessão, a delegação e o contexto recente do Acessos. A lista combina as células permitidas ao operador com a propriedade da oficina. A lista de projetos também exige projeto da mesma oficina, alocação visível e ativa e projeto até a entrega. O detalhe verifica se o projeto pertence à célula autorizada e mostra apenas os modelos ativos da própria oficina. Registros alheios e sem classificação são omitidos. A paginação ocorre no banco. As respostas e páginas de acesso usam `no-store`.

## Validação e piloto

A suíte `rm-mobile-supabase/tests/online_operation_reads.sql` usa BMA, BRJ e BBH em banco descartável. Verifica acessos recíprocos, vínculos de célula, registros não classificados, contexto inválido, revogação e execução restrita ao servidor. As três oficinas têm identidades e registros próprios no teste. A conferência de Acessos em produção encontrou BMA ativa, BRJ e BBH inativas e zero vínculos de dispositivo ou operador. Para homologar com uma conta real, cadastrar o par autorizado na BMA e verificar acesso, células e projetos com essa conta.

Os próximos incrementos são os registros online de formulários e fotos e a homologação com a equipe. Cada envio terá confirmação do servidor e revalidação de autoria, oficina, célula e projeto. A expansão para BRJ e BBH depende dos vínculos reais, da classificação do acervo e do aceite multi-oficina, incluindo o isolamento dos acessos legados que usam essas identidades. [Publicação e evidências](web-platform.md#em-operacional-web--entrada-e-consultas-por-oficina).

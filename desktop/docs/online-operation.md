# EM Operacional Web

O acesso em `/operacao` atende o operador no navegador pelo mesmo serviço Railway do EM. O operador pode entrar, consultar suas células, abrir os projetos liberados e preencher e enviar os formulários compatíveis vinculados a cada alocação da sua oficina ativa.

## Identidade e oficina

O login segue as duas telas do Android. Primeiro, entre com o e-mail e a senha do dispositivo. Depois, informe a matrícula e a palavra-chave do operador. Supabase Auth valida o dispositivo, e o RPC de identificação do aplicativo valida o operador. Entre as telas, o navegador guarda um cookie cifrado, `HttpOnly`, limitado a `/operacao/login` e válido por até cinco minutos. **Trocar conta do dispositivo** cancela essa etapa e volta à primeira tela.

A identificação do operador e a confirmação da oficina em Acessos dão início à sessão da operação. O cookie da sessão é cifrado, `HttpOnly` e limitado a `/operacao`. A sessão dura até uma hora e respeita as expirações do JWT e da delegação. Dispositivos com MFA configurado precisam satisfazer esse controle para entrar.

A cada consulta, o servidor revalida a sessão e confirma a oficina em Acessos pelo par verificado. Na Central, cadastrar o **UUID do usuário em Supabase Auth** como identidade `device` e o **UUID do operador em `rm_users`** como identidade `operator`. Ambos devem estar vinculados à mesma oficina ativa. O EM usa o vínculo confirmado e orienta a regularização quando ele está ausente, revogado ou divergente.

A migração `061` acrescenta consultas exclusivas do servidor. O banco revalida a sessão, a delegação e o contexto recente do Acessos. A lista combina as células permitidas ao operador com a propriedade da oficina. A lista de projetos também exige projeto da mesma oficina, alocação visível e ativa e projeto até a entrega. O detalhe verifica se o projeto pertence à célula autorizada e mostra apenas os modelos ativos da própria oficina. Registros alheios e sem classificação são omitidos. A paginação ocorre no banco. As respostas e páginas de acesso usam `no-store`.

## Validação pela conta Microsoft

A conta corporativa `softdev05@mielectric.com.br` pode entrar pelo [portal do EM](https://em-web-production.up.railway.app/login) e abrir **Validar EM Operacional** no painel. A página de validação usa a mesma interface de consulta da operação. O servidor verifica a sessão Microsoft, o vínculo corporativo e as capacidades do EM. A Central confirma a BMA em cada consulta, e a migração `062` aplica as permissões de célula já cadastradas para o operador associado. As consultas usam uma confirmação do servidor de uso único com os filtros exatos.

Esse acesso cobre a consulta de células, projetos ativos e modelos de formulário na BMA. A remoção de permissões de célula, a revogação do vínculo ou a mudança de oficina em Acessos altera o resultado das próximas consultas. A entrada por senha do dispositivo continua atendendo o fluxo do operador.

## Consulta de formulários

Dentro do projeto, selecione **Abrir formulário** para ver as seções, as perguntas obrigatórias e as opções cadastradas. Os subtítulos começam recolhidos. O botão **Voltar ao projeto** leva à mesma alocação.

A migração `063` acrescenta a consulta do modelo pelo caminho completo de célula, projeto e formulário nos dois acessos. O servidor consulta a oficina e o banco exige que o modelo esteja ativo e vinculado à alocação acessível. A confirmação de uso único da validação Microsoft inclui o identificador do formulário. A validação Microsoft é somente leitura.

## Envio de inspeção por oficina

A migração `064` habilita texto, número, data, intervalo de datas e escolha simples ou múltipla para o operador identificado. Um modelo com uma pergunta obrigatória de outro tipo é preenchido no aplicativo. Abra as seções do formulário, preencha as respostas e toque em **Enviar formulário**. Após confirmação, o navegador exibe o código do registro, disponível em **Formulários e aprovações** com status **Em análise**.

A migração `126` aplica esse envio a todas as oficinas ativas em Acessos. A confirmação vincula oficina, dispositivo, operador, célula, projeto e versão do modelo. Um reenvio exato conserva o código e a autoria originais. A equipe da mesma oficina encontra o registro na fila de revisão do portal.

Se a confirmação atrasar ou a conexão cair, mantenha a página aberta e selecione **Tentar o mesmo envio**. O navegador repete os valores e o protocolo da primeira tentativa. O servidor vincula o protocolo ao operador, dispositivo, oficina e versão do formulário. O banco revalida o acesso, usa a mesma transação de inspeção do aplicativo, devolve o comprovante anterior em retentativas idênticas e mantém intactos os rascunhos legados. O envio web aparece no histórico do projeto com autoria operacional e origem web.

## Validação e piloto

A suíte `rm-mobile-supabase/tests/online_operation_reads.sql` usa BMA, BRJ e BBH em banco descartável. Verifica acessos recíprocos, vínculos de célula, registros não classificados, contexto inválido, revogação e execução restrita ao servidor. As três oficinas têm identidades e registros próprios no teste. Em 26/11/2026, Acessos confirmou em produção o vínculo da conta Digital e do operador Igor Nascimento, matrícula `05`, à BMA ativa. Para homologar o envio, configurar a palavra-chave do operador, abrir um modelo compatível e conferir o registro em Formulários e aprovações.

A matriz de quatro oficinas conferiu o envio e a fila de revisão antes e depois da restauração. A liberação real de BRJ ou BBH ainda depende dos vínculos e do aceite do piloto. [Procedimento de ativação](sso.md#ativação-suspensão-e-retomada-de-uma-oficina).

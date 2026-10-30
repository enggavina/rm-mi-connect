# Correção de comentários do projeto — incremento 032

**Status:** 032 aplicada no Supabase `oficina-em-mi-off` e consumidor publicado em [EM web](https://em-web-production.up.railway.app), commit `18fd297af07fc4df185703ad7c4b1f7be8f07ea7`, Railway `054e3163-0298-445c-adc9-8ddf0263a23f` com `SUCCESS`. [CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41123841265).

A migração 032 acrescenta edição somente do texto de comentários manuais comprovados, mantendo o ID, projeto, célula, autor original, data de criação e metadados de origem. Não altera as migrações 001–031, não cria histórico retroativo e não exclui comentários.

## Origem e autorização

A origem manual exige evidência exata em um recibo privado concluído: operação web add_project_comment ou RPC mobile rm_add_cell_comment_v1. São conferidos comentário/projeto/célula/alocação, autor e texto original; no web, também data de criação e protocolo. O primeiro before_record auditado conserva o texto original depois da primeira correção. O texto atual deve corresponder ao último after_record auditado. Comparações de instantes não dependem da representação do fuso horário.

Registros sem origem manual comprovada, incluindo legados importados sem recibo, QR e observações vinculadas a rm_web_stage_decisions ficam somente para consulta. Metadados de importação não substituem nem invalidam, isoladamente, uma prova manual válida. Não são usados prefixos de texto, nomes ou permissões do Bubble para inferir autoria ou editabilidade. A alocação original precisa existir e estar ativa; oculta continua elegível, retirada não. Projeto com entrega real, cancelado ou finalizando para faturar permanece em consulta.

RM administrador pode corrigir comentários elegíveis de outros autores; padrão corrige somente os próprios; auditor consulta. A camada web exige em.portal.read, em.projects.read, em.history.read e em.projects.manage para escrever. SSO/MFA e papel/identidade atuais continuam obrigatórios. Autoria original e papel atual são verificados antes de recuperar um recibo de correção concluído; encerramento posterior não invalida o replay exato autenticado.

## Leitura e histórico

rm_web_project_comment_snapshot_v1(p_project_id uuid,p_comment_id uuid,p_history_page integer default 1) é STABLE SECURITY INVOKER e aplica as RLS existentes. Somente authenticated executa; exige identidade RM interna ativa. Projeto/comentário inexistente ou outro projeto retorna null. Página deve estar entre 1 e 100000 e é ajustada à última página real.

O snapshot contém project (id, numero, updated_at, status_pcp, data_real_de_entrega, closed), comment (id, projeto_id, celula_id, cadastrado_por_id, evento, created_at, updated_at, author_name, author_registration, cell_name), allocation (id, updated_at, retirada) ou null, can_edit, reason, context_version e history.

can_edit considera elegibilidade e autoria/perfil RM; a interface ainda combina a capacidade corporativa vigente. O hash inclui versões e contexto canônico do projeto/comentário/alocação, prova de origem e revisão. Uma consulta que falha ou retorna outro contexto não deve ser apresentada como histórico vazio.

O helper privado project_comment_revision_context_v1 usa SECURITY DEFINER com gate interno e projeto/comentário exatos para consultar os recibos e o diário; retorna apenas a projeção de negócio. history possui items, total, page e page_size=25. Cada item possui id, revision, evento_anterior, evento_novo, motivo, editor_id, editor_name, editor_registration e created_at, em revisão decrescente. Não expõe Auth IDs, protocolos privados, parâmetros de recibos, transaction_id ou linhas completas privadas.

## Comando

Operação edit_project_comment no envelope rm_web_mutate_v1:

~~~json
{
  "projeto_id": "uuid",
  "comentario_id": "uuid",
  "expected_project_updated_at": "ISO timestamp exato",
  "expected_comment_updated_at": "ISO timestamp exato",
  "expected_context_version": "SHA256 hexadecimal",
  "evento": "Texto corrigido",
  "motivo": "Motivo da correção",
  "confirm_change": true
}
~~~

O objeto é estrito. Texto e motivo são aparados nas extremidades e exigem conteúdo não vazio, inclusive após espaços/tabulações/quebras de linha; limites de 10000 e 2000 caracteres. Identidade, destinatário, datas e origem não podem ser enviados como alterações. A confirmação deve ser explícita.

Locks: protocolo, advisory project11, projeto, alocação original, comentário. Versões/hash, autoria e origem são reavaliados dentro da transação. Conflito PT409 exige nova leitura antes de preparar outra intenção. Resposta incerta mantém UUID, texto, motivo, versões e confirmação congelados para repetir o mesmo protocolo.

Resultado mínimo: operation, id do comentário, projeto_id, updated_at, idempotent_replay e record com projeto_id, comentario_id, project_updated_at, changed, revision e context_version posterior. Não devolve o diário privado. Sem diferença real, há recibo sem UPDATE, sem mudança de timestamp e sem evento de histórico.

## Preservação e coexistência

rm_private.project_comment_revisions registra revisão sequencial, autor RM/Auth da correção, protocolo, motivo e linhas completas antes/depois. Nenhum cliente, inclusive service_role, tem acesso direto ao diário. Os DTOs do histórico identificam o editor da correção separadamente do autor original.

Após a primeira correção, o trigger rm_guard_comment_revisions protege texto, ID, projeto, célula, autor e data original, além de recusar exclusão. Somente o delta exato autorizado pelo diário da mesma transação pode alterar o texto. Não existe flag de cliente ou GUC de desvio. Atualização externa somente de metadados de integração continua possível e não altera o texto corrigido.

Os escritores mobile existentes acrescentam comentários e seus recibos concluídos permanecem intocados. Repetir o recibo original de criação retorna o resultado original e não regrava o texto atual. A ordem de locks e a guarda 028 preservam tentativas pendentes e seu UUID/corpo/ator; uma inserção mobile concorrente pode aguardar ou receber conflito recuperável, sem descarte automático da intenção. Arquivos, respostas e filas offline permanecem preservados.

A correção não acrescenta eventos à outbox nem ativa a ponte Bubble. Eventos pendentes anteriores não são reescritos. Exportação/coexistência exige entrega própria; SYNC_OUTBOX_ENABLED=false permanece.

## Validação e publicação

web_project_comment_revisions_upgrade.sql aplica o código exato sobre 031 com chamadas previamente aquecidas, comparando 72 tabelas RM anteriores e duas tabelas Storage, políticas e funções/grants não alterados. A instalação cria somente o diário vazio, sem dados artificiais ou backfill.

web_project_comment_revisions.sql cobre origem web/mobile, perfis/autoria, histórico com mais de uma página, fuso horário, versão/hash, confirmações, motivos, no-op, recibos e proteção contra escrita externa, além de 10 disputas reais entre duas conexões. O executor usa um PostgreSQL local descartável. A 032 foi aplicada somente no Supabase `oficina-em-mi-off`, seguida do consumidor EM no Railway após as validações. Migrações **001–032 aplicadas e imutáveis**; nenhum dado de negócio artificial foi gerado em produção.

## Incremento 032 publicado: evidências e limites

**Projetos → abrir projeto → Histórico → Consultar comentário → Corrigir comentário** oferece correção do texto com motivo obrigatório, comparação antes/depois, confirmação e histórico de versões por 25. O autor original e a criação permanecem identificados; cada correção mostra seu editor, data, motivo e textos anterior/novo. O fluxo substitui o auto-binding do Live por uma alteração explícita e auditada no servidor.

A correção exige origem manual comprovada por recibo de criação web ou mobile e vínculo exato ao projeto/célula. Administrador pode corrigir registros elegíveis; perfil padrão somente os próprios. Origem não comprovada, incluindo legados importados sem recibo manual, registros automáticos e observações vinculadas a decisões permanecem em consulta. O número de recibos existentes não equivale ao número de comentários elegíveis: cada registro é revalidado individualmente. Projetos encerrados e alocações retiradas ficam em consulta; ocultar a célula conserva sua atividade. A operação reutiliza em.projects.manage e as leituras de portal/projeto/histórico, sem ampliar concessões.

A escrita altera somente o texto e sua data de atualização, preservando ID, projeto, célula, autor/criação e metadados de origem. Versões exatas e hash contextual protegem disputas; motivo e antes/depois são registrados em diário privado. Uma projeção autorizada fornece o histórico sem Auth UID, recibos ou linhas privadas completas. Recibos de criação e correção continuam preservados. Retentativa mantém ator, UUID e conteúdo; autorização/SSO/MFA atuais precedem o replay. No-op não altera timestamp nem inventa revisão. A guarda impede sobrescrita do texto corrigido, alteração de identidade ou exclusão por escritores externos; mudanças apenas de metadados de sincronização continuam sob seu contrato anterior. Dados, filas e trabalhos offline existentes foram preservados.

**362 testes desktop, 87 mobile no CI, 21 suítes PostgreSQL e 10 novas disputas reais aprovados**, além de tipos, build e dois smokes. Concorrência cobriu dois editores, retry exato, encerramento, gravação externa, contexto de alocação e intenção mobile original. Navegador: **15 cenários**, build `v61rsVgNbvFRSYgW4cCI-`, DOM real com HTTP/autenticação simulados, sem banco ou SSO reais; zero erros/origens externas e capturas desktop/390 px inspecionadas. Auditoria de **73 JavaScripts** sem os dez segredos locais conhecidos. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41123841265).

Ensaio com rollback e aplicação preservaram **72 tabelas RM anteriores e dois snapshots de Storage**, todas as colunas/contagens/hashes e **74 definições de colunas/ACLs**, **96 OIDs/ACLs de funções anteriores** — 94 definições idênticas e duas alterações exatas revisadas — e **46 políticas RM/Storage**. As exceções são renomear o core anterior sem mudar corpo/OID/ACL e acrescentar a operação ao mapa SSO. Após instalar: **73 tabelas RM/privadas, 57 públicas com RLS, 100 funções RM e novo diário de correções vazio**; 178 projetos, 94 comentários, 778 registros e 61.803 respostas preservados, 102 usuários, outbox 4, 4 recibos web e 3 buckets/13 objetos. Os diários anteriores foram comparados sem presumir que estivessem vazios; SSO, administradores e guardas anteriores permanecem.

Fonte SQL local, índice, commit e fonte aplicada conferidos com SHA256 `3c1f4b6ab8d8dce4bee843c7fd52c9212fe83f36e8675ea1a3b7f68bf5e37fcb`. Migrações **001–032 aplicadas e imutáveis**; a instalação não inventa origem manual, corrige registros ou cria histórico retroativo.

Consumidor **`18fd297af07fc4df185703ad7c4b1f7be8f07ea7`**, Railway **`054e3163-0298-445c-adc9-8ddf0263a23f`** com `SUCCESS`; [EM web](https://em-web-production.up.railway.app) com health 200. QA público: **64 negações em 32 URLs e seis verificações de API, total de 70 bloqueios**, com anônimo/cookie forjado e POST de origem indevida. Login Microsoft-only, CSRF, callback estrito, cookie opaco HttpOnly/Secure e início PKCE até Microsoft conferidos; somente o fluxo próprio de QA foi cancelado, sem autenticação humana automatizada ou CRUD artificial em produção.

Nenhum novo APK, identidade/grant na Central, escrita no Bubble ou ativação da ponte; SYNC_OUTBOX_ENABLED=false permanece. Esta entrega preserva o fluxo mobile de criação e seus recibos, sem alterar intenções offline, arquivos ou respostas. Exclusão de comentários, alteração de destinatário e substituição/exclusão de anexos permanecem pendentes de contrato próprio.

**Próxima prioridade:** substituição de anexos privados com versionamento, preservando os arquivos e as versões anteriores. Exclusão de arquivos não faz parte do próximo incremento. Word/relatórios, QR, cadastros complementares, capacidade/calendários/lotes, comercial, laboratório e coexistência continuam no plano; a paridade global permanece em andamento.

[Discovery Live](../docs/discovery_rmmi_correcao_comentarios.md). Provas locais ignoradas: `comment-revisions-032-{rehearse,apply}-proof.json`, `comment-revisions-postflight.json`, `comment-revisions-ci-proof.json`, `comment-revisions-deployment.json`, `comment-revisions-public-qa.json`, `public-sso-qa.json`, `project-comment-qa-summary.json`, `comment-revisions-browser-secret-audit.json` e logs `comment-revisions-{desktop-tests,build,smoke,sso-smoke,final-full}.log`.

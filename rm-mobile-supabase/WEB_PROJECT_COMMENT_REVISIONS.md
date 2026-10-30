# Correção de comentários do projeto — incremento 032

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

web_project_comment_revisions.sql cobre origem web/mobile, perfis/autoria, histórico com mais de uma página, fuso horário, versão/hash, confirmações, motivos, no-op, recibos e proteção contra escrita externa, além de 10 disputas reais entre duas conexões. O executor usa um PostgreSQL local descartável. Produção deve receber somente 032 no Supabase oficina-em-mi-off e o consumidor EM no Railway após todas as validações; não gerar dados de negócio artificiais em produção.

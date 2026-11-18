# Modelos e rascunhos por oficina — O10 / 058

Escopo: as quatro ações web `create_form_template`, `save_form_template`, `publish_form_template` e `delete_form_template`. Criar inclui modelo novo, cópia independente e nova versão da mesma família. O construtor continua restrito ao administrador RM com `em.form_templates.manage`, sessão SSO Microsoft e MFA atual. Nenhuma capacidade ou administração global é concedida. O mobile mantém login/senha.

Cada ação consulta o contexto v2 atual de Acessos no servidor, depois das verificações corporativas e locais. A oficina não é campo do navegador ou escolha no login. A sessão corporativa permanece no WeakMap do servidor introduzido na O09; não é serializada no contexto nem persistida no banco. A nova RPC de confirmação é exclusiva do servidor e reutiliza a validação estrita da 057, alterando somente nome, operações, capacidade e tabela de permissões. A RPC anterior não muda.

A confirmação dura no máximo quinze segundos, vinculada ao protocolo, sessão, operação, hash do corpo e oficina. Renovar o mesmo protocolo não troca sua oficina. O SSO público existente consome sua autorização normal e chama o novo auxiliar privado; seu OID, proprietário, ACL e regras anteriores permanecem. A O09 continua protegendo clientes/tipos por meio do despacho encadeado.

## Propriedade e operação

Famílias e rascunhos ganham propriedade privada durável. Modelos publicados usam a propriedade de catálogo da 056. Criação grava rascunho/família e classificação na mesma transação; publicação grava definição, perguntas, opções, versão, recibo e classificação também atomicamente. A cópia exige fonte da mesma oficina e cria uma família independente. Nova versão mantém a família existente; registrar a primeira versão de um modelo legado classifica a nova família somente depois de comprovar a oficina da fonte. Não há inferência de oficina pelo autor ou e-mail.

Salvar, publicar e excluir exige a oficina comprovada do alvo e de suas referências necessárias. Fontes desconhecidas, de outra oficina ou encerradas são recusadas. Rascunhos existentes sem origem permanecem pendentes de revisão. Exclusão conserva a origem de rascunho, família e publicação e proíbe reutilização dos UUIDs encerrados. O replay de exclusão concluída precisa de autorização nova e da mesma oficina. Retentativas mantêm corpo/protocolo; não criam cópias adicionais.

As guardas conferem vínculos entre família, rascunho, fonte e publicação, incluindo relações indiretas família → fonte/publicação por rascunho ainda não classificado. Classificação posterior também confere as referências existentes em ambas as direções. Objetos desconhecidos não recebem oficina padrão. Perguntas/opções novas pertencem à publicação gerada pelo core; suas regras anteriores de exclusividade e imutabilidade continuam. O editor não altera metadados herdados de células/equipes. O isolamento completo de todas essas referências operacionais permanece uma etapa separada.

Locks de origem são compartilhados para conferência e exclusivos para classificação, ciclo de vida e alvo de escrita; disputas recusam PT409 sem descartar trabalho. Snapshots antigos não podem validar uma associação após uma classificação concorrente. A função verifica validade novamente depois do core e da classificação: expiração durante uma espera reverte toda a operação, inclusive recibo e família. Logout remove as confirmações junto com a sessão. Os testes usam conexões independentes reais.

Continuam valendo a validação de conteúdo, versão otimista, limite do formulário, autoria, IDs novos de perguntas/opções e mapeamentos, modelos publicados imutáveis, checagem de dependências e preservação de respostas/históricos. A propriedade privada não cria FKs para os registros públicos de negócio e não impede a exclusão autorizada de uma publicação sem uso.

## Lote inicial e publicação

O usuário confirmou que o acervo existente pertence à BMA. A conferência de produção encontrou 3 famílias, 3 rascunhos (2 novos e 1 cópia), 1 versão e 59 modelos. Os rascunhos foram criados em 29/10, 04/11 e 16/11/2026, antes da adoção inicial BMA; nenhum modelo publicado está sem classificação. A função técnica de adoção exige o recibo/declaração original, a adoção dos catálogos, contagens revisadas e datas anteriores ao recibo inicial. Registra apenas propriedade e recibo privados, com executor real do banco; não altera conteúdos, datas, IDs ou perguntas. Criação posterior ao lote exige revisão explícita. Repetição exata reconhece o mesmo lote e nunca classifica objetos posteriores.

A 058 instala a exigência desativada. O novo BFF já emite confirmação e classifica suas operações nessa fase. Após schema, adoção revisada, CI/regressão, deploy confirmado e verificações públicas, o proprietário técnico ativa a exigência com commit e deployment reais. A ativação exige SSO e O09 ativos, adoção dos rascunhos, nenhuma família/rascunho/modelo atual sem origem e relações conhecidas consistentes. Depois dela, uma autorização SSO v1 isolada não permite essas quatro ações. Reversão da interface precisa de consumidor compatível; preservar recibos, origem e encerramentos, sem exclusão de dados ou oficina padrão como contorno.

## Limites e validação

Este pacote é de escrita. Não ativa filtros de leitura, busca, contagens, exportações, arquivos/Storage ou filas/cache offline. BRJ/BBH permanecem inativas até isolamento e homologação completos. Não entrega uma CLI, editor novo de relatórios ou novo APK. Homologação humana de uma operação real é separada dos testes técnicos; não criar dados artificiais em produção.

- `npm run typecheck`, `npm test`, build e smokes em `desktop`; CI também valida mobile e o contrato QR.
- `powershell -NoProfile -File rm-mobile-supabase/tests/run-local-tests.ps1 -WorkshopInventory`.
- `python rm-mobile-supabase/scripts/test_template_workshops_local.py`: PostgreSQL descartável, jornada de escrita, adoção, referências indiretas/inversas, exclusões, replay, expiração, MFA, logout, três disputas reais e dez alterações indevidas recusadas pelo envelope.
- `prepare_template_workshops_release.py`: gerador offline com hashes obrigatórios e rollback padrão; preserva dados anteriores/Auth/Storage, OIDs/owners/ACLs, corpos das funções salvo o despacho exato, papéis, índices, políticas e histórico. Não editar migrações aplicadas.

Publicada e ativada em 18/11/2026: migração 058, consumidor `cba3507d7e928da5e7fb7838d4c846f4794b3631`, Railway `3c1094ec-c989-4038-bbcb-562a2a7dd019` com SUCCESS. [Resultado, evidências e próximas prioridades](../desktop/docs/web-platform.md). Os 5/5 marcos técnicos não equivalem a isolamento completo ou homologação humana da operação.

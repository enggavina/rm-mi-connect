# Cadastros básicos web — contrato 017

Estado: **017 aplicada e pacote publicado em 29/10/2026**, no projeto autorizado `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`). O histórico remoto contém 001–017 e `require_sso=true` foi preservado. Commit `38f482e`, deploy `7a225233-f6d4-4f3e-814e-b9497f3dbc42`; `em.catalogs.manage` foi registrada na Central e concedida somente ao administrador autorizado depois da publicação compatível. A 017 preserva os payloads e regras das três operações anteriores e o gateway mobile. O SQL não cadastra usuários, não concede capabilities e não gera outbox, email ou chamadas Bubble; a concessão central foi uma operação administrativa separada.

O único ponto de entrada continua `rm_web_mutate_v1(p_client_submission_id uuid, p_operation text, p_payload jsonb)`. As duas novas operações exigem conta RM ativa com perfil **administrador**. Na configuração ativa de produção (`require_sso=true`), também exigem sessão/permit SSO vinculados à identidade e capability exata **`em.catalogs.manage`**. TOTP verificado continua exigindo AAL2, inclusive no replay. Nenhum `actor_id` é aceito do cliente. Os novos helpers e os dois cores privados não podem ser executados por `anon`, `authenticated` ou `service_role`; este último continua emitindo somente o permit por RPC de infraestrutura. A aplicação usa a chave pública com o JWT EM para a mutação.

A exceção de staging herdada da 016 permanece: se `require_sso=false`, uma conta RM **sem vínculo SSO cadastrado** pode usar o caminho legado, ainda sujeito a perfil/MFA/validações, sem permit nem capability central. Uma conta com vínculo desativado não cai nesse caminho. A 017 não altera essa regra e não desativa a exigência em produção. O teste local de upgrade usa deliberadamente o caminho legado para aquecer o plano anterior, enquanto a suíte funcional de cadastros executa com `require_sso=true`.

`save_catalog`:

```json
{
  "kind": "clients",
  "id": "uuid-gerado-pelo-cliente",
  "expected_updated_at": null,
  "changes": {"nome": "Cliente", "codigo": null, "descricao": null}
}
```

`delete_catalog`:

```json
{
  "kind": "clients",
  "id": "uuid-do-cadastro",
  "expected_updated_at": "timestamp-exato-retornado-pelo-banco"
}
```

| `kind` | Tabela | Campos permitidos em `changes` |
|---|---|---|
| `clients` | `rm_clientes` | `nome`: texto obrigatório até 200; `codigo`: texto/null até 80; `descricao`: texto/null até 4000 |
| `cells` | `rm_celulas` | `nome`: texto obrigatório até 200; `codigo`: texto/null até 80; `indice`, `ordem`: número inteiro/null entre 0 e 1.000.000 |
| `types` | `rm_tipos_equipamento` | `nome`: texto obrigatório até 200; `sigla`: texto/null até 30 |

Os textos perdem espaços externos, inclusive tabs/quebras de linha; texto opcional vazio vira null. `changes` precisa conter pelo menos um campo. Na criação, exige `nome` e versão null. Na edição, campos omitidos permanecem iguais e exige a versão atual. Omitir ou enviar null em `indice`/`ordem` de **nova célula** atribui `max+1` a cada campo, começando em 1; numa célula existente, null é preservado como null. Valores fracionários, strings numéricas e booleanos são rejeitados. Metadados Bubble/Auth/sync/auditoria e campos fora da lista são rejeitados.

Nova criação e renomeação não podem colidir com o nome de outro registro do mesmo catálogo, ignorando maiúsculas e diferenças de espaços. A comparação não remove acentos. Duplicados legados não são alterados pela migration; alterações que mantêm seu nome são permitidas. Os nomes normalizados de cada edição são verificáveis pelos recibos anteriores.

Ao renomear uma célula, os vínculos textuais de `rm_cadastro_fotos.celula_nome` são atualizados atomicamente quando o nome antigo identifica uma única célula. A normalização também identifica variações de caixa/espaços. Havendo nomes antigos ambíguos com fotos, a renomeação é negada. Um nome de destino que já tenha fotos sem associação inequívoca também é negado, inclusive na criação. O recibo privado guarda `_related_changes` com tabela/ID e snapshots antes/depois de cada título afetado. Não reescreve os exports históricos de projetos.

A exclusão é física **somente quando não há uso**. Verifica todas as FKs ao catálogo descobertas no schema, inclusive `CASCADE` e `SET NULL`; nenhuma referência é apagada ou zerada. Uma FK composta futura bloqueia a exclusão conservadoramente. Verifica também todos os campos `uuid[]` das tabelas públicas `rm_*`, os títulos de fotos, exports de cliente/tipo, classificação de precificação/templates e dependências textuais das células. Referências textuais consideram o nome atual, nomes anteriores registrados pela API, UUID e ID Bubble. `depende_de` usa uma comparação conservadora por ocorrência do nome. Nenhum registro operacional deve ser excluído para QA.

O retorno mantém `{operation,id,projeto_id:null,updated_at,record,idempotent_replay}`. Em exclusões, `record` e `updated_at` são o snapshot da linha excluída. O UUID de envio é global: um replay exato devolve o primeiro resultado, mesmo após exclusão, mas exige **novo permit SSO**. Outro ator/operação/payload não pode reutilizar o UUID. Falhas desfazem a mutação, a auditoria e o consumo do permit.

| Código | Significado |
|---|---|
| `42501` | Perfil/atividade/MFA/SSO não permite a operação |
| `22023` | Payload/campo/limite/tipo inválido |
| `PT409` | Versão desatualizada/linha removida ou catálogo ocupado por outra transação |
| `23505` | Nome normalizado em uso ou UUID de envio reutilizado com conteúdo diferente |
| `23503` | Referência existente impede excluir ou vínculo textual impede renomear |

As edições de catálogo são serializadas por lock transacional, e verificações de nome/ordenação usam lock de tabela. Somente exclusões bloqueiam tabelas de referências sem FK; renomeação de célula bloqueia o catálogo de fotos. Os locks de tabela usam `NOWAIT`: se houver escritor concorrente, a ação retorna PT409 e preserva os dados. O wrapper/core têm `lock_timeout` de 10 segundos, restaurado automaticamente na saída da função. Deadlocks e outros erros de banco não são convertidos nem ignorados. Isso favorece a operação mobile, mas uma exclusão pode precisar ser repetida num período de menor atividade. Não substitui a proteção transacional da ponte, que permanece desativada.

A migration recompila o wrapper público existente para invalidar planos de sessões que já chamaram a 016. O harness faz esse upgrade na mesma conexão previamente aquecida, depois executa seis suítes transacionais. A suíte de cadastros cobre os três tipos, patch/normalização/limites, duplicados legados, versões, criação/edição/exclusão e replay, FKs `CASCADE`/`SET NULL` futuras, listas, nomes anteriores, rename de fotos/auditoria, ambiguidades, SSO/capability/MFA/perfis e ausência de eventos. Usa `dblink` **apenas no banco local descartável** para provar que um escritor concorrente de referências impede a exclusão com PT409.

Aplicação remota: antes da transação, foram conferidos nome/organização/ref do projeto, histórico exato 001–016, ACLs e SSO obrigatório. A comparação transacional de 53 snapshots (52 tabelas públicas RM e os recibos web privados) confirmou conteúdo e contagens preservados, incluindo os 102 usuários RM. A outbox permaneceu com quatro registros preexistentes e os recibos web com zero: nenhuma mutação de negócio foi criada pela migration. O pós-teste confirmou histórico 001–017, cinco operações no permit, mapeamento exato das duas novas operações à capability, dois vínculos SSO ativos, helpers privados, gateway restrito a `authenticated`, escrita direta dos catálogos negada e credenciais privadas. Não foi criado ou excluído registro de teste em produção. A prova local sem segredos está em `.tmp/catalogs-017-application-proof.json`.

Implantação concluída: primeiro o consumidor compatível com 12 capacidades foi publicado e as quatro rotas novas foram conferidas publicamente com autenticação obrigatória. Depois, cadastro técnico e concessão de `em.catalogs.manage` foram aplicados em uma transação central separada: `mgavina` ficou com 12 capacidades e `softdev05` manteve oito de consulta. Outras aplicações/contas/concessões foram preservadas; replay idempotente e destinatário de consulta foram testados com rollback. O [CI](https://github.com/enggavina/rm-mi-connect/actions/runs/40833409039), 110 testes desktop, tipos, build e dois smokes passaram. Dez cenários de interface usaram o standalone real com HTTP/dados simulados e rede externa bloqueada; a persistência foi exercitada em PostgreSQL isolado, sem criar/excluir cadastros reais em produção.

O controle de referências cobre os dados carregados no EM. Não altera nem exclui cadastros no Bubble. A importação histórica é parcial e a ponte permanece desligada; uma futura importação pode restaurar um cadastro ainda existente na origem. A resolução da coexistência está no pacote próprio do [plano de paridade](../plano_paridade_rmmi_web.md).

# Edição técnica do equipamento do projeto — incremento 031

**Status:** 031 aplicada no Supabase `oficina-em-mi-off` e consumidor publicado em [EM web](https://em-web-production.up.railway.app), commit `f587c390f16f7f91559bdca0660218078f8aad09`, Railway `76171a0e-bf22-4d91-838d-77e196587f3c` com `SUCCESS`. [CI aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41111508903).

O portal edita somente o equipamento já vinculado de forma inequívoca ao projeto. A migração `031_rm_web_project_equipment.sql` acrescenta uma leitura contextual, um comando ao envelope web existente e um diário privado. Não cria equipamentos, não corrige vínculos e não altera formulários, respostas, fotos, arquivos, delegações ou o contrato da fila offline.

## Vínculo e leitura

`rm_web_project_equipment_snapshot_v1(p_project_id uuid)` é `STABLE SECURITY INVOKER`, aplica as RLS existentes e exige usuário RM interno ativo (`administrador`, `padr_o` ou `auditor`). A camada web exige sessão válida e `em.portal.read`/`em.projects.read`. Projeto inexistente retorna `null`.

```ts
type EquipmentSnapshot = {
  project: {
    id: string; numero: string | null; status_pcp: string | null;
    data_real_de_entrega: string | null; equipamento_id: string | null;
    tipo_equipamento_id: string | null; updated_at: string; closed: boolean;
  };
  equipment: EquipmentRecord | null;
  binding_state: "linked" | "missing" | "unlinked" | "conflicting" | "orphaned" | "shared";
  can_edit: boolean;
  reason: string | null;
  context_version: string; // SHA-256 hexadecimal
  type_mismatch: boolean;
};
```

`linked` exige `projeto.equipamento_id = equipamento.id`, `equipamento.projeto_id = projeto.id`, o mesmo equipamento na busca por proprietário e exatamente um projeto apontando para ele. `missing` significa ausência de ponteiro e de equipamento proprietário; `unlinked`, equipamento proprietário sem ponteiro; `orphaned`, ponteiro sem proprietário válido; `conflicting`, ponteiro/proprietário divergentes; `shared`, mais de um projeto referenciando o equipamento canônico. Estados diferentes de `linked` retornam `equipment: null` e motivo genérico, sem revelar o conteúdo de outro equipamento.

`can_edit` representa elegibilidade operacional (`linked` e projeto aberto); a interface também exige a capacidade de gestão vigente. Não concede permissão de escrita a leitores. Projetos com entrega real, cancelados ou finalizando para faturar ficam em consulta. A divergência histórica entre os dois `tipo_equipamento_id` aparece como `type_mismatch`; não impede edição técnica nem sincroniza esses IDs.

O DTO do equipamento contém apenas `id`, `projeto_id`, `tipo_equipamento_id`, `updated_at`, os campos abaixo, `placa_motor`, `fp`, `fs` e `numero_cabos`. Não expõe identificadores de importação nem os três antigos sinalizadores de recebimento. `fp`/`fs` são strings decimais produzidas por `numeric::text`, nunca convertidas em `Number` JavaScript. Valores legados permanecem legíveis, inclusive textos longos ou com aparência de JSON e números fora da validação de novas alterações.

## Comando e validação

Operação `save_project_equipment` no `rm_web_mutate_v1` já protegido por SSO, autorização atual e protocolo idempotente. A permissão é `em.projects.manage`; o usuário RM deve estar ativo com perfil `administrador` ou `padr_o`. MFA verificado exige `aal2` inclusive para recuperar recibo concluído.

```json
{
  "projeto_id": "uuid",
  "equipamento_id": "uuid",
  "expected_project_updated_at": "ISO timestamp",
  "expected_equipment_updated_at": "ISO timestamp",
  "expected_context_version": "64 hexadecimal characters",
  "confirm_change": true,
  "changes": {"modelo": "Valor exato", "fs": "1.15"}
}
```

O objeto é estrito e `changes` deve conter pelo menos um campo permitido. Somente campos modificados pelo usuário são enviados; campos omitidos permanecem intactos.

| Campos | Validação de uma alteração |
| --- | --- |
| `embarcacao`, `fabricante`, `modelo`, `numero_serie`, `descricao`, `certificado`, `norma`, `potencia`, `rotacao`, `tensao_estator`, `tipo_tensao`, `corrente_estator`, `corrente_partida`, `frequencia`, `classe_isolamento`, `grau_ip`, `forma`, `regime`, `peso`, `ligacao`, `componentes` | Texto exato de até 10000 caracteres; não remove espaços nem interpreta listas/JSON; `null` limpa o campo. |
| `placa_motor` | `c___placa`, `s___placa` ou `null`. |
| `fp`, `fs` | String decimal simples com sinal opcional, 1–30 dígitos inteiros e até 20 casas decimais, ou `null`; sem notação científica, coerção JavaScript ou limite físico presumido. |
| `numero_cabos` | Inteiro JSON entre 0 e 2147483647, ou `null`. |

Não aceita tipo de equipamento, vínculo/identidade, metadados de importação, `desmontar_para_orcar`, `ensaiar_antes_desmontar` ou `teste_intermediario`. O tipo que determina o planejamento continua sob o comando de planejamento existente. O texto histórico `rm_projetos.descricao_equipamento`, registrado no recebimento, não é reescrito por esta edição técnica.

O comando obtém o lock de protocolo existente, depois advisory `project11`, linha do projeto e linha do equipamento. Revalida versões e hash contextual dentro desses locks. Dado novo ou vínculo divergente retorna `PT409`; o usuário atualiza a consulta antes de preparar nova alteração. A comparação efetiva usa tipos PostgreSQL: uma diferença apenas na escala decimal não constitui alteração.

## Resultado, auditoria e repetição

O resultado usa `id` e `updated_at` do equipamento e o registro mínimo:

```ts
{
  projeto_id: string;
  equipamento_id: string;
  project_updated_at: string;
  changed_fields: string[]; // somente o subconjunto efetivamente alterado
  context_version: string; // contexto posterior ao salvamento
}
```

O diário `rm_private.equipment_change_events` registra versões completas anterior/posterior, campos efetivamente alterados, identidade Auth, ator RM e protocolo. Nenhum cliente, inclusive `service_role`, tem acesso direto ao diário. Sem alteração efetiva, o comando produz recibo sem UPDATE, sem mudar timestamp e sem inventar evento. Repetir o mesmo protocolo/ator/corpo retorna o recibo original, inclusive após encerramento; autorização, sessão SSO e MFA atuais são verificados antes. Protocolo com intenção diferente é rejeitado.

## Convivência com recebimentos offline

O antigo recebimento não carrega versão do equipamento e pode reenviar dados técnicos de um rascunho. O incremento mantém esse corpo/protocolo/ator e a fila existentes. A função privada de atualização passa a obter `project11` antes da linha do projeto e, antes de qualquer escrita, verifica o vínculo canônico dos equipamentos já editados na web e os campos que a web efetivamente alterou.

Recebimento novo conflitante retorna `PT409` sem persistir alterações parciais, registros de mídia, recibo ou mudança de vínculo no banco. Arquivos já enviados ao Storage permanecem preservados; a guarda transacional não desfaz transferências de arquivos. Não se recria automaticamente o envio com outro UUID. Campos nunca alterados na web e reenvio de valores atuais continuam aceitos; recibos mobile já concluídos são recuperados antes desses bloqueios. Recebimentos de equipamentos novos continuam pelo caminho existente.

Um trigger em `rm_equipamentos` impede que outros escritores, incluindo ETL, sobrescrevam os campos assumidos pela edição web, mudem o proprietário ou removam um equipamento com histórico técnico. Somente o delta exato autorizado no diário privado da transação permite a alteração web. Não existe flag de cliente ou GUC que ignore essa proteção.

O lock `FOR UPDATE` do equipamento também serializa escritas externas no ponteiro reverso por meio do `KEY SHARE` da chave estrangeira. Vínculo externo confirmado primeiro invalida o contexto do editor; confirmado depois de um salvamento válido deixa a próxima consulta em estado somente leitura. Esta entrega não reconcilia esses vínculos.

## Validação e publicação

`tests/web_project_equipment_upgrade.sql` aplica o código exato sobre a versão 030 com chamadas previamente aquecidas. Compara hash/contagem das 71 tabelas RM anteriores e das duas tabelas Storage, políticas e definições/ACLs das funções não alteradas. A instalação cria apenas o diário vazio, sem backfill de dados ou de histórico.

`tests/web_project_equipment.sql` cobre a projeção/vínculos, autorização, patch estrito, precisão decimal, preservação de campos omitidos/legados, no-op, recibos, encerramento, conflito offline/ETL e transações concorrentes reais. O executor usa exclusivamente um PostgreSQL local descartável. As migrações **001–031 estão aplicadas e permanecem imutáveis**. Somente a 031 foi acrescentada ao Supabase `oficina-em-mi-off`, seguida do portal EM no Railway e verificações de leitura/saúde; não foram gerados dados de negócio artificiais em produção.

## Incremento 031 publicado: evidências e limites

**Projetos → abrir projeto → Informações → Editar dados técnicos** permite corrigir os 25 campos escalares existentes, em grupos de identificação, dados elétricos e construção. Somente campos alterados são enviados, com revisão explícita de antes/depois, confirmação, versões exatas/hash contextual e protocolo congelado para retentativa após resposta incerta. Textos e unidades livres são preservados; FP/FS mantêm precisão decimal sem Number JavaScript. A ação Live comprovada edita seis campos; a edição dos 25 no EM é uma ampliação deliberada dos consumidores dos dados legados, sem alegação de paridade visual integral.

A leitura resolve o vínculo exato e bidirecional entre projeto/equipamento, próprio e não compartilhado; não escolhe a primeira linha, cria equipamentos ou repara vínculos. Projeto encerrado, vínculo inconsistente ou contexto indisponível permanece em consulta. Divergências legadas de classificação são sinalizadas sem sincronizar tipoIDs nem impedir a correção técnica. Descrição histórica do recebimento, flags removidas, respostas, formulários, fotos e arquivos não são reescritos por esse editor. A escrita exige perfil RM administrador/padrão, em.projects.manage e leituras de portal/projetos atuais; leitores/auditores não recebem escrita. SSO/MFA e autorização são revalidados inclusive antes do replay.

O diário privado registra autoria RM/Auth, protocolo, campos e versões completas antes/depois; não é exposto aos clientes. No-op não altera timestamp nem inventa evento. Campos já corrigidos no portal ficam protegidos contra sobrescrita por recebimento offline antigo ou ETL. A guarda roda antes da escrita do recebimento, com ordem de locks compatível; conflito devolve PT409 sem efeitos parciais, mantendo o corpo, arquivos, ator e UUID originais. Valores atuais e campos nunca corrigidos na web continuam aceitos, e recibos mobile concluídos preservam seu replay. Não há flag/GUC para contornar o delta exato autorizado no diário.

**344 testes desktop, 87 mobile no CI, 20 suítes PostgreSQL e 11 novas disputas reais aprovados**, além de tipos, build e dois smokes. As disputas cobriram recebimento antigo, encerramento, escritores externos, vínculo compartilhado em ambas as ordens e retry exato. Navegador: **15 cenários**, build `iA_tlRoQeSBK-WIC5JPyZ`, DOM real com HTTP/autenticação simulados, sem banco ou SSO reais, zero erros/origens externas; telas desktop e 390 px inspecionadas. Auditoria de **72 JavaScripts** sem os dez segredos locais conhecidos. [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41111508903).

Ensaio com rollback e aplicação preservaram integralmente **71 tabelas RM anteriores e dois snapshots de Storage**, todas as colunas/contagens/hashes, **91 OIDs/ACLs de funções anteriores** — 88 definições idênticas e três alterações exatas revisadas — e **46 políticas RM/Storage**. As três exceções são renomear o core anterior sem mudar corpo/OID/ACL, acrescentar o lock de projeto e a verificação anterior à escrita do recebimento, além de uma entrada na permissão SSO. Após instalar: **72 tabelas RM/privadas, 57 públicas com RLS e diário técnico vazio**; 178 projetos, 178 equipamentos, 778 registros e 61.803 respostas preservados, 102 usuários, outbox 4, 4 recibos web, 3 buckets/13 objetos. SSO, os dois administradores EM, políticas e guardas anteriores foram preservados.

Fonte SQL local, índice, commit e fonte aplicada conferidos com SHA256 `7d4585dc7964c01c40ab755c82252b6e5e36274f3800f555c0d590fff4e54b50`. Migrações **001–031 aplicadas e imutáveis**; a 031 é aditiva e não contém backfill de dados/histórico.

Consumidor **`f587c390f16f7f91559bdca0660218078f8aad09`**, Railway **`76171a0e-bf22-4d91-838d-77e196587f3c`** com `SUCCESS`; [EM web](https://em-web-production.up.railway.app) com health 200. QA público: **60 negações em 30 URLs e seis verificações de API, total de 66 bloqueios**, com anônimo/cookie forjado e POST de origem indevida. Microsoft-only, CSRF, callback estrito, cookie opaco HttpOnly/Secure e início PKCE até Microsoft conferidos; somente o fluxo próprio de QA foi cancelado, sem autenticar uma pessoa.

Não houve CRUD artificial em produção, novo APK, alteração de identidades/grants na Central ou escrita no Bubble. A ponte permanece desativada (SYNC_OUTBOX_ENABLED=false). Dados, respostas e trabalhos offline existentes foram preservados. Esta entrega não cria equipamentos, reconcilia vínculos, restaura etapas removidas do mobile, publica histórico técnico como uma nova tela ou entrega exclusão/versionamento de comentários/documentos.

**Próxima prioridade:** edição protegida de comentários do projeto, com autoria, versões e histórico. Exclusão de comentários e substituição/exclusão/versionamento de documentos continuam fora desse próximo incremento; Word/relatórios, QR, cadastros complementares, capacidade/calendários/lotes, comercial, laboratório e coexistência permanecem no plano. A paridade global continua em andamento.

[Discovery Live](../docs/discovery_rmmi_equipamento_tecnico.md). Provas locais ignoradas: `project-equipment-031-{rehearse,apply}-proof.json`, `project-equipment-postflight.json`, `project-equipment-ci-proof.json`, `project-equipment-deployment.json`, `project-equipment-public-qa.json`, `public-sso-qa.json`, `project-equipment-source-proof.json`, `project-equipment-qa-summary.json`, `project-equipment-browser-secret-audit.json`, `.tmp/equipment-desktop-tests.log` e `.tmp/equipment-final-full.log`.

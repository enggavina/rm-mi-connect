# Edição técnica do equipamento do projeto — incremento 031

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

Recebimento novo conflitante retorna `PT409` sem persistir alterações parciais, mídias, recibo ou mudança de vínculo. Não se recria automaticamente o envio com outro UUID. Campos nunca alterados na web e reenvio de valores atuais continuam aceitos; recibos mobile já concluídos são recuperados antes desses bloqueios. Recebimentos de equipamentos novos continuam pelo caminho existente.

Um trigger em `rm_equipamentos` impede que outros escritores, incluindo ETL, sobrescrevam os campos assumidos pela edição web, mudem o proprietário ou removam um equipamento com histórico técnico. Somente o delta exato autorizado no diário privado da transação permite a alteração web. Não existe flag de cliente ou GUC que ignore essa proteção.

O lock `FOR UPDATE` do equipamento também serializa escritas externas no ponteiro reverso por meio do `KEY SHARE` da chave estrangeira. Vínculo externo confirmado primeiro invalida o contexto do editor; confirmado depois de um salvamento válido deixa a próxima consulta em estado somente leitura. Esta entrega não reconcilia esses vínculos.

## Validação e publicação

`tests/web_project_equipment_upgrade.sql` aplica o código exato sobre a versão 030 com chamadas previamente aquecidas. Compara hash/contagem das 71 tabelas RM anteriores e das duas tabelas Storage, políticas e definições/ACLs das funções não alteradas. A instalação cria apenas o diário vazio, sem backfill de dados ou de histórico.

`tests/web_project_equipment.sql` cobre a projeção/vínculos, autorização, patch estrito, precisão decimal, preservação de campos omitidos/legados, no-op, recibos, encerramento, conflito offline/ETL e transações concorrentes reais. O executor usa exclusivamente um PostgreSQL local descartável. As migrações 001–030 permanecem imutáveis. Produção deve receber somente a 031 no Supabase `oficina-em-mi-off`, seguida do portal EM no Railway e verificações de leitura/saúde; não gerar dados de negócio artificiais em produção.

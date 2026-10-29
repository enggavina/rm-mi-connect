# Construtor de formulários — contrato 019

Estado: migração 019 aplicada em `oficina-em-mi-off` (`ellpxfbsrbhblyizvbbk`) em 29/10/2026 às 13:46:39 UTC. Consumidor de 16 capacidades publicado em [Modelos de formulário](https://em-web-production.up.railway.app/modelos-formularios): commit `934f8bc1fd45ba9287666c7371a79c7b00ba1c83`, deploy Railway `21c95a5e-2f82-4f64-9f92-4fe676324e16` com `SUCCESS`. As novas permissões foram concedidas depois de confirmar essa disponibilidade: `mgavina` e `softdev05` têm gestão do EM, com 16 capacidades cada. O papel global de `softdev05` na Central permanece `user`. A migração não criou rascunhos, versões nem dados operacionais e não ativou integração.

A publicação cria um novo `rm_forms`, novas `rm_questoes` e novos `rm_itens_questoes`. A versão anterior permanece ativa e conserva todos os IDs, vínculos, respostas e rascunhos offline. Para usar a nova versão, o administrador precisa selecioná-la explicitamente na matriz de engenharia; o contrato 018 aplica essa seleção somente às alocações futuras.

## Permissões e armazenamento

- BFF: `em.form_templates.read` para consultar; `em.form_templates.manage` para criar, salvar e publicar.
- Banco: conta RM ativa vinculada a `auth.uid()`, perfil `administrador` e MFA AAL2 quando houver TOTP verificado. O cliente não fornece ator, perfil ou autoria.
- O envelope SSO 016 exige permissão de uso único para o UUID da submissão, operação, hash do payload e sessão Auth local. Cada replay precisa de autorização nova. A configuração de produção continua `require_sso=true`; a exceção legada de ambiente com `require_sso=false` permanece a mesma de 016.
- Novas tabelas `rm_form_template_families`, `rm_form_template_drafts` e `rm_form_template_versions` permitem somente SELECT sob RLS para identidade RM ativa. Não entram no catálogo de sincronização mobile. Writes diretos são revogados inclusive de `service_role`; as mutações passam pela RPC autenticada.
- A capacidade de leitura é verificada no BFF a cada solicitação. A RLS de leitura mantém o contrato RM existente, sem alegar que as capacidades corporativas são verificadas em consultas REST diretas com credenciais legadas mobile.

`rm_form_template_versions` usa chave `(family_id, version)`, com `form_id` e `draft_id` únicos. Uma origem legada é registrada como versão 1 somente quando alguém cria uma nova versão dela; esse registro tem `legacy=true`, sem assumir propriedade do importador legado. New/copy criam família independente. Nenhum dado legado é inserido ou reescrito na instalação da migração.

## Mutações

Todas usam `rm_web_mutate_v1(p_client_submission_id uuid, p_operation text, p_payload jsonb)` e a capacidade exata `em.form_templates.manage`.

```ts
create_form_template: {
  id: UUID; // ID do novo rascunho
  source_form_id: UUID | null;
  kind: 'new' | 'copy' | 'version';
}
save_form_template: {
  id: UUID;
  expected_updated_at: string;
  content: FormTemplateContent;
}
publish_form_template: {
  id: UUID;
  expected_updated_at: string;
}
```

`new` exige origem nula. `copy` e `version` exigem formulário existente. Copiar cria família nova; criar versão conserva a família da origem. Publicar usa exclusivamente o conteúdo salvo, nunca conteúdo adicional enviado no clique de publicação. O UUID de cada submissão é estável; repetir com outro ator, operação ou payload retorna `23505`.

```ts
type FormTemplateContent = {
  titulo: string;
  descricao: string | null;
  title: string | null;
  description: string | null;
  tipo: FormType | null;
  questions: Array<{
    id: UUID;
    indice: string;
    enunciado: string;
    title: string | null;
    subtitulo: string | null;
    tag: string | null;
    tipo: QuestionType;
    subtipo: QuestionSubtype | null;
    dimensoes: Dimension | null;
    obrigatorio: boolean;
    colaborador_filtro_perfil: RmProfile | null;
    items: Array<{
      id: UUID;
      indice: string;
      descricao: string;
      description: string | null;
    }>;
  }>;
};
```

Todas as propriedades do DTO são obrigatórias; opcionais sem valor usam `null`. Não são aceitas propriedades extras, IDs Bubble, campos de sincronização ou autoria. Os IDs de questões/opções são chaves internas do editor, globalmente distintas no conteúdo. A cópia remapeia essas chaves; a publicação gera outro conjunto de IDs e registra o mapeamento.

`source_snapshot` é somente leitura, separado do conteúdo editável: `{usa_aprovacao, imagem_capa_url, celulas_ids, equipes_ids}`. A cópia preserva esses metadados e os textos alternativos. Um formulário novo usa `usa_aprovacao=true`, capa nula e listas vazias. `usa_aprovacao` não é um controle para dispensar revisão: o fluxo operacional atual não usa esse campo para pular aprovação. O BFF não expõe a URL de capa à interface; fornece somente a indicação de presença.

### Validação

Salvar permite título/enunciado/opção vazios, seleções sem opções e índices repetidos, para recuperar e completar uma origem legada. UUIDs, tipos dos campos, enums e limites estruturais continuam obrigatórios.

Limites: 1.000 questões, 5.000 opções no formulário inteiro, 800.000 bytes do JSONB textual no PostgreSQL. Índices são strings decimais com até 60 caracteres, sem expoente, valor absoluto até 1.000.000.000. Valores fracionários são gravados como `numeric`, sem arredondamento. A publicação exige índices distintos por questão e por lista de opções, inclusive após conversão para `double precision`, porque o mobile ordena usando `Number`. O editor pode oferecer normalização explícita; o servidor não renumera silenciosamente.

Publicar exige título, pelo menos uma questão que não seja subtítulo e textos preenchidos. São suportados os 15 tipos de 001: `texto_curto`, `texto_longo`, `escolha__nica`, `caixas_de_sele__o`, `lista_suspensa`, `lista_multi_sele__o`, `foto`, `foto_antes_depois`, `data`, `hora`, `subt_tulo`, `colaborador`, `assinatura`, `cliente`, `numero`.

Os quatro tipos de seleção precisam de opções; os demais não aceitam opções na publicação. `intervalo_de_datas` exige tipo `data`; `intervalo_de_hor_rios`, tipo `hora`. Dimensões são permitidas em texto curto, texto longo ou número. Filtro de perfil exige tipo colaborador. Os enums de formulário, dimensão, subtipo e perfil são os existentes em 001; não são criados tipos de pergunta sem suporte no mobile.

### Concorrência e resultado

Salvar/publicar bloqueia o rascunho e compara `expected_updated_at` sem truncar precisão. Divergência retorna `PT409`. Publicações compartilham lock por família e recebem `max(version)+1` atomicamente. É permitido publicar a partir de uma versão anterior: o número da origem é informativo, e não existe ponteiro mutável que reconfigure automaticamente a engenharia. O timeout do lock é 10 segundos (`55P03`); deadlocks e falhas de infraestrutura não são ocultados.

O retorno mantém o envelope web:

```ts
{
  operation, id: draftId, projeto_id: null, updated_at,
  record: snapshot.draft,
  snapshot,
  publication: null | {
    form_id: UUID,
    version: number,
    id_mapping: {
      questions: Record<DraftQuestionUUID, PublishedQuestionUUID>,
      items: Record<DraftItemUUID, PublishedItemUUID>
    }
  },
  idempotent_replay: boolean
}
```

O mesmo rascunho não publica duas vezes. Repetir o UUID de submissão retorna a publicação original; tentar outra publicação do rascunho já publicado retorna erro. Formulários gerados pelo construtor e seus filhos ficam protegidos contra INSERT de filhos, UPDATE ou DELETE, inclusive por chamadas técnicas que respeitem os triggers. Isso não impede o uso normal dos formulários em respostas ou alocações.

Cada formulário tem sua própria sequência em `rm_numeracoes`: a versão nova inicia numeração própria ao primeiro envio. Contadores e códigos históricos não são copiados. As consultas e relatórios devem considerar o `form_id`/versão, não interpretar o código isolado como identificador global.

## Leitura atômica

As duas RPCs são `STABLE SECURITY INVOKER`, compostas por um único SELECT, respeitando a RLS. São executáveis apenas por `authenticated`; origem/rascunho ausente ou não visível retorna `null`.

- `rm_web_form_template_snapshot_v1(p_id uuid)` → `{draft:{id,kind,state,family_id,source_form_id,source_version,content,source_snapshot,created_at,updated_at,published_form_id}, publication}`. `state` é `draft` ou `published`.
- `rm_web_form_source_snapshot_v1(p_id uuid)` → `{form:{id,titulo,descricao,title,description,tipo,ativo}, content, source_snapshot, version, family_id}`. Origem legada ainda não registrada retorna versão 1 e família nula. Todos os índices são serializados como texto.

Os campos `source_snapshot` não aceitam alterações por `save_form_template`. A publicação não altera `rm_celula_form_tipos_equipamento`, `rm_celulas_projeto.forms_ids`, respostas, filas ou rascunhos mobile. Não cria eventos para o Bubble.

## Validação local e implantação

Validação concluída: 001–019 e as oito suítes passaram em PostgreSQL isolado, incluindo o ensaio de upgrade com função previamente executada de 017. A suíte `tests/web_form_templates.sql` cobre criação/cópia, origem legada, validações de publicação, índices fracionários e colisões `double precision`, metadados preservados, IDs novos, replay, imutabilidade, adoção explícita em engenharia, envio/revisão mobile com IDs antigos e fronteiras RLS/SSO/MFA. Duas conexões com administradores SSO distintos publicaram simultaneamente na mesma família e obtiveram versões 2 e 3; uma edição concorrente do mesmo rascunho retornou `PT409`, preservando a primeira alteração. O banco temporário foi encerrado e removido pelo harness.

Na aplicação remota, 53 comparações transacionais preservaram integralmente as 52 tabelas RM anteriores e o ledger privado de mutações web, sem excluir colunas: 102 usuários preservados, outbox 4 → 4 e receipts web 0 → 0. Permaneceram `require_sso=true`, ACLs privadas e o gateway mobile. Foram verificadas 55 tabelas RM com RLS, três tabelas novas vazias, dois leitores `STABLE SECURITY INVOKER`, três triggers de imutabilidade e os dez mapeamentos exatos de operação/capacidade. Nenhum CRUD operacional foi executado para QA remoto.

A fonte completa de 019 está registrada em `supabase_migrations.schema_migrations`; o SHA-256 conferido em uma segunda leitura foi `045192bf56ff275dc31645c2cd089c6ebba7ad04a300466c3dfd540afc0b6111`. Provas locais ignoradas pelo Git: `.tmp/form-templates-019-application-proof.json`, `.tmp/form-templates-019-postflight.json` e `.tmp/form-builder-019-tests.log`. A fonte de 019 está congelada após aplicação; correções posteriores exigem migração aditiva.

Antes da implantação remota: revisar 019 e os resultados locais, confirmar o projeto autorizado e a sequência 001–018, preservar `require_sso=true`, comparar os dados legados antes/depois e registrar a fonte exata no histórico de migrações. Não criar ou excluir registros operacionais para QA. A publicação de capacidades e concessões na Central é uma etapa separada, posterior à disponibilidade de backend compatível.

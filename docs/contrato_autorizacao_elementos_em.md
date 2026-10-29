# Contrato proposto: Elementos e gestão individual do EM

Discovery local complementar em 29/10/2026. **Proposta para implementação futura; nenhuma migração, capacidade ou permissão foi alterada por este documento.** Complementa [a matriz de Cadastros/Autorização](discovery_rmmi_cadastros_autorizacao.md) e preserva Microsoft/Central como autoridade do acesso web.

## Conclusão e pré-requisitos reais

O fluxo legado central já foi compreendido: catálogo de elementos, busca/seleção de pessoa, filtro por módulo e adicionar/remover pessoa da lista explícita, com log. **Não foi demonstrada herança de perfil/função, deny explícito ou uma administração global legítima.** A GUI pode começar como consulta, mas a escrita de permissões e a aplicação dessa política aos módulos existentes precisam dos pré-requisitos abaixo:

| Pré-requisito | Evidência e resolução necessária | O que bloqueia |
| --- | --- | --- |
| Dados ainda não importados | Leitura agregada de produção feita pelo agente principal confirmou **0 `rm_elementos_permissao` e 0 `rm_templates_word`**, registrada em `.tmp/parity-unmigrated-data-counts.json`. Schema 005 não corresponde ao contrato Live de Elemento. Reconciliar/cargar a fonte real por IDs, com relatório de rejeições | Paridade da lista e de concessões; habilitar um novo gate local com a tabela vazia bloquearia o portal inteiro |
| Mapa de consumidores por código | GT 005/006/007, por exemplo, são compartilhados entre títulos e tipos; rótulos antigos divergem da condição. Código sozinho não prova ação exclusiva nem escopo EM | Aplicar regras de elemento sobre ações/rotas existentes ou permitir que editar um código altere segurança |
| Identidade legada vs corporativa | Live altera User encontrado por email; web já tem binding explícito `(issuer,subject)→rm_user_id/auth_user_id`. Falta comprovar a correspondência de cada pessoa legada com eventual perfil web separado | Importar memberships como concessões web; criar vínculos ou promover pessoa por email seria uma concessão indevida |
| Capacidade administrativa específica | As 18 capacidades atuais não distinguem gerir conteúdo de gerir autorização. Planejar capacidades EM próprias e publicar consumidor compatível antes da concessão na Central | Escrita de elementos/grants em produção; `em.catalogs.manage` ou ser admin RM não basta para administrar permissões |
| Transação e auditoria | Array 005 não tem FK por membro; log Live é texto e possui inconsistência após remover. Reutilizar envelope/recibo 016 e validar todos os IDs na RPC | Grant/revoke seguro, concorrência, revogação efetiva e replay |

Esses itens são trabalho técnico verificável, não justificativa para inventar regra nem para pedir promoção global na Central. Os demais detalhes de paginação/navegação ainda sem evento individual não impedem projetar o contrato conhecido. Não é necessário esperar a leitura de todos os 431 eventos para construir uma consulta fiel e segura, mas não se deve declarar a migração inteira concluída.

## Fonte funcional confirmada

| Fluxo Live | Leitura/ação confirmada | Equivalência necessária |
| --- | --- | --- |
| Catálogo `cnCjM/cnCkm` | Elemento por `aplicacao_text`; 10/20/50; criar/editar/excluir via `cnCgL/cnCgM` | Buscar código/funcionalidade/descrição e filtrar módulo, seleção de registro por ID, estados vazio/carregando/erro, retorno à lista |
| Criar/editar | `cnDGc` cria se estado vazio; `cnDGh` altera se presente; escreve aplicação/código/descrição/funcionalidade; edição acrescenta log | Metadados versionados; criação de metadado não cria automaticamente nova autoridade/ação/capacidade |
| Gestão individual `cnCsq` | Pesquisa pessoa, estado `cnCsA.usuario`, estado pesquisa/individual, módulos agrupados e filtro em `cnCpR` | Pessoa selecionada por ID estável; voltar mantém busca; não resolver perfil ou alvo por nome/email |
| Revogar/conceder | `cnDRk` remove e `cnDSn` adiciona a User encontrada por built-in email=selecionado.email_corporativo; escreve `log_list_text` | Comando idempotente de estado desejado, alvo RM explícito e validado; journal estruturado preserva antes/depois |
| Guard e herança | Guard DJ 017 `cnDTL` está desativado; condições dos controles usam membership explícita. Não foi encontrada rotina comprovada de herança | Não ativar guard desativado, não usar bypass de administrador 005 como regra inferida e não apresentar permissões herdadas fictícias |

## Reconciliação do schema 005

Reutilizar **`rm_elementos_permissao`** e preservar seus IDs. Não criar outra entidade de elementos ou outra lista de concessões concorrente.

| Fonte Live | Situação 005 | Contrato proposto |
| --- | --- | --- |
| `_id` | `bubble_unique_id` UNIQUE já existe | Identificador de origem imutável; importar idempotentemente por ele, preservando UUID destino |
| `codigo_text` | `codigo` NOT NULL UNIQUE existe | Preservar código; detectar duplicatas/vazios na fonte antes da carga. Não remover UNIQUE para ocultar inconsistência. Código publicado/vinculado a ação é imutável na GUI |
| `aplicacao_text` | `aplicacao` existe, mas comentário 005 fala RM/NR12/Geral | Preservar texto Live como **módulo** (PAINEL/COMERCIAL/GESTÃO etc.). Não confundir com aplicação autorizada. Classificar o escopo da aplicação por consumidores reais |
| `funcionalidade_text` | Falta coluna correspondente | Acrescentar `funcionalidade`; pode ser base do nome de exibição, sem substituir o código |
| `descricao_text` | Falta coluna correspondente | Acrescentar `descricao`; não descartar descrição ou escondê-la em `nome` |
| `log_list_text` | Falta coluna correspondente | Preservar em histórico legado separado/imutável, por exemplo `legacy_log text[]`. Nunca transformá-lo em concessão ou tratá-lo como journal novo confiável |
| `permissoes_list_user` | `usuarios_permitidos uuid[]` existe | Manter como fonte local única de membership explícita; todos os IDs são **`rm_users.id`**, não UUID Auth, subject Microsoft ou email. Validar cada membro na carga/RPC |
| Creator e datas | `created_by/created_at/updated_at` existem | Resolver autor por ID legado; preservar Modified Date de origem em campo próprio, sem falsificar versão local de concorrência |
| Nome/página/tipo | `nome` é NOT NULL; `pagina/tipo` existem, mas não constam no tipo Live lido | `nome` é rótulo derivado documentado de funcionalidade não vazia, senão código; conservar a origem. Página/tipo só podem ser classificados por evidência do consumidor, não pelo rótulo do botão |
| Escopo EM e binding da ação | Não existem | Registro classificado como EM somente após mapa verificável; desconhecido fica em quarentena. Pode-se usar coluna de escopo nullable com valor EM apenas quando provado; **não aplicar default EM à carga inteira**. Mapa código/ID→rota/ação/capacidade é registro controlado no servidor e fora do CRUD comum |

O importador deve mostrar contagens recebidas/aceitas/rejeitadas, duplicatas, consumidores, membros resolvidos e não resolvidos. Importar somente permissões resolvidas; preservar referências não resolvidas para reconciliação, sem convertê-las em acesso. Não inserir linhas artificiais em produção para demonstrar a GUI. Não ativar a ponte ou passar a sincronizar autorizações com o Bubble como consequência da carga.

## Identidade: sem associação automática por email

A cadeia web atual é aprovada explicitamente: `issuer+subject corporativos → rm_private.sso_identity_bindings → auth_user_id local + rm_user_id`. O binding é único por sujeito, perfil RM e Auth local, possui `enabled/approved_by/approved_at/approval_metadata` e só serve se o perfil RM estiver ativo e o Auth local corresponder. Reutilizar isso.

1. Resolver cada Bubble User por `rm_users.bubble_id`, nunca por nome/email. Membership legada vai primeiro para esse RM ID exato.
2. Se o próprio RM ID já tem binding corporativo aprovado, a correspondência é direta e comprovável. Email é somente dado de apresentação.
3. Se a pessoa possui perfil RM web separado da identidade legada do operador, **não fundir linhas, não mudar Auth do operador e não copiar permissões automaticamente**. Registrar crosswalk aprovado entre os dois IDs antes de migrar a concessão web. Verificar primeiro se `approval_metadata` já documenta essa correspondência; se faltar representação durável, uma coluna nullable de referência legada no binding existente é preferível a outra entidade de identidades, com FK/uniquidade e aprovação fora deste CRUD.
4. Contas compartilhadas do tablet e pessoas identificadas por matrícula são entidades distintas. Uma conta login/tablet não deve virar sujeito SSO de uma pessoa. A migração 010 e seus vínculos permanecem intactos.
5. Pessoa legada sem binding ou crosswalk comprovado fica consultável para reconciliação, com escrita de concessão web desabilitada. Nenhuma criação de binding/Auth é disparada por conceder Elemento.

`mgavina` e `softdev05` continuam administradores do EM conforme autorização explícita. O plano de ativação precisa preservar essa autorização com os **bindings já aprovados por ID**, sem conceder por regra genérica de email ou perfil. Isso não os transforma em administradores globais da Central/Microsoft. Este documento não altera seus vínculos nem concede capacidades.

## Autoridade, capacidades e negação por padrão

Proposta mínima de **duas capacidades novas, restritas à aplicação `em`**:

- `em.authorization.read`: consultar catálogo, concessões locais e journal redigido.
- `em.authorization.manage`: alterar metadados/conceder/revogar dentro do escopo EM. Além da capacidade, exige perfil RM administrador, sessão corporativa/binding válidos e MFA quando configurado.

Nenhuma capacidade atual será interpretada como autorização para conceder permissões. Manter a separação leitura/escrita permite consulta de auditoria sem administração. Atribuir capacidade na Central é uma operação do aplicativo EM e não exige nem autoriza promover papel global; a GUI Elemento não fará essa atribuição. Concessões dessas novas capacidades devem usar a autorização administrativa EM já aprovada e sujeitos exatos, após publicar um consumidor que aceite os 20 códigos e continue aceitando as 18 capacidades anteriores. O consumidor atual rejeita códigos desconhecidos; não conceder antes de sua compatibilidade estar publicada.

Para um recurso do EM futuramente governado por Elemento, acesso efetivo exige conjuntamente: identidade corporativa verificada, aplicação EM liberada na Central, capacidade exata da ação, perfil RM/condições de negócio, escopo/consumidor local conhecido e membership local explicitamente resolvida. Falha/ausência/ambiguidade nega. **Um grant local não concede capacidade Central; uma capacidade Central não comprova membership legada.** Não criar bypass genérico `rm_users.perfil=administrador` para esse novo motor.

Essa interseção só será habilitada módulo a módulo depois da carga/mapeamento e de ensaio que preserve os acessos explicitamente aprovados. Enquanto não habilitada, os módulos existentes mantêm seu contrato SSO/capacidades atual; tabela vazia não será tratada nem como grant universal nem como gatilho para negar todas as rotas já publicadas. A GUI deve distinguir concessão local de acesso corporativo efetivo: sem uma decisão de alvo proveniente da Central, não afirmar que outra pessoa tem acesso efetivo só porque seu checkbox local está marcado.

Ausência de membro significa não permitido; não foi demonstrado deny explícito com precedência sobre allow, nem herança. Não adicionar tabela de perfis/grupos herdados sem fonte comprovada. O controle da própria administração de autorização fica na Central mais os guardas RM, não em um código de Elemento que o próprio administrador possa editar para ganhar autoridade.

## Fronteiras BFF, PostgreSQL e RLS

- **BFF:** `requireWebUser`/`getSsoWebAccess` validam a identidade e decisão Central frescas. Consultas exigem read; comandos exigem manage e administrador/MFA. Usar `no-store`; validar entrada e envelope de saída. Browser nunca fornece ator, perfil, capability concedida, issuer, subject, hash da sessão ou autoria.
- **Consulta sensível:** tabela bruta não deve ser liberada para todo RM autenticado. Manter RLS negando acesso direto e expor DTO por RPC de leitura servidor a servidor, seguindo o padrão das RPCs privadas SSO 016: somente o bridge/BFF autorizado a executar, sessão/binding/ator verificados, escopo EM e projeção estrita. A Central é verificada no BFF; a RLS não será apresentada falsamente como conhecedora de capacidades corporativas em um JWT legado. DTO não contém tokens, chaves, campos privados de User, membership de outros aplicativos ou log legado bruto indiscriminado.
- **Escrita:** reutilizar `rm_web_mutate_v1` e permit 016 com operação/capacidade exatas e hash do corpo; não criar endpoint genérico de update de tabela. PostgreSQL deriva ator de `auth.uid()`, exige binding/sessão SSO ativos para essas operações inclusive se outros fluxos mantiverem exceção legada de staging, verifica perfil/MFA, valida destino/escopo/registro e grava tudo na mesma transação. Writes diretos continuam revogados.
- **Helper 005:** `rm_user_has_element_permission(p_user_id,...)` aceita identidade fornecida e faz bypass por administrador. Não utilizá-lo para autorizar o novo portal. Antes de reaproveitar qualquer helper legado, rever privilégios/anônimo e substituir por contexto verificável sem parâmetro de ator controlado pelo browser.
- **Revogação real:** reavaliar membership atual na execução da operação, e não confiar só em menu oculto, sessão em cache ou permit emitido antes da revogação. Introduzir protocolo de lock compartilhado da política para ações governadas, exclusivo para alteração de concessões, antes dos locks de recurso de negócio. Preservar a ordem do envelope 016 e comprovar concorrência com os dispatchers atuais; uma autorização revogada não pode ser reutilizada por permit antigo.

## Comandos futuros e journal

Proposta de operações específicas, sem implementá-las nesta revisão:

```text
save_permission_element:
  {id, expected_updated_at, changes:{codigo?, nome?, funcionalidade?, descricao?, aplicacao?, pagina?, tipo?}}

set_element_membership:
  {elemento_id, target_rm_user_id, expected_updated_at, allowed:boolean, comment?:string}
```

UUID de submissão fica no envelope existente. `allowed` representa estado desejado; **não existe toggle baseado em estado do cliente**. Conceder já concedido ou revogar já ausente é no-op com novo recibo, sem bump de versão desnecessário; replay do mesmo UUID/corpo/ator retorna o resultado inicial. Outro corpo/ator/operação retorna conflito. Versão incorreta ou alvo alterado precisa PT409; escopo/identidade/capacidade não autorizados retornam 42501, sem revelar dados privados.

Validar a versão antes de decidir um no-op: outro administrador pode ter alterado o mesmo elemento. Só o replay exato usa o recibo anterior, depois de confirmar a autorização atual do ator; ele não reaplica a concessão nem ressuscita acesso revogado posteriormente. O resultado é a confirmação daquela tentativa, não uma promessa de estado atual: após confirmar, a UI invalida a consulta e relê a membership canônica.

Criação exige código e campos obrigatórios reconciliados; editar código de elemento já vinculado/publicado é rejeitado. O mapa de segurança não é editável pelo comando de metadados. Criar metadado sem consumer comprovado deixa registro não autorizador. Exclusão definitiva de elemento ativo/vinculado não deve ser a primeira etapa; preferir arquivamento preservando referências e journal. O DeleteThing legado não comprova que apagar metadado com consumidores seja seguro. Antes de disponibilizar exclusão, fechar inventário de consumidores e estratégia de compatibilidade.

Para membership: lock da submissão, proteção exclusiva da política, elemento `FOR UPDATE`, alvo/binding verificados, versão exata, conjunto distinto de UUIDs, validação de todos os membros tocados e atualização no mesmo commit do recibo. Usar `rm_private.web_mutation_receipts` existente como journal transacional: versão e membership do alvo antes/depois, ator RM/Auth, binding/subject aprovados por referência, elemento/alvo, operação, comentário e ID de envio. O snapshot anterior e o estado desejado/confirmado bastam para reconstruir a alteração individual; não criar outra tabela concorrente de concessões. Guardar só os dados necessários; nunca JWT, senha, segredo TOTP ou ciphertext no resultado. Preservar log legado como evidência separada, sem reescrevê-lo como se fosse esse journal.

Retorno mínimo: operação, elemento/alvo, versão confirmada, membership local e indicador de replay/no-op. A UI usa uma única tentativa congelada durante envio incerto, sem permitir outro grant/revoke com novo UUID antes de confirmar. Só o servidor informa sucesso; erro não muda checkbox permanentemente.

## Impedir autoelevação e alcance global

1. O próprio ator não pode aumentar seu acesso por um grant local; bloquear concessão para si. Controlar o conjunto delegável por registro estático de ações EM e capacidades que o ator possui, nunca por strings/códigos livres fornecidos na tela.
2. Elementos administrativos de Central/SSO/bindings/papéis/capability registry estão fora do conjunto delegável. A gestão local não altera `rm_users.perfil`, `auth_user_id`, status de Auth, bindings ou grants da Central.
3. Rejeitar alvo de outro aplicativo, código desconhecido, mapping ambíguo, conta compartilhada ou binding desabilitado. Um administrador EM não administra pessoas/elementos NR12/Geral por ter o mesmo tipo Bubble.
4. Preservar a administração aprovada de mgavina/softdev05 por vínculos exatos. Não usar um checkbox local para criar/remover a própria capacidade de administrar autorização nem para retirar o último acesso administrativo corporativo; essa autoridade permanece na Central.
5. Revogação local não altera login de tablet, identidade por matrícula, resposta, trabalho offline ou vínculos da 010. Qualquer gestão operacional dessas permissões pertence ao contrato próprio de usuários/células.

## Sequência verificável antes da GUI de escrita

1. Reconciliação de campos/consumidores e importador de Elementos com simulação/relatório, sem enforcement. Confirmar 0→carga real com contagens e IDs estáveis; nenhuma concessão por email.
2. Crosswalk de identidades comprovado e relatório de ambiguidades/contas compartilhadas. Os dois administradores EM permanecem preservados por bindings aprovados.
3. Consumidor compatível com as duas novas capacidades, BFF/RPCs/RLS e protocolo de journal/locks; testes negando acesso direto/legado/global e autoelevação. Nenhuma concessão remota anterior à publicação compatível.
4. Consulta dos dois menus com DTOs reais; depois metadados e grant/revoke com recibo, validação, estados e auditoria.
5. Aplicar Elementos às ações existentes somente após manifesto dos códigos/consumidores e migração de concessões explícitas; ativação por módulo com regressão do SSO/admins/mobile. Não contar essa etapa como concluída por uma GUI de checkboxes.

Testes indispensáveis: código/usuário duplicado, email alterado sem mudança de ID, perfil web separado do operador, binding inativo/trocado, sem capability/MFA, alvo de outro aplicativo, self-grant, tentativa de mudar mapa/capability/ator, concorrência grant×revoke, revogação×permit antigo, recibo repetido/alterado/outro ator, no-op, perda de conexão, journal sem segredos e preservação dos dados/importação/filas offline.

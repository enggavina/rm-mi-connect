# Identificação do projeto por QR — 034

O portal oferece **Projetos → abrir projeto → Identificação por QR**. A etiqueta exibe EM / MI Electric Brasil, OS ou “Projeto em recebimento”, descrição e identificador. Pode ser impressa ou baixada como SVG. O código contém somente o UUID canônico de `rm_projetos.id`, em minúsculas e com hífens; os demais textos da etiqueta não são codificados.

## Acesso e geração

A página e `GET /api/web/projects/{id}/qr` exigem sessão atual, perfil RM administrador/padrão/auditor e as capacidades existentes `em.portal.read` e `em.projects.read`. A consulta usa o cliente autenticado e as políticas atuais do projeto. O parâmetro opcional `download=1` entrega o SVG como anexo. A resposta é privada, sem cache, com `nosniff`, sem referência e CSP restrita.

A imagem é gerada localmente com `qrcode` 1.5.4: preto/branco, 512 px, correção Q e margem de quatro módulos. Não depende de um serviço externo, não cria arquivo no Storage, não altera `qrcode_url` e não envia credenciais ou dados pessoais para o código. `qrcode_url` legado continua sendo a URL de uma imagem da origem. Não há migração SQL, RPC nova, escrita, backfill ou ampliação de permissões; 001–033 permanecem imutáveis.

Imprimir fica disponível após a imagem carregar. A impressão contém a etiqueta e oculta os controles e a navegação somente nesta página. Falha da imagem oferece retentativa; falha da cópia seleciona o identificador e informa que a cópia manual é necessária.

## Jornada do aplicativo

O recurso requer **APK 1.2.4 / código 7**. O APK anterior tinha um componente de câmera sem consumidor nessa jornada. O operador identifica-se, escolhe uma célula permitida e, na lista de projetos, usa **Ler QR Code**. **Digitar código do projeto** permite colar o mesmo UUID quando a câmera estiver indisponível. Cancelar, voltar, negar a câmera ou receber um código inválido conserva a lista utilizável.

O resolvedor lê somente o catálogo SQLite existente. Exige identificação vigente, política atual de células, célula explicitamente permitida, projeto ativo e uma única alocação visível e não retirada naquele par projeto/célula. Projeto desconhecido, encerrado, oculto, retirado, de outra célula ou catálogo ambíguo não abre. Alocação bloqueada mantém a consulta normal; sua edição continua sob as regras existentes. URLs antigas do Bubble, números de OS, maiúsculas, espaços e aliases não são aceitos como novos códigos EM.

Antes e depois da leitura, e imediatamente antes de navegar, são conferidos operador, proprietário da sessão, célula, permissões, foco e revisão do catálogo. Uma sincronização em andamento ou mudança de contexto exige nova leitura. O sucesso abre a rota existente `/projeto` com `{celula, projeto}`, sem escolher outra célula automaticamente.

Offline, somente projetos já sincronizados e permitidos pelo catálogo local podem abrir. Uma revogação remota ainda não recebida não pode ser conhecida offline; as guardas do servidor continuam controlando as mutações após reconexão. Ler o QR não sincroniza, chama RPC, salva recebimento, altera respostas, arquivos ou rascunhos, envia fila ou modifica UUID/autoria de intenções anteriores. O QR identifica o projeto e não concede acesso.

## Validação e publicação

Os testes incluem geração SVG real → rasterização `sharp` → decodificação independente `jsQR` → resolvedor mobile, em 256/512/1024 px e rotação de 90°. O contrato integrado fica em `tests/project-qr-contract.test.ts` e no CI desktop; as regras offline e mudanças de contexto ficam nos testes mobile. A validação de interface usa DOM real com HTTP/autenticação simulados, inclusive 390 px, texto longo, falhas, download e impressão.

O instalador deve manter pacote `br.com.mielectric.rmconnect` e certificado anterior. Atualizar sem desinstalar nem limpar dados preserva a instalação existente; não se deve trocar keystore ou incrementar identidades para resolver um erro de instalação. O APK interno usa assinatura Android Debug, destinada à homologação interna. Testes automatizados, exportação e verificação do APK não substituem homologação óptica com câmera/tablet físico.

[Discovery Live e limites](../docs/discovery_rmmi_qr_projeto.md). Resultado de testes, hash do APK e endereço publicado são registrados no [plano de execução](../docs/plano_execucao_paridade_rmmi.md).

## Resultado publicado do incremento 034

Consumidor **`3a1367cf398e8bc3c3f97ab3191b8c8555098909`**, Railway **`33c646e4-4b9a-4c25-a84a-8583f187379a`** com `SUCCESS`; [CI web/mobile aprovado](https://github.com/enggavina/rm-mi-connect/actions/runs/41135639324) e [EM web](https://em-web-production.up.railway.app) com health 200.

**Projetos → abrir projeto → Identificação por QR** oferece etiqueta EM / MI Electric Brasil para visualizar, imprimir, baixar SVG e copiar o identificador. A imagem local preta/branca de 512 px usa correção Q e quatro módulos de margem. O payload contém somente o UUID canônico do projeto; não inclui cliente, OS, URL, célula ou credencial. Página e imagem exigem sessão atual, perfil RM interno e as capacidades existentes de leitura do portal/projeto, com consulta JWT exata. O QR identifica o projeto e não concede acesso.

A revisão encontrou a lacuna real do APK 1.2.3/código 6: o helper e o componente de câmera não tinham consumidor na jornada. O novo **APK 1.2.4/código 7** acrescenta **Ler QR Code** e digitação do UUID na lista da célula selecionada. Resolve somente SQLite e abre a rota existente quando operador/turno/política e célula permitidos, projeto ativo e uma única alocação visível não retirada conferem. Mudanças de identidade, célula, foco ou catálogo invalidam a leitura; offline exige catálogo já sincronizado. Não há busca por URL/OS/Bubble ID nem seleção automática de outra célula.

O incremento 034 é somente leitura/navegação: não há migração SQL nova, RPC, DML, upload ou gravação em qrcode_url. As migrações **001–033 permanecem aplicadas e imutáveis**. Ler o QR não inicia sincronização, altera recebimento/resposta/rascunho/foto, reenvia fila ou troca UUID/autoria anteriores. Bubble permaneceu somente leitura, sem nova concessão na Central, alteração de identidade ou ativação da ponte; SYNC_OUTBOX_ENABLED=false permanece.

**398 testes desktop, 99 mobile e dois testes de contrato integrado aprovados**, além de tipos, build e dois smokes. SVG real → sharp → jsQR → parser/resolvedor mobile foi conferido em 256/512/1024 px e rotação de 90°. Navegador: **19 cenários**, build `dM8PuvMWFBMKYDfUn3M0-`, DOM real com HTTP/autenticação simulados, zero erros inesperados, origens externas ou escritas de negócio; capturas desktop/390 px/impressão inspecionadas. As falhas 404/503 dos cenários negativos são esperadas. Auditoria de **78 JavaScripts** contra 10 segredos locais conhecidos sem ocorrências. Auditoria npm de produção sem vulnerabilidades.

As consultas somente leitura antes/depois mantiveram **33 migrações, 74 tabelas RM/privadas, 57 públicas com RLS, 104 funções e 46 políticas RM/Storage**, além de SSO e dos dois administradores. SHA256 da 033: `ae2b343e4619d79e34b0056ec02d39afdbeb93d4b354ed1ef014aade4fd8b6e4`. Contagens observadas (antes → depois): projetos 178 → 178, respostas 61.803 → 61.803, registros 778 → 778, outbox 4 → 4, recibos 4 → 4; iguais nos dois instantes. O digest das imagens QR legadas ficou igual entre as consultas. Essa observação não pressupõe ausência de uso legítimo da produção nem equivale a snapshot integral de todas as tabelas.

QA público posterior ao deploy: **70 negações em 35 URLs e 16 verificações de API**, incluindo QR inline/download/parâmetro inválido com anônimo e cookie forjado. Login Microsoft-only, callback/CSRF, cookie opaco seguro e início PKCE até Microsoft conferidos; somente o fluxo próprio de QA foi cancelado. Não houve login Microsoft humano automatizado nem CRUD artificial em produção.

Instalador local: `artifacts/em-mi-electric-brasil-internal.apk`, **1.2.4/código 7**, pacote `br.com.mielectric.rmconnect`, ARM64/x86_64, **68.982.012 bytes**, SHA256 `7ab57b1b1b5ccf02a8f0430e3dbbf5b7e5961c446e7298c1ebba3c94d6074b66`. Mesmo certificado SHA256 `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`, com assinatura Android Debug para homologação interna. Assets verificaram o novo runtime QR e apenas a configuração pública do Supabase autorizado, sem os segredos locais conhecidos ou JWT de serviço. O instalador anterior foi conservado em backup ignorado pelo Git.

**Nenhum dispositivo foi instalado, desinstalado, limpo ou alterado. Não houve homologação óptica em câmera/tablet físico nesta rodada.** Atualizar uma instalação existente exige o mesmo pacote/certificado e instalação de atualização, sem desinstalar ou limpar dados. A geração/verificação do APK e os testes automatizados não substituem essa homologação. Uma revogação remota ainda não sincronizada não pode ser conhecida offline; as guardas do servidor continuam controlando mutações após reconexão.

**Próxima prioridade:** reconciliar o catálogo real de Templates Word e seus contratos de geração antes de implementar relatórios individuais/técnicos/fotográficos e compilação durável. Não declarar geração concluída enquanto as APIs retornarem 501 ou não houver arquivo real autorizado. Exclusões, compartilhamento com cliente, cadastros complementares, capacidade/calendários/lotes, comercial, laboratório e coexistência permanecem no plano; a paridade global continua em andamento.

[Contrato](WEB_PROJECT_QR.md) e [discovery Live](../docs/discovery_rmmi_qr_projeto.md). Provas locais ignoradas: `project-qr-release-proof.json`, `project-qr-ci-proof.json`, `project-qr-deployment.json`, `project-qr-public-qa.json`, `public-sso-qa.json`, `project-qr-qa-summary.json`, `project-qr-browser-secret-audit.json`, `project-qr-apk-proof.json`, `project-qr-apk-baseline.json`, `project-qr-db-before.json`, `project-qr-db-after.json`, `project-qr-environment-check.json` e logs `project-qr-{desktop-tests,mobile-tests,build,smoke,sso-smoke}.log`; provas nativas em `mobile/.tmp/em-124-*`.

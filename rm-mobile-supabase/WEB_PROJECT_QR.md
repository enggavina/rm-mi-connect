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

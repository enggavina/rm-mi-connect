# Instruções de trabalho do EM

- O aplicativo mobile mantém login e senha, sem SSO. O SSO Microsoft é do portal web. A oficina será determinada pela integração com Acessos, sem seletor no login, preservando identidades tablet/operador e filas offline.
- Informar sempre o percentual de conclusão, identificando escopo e denominador. Não estimar uma porcentagem global do software sem uma base; distinguir pacote atual, itens integralmente concluídos do backlog e homologação pendente.

- Após cada desenvolvimento, executar a validação adequada e publicar em produção, conforme autorização permanente do usuário em 29/10/2026. Não pedir nova confirmação de deploy; confirmar o resultado e o endereço publicado. Se uma validação falhar, corrigir antes de publicar.
- O destino é o portal Railway EM e o Supabase `oficina-em-mi-off`. Os detalhes de ambiente e publicação ficam em `desktop/docs/web-platform.md`; não atingir serviços de outros sistemas.
- `mgavina@mielectric.com.br` e `softdev05@mielectric.com.br` são administradores do EM, por autorização explícita. Esse papel não autoriza administração global da Central de Acessos, Microsoft ou outros aplicativos. Preservar as identidades legadas do tablet/mobile.
- O Bubble `rmmi` é referência somente para leitura nesta recriação. A ponte de saída permanece desativada até uma entrega explícita de coexistência.
- Preservar respostas, projetos e trabalhos offline existentes. Não editar migrações já aplicadas, não usar dados artificiais em produção e não publicar segredos dos arquivos `.env`.

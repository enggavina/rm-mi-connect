# Clientes e tipos com oficina validada — O09 / 057

Escopo: `save_catalog` e `delete_catalog`, somente `clients` e `types` no portal web. A oficina vem do contexto v2 atual de Acessos, após SSO corporativo, identidade RM, MFA e capacidade `em.catalogs.manage`. Não há oficina enviada pelo navegador, seletor no login, nova capacidade ou concessão global. Mobile mantém senha e filas existentes.

O BFF retém a sessão corporativa verificada em um WeakMap ligado ao objeto da requisição; nenhum Bearer é acrescentado ao contexto serializável. Cada ação protegida consulta novamente o endereço HTTPS fixo de Acessos, sem cache positivo, redirect ou fallback. Falhas apresentam orientação sanitizada e conservam o protocolo da tentativa. O leitor também valida versão, autoridade, aplicação, canal, oficina ativa, identidade exata, revisões, tamanho e validade.

A RPC exclusiva do servidor confere o contexto, o vínculo e a sessão SSO reais. Emite a autorização normal existente e uma confirmação adicional de oficina, ambas limitadas a quinze segundos e vinculadas ao mesmo protocolo, sessão, operação e hash do corpo. A confirmação não concede capacidades. Sua renovação mantém a oficina original do protocolo; intenção já iniciada não migra silenciosamente após transferência na Central. Não se publica a sessão corporativa no banco ou navegador.

A função pública existente mantém OID, proprietário, grants e as regras de SSO/MFA; somente seu despacho final passa pelo novo auxiliar privado. O core anterior continua validando perfis, campos, dependências, versão otimista e recibos. Para registros conhecidos, edição/exclusão exige a mesma oficina. Registros existentes sem origem comprovada ficam pendentes; não são adotados automaticamente. A criação de um UUID novo grava registro e propriedade na mesma transação. Falha na classificação ou expiração durante uma espera reverte também registro e recibo. Exclusão conserva a origem durável da 056; replay concluído exige autorização nova e a mesma oficina.

Os locks seguem vínculo → sessão → autorizações; a classificação usa o mesmo lock exclusivo por raiz de catálogo da 056. Logout remove os dois tipos de autorização. A guarda revalida expiração após o core, inclusive após espera. As tabelas novas têm RLS sem acesso direto dos clientes, incluindo service_role; somente a RPC de emissão é executável pelo servidor. Não há nova FK para registros de negócio que interfira na exclusão de projetos.

## Publicação gradual

A 057 instala a exigência desativada. O novo BFF já solicita confirmação e classifica seus novos registros nessa fase. Após validação, aplicação do schema, publicação bem-sucedida do consumidor e conferência do endereço público, o proprietário técnico executa `rm_private.activate_catalog_workshop_writes_v1(commit,deployment)`. A ativação exige SSO obrigatório, recibo de adoção dos catálogos e nenhum cliente/tipo atual sem propriedade. Registra commit, deployment, instante e executor técnico reais; não simula uma pessoa ou login. Replay somente para o mesmo par commit/deployment.

Depois de ativada, a autorização v1 sozinha não permite essas duas escritas; clientes antigos devem usar o BFF atualizado. Reverter a interface exige planejar o consumidor compatível, mantendo propriedade, recibos e tombstones. Não apagar dados ou liberar oficina por padrão para contornar falha de contexto. A flag privada não pode ser alterada pelo portal ou pela chave de runtime.

## Limites

Esta guarda não entrega isolamento de leitura. Consultas, buscas, contagens, exportações, Storage, modelos/rascunhos, demais cadastros e contexto offline continuam no backlog. BRJ/BBH permanecem inativas até isolamento e homologação completos. Cadastros ainda conservam as regras globais de duplicidade do core anterior; não se afirma criação de nomes iguais em oficinas distintas nesta entrega. Não há novo APK, autenticação mobile SSO, classificação de filas antigas ou teste artificial em produção.

## Validação reproduzível

- `npm run typecheck` e `npm test` em `desktop`, build e smokes standalone.
- `powershell -NoProfile -File rm-mobile-supabase/tests/run-local-tests.ps1 -WorkshopInventory`.
- `python rm-mobile-supabase/scripts/test_catalog_writes_local.py`: PostgreSQL descartável, contrato transacional, três disputas reais, manifesto e dez alterações indevidas recusadas pelo envelope de preservação.
- `prepare_catalog_writes_release.py` gera SQL offline com hashes obrigatórios e rollback por padrão. Confere dados anteriores, Auth/Storage, OIDs/ACLs/corpos de funções, única substituição exata de despacho, papéis, políticas, índices e histórico. Nenhuma migração aplicada é editada.

Dados sintéticos somente no banco descartável. Os testes públicos de produção verificam recusas, saúde e início SSO; não substituem login humano nem uma criação real feita pela equipe.

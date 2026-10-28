# EM — Relatórios — Fase 2

Pontos de entrada reservados em `/api/reports/generate-pdf` e `/api/reports/compile-s3` retornam HTTP 501 após autenticação. Implementar templates DOCX, composição PDF, Storage/S3 e fila de jobs usando os contratos de `rm-mobile-supabase/blueprint/01_integracoes_render_n8n_s3_contratos.md`. Nenhuma chamada é encaminhada automaticamente aos serviços Render existentes.

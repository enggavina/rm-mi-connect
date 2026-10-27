# Auth — Fase 2

O mobile usa Supabase Auth e delegação de operador. `/api/auth/totp` está reservado para a migração dos contratos TOTP legados e retorna 501; não aceita segredos nem verifica tokens na Fase 1. Preferir o MFA nativo do Supabase na aplicação desktop.

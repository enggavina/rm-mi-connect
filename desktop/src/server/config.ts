import { createClient } from '@supabase/supabase-js';

export function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Configuração ausente: ${name}`);
  return value;
}
export function adminClient() {
  return createClient(required('SUPABASE_URL'), required('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
export function bridgeConfig() {
  const baseUrl = new URL(required('BUBBLE_API_BASE_URL'));
  if (baseUrl.protocol !== 'https:' || baseUrl.username || baseUrl.password) throw new Error('BUBBLE_API_BASE_URL deve ser HTTPS.');
  const endpointOverrides: Record<string, string> = JSON.parse(process.env.BUBBLE_ENDPOINT_OVERRIDES || '{}');
  for (const value of Object.values(endpointOverrides)) if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]+$/.test(value)) throw new Error('BUBBLE_ENDPOINT_OVERRIDES inválido.');
  return {
    baseUrl: baseUrl.toString().replace(/\/+$/, ''),
    token: required('BUBBLE_API_TOKEN'),
    syncIdField: process.env.BUBBLE_SYNC_ID_FIELD || 'supabase_id',
    webhookAllowlist: (process.env.SYNC_WEBHOOK_ALLOWLIST || '').split(',').map(v => v.trim()).filter(Boolean),
    webhookToken: process.env.N8N_WEBHOOK_TOKEN,
    endpointOverrides,
  };
}

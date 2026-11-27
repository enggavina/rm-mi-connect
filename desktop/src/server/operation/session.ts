import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';
import { cookies } from 'next/headers';
import { z } from 'zod';
import { required } from '../config';
import { createWorkshopContextReader, EM_IDENTITY_ISSUER, WorkshopContextError } from '../web/workshop-context';
import { resolveWorkshopMedia, workshopMediaMatch } from '../web/workshop-media';
import { OPERATION_COOKIE, type OperationSelection } from './policy';
import { createOperationService } from './service';
import type { NativeMediaUpload } from './media-upload-policy';

function operationClient(privileged = false, token?: string) {
  const url = required('SUPABASE_URL');
  if (`${url}/auth/v1` !== EM_IDENTITY_ISSUER) throw new Error('Serviço operacional indisponível.');
  return createClient(url, required(privileged ? 'EM_SSO_BRIDGE_SERVICE_ROLE_KEY' : 'SUPABASE_ANON_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      ...(token ? { headers: { Authorization: `Bearer ${token}` } } : {}),
      fetch: (input, init) => fetch(input, { ...init, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10_000) }),
    },
  });
}

export const operationService = createOperationService({
  async signIn(email, password) {
    const { data, error } = await operationClient().auth.signInWithPassword({ email, password });
    if (error) {
      if ([400, 401, 403, 422, 429].includes(error.status ?? 0)) return null;
      throw new Error('Autenticação operacional indisponível.');
    }
    return data.session?.access_token ?? null;
  },
  async verify(token) {
    const { data, error } = await operationClient().auth.getUser(token);
    if (error && ![400, 401, 403, 422].includes(error.status ?? 0)) throw new Error('Autenticação operacional indisponível.');
    return !error && data.user ? {
      id: data.user.id, requiresMfa: (data.user.factors ?? []).some(factor => factor.status === 'verified'),
    } : null;
  },
  async identify(token, matricula, password) {
    return await operationClient(false, token).rpc('rm_authenticate_operator_v1', {
      p_matricula: matricula, p_palavra_chave: password, p_local: 'EM Operacional Web',
    });
  },
  async readIdentity(args) {
    return await operationClient(true).rpc('rm_online_operator_identity_v1', args);
  },
  async readWorkshop(identity, expiresAt) {
    return await createWorkshopContextReader().readMobile(identity, expiresAt, required('EM_WORKSHOP_CONTEXT_TOKEN'));
  },
  async readData(args) {
    const rpc = 'p_form_id' in args ? 'rm_online_operation_form_entry_v1' : 'rm_online_operation_read_v1';
    return await operationClient(true).rpc(rpc, args);
  },
  async writeForm(args) {
    return await operationClient(true).rpc('rm_online_operation_submit_form_v1', args);
  },
  async signOut(token) {
    const { error } = await operationClient().auth.admin.signOut(token, 'local');
    if (error) throw new Error('Encerramento operacional indisponível.');
  },
});

export async function loadOperation(selection: OperationSelection = {}) {
  return operationService.load((await cookies()).get(OPERATION_COOKIE)?.value, selection);
}

export async function sendNativeReceiving(token: string, operatorToken: string, submission: string,
  phase: 'open' | 'complete', payload: Record<string, unknown>, workshopOrigin?: string) {
  const scope = await operationService.authorizeNativeOperation(token, operatorToken, workshopOrigin);
  const input = { p_client_submission_id: submission, p_phase: phase, p_params: payload, p_operator_token: operatorToken };
  const permit = await operationClient(true).rpc('rm_authorize_mobile_receiving_workshop_v1', { ...scope, ...input });
  if (permit.error) return permit;
  return await operationClient(false, token).rpc('rm_mobile_receiving_workshop_v1', input);
}

export async function sendNativeWorkshopMutation(token: string, operatorToken: string, submission: string,
  operation: string, payload: Record<string, unknown>, workshopOrigin?: string) {
  const scope = await operationService.authorizeNativeOperation(token, operatorToken, workshopOrigin);
  const input = { p_client_submission_id: submission, p_rpc_name: operation, p_params: payload, p_operator_token: operatorToken };
  const permit = await operationClient(true).rpc('rm_authorize_mobile_workshop_mutation_v1', { ...scope, ...input });
  if (permit.error) return permit;
  return await operationClient(false, token).rpc('rm_mobile_workshop_mutate_v1', input);
}

export async function loadNativeCatalogPage(token: string, operatorToken: string, table: string,
  after: { at: string; id: string } | null, idsOnly: boolean) {
  const scope = await operationService.authorizeNativeOperation(token, operatorToken);
  const { data, error } = await operationClient(true).rpc('rm_mobile_workshop_catalog_v1', {
    ...scope, p_table: table, p_after_at: after?.at ?? null, p_after_id: after?.id ?? null, p_ids_only: idsOnly,
  });
  if (error || !data || data.workshop_id !== scope.p_workshop_context.workshop.id || data.table !== table) return { data: null, error };
  return { data, error: null };
}

export async function loadNativeWorkshopExecution(token: string, operatorToken: string, workshopOrigin: string, allocation: string) {
  const scope = await operationService.authorizeNativeOperation(token, operatorToken, workshopOrigin);
  const { data, error } = await operationClient(true).rpc('rm_mobile_workshop_execution_v1', { ...scope, p_allocation_id: allocation });
  if (error) return { data: null, error };
  if (!data || data.workshop_id !== scope.p_workshop_context.workshop.id || data.snapshot?.allocation?.id !== allocation.toLowerCase()) {
    return { data: null, error: null };
  }
  return { data, error: null };
}

const mediaBatch = z.object({ workshop_id: z.uuid(), files: z.array(workshopMediaMatch).max(100) }).strict();

export async function loadNativeWorkshopMedia(token: string, operatorToken: string, urls: string[]) {
  const scope = await operationService.authorizeNativeOperation(token, operatorToken);
  const service = operationClient(true);
  const { data, error } = await service.rpc('rm_mobile_workshop_media_v1', { ...scope, p_urls: urls });
  if (error) return { data: null, error };
  const checked = mediaBatch.safeParse(data);
  if (!checked.success || checked.data.workshop_id !== scope.p_workshop_context.workshop.id) return { data: null, error: null };
  const files = await Promise.all([...new Set(urls)].map(async reference => {
    const matches = checked.data.files.filter(match => match.url === reference);
    for (const { source } of matches) {
      const url = await resolveWorkshopMedia(reference, required('SUPABASE_URL'), source, async (bucket, path) => {
        const { data, error } = await service.storage.from(bucket).createSignedUrl(path, 60);
        if (error && !('statusCode' in error && ['400', '404'].includes(String(error.statusCode)))) {
          throw new Error('Armazenamento indisponível.');
        }
        return data?.signedUrl;
      });
      if (url) return { reference, url };
    }
    return null;
  }));
  return { data: { workshop_id: checked.data.workshop_id, files: files.filter(file => file !== null) }, error: null };
}

export async function authorizeWorkshopMediaUpload(scope: Awaited<ReturnType<typeof operationService.authorizeNativeOperation>>,
  input: NativeMediaUpload, stored: boolean) {
  if (scope.p_workshop_context.workshop.id !== input.workshopOrigin) throw new WorkshopContextError('WORKSHOP_FORBIDDEN');
  return await operationClient(true).rpc('rm_mobile_workshop_upload_v1', { ...scope, p_workshop_origin: input.workshopOrigin,
    p_submission: input.submission, p_operation: input.operation, p_payload: input.payload, p_asset: input.asset, p_kind: input.kind,
    p_reference: input.reference, p_mime: input.mime, p_size: input.size, p_sha256: input.sha256, p_mark_stored: stored });
}

export async function sendNativeReceivingDraft(token: string, operatorToken: string, workshopOrigin: string, args: Record<string, unknown>) {
  const scope = await operationService.authorizeNativeOperation(token, operatorToken, workshopOrigin);
  const request = { p_request_id: randomUUID(), p_args: args, p_operator_token: operatorToken };
  const permit = await operationClient(true).rpc('rm_authorize_receiving_draft_workshop_v1', { ...scope, ...request });
  if (permit.error) return permit;
  return await operationClient(false, token).rpc('rm_mobile_receiving_draft_workshop_v1', request);
}

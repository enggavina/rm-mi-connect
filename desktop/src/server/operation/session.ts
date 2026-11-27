import { createClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { required } from '../config';
import { createWorkshopContextReader, EM_IDENTITY_ISSUER } from '../web/workshop-context';
import { OPERATION_COOKIE, type OperationSelection } from './policy';
import { createOperationService } from './service';

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
  phase: 'open' | 'complete', payload: Record<string, unknown>) {
  const scope = await operationService.authorizeNativeReceiving(token, operatorToken);
  const input = { p_client_submission_id: submission, p_phase: phase, p_params: payload, p_operator_token: operatorToken };
  const permit = await operationClient(true).rpc('rm_authorize_mobile_receiving_workshop_v1', { ...scope, ...input });
  if (permit.error) return permit;
  return await operationClient(false, token).rpc('rm_mobile_receiving_workshop_v1', input);
}

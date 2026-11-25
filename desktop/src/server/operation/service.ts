import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { OnlineFormSubmission } from '../../shared/online-form';
import { openSso, sealSso } from '../web/sso-crypto';
import { WorkshopContextError, type ExpectedWorkshopIdentity, type WorkshopContext } from '../web/workshop-context';
import { formVersion, openOperationSession, operationClaims, operationData, operationQuery, operatorToken, sealOperationSession,
  type OperationCredentials, type OperationData, type OperationSelection, type OperationSession } from './policy';

type Reply = { data: unknown; error: { code?: string; status?: number } | null };
type MobileIdentity = Extract<ExpectedWorkshopIdentity, { channel: 'mobile' }>;
type OperationDeps = {
  signIn: (email: string, password: string) => Promise<string | null>;
  verify: (token: string) => Promise<{ id: string; requiresMfa: boolean } | null>;
  identify: (token: string, matricula: string, password: string) => Promise<Reply>;
  readIdentity: (args: IdentityParams) => Promise<Reply>;
  readWorkshop: (identity: MobileIdentity, expiresAt: number) => Promise<WorkshopContext>;
  readData: (args: IdentityParams & { p_workshop_context: WorkshopContext } & (
    { p_cell_id: string | null; p_project_id: string | null; p_page: number } |
    { p_cell_id: string; p_project_id: string; p_form_id: string }
  )) => Promise<Reply>;
  writeForm: (args: IdentityParams & { p_workshop_context: WorkshopContext; p_cell_id: string; p_project_id: string;
    p_form_id: string; p_protocol: string; p_version: string; p_answers: OnlineFormSubmission['answers'] }) => Promise<Reply>;
  signOut: (token: string) => Promise<void>;
  now?: () => number;
  cookieKey?: string;
};
type IdentityParams = { p_auth_user_id: string; p_session_id: string; p_operator_token: string };
export type OperationResult =
  | { status: 'session' | 'forbidden' | 'unavailable' | 'missing' }
  | { status: 'ok'; workshop: { name: string; code: string }; operatorName: string; data: OperationData; submissionProof?: string };
export type FormSubmissionResult =
  | { status: 'session' | 'forbidden' | 'invalid' | 'changed' | 'conflict' | 'unavailable' }
  | { status: 'ok'; code: string };
const formScope = z.object({ device: z.uuid(), operator: z.uuid(), office: z.uuid(), cell: z.uuid(), project: z.uuid(),
  form: z.uuid(), version: formVersion, protocol: z.uuid() }).strict();
const receipt = z.object({ registro_formulario_id: z.uuid(), codigo_text: z.string().regex(/^\d{1,12}$/) });
const loginIdentity = z.object({ authenticated: z.literal(true), operator_token: operatorToken });
const operatorIdentity = z.object({
  device_subject: z.string().uuid(), operator_subject: z.string().uuid(),
  operator_name: z.string().min(1).max(250), expires_at: z.iso.datetime({ offset: true }),
}).strict();
const sessionLimit = 60 * 60_000;

function identityError(code?: string) {
  return new WorkshopContextError(code === '42501' || code === '28000' || code === '28P01'
    ? 'WORKSHOP_UNAUTHORIZED' : 'WORKSHOP_UNAVAILABLE');
}

export function createOperationService(deps: OperationDeps) {
  const now = deps.now ?? Date.now;
  const invalid = () => new WorkshopContextError('WORKSHOP_UNAUTHORIZED');

  async function verifiedClaims(token: string) {
    const user = await deps.verify(token);
    if (!user) throw invalid();
    const claims = operationClaims(token, user.id, now());
    if (!claims || (user.requiresMfa && claims.aal !== 'aal2')) throw invalid();
    return claims;
  }

  async function authority(claims: Awaited<ReturnType<typeof verifiedClaims>>, delegation: string, sessionExpiresAt: number) {
    if (sessionExpiresAt <= now()) throw invalid();
    const args = { p_auth_user_id: claims.authUserId, p_session_id: claims.sessionId, p_operator_token: delegation };
    const reply = await deps.readIdentity(args);
    if (reply.error) throw identityError(reply.error.code);
    if (reply.data === null) throw invalid();
    const parsed = operatorIdentity.parse(reply.data);
    if (parsed.device_subject !== claims.authUserId) throw invalid();
    const expiresAt = Math.min(claims.expiresAt, sessionExpiresAt, Date.parse(parsed.expires_at));
    if (!Number.isFinite(expiresAt) || expiresAt <= now()) throw invalid();
    const workshop = await deps.readWorkshop({
      channel: 'mobile', deviceSubject: parsed.device_subject, operatorSubject: parsed.operator_subject,
    }, expiresAt);
    if (expiresAt <= now()) throw invalid();
    return { workshop, args, operator: parsed.operator_subject, operatorName: parsed.operator_name, expiresAt };
  }

  return {
    async login(input: OperationCredentials): Promise<{ envelope: string; maxAge: number }> {
      const token = await deps.signIn(input.email, input.password);
      if (!token) throw invalid();
      try {
        const claims = await verifiedClaims(token);
        const reply = await deps.identify(token, input.matricula, input.palavra_chave);
        if (reply.error) throw identityError(reply.error.code);
        if (reply.data && typeof reply.data === 'object' && 'authenticated' in reply.data && reply.data.authenticated === false) throw invalid();
        const identity = loginIdentity.parse(reply.data);
        const { expiresAt } = await authority(claims, identity.operator_token, now() + sessionLimit);
        return {
          envelope: sealOperationSession({ token, operatorToken: identity.operator_token, expiresAt }, deps.cookieKey),
          maxAge: Math.max(0, Math.floor((expiresAt - now()) / 1000)),
        };
      } catch (error) {
        await deps.signOut(token).catch(() => undefined);
        throw error;
      }
    },
    async load(envelope: string | undefined, selection: OperationSelection): Promise<OperationResult> {
      const saved = openOperationSession(envelope, now(), deps.cookieKey);
      if (!saved) return { status: 'session' };
      const query = operationQuery(selection);
      if (!query) return { status: 'missing' };
      try {
        const claims = await verifiedClaims(saved.token);
        const access = await authority(claims, saved.operatorToken, saved.expiresAt);
        const { workshop } = access;
        const reply = await deps.readData({
          ...access.args, p_workshop_context: workshop, ...(query.formId
            ? { p_cell_id: query.cellId, p_project_id: query.projectId, p_form_id: query.formId }
            : { p_cell_id: query.cellId, p_project_id: query.projectId, p_page: query.page }),
        });
        if (reply.error) throw reply.error.code === '42501' || reply.error.code === 'PT403'
          ? new WorkshopContextError('WORKSHOP_FORBIDDEN') : identityError(reply.error.code);
        const data = operationData(reply.data, query);
        if (!data) return { status: 'missing' };
        const submissionProof = data.kind === 'form' && data.edition && workshop.workshop.code === 'BMA'
          ? sealSso(formScope.parse({ device: claims.authUserId, operator: access.operator, office: workshop.workshop.id,
            cell: data.cell.id, project: data.project.id, form: data.form.id, version: data.edition.version, protocol: randomUUID() }),
          'operation-form', deps.cookieKey)
          : undefined;
        return { status: 'ok', workshop: { name: workshop.workshop.name, code: workshop.workshop.code },
          operatorName: access.operatorName, data, ...(submissionProof && { submissionProof }) };
      } catch (error) {
        if (error instanceof WorkshopContextError) {
          if (error.status === 401) return { status: 'session' };
          if (error.status === 403) return { status: 'forbidden' };
        }
        return { status: 'unavailable' };
      }
    },
    async submitForm(envelope: string | undefined, selection: OperationSelection, input: OnlineFormSubmission): Promise<FormSubmissionResult> {
      const saved = openOperationSession(envelope, now(), deps.cookieKey);
      if (!saved) return { status: 'session' };
      const query = operationQuery(selection);
      if (!query?.formId) return { status: 'invalid' };
      let scope: z.infer<typeof formScope>;
      try {
        scope = formScope.parse(openSso(input.proof, 'operation-form', deps.cookieKey));
      } catch {
        return { status: 'forbidden' };
      }
      if (scope.cell !== query.cellId || scope.project !== query.projectId || scope.form !== query.formId) {
        return { status: 'forbidden' };
      }
      try {
        const claims = await verifiedClaims(saved.token);
        const access = await authority(claims, saved.operatorToken, saved.expiresAt);
        if (scope.device !== claims.authUserId || scope.operator !== access.operator
          || scope.office !== access.workshop.workshop.id || access.workshop.workshop.code !== 'BMA') return { status: 'forbidden' };
        const result = await deps.writeForm({ ...access.args, p_workshop_context: access.workshop, p_cell_id: scope.cell,
          p_project_id: scope.project, p_form_id: scope.form, p_protocol: scope.protocol, p_version: scope.version, p_answers: input.answers });
        if (!result.error) return { status: 'ok', code: receipt.parse(result.data).codigo_text };
        switch (result.error.code) {
          case '28000': return { status: 'session' };
          case '42501': case 'PT403': case 'PT410': return { status: 'forbidden' };
          case 'PT412': return { status: 'changed' };
          case 'PT409': return { status: 'conflict' };
          case '22023': case '22007': case '22008': case 'PT422': return { status: 'invalid' };
          default: return { status: 'unavailable' };
        }
      } catch (error) {
        if (error instanceof WorkshopContextError) {
          if (error.status === 401) return { status: 'session' };
          if (error.status === 403) return { status: 'forbidden' };
        }
        return { status: 'unavailable' };
      }
    },
    async logout(envelope: string | undefined): Promise<void> {
      const saved: OperationSession | null = openOperationSession(envelope, now(), deps.cookieKey);
      if (!saved) return;
      await verifiedClaims(saved.token);
      await deps.signOut(saved.token);
    },
  };
}

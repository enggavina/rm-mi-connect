import { z } from 'zod';
import { CORPORATE_CAPABILITIES, CORPORATE_ISSUER } from './sso-policy';

const uuid = z.string().uuid();
export const ssoBindingSchema = z.object({
  binding_id: uuid, auth_user_id: uuid, rm_user_id: uuid,
  profile: z.object({ id: uuid, nome: z.string().max(500), perfil: z.enum(['administrador', 'padr_o', 'auditor']),
    cargo: z.string().nullable().optional(), matricula: z.string().nullable().optional() }),
}).refine(value => value.profile.id === value.rm_user_id);
const corporateSchema = z.object({
  accessToken: z.string().min(50).max(16_384),
  user: z.object({ id: uuid, email: z.email().max(254), nome: z.string().max(200).optional() }),
  expiresAt: z.number().finite(),
  decision: z.object({ application: z.literal('em'), issuer: z.literal(CORPORATE_ISSUER), subject: uuid,
    app_access: z.literal(true), capabilities: z.array(z.enum(CORPORATE_CAPABILITIES)).max(11),
    all_employees: z.literal(false), fields: z.tuple([]), export_allowed: z.literal(false) }),
}).refine(value => value.user.id === value.decision.subject);
export const ssoSessionSchema = z.object({
  corporate: corporateSchema, localToken: z.string().min(50).max(32_768), binding: ssoBindingSchema,
  localSessionId: uuid, expiresAt: z.number().finite(),
}).refine(value => value.expiresAt <= value.corporate.expiresAt);
const pending = { factors: z.array(z.object({ id: uuid, name: z.string().min(1).max(100) })).min(1).max(10),
  expiresAt: z.number().finite(), attempts: z.number().int().min(0).max(5) };
export const ssoFlowSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('oauth'), expiresAt: z.number().finite(), flow: z.object({
    entries: z.array(z.tuple([z.string().max(128), z.string().max(1024)])).min(1).max(8),
    flowId: z.string().regex(/^[A-Za-z0-9_-]{8,64}$/), startedAt: z.number().finite(),
  }) }),
  z.object({ kind: z.literal('corporate-mfa'), corporate: corporateSchema, ...pending }),
  z.object({ kind: z.literal('local-mfa'), contents: ssoSessionSchema, ...pending }),
]);

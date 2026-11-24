import { CorporateAuthError, type CorporateCapability, type VerifiedCorporateSession } from './sso-policy';
import type { SsoContext } from './auth-policy';
import { createWorkshopContextReader, type WorkshopContext } from './workshop-context';
import { workshopReadCapabilities, type WorkshopReadResource } from './workshop-read-policy';

export function isScopedCatalogWrite(operation: string, payload: Record<string, unknown>): boolean {
  return ['save_catalog', 'delete_catalog'].includes(operation) && typeof payload.kind === 'string' && ['clients', 'types'].includes(payload.kind);
}

export function isScopedTemplateWrite(operation: string): boolean {
  return ['create_form_template', 'save_form_template', 'publish_form_template', 'delete_form_template'].includes(operation);
}

/** Request objects, not serializable session fields, retain the verified bearer.
 * The bridge calls remember only after current corporate/local SSO and MFA.
 * There is no cross-request positive decision cache or new browser credential. */
export function createCatalogWorkshopAuthorizer({ reader = createWorkshopContextReader(), mint, mintRead }: {
  reader?: Pick<ReturnType<typeof createWorkshopContextReader>, 'readWeb'>;
  mint: (args: { sessionHash: string; submissionId: string; operation: string; payload: Record<string, unknown>; context: WorkshopContext }) => Promise<void>;
  mintRead?: (args: { sessionHash: string; requestId: string; resource: WorkshopReadResource; filters: Record<string, unknown>; context: WorkshopContext }) => Promise<void>;
}) {
  const verified = new WeakMap<SsoContext, VerifiedCorporateSession>();
  return {
    remember(context: SsoContext, corporate: VerifiedCorporateSession) {
      if (corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      verified.set(context, corporate);
    },
    async authorizeRead(context: SsoContext, requestId: string, resource: WorkshopReadResource, filters: Record<string, unknown>) {
      if (!workshopReadCapabilities(resource, filters).every(capability => context.capabilities.includes(capability))
        || resource === 'project_entry' && filters.cells === true
          && !context.capabilities.some(capability => capability === 'em.planning.read' || capability === 'em.history.read')) throw new CorporateAuthError('CORP_FORBIDDEN');
      const corporate = verified.get(context);
      if (!mintRead || !corporate || corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      const workshop = await reader.readWeb(corporate);
      await mintRead({ sessionHash: context.sessionHash, requestId, resource, filters, context: workshop });
      return workshop.workshop.id;
    },
    async authorize(context: SsoContext, submissionId: string, operation: string, payload: Record<string, unknown>, capability: CorporateCapability) {
      const expected = isScopedTemplateWrite(operation) ? 'em.form_templates.manage'
        : isScopedCatalogWrite(operation, payload) ? 'em.catalogs.manage' : null;
      if (!expected) return false;
      if (capability !== expected || !context.capabilities.includes(capability)) throw new CorporateAuthError('CORP_FORBIDDEN');
      const corporate = verified.get(context);
      if (!corporate || corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      const workshop = await reader.readWeb(corporate);
      await mint({ sessionHash: context.sessionHash, submissionId, operation, payload, context: workshop });
      return true;
    },
  };
}

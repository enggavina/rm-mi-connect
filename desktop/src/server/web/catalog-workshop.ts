import { CorporateAuthError, type CorporateCapability, type VerifiedCorporateSession } from './sso-policy';
import type { SsoContext } from './auth-policy';
import { ASSIGNMENT_TEAM_CAPABILITIES, createWorkshopContextReader, type AssignmentPurpose, type WorkshopContext, type WorkshopTeam } from './workshop-context';
import { assignmentRosterPurpose, workshopReadCapabilities, workshopRosterRequired, type WorkshopReadResource } from './workshop-read-policy';

export function isScopedCatalogWrite(operation: string, payload: Record<string, unknown>): boolean {
  return ['save_catalog', 'delete_catalog'].includes(operation) && typeof payload.kind === 'string' && ['clients', 'types'].includes(payload.kind);
}

export function isScopedTemplateWrite(operation: string): boolean {
  return ['create_form_template', 'save_form_template', 'publish_form_template', 'delete_form_template'].includes(operation);
}

export function rootWriteCapability(operation: string, payload: Record<string, unknown>, includeEdits = false): CorporateCapability | null {
  if (operation === 'delete_catalog' && payload.kind === 'cells') return 'em.catalogs.manage';
  if (includeEdits && ['save_project', 'save_project_equipment', 'delete_project'].includes(operation)) return 'em.projects.manage';
  if (includeEdits || payload.expected_updated_at === null) {
    if (operation === 'save_project_with_equipment') return 'em.projects.manage';
    if (operation === 'save_catalog' && payload.kind === 'cells') return 'em.catalogs.manage';
  }
  return null;
}

export function isScopedPlanningWrite(operation: string): boolean {
  return ['save_gantt_plan', 'save_gantt_settings', 'plan_cell', 'save_project_route',
    'assign_form_reviewer'].includes(operation);
}

export function requiresPlanningWorkshop(operation: string): boolean {
  return ['save_capacity_resource', 'save_capacity_bookings', 'manage_cell_availability', 'manage_project_route_cell',
    'save_cell_queue', 'review_execution_session'].includes(operation);
}

export function isScopedEngineeringWrite(operation: string): boolean {
  return ['save_engineering', 'save_photo_title', 'delete_photo_title'].includes(operation);
}

export function workshopReviewCapability(operation: string): CorporateCapability | null {
  if (operation === 'review_form') return 'em.forms.review';
  if (operation === 'transition_stage_approval') return 'em.approvals.decide';
  return null;
}

export function assignmentWritePurpose(operation: string, payload: Record<string, unknown>): AssignmentPurpose | undefined {
  const changes = payload.changes as Record<string, unknown> | null | undefined;
  if (['save_project', 'save_project_with_equipment'].includes(operation) && typeof changes?.gestor_responsavel_id === 'string') return 'project';
  if (operation === 'save_engineering' && Array.isArray(changes?.stages) && changes.stages.length > 0) return 'engineering';
  if (operation === 'plan_cell' && typeof changes?.responsavel_id === 'string'
    || operation === 'assign_form_reviewer' && typeof payload.avaliador_user_id === 'string'
    || operation === 'manage_stage_rules' && ['create', 'replace', 'restore', 'retire'].includes(String(payload.action))) return 'planning';
  return undefined;
}

/** Request objects, not serializable session fields, retain the verified bearer.
 * The bridge calls remember only after current corporate/local SSO and MFA.
 * There is no cross-request positive decision cache or new browser credential. */
export function createCatalogWorkshopAuthorizer({ reader = createWorkshopContextReader(), mint, mintRead, mintAssignment, enableGanttWrites = false,
  enableRootEdits = false, enableFormReviewWrites = false }: {
  reader?: Pick<ReturnType<typeof createWorkshopContextReader>, 'readWeb'>
    & Partial<Pick<ReturnType<typeof createWorkshopContextReader>, 'readTeam'>>;
  mint: (args: { sessionHash: string; submissionId: string; operation: string; payload: Record<string, unknown>; context: WorkshopContext }) => Promise<void>;
  mintRead?: (args: { sessionHash: string; requestId: string; resource: WorkshopReadResource; filters: Record<string, unknown>; context: WorkshopContext }) => Promise<void>;
  mintAssignment?: (args: { sessionHash: string; submissionId: string; operation: string; payload: Record<string, unknown>; team: WorkshopTeam }) => Promise<void>;
  enableGanttWrites?: boolean;
  enableRootEdits?: boolean;
  enableFormReviewWrites?: boolean;
}) {
  const verified = new WeakMap<SsoContext, VerifiedCorporateSession>();
  return {
    remember(context: SsoContext, corporate: VerifiedCorporateSession) {
      if (corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      verified.set(context, corporate);
    },
    async authorizeRead(context: SsoContext, requestId: string, resource: WorkshopReadResource, filters: Record<string, unknown>) {
      if (workshopRosterRequired(resource, filters) || !workshopReadCapabilities(resource, filters).every(capability => context.capabilities.includes(capability))
        || resource === 'project_entry' && filters.cells === true
          && !context.capabilities.some(capability => capability === 'em.planning.read' || capability === 'em.history.read')) throw new CorporateAuthError('CORP_FORBIDDEN');
      const corporate = verified.get(context);
      if (!mintRead || !corporate || corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      const workshop = await reader.readWeb(corporate);
      await mintRead({ sessionHash: context.sessionHash, requestId, resource, filters, context: workshop });
      return workshop.workshop.id;
    },
    async authorizeTeamRead(context: SsoContext, requestId: string, filters: Record<string, unknown>, resource: WorkshopReadResource = 'workshop_team') {
      if (!workshopRosterRequired(resource, filters) || !workshopReadCapabilities(resource, filters).every(capability => context.capabilities.includes(capability))) {
        throw new CorporateAuthError('CORP_FORBIDDEN');
      }
      const corporate = verified.get(context);
      if (!mintRead || !reader.readTeam || !corporate || corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      const team = await reader.readTeam(corporate, assignmentRosterPurpose(resource, filters));
      const args = { ...filters, members: team.members };
      await mintRead({ sessionHash: context.sessionHash, requestId, resource, filters: args, context: team.context });
      return { args, office: team.context.workshop.id };
    },
    async authorize(context: SsoContext, submissionId: string, operation: string, payload: Record<string, unknown>, capability: CorporateCapability) {
      const expected = isScopedTemplateWrite(operation) ? 'em.form_templates.manage'
        : isScopedCatalogWrite(operation, payload) ? 'em.catalogs.manage'
        : isScopedEngineeringWrite(operation) ? 'em.engineering.manage'
        : requiresPlanningWorkshop(operation) || enableGanttWrites && isScopedPlanningWrite(operation) ? 'em.planning.manage'
        : (enableFormReviewWrites && workshopReviewCapability(operation)) || rootWriteCapability(operation, payload, enableRootEdits);
      const purpose = assignmentWritePurpose(operation, payload);
      if (!expected && !purpose) return false;
      if (expected && capability !== expected || purpose && capability !== ASSIGNMENT_TEAM_CAPABILITIES[purpose]
        || !context.capabilities.includes(capability)) throw new CorporateAuthError('CORP_FORBIDDEN');
      const corporate = verified.get(context);
      if (!corporate || corporate.user.id !== context.subject) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      let workshop: WorkshopContext | undefined;
      if (purpose) {
        if (!mintAssignment || !reader.readTeam) throw new CorporateAuthError('CORP_UNAVAILABLE');
        const team = await reader.readTeam(corporate, purpose);
        await mintAssignment({ sessionHash: context.sessionHash, submissionId, operation, payload, team });
        workshop = team.context;
      }
      if (!expected) return false;
      workshop ??= await reader.readWeb(corporate);
      await mint({ sessionHash: context.sessionHash, submissionId, operation, payload, context: workshop });
      return true;
    },
  };
}

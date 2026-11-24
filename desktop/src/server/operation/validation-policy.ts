import type { SsoContext, WebAccess } from '../web/auth-policy';
import { CorporateAuthError } from '../web/sso-policy';
import { WorkshopContextError } from '../web/workshop-context';
import { workshopReadCapabilities, type WorkshopRead } from '../web/workshop-read-policy';
import { operationData, operationQuery, type OperationSelection } from './policy';
import type { OperationResult } from './service';

type ValidationAuthState = WebAccess | { state: 'unconfigured' };
type ValidationAccess = Extract<WebAccess, { state: 'authenticated' }> & { sso: SsoContext };

const validationIdentity = {
  subject: 'a9e45880-1924-4b2d-a2b1-dc12fd029bff',
  bindingId: 'ae29e9a9-9c50-4d25-81eb-6a01202bc20a',
  profileId: '2e70c7e9-3ed2-47fa-9860-9501aeac96cc',
};

export function canUseOperationValidation(access: ValidationAuthState): access is ValidationAccess {
  if (access.state !== 'authenticated' || !access.sso) return false;
  const { sso, profile } = access;
  return sso.subject === validationIdentity.subject
    && sso.bindingId === validationIdentity.bindingId
    && profile.id === validationIdentity.profileId
    && profile.perfil === 'administrador'
    && workshopReadCapabilities('operation_validation').every(capability => sso.capabilities.includes(capability));
}

type ValidationDependencies = {
  authenticate: () => Promise<ValidationAuthState>;
  workshopRead: (access: ValidationAccess) => WorkshopRead;
};

export function createOperationValidationReader({ authenticate, workshopRead }: ValidationDependencies) {
  return async (selection: OperationSelection = {}): Promise<OperationResult> => {
    try {
      const access = await authenticate();
      if (access.state === 'unconfigured') return { status: 'unavailable' };
      if (access.state === 'anonymous' || access.state === 'mfa') return { status: 'session' };
      if (!canUseOperationValidation(access)) return { status: 'forbidden' };

      const query = operationQuery(selection);
      if (!query) return { status: 'missing' };
      const payload = await workshopRead(access)('operation_validation', {
        cell_id: query.cellId, project_id: query.projectId, page: query.page,
        ...(query.formId && { form_id: query.formId }),
      });
      const data = operationData(payload, query);
      if (!data) return { status: 'missing' };

      // The dedicated reader accepts only the authoritative context for BMA.
      return { status: 'ok', workshop: { name: 'BMA', code: 'BMA' }, operatorName: access.profile.nome, data };
    } catch (error) {
      if (error instanceof WorkshopContextError || error instanceof CorporateAuthError) {
        if (error.status === 401) return { status: 'session' };
        if (error.status === 403) return { status: 'forbidden' };
      }
      return { status: 'unavailable' };
    }
  };
}

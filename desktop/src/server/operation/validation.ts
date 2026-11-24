import { getWebAuthState } from '../web/auth';
import { ssoWorkshopRead } from '../web/sso-bridge';
import { createOperationValidationReader } from './validation-policy';

export { canUseOperationValidation } from './validation-policy';

export const loadOperationValidation = createOperationValidationReader({
  authenticate: getWebAuthState,
  workshopRead: access => ssoWorkshopRead(access.sso, access.client),
});

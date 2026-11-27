import { createAndroidPilotService } from './android-pilot-policy';
import { getWebAuthState } from './auth';
import { readSsoWorkshopContext, signAndroidPilotApk } from './sso-bridge';

export const androidPilot = createAndroidPilotService({
  authenticate: getWebAuthState,
  workshop: readSsoWorkshopContext,
  sign: signAndroidPilotApk,
});

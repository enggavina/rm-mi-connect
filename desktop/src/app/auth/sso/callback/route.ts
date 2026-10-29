import { beginSso, finishSso } from '@/server/web/sso-bridge';
import { corporateSettings } from '@/server/web/sso-policy';
import { createSsoHandlers } from '../handlers';

export const dynamic = 'force-dynamic';
export const GET = createSsoHandlers({ settings: corporateSettings, begin: beginSso, finish: finishSso }).callback;

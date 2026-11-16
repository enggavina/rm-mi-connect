import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from './sso-policy';
import { mapWorkshopSnapshot } from './workshop-policy';

export const WORKSHOP_CAPABILITIES: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read'];
export function createWorkshopData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  return {
    async getWorkshopSnapshot() {
      if (capabilities !== undefined && WORKSHOP_CAPABILITIES.some(capability => !capabilities.includes(capability))) {
        throw new Error('Acesso ao gêmeo digital não autorizado.');
      }
      let result;
      try { result = await client.rpc('rm_web_workshop_snapshot_v1'); }
      catch { throw new Error('Não foi possível consultar os dados da oficina.'); }
      if (result.error) throw new Error(result.error.code === 'PT413'
        ? 'O conjunto da oficina excedeu o limite de leitura completa.'
        : 'Não foi possível consultar os dados da oficina.');
      return mapWorkshopSnapshot(result.data);
    },
  };
}

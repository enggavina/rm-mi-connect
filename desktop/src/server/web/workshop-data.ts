import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from './sso-policy';
import { mapWorkshopSnapshot } from './workshop-policy';
import type { WorkshopRead } from './workshop-read-policy';

export const WORKSHOP_CAPABILITIES: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read'];
export function createWorkshopData(client: SupabaseClient, capabilities?: readonly CorporateCapability[], read?: WorkshopRead) {
  return {
    async getWorkshopSnapshot() {
      if (capabilities !== undefined && WORKSHOP_CAPABILITIES.some(capability => !capabilities.includes(capability))) {
        throw new Error('Acesso ao gêmeo digital não autorizado.');
      }
      if (read) {
        const data = await read('workshop_twin', {});
        if (data?.layout !== 'bma' && data?.layout !== 'management') throw new Error('A planta autorizada da oficina não pôde ser confirmada.');
        return { ...mapWorkshopSnapshot(data), layout: data.layout as 'bma' | 'management' };
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

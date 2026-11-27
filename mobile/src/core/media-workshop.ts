const destination = 'https://em-web-production.up.railway.app/api/mobile/midia';

export function workshopMediaCacheKey(workshopId: string, operatorId: string, reference: string) {
  return `workshop-media:${workshopId}:${operatorId}:${reference}`;
}

export async function readWorkshopMedia(session: { deviceToken: string; operatorToken: string; workshopId: string },
  urls: string[], supabaseOrigin: string, request = fetch): Promise<Map<string, string>> {
  const { deviceToken, operatorToken, workshopId } = session;
  const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const response = await request(destination, {
      method: 'POST', redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${deviceToken}` },
      body: JSON.stringify({ operatorToken, urls }),
    });
    if (!response.ok) throw new Error('Não foi possível confirmar os arquivos da oficina.');
    const data = await response.json();
    if (data?.workshop_id !== workshopId || !Array.isArray(data.files) || data.files.length > urls.length) {
      throw new Error('O retorno dos arquivos divergiu da oficina autorizada.');
    }
    const allowed = new Set(urls), found = new Map<string, string>();
    for (const item of data.files) {
      if (!allowed.has(item?.reference) || found.has(item.reference) || typeof item.url !== 'string') throw new Error('Arquivo divergente.');
      const address = new URL(item.url);
      if (address.protocol !== 'https:' || address.username || address.password || address.port || address.hash
        || !(address.hostname.endsWith('.cdn.bubble.io') || (address.origin === supabaseOrigin
          && /^\/storage\/v1\/object\/sign\/rm-(fotos|assinaturas|documentos)\//.test(address.pathname)
          && [...address.searchParams.keys()].length === 1 && address.searchParams.get('token')))) throw new Error('Endereço de arquivo inválido.');
      found.set(item.reference, address.href);
    }
    return found;
  } finally {
    clearTimeout(timeout);
  }
}

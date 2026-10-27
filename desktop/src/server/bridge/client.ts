import { allowedWebhook } from '../security';
import type { bridgeConfig } from '../config';
import type { Row } from './mapping';
export type Config = ReturnType<typeof bridgeConfig>;
export type Fetcher = typeof fetch;
export type Constraint = { key: string; constraint_type: string; value?: unknown };
export class BubbleClient {
  constructor(readonly config: Config, private fetcher: Fetcher = fetch) {}
  async request(path: string, init: RequestInit = {}) {
    path = path.replace(/^\/obj\/([^/?]+)/, (_match, endpoint: string) => `/obj/${encodeURIComponent(this.config.endpointOverrides[decodeURIComponent(endpoint)] || decodeURIComponent(endpoint))}`);
    const response = await this.fetcher(`${this.config.baseUrl}${path}`, {
      ...init, redirect: 'error', signal: AbortSignal.timeout(45_000),
      headers: { Authorization: `Bearer ${this.config.token}`, 'Content-Type': 'application/json', ...init.headers },
    });
    if (!response.ok) throw new Error(`Bubble ${init.method || 'GET'} ${path.split('?')[0]}: HTTP ${response.status}`);
    return response;
  }
  async get(endpoint: string, id: string): Promise<Row> {
    const body = await (await this.request(`/obj/${encodeURIComponent(endpoint)}/${encodeURIComponent(id)}`)).json();
    if (!body.response || typeof body.response !== 'object') throw new Error('Resposta Bubble inválida.');
    return { ...body.response, _id: id };
  }
  async *pages(endpoint: string, since: string, until: string, constraints: Constraint[] = []): AsyncGenerator<Row[]> {
    let cursor = 0;
    while (true) {
      const query = new URLSearchParams({ cursor: String(cursor), limit: '100', sort_field: 'Modified Date', descending: 'false', constraints: JSON.stringify([
        { key: 'Modified Date', constraint_type: 'greater than', value: since },
        { key: 'Modified Date', constraint_type: 'less than', value: until },
        ...constraints,
      ]) });
      const json = await (await this.request(`/obj/${encodeURIComponent(endpoint)}?${query}`)).json();
      const page = json.response;
      if (!page || !Array.isArray(page.results) || !Number.isFinite(page.remaining)) throw new Error('Página Bubble inválida.');
      if (!page.results.length && page.remaining > 0) throw new Error('Paginação Bubble sem progresso.');
      yield page.results as Row[];
      if (page.remaining <= 0) break;
      cursor += page.results.length;
    }
  }
  async write(endpoint: string, id: string | null, localId: string, body: Row): Promise<string> {
    if (!id) {
      // Query the stable local UUID BEFORE each create, including after a timeout.
      // Required Bubble text field ensures a lost POST response does not duplicate rows.
      const query = new URLSearchParams({ limit: '2', constraints: JSON.stringify([{ key: this.config.syncIdField, constraint_type: 'equals', value: localId }]) });
      const found = await (await this.request(`/obj/${encodeURIComponent(endpoint)}?${query}`)).json();
      const rows = found.response?.results;
      if (!Array.isArray(rows)) throw new Error('Consulta de chave de sincronização inválida.');
      if (rows.length > 1) throw new Error('Chave de sincronização duplicada no Bubble; exige reconciliação.');
      id = rows[0]?._id || null;
    }
    // Existing rows already have an unambiguous remote ID. They need no new field
    // (in particular stage/cell rows edited by the Phase 1 mobile).
    const payload = id ? body : { ...body, [this.config.syncIdField]: localId };
    const path = `/obj/${encodeURIComponent(endpoint)}${id ? `/${encodeURIComponent(id)}` : ''}`;
    const response = await this.request(path, { method: id ? 'PATCH' : 'POST', body: JSON.stringify(payload) });
    if (id) return id;
    const result = await response.json();
    if (typeof result.id !== 'string' || !result.id) throw new Error('Bubble não devolveu o ID criado; próximo retry fará reconciliação.');
    return result.id;
  }
  async webhook(url: string, body: unknown, eventId: string) {
    if (!allowedWebhook(url, this.config.webhookAllowlist)) throw new Error('Webhook fora de SYNC_WEBHOOK_ALLOWLIST.');
    const response = await this.fetcher(url, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45_000), headers: {
      'Content-Type': 'application/json', 'Idempotency-Key': eventId,
      ...(this.config.webhookToken ? { Authorization: `Bearer ${this.config.webhookToken}` } : {}),
    }, body: JSON.stringify(body) });
    if (!response.ok) throw new Error(`Webhook: HTTP ${response.status}`);
  }
}

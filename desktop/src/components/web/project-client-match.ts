export type ProjectClientChoice = { id: string; nome: string | null };
type Candidate = { client: ProjectClientChoice; tokens: string[] };
type Node = { children: Map<string, Node>; candidates: Candidate[] };
export type ProjectClientMatch = { kind: 'none' | 'ambiguous' } | { kind: 'match'; client: ProjectClientChoice };

/** Comparison only: the stored name and the selected client's UUID stay intact. */
export function projectClientNameTokens(value: string): string[] {
  return value.normalize('NFKD').replace(/\p{M}/gu, '').toLocaleLowerCase('pt-BR')
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim().split(/\s+/).filter(Boolean);
}
const node = (): Node => ({ children: new Map(), candidates: [] });
function containsTokens(container: string[], part: string[]): boolean {
  for (let at = 0; at <= container.length - part.length; at++) {
    if (part.every((token, index) => token === container[at + index])) return true;
  }
  return false;
}

/** Build once per already-loaded catalogue; each keystroke never fetches clients. */
export function createProjectClientMatcher(clients: readonly ProjectClientChoice[]) {
  const root = node();
  for (const client of clients) {
    if (!client.id || typeof client.nome !== 'string') continue;
    const tokens = projectClientNameTokens(client.nome); if (!tokens.length) continue;
    let current = root;
    for (const token of tokens) {
      let next = current.children.get(token);
      if (!next) { next = node(); current.children.set(token, next); }
      current = next;
    }
    // A repeated row with the same UUID is still the same real client.
    if (!current.candidates.some(candidate => candidate.client.id === client.id)) current.candidates.push({ client, tokens });
  }
  return (projectName: string): ProjectClientMatch => {
    const tokens = projectClientNameTokens(projectName), matches = new Map<string, Candidate>();
    for (let at = 0; at < tokens.length; at++) {
      let current = root;
      for (let end = at; end < tokens.length; end++) {
        const next = current.children.get(tokens[end]); if (!next) break;
        current = next;
        for (const candidate of current.candidates) matches.set(candidate.client.id, candidate);
      }
    }
    if (!matches.size) return { kind: 'none' };
    // Only a unique name containing ALL shorter matches is unambiguous.
    // Two unrelated clients in the same project name must be chosen manually.
    const values = [...matches.values()];
    const specific = values.filter(candidate => values.every(other => containsTokens(candidate.tokens, other.tokens)));
    return specific.length === 1 ? { kind: 'match', client: specific[0].client } : { kind: 'ambiguous' };
  };
}

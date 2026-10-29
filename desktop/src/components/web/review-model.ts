import type { WebRow } from '@/server/web/data';

export type ReviewAnswer = WebRow & { label: string; historical: boolean; canCorrect: boolean; itemLabels: string[] };
export type RecordSection = { id: string; title: string; description?: string; answers: ReviewAnswer[] };
export type ReviewRequest = {
  submissionId: string; registro_formulario_id: string; expected_updated_at: string;
  decision: 'approve' | 'return'; parecer: string; resposta_ids: readonly string[];
};

const order = (row: WebRow) => Number.isFinite(Number(row.indice)) ? Number(row.indice) : 0;
const text = (value: unknown) => value == null ? '' : typeof value === 'object' ? JSON.stringify(value) : String(value);

/** Use submitted labels/values, and only current dividers to organize missing legacy headings. */
export function recordSections(answers: WebRow[], questions: WebRow[], items: WebRow[]): RecordSection[] {
  const current = new Map(questions.map(question => [question.id, question]));
  const choices = new Map(items.map(item => [item.id, item]));
  const submitted = new Map(answers.filter(answer => answer.questao_id).map(answer => [answer.questao_id, answer]));
  const headings: WebRow[] = questions.filter(question => question.tipo === 'subt_tulo').map(question => {
    const snapshot = submitted.get(question.id);
    return { ...question, indice: snapshot?.indice ?? question.indice, enunciado: snapshot?.enunciado ?? question.enunciado };
  }).sort((a, b) => order(a) - order(b));
  const sections = new Map<string, RecordSection>();
  const historical: RecordSection = { id: 'historical', title: 'Respostas históricas sem questão vinculada', answers: [] };
  for (const answer of [...answers].sort((a, b) => order(a) - order(b) || a.id.localeCompare(b.id))) {
    const question = current.get(answer.questao_id);
    const snapshots = Array.isArray(answer.itens) ? answer.itens.map(text) : [];
    const choiceIds: unknown[] = Array.isArray(answer.itens_questoes_ids) ? answer.itens_questoes_ids : [];
    const row: ReviewAnswer = {
      ...answer, indice: answer.indice ?? question?.indice, tipo: answer.tipo ?? question?.tipo,
      tag: answer.tag ?? question?.tag, dimensoes: answer.dimensoes ?? question?.dimensoes,
      label: text(answer.enunciado ?? question?.enunciado) || 'Questão sem título',
      historical: !question, canCorrect: !!question && question.tipo !== 'subt_tulo',
      itemLabels: snapshots.length ? snapshots : choiceIds.map(id => text(choices.get(String(id))?.descricao) || 'Item histórico sem descrição'),
    };
    if (!question) { historical.answers.push(row); continue; }
    const heading = headings.filter(candidate => order(candidate) <= order(row)).at(-1);
    const key = heading?.id || 'general';
    let section = sections.get(key);
    if (!section) {
      section = { id: key, title: text(heading?.enunciado) || 'Respostas do formulário', description: text(heading?.subtitulo) || undefined, answers: [] };
      sections.set(key, section);
    }
    section.answers.push(row);
  }
  return [...sections.values(), ...(historical.answers.length ? [historical] : [])];
}

export function mayReview(record: WebRow, profile: { id: string; perfil: string }): boolean {
  return record.status === 'em_an_lise' && record.preenchido === true && (
    profile.perfil === 'administrador' || profile.id === record.avaliador_user_id ||
    (Array.isArray(record.aprovadores_ids) && record.aprovadores_ids.includes(profile.id))
  );
}

/** Each uncertain retry reuses this exact body and preserves PostgreSQL timestamp precision. */
export function freezeReviewRequest(input: ReviewRequest): Readonly<ReviewRequest> {
  return Object.freeze({ ...input, resposta_ids: Object.freeze([...input.resposta_ids]) });
}

export function safeAnswerMedia(raw: unknown, supabaseOrigin: string): string | null {
  if (typeof raw !== 'string') return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash) return null;
    if (url.hostname.endsWith('.cdn.bubble.io')) return url.toString();
    const base = new URL(supabaseOrigin);
    if (url.origin === base.origin && /^\/storage\/v1\/object\/public\/(rm-fotos|rm-assinaturas)\//.test(url.pathname) && !url.search) return url.toString();
    return null;
  } catch { return null; }
}

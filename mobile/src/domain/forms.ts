import { buildDefaultNaAnswer } from '../../../rm-mobile-supabase/mobile-offline/sqlite_schema';
import type { Answer, Row } from '../core';

export type DisplayAnswer = (Answer | (Omit<Answer, 'questao_id' | 'resposta_id'> & { questao_id: null; resposta_id: string })) & { subtitulo?: string };
export function hasQuestionId(answer: DisplayAnswer | undefined): answer is Answer {
  return typeof answer?.questao_id === 'string' && answer.questao_id.length > 0;
}
export function answerDisplayKey(answer: DisplayAnswer): string {
  return hasQuestionId(answer) ? answer.questao_id : `snapshot:${answer.resposta_id}`;
}
export function displayedRecordAnswers(originals: readonly DisplayAnswer[], draft?: Record<string, Answer>): Record<string, DisplayAnswer> {
  // Orphaned historical snapshots are read-only and never enter the editable SQLite draft.
  const visible = draft ? [...Object.values(draft), ...originals.filter(answer => !hasQuestionId(answer))] : originals;
  return Object.fromEntries(visible.map(answer => [answerDisplayKey(answer), answer]));
}

export const statusLabels: Record<string, string> = {
  pendente: 'Pendente', em_dia: 'Executando', atrasado: 'Atrasado', finalizado: 'Finalizado',
  retornado: 'Retornado', para_execu__o: 'Para execução', em_an_lise: 'Em análise',
  direcionado: 'Revisar', aprovado: 'Concluído', nulo: 'Ag. aprovação', reprovado: 'Retornado',
};
export const label = (value?: string) => value ? statusLabels[value] ?? value.replace(/_/g, ' ') : 'Pendente';
export function emptyAnswer(q: Row): Answer {
  return { questao_id: q.id, indice: q.indice, enunciado: q.enunciado, tipo: q.tipo, dimensoes: q.dimensoes, tag: q.tag,
    resposta: '', itens: [], itens_questoes_ids: [], fotos_urls: [], assinatura_url: null,
    date_inicio: null, data_fim: null, hora: null, is_na: false };
}
export function naAnswer(q: Row): Answer {
  const legacy = buildDefaultNaAnswer({ id: q.id, indice: q.indice, enunciado: q.enunciado, tipo: q.tipo, dimensoes: q.dimensoes });
  return { ...emptyAnswer(q), resposta: legacy.resposta, date_inicio: legacy.date_inicio ?? null,
    data_fim: legacy.data_fim ?? null, hora: legacy.hora ?? null, is_na: true };
}
export function validateAnswer(q: Row, a?: Answer): string | null {
  if (q.tipo === 'subt_tulo' || a?.is_na || a?.resposta === 'N/A') return null;
  const missing = !answerHasValue(q, a);
  if (missing) return q.obrigatorio ? 'Preenchimento obrigatório.' : null;
  if (q.tipo === 'numero' && !/^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(a!.resposta?.trim() ?? '')) return 'Informe um número válido.';
  if (q.tipo === 'foto_antes_depois' && (!a!.fotos_urls?.[0] || !a!.fotos_urls?.[1])) return 'Registre as fotos de antes e depois.';
  if (q.subtipo === 'intervalo_de_datas' || q.subtipo === 'intervalo_de_hor_rios') {
    if (!a!.date_inicio || !a!.data_fim) return 'Informe o início e o fim do intervalo.';
    if (Date.parse(a!.data_fim) < Date.parse(a!.date_inicio)) return 'O fim deve ser posterior ao início.';
  }
  return null;
}

export function answerHasValue(q: Row, a?: DisplayAnswer): boolean {
  if (!a || q.tipo === 'subt_tulo') return false;
  if (a.is_na || a.resposta === 'N/A') return true;
  return !!(['foto', 'foto_antes_depois'].includes(q.tipo) ? a.fotos_urls?.some(Boolean)
    : q.tipo === 'assinatura' ? a.assinatura_url : q.tipo === 'data' ? a.date_inicio
    : q.tipo === 'hora' ? a.hora || a.date_inicio
    : ['caixas_de_sele__o', 'lista_multi_sele__o'].includes(q.tipo) ? a.itens?.length : a.resposta?.trim());
}

export interface FormSection { id: string; title: string; description?: string; subtitle?: Row; questions: Row[] }
export function formSections(questions: readonly Row[]): FormSection[] {
  const sections: FormSection[] = []; let current: FormSection | undefined;
  // Fractional indices are used by the source forms; do not round them or sort as strings.
  for (const question of [...questions].sort((a, b) => Number(a.indice ?? 0) - Number(b.indice ?? 0))) {
    if (question.tipo === 'subt_tulo') {
      current = { id: question.id, title: question.enunciado || 'Seção', description: question.subtitulo, subtitle: question, questions: [] };
      sections.push(current);
    } else {
      if (!current) { current = { id: '__general', title: 'Questões gerais', questions: [] }; sections.push(current); }
      current.questions.push(question);
    }
  }
  return sections;
}

export function sectionForQuestion(sections: readonly FormSection[], questionId?: string): FormSection | undefined {
  return questionId ? sections.find(section => section.questions.some(question => question.id === questionId)) : undefined;
}

export function firstInvalidSection(sections: readonly FormSection[], errors: Record<string, string>): FormSection | undefined {
  return sections.find(section => section.questions.some(question => !!errors[question.id]));
}

export function canCorrectAnswer(record: Row | undefined, answer: DisplayAnswer | undefined): answer is Answer {
  return record?.status === 'direcionado' && hasQuestionId(answer) && answer.revisar === true;
}

export function storedAnswer(row: Row): DisplayAnswer {
  return { ...row, questao_id: typeof row.questao_id === 'string' && row.questao_id ? row.questao_id : null, resposta_id: row.id, is_na: row.is_na === true || row.resposta === 'N/A' } as unknown as DisplayAnswer;
}

/** Submitted answer snapshots remain visible even if a template label/order has since changed. */
export function recordedQuestions(templates: readonly Row[], answers: readonly DisplayAnswer[]): Row[] {
  if (!answers.length) return [];
  const current = new Map(templates.map(question => [question.id, question]));
  const answered = new Set(answers.map(answer => answer.questao_id));
  const rows: Row[] = answers.map(answer => {
    const template = hasQuestionId(answer) ? current.get(answer.questao_id) : undefined;
    return { ...template, id: answerDisplayKey(answer), indice: answer.indice ?? template?.indice,
      enunciado: answer.enunciado ?? template?.enunciado, tipo: answer.tipo ?? template?.tipo,
      dimensoes: answer.dimensoes ?? template?.dimensoes, tag: answer.tag ?? template?.tag,
      subtitulo: answer.subtitulo ?? template?.subtitulo, historical_only: !hasQuestionId(answer) };
  });
  // Some legacy submissions omit visual dividers. Reuse only dividers, never new unanswered questions.
  return [...rows, ...templates.filter(question => question.tipo === 'subt_tulo' && !answered.has(question.id)
    && !answers.some(answer => answer.tipo === 'subt_tulo' && answer.indice != null && question.indice != null && Number(answer.indice) === Number(question.indice)))]
    .sort((a, b) => Number(a.indice ?? 0) - Number(b.indice ?? 0));
}
export const approvalActions = ['liberar','retornar','aprovar','finalizar_ciclo'] as const;
export type ApprovalAction = typeof approvalActions[number];
export function canApprove(operator: {operador_id: string; perfil?: string; perfil_assinante?: string[]} | null, stage: Row, action?: ApprovalAction) {
  if (!operator) return false;
  const general = operator.perfil === 'administrador' ||
    stage.aprovador_id === operator.operador_id || (stage.aprovadores_ids ?? []).includes(operator.operador_id) ||
    (!stage.aprovador_id && !(stage.aprovadores_ids ?? []).length &&
      (operator.perfil_assinante ?? []).some(role => ['aprovador','aprovador_supervis_o'].includes(role)));
  return general || ((!action || action === 'retornar') && (stage.aprovadores_retorno_ids ?? []).includes(operator.operador_id));
}
export function qrProjectValue(data: string): string {
  try { const u = new URL(data); return u.searchParams.get('projeto') || u.searchParams.get('numero') || u.pathname.split('/').filter(Boolean).at(-1) || data; }
  catch { return data.trim(); }
}

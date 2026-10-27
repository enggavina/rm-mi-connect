import { buildDefaultNaAnswer } from '../../../rm-mobile-supabase/mobile-offline/sqlite_schema';
import type { Answer, Row } from '../core';

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
  const hasValue = a && (['foto','foto_antes_depois'].includes(q.tipo) ? a.fotos_urls?.some(Boolean)
    : q.tipo === 'assinatura' ? a.assinatura_url : q.tipo === 'data' ? a.date_inicio
    : q.tipo === 'hora' ? a.hora || a.date_inicio
    : ['caixas_de_sele__o','lista_multi_sele__o'].includes(q.tipo) ? a.itens?.length : a.resposta?.trim());
  const missing = !hasValue;
  if (missing) return q.obrigatorio ? 'Preenchimento obrigatório.' : null;
  if (q.tipo === 'numero' && !/^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(a!.resposta?.trim() ?? '')) return 'Informe um número válido.';
  if (q.tipo === 'foto_antes_depois' && (!a!.fotos_urls?.[0] || !a!.fotos_urls?.[1])) return 'Registre as fotos de antes e depois.';
  if (q.subtipo === 'intervalo_de_datas' || q.subtipo === 'intervalo_de_hor_rios') {
    if (!a!.date_inicio || !a!.data_fim) return 'Informe o início e o fim do intervalo.';
    if (Date.parse(a!.data_fim) < Date.parse(a!.date_inicio)) return 'O fim deve ser posterior ao início.';
  }
  return null;
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

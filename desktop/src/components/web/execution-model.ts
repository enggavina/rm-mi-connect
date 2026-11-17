import { calendarDay } from '@/server/web/gantt';

export type ExecutionEvidence = { state: 'running' | 'paused' | 'finished' | 'review' | 'void'; needs_review: boolean; clock_warning: boolean; has_review: boolean; confirmed_minutes: number | null };
export type ExecutionCardState = 'running' | 'paused' | 'finished' | 'unknown' | 'review';
export const executionStateLabel: Record<ExecutionCardState | 'void', string> = {
  running: 'Trabalho informado', paused: 'Pausa informada', finished: 'Término informado', unknown: 'Situação a confirmar', review: 'Requer revisão', void: 'Apontamento desconsiderado',
};
export const executionEventLabel = { start: 'Início informado', pause: 'Pausa informada', resume: 'Retomada informada', finish: 'Término informado' };
export const executionPauseLabel: Record<string, string> = { material: 'Material', cliente: 'Cliente', engenharia: 'Engenharia', ferramenta: 'Ferramenta', maquina: 'Máquina', manutencao: 'Manutenção', transporte: 'Transporte', servico_externo: 'Serviço externo', intervalo: 'Intervalo', outro: 'Outro motivo' };
export const executionReviewReasonLabel: Record<string, string> = {
  missing_start: 'O início deste apontamento ainda não foi recebido.', unresolved_evidence: 'Há evidências anteriores que precisam ser conciliadas.',
  after_management_review: 'O evento chegou após uma reconciliação da gestão e precisa de nova conferência.',
  duplicate_start: 'Outro início já está registrado para este apontamento.', previous_event_mismatch: 'A sequência informada difere da sequência recebida.',
  invalid_transition: 'A ação recebida precisa ser conferida com a situação anterior.', allocation_changed: 'A situação da etapa mudou desde o registro no aparelho.',
  another_open_session: 'Outro apontamento aberto precisa ser conferido.', operator_already_running: 'Há outro trabalho informado em aberto para este operador.',
};
export function executionNeedsReview(session: ExecutionEvidence): boolean {
  return session.needs_review || session.state === 'review' || session.clock_warning && !session.has_review;
}
/** Summaries remain evidence, not presence or approval of the allocation. */
export function allocationExecutionState(sessions: readonly ExecutionEvidence[]): ExecutionCardState {
  if (sessions.some(executionNeedsReview)) return 'review';
  if (sessions.some(session => session.state === 'running')) return 'running';
  if (sessions.some(session => session.state === 'paused')) return 'paused';
  if (sessions.some(session => session.state === 'finished')) return 'finished';
  return 'unknown';
}
export function confirmedExecutionEffort(sessions: readonly ExecutionEvidence[]) {
  const evidence = sessions.filter(session => session.state !== 'void');
  let minutes = 0, confirmed = 0;
  for (const session of evidence) if (session.confirmed_minutes !== null && !executionNeedsReview(session)) { minutes += session.confirmed_minutes; confirmed++; }
  return { minutes: confirmed ? minutes : null, confirmed, missing: evidence.length - confirmed, sessions: evidence.length };
}
export function parseExecutionMinutes(value: string): number | null | undefined {
  const text = value.trim(); if (!text) return null;
  return /^\d{1,7}$/.test(text) && Number(text) <= 1_000_000 ? Number(text) : undefined;
}
const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
export function executionSearchMatches(query: string, values: readonly (string | null | undefined)[]) {
  return normalize(values.filter(Boolean).join(' ')).includes(normalize(query.trim()));
}
/** Age describes received evidence only, without guessing a shift/freshness threshold. */
export function executionEvidenceAge(value: string | null, reference: string): string {
  const at = value ? Date.parse(value) : NaN, now = Date.parse(reference);
  if (!Number.isFinite(at) || !Number.isFinite(now)) return 'Sem atualização recebida';
  const minutes = Math.floor((now - at) / 60000);
  if (minutes < 0) return 'Recebimento posterior à referência da consulta';
  if (minutes < 1) return 'Recebido há menos de 1 minuto';
  if (minutes < 60) return `Recebido há ${minutes} minuto(s)`;
  if (minutes < 1440) return `Recebido há ${Math.floor(minutes / 60)} hora(s)`;
  return `Recebido há ${Math.floor(minutes / 1440)} dia(s)`;
}

const clock = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
function parts(at: number) {
  const p = Object.fromEntries(clock.formatToParts(at).map(part => [part.type, part.value]));
  return { input: `${p.year.padStart(4, '0')}-${p.month}-${p.day}T${p.hour}:${p.minute}`, day: `${p.year.padStart(4, '0')}-${p.month}-${p.day}`, hour: Number(p.hour), minute: Number(p.minute), second: Number(p.second) };
}
export function executionSaoPauloInput(value: string | null): string {
  const at = value ? Date.parse(value) : NaN;
  return Number.isFinite(at) ? parts(at).input : '';
}
/** Convert a civil São Paulo minute independently of the browser's timezone.
 * Repeated/nonexistent DST minutes require another explicit minute; no hidden choice. */
export function executionInputInstant(value: string): string | null {
  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})$/.exec(value);
  if (!match || match[1] < '1900-01-01' || match[1] > '2200-12-31') return null;
  const day = calendarDay(match[1]), hour = Number(match[2]), minute = Number(match[3]);
  if (day === null || hour > 23 || minute > 59) return null;
  const target = day * 86400000 + hour * 3600000 + minute * 60000, offsets = new Set<number>();
  for (const delta of [-36, -12, 0, 12, 36]) {
    const probe = target + delta * 3600000, observed = parts(probe), observedDay = calendarDay(observed.day);
    if (observedDay !== null) offsets.add(observedDay * 86400000 + observed.hour * 3600000 + observed.minute * 60000 + observed.second * 1000 - probe);
  }
  const candidates = [...offsets].map(offset => target - offset).filter(candidate => parts(candidate).input === value);
  return candidates.length === 1 ? new Date(candidates[0]).toISOString() : null;
}

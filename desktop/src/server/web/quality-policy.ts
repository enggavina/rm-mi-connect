import type { ExecutionSnapshot } from './execution-data';
import { planningDay } from './gantt';

export const qualityLabels = {
  missing_start: 'Início planejado ausente', missing_end: 'Prazo da etapa ausente',
  inverted_dates: 'Prazo anterior ao início', no_evidence: 'Sem apontamento recebido',
  review: 'Apontamento ou relógio para revisão',
} as const;
export type QualityReason = keyof typeof qualityLabels;
/** Complete, authorized execution snapshots only. Coverage is evidence, never
 * physical progress; a missing record does not mean the equipment is stopped. */
export function executionQuality(snapshot: ExecutionSnapshot) {
  if (!snapshot.complete) return null;
  const active = snapshot.allocations.filter(a => !a.retired && !a.project_closed && !['finalizado', 'n_a'].includes(a.status ?? ''));
  const sessions = new Map<string, typeof snapshot.sessions>();
  for (const session of snapshot.sessions) {
    const list = sessions.get(session.allocation_id) ?? []; list.push(session); sessions.set(session.allocation_id, list);
  }
  let dated = 0, received = 0, review = 0;
  const rows = active.map(allocation => {
    const evidence = (sessions.get(allocation.id) ?? []).filter(s => s.state !== 'void' && s.last_received_at !== null);
    const reasons: QualityReason[] = [];
    if (!allocation.planned_start) reasons.push('missing_start');
    if (!allocation.planned_end) reasons.push('missing_end');
    // Compare São Paulo civil days, not time-of-day or the original UTC offsets.
    if (allocation.planned_start && allocation.planned_end && planningDay(allocation.planned_end)! < planningDay(allocation.planned_start)!) reasons.push('inverted_dates');
    if (!reasons.length) dated++;
    if (evidence.length) received++; else reasons.push('no_evidence');
    if (evidence.some(s => s.needs_review || s.clock_warning && !s.has_review)) { reasons.push('review'); review++; }
    return { allocation, reasons };
  }).filter(row => row.reasons.length).sort((a,b) => Number(b.reasons.includes('review'))-Number(a.reasons.includes('review')) || a.allocation.id.localeCompare(b.allocation.id));
  const percent = (count: number) => active.length ? Math.round(count / active.length * 1000) / 10 : null;
  return { total: active.length, dated, received, review, datedPercent: percent(dated), receivedPercent: percent(received), rows };
}

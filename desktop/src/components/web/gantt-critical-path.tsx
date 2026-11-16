import type { GanttItem } from '@/server/web/gantt-data';
import { formatGanttDay, planningDay } from '@/server/web/gantt';
import type { CriticalPathResult, CriticalPathNode } from './gantt-calendar-model';
import s from './gantt-planner.module.css';

const day = (value: string | null) => { const parsed = planningDay(value); return parsed === null ? 'Não calculado' : formatGanttDay(parsed); };
const signed = (value: number) => `${value > 0 ? '+' : ''}${value}`;

export function GanttCriticalPath({ analysis, rows, useTarget, hasTarget, onTargetChange, dirty, onSelect }: {
  analysis: CriticalPathResult; rows: GanttItem[]; useTarget: boolean; hasTarget: boolean; onTargetChange: (value: boolean) => void; dirty: boolean; onSelect: (row: GanttItem) => void;
}) {
  const label = (id: string) => rows.find(row => row.id === id)?.celula_nome || 'Etapa';
  return <section className={`panel ${s.analysis}`} aria-label="Análise do caminho crítico">
    <div className={s.analysisHeading}><div><h3>Caminho crítico e folgas {dirty && <small>· prévia não salva</small>}</h3><p>Rede planejada completa do projeto, em dias do calendário de trabalho.</p></div>
      <label><input type="checkbox" aria-label="Calcular folgas até a entrega contratual" checked={useTarget} disabled={!hasTarget} onChange={event => onTargetChange(event.target.checked)} /> Calcular folgas até a entrega {hasTarget ? '(renegociada ou contratual)' : '(data não informada)'}</label></div>
    {analysis.complete ? <>
      <div className={s.analysisMetrics}><span>Início teórico<strong>{day(analysis.projectStart)}</strong></span><span>Término mais cedo<strong>{day(analysis.networkFinish)}</strong></span><span>Alvo da análise<strong>{day(analysis.targetFinish)}</strong></span><span>Caminho crítico da rede<strong>{analysis.networkCriticalIds.length} etapa(s)</strong></span><span>Folga negativa<strong>{analysis.negativeFloatIds.length} etapa(s)</strong></span><span>Margem até o alvo<strong>{signed(analysis.finishVarianceDays ?? 0)} dia(s)</strong></span></div>
      <details><summary>Conferir datas e folgas por etapa</summary><div className={s.analysisTable}><table><thead><tr><th>Etapa</th><th>Duração</th><th>Início mais cedo</th><th>Término mais cedo</th><th>Início limite</th><th>Término limite</th><th>Folga total</th><th>Margem do programado</th></tr></thead><tbody>{analysis.nodes.map(node => <tr key={node.id}><td><button type="button" className={s.stageLink} onClick={() => { const row = rows.find(row => row.id === node.id); if (row) onSelect(row); }}>{label(node.id)}</button>{node.networkCritical && <small className={s.criticalBadge}>Crítica na rede</small>}{node.negativeFloat && <small className={s.riskBadge}>Prazo em risco</small>}</td><td>{node.durationDays} dia(s)</td><td>{day(node.earliestStart)}</td><td>{day(node.earliestFinish)}</td><td>{day(node.latestStart)}</td><td>{day(node.latestFinish)}</td><td>{signed(node.totalFloatDays)} dia(s)</td><td>{signed(node.scheduledSlackDays)} dia(s)</td></tr>)}</tbody></table></div></details>
    </> : <div className="notice" role="status"><strong>Análise incompleta</strong><ul className={s.issueList}>{analysis.issues.map((issue, index) => <li key={index}>{issue.allocation_id ? `${label(issue.allocation_id)}: ` : ''}{issue.message}</li>)}</ul></div>}
    {analysis.warnings.map(warning => <p className="form-note" key={warning}>{warning}</p>)}
    <p className="form-note">O contorno das barras identifica o caminho mais longo da rede. Folga total compara o início mais cedo ao início limite; margem do programado compara a data programada ao início limite. Valores negativos indicam risco. O cálculo usa durações planejadas e vínculos, sem disponibilidade de recursos, progresso real ou previsão da execução restante.</p>
  </section>;
}

export function GanttStageAnalysis({ node }: { node: CriticalPathNode }) {
  return <div className={s.stageAnalysis}><h4>Datas calculadas da etapa</h4><p>{node.networkCritical ? 'Integra o caminho crítico da rede.' : `Folga na rede: ${node.networkFloatDays} dia(s).`} {node.negativeFloat && 'Há folga negativa até o alvo.'}</p><dl><dt>Início / término mais cedo</dt><dd>{day(node.earliestStart)} a {day(node.earliestFinish)}</dd><dt>Início / término limite</dt><dd>{day(node.latestStart)} a {day(node.latestFinish)}</dd><dt>Duração / folga total</dt><dd>{node.durationDays} / {signed(node.totalFloatDays)} dia(s)</dd><dt>Margem do programado</dt><dd>{signed(node.scheduledSlackDays)} dia(s)</dd></dl></div>;
}

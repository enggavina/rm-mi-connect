'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { saveGanttSettings } from '@/server/web/gantt-settings-actions';
import type { GanttCalendar, GanttMilestone, SaveGanttSettingsInput } from '@/server/web/gantt-settings-policy';
import { calendarDay, formatGanttDay } from '@/server/web/gantt';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { Icon } from './icons';
import s from './gantt-settings-panel.module.css';

export type GanttSettingsState = {
  dirty: boolean; busy: boolean; uncertain: boolean; stale: boolean; unauthorized: boolean; saved: boolean; locked: boolean;
};
export type GanttSettingsPanelProps = {
  project: { id: string; updated_at: string; plan_version: string; closed: boolean };
  settings: { calendar: GanttCalendar; milestones: GanttMilestone[] } | null;
  canManage: boolean;
  hasPendingDateChanges: boolean;
  destination: string;
  onStateChange?: (state: GanttSettingsState) => void;
  onSaved?: () => void;
};

const weekdays = [
  { day: 1, short: 'Seg', name: 'Segunda-feira' }, { day: 2, short: 'Ter', name: 'Terça-feira' },
  { day: 3, short: 'Qua', name: 'Quarta-feira' }, { day: 4, short: 'Qui', name: 'Quinta-feira' },
  { day: 5, short: 'Sex', name: 'Sexta-feira' }, { day: 6, short: 'Sáb', name: 'Sábado' }, { day: 7, short: 'Dom', name: 'Domingo' },
] as const;
const MIN_DATE = '1900-01-01', MAX_DATE = '2200-12-31';
const defaultCalendar = (): GanttCalendar => ({ weekdays: [1, 2, 3, 4, 5, 6, 7], exceptions: [] });
const copyCalendar = (calendar: GanttCalendar): GanttCalendar => ({ weekdays: [...calendar.weekdays], exceptions: calendar.exceptions.map(item => ({ ...item })) });
const cleanCalendar = (calendar: GanttCalendar): GanttCalendar => ({
  weekdays: [...calendar.weekdays].sort((a, b) => a - b),
  exceptions: calendar.exceptions.map(item => ({ ...item, label: item.label.trim() })).sort((a, b) => a.date.localeCompare(b.date)),
});
const cleanMilestones = (milestones: GanttMilestone[]): GanttMilestone[] => milestones.map(item => ({ ...item, label: item.label.trim() })).sort((a, b) => a.id.localeCompare(b.id));
const signature = (calendar: GanttCalendar, milestones: GanttMilestone[]) => JSON.stringify({ calendar: cleanCalendar(calendar), milestones: cleanMilestones(milestones) });
const dayLabel = (day: string) => { const parsed = calendarDay(day); return parsed === null ? 'Data não informada' : formatGanttDay(parsed); };
const validDay = (day: string) => day >= MIN_DATE && day <= MAX_DATE && calendarDay(day) !== null;
const validLabel = (label: string) => label.trim().length >= 1 && label.trim().length <= 120 && !/[\u0000-\u001f\u007f]/.test(label);
function weekLabel(calendar: GanttCalendar) {
  return calendar.weekdays.length === 7 ? 'Dias corridos · todos os dias' : calendar.weekdays.length
    ? weekdays.filter(item => calendar.weekdays.includes(item.day)).map(item => item.short).join(' · ') : 'Nenhum dia de trabalho selecionado';
}

/** Configuration is saved separately from date drafts. The parent owns the
 * single navigation guard and interlocks both editors through onStateChange. */
export function GanttSettingsPanel({ project, settings, canManage, hasPendingDateChanges, destination, onStateChange, onSaved }: GanttSettingsPanelProps) {
  const originalCalendar = useMemo(() => copyCalendar(settings?.calendar ?? defaultCalendar()), [settings]);
  const originalMilestones = useMemo(() => (settings?.milestones ?? []).map(item => ({ ...item })), [settings]);
  const [calendar, setCalendar] = useState(() => copyCalendar(originalCalendar));
  const [milestones, setMilestones] = useState(() => originalMilestones.map(item => ({ ...item })));
  const [reason, setReason] = useState(''), [reviewing, setReviewing] = useState(false), [saved, setSaved] = useState(false);
  const review = useRef<HTMLElement>(null), callbacks = useRef({ onStateChange, onSaved });
  callbacks.current = { onStateChange, onSaved };
  const save = useEngineeringSave<SaveGanttSettingsInput>(async input => {
    const result = await saveGanttSettings(input);
    if (result.ok) { setSaved(true); callbacks.current.onSaved?.(); }
    return result;
  }, destination);
  const dirty = signature(calendar, milestones) !== signature(originalCalendar, originalMilestones);
  const locked = save.locked || saved;
  const editable = canManage && !project.closed && !hasPendingDateChanges && !locked;
  const invalidExceptions = calendar.exceptions.some(item => !validDay(item.date) || !validLabel(item.label));
  const duplicateDates = new Set(calendar.exceptions.map(item => item.date)).size !== calendar.exceptions.length;
  const invalidMilestones = milestones.some(item => !validDay(item.date) || !validLabel(item.label));
  const valid = calendar.weekdays.length > 0 && !invalidExceptions && !duplicateDates && !invalidMilestones;
  useEffect(() => {
    callbacks.current.onStateChange?.({ dirty, busy: save.busy, uncertain: save.uncertain, stale: save.stale, unauthorized: save.unauthorized, saved, locked });
  }, [dirty, save.busy, save.uncertain, save.stale, save.unauthorized, saved, locked]);

  function editCalendar(next: GanttCalendar) { if (!editable) return; setReviewing(false); setCalendar(next); }
  function editMilestones(next: GanttMilestone[]) { if (!editable) return; setReviewing(false); setMilestones(next); }
  function discard() {
    if (locked) return;
    setCalendar(copyCalendar(originalCalendar)); setMilestones(originalMilestones.map(item => ({ ...item }))); setReason(''); setReviewing(false);
  }
  function beginReview() {
    if (!editable || !dirty || !valid) return;
    setReviewing(true);
    setTimeout(() => { review.current?.focus({ preventScroll: true }); review.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); }, 0);
  }
  function commit() {
    if (save.uncertain) { save.retry(); return; }
    if (!editable || !dirty || !valid || !reviewing || reason.trim().length < 3) return;
    void save.send({ submissionId: crypto.randomUUID(), projeto_id: project.id, expected_updated_at: project.updated_at,
      expected_plan_version: project.plan_version, calendar: cleanCalendar(calendar), milestones: cleanMilestones(milestones), reason: reason.trim() });
  }

  return <section className={`panel ${s.panel}`} data-gantt-settings>
    <details>
      <summary className={s.summary}><span><strong>Calendário e marcos do projeto</strong><small>{weekLabel(originalCalendar)} · {originalCalendar.exceptions.length} exceção(ões) · {originalMilestones.length} marco(s)</small></span><span className={dirty ? s.pending : s.caption}>{dirty ? 'Configuração não salva' : 'Consultar configuração'}<Icon name="chevron" size={15} /></span></summary>
      <div className={s.body}>
        <EngineeringSaveNotice state={save} reload={destination} />
        {saved && <p className="notice success" role="status">Calendário e marcos confirmados. Atualizando o Gantt…</p>}
        <p className={s.note}>O calendário define os dias de trabalho usados na duração, nas esperas e na proposta de reprogramação das etapas deste projeto. As exceções são cadastradas pela equipe; feriados não são incluídos automaticamente.</p>
        <p className={s.note}>Salvar esta configuração mantém as datas atuais. Depois, revise os avisos do Gantt e use a prévia de reprogramação para ajustar os prazos necessários. Marcos são datas civis de referência, inclusive quando caem em dias sem trabalho.</p>
        {project.closed ? <p className="notice">Projeto encerrado. Calendário e marcos disponíveis para consulta.</p>
          : !canManage ? <p className="notice">Seu perfil permite consultar o calendário e os marcos deste projeto.</p>
            : hasPendingDateChanges && <p className="notice" role="status">Salve ou descarte a prévia de datas e dependências antes de alterar o calendário e os marcos.</p>}
        <form data-gantt-local onSubmit={event => { event.preventDefault(); commit(); }}>
          <fieldset className={s.fields} disabled={!editable}>
            <fieldset className={s.week}><legend>Dias de trabalho da semana</legend><div className={s.weekdays}>{weekdays.map(item => <label key={item.day}><input type="checkbox" checked={calendar.weekdays.includes(item.day)} aria-label={item.name} onChange={event => editCalendar({ ...calendar, weekdays: event.target.checked ? [...calendar.weekdays, item.day].sort((a, b) => a - b) : calendar.weekdays.filter(day => day !== item.day) })} /><span>{item.short}</span></label>)}</div><div className={s.presets}><button type="button" className="button small secondary" onClick={() => editCalendar({ ...calendar, weekdays: [1, 2, 3, 4, 5, 6, 7] })}>Usar dias corridos</button><button type="button" className="button small secondary" onClick={() => editCalendar({ ...calendar, weekdays: [1, 2, 3, 4, 5] })}>Usar segunda a sexta</button></div></fieldset>
            <div className={s.sectionHead}><div><h3>Exceções do calendário</h3><p>Uma exceção substitui a regra semanal naquela data: feriado, parada ou dia adicional de trabalho.</p></div><button type="button" className="button small secondary" disabled={calendar.exceptions.length >= 366} onClick={() => editCalendar({ ...calendar, exceptions: [...calendar.exceptions, { date: '', working: false, label: '' }] })}><Icon name="plus" size={14} />Adicionar exceção</button></div>
            {!calendar.exceptions.length && <p className={s.empty}>Nenhuma exceção cadastrada.</p>}
            <div className={s.rows}>{calendar.exceptions.map((item, index) => <div className={s.exception} key={index}>
              <label className={s.field}>Data da exceção<input aria-label={`Data da exceção ${index + 1}`} type="date" min={MIN_DATE} max={MAX_DATE} required value={item.date} onChange={event => editCalendar({ ...calendar, exceptions: calendar.exceptions.map((row, position) => position === index ? { ...row, date: event.target.value } : row) })} /></label>
              <label className={s.field}>Funcionamento<select aria-label={`Funcionamento da exceção ${index + 1}`} value={item.working ? 'working' : 'off'} onChange={event => editCalendar({ ...calendar, exceptions: calendar.exceptions.map((row, position) => position === index ? { ...row, working: event.target.value === 'working' } : row) })}><option value="off">Sem trabalho</option><option value="working">Dia de trabalho</option></select></label>
              <label className={s.field}>Descrição<input aria-label={`Descrição da exceção ${index + 1}`} required maxLength={120} value={item.label} placeholder="Ex.: manutenção da oficina" onChange={event => editCalendar({ ...calendar, exceptions: calendar.exceptions.map((row, position) => position === index ? { ...row, label: event.target.value } : row) })} /></label>
              <button className="button small secondary" type="button" aria-label={`Remover exceção ${index + 1}`} onClick={() => editCalendar({ ...calendar, exceptions: calendar.exceptions.filter((_, position) => position !== index) })}><Icon name="close" size={14} /><span>Remover</span></button>
            </div>)}</div>
            {calendar.exceptions.length >= 366 && <p className={s.note}>O limite é de 366 exceções por projeto.</p>}
            <div className={s.sectionHead}><div><h3>Marcos do projeto</h3><p>Datas de referência para acompanhar entregas, inspeções e compromissos. Não alteram as datas contratuais do cadastro.</p></div><button type="button" className="button small secondary" disabled={milestones.length >= 100} onClick={() => editMilestones([...milestones, { id: crypto.randomUUID(), label: '', date: '' }])}><Icon name="plus" size={14} />Adicionar marco</button></div>
            {!milestones.length && <p className={s.empty}>Nenhum marco cadastrado.</p>}
            <div className={s.rows}>{milestones.map((item, index) => <div className={s.milestone} key={item.id}>
              <label className={s.field}>Nome do marco<input aria-label={`Nome do marco ${index + 1}`} required maxLength={120} value={item.label} placeholder="Ex.: inspeção com o cliente" onChange={event => editMilestones(milestones.map(row => row.id === item.id ? { ...row, label: event.target.value } : row))} /></label>
              <label className={s.field}>Data do marco<input aria-label={`Data do marco ${index + 1}`} type="date" min={MIN_DATE} max={MAX_DATE} required value={item.date} onChange={event => editMilestones(milestones.map(row => row.id === item.id ? { ...row, date: event.target.value } : row))} /></label>
              <button className="button small secondary" type="button" aria-label={`Remover marco ${index + 1}`} onClick={() => editMilestones(milestones.filter(row => row.id !== item.id))}><Icon name="close" size={14} /><span>Remover</span></button>
            </div>)}</div>
            {milestones.length >= 100 && <p className={s.note}>O limite é de 100 marcos por projeto.</p>}
          </fieldset>
          {dirty && !valid && <div className="notice error" role="alert"><strong>Complete a configuração antes de revisar.</strong><ul>{!calendar.weekdays.length && <li>Selecione pelo menos um dia de trabalho da semana.</li>}{invalidExceptions && <li>Informe data válida entre 1900 e 2200 e descrição em todas as exceções.</li>}{duplicateDates && <li>Cada data pode ter somente uma exceção.</li>}{invalidMilestones && <li>Informe nome e data válida entre 1900 e 2200 em todos os marcos.</li>}</ul></div>}
          {dirty && <div className={s.actions}><button type="button" className="button secondary" disabled={locked} onClick={discard}>Descartar configuração</button><button type="button" className="button secondary" disabled={!editable || !valid} onClick={beginReview}>Revisar calendário e marcos</button></div>}
          {(reviewing || save.uncertain) && <section className={s.review} ref={review} tabIndex={-1} aria-label="Revisão do calendário e marcos">
            <h3>Revisar configuração antes de salvar</h3>
            <div className={s.compare}><div><h4>Configuração atual</h4><p>{weekLabel(originalCalendar)}</p><p>{originalCalendar.exceptions.length} exceção(ões) · {originalMilestones.length} marco(s)</p></div><div><h4>Nova configuração</h4><p>{weekLabel(calendar)}</p><p>{calendar.exceptions.length} exceção(ões) · {milestones.length} marco(s)</p></div></div>
            {(calendar.exceptions.length > 0 || originalCalendar.exceptions.length > 0) && <details><summary>Conferir exceções anteriores e novas</summary><div className={s.compare}><div><h4>Antes</h4>{originalCalendar.exceptions.length ? <ul>{originalCalendar.exceptions.map(item => <li key={item.date}>{dayLabel(item.date)} · {item.working ? 'Dia de trabalho' : 'Sem trabalho'} · {item.label}</li>)}</ul> : <p>Nenhuma exceção</p>}</div><div><h4>Prévia</h4>{calendar.exceptions.length ? <ul>{cleanCalendar(calendar).exceptions.map(item => <li key={item.date}>{dayLabel(item.date)} · {item.working ? 'Dia de trabalho' : 'Sem trabalho'} · {item.label}</li>)}</ul> : <p>Nenhuma exceção</p>}</div></div></details>}
            {(milestones.length > 0 || originalMilestones.length > 0) && <details><summary>Conferir marcos anteriores e novos</summary><div className={s.compare}><div><h4>Antes</h4>{originalMilestones.length ? <ul>{originalMilestones.map(item => <li key={item.id}>{dayLabel(item.date)} · {item.label}</li>)}</ul> : <p>Nenhum marco</p>}</div><div><h4>Prévia</h4>{milestones.length ? <ul>{milestones.map(item => <li key={item.id}>{dayLabel(item.date)} · {item.label.trim()}</li>)}</ul> : <p>Nenhum marco</p>}</div></div></details>}
            <label className={s.field}>Motivo da alteração<textarea aria-label="Motivo da configuração do Gantt" value={reason} minLength={3} maxLength={2000} rows={2} placeholder="Explique a definição do calendário ou dos marcos." disabled={locked} onChange={event => setReason(event.target.value)} /></label>
            <p className={s.note}>A confirmação salva somente o calendário e os marcos. A reprogramação dos prazos será revisada na prévia do Gantt.</p>
            <div className={s.actions}><button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!editable || !dirty || !valid || !reviewing || reason.trim().length < 3)}>{save.busy ? 'Confirmando configuração…' : save.uncertain ? 'Tentar confirmar configuração' : 'Confirmar calendário e marcos'}</button></div>
          </section>}
        </form>
      </div>
    </details>
  </section>;
}

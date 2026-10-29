'use client';

import { useRef, useState } from 'react';
import { reviewForm } from '@/server/web/actions';
import { Icon } from './icons';
import { Photo } from './photo';
import { date } from './ui';
import { freezeReviewRequest, safeAnswerMedia, type RecordSection, type ReviewAnswer, type ReviewRequest } from './review-model';

function AnswerValue({ answer, mediaOrigin }: { answer: ReviewAnswer; mediaOrigin: string }) {
  const photos: unknown[] = Array.isArray(answer.fotos_urls) ? answer.fotos_urls : [];
  const validPhotos = photos.map(url => safeAnswerMedia(url, mediaOrigin)).filter((url): url is string => !!url);
  const signature = safeAnswerMedia(answer.assinatura_url, mediaOrigin);
  const hasText = answer.resposta != null && answer.resposta !== '';
  const hasValue = hasText || answer.itemLabels.length || photos.length || answer.assinatura_url || answer.date_inicio || answer.data_fim || answer.hora;
  return <div className="answer-value">
    {hasText && <p style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{String(answer.resposta)}</p>}
    {!!answer.itemLabels.length && <ul>{answer.itemLabels.map((label, index) => <li key={index}>{label}</li>)}</ul>}
    {answer.date_inicio && <p>Início: {date(answer.date_inicio, true)}</p>}
    {answer.data_fim && <p>Fim: {date(answer.data_fim, true)}</p>}
    {answer.hora && <p>Hora: {String(answer.hora)}</p>}
    {!!validPhotos.length && <div className="answer-photos">{validPhotos.map((url, index) => <Photo key={`${url}:${index}`} url={url} title={`${answer.label} — foto ${index + 1}`} />)}</div>}
    {signature && <div className="answer-photos"><Photo url={signature} title={`Assinatura — ${answer.label}`} /></div>}
    {(validPhotos.length < photos.length || (!!answer.assinatura_url && !signature)) && <p className="form-note">Há uma mídia histórica sem endereço disponível para visualização.</p>}
    {!hasValue && answer.tipo !== 'subt_tulo' && <p className="form-note">Resposta não informada.</p>}
  </div>;
}

function AnswerSection({ section, selected, selecting, disabled, onSelect, mediaOrigin }: {
  section: RecordSection; selected: Set<string>; selecting: boolean; disabled: boolean;
  onSelect: (id: string, checked: boolean) => void; mediaOrigin: string;
}) {
  const [open, setOpen] = useState(false);
  const selectedCount = section.answers.filter(answer => selected.has(answer.id)).length;
  return <details className="record-section" onToggle={event => setOpen(event.currentTarget.open)}>
    <summary><span>{section.title}</span><span className="panel-caption">{section.answers.length} respostas{selectedCount ? ` · ${selectedCount} para correção` : ''}<Icon name="chevron" size={15} /></span></summary>
    {open && <>{section.description && <p className="form-note" style={{ padding: '0 22px' }}>{section.description}</p>}{section.answers.map(answer => <div className="answer-row" key={answer.id}>
      <div className="answer-question"><h3>{answer.indice != null ? `${answer.indice}. ` : ''}{answer.label}</h3>
        {(answer.tag || answer.dimensoes) && <p className="form-note">{[answer.tag, answer.dimensoes].filter(Boolean).join(' · ')}</p>}
        {answer.historical && <p className="form-note">Histórico · somente consulta</p>}
        {answer.revisar && <p className="form-note">Correção solicitada</p>}
        {selecting && answer.canCorrect && <label className="check-label"><input type="checkbox" checked={selected.has(answer.id)} disabled={disabled} onChange={event => onSelect(answer.id, event.target.checked)} />Devolver esta resposta para correção</label>}
      </div>
      <AnswerValue answer={answer} mediaOrigin={mediaOrigin} />
    </div>)}</>}
  </details>;
}

export function RecordReview({ recordId, version, sections, canReview, mediaOrigin }: {
  recordId: string; version: string; sections: RecordSection[]; canReview: boolean; mediaOrigin: string;
}) {
  const [decision, setDecision] = useState<'' | 'approve' | 'return'>('');
  const [opinion, setOpinion] = useState(''); const [selected, setSelected] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false); const [uncertain, setUncertain] = useState(false); const [stale, setStale] = useState(false);
  const [error, setError] = useState(''); const [success, setSuccess] = useState('');
  const inFlight = useRef(false); const attempt = useRef<Readonly<ReviewRequest> | null>(null);
  const answers = sections.flatMap(section => section.answers);
  const correctionsPending = answers.some(answer => answer.revisar === true);
  const correctable = new Set(answers.filter(answer => answer.canCorrect).map(answer => answer.id));
  const enabled = canReview && answers.length > 0 && !success;
  const locked = busy || uncertain || stale || !!success;
  const selectAnswer = (id: string, checked: boolean) => {
    if (locked || !correctable.has(id)) return;
    setSelected(previous => { const next = new Set(previous); if (checked) next.add(id); else next.delete(id); return next; });
  };
  async function submit() {
    if (inFlight.current || !enabled || stale) return;
    if (!attempt.current) {
      const ids = [...selected].filter(id => correctable.has(id));
      if (!decision) { setError('Escolha a decisão antes de confirmar.'); return; }
      if (decision === 'return' && (!ids.length || !opinion.trim())) { setError('Abra as seções, selecione as respostas para correção e informe o parecer.'); return; }
      if (decision === 'approve' && correctionsPending) { setError('A aprovação fica disponível quando as correções solicitadas forem concluídas.'); return; }
      attempt.current = freezeReviewRequest({ submissionId: crypto.randomUUID(), registro_formulario_id: recordId,
        expected_updated_at: version, decision, parecer: opinion.trim(), resposta_ids: decision === 'return' ? ids : [] });
    }
    inFlight.current = true; setBusy(true); setError('');
    try {
      const result = await reviewForm(attempt.current);
      if (result.ok) {
        setSuccess(attempt.current.decision === 'approve' ? 'Formulário aprovado.' : 'Formulário devolvido para correção das respostas selecionadas.');
        setUncertain(false); window.location.reload();
      } else {
        setError(result.error); setUncertain(result.code === 'UNAVAILABLE');
        setStale(['PT409', '40001', '23505'].includes(result.code));
        if (result.code !== 'UNAVAILABLE') attempt.current = null;
      }
    } catch { setUncertain(true); setError('A conexão foi interrompida. Confirme novamente para verificar o resultado do mesmo envio.'); }
    finally { inFlight.current = false; setBusy(false); }
  }
  return <>
    {enabled && <div className="review-box"><h2>Revisar formulário</h2><p className="form-note">Confira as respostas antes de decidir. Para solicitar correções, escolha a devolução e marque as respostas nas seções abaixo.</p>
      <fieldset disabled={locked} style={{ border: 0, padding: 0, margin: 0 }}><div className="field"><label htmlFor="review-decision">Decisão</label><select id="review-decision" value={decision} onChange={event => { setDecision(event.target.value as typeof decision); setError(''); }}>
        <option value="">Escolha após conferir as respostas</option><option value="approve" disabled={correctionsPending}>Aprovar formulário</option><option value="return" disabled={!correctable.size}>Devolver para correção</option>
      </select></div></fieldset>
      {correctionsPending && <p className="form-note">Há respostas com correção pendente. A aprovação exige a conclusão dessas correções.</p>}
    </div>}
    {sections.map(section => <AnswerSection key={section.id} section={section} selected={selected} selecting={enabled && decision === 'return'} disabled={locked} onSelect={selectAnswer} mediaOrigin={mediaOrigin} />)}
    {enabled && <form className="review-box" onSubmit={event => { event.preventDefault(); void submit(); }}>
      <h2>Confirmar revisão</h2>
      {error && <div role="alert" className="notice error">{error}</div>}
      {uncertain && <div className="notice">A decisão e as respostas permanecem protegidas até a confirmação. Tentar novamente repete o mesmo envio, sem duplicar a revisão.</div>}
      <fieldset disabled={locked} style={{ border: 0, padding: 0, margin: 0 }}><div className="field"><label htmlFor="review-opinion">Parecer{decision === 'return' ? ' (obrigatório)' : ' (opcional)'}</label><textarea id="review-opinion" value={opinion} maxLength={10000} required={decision === 'return'} onChange={event => setOpinion(event.target.value)} /></div></fieldset>
      {decision === 'return' && <p className="form-note">{selected.size} respostas selecionadas para correção.</p>}
      <div className="form-actions">{stale ? <button type="button" className="button secondary" onClick={() => window.location.reload()}><Icon name="refresh" size={15} />Atualizar registro</button> : <button type="submit" className="button" disabled={busy || !decision}>{busy ? 'Confirmando…' : uncertain ? 'Tentar confirmar o mesmo envio' : decision === 'return' ? 'Confirmar devolução' : 'Confirmar aprovação'}</button>}</div>
    </form>}
    {success && <div role="status" className="notice success">{success}</div>}
  </>;
}

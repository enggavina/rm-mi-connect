'use client';

import { useRef, useState, type ChangeEvent, type FormEvent } from 'react';
import { onlineQuestionKind, type OnlineAnswer } from '@/shared/online-form';
import type { OperationData } from '@/server/operation/policy';
import { templateSections } from '@/components/web/form-template-model';
import s from './operation.module.css';

type FormDataView = Extract<OperationData, { kind: 'form' }>;
type Question = FormDataView['questions'][number];
type Outcome = 'session' | 'forbidden' | 'invalid' | 'changed' | 'conflict' | 'unavailable';

const messages: Record<Outcome, string> = {
  session: 'Sua sessão expirou. Entre novamente com o mesmo operador e volte a esta tela para tentar o mesmo envio.',
  forbidden: 'O acesso a este formulário mudou. Confirme o vínculo com o responsável pela oficina.',
  invalid: 'Revise as respostas obrigatórias e os valores antes de enviar novamente.',
  changed: 'O modelo foi alterado. Reabra o formulário para consultar a versão atual.',
  conflict: 'O envio não pôde ser confirmado. Aguarde alguns instantes e tente o mesmo envio.',
  unavailable: 'O envio ainda não foi confirmado. Mantenha esta página aberta e tente o mesmo envio novamente.',
};

function AnswerControl({ question, interval, error }: { question: Question; interval: boolean; error?: string }) {
  const [na, setNa] = useState(false);
  const { id, enunciado, subtitulo, obrigatorio, items } = question;
  const kind = onlineQuestionKind(question.tipo);
  const name = `answer-${id}`;
  return <fieldset className={s.answer} id={`question-${id}`}>
    <legend>{enunciado || 'Questão sem enunciado'} {obrigatorio && <span className={s.questionNote}>Obrigatória</span>}</legend>
    {subtitulo && <p className={s.questionNote}>{subtitulo}</p>}
    {kind ? <>
      <fieldset className={s.answerFields} disabled={na} aria-label={enunciado || 'Resposta'}>
        {kind === 'date' && <>
          <label>{interval ? 'Início' : 'Data'}<input name={name} type="date" /></label>
          {interval && <label>Fim<input name={`end-${id}`} type="date" /></label>}
        </>}
        {kind === 'single' && <select name={name} aria-label={enunciado || 'Opção'} defaultValue="">
          <option value="">Selecione</option>
          {items.map(item => <option key={item.id} value={item.id}>{item.descricao}</option>)}
        </select>}
        {kind === 'multiple' && items.map(item => <label className={s.checkLabel} key={item.id}>
          <input type="checkbox" name={name} value={item.id} />{item.descricao}
        </label>)}
        {kind === 'text' && question.tipo === 'texto_longo' &&
          <textarea name={name} maxLength={4000} aria-label={enunciado || 'Resposta'} rows={3} />}
        {(kind === 'number' || kind === 'text' && question.tipo !== 'texto_longo') &&
          <input name={name} type="text" inputMode={kind === 'number' ? 'decimal' : 'text'}
            maxLength={kind === 'number' ? 80 : 4000} aria-label={enunciado || 'Resposta'} />}
      </fieldset>
      <label className={s.checkLabel}>
        <input type="checkbox" name={`na-${id}`} checked={na} onChange={event => setNa(event.target.checked)} />Não se aplica
      </label>
    </> : <p className={s.questionNote}>Preenchimento disponível no app mobile.</p>}
    {error && <p role="alert" className={s.fieldError}>{error}</p>}
  </fieldset>;
}

function readAnswers(form: HTMLFormElement, questions: readonly Question[], intervals: ReadonlySet<string>) {
  const fields = new FormData(form);
  const answers: Record<string, OnlineAnswer> = {};
  const errors: Record<string, string> = {};
  for (const { id, tipo, obrigatorio } of questions) {
    const kind = onlineQuestionKind(tipo);
    if (!kind) continue;
    if (fields.has(`na-${id}`)) { answers[id] = true; continue; }
    const name = `answer-${id}`;
    const value = String(fields.get(name) ?? '').trim();
    const end = String(fields.get(`end-${id}`) ?? '');
    if (!value && !end) {
      if (obrigatorio) errors[id] = 'Preencha esta pergunta.';
      continue;
    }
    if (kind === 'single' || kind === 'multiple') answers[id] = fields.getAll(name).map(String);
    else if (kind === 'date') {
      if (intervals.has(id) && (!value || !end || end < value)) errors[id] = 'Informe o início e um fim igual ou posterior.';
      else answers[id] = { inicio: value, ...(end ? { fim: end } : {}) };
    } else if (kind === 'number' && !/^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(value)) {
      errors[id] = 'Informe um número válido.';
    } else if (value === 'N/A') {
      errors[id] = 'Use a opção “Não se aplica”.';
    } else answers[id] = value;
  }
  return { answers, errors };
}

export function OperationFormEditor({ data, endpoint, proof }: { data: FormDataView; endpoint: string; proof: string }) {
  const [pending, setPending] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [code, setCode] = useState<string | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [empty, setEmpty] = useState(false);
  const body = useRef<string | null>(null);
  const inFlight = useRef(false);
  const statusRef = useRef<HTMLDivElement>(null);
  const intervals = new Set(data.edition?.dateIntervals);
  const sections = templateSections(data.questions);

  function clearFieldError(event: ChangeEvent<HTMLFormElement>) {
    const id = event.target.closest('fieldset[id^="question-"]')?.id.slice('question-'.length);
    if (id && errors[id]) {
      setErrors(previous => {
        const next = { ...previous };
        delete next[id];
        return next;
      });
    }
    if (empty) setEmpty(false);
  }

  async function send(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (inFlight.current || code || outcome === 'changed') return;
    if (!body.current) {
      const form = event.currentTarget;
      const { answers, errors: fieldErrors } = readAnswers(form, data.questions, intervals);
      const first = Object.keys(fieldErrors)[0];
      setErrors(fieldErrors);
      setOutcome(null);
      setEmpty(!first && Object.keys(answers).length === 0);
      if (first) {
        const question = form.querySelector(`#question-${first}`);
        const section = question?.closest('details');
        if (section) section.open = true;
        question?.querySelector<HTMLElement>('input, select, textarea')?.focus();
        return;
      }
      if (Object.keys(answers).length === 0) { statusRef.current?.focus(); return; }
      body.current = JSON.stringify({ proof, answers });
    }
    inFlight.current = true;
    setPending(true);
    setOutcome(null);
    try {
      const response = await fetch(endpoint, {
        method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error',
        headers: { 'Content-Type': 'application/json' }, body: body.current,
        signal: AbortSignal.timeout(45_000),
      });
      const result = await response.json();
      if (response.ok && result.status === 'ok' && typeof result.code === 'string') {
        setCode(result.code);
        return;
      }
      if (result.status === 'invalid' && response.status === 422) body.current = null;
      setOutcome(Object.hasOwn(messages, result.status) ? result.status : 'unavailable');
    } catch {
      setOutcome('unavailable');
    } finally {
      inFlight.current = false;
      setPending(false);
      statusRef.current?.focus();
    }
  }

  return <form onSubmit={send} onChange={clearFieldError} noValidate className={s.sections}>
    <fieldset className={s.editorFields} disabled={pending || !!body.current || !!code}>
      {sections.map(section => <details key={section.id} className={`panel ${s.section}`}>
        <summary>{section.title}</summary>
        <div className={s.sectionContent}>
          {section.description && <p className={s.questionNote}>{section.description}</p>}
          {section.questions.length ? section.questions.map(question =>
            <AnswerControl key={question.id} question={question} interval={intervals.has(question.id)} error={errors[question.id]} />)
            : <p className={s.questionNote}>Nenhuma pergunta nesta seção.</p>}
        </div>
      </details>)}
    </fieldset>
    <div ref={statusRef} tabIndex={-1} aria-live="polite" className={s.submissionStatus}>
      {code && <p className="notice">Formulário enviado. Registro {code} em análise no portal EM.</p>}
      {empty && <p role="alert" className={s.fieldError}>Preencha pelo menos uma pergunta.</p>}
      {outcome && <p role="alert" className={s.fieldError}>{messages[outcome]}</p>}
    </div>
    {!code && <div className={s.submissionActions}>
      {outcome === 'changed' ? <button type="button" className="button secondary" onClick={() => window.location.reload()}>Reabrir formulário</button>
        : <button className="button" disabled={pending} type="submit">
          {pending ? 'Enviando…' : body.current ? 'Tentar o mesmo envio' : 'Enviar formulário'}
        </button>}
      {outcome === 'session' && <a href="/operacao/login" className="button secondary" target="_blank" rel="noopener noreferrer">Entrar em nova aba</a>}
    </div>}
  </form>;
}

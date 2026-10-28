import { useEffect, useRef, useState } from 'react';
import { ScrollView, Text, View } from 'react-native';
import { router } from 'expo-router';
import { service, type Answer } from '../core';
import { canCorrectAnswer, displayedRecordAnswers, emptyAnswer, firstInvalidSection, formSections, hasQuestionId, naAnswer, recordedQuestions, sectionForQuestion, storedAnswer, validateAnswer, type FormSection } from '../domain/forms';
import { canOpenForm, canReviseRecord } from '../domain/journey';
import { useApp, useRows } from './state';
import { Badge, Button, Card, Notice, Screen, s } from './components';
import { Question } from './question';
import { CollapseSection, FormSections } from './form-sections';
import { RecordedAnswer } from './recorded-answer';
import { JourneyUnavailable, journeyLabel, useJourney } from './journey';

export function FormScreen({ projectId, cellId, formId, recordId, mode = 'revision', focusQuestionId }: {
  projectId?: string; cellId?: string; formId?: string; recordId?: string; mode?: 'view' | 'revision'; focusQuestionId?: string;
}) {
  const app = useApp();
  const forms = useRows('rm_forms'); const items = useRows('rm_itens_questoes'); const users = useRows('rm_users'); const clients = useRows('rm_clientes'); const records = useRows('rm_registros_formulario'); const remoteAnswers = useRows('rm_respostas', { field: 'registro_formulario_id', value: recordId });
  const record = records.rows.find(row => row.id === recordId);
  const fId = formId || record?.form_id; const pId = projectId || record?.projeto_id; const cId = cellId || record?.celula_id;
  const questions = useRows('rm_questoes', { field: 'form_id', value: fId });
  const { context, error: journeyError } = useJourney(cId, pId);
  const form = forms.rows.find(row => row.id === fId);
  const templates = questions.rows.filter(question => question.form_id === fId).sort((a, b) => a.indice - b.indice);
  const originals = remoteAnswers.rows.filter(answer => answer.registro_formulario_id === recordId).map(storedAnswer);
  const mayOpen = canOpenForm(context, fId) && !!form && (recordId
    ? !!record && record.projeto_id === pId && record.celula_id === cId && record.form_id === fId
    : form.ativo === true);
  const mayCorrectRecord = context.ok && context.canEdit && canReviseRecord(context, record);
  const correctionMode = !!recordId && mode !== 'view' && mayCorrectRecord;
  const mayEdit = mayOpen && context.ok && context.canEdit && (!recordId || correctionMode);
  const loadDraft = mayOpen && (!recordId || correctionMode);
  const sourceAvailable = !recordId || originals.length > 0;
  const draftSourceAvailable = !recordId || originals.some(hasQuestionId);
  const contextKey = `${app.operator?.operador_id}:${pId}:${cId}:${fId}:${recordId || 'new'}`;
  const [loadedContext, setLoadedContext] = useState(''); const [draftId, setDraftId] = useState(''); const [submissionId, setSubmissionId] = useState('');
  const [answers, setAnswers] = useState<Record<string, Answer>>({}); const [status, setStatus] = useState('');
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [saving, setSaving] = useState(0); const [mediaBusy, setMediaBusy] = useState(0);
  const [validation, setValidation] = useState<Record<string, string>>({}); const [expandedId, setExpandedId] = useState<string | null>(null);
  const pending = useRef(Promise.resolve()); const saveErrors = useRef<Record<string, string>>({}); const answersRef = useRef<Record<string, Answer>>({}); const submitting = useRef(false);
  const scrollRef = useRef<ScrollView>(null); const listTop = useRef(0); const sectionPositions = useRef<Record<string, number>>({});
  const draftLoaded = !!draftId && loadedContext === contextKey;
  const shownAnswers = recordId ? displayedRecordAnswers(originals, correctionMode && draftLoaded ? answers : undefined) : answers;
  const qs = recordId ? recordedQuestions(templates, Object.values(shownAnswers)) : templates;
  const sections = formSections(qs); const expanded = sections.find(section => section.id === expandedId && section.subtitle);
  const locked = status !== 'in_progress' || !draftLoaded || busy || !mayEdit;

  useEffect(() => {
    let live = true; setDraftId(''); setLoadedContext(''); setSubmissionId(''); setStatus(''); setError('');
    if (pId && cId && fId && loadDraft && draftSourceAvailable) service.getDraft({ projeto_id: pId, celula_id: cId, form_id: fId, registro_formulario_id: recordId }).then(draft => {
      if (!live) return;
      const saved = Object.fromEntries(draft.answers.map(answer => [answer.questao_id, answer]));
      answersRef.current = saved; setAnswers(saved); saveErrors.current = {}; setValidation({});
      setDraftId(draft.draft_id); setSubmissionId(draft.client_submission_id); setStatus(draft.status); setLoadedContext(contextKey);
    }).catch(e => { if (live) setError(e.message); });
    return () => { live = false; };
  }, [pId, cId, fId, recordId, contextKey, loadDraft, draftSourceAvailable]);
  useEffect(() => { setExpandedId(null); sectionPositions.current = {}; }, [contextKey, mode]);
  useEffect(() => {
    let live = true;
    if (submissionId && status === 'ready_to_sync') service.operation(submissionId).then(operation => { if (live && operation?.status === 'completed') setStatus('synced'); }).catch(e => { if (live) setError(e.message); });
    return () => { live = false; };
  }, [submissionId, status, app.revision]);
  const focusedSection = sectionForQuestion(sections, focusQuestionId)?.id;
  useEffect(() => { if (focusedSection && mode !== 'view') { setExpandedId(focusedSection); scrollToSection(focusedSection); } }, [focusedSection, mode, contextKey]);

  function scrollToSection(id: string) {
    // Allow the native layout to update after switching/collapsing an expanded section.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const y = sectionPositions.current[id]; if (y !== undefined) scrollRef.current?.scrollTo({ y: Math.max(0, listTop.current + y - 12), animated: true });
    }));
  }
  function toggleSection(section: FormSection) { if (mediaBusy) return; setExpandedId(expandedId === section.id ? null : section.id); scrollToSection(section.id); }
  function openCorrection(questionId?: string) {
    if (!mayCorrectRecord || !recordId || !pId || !cId) return;
    router.replace({ pathname: '/revisao-form', params: { registro: recordId, projeto: pId, celula: cId, modo: 'corrigir', ...(questionId ? { questao: questionId } : {}) } });
  }
  function change(answer: Answer) {
    if (locked) return;
    const original = answersRef.current[answer.questao_id];
    if (recordId && !canCorrectAnswer(record, original)) return;
    const next = { ...answer, resposta_id: original?.resposta_id, revisar: original?.revisar };
    answersRef.current = { ...answersRef.current, [answer.questao_id]: next }; setAnswers(answersRef.current); setSaving(n => n + 1);
    // Call immediately so the core captures this operator before a possible operator switch.
    const write = service.saveAnswer(draftId, next).then(() => { delete saveErrors.current[answer.questao_id]; })
      .catch(e => { saveErrors.current[answer.questao_id] = e.message; setError(`Não foi possível salvar: ${e.message}`); })
      .finally(() => setSaving(n => Math.max(0, n - 1)));
    pending.current = Promise.all([pending.current, write]).then(() => undefined);
  }
  async function submit() {
    if (locked || mediaBusy || submitting.current) return;
    submitting.current = true; setBusy(true); setError('');
    try {
      await pending.current;
      if (Object.keys(saveErrors.current).length) throw new Error('Há respostas que não foram salvas. Edite os campos com falha e tente novamente.');
      const errors: Record<string, string> = {};
      for (const question of qs) {
        if (recordId && !canCorrectAnswer(record, answersRef.current[question.id])) continue;
        const message = validateAnswer(question, answersRef.current[question.id]); if (message) errors[question.id] = message;
      }
      setValidation(errors);
      if (Object.keys(errors).length) {
        const section = firstInvalidSection(sections, errors); if (section) { setExpandedId(section.id); scrollToSection(section.id); }
        throw new Error('Revise as questões destacadas antes de enviar. A primeira seção com pendências foi aberta.');
      }
      if (!qs.length) throw new Error('Sincronize as questões deste formulário antes de enviar.');
      const id = await service.submitDraft(draftId, recordId); setSubmissionId(id); setStatus('ready_to_sync');
      router.replace({ pathname: '/confirmacao', params: { id, tipo: recordId ? 'Revisão' : 'Formulário', projeto: pId, celula: cId } });
    } catch (e) { setError(e instanceof Error ? e.message : 'Falha ao enviar.'); } finally { submitting.current = false; setBusy(false); }
  }
  async function newInspection() {
    if (!pId || !cId || !fId || !mayEdit) return;
    setBusy(true); setError('');
    try {
      const draft = await service.startNewDraft({ projeto_id: pId, celula_id: cId, form_id: fId });
      setDraftId(draft.draft_id); setSubmissionId(draft.client_submission_id); setStatus(draft.status); setLoadedContext(contextKey);
      answersRef.current = {}; setAnswers({}); saveErrors.current = {}; setValidation({}); setExpandedId(null);
    } catch (e) { setError(e instanceof Error ? e.message : 'Falha ao iniciar outro preenchimento.'); } finally { setBusy(false); }
  }
  if (!context.ok) return <JourneyUnavailable context={context} error={journeyError} title="Formulário indisponível" />;
  const backHref = { pathname: '/formularios' as const, params: { projeto: context.project.id, celula: context.cell.id } };
  if (!mayOpen) return <Screen title="Formulário indisponível" eyebrow={journeyLabel(context)} backHref={backHref} backLabel="Formulários do projeto"><Notice error>{!canOpenForm(context, fId) ? 'Este formulário não está vinculado a este projeto e célula.' : 'O registro ou modelo ainda não está disponível no catálogo local. Sincronize novamente.'}</Notice></Screen>;
  const flagged = originals.filter(answer => canCorrectAnswer(record, answer)).length;
  const catalogError = forms.error || questions.error || remoteAnswers.error;
  const allErrors = { ...validation, ...saveErrors.current };
  return <Screen title={correctionMode ? 'Corrigir formulário' : form?.titulo ?? 'Formulário'} eyebrow={journeyLabel(context)} backHref={backHref} backLabel="Formulários do projeto" subtitle={recordId ? `Registro ${record?.codigo_text || record?.descricao || ''} · ${correctionMode ? 'Corrija somente as questões sinalizadas.' : 'Consulte as respostas enviadas.'}` : 'Abra um subtítulo para preencher suas questões. Cada alteração é salva neste dispositivo.'}
    scrollRef={scrollRef} floatingFooter={expanded && <CollapseSection section={expanded} disabled={!!mediaBusy} onCollapse={() => toggleSection(expanded)} />}>
    {!context.canEdit && <Notice error>{context.allocation.motivo_bloqueio || 'Execução bloqueada pelo planejamento. A consulta e seus rascunhos foram preservados.'}</Notice>}
    {record?.status === 'direcionado' && <Notice error>{record.parecer || (record.observacao_list ?? []).join('\n') || 'A engenharia solicitou revisão das questões sinalizadas.'}</Notice>}
    <Card><View style={s.row}><Badge text={recordId && !correctionMode ? 'Consulta do registro' : saving ? 'Salvando…' : status !== 'in_progress' && draftLoaded ? 'Envio registrado' : 'Rascunho local'} /><Text style={s.muted}>{qs.filter(question => question.tipo !== 'subt_tulo').length} questões</Text></View>
      {sections.some(section => section.subtitle) && <Text style={s.muted}>Os subtítulos começam recolhidos. Toque em um deles para visualizar suas questões.</Text>}
      {!locked && <Button secondary title="Preencher N/A nas questões vazias" onPress={() => { for (const question of qs) {
        const answer = answersRef.current[question.id] ?? emptyAnswer(question);
        if ((!recordId || canCorrectAnswer(record, answer)) && question.tipo !== 'subt_tulo' && !answer.resposta && !answer.itens?.length && !answer.fotos_urls?.some(Boolean) && !answer.assinatura_url && !answer.date_inicio && !answer.hora) change(naAnswer(question));
      } }} />}
      {recordId && !correctionMode && !mayCorrectRecord && <Text style={s.muted}>Após o envio, somente questões devolvidas pela engenharia ficam disponíveis para correção.</Text>}
      {recordId && !correctionMode && mayCorrectRecord && !!flagged && <Button title={`Corrigir ${flagged} ${flagged === 1 ? 'questão sinalizada' : 'questões sinalizadas'}`} onPress={() => openCorrection()} />}
      {draftLoaded && status !== 'in_progress' && <><Notice>{status === 'synced' ? 'O envio foi confirmado. As respostas permanecem disponíveis para consulta.' : 'Este envio está salvo e protegido contra alterações até a confirmação.'}</Notice><Button secondary title="Consultar envio" onPress={() => router.push({ pathname: '/confirmacao', params: { id: submissionId, tipo: recordId ? 'Revisão' : 'Formulário', projeto: pId, celula: cId } })} /></>}
    </Card>
    {status === 'synced' && !recordId && mayEdit && <Button secondary title="Iniciar novo preenchimento" busy={busy} onPress={() => { void newInspection(); }} />}
    {!!catalogError && <Notice error>{catalogError}</Notice>}
    {!sourceAvailable && <Notice>As respostas deste registro ainda não estão disponíveis neste dispositivo. Sincronize para consultá-las.</Notice>}
    {sourceAvailable && !qs.length && <Notice>Não há questões disponíveis neste dispositivo. Sincronize o catálogo.</Notice>}
    {correctionMode && sourceAvailable && !flagged && <Notice>Não há questões sinalizadas disponíveis para correção. Sincronize o registro novamente.</Notice>}
    <FormSections sections={sections} expandedId={expandedId} answers={shownAnswers} errors={allErrors} disabled={!!mediaBusy}
      onToggle={toggleSection} onListLayout={y => { listTop.current = y; }} onSectionLayout={(id, y) => { sectionPositions.current[id] = y; }}
      renderQuestion={question => {
        const answer = shownAnswers[question.id];
        const editable = !locked && (!recordId || canCorrectAnswer(record, answer));
        return <View key={question.id} style={{ gap: 8 }}>{editable ? <>{recordId && <Badge text="Resposta em revisão" alert />}<Question q={question} answer={hasQuestionId(answer) ? answer : undefined} items={items.rows} users={users.rows} clients={clients.rows} onChange={change} onMediaBusy={value => setMediaBusy(n => Math.max(0, n + (value ? 1 : -1)))} error={allErrors[question.id]} /></>
          : <RecordedAnswer question={question} answer={answer} onCorrect={recordId && !correctionMode && mayCorrectRecord && canCorrectAnswer(record, answer) ? () => openCorrection(question.id) : undefined} />}</View>;
      }} />
    {!!mediaBusy && <Notice>Salvando as fotos no dispositivo… Aguarde para recolher ou trocar de seção.</Notice>}{!!error && <Notice error>{error}</Notice>}
    {(!recordId || correctionMode) && <Button title={recordId ? 'Enviar correção' : 'Concluir e enviar'} busy={busy} disabled={locked || !!saving || !!mediaBusy || !qs.length || (!!recordId && !flagged)} onPress={() => { void submit(); }} />}
  </Screen>;
}

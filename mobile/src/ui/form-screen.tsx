import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { router } from 'expo-router';
import { service, type Answer, type Row } from '../core';
import { emptyAnswer, naAnswer, validateAnswer } from '../domain/forms';
import { useApp, useRows } from './state';
import { Badge, Button, Card, Notice, Screen, s } from './components';
import { Question } from './question';
export function FormScreen({ projectId, cellId, formId, recordId }: { projectId?: string; cellId?: string; formId?: string; recordId?: string }) {
  const app = useApp();
  const forms = useRows('rm_forms'); const questions = useRows('rm_questoes'); const items = useRows('rm_itens_questoes'); const users = useRows('rm_users'); const clients = useRows('rm_clientes'); const records = useRows('rm_registros_formulario');
  const record = records.rows.find(r => r.id === recordId);
  const fId = formId || record?.form_id; const pId = projectId || record?.projeto_id; const cId = cellId || record?.celula_id;
  const cellAllowed = app.operator?.perfil === 'administrador' || !!app.operator?.celulas_vinculadas.some(link => link.celula_id === cId);
  const form = forms.rows.find(f => f.id === fId);
  const qs = questions.rows.filter(q => q.form_id === fId).sort((a,b) => a.indice - b.indice);
  const [draftId, setDraftId] = useState(''); const [answers, setAnswers] = useState<Record<string, Answer>>({}); const [status, setStatus] = useState('');
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [saving, setSaving] = useState(0); const [validation, setValidation] = useState<Record<string,string>>({});
  const [mediaBusy,setMediaBusy] = useState(0);
  const pending = useRef(Promise.resolve()); const saveErrors = useRef<Record<string,string>>({}); const answersRef = useRef<Record<string, Answer>>({});
  useEffect(() => { let live = true; setDraftId(''); setError(''); if (pId && cId && fId) { if (!cellAllowed) {setError('Esta célula não está vinculada ao dispositivo. Solicite o vínculo ao supervisor.');return;} service.getDraft({ projeto_id:pId,celula_id:cId,form_id:fId,registro_formulario_id:recordId }).then(draft => { if (live) { setDraftId(draft.draft_id); setStatus(draft.status); const a = Object.fromEntries(draft.answers.map(a => [a.questao_id,a])); answersRef.current=a; setAnswers(a); saveErrors.current={}; setValidation({}); } }).catch(e => { if (live) setError(e.message); }); } return () => { live=false; }; }, [pId,cId,fId,recordId,app.operator?.operador_id,cellAllowed]);
  function change(a: Answer) {
    const original = answersRef.current[a.questao_id];
    const next = {...a,resposta_id:original?.resposta_id,revisar:original?.revisar};
    answersRef.current={...answersRef.current,[a.questao_id]:next}; setAnswers(answersRef.current); setSaving(n => n+1);
    // Call immediately so the core captures this operator before a possible operator switch.
    const write = service.saveAnswer(draftId,next).then(() => { delete saveErrors.current[a.questao_id]; })
      .catch(e => { saveErrors.current[a.questao_id]=e.message; setError(`Não foi possível salvar: ${e.message}`); })
      .finally(() => setSaving(n => Math.max(0,n-1)));
    pending.current=Promise.all([pending.current,write]).then(() => undefined);
  }
  async function submit() { setBusy(true); setError(''); try {
    await pending.current;
    if (Object.keys(saveErrors.current).length) throw new Error('Há respostas que não foram salvas. Edite os campos com falha e tente novamente.');
    const errors: Record<string,string>={}; for (const q of qs) { if (recordId && !answersRef.current[q.id]?.revisar) continue; const e=validateAnswer(q,answersRef.current[q.id]); if (e) errors[q.id]=e; }
    setValidation(errors); if (Object.keys(errors).length) throw new Error('Revise as questões destacadas antes de enviar.');
    if (!qs.length) throw new Error('Sincronize as questões deste formulário antes de enviar.');
    const id=await service.submitDraft(draftId,recordId); setStatus('ready_to_sync'); router.replace({pathname:'/confirmacao',params:{id,tipo:recordId ? 'Revisão' : 'Formulário'}});
  } catch(e) { setError(e instanceof Error ? e.message : 'Falha ao enviar.'); } finally { setBusy(false); } }
  async function newInspection() { if (!pId || !cId || !fId) return; setBusy(true); setError(''); try { const draft=await service.startNewDraft({projeto_id:pId,celula_id:cId,form_id:fId}); setDraftId(draft.draft_id);setStatus(draft.status);answersRef.current={};setAnswers({});saveErrors.current={};setValidation({}); } catch(e) {setError(e instanceof Error ? e.message : 'Falha ao iniciar outro preenchimento.');} finally {setBusy(false);} }
  const locked = status !== 'in_progress' || !draftId || busy;
  return <Screen title={recordId ? 'Corrigir formulário' : form?.titulo ?? 'Preencher formulário'} subtitle={form?.descricao ?? 'As respostas são salvas neste dispositivo a cada alteração.'}>
    {recordId && <Notice error>{record?.parecer || (record?.observacao_list ?? []).join('\n') || 'A engenharia solicitou uma revisão. Confira os itens sinalizados.'}</Notice>}
    <Card><View style={s.row}><Badge text={saving ? 'Salvando…' : locked && draftId ? 'Envio registrado' : 'Rascunho local'} /><Text style={s.muted}>{qs.filter(q => q.tipo !== 'subt_tulo').length} questões</Text></View>{!locked && <Button secondary title="Preencher N/A nas questões vazias" onPress={() => { for (const q of qs) { const a = answersRef.current[q.id] ?? emptyAnswer(q); if ((!recordId || a.revisar) && q.tipo !== 'subt_tulo' && !a.resposta && !a.itens?.length && !a.fotos_urls?.some(Boolean) && !a.assinatura_url && !a.date_inicio && !a.hora) change(naAnswer(q)); } }} />}{locked && draftId && <Notice>Este envio está protegido contra alterações. Consulte a fila ou volte para a lista de formulários.</Notice>}</Card>
    {status === 'synced' && !recordId && <Button secondary title="Iniciar novo preenchimento" busy={busy} onPress={() => { void newInspection(); }} />}
    {forms.error || questions.error ? <Notice error>{forms.error || questions.error}</Notice> : null}
    {!qs.length && <Notice>Não há questões disponíveis neste dispositivo. Sincronize o catálogo.</Notice>}
    {qs.map(q => <View key={q.id} style={{ gap: 8 }}>{recordId && answers[q.id]?.revisar && <Badge text="Resposta em revisão" alert />}<Question q={q} answer={answers[q.id]} items={items.rows} users={users.rows} clients={clients.rows} onChange={change} onMediaBusy={value => setMediaBusy(n => Math.max(0,n+(value ? 1 : -1)))} disabled={locked || (!!recordId && !answers[q.id]?.revisar)} error={validation[q.id] || saveErrors.current[q.id]} /></View>)}
    {!!mediaBusy && <Notice>Salvando as fotos no dispositivo…</Notice>}{!!error && <Notice error>{error}</Notice>}<Button title={recordId ? 'Enviar correção' : 'Concluir e enviar'} busy={busy} disabled={locked || !!saving || !!mediaBusy || !qs.length} onPress={() => { void submit(); }} />
  </Screen>;
}

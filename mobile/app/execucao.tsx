import { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import * as Crypto from 'expo-crypto';
import { service } from '../src/core';
import { EXECUTION_RPC, PAUSE_REASONS, executionMinutes, executionReviewReasonLabel, projectExecution, type ExecutionKind, type ExecutionParams, type PauseReason } from '../src/core/execution';
import { executionReadRefused, newestExecutionView, type ExecutionLocalView } from '../src/core/execution-cache';
import { canAccessCell } from '../src/domain/journey';
import { useApp, useRouteFocused, useRows } from '../src/ui/state';
import { Badge, Button, Card, Field, Notice, Screen, Select, s } from '../src/ui/components';

const stateLabels = { running: 'Em andamento', paused: 'Pausado', finished: 'Apontamento encerrado', review: 'Aguardando revisão', void: 'Anulado pela gestão' };
const actionLabels: Record<ExecutionKind, string> = { start: 'Iniciar trabalho', pause: 'Pausar trabalho', resume: 'Retomar trabalho', finish: 'Encerrar apontamento' };
const reasons: Record<PauseReason, string> = { material: 'Material', cliente: 'Cliente', engenharia: 'Engenharia', ferramenta: 'Ferramenta', maquina: 'Máquina', manutencao: 'Manutenção', transporte: 'Transporte', servico_externo: 'Serviço externo', intervalo: 'Intervalo', outro: 'Outro motivo' };
const at = (value: string | null) => value ? new Date(value).toLocaleString('pt-BR') : 'Não confirmado';
type ReviewDraft = { id: string; params: ExecutionParams; attempted: boolean };

export default function Execucao() {
  const params = useLocalSearchParams<{ celula?: string; projeto?: string; allocation?: string }>();
  const app = useApp(), focused = useRouteFocused(), allocations = useRows('rm_celulas_projeto');
  const allocationId = params.allocation || allocations.rows.find(row => row.projeto_id === params.projeto && row.celula_id === params.celula && !row.retirada)?.id;
  const owner = app.sessionUserId, actorId = app.operator?.operador_id, key = `${owner}:${actorId}:${allocationId}`;
  const [view, setView] = useState<ExecutionLocalView | null>(null), [loadedKey, setLoadedKey] = useState('');
  const [queueReady, setQueueReady] = useState(false), [loading, setLoading] = useState(false);
  const [readRefused, setReadRefused] = useState(false);
  const [error, setError] = useState(''), [queueError, setQueueError] = useState(''), [refresh, setRefresh] = useState(0);
  const [note, setNote] = useState(''), [pauseReason, setPauseReason] = useState<PauseReason | ''>(''), [minutes, setMinutes] = useState('');
  const [draft, setDraft] = useState<ReviewDraft | null>(null), [busy, setBusy] = useState(false), [receiptId, setReceiptId] = useState('');
  const sending = useRef(false), currentKey = useRef(key); currentKey.current = key;
  useEffect(() => { setView(null); setLoadedKey(''); setQueueReady(false); setReadRefused(false); setDraft(null); setNote(''); setPauseReason(''); setMinutes(''); setReceiptId(''); setError(''); }, [key]);
  useEffect(() => {
    let live = true;
    if (!focused || !owner || !actorId || !allocationId || !app.ready) return;
    setLoading(true); setError('');
    void (async () => {
      const cached = await service.executionSnapshot(allocationId, false);
      if (live && currentKey.current === key) { setView(previous => newestExecutionView(previous, cached)); setLoadedKey(key); }
      if (app.online) {
        const fresh = await service.executionSnapshot(allocationId, true);
        if (live && currentKey.current === key) { setView(previous => newestExecutionView(previous, fresh)); setLoadedKey(key); setReadRefused(false); }
      }
    })().catch(e => {
      if (live && currentKey.current === key) {
        if (executionReadRefused(e)) setReadRefused(true);
        setError(e instanceof Error ? e.message : 'Não foi possível consultar os apontamentos.');
      }
    }).finally(() => { if (live && currentKey.current === key) setLoading(false); });
    return () => { live = false; };
  }, [focused, owner, actorId, allocationId, app.ready, app.online, app.lastSync, key, refresh]);
  useEffect(() => {
    let live = true;
    if (!focused || !owner || !actorId || !allocationId || !app.ready) return;
    // Revision refreshes SQLite only. Server reads depend on focus/lastSync,
    // preventing a fetch -> revision -> fetch loop.
    service.executionSnapshot(allocationId, false).then(local => { if (live && currentKey.current === key) { setView(previous => newestExecutionView(previous, local)); setLoadedKey(key); setQueueReady(true); setQueueError(''); } }).catch(e => { if (live) { setQueueReady(false); setQueueError(e.message); } });
    return () => { live = false; };
  }, [focused, owner, actorId, allocationId, app.ready, app.revision, key]);
  const candidate = view?.snapshot;
  const current = !readRefused && loadedKey === key && candidate && candidate.operator_id === actorId ? candidate : null;
  const projection = useMemo(() => current ? projectExecution(current, view?.operations ?? [], !!view?.safeToAppend, view?.contexts) : null, [current, view?.operations, view?.safeToAppend, view?.contexts]);
  const allowed = !!current && canAccessCell(app.operator, current.allocation.cell_id);
  const back = params.projeto && params.celula ? { pathname: '/projeto' as const, params: { projeto: params.projeto, celula: params.celula } } : '/celula' as const;
  const session = projection?.session;
  const closedContext = !!current && (current.allocation.project_closed || current.allocation.retired || !current.allocation.visible || current.allocation.blocked || ['finalizado', 'n_a'].includes(current.allocation.status ?? ''));
  const enabled = !!current && allowed && queueReady && !!view?.safeToAppend && !projection?.uncertain && !busy && !draft;
  function prepare(kind: ExecutionKind) {
    if (!enabled || !projection || !current || note.length > 1000) return;
    if (kind === 'pause' && !pauseReason) { setError('Selecione o motivo da pausa.'); return; }
    if (kind === 'pause' && pauseReason === 'outro' && note.trim().length < 3) { setError('Descreva o outro motivo da pausa com pelo menos três caracteres.'); return; }
    const effort = minutes.trim() ? executionMinutes(minutes) : null;
    if (kind === 'finish' && minutes.trim() && effort === null) { setError('Informe minutos inteiros de 0 a 1.000.000, ou deixe em branco.'); return; }
    if (kind !== 'start' && (!session || !session.last_event_id)) return;
    setError(''); setDraft({ id: Crypto.randomUUID(), attempted: false, params: { p_session_id: kind === 'start' ? Crypto.randomUUID() : session!.id, p_allocation_id: current.allocation.id,
      p_previous_event_id: kind === 'start' ? null : session!.last_event_id, p_kind: kind, p_occurred_at: new Date().toISOString(), p_pause_reason: kind === 'pause' ? pauseReason as PauseReason : null,
      p_note: note.trim() || null, p_effort_minutes: kind === 'finish' ? effort : null } });
  }
  async function confirm() {
    if (!draft || !current || !queueReady || !draft.attempted && (!view?.safeToAppend || projection?.uncertain) || sending.current) return;
    sending.current = true; setBusy(true); setError(''); const intention = draft, author = actorId;
    setDraft({ ...intention, attempted: true });
    try {
      if (currentKey.current !== key || service.getSnapshot().operator?.operador_id !== author) throw new Error('O operador mudou. Retome com o responsável pelo apontamento.');
      const id = await service.recordExecutionEvent(intention.params, intention.id);
      if (currentKey.current !== key) return;
      setReceiptId(id); setDraft(null); setNote(''); setMinutes(''); setPauseReason('');
      const local = await service.executionSnapshot(current.allocation.id, false); setView(previous => newestExecutionView(previous, local));
    } catch (e) {
      if (currentKey.current !== key) return;
      try {
        const saved = await service.operation(intention.id);
        if (saved && saved.actor_id === author && saved.rpc_name === EXECUTION_RPC) { setReceiptId(saved.id); setDraft(null); const local = await service.executionSnapshot(current.allocation.id, false); setView(previous => newestExecutionView(previous, local)); }
        else setDraft({ ...intention, attempted: false });
      } catch { /* Keep the exact protocol frozen when local persistence is uncertain. */ }
      setError(e instanceof Error ? e.message : 'O apontamento não foi confirmado. Tente com o mesmo protocolo.');
    } finally { sending.current = false; if (currentKey.current === key) setBusy(false); }
  }
  return <Screen title="Apontamentos de execução" eyebrow="SEU TRABALHO NA ETAPA" subtitle="Registre início, pausas, retomada e encerramento com sua identidade." backHref={back} backLabel={typeof back === 'string' ? 'Escolher célula' : 'Voltar ao projeto'}>
    {(error || queueError || allocations.error) && <Notice error>{error || queueError || allocations.error}</Notice>}
    {loading && <ActivityIndicator />}
    {!allocationId && <Notice>Selecione uma etapa disponível no projeto para consultar os apontamentos.</Notice>}
    {allocationId && !current && !loading && <Notice>{app.online ? 'Não foi possível carregar o contexto desta etapa. Tente atualizar a consulta.' : 'Conecte uma vez e consulte esta etapa para preparar seus apontamentos offline. Os envios e rascunhos existentes continuam preservados.'}</Notice>}
    <Button secondary title="Atualizar consulta" disabled={!allocationId || loading || busy || !!draft} onPress={() => setRefresh(n => n + 1)} />
    {current && !allowed && <Notice error>Esta célula não está mais vinculada ao operador identificado. Os registros locais permanecem preservados.</Notice>}
    {current && allowed && projection && <>
      <Card><Text style={s.h2}>{current.allocation.numero_projeto ? `OS ${current.allocation.numero_projeto}` : 'Projeto sem OS'} · {current.allocation.cell_name || 'Célula'}</Text><Text style={s.body}>{app.operator?.nome}</Text><Badge text={session ? stateLabels[session.state] : 'Sem apontamento aberto nesta etapa'} alert={!!session?.needs_review} />
        <Text style={s.muted}>Consulta confirmada em {at(current.as_of)}.</Text>{session && <><Text style={s.muted}>Último horário informado: {at(session.last_captured_at)}</Text><Text style={s.muted}>Último recebimento confirmado: {at(session.last_received_at)}</Text>{session.confirmed_minutes !== null && <Text style={s.body}>{session.confirmed_minutes} minutos informados {session.effort_source === 'manager' ? 'pela gestão' : 'pelo operador'}.</Text>}</>}
        {Object.values(view?.contexts ?? {}).filter(context => context.allocation.id !== current.allocation.id && canAccessCell(app.operator, context.allocation.cell_id)).map(context => <Text key={context.allocation.id} style={s.muted}>Contexto salvo: {context.allocation.numero_projeto ? `OS ${context.allocation.numero_projeto}` : 'Projeto'} · {context.allocation.cell_name || 'Célula'} · consulta de {at(context.as_of)}.</Text>)}
        {!!projection.pending && <Notice>{projection.pending} registro(s) deste dispositivo aguardam confirmação. O estado acima inclui sua prévia local.</Notice>}
        {!view?.safeToAppend && <Notice>Atualize a consulta com conexão antes de registrar outra ação. Os dados e protocolos anteriores permanecem preservados.</Notice>}
        {(session?.clock_warning || projection.uncertain) && <Notice error>Há horários ou envios que precisam de conferência. Os registros foram preservados; consulte a gestão para reconciliar divergências.</Notice>}
      </Card>
      {closedContext && <Notice>Esta etapa está bloqueada, oculta ou encerrada. O início e a retomada estão indisponíveis. O encerramento de um apontamento anterior permanece disponível para conferência da gestão.</Notice>}
      {projection.runningSession && projection.runningSession.allocation_id !== current.allocation.id && <Card><Notice>Existe um apontamento em andamento em outra etapa. Pause ou encerre esse trabalho antes de iniciar ou retomar outro.</Notice>{canAccessCell(app.operator, projection.runningSession.cell_id) && !!projection.runningSession.project_id && <Button secondary title="Abrir trabalho em andamento" onPress={() => router.push({ pathname: '/execucao', params: { allocation: projection.runningSession!.allocation_id, projeto: projection.runningSession!.project_id, celula: projection.runningSession!.cell_id } })} />}</Card>}
      <Card><Text style={s.h2}>Registrar atividade</Text><Notice>Os horários são informados pelo dispositivo. Minutos trabalhados são declarados por você; o sistema não usa um cronômetro para preencher horas realizadas ou capacidade.</Notice>
        <Field label="Observação (opcional)" value={note} onChangeText={setNote} maxLength={1000} multiline editable={!busy && !draft} />
        {session?.state === 'running' && <Select label="Motivo da pausa" value={pauseReason} options={PAUSE_REASONS.map(value => ({ value, label: reasons[value] }))} onChange={values => setPauseReason(values[0] as PauseReason)} disabled={busy || !!draft} />}
        {session && ['running', 'paused'].includes(session.state) && <Field label="Minutos trabalhados ao encerrar (opcional)" value={minutes} onChangeText={setMinutes} keyboardType="number-pad" placeholder="Deixe em branco quando não informado" editable={!busy && !draft} maxLength={7} />}
        <View style={{ gap: 10 }}>
          {(!session || !['running', 'paused'].includes(session.state)) && <Button title="Iniciar trabalho" disabled={!enabled || closedContext || !!projection.runningSession || projection.uncertain} onPress={() => prepare('start')} />}
          {session?.state === 'running' && <Button secondary title="Pausar trabalho" disabled={!enabled} onPress={() => prepare('pause')} />}
          {session?.state === 'paused' && <Button title="Retomar trabalho" disabled={!enabled || closedContext || !!projection.runningSession} onPress={() => prepare('resume')} />}
          {session && ['running', 'paused'].includes(session.state) && <Button title="Encerrar apontamento" disabled={!enabled} onPress={() => prepare('finish')} />}
        </View>
      </Card>
      {draft && <Card><Text style={s.h2}>Revisar antes de registrar</Text><Text style={s.body}>{actionLabels[draft.params.p_kind]}</Text><Text style={s.body}>Horário do dispositivo: {at(draft.params.p_occurred_at)}</Text>{draft.params.p_pause_reason && <Text style={s.body}>Motivo: {reasons[draft.params.p_pause_reason]}</Text>}{draft.params.p_note && <Text style={s.body}>{draft.params.p_note}</Text>}{draft.params.p_kind === 'finish' && <Text style={s.body}>Minutos trabalhados: {draft.params.p_effort_minutes === null ? 'não informados' : draft.params.p_effort_minutes}</Text>}<Notice>A confirmação salva o protocolo neste dispositivo. A aceitação ou necessidade de revisão será apresentada após o envio.</Notice><Button title={draft.attempted ? 'Confirmar com o mesmo protocolo' : 'Confirmar registro'} disabled={!draft.attempted && (!view?.safeToAppend || !!projection.uncertain)} busy={busy} onPress={() => { void confirm(); }} /><Button secondary title="Voltar e corrigir" disabled={busy || draft.attempted} onPress={() => setDraft(null)} /></Card>}
      {!!receiptId && <Card><Notice>Registro salvo com seu protocolo original. Consulte a confirmação para distinguir envio pendente, aceitação e revisão.</Notice><Button secondary title="Consultar envio do apontamento" onPress={() => router.push({ pathname: '/confirmacao', params: { id: receiptId, tipo: 'Apontamento', projeto: current.allocation.project_id, celula: current.allocation.cell_id } })} /></Card>}
      {(current.review_sessions_total > 0 || projection.reviewOperations.length > 0 || session?.needs_review) && <Card><Text style={s.h2}>Apontamentos para revisão</Text><Notice>Os registros foram recebidos e preservados. A gestão poderá conferir o encerramento ou anular o apontamento, mantendo o histórico.</Notice>{current.review_sessions.map(row => <Text style={s.muted} key={row.id}>Sessão {row.id.slice(0, 8)} · {stateLabels[row.state]}</Text>)}{projection.reviewOperations.map(row => <Text key={row.id} style={s.muted}>Protocolo {row.id.slice(0, 8)} · {row.reason}</Text>)}{!current.review_sessions_complete && <Notice>Exibindo {current.review_sessions.length} sessões recentes de {current.review_sessions_total} que precisam de revisão.</Notice>}</Card>}
      <Card><Text style={s.h2}>Histórico confirmado</Text>{!current.events_complete && <Notice>Exibindo {current.events.length} eventos recentes de {current.events_total}. A situação atual da sessão é consultada separadamente e continua disponível.</Notice>}{!current.events.length && <Text style={s.muted}>Nenhum evento confirmado nesta consulta.</Text>}{current.events.map(event => <View key={event.id} style={{ gap: 4, paddingVertical: 8 }}><Badge text={event.disposition === 'review' ? 'Recebido para revisão' : 'Confirmado'} alert={event.disposition === 'review'} /><Text style={s.body}>{actionLabels[event.kind]} · {at(event.occurred_at)}</Text><Text style={s.muted}>Recebido em {at(event.received_at)}</Text>{event.pause_reason && <Text style={s.muted}>{reasons[event.pause_reason]}</Text>}{event.note && <Text style={s.muted}>{event.note}</Text>}{event.review_reason && <Text style={s.muted}>{executionReviewReasonLabel(event.review_reason)}</Text>}</View>)}</Card>
      {!!projection.localEvents.length && <Card><Text style={s.h2}>Registros deste dispositivo</Text>{projection.localEvents.map(event => <View key={event.id} style={{ gap: 4, paddingVertical: 8 }}><Text style={s.body}>{actionLabels[event.params.p_kind]} · {at(event.params.p_occurred_at)}</Text><Text style={s.muted}>{event.status === 'completed' ? 'Envio recebido; consulte a revisão e o histórico confirmado.' : 'Salvo para envio'} · protocolo {event.id.slice(0, 8)}</Text>{event.error && <Notice error>{event.error}</Notice>}</View>)}</Card>}
      {!!current.reviews.length && <Card><Text style={s.h2}>Conferências da gestão</Text>{!current.reviews_complete && <Notice>Exibindo {current.reviews.length} conferências recentes de {current.reviews_total}.</Notice>}{current.reviews.map(row => <View key={row.id} style={{ gap: 4, paddingVertical: 8 }}><Text style={s.body}>{row.action === 'void' ? 'Apontamento anulado' : 'Encerramento conferido'} · {row.actor_name || 'Gestão'}</Text><Text style={s.muted}>{at(row.created_at)} · {row.reason}</Text>{row.effort_minutes !== null && <Text style={s.muted}>{row.effort_minutes} minutos confirmados.</Text>}{row.note && <Text style={s.muted}>{row.note}</Text>}</View>)}</Card>}
      <Notice>Encerrar seu apontamento não finaliza a etapa, não responde formulários e não libera aprovações.</Notice>
    </>}
  </Screen>;
}

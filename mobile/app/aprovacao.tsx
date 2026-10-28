import { Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import type { OutboxRow, Row } from '../src/core';
import { label } from '../src/domain/forms';
import type { JourneyContext } from '../src/domain/journey';
import { availableStageActions, cellProjectLogs, cellProjectStages, cellStatusLabel, queuedProjectActions, stageActionLabels, type StageAction } from '../src/domain/project-actions';
import { useApp, useRows } from '../src/ui/state';
import { useQueue } from '../src/ui/queue';
import { useActionDraft } from '../src/ui/action-draft';
import { Badge, Button, Card, Field, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';

function ApprovalCard({ stage, context, cells, users, queue, queueReady }: { stage: Row; context: Extract<JourneyContext, { ok: true }>; cells: Row[]; users: Row[]; queue: OutboxRow[]; queueReady: boolean }) {
  const app = useApp();
  const draft = useActionDraft<{ action: StageAction | ''; note: string }>(`approval:${stage.id}:${stage.updated_at}`, { action: '', note: '' });
  const allowed = availableStageActions(app.operator, context, stage);
  const pending = queuedProjectActions(queue, 'rm_transition_stage_approval_v1', { field: 'p_aprovacao_etapa_id', id: stage.id })[0]?.operation;
  const receipt = pending?.id || (draft.draft?.submitted ? draft.draft.id : undefined);
  const decided = stage.status != null && stage.status !== 'nulo';
  const destination = cells.find(cell => cell.id === stage.celula_destino_id)?.nome;
  function showReceipt(id: string) { router.push({ pathname: '/confirmacao', params: { id, tipo: 'Aprovação', projeto: context.project.id, celula: context.cell.id } }); }
  async function submit() {
    if (!queueReady || receipt) return;
    const id = await draft.submit('rm_transition_stage_approval_v1', values => {
      if (!values.action || !allowed.includes(values.action)) throw new Error('Esta ação não está disponível para o operador e status atuais.');
      if (values.action === 'retornar' && !values.note.trim()) throw new Error('Informe o motivo do retorno.');
      return { p_aprovacao_etapa_id: stage.id, p_acao: values.action, p_observacao: values.note.trim() || null };
    });
    if (id) showReceipt(id);
  }
  return <Card><Text style={s.h2}>{stage.status_cel_proj === 'retornado' ? 'Etapa de retorno' : `Liberação · ${cellStatusLabel(stage.status_cel_proj)}`}</Text>{destination && <Text style={s.body}>Destino: {destination}</Text>}<Badge text={label(stage.status || 'nulo')} />
    {decided ? <><Text style={s.body}>Decisão registrada por {users.find(user => user.id === stage.aprovado_por_id)?.nome || 'aprovador responsável'}.</Text>{stage.data_aprovacao && <Text style={s.muted}>{new Date(stage.data_aprovacao).toLocaleString('pt-BR')}</Text>}</>
      : receipt ? <><Notice>Há uma decisão registrada neste dispositivo. O envio preserva o operador responsável.</Notice>{!!pending?.last_error && <Notice error>{pending.last_error}</Notice>}<Button secondary title="Consultar decisão enviada" onPress={() => showReceipt(receipt)} /></>
      : !queueReady || !draft.draft ? <Notice>Consultando decisões salvas neste dispositivo…</Notice>
      : !allowed.length ? <Notice>Não há decisão disponível para seu perfil e o status atual da célula. Status da célula: {cellStatusLabel(context.allocation.status)}.</Notice>
      : <><Field label="Observação (obrigatória para retornar)" multiline maxLength={10000} value={draft.draft.values.note} onChangeText={note => draft.update({ note })} editable={!draft.busy} />
        <View style={s.row}>{allowed.map(action => <Button key={action} title={stageActionLabels[action]} disabled={draft.busy} secondary={draft.draft?.values.action !== action} onPress={() => draft.update({ action })} />)}</View>
        {!!draft.draft.values.action && <Notice>Decisão selecionada: {stageActionLabels[draft.draft.values.action]}. Ela será registrada com sua identidade.</Notice>}
        <Button title="Confirmar decisão" busy={draft.busy} disabled={!draft.draft.values.action || !!draft.saving || !allowed.includes(draft.draft.values.action as StageAction)} onPress={() => { void submit(); }} />
      </>}{!!draft.error && <Notice error>{draft.error}</Notice>}
  </Card>;
}

export default function Aprovacao() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>();
  const { context, error } = useJourney(celula, projeto); const stages = useRows('rm_aprovacoes_etapas'); const cells = useRows('rm_celulas'); const logs = useRows('rm_logs_aprovacao'); const users = useRows('rm_users'); const queue = useQueue();
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Selecione um projeto" />;
  const rows = cellProjectStages(context.allocation, stages.rows); const history = cellProjectLogs(context.allocation, logs.rows);
  return <Screen title="Aprovações da célula" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Consulte as decisões e as ações disponíveis para esta etapa.">
    {(stages.error || logs.error || queue.error) && <Notice error>{stages.error || logs.error || queue.error}</Notice>}
    {!rows.length && <Notice>Nenhuma etapa de aprovação configurada para esta célula no projeto.</Notice>}
    {rows.map(stage => <ApprovalCard key={stage.id} stage={stage} context={context} cells={cells.rows} users={users.rows} queue={queue.rows} queueReady={queue.ready} />)}
    <Text style={s.h2}>Histórico de decisões</Text>{!history.length && <Notice>Nenhum registro de aprovação no catálogo local para esta célula.</Notice>}
    {history.map(log => <Card key={log.id}><Badge text={label(log.status_aprovacao)} /><Text style={s.body}>{users.rows.find(user => user.id === log.aprovador_id)?.nome || 'Aprovador registrado'}</Text><Text style={s.muted}>{new Date(log.data_aprovacao || log.created_at).toLocaleString('pt-BR')}</Text></Card>)}
  </Screen>;
}

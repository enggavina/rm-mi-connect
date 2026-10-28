import { Text } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { cellProjectComments, queuedProjectActions } from '../src/domain/project-actions';
import { useRows } from '../src/ui/state';
import { useQueue } from '../src/ui/queue';
import { useActionDraft } from '../src/ui/action-draft';
import { Badge, Button, Card, Field, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';

export default function Comentarios() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>();
  const { context, error } = useJourney(celula, projeto); const comments = useRows('rm_comentarios'); const users = useRows('rm_users'); const queue = useQueue();
  const draft = useActionDraft(`comment:${projeto}:${celula}`, { text: '' });
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Comentários indisponíveis" />;
  const rows = cellProjectComments(context.allocation, comments.rows);
  const pending = queuedProjectActions(queue.rows, 'rm_add_cell_comment_v1', { field: 'p_celula_projeto_id', id: context.allocation.id });
  function showReceipt(id: string) { router.push({ pathname: '/confirmacao', params: { id, tipo: 'Comentário', projeto: projeto!, celula: celula! } }); }
  async function submit() {
    if (!context.ok || !queue.ready) return;
    const id = await draft.submit('rm_add_cell_comment_v1', values => {
      const text = values.text.trim(); if (!text || text.length > 10000) throw new Error('Informe um comentário de até 10000 caracteres.');
      return { p_celula_projeto_id: context.allocation.id, p_comentario: text };
    });
    if (id) showReceipt(id);
  }
  return <Screen title="Comentários da célula" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Registre observações e acompanhe o histórico desta célula no projeto.">
    {(comments.error || queue.error) && <Notice error>{comments.error || queue.error}</Notice>}
    <Card><Text style={s.h2}>Novo comentário</Text>{!draft.draft || !queue.ready ? <Notice>Carregando rascunho e envios locais…</Notice> : draft.draft.submitted ? <><Notice>Seu comentário foi registrado com o protocolo original.</Notice><Button secondary title="Consultar envio" onPress={() => showReceipt(draft.draft!.id)} /><Button title="Escrever outro comentário" onPress={draft.startAnother} disabled={draft.busy || !!draft.saving} /></> : <>
      <Field label="Comentário" multiline maxLength={10000} value={draft.draft.values.text} onChangeText={text => draft.update({ text })} editable={!draft.busy} />
      <Text style={s.muted}>{draft.saving ? 'Salvando rascunho…' : `${draft.draft.values.text.length}/10000 caracteres`}</Text>
      <Button title="Salvar comentário" busy={draft.busy} disabled={!draft.draft.values.text.trim() || !!draft.saving} onPress={() => { void submit(); }} />
    </>}{!!draft.error && <Notice error>{draft.error}</Notice>}</Card>
    {!!pending.length && <Text style={s.h2}>Aguardando confirmação</Text>}
    {pending.map(({ operation, params }) => <Card key={operation.id}><Badge text={operation.status === 'failed' ? 'Envio requer atenção' : 'Salvo para envio'} alert /><Text selectable style={s.body}>{String(params.p_comentario || '')}</Text><Text style={s.muted}>{users.rows.find(user => user.id === operation.actor_id)?.nome || 'Operador responsável'} · {new Date(operation.created_at).toLocaleString('pt-BR')}</Text>{!!operation.last_error && <Notice error>{operation.last_error}</Notice>}<Button secondary title="Consultar envio" onPress={() => showReceipt(operation.id)} /></Card>)}
    <Text style={s.h2}>Histórico da célula</Text>{!rows.length && <Notice>Nenhum comentário sincronizado para esta célula no projeto.</Notice>}
    {rows.map(comment => <Card key={comment.id}><Text selectable style={s.body}>{comment.evento}</Text><Text style={s.muted}>{users.rows.find(user => user.id === comment.cadastrado_por_id)?.nome || 'Autor registrado'} · {new Date(comment.created_at).toLocaleString('pt-BR')}</Text></Card>)}
  </Screen>;
}

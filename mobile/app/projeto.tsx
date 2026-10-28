import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { service, type OutboxRow } from '../src/core';
import { assignedForms, pendingProjectPhotos, projectPhotos, requiredPhotoProgress } from '../src/domain/journey';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, Card, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, ProjectSummary, journeyLabel, useJourney } from '../src/ui/journey';

export default function Projeto() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>();
  const app = useApp(); const [queue, setQueue] = useState<OutboxRow[]>([]); const [queueError, setQueueError] = useState('');
  useEffect(() => { let live = true; service.listQueue().then(rows => { if (live) { setQueue(rows); setQueueError(''); } }).catch(e => { if (live) setQueueError(e.message); }); return () => { live = false; }; }, [app.revision]);
  const { context, error } = useJourney(celula, projeto); const forms = useRows('rm_forms'); const records = useRows('rm_registros_formulario'); const photos = useRows('rm_fotos');
  if (!context.ok) return <JourneyUnavailable context={context} error={error} />;
  const assigned = assignedForms(context.allocation, forms.rows); const gallery = projectPhotos(context, photos.rows);
  const revisions = records.rows.filter(r => r.projeto_id === projeto && r.celula_id === celula && r.status === 'direcionado' && assigned.some(form => form.id === r.form_id)).length;
  const pendingPhotos = pendingProjectPhotos(context, photos.rows, queue);
  const progress = requiredPhotoProgress(gallery.required, pendingPhotos.slots);
  const params = { celula: context.cell.id, projeto: context.project.id };
  return <Screen title={`OS ${context.project.numero || context.allocation.numero_projeto}`} eyebrow={journeyLabel(context)} backHref={{ pathname: '/projetos', params: { celula: context.cell.id } }} backLabel="Projetos da célula" subtitle="Escolha o que deseja fazer neste projeto.">
    <ProjectSummary context={context} />
    <Card><Text style={s.h2}>Formulários</Text><Text style={s.body}>Preencha os formulários definidos para este projeto e célula. Consulte envios e corrija as revisões solicitadas.</Text><Badge text={`${assigned.length} ${assigned.length === 1 ? 'formulário vinculado' : 'formulários vinculados'}`} />{!!revisions && <Badge text={`${revisions} ${revisions === 1 ? 'revisão pendente' : 'revisões pendentes'}`} alert />}<Button title="Acessar formulários" onPress={() => router.push({ pathname: '/formularios', params })} /></Card>
    <Card><Text style={s.h2}>Galeria</Text><Text style={s.body}>Registre as fotos obrigatórias e complementares desta célula e consulte as demais fotos do projeto.</Text>{!!queueError && <Notice error>{queueError}</Notice>}<Badge text={`${progress.registered} de ${gallery.required.length} fotos obrigatórias registradas`} /><Badge text={`${progress.confirmed} confirmadas · ${progress.pending} salvas para envio`} alert={!!progress.pending} />{!!progress.attention && <Notice error>{progress.attention} envio(s) de foto obrigatória requer(em) atenção. Consulte a galeria.</Notice>}<Badge text={`${gallery.complementary.length + pendingPhotos.complementary.length} complementares · ${gallery.others.length} de outras células`} /><Button title="Abrir galeria" onPress={() => router.push({ pathname: '/galeria', params })} /></Card>
  </Screen>;
}

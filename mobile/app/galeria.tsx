import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { service, type OutboxRow } from '../src/core';
import { galleryPhotos, photoTitle } from '../src/domain/gallery';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, Card, Notice, Screen, Select, s } from '../src/ui/components';
import { MediaImage } from '../src/ui/media';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';

export default function Galeria() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>(); const app = useApp();
  const { context, error } = useJourney(celula, projeto); const photos = useRows('rm_fotos', { field: 'projeto_id', value: projeto }); const cells = useRows('rm_celulas'); const users = useRows('rm_users');
  const [queue, setQueue] = useState<OutboxRow[]>([]); const [queueError, setQueueError] = useState('');
  const [category, setCategory] = useState(''); const [cellFilter, setCellFilter] = useState('');
  useEffect(() => { let live = true; service.listQueue().then(rows => { if (live) { setQueue(rows); setQueueError(''); } }).catch(e => { if (live) setQueueError(e.message); }); return () => { live = false; }; }, [app.revision]);
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Galeria indisponível" />;
  const gallery = galleryPhotos(context, photos.rows, queue);
  const visible = gallery.filter(photo => (!category || (category === 'recebimento' ? !!photo.tipo_recebimento : photo.categoria_foto === category)) && (!cellFilter || (cellFilter === 'recebimento' ? !photo.celula_id : photo.celula_id === cellFilter)));
  const cellIds = new Set(gallery.map(photo => photo.celula_id).filter(Boolean));
  return <Screen title="Galeria do projeto" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Fotos já registradas no projeto. Toque na imagem para ampliar.">
    {(photos.error || queueError) && <Notice error>{photos.error || queueError}</Notice>}
    <Select label="Tipo de foto" value={category} options={[{ value: '', label: 'Todas' }, { value: 'obrigat_ria', label: 'Obrigatórias' }, { value: 'complementar', label: 'Complementares' }, { value: 'recebimento', label: 'Recebimento' }]} onChange={([value]) => setCategory(value || '')} />
    <Select label="Célula" value={cellFilter} options={[{ value: '', label: 'Todo o projeto' }, ...cells.rows.filter(cell => cellIds.has(cell.id)).map(cell => ({ value: cell.id, label: cell.nome })), ...(gallery.some(photo => !photo.celula_id) ? [{ value: 'recebimento', label: 'Recebimento / projeto' }] : [])]} onChange={([value]) => setCellFilter(value || '')} />
    <Badge text={`${visible.length} ${visible.length === 1 ? 'foto registrada' : 'fotos registradas'}`} />
    {!visible.length && <Notice>Nenhuma foto registrada para esta seleção. Use “Registrar fotos” no projeto para adicionar uma evidência.</Notice>}
    {visible.map(photo => <Card key={photo.id}>
      <Badge text={photo.tipo_recebimento ? 'Recebimento' : photo.categoria_foto === 'obrigat_ria' ? 'Obrigatória' : 'Complementar'} />
      <Text style={s.h2}>{photoTitle(photo)}</Text><Text style={s.muted}>{cells.rows.find(cell => cell.id === photo.celula_id)?.nome || 'Recebimento / projeto'}</Text>
      <MediaImage uri={photo.foto_url} height={260} expand label={photoTitle(photo)} />
      {!!photo.legenda && <Text style={s.body}>{photo.legenda}</Text>}{!!photo.descricao && <Text style={s.muted}>{photo.descricao}</Text>}
      {!!photo.registered_by && <Text style={s.muted}>Registrada por {users.rows.find(user => user.id === photo.registered_by)?.nome || 'operador identificado'}</Text>}
      {photo.operation_id && <><Badge text={photo.upload_status === 'failed' ? 'Envio requer atenção' : 'Salva para envio'} alert /><Button secondary title="Consultar envio" onPress={() => router.push({ pathname: '/confirmacao', params: { id: photo.operation_id, tipo: 'Foto', projeto, celula } })} /></>}
    </Card>)}
  </Screen>;
}

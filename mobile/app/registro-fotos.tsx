import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { pendingProjectPhotos, projectPhotos } from '../src/domain/journey';
import { useRows } from '../src/ui/state';
import { useQueue } from '../src/ui/queue';
import { Badge, C, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';
import { PhotoEditor } from '../src/ui/photo-editor';

export default function RegistrarFotos() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>();
  const { context, error } = useJourney(celula, projeto); const photos = useRows('rm_fotos', { field: 'projeto_id', value: projeto });
  const [tab, setTab] = useState<'obrigat_ria' | 'complementar'>('obrigat_ria'); const { rows: queue, error: queueError } = useQueue();
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Registro de fotos indisponível" />;
  const gallery = projectPhotos(context, photos.rows); const pending = pendingProjectPhotos(context, photos.rows, queue);
  return <Screen title="Registrar fotos" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Escolha o tipo de foto que deseja registrar nesta célula.">
    <View style={[s.row, { gap: 8 }]}>{[{ id: 'obrigat_ria' as const, title: 'Obrigatórias' }, { id: 'complementar' as const, title: 'Complementares' }].map(item => <Pressable key={item.id} accessibilityRole="tab" accessibilityState={{ selected: tab === item.id }} onPress={() => setTab(item.id)} style={{ flex: 1, padding: 16, borderRadius: 12, backgroundColor: tab === item.id ? C.primary : C.white, borderWidth: 1, borderColor: C.line }}><Text style={{ textAlign: 'center', color: tab === item.id ? C.white : C.ink, fontWeight: '700', fontSize: 16 }}>{item.title}</Text></Pressable>)}</View>
    {(photos.error || queueError) && <Notice error>{photos.error || queueError}</Notice>}
    {!context.canEdit && <Notice error>{context.allocation.motivo_bloqueio || 'O registro de fotos está bloqueado pelo planejamento.'}</Notice>}
    <View style={{ display: tab === 'obrigat_ria' ? 'flex' : 'none', gap: 20 }}>
      <Badge text={`${gallery.required.length} itens obrigatórios definidos`} />
      {!gallery.required.length && <Notice>Nenhuma foto obrigatória definida para esta célula neste projeto.</Notice>}
      {gallery.required.map(photo => <PhotoEditor key={photo.id} slot={photo} context={context} queuedPhoto={pending.slots[photo.id]} />)}
    </View>
    <View style={{ display: tab === 'complementar' ? 'flex' : 'none', gap: 20 }}><Text style={s.body}>Registre as evidências adicionais necessárias ao projeto. Digite um título para identificar cada foto.</Text><PhotoEditor key={context.allocation.id} context={context} /></View>
  </Screen>;
}

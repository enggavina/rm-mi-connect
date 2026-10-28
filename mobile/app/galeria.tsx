import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import * as Crypto from 'expo-crypto';
import { service, type Row, type OutboxRow } from '../src/core';
import { canEditPhoto, pendingProjectPhotos, projectPhotos, type JourneyContext, type PendingPhoto } from '../src/domain/journey';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, Card, Field, Notice, Screen, s } from '../src/ui/components';
import { MediaImage, Photos } from '../src/ui/media';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';

type PhotoDraft = { id: string; uri: string; title: string; caption: string; submitted?: boolean };
const freshPhoto = (): PhotoDraft => ({ id: Crypto.randomUUID(), uri: '', title: '', caption: '' });

function PhotoEditor({ slot, context, queuedPhoto }: { slot?: Row; context: Extract<JourneyContext, { ok: true }>; queuedPhoto?: PendingPhoto }) {
  const app = useApp(); const [data, setData] = useState<PhotoDraft | null>(null); const [saved, setSaved] = useState('');
  const [open, setOpen] = useState(!slot?.foto_url); const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [saving, setSaving] = useState(0); const [mediaBusy, setMediaBusy] = useState(false); const [confirmed, setConfirmed] = useState(false);
  const current = useRef<PhotoDraft | null>(null); const pending = useRef(Promise.resolve()); const saveError = useRef(''); const inFlight = useRef(false);
  const key = `gallery-draft:${app.operator?.operador_id}:${context.allocation.id}:${slot?.id ?? 'new'}`;
  const editable = !queuedPhoto && (slot ? canEditPhoto(context, slot) : context.canEdit);
  useEffect(() => { let live = true; setData(null); current.current = null;
    Promise.all([service.getLocal<PhotoDraft>(key), service.getLocal<{ uri: string }>(`photo-slot:${slot?.id ?? context.allocation.id}`)]).then(async ([draft, legacy]) => {
      // Recover an enqueue that succeeded just before the local submitted marker could be saved.
      const operation = draft ? await service.operation(draft.id) : null;
      if (!live) return; const value = draft ? { ...draft, submitted: draft.submitted || !!operation } : freshPhoto(); current.current = value; setData(value); setConfirmed(operation?.status === 'completed'); if (legacy?.uri) setSaved(legacy.uri); if (value.uri && !value.submitted) setOpen(true);
    }).catch(e => { if (live) setError(e.message); }); return () => { live = false; };
  }, [key]);
  useEffect(() => { let live = true; if (data?.submitted) service.operation(data.id).then(op => { if (live) setConfirmed(op?.status === 'completed'); }).catch(e => { if (live) setError(e.message); }); return () => { live = false; }; }, [data?.id, data?.submitted, app.revision]);
  function persist(next: PhotoDraft) {
    current.current = next; setData(next); setSaving(n => n + 1);
    const write = service.saveLocal(key, next).then(() => { saveError.current = ''; }).catch(e => { saveError.current = e.message; setError(`Não foi possível salvar o rascunho: ${e.message}`); }).finally(() => setSaving(n => Math.max(0, n - 1)));
    pending.current = Promise.all([pending.current, write]).then(() => undefined);
  }
  function update(patch: Partial<PhotoDraft>) { if (current.current && editable && !busy && !current.current.submitted) persist({ ...current.current, ...patch }); }
  async function submit() {
    if (inFlight.current || !editable || !current.current || current.current.submitted || mediaBusy) return;
    inFlight.current = true; setBusy(true); setError('');
    try {
      await pending.current; if (saveError.current) throw new Error(saveError.current);
      const draft = current.current; if (!draft.uri) throw new Error('Adicione uma foto.'); if (!slot && !draft.title.trim()) throw new Error('Informe o título da foto complementar.');
      // Save the protocol before enqueue so reopening the page never creates a duplicate submission.
      await service.saveLocal(key, draft);
      await service.enqueue('rm_record_cell_photo_v1', { p_foto_id: slot?.id ?? null, p_projeto_id: context.project.id, p_celula_id: context.cell.id, p_celula_projeto_id: context.allocation.id, p_foto_url: draft.uri, p_legenda: draft.caption, p_titulo: slot?.titulo ?? draft.title.trim(), p_categoria_foto: slot?.categoria_foto ?? 'complementar' }, draft.id);
      const submitted = { ...draft, submitted: true }; current.current = submitted; setData(submitted); setSaved(draft.uri); setConfirmed(false); setOpen(false);
      await service.saveLocal(key, submitted);
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível registrar a foto.'); } finally { inFlight.current = false; setBusy(false); }
  }
  const preview = queuedPhoto?.uri || (data?.submitted ? (confirmed && slot?.foto_url) || data.uri : slot?.foto_url || saved);
  return <Card><View style={s.row}><Badge text={slot?.categoria_foto === 'obrigat_ria' ? 'Obrigatória' : 'Complementar'} /><Badge text={queuedPhoto ? queuedPhoto.status === 'failed' ? 'Envio requer atenção' : 'Salva para envio' : data?.submitted ? confirmed ? 'Envio confirmado' : 'Salva para envio' : preview ? 'Registrada' : slot ? 'Foto pendente' : 'Nova foto'} alert={!!queuedPhoto || (!!slot && !preview)} /></View>
    <Text style={s.h2}>{slot?.titulo || (data?.submitted && data.title) || 'Adicionar foto complementar'}</Text>{!!slot?.descricao && <Text style={s.muted}>{slot.descricao}</Text>}
    {!!preview && <MediaImage uri={preview} height={230} />}{!!(queuedPhoto?.caption || slot?.legenda) && <Text style={s.muted}>{queuedPhoto?.caption || slot?.legenda}</Text>}
    {queuedPhoto && <><Notice>{queuedPhoto.operatorId === app.operator?.operador_id ? 'Sua foto está salva e aguarda confirmação do envio.' : 'Uma foto foi salva por outro operador. O envio mantém a autoria original.'} Este item poderá receber outra foto após a confirmação. Seus rascunhos permanecem preservados.</Notice>{!!queuedPhoto.error && <Notice error>{queuedPhoto.error}</Notice>}<Button secondary title="Consultar envio da foto" onPress={() => router.push({ pathname: '/confirmacao', params: { id: queuedPhoto.operationId, tipo: 'Foto', projeto: context.project.id, celula: context.cell.id } })} /></>}
    {!queuedPhoto && data?.submitted && <><Notice>{confirmed ? 'O envio desta foto foi confirmado.' : 'A foto está salva no dispositivo. Acompanhe a confirmação do envio.'}</Notice><Button secondary title="Consultar envio da foto" onPress={() => router.push({ pathname: '/confirmacao', params: { id: data.id, tipo: 'Foto', projeto: context.project.id, celula: context.cell.id } })} /></>}
    {!data && editable && <Notice>Carregando rascunho da foto…</Notice>}
    {editable && data && (data.submitted || !open) && <Button secondary title={slot ? 'Registrar outra foto neste item' : 'Adicionar outra foto complementar'} disabled={busy || !!saving} onPress={() => { if (data.submitted) persist(freshPhoto()); setOpen(true); setError(''); }} />}
    {editable && data && open && !data.submitted && <>
      {!slot && <Field label="Título da foto *" value={data.title} onChangeText={title => update({ title })} editable={!busy} />}
      <Photos single values={data.uri ? [data.uri] : []} onChange={uris => update({ uri: uris.at(-1) ?? '' })} disabled={busy} onBusyChange={setMediaBusy} />
      <Field label="Descrição / legenda" value={data.caption} onChangeText={caption => update({ caption })} multiline editable={!busy} />
      {!!saving && <Text style={s.muted}>Salvando rascunho…</Text>}{mediaBusy && <Notice>Salvando a foto no dispositivo…</Notice>}
      <Button title="Salvar foto" busy={busy} disabled={!data.uri || !!saving || mediaBusy} onPress={() => { void submit(); }} />
    </>}{!!error && <Notice error>{error}</Notice>}
  </Card>;
}

export default function Galeria() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>(); const app = useApp();
  const { context, error } = useJourney(celula, projeto); const photos = useRows('rm_fotos'); const cells = useRows('rm_celulas');
  const [othersOpen, setOthersOpen] = useState(false); const [queue, setQueue] = useState<OutboxRow[]>([]); const [queueError, setQueueError] = useState('');
  useEffect(() => { let live = true; service.listQueue().then(rows => { if (live) { setQueue(rows); setQueueError(''); } }).catch(e => { if (live) setQueueError(e.message); }); return () => { live = false; }; }, [app.revision]);
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Galeria indisponível" />;
  const gallery = projectPhotos(context, photos.rows);
  const pendingPhotos = pendingProjectPhotos(context, photos.rows, queue);
  return <Screen title="Galeria do projeto" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Registre as evidências desta célula e consulte as demais fotos do projeto.">
    {(photos.error || queueError) && <Notice error>{photos.error || queueError}</Notice>}
    {!context.canEdit && <Notice error>{context.allocation.motivo_bloqueio || 'Execução bloqueada pelo planejamento. As fotos estão disponíveis para consulta.'}</Notice>}
    <Text style={s.h2}>Obrigatórias · {context.cell.nome}</Text>{!gallery.required.length && <Notice>Nenhuma foto obrigatória definida para esta célula no projeto.</Notice>}
    {gallery.required.map(photo => <PhotoEditor key={photo.id} slot={photo} context={context} queuedPhoto={pendingPhotos.slots[photo.id]} />)}
    <Text style={s.h2}>Complementares · {context.cell.nome}</Text>
    {!gallery.complementary.length && !pendingPhotos.complementary.length && <Notice>Ainda não há fotos complementares nesta célula.</Notice>}
    {gallery.complementary.map(photo => <PhotoEditor key={photo.id} slot={photo} context={context} queuedPhoto={pendingPhotos.slots[photo.id]} />)}
    {pendingPhotos.complementary.map(photo => <Card key={photo.operationId}><Badge text={photo.status === 'failed' ? 'Envio requer atenção' : 'Aguardando confirmação'} alert /><Text style={s.h2}>{photo.title || 'Foto complementar'}</Text><MediaImage uri={photo.uri} /><Text style={s.muted}>{photo.caption}</Text><Button secondary title="Consultar envio" onPress={() => router.push({ pathname: '/confirmacao', params: { id: photo.operationId, tipo: 'Foto', projeto: context.project.id, celula: context.cell.id } })} /></Card>)}
    {context.canEdit && <PhotoEditor key={context.allocation.id} context={context} />}
    <Card><Text style={s.h2}>Outras fotos do projeto</Text><Text style={s.body}>Fotos de outras células ficam disponíveis somente para consulta.</Text><Badge text={`${gallery.others.length} fotos`} /><Button secondary title={othersOpen ? 'Recolher fotos' : 'Consultar outras fotos'} onPress={() => setOthersOpen(!othersOpen)} /></Card>
    {othersOpen && !gallery.others.length && <Notice>Nenhuma foto de outras células disponível neste projeto.</Notice>}
    {othersOpen && gallery.others.map(photo => <Card key={photo.id}><Badge text={cells.rows.find(cell => cell.id === photo.celula_id)?.nome || 'Foto do projeto'} /><Text style={s.h2}>{photo.titulo || 'Foto do projeto'}</Text>{photo.foto_url ? <MediaImage uri={photo.foto_url} height={230} /> : <Notice>Esta foto ainda não foi registrada.</Notice>}{!!photo.descricao && <Text style={s.body}>{photo.descricao}</Text>}{!!photo.legenda && <Text style={s.muted}>{photo.legenda}</Text>}</Card>)}
  </Screen>;
}

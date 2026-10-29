import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { router } from 'expo-router';
import * as Crypto from 'expo-crypto';
import { service, type Row } from '../core';
import { canEditPhoto, type JourneyContext, type PendingPhoto } from '../domain/journey';
import { useApp } from './state';
import { Badge, Button, Card, Field, Notice, s } from './components';
import { MediaImage, Photos } from './media';

type PhotoDraft = { id: string; uri: string; title: string; caption: string; submitted?: boolean };
const freshPhoto = (): PhotoDraft => ({ id: Crypto.randomUUID(), uri: '', title: '', caption: '' });

export function PhotoEditor({ slot, context, queuedPhoto }: { slot?: Row; context: Extract<JourneyContext, { ok: true }>; queuedPhoto?: PendingPhoto }) {
  const app = useApp(); const [data, setData] = useState<PhotoDraft | null>(null); const [saved, setSaved] = useState('');
  const [open, setOpen] = useState(!slot?.foto_url); const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [saving, setSaving] = useState(0); const [mediaBusy, setMediaBusy] = useState(false); const [confirmed, setConfirmed] = useState(false);
  const current = useRef<PhotoDraft | null>(null); const pending = useRef(Promise.resolve()); const saveError = useRef(''); const inFlight = useRef(false);
  const key = `gallery-draft:${app.operator?.operador_id}:${context.allocation.id}:${slot?.id ?? 'new'}`;
  const actorId = app.operator?.operador_id; const activeKey = useRef(key); activeKey.current = key;
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
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
      if (!mounted.current || activeKey.current !== key || service.getSnapshot().operator?.operador_id !== actorId) throw new Error('O operador ou projeto mudou. O rascunho foi preservado; volte com o autor para enviar.');
      await service.enqueue('rm_record_cell_photo_v1', { p_foto_id: slot?.id ?? null, p_projeto_id: context.project.id, p_celula_id: context.cell.id, p_celula_projeto_id: context.allocation.id, p_foto_url: draft.uri, p_legenda: draft.caption, p_titulo: slot?.titulo ?? draft.title.trim(), p_cadastro_foto_id: null, p_categoria_foto: slot?.categoria_foto ?? 'complementar' }, draft.id);
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
      {!slot && <Field label="Título da foto *" placeholder="Digite o título da foto" value={data.title} onChangeText={title => update({ title })} editable={!busy} />}
      <Photos single values={data.uri ? [data.uri] : []} onChange={uris => update({ uri: uris.at(-1) ?? '' })} disabled={busy} onBusyChange={setMediaBusy} />
      <Field label="Comentário da foto (opcional)" value={data.caption} onChangeText={caption => update({ caption })} multiline editable={!busy} />
      {!!saving && <Text style={s.muted}>Salvando rascunho…</Text>}{mediaBusy && <Notice>Salvando a foto no dispositivo…</Notice>}
      <Button title="Salvar foto" busy={busy} disabled={!data.uri || !!saving || mediaBusy} onPress={() => { void submit(); }} />
    </>}{!!error && <Notice error>{error}</Notice>}
  </Card>;
}

import { useEffect, useRef, useState } from 'react';
import { Alert, Platform, Text, View } from 'react-native';
import { router } from 'expo-router';
import * as Crypto from 'expo-crypto';
import * as ImagePicker from 'expo-image-picker';
import DateTimePicker from '@react-native-community/datetimepicker';
import { service } from '../src/core';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, C, Card, Field, Notice, Screen, Select, s } from '../src/ui/components';
import { MediaImage } from '../src/ui/media';
import { DocumentField } from '../src/ui/documents';
import { newReceiving, receivingPayload, receivingPhotoTitle, restoreReceiving, setArrivalPart,
  validateReceiving, RECEIVING_PHOTO_TITLES, RECEIVING_STEPS, type Receiving, type ReceivingPhoto } from '../src/domain/receiving';

function ArrivalField({ value, onChange, disabled }: { value: string; onChange: (value: string) => void; disabled: boolean }) {
  const [mode, setMode] = useState<'date' | 'time' | null>(null);
  const valid = Number.isFinite(Date.parse(value)), date = valid ? new Date(value) : new Date();
  return <View style={{ gap: 12 }}>
    <Text style={{ color: C.ink, fontSize: 14, fontWeight: '600' }}>Chegada do equipamento *</Text>
    <View style={s.row}>
      <View style={{ flex: 1, minWidth: 150 }}><Text style={s.muted}>Data</Text><Button secondary disabled={disabled} title={valid ? date.toLocaleDateString('pt-BR') : 'Selecionar data'} onPress={() => setMode('date')} /></View>
      <View style={{ flex: 1, minWidth: 120 }}><Text style={s.muted}>Hora</Text><Button secondary disabled={disabled} title={valid ? date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : 'Selecionar hora'} onPress={() => setMode('time')} /></View>
    </View>
    {mode && <><DateTimePicker value={date} mode={mode} is24Hour locale="pt-BR" display={Platform.OS === 'ios' ? 'spinner' : 'default'} onChange={(event, selected) => {
      if (Platform.OS !== 'ios') setMode(null);
      if (event.type !== 'dismissed' && selected) onChange(setArrivalPart(value, selected, mode));
    }} />{Platform.OS === 'ios' && <Button secondary title="Concluir ajuste" onPress={() => setMode(null)} />}</>}
  </View>;
}

export default function Recebimento() {
  const app = useApp(), clients = useRows('rm_clientes');
  const key = `recebimento:${app.operator?.operador_id}`;
  const [data, setData] = useState<Receiving | null>(null), current = useRef<Receiving | null>(null);
  const owner = useRef(key), pending = useRef(Promise.resolve()), saveError = useRef(''), submitting = useRef(false);
  const [error, setError] = useState(''), [busy, setBusy] = useState(false), [saving, setSaving] = useState(0);
  const [mediaBusy, setMediaBusy] = useState(false), [loading, setLoading] = useState(true), [reload, setReload] = useState(0);
  const fresh = () => newReceiving(Crypto.randomUUID(), new Date().toISOString());

  useEffect(() => {
    let live = true; owner.current = key; current.current = null; setData(null); setError(''); setLoading(true);
    saveError.current = ''; pending.current = Promise.resolve(); setSaving(0);
    if (!app.operator?.operador_id) { setLoading(false); return; }
    void (async () => {
      const saved = await service.getLocal<unknown>(key);
      const value = restoreReceiving(saved, Crypto.randomUUID(), new Date().toISOString());
      // Recover a successful enqueue even if the subsequent draft save was interrupted.
      if (await service.operation(value.id)) value.submitted = true;
      if (live) { current.current = value; setData(value); }
    })().catch(e => { if (live) setError(e instanceof Error ? e.message : 'Não foi possível abrir o rascunho.'); })
      .finally(() => { if (live) setLoading(false); });
    return () => { live = false; };
  }, [key, app.operator?.operador_id, reload]);

  function update(patch: Partial<Receiving>) {
    if (!current.current || submitting.current || current.current.submitted) return;
    const next = { ...current.current, ...patch }, saveKey = key;
    current.current = next; setData(next); setSaving(count => count + 1);
    pending.current = pending.current.then(() => service.saveLocal(saveKey, next)).then(() => {
      if (owner.current === saveKey) {
        saveError.current = '';
        setError(previous => previous.startsWith('Falha ao salvar o rascunho:') ? '' : previous);
      }
    }).catch(e => {
      if (owner.current !== saveKey) return;
      saveError.current = e instanceof Error ? e.message : 'Falha de armazenamento.';
      setError(`Falha ao salvar o rascunho: ${saveError.current}`);
    }).finally(() => { if (owner.current === saveKey) setSaving(count => Math.max(0, count - 1)); });
  }
  function patchPhoto(id: string, patch: Partial<ReceivingPhoto>) {
    if (current.current) update({ fotos: current.current.fotos.map(photo => photo.id === id ? { ...photo, ...patch } : photo) });
  }
  async function capturePhoto(camera: boolean, type: string, replaceId?: string) {
    if (submitting.current || mediaBusy) return;
    const captureKey = key; setMediaBusy(true); setError('');
    try {
      if (camera && !(await ImagePicker.requestCameraPermissionsAsync()).granted) throw new Error('Autorize o acesso à câmera nas configurações do dispositivo.');
      const result = camera
        ? await ImagePicker.launchCameraAsync({ mediaTypes: ['images'], quality: 1 })
        : await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: !replaceId, quality: 1 });
      if (!result.canceled) for (const asset of result.assets) {
        const uri = await service.addMedia(asset.uri, 'rm-fotos');
        if (owner.current !== captureKey || !current.current) break;
        if (replaceId) patchPhoto(replaceId, { uri });
        else update({ fotos: [...current.current.fotos, { id: Crypto.randomUUID(), uri, tipo: type, comentario: '' }] });
      }
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível salvar a foto.'); }
    finally { setMediaBusy(false); }
  }
  function choosePhoto(type: string, replaceId?: string) {
    Alert.alert(replaceId ? 'Substituir foto' : 'Adicionar foto', receivingPhotoTitle(type) || 'Foto do rascunho anterior', [
      { text: 'Cancelar', style: 'cancel' },
      { text: 'Câmera', onPress: () => { void capturePhoto(true, type, replaceId); } },
      { text: 'Galeria', onPress: () => { void capturePhoto(false, type, replaceId); } },
    ]);
  }
  function next() {
    if (!current.current) return;
    const problem = validateReceiving(current.current, current.current.step >= 1);
    if (problem) { setError(problem); return; }
    setError(''); update({ step: Math.min(2, current.current.step + 1) });
  }
  async function submit() {
    if (!current.current || submitting.current || mediaBusy) return;
    const submitOperator = app.operator?.operador_id, submitKey = key;
    submitting.current = true; setBusy(true); setError('');
    try {
      await pending.current;
      if (!submitOperator || service.getSnapshot().operator?.operador_id !== submitOperator || owner.current !== submitKey) {
        throw new Error('O operador mudou. Volte ao rascunho com o responsável antes de enviar.');
      }
      if (saveError.current) throw new Error(saveError.current);
      const draft = current.current;
      const id = await service.enqueue('rm_submit_recebimento_v1', receivingPayload(draft), draft.id);
      const sent = { ...draft, submitted: true }; current.current = sent; setData(sent);
      // The durable queue is authoritative; never unlock an already enqueued draft.
      await service.saveLocal(key, sent).catch(() => undefined);
      router.replace({ pathname: '/confirmacao', params: { id, tipo: 'Recebimento' } });
    } catch (e) { setError(e instanceof Error ? e.message : 'Falha ao salvar o recebimento.'); }
    finally { submitting.current = false; setBusy(false); }
  }
  async function startAnother() {
    if (submitting.current) return; submitting.current = true; setBusy(true); setError('');
    try { const value = fresh(); await pending.current; await service.saveLocal(key, value); current.current = value; setData(value); saveError.current = ''; }
    catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível iniciar outro recebimento.'); }
    finally { submitting.current = false; setBusy(false); }
  }
  const disabled = busy || mediaBusy;
  function photoContent(photo: ReceivingPhoto, unassigned = false) {
    return <View key={photo.id} style={{ gap: 12, paddingTop: 8 }}>
      {unassigned && <Select label="Título cadastrado *" value={photo.tipo} options={[...RECEIVING_PHOTO_TITLES]} disabled={disabled} onChange={values => patchPhoto(photo.id, { tipo: values[0] })} />}
      <MediaImage uri={photo.uri} height={230} />
      <Field label="Comentário da foto (opcional)" value={photo.comentario} multiline editable={!disabled} onChangeText={comentario => patchPhoto(photo.id, { comentario })} />
      <View style={s.row}>
        <Button secondary title="Substituir foto" disabled={disabled} onPress={() => choosePhoto(photo.tipo, photo.id)} />
        <Button secondary title="Remover foto" disabled={disabled} onPress={() => { if (current.current) update({ fotos: current.current.fotos.filter(item => item.id !== photo.id) }); }} />
      </View>
    </View>;
  }

  return <Screen title="Recebimento de equipamento" subtitle="Registre a chegada, a nota fiscal e as fotos do equipamento." backHref="/celula" backLabel="Voltar às células">
    {!!error && <Notice error>{error}</Notice>}
    {!data ? <Card><Notice>{loading ? 'Carregando rascunho…' : 'O rascunho não foi aberto. Seus dados não foram substituídos.'}</Notice>{!loading && <Button secondary title="Tentar novamente" onPress={() => setReload(value => value + 1)} />}</Card>
      : data.submitted ? <Card><Notice>Este recebimento já está na fila. O protocolo foi preservado para evitar duplicações.</Notice><Button title="Consultar envio" onPress={() => router.push({ pathname: '/confirmacao', params: { id: data.id, tipo: 'Recebimento' } })} /><Button secondary title="Iniciar outro recebimento" busy={busy} onPress={() => { void startAnother(); }} /></Card>
        : <>
          <View style={{ flexDirection: 'row', gap: 10 }}>{RECEIVING_STEPS.map((title, index) => <View key={title} style={{ flex: 1, gap: 8 }}><View style={{ height: 4, borderRadius: 3, backgroundColor: index <= data.step ? C.brand : C.line }} /><Text style={{ color: index === data.step ? C.primary : C.muted, fontSize: 12, lineHeight: 18, fontWeight: '700' }}>{index + 1}. {title}</Text></View>)}</View>
          <View style={[s.row, { justifyContent: 'space-between' }]}><Text style={s.h2}>{RECEIVING_STEPS[data.step]}</Text><Badge text={saving ? 'Salvando…' : 'Rascunho local'} /></View>
          {data.step === 0 && <Card>
            {!!clients.error && <Notice error>{clients.error}</Notice>}
            <Select label="Cliente *" value={data.cliente} options={clients.rows.map(client => ({ value: client.id, label: client.nome }))} onChange={values => update({ cliente: values[0] })} disabled={disabled} />
            <ArrivalField value={data.chegada} onChange={chegada => update({ chegada })} disabled={disabled} />
            <Field label="Número da nota fiscal" value={data.notaFiscal} editable={!disabled} onChangeText={notaFiscal => update({ notaFiscal })} />
            <DocumentField label="Arquivo da nota fiscal" value={data.arquivoNotaFiscal} onChange={arquivoNotaFiscal => update({ arquivoNotaFiscal })} disabled={disabled} onBusyChange={setMediaBusy} />
            <Field label="Descrição do equipamento" value={data.descricaoEquipamento} multiline editable={!disabled} onChangeText={descricaoEquipamento => update({ descricaoEquipamento })} />
            <Select label="Placa do motor" value={data.placaMotor} options={[{ value: '', label: 'Não informado' }, { value: 'c___placa', label: 'Com placa' }, { value: 's___placa', label: 'Sem placa' }]} disabled={disabled} onChange={values => update({ placaMotor: values[0] })} />
            <Field label="Eventualidades na chegada" value={data.eventualidades} multiline editable={!disabled} onChangeText={eventualidades => update({ eventualidades })} />
            {!!data.legacySnapshot && <Notice>As informações preenchidas no rascunho anterior foram preservadas. Confira os dados de chegada e os títulos das fotos antes de enviar.</Notice>}
          </Card>}
          {data.step === 1 && <>
            <Notice>Use os títulos cadastrados para identificar as fotos. O comentário é opcional em cada imagem. Registre pelo menos uma foto.</Notice>
            {data.fotos.filter(photo => !receivingPhotoTitle(photo.tipo)).map(photo => <Card key={photo.id}><Text style={s.h2}>Foto preservada do rascunho anterior</Text>{photoContent(photo, true)}</Card>)}
            {RECEIVING_PHOTO_TITLES.map(option => {
              const photos = data.fotos.filter(photo => photo.tipo === option.value);
              return <Card key={option.value}><View style={[s.row, { justifyContent: 'space-between' }]}><Text style={[s.h2, { flex: 1 }]}>{option.label}</Text><Badge text={`${photos.length} foto${photos.length === 1 ? '' : 's'}`} /></View>
                {photos.map(photo => photoContent(photo))}
                <Button secondary disabled={disabled} title={photos.length ? 'Adicionar outra foto' : 'Adicionar foto'} onPress={() => choosePhoto(option.value)} />
              </Card>;
            })}
          </>}
          {data.step === 2 && <Card>
            <Text style={s.h2}>{clients.rows.find(client => client.id === data.cliente)?.nome || 'Cliente selecionado'}</Text>
            <Text style={s.body}>Chegada: {Number.isFinite(Date.parse(data.chegada)) ? new Date(data.chegada).toLocaleString('pt-BR') : 'Data inválida'}</Text>
            <Text style={s.body}>Nota fiscal: {data.notaFiscal || 'Não informada'}</Text>
            <Text style={s.body}>Arquivo da NF: {data.arquivoNotaFiscal ? 'Anexado' : 'Não anexado'}</Text>
            {!!data.descricaoEquipamento && <Text style={s.body}>{data.descricaoEquipamento}</Text>}
            <Text style={s.body}>Placa do motor: {data.placaMotor === 'c___placa' ? 'Com placa' : data.placaMotor === 's___placa' ? 'Sem placa' : 'Não informado'}</Text>
            {!!data.eventualidades && <Text style={s.body}>Eventualidades: {data.eventualidades}</Text>}
            <Text style={s.h2}>{data.fotos.filter(photo => photo.uri).length} fotos anexadas</Text>
            {data.fotos.filter(photo => photo.uri).map((photo, index) => <View key={photo.id} style={{ gap: 3 }}><Text style={s.body}>{index + 1}. {receivingPhotoTitle(photo.tipo) || 'Título a selecionar'}</Text>{!!photo.comentario.trim() && <Text style={s.muted}>{photo.comentario}</Text>}</View>)}
            <Notice>Ao concluir, o recebimento ficará salvo na fila. A nota fiscal e as fotos serão enviadas antes do pedido de abertura, quando houver conexão.</Notice>
          </Card>}
          <View style={[s.row, { justifyContent: 'space-between' }]}>
            <Button secondary title="Voltar" disabled={data.step === 0 || disabled} onPress={() => { setError(''); update({ step: data.step - 1 }); }} />
            {data.step < 2 ? <Button title={data.step === 0 ? 'Continuar para fotos' : 'Conferir recebimento'} disabled={disabled} onPress={next} />
              : <Button title="Solicitar abertura" busy={busy} disabled={!!saving || mediaBusy} onPress={() => { void submit(); }} />}
          </View>
        </>}
  </Screen>;
}

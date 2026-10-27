import React, { useEffect, useRef, useState } from 'react';
import { Alert, Image, Modal, PanResponder, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as ImagePicker from 'expo-image-picker';
import Svg, { Path } from 'react-native-svg';
import ViewShot from 'react-native-view-shot';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { service } from '../core';
import { Button, C, Notice, s } from './components';

export function MediaImage({ uri, height = 180 }: { uri: string; height?: number }) {
  const [url, setUrl] = useState(uri); const [failed, setFailed] = useState(false);
  useEffect(() => { let live = true; setFailed(false); service.getMediaUrl(uri).then(u => { if (live) setUrl(u); }).catch(() => { if (live) setFailed(true); }); return () => { live = false; }; }, [uri]);
  return failed ? <Notice>Prévia indisponível offline. O vínculo da imagem está preservado.</Notice> : <Image accessibilityLabel="Evidência da inspeção" source={{ uri: url }} style={{ width: '100%', height, borderRadius: 10, backgroundColor: '#E7EDF3' }} resizeMode="contain" onError={() => setFailed(true)} />;
}
export function Photos({ values, onChange, disabled, beforeAfter = false, onBusyChange }: { values: string[]; onChange: (uris: string[]) => void; disabled?: boolean; beforeAfter?: boolean; onBusyChange?: (busy: boolean) => void }) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  async function pick(camera: boolean, index?: number) {
    setBusy(true); onBusyChange?.(true); setError('');
    try {
      if (camera && !(await ImagePicker.requestCameraPermissionsAsync()).granted) throw new Error('Autorize o acesso à câmera nas configurações do dispositivo.');
      const result = camera ? await ImagePicker.launchCameraAsync({ mediaTypes: ['images'], quality: 1 }) : await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: index === undefined, quality: 1 });
      if (!result.canceled) {
        const saved: string[] = []; for (const asset of result.assets) saved.push(await service.addMedia(asset.uri, 'rm-fotos'));
        if (index !== undefined) { const next = [values[0] || '',values[1] || '']; next[index] = saved[0]; onChange(next); } else onChange([...values, ...saved]);
      }
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível salvar a foto.'); } finally { setBusy(false); onBusyChange?.(false); }
  }
  function choose(index?: number) { Alert.alert('Adicionar foto', 'Selecione a origem da imagem.', [{ text: 'Cancelar', style: 'cancel' }, { text: 'Câmera', onPress: () => { void pick(true, index); } }, { text: 'Galeria', onPress: () => { void pick(false, index); } }]); }
  const slots = beforeAfter ? [values[0] || '', values[1] || ''] : values;
  return <View style={{ gap: 12 }}>{slots.map((uri, i) => <View key={`${i}-${uri}`} style={{ gap: 8 }}>
    {beforeAfter && <Text style={s.h2}>{i === 0 ? 'Antes' : 'Depois'}</Text>}{!!uri && <MediaImage uri={uri} />}
    {!disabled && <View style={s.row}>{beforeAfter && <Button secondary busy={busy} title={uri ? 'Substituir foto' : 'Adicionar foto'} onPress={() => choose(i)} />}{!!uri && <Button secondary disabled={busy} title="Remover foto" onPress={() => { const next=beforeAfter ? values.map((v,j) => j === i ? '' : v) : values.filter((_,j) => j !== i); onChange(next.some(Boolean) ? next : []); }} />}</View>}
  </View>)}{!beforeAfter && !disabled && <Button secondary busy={busy} title="Adicionar foto" onPress={() => choose()} />}{!!error && <Notice error>{error}</Notice>}</View>;
}
export function Signature({ value, onChange, disabled }: { value?: string | null; onChange: (uri: string | null) => void; disabled?: boolean }) {
  const [open, setOpen] = useState(false); const [paths, setPaths] = useState<string[]>([]); const pathsRef = useRef<string[]>([]); const shot = useRef<ViewShot>(null); const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  const responder = useRef(PanResponder.create({ onStartShouldSetPanResponder: () => true, onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: e => { const { locationX: x, locationY: y } = e.nativeEvent; pathsRef.current = [...pathsRef.current, `M${x},${y} l0.1,0.1`]; setPaths([...pathsRef.current]); },
    onPanResponderMove: e => { const { locationX: x, locationY: y } = e.nativeEvent; const p = pathsRef.current; if (p.length) { p[p.length - 1] += ` L${x},${y}`; setPaths([...p]); } }, onPanResponderTerminationRequest: () => false,
  })).current;
  async function save() { setBusy(true); setError(''); try { const uri = await shot.current?.capture?.(); if (!uri) throw new Error('Assinatura vazia.'); onChange(await service.addMedia(uri, 'rm-assinaturas')); setOpen(false); } catch(e) { setError(e instanceof Error ? e.message : 'Falha ao salvar.'); } finally { setBusy(false); } }
  return <View style={{ gap: 10 }}>{value && <MediaImage uri={value} height={150} />}{!disabled && <Button secondary title={value ? 'Refazer assinatura' : 'Assinar'} onPress={() => { pathsRef.current = []; setPaths([]); setError(''); setOpen(true); }} />}
    <Modal visible={open} animationType="slide" onRequestClose={() => setOpen(false)}><SafeAreaView style={{ flex: 1, backgroundColor: C.bg, padding: 20, gap: 18 }}><Text style={s.h2}>Assine no espaço abaixo</Text><ViewShot ref={shot} options={{ format: 'png', quality: 1, result: 'tmpfile' }} style={{ flex: 1, backgroundColor: 'white', borderWidth: 1, borderColor: C.line }}><View {...responder.panHandlers} style={{ flex: 1 }}><Svg width="100%" height="100%">{paths.map((d, i) => <Path key={i} d={d} stroke={C.ink} strokeWidth={3} fill="none" strokeLinecap="round" strokeLinejoin="round" />)}</Svg></View></ViewShot>{!!error && <Notice error>{error}</Notice>}<View style={s.row}><Button secondary title="Limpar" onPress={() => { pathsRef.current = []; setPaths([]); }} /><Button secondary title="Cancelar" onPress={() => setOpen(false)} /><Button title="Salvar assinatura" disabled={!paths.length} busy={busy} onPress={() => { void save(); }} /></View></SafeAreaView></Modal>
  </View>;
}
export function QrScanner({ onRead }: { onRead: (data: string) => void }) {
  const [permission, requestPermission] = useCameraPermissions(); const [open, setOpen] = useState(false); const scanned = useRef(false); const [error, setError] = useState('');
  async function start() { if (!permission?.granted && !(await requestPermission()).granted) { setError('Autorize a câmera para ler o QR Code.'); return; } scanned.current = false; setOpen(true); }
  return <View style={{ gap: 8 }}><Button secondary title="Ler QR Code" onPress={() => { void start(); }} />{!!error && <Notice error>{error}</Notice>}<Modal visible={open} onRequestClose={() => setOpen(false)}><SafeAreaView style={{ flex: 1, backgroundColor: C.navy, padding: 16, gap: 16 }}>{open && <CameraView style={{ flex: 1 }} barcodeScannerSettings={{ barcodeTypes: ['qr'] }} onBarcodeScanned={({ data }) => { if (scanned.current) return; scanned.current = true; setOpen(false); onRead(data); }} />}<Button title="Cancelar leitura" onPress={() => setOpen(false)} /></SafeAreaView></Modal></View>;
}

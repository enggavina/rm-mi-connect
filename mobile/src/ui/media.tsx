import React, { useEffect, useRef, useState } from 'react';
import { Alert, Image, Modal, PanResponder, Pressable, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as ImagePicker from 'expo-image-picker';
import Svg, { Path } from 'react-native-svg';
import ViewShot from 'react-native-view-shot';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { service } from '../core';
import { Button, C, Notice, s } from './components';
import { useRouteFocused } from './state';

export function MediaImage({ uri, height = 180, expand = false, label = 'Evidência da inspeção' }: { uri: string; height?: number; expand?: boolean; label?: string }) {
  const focused = useRouteFocused();
  const [resolved, setResolved] = useState<{ source: string; url: string } | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    let live = true;
    setOpen(false); setFailed(null); setResolved(null);
    if (focused) service.getMediaUrl(uri).then(url => {
      if (!live) return;
      if (url) setResolved({ source: uri, url }); else setFailed(uri);
    }).catch(() => { if (live) setFailed(uri); });
    return () => { live = false; };
  }, [uri, focused]);
  const url = focused && resolved?.source === uri ? resolved.url : null;
  if (focused && failed === uri) return <Notice>Prévia indisponível offline. O vínculo da imagem está preservado.</Notice>;
  if (!url) return <View style={{ width: '100%', height, borderRadius: 10, backgroundColor: C.soft, alignItems: 'center', justifyContent: 'center' }}>{focused && <Text style={s.muted}>Carregando foto…</Text>}</View>;
  return <>
    <Pressable disabled={!expand} accessibilityRole={expand ? 'button' : 'image'} accessibilityLabel={expand ? `Ampliar ${label}` : label} onPress={() => setOpen(true)}><Image source={{ uri: url }} style={{ width: '100%', height, borderRadius: 10, backgroundColor: C.soft }} resizeMode="contain" resizeMethod="resize" onError={() => setFailed(uri)} /></Pressable>
    {open && expand && <Modal visible animationType="fade" onRequestClose={() => setOpen(false)}><SafeAreaView style={{ flex: 1, padding: 16, backgroundColor: C.bg, gap: 16 }}><Text style={s.h2}>{label}</Text><Image source={{ uri: url }} style={{ flex: 1, width: '100%' }} resizeMode="contain" resizeMethod="resize" /><Button title="Fechar foto" onPress={() => setOpen(false)} /></SafeAreaView></Modal>}
  </>;
}
export function Photos({ values, onChange, disabled, beforeAfter = false, single = false, onBusyChange }: { values: string[]; onChange: (uris: string[]) => void; disabled?: boolean; beforeAfter?: boolean; single?: boolean; onBusyChange?: (busy: boolean) => void }) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  async function pick(camera: boolean, index?: number) {
    setBusy(true); onBusyChange?.(true); setError('');
    try {
      if (camera && !(await ImagePicker.requestCameraPermissionsAsync()).granted) throw new Error('Autorize o acesso à câmera nas configurações do dispositivo.');
      const result = camera ? await ImagePicker.launchCameraAsync({ mediaTypes: ['images'], quality: 1 }) : await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: !single && index === undefined, quality: 1 });
      if (!result.canceled) {
        const saved: string[] = []; for (const asset of result.assets) saved.push(await service.addMedia(asset.uri, 'rm-fotos'));
        if (index !== undefined) { const next = [values[0] || '',values[1] || '']; next[index] = saved[0]; onChange(next); } else onChange(single ? saved.slice(-1) : [...values, ...saved]);
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
export function QrScanner({ onRead, disabled = false }: { onRead: (data: string) => void; disabled?: boolean }) {
  const [permission, requestPermission] = useCameraPermissions(); const [open, setOpen] = useState(false); const scanned = useRef(false); const [error, setError] = useState('');
  const live = useRef(true); const attempt = useRef(0); const unavailable = useRef(disabled); unavailable.current = disabled;
  useEffect(() => { live.current = true; return () => { live.current = false; attempt.current++; }; }, []);
  function close() { attempt.current++; scanned.current = true; setOpen(false); }
  useEffect(() => { if (disabled) close(); }, [disabled]);
  async function start() {
    if (unavailable.current) return;
    const current = ++attempt.current; setError('');
    try {
      const granted = permission?.granted || (await requestPermission()).granted;
      if (!live.current || unavailable.current || current !== attempt.current) return;
      if (!granted) { setError('Autorize a câmera nas configurações do dispositivo ou use “Digitar código do projeto”.'); return; }
      scanned.current = false; setOpen(true);
    } catch {
      if (live.current && current === attempt.current) setError('Não foi possível abrir a câmera. Tente novamente ou digite o código do projeto.');
    }
  }
  return <View style={{ gap: 8 }}><Button secondary disabled={disabled} title="Ler QR Code" onPress={() => { void start(); }} />{!!error && <Notice error>{error}</Notice>}<Modal visible={open} onRequestClose={close}><SafeAreaView style={{ flex: 1, backgroundColor: C.navy, padding: 16, gap: 16 }}><Text style={[s.body, { color: C.white }]}>Aponte a câmera para o QR Code da etiqueta EM.</Text>{open && <CameraView style={{ flex: 1 }} barcodeScannerSettings={{ barcodeTypes: ['qr'] }} onMountError={() => { close(); setError('Câmera indisponível. Tente novamente ou digite o código do projeto.'); }} onBarcodeScanned={({ data }) => { if (scanned.current || unavailable.current || !live.current) return; close(); onRead(data); }} />}<Button title="Cancelar leitura" onPress={close} /></SafeAreaView></Modal></View>;
}

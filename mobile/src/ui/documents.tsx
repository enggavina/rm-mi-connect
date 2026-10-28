import { useEffect, useState } from 'react';
import { Platform, Text, View } from 'react-native';
import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system/legacy';
import * as IntentLauncher from 'expo-intent-launcher';
import * as Sharing from 'expo-sharing';
import { service } from '../core';
import { DOCUMENT_MIME_TYPES } from '../core/document-policy';
import { isLocalUri } from '../core/sync-policy';
import { Button, Notice, s } from './components';

export function DocumentLink({ uri, title = 'Abrir documento' }: { uri: string; title?: string }) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [available, setAvailable] = useState(false);
  useEffect(() => { let live = true; service.getMediaUrl(uri).then(value => { if (live) setAvailable(isLocalUri(value)); }).catch(() => {}); return () => { live = false; }; }, [uri]);
  async function open() {
    setBusy(true); setError('');
    try {
      const local = await service.getDocumentFile(uri); setAvailable(true);
      const info = await service.documentInfo(local);
      const extension = local.split('.').at(-1)?.toLowerCase();
      const mimeType = (info.mimeType !== 'application/octet-stream' ? info.mimeType : null) || ({ pdf: 'application/pdf', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' } as Record<string, string>)[extension || ''] || 'application/octet-stream';
      if (Platform.OS === 'android') {
        try { await IntentLauncher.startActivityAsync('android.intent.action.VIEW', { data: await FileSystem.getContentUriAsync(local), type: mimeType, flags: 1 }); return; }
        catch { /* The chooser also works when there is no default viewer. */ }
      }
      if (!(await Sharing.isAvailableAsync())) throw new Error('Nenhum visualizador está disponível neste dispositivo.');
      await Sharing.shareAsync(local, { mimeType, dialogTitle: title, ...(extension === 'pdf' ? { UTI: 'com.adobe.pdf' } : {}) });
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível abrir o documento.'); }
    finally { setBusy(false); }
  }
  return <View style={{ gap: 8 }}><Button secondary title={title} busy={busy} onPress={() => { void open(); }} /><Text style={s.muted}>{available ? 'Disponível neste dispositivo, inclusive offline.' : 'Ao abrir com conexão, uma cópia fica disponível offline.'}</Text>{!!error && <Notice error>{error}</Notice>}</View>;
}

export function DocumentField({ label, value, onChange, disabled, onBusyChange }: { label: string; value?: string; onChange: (uri: string) => void; disabled?: boolean; onBusyChange?: (busy: boolean) => void }) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [name, setName] = useState('');
  useEffect(() => { let live = true; setName(''); if (value) service.documentInfo(value).then(info => { if (live) setName(info.name); }).catch(() => {}); return () => { live = false; }; }, [value]);
  async function pick() {
    setBusy(true); onBusyChange?.(true); setError('');
    try {
      const result = await DocumentPicker.getDocumentAsync({ type: DOCUMENT_MIME_TYPES, multiple: false, copyToCacheDirectory: true });
      if (result.canceled) return;
      const file = result.assets[0];
      onChange(await service.addDocument(file.uri, file.name, file.mimeType));
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível salvar o arquivo.'); }
    finally { setBusy(false); onBusyChange?.(false); }
  }
  return <View style={{ gap: 10 }}><Text style={s.h2}>{label}</Text><Text style={s.muted}>PDF, JPG ou PNG · até 20 MB</Text>
    {!!value && <><Text style={s.body}>{name || 'Arquivo anexado'}</Text><DocumentLink uri={value} title="Consultar arquivo anexado" /></>}
    {!disabled && <View style={s.row}><Button secondary busy={busy} title={value ? 'Substituir arquivo' : 'Selecionar arquivo'} onPress={() => { void pick(); }} />{!!value && <Button secondary disabled={busy} title="Remover arquivo" onPress={() => onChange('')} />}</View>}
    {!!error && <Notice error>{error}</Notice>}
  </View>;
}

import { useState } from 'react';
import { Pressable, Text } from 'react-native';
import { router } from 'expo-router';
import { reloadAppAsync } from 'expo';
import { service } from '../src/core';
import { WorkshopRestartRequired } from '../src/core/workshop-database';
import { useApp } from '../src/ui/state';
import { Button, Card, C, Field, Notice, Screen, s } from '../src/ui/components';

export default function Identify() {
  const state = useApp();
  const [matricula, setMatricula] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [restart, setRestart] = useState<WorkshopRestartRequired | null>(null);
  async function submit() {
    setBusy(true); setError('');
    try { await service.identify(matricula.trim(), password); setPassword(''); }
    catch (error) {
      if (error instanceof WorkshopRestartRequired) { setPassword(''); setRestart(error); }
      else setError(error instanceof Error ? error.message : 'Identificação não concluída.');
    }
    finally { setBusy(false); }
  }
  async function reopen() {
    setBusy(true);
    try { await reloadAppAsync('EM workshop changed'); }
    catch { setError('Feche o app pela lista de aplicativos recentes e abra novamente.'); }
    finally { setBusy(false); }
  }
  if (restart) return <Screen auth title="Oficina atualizada">
    <Notice>{restart.message}</Notice>
    {!!error && <Notice error>{error}</Notice>}
    <Button title="Reabrir aplicativo" busy={busy} onPress={() => { void reopen(); }} />
  </Screen>;
  return <Screen auth eyebrow="Acesso à operação" title="Identifique o operador" subtitle="Suas permissões definem as células disponíveis.">
    <Card>
      <Field label="Matrícula" value={matricula} onChangeText={setMatricula} autoCapitalize="none" autoCorrect={false} placeholder="Sua matrícula" />
      <Field label="Palavra-chave" value={password} onChangeText={setPassword} secureTextEntry onSubmitEditing={() => { if (matricula && password && !busy) void submit(); }} />
      {!!error && <Notice error>{error}</Notice>}
      <Button title="Escolher minha célula" busy={busy} disabled={!matricula || !password} onPress={() => { void submit(); }} />
    </Card>
    <Text style={s.muted}>Seus rascunhos e envios são mantidos ao trocar de operador.</Text>
    {!state.online && <Notice>Você está sem conexão. Use a identificação já validada neste dispositivo.</Notice>}
    <Pressable accessibilityRole="button" disabled={busy} onPress={() => router.push('/login')} style={{ minHeight: 48, alignSelf: 'center', justifyContent: 'center' }}>
      <Text style={{ fontSize: 14, fontWeight: '600', color: C.muted }}>Renovar acesso do dispositivo</Text>
    </Pressable>
  </Screen>;
}

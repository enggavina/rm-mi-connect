import { useState } from 'react';
import { Text } from 'react-native';
import { router } from 'expo-router';
import { service } from '../src/core';
import { Button, Card, Field, Notice, Screen, s } from '../src/ui/components';
export default function Identify() {
  const [matricula, setMatricula] = useState(''); const [password, setPassword] = useState(''); const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  async function submit() { setBusy(true); setError(''); try { await service.identify(matricula.trim(), password); setPassword(''); } catch (e) { setError(e instanceof Error ? e.message : 'Identificação não concluída.'); } finally { setBusy(false); } }
  return <Screen auth title="Quem está na operação?" subtitle="Identifique-se para registrar suas atividades."><Card><Field label="Matrícula" value={matricula} onChangeText={setMatricula} autoCapitalize="none" /><Field label="Palavra-chave" value={password} onChangeText={setPassword} secureTextEntry />{!!error && <Notice error>{error}</Notice>}<Button title="Iniciar operação" busy={busy} disabled={!matricula || !password} onPress={() => { void submit(); }} /><Text style={s.muted}>A troca de operador preserva os dados do tablet. A identificação offline está disponível por até 24 horas após a validação online.</Text><Button secondary disabled={busy} title="Renovar login do dispositivo" onPress={() => router.push('/login')} /></Card></Screen>;
}

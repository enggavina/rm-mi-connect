import { useState } from 'react';
import { Text } from 'react-native';
import { router } from 'expo-router';
import { service } from '../src/core';
import { useApp } from '../src/ui/state';
import { Button, Card, Field, Notice, Screen, s } from '../src/ui/components';
export default function Login() {
  const state = useApp(); const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [error, setError] = useState(''); const [busy, setBusy] = useState(false);
  async function submit() { setBusy(true); setError(''); try { await service.login(email.trim(), password); setPassword(''); router.replace('/identify'); } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível entrar.'); } finally { setBusy(false); } }
  return <Screen auth title="Sua oficina, conectada." subtitle="Entre com a conta do tablet ou do supervisor."><Card><Text style={s.h2}>Acesso ao dispositivo</Text>{!state.configured && <Notice error>Configure a URL e a chave pública do Supabase no aplicativo para ativar o acesso.</Notice>}<Field label="E-mail" value={email} autoCapitalize="none" keyboardType="email-address" autoComplete="email" onChangeText={setEmail} /><Field label="Senha" value={password} secureTextEntry autoComplete="current-password" onChangeText={setPassword} />{!!error && <Notice error>{error}</Notice>}<Button title="Entrar" busy={busy} disabled={!email || !password || !state.configured || !state.online} onPress={() => { void submit(); }} /><Text style={s.muted}>O primeiro acesso precisa de conexão. Depois da sincronização, os catálogos e rascunhos ficam disponíveis neste dispositivo.</Text></Card></Screen>;
}

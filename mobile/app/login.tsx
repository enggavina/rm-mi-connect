import { useState } from 'react';
import { Image, Text, View } from 'react-native';
import { router } from 'expo-router';
import { service } from '../src/core';
import { useApp } from '../src/ui/state';
import { Button, Card, Field, Notice, Screen, s } from '../src/ui/components';

export default function Login() {
  const state = useApp();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  async function submit() {
    setBusy(true); setError('');
    try { await service.login(email.trim(), password); setPassword(''); router.replace('/identify'); }
    catch (error) { setError(error instanceof Error ? error.message : 'Não foi possível entrar.'); }
    finally { setBusy(false); }
  }
  return <Screen auth eyebrow="Operação da oficina" title="Acesso ao EM" subtitle="Entre com a conta autorizada para este dispositivo.">
    <Card>
      <View style={{ alignItems: 'center', paddingVertical: 4 }}>
        <Image accessibilityLabel="Logo MI Electric Brasil" source={require('../assets/brand/mi-electric-brasil.png')} style={{ width: 138, height: 136 }} resizeMode="contain" />
      </View>
      {!state.configured && <Notice error>Este aplicativo ainda não foi configurado. Solicite a configuração ao responsável pelo dispositivo.</Notice>}
      <Field label="E-mail" value={email} autoCapitalize="none" keyboardType="email-address" autoComplete="email" onChangeText={setEmail} placeholder="seu e-mail de acesso" />
      <Field label="Senha" value={password} secureTextEntry autoComplete="current-password" onChangeText={setPassword} onSubmitEditing={() => { if (email && password && state.online && !busy) void submit(); }} />
      {!!error && <Notice error>{error}</Notice>}
      <Button title="Entrar" busy={busy} disabled={!email || !password || !state.configured || !state.online} onPress={() => { void submit(); }} />
    </Card>
    <Text style={s.muted}>Após entrar, identifique o operador para escolher uma das células permitidas em seu cadastro.</Text>
    {!state.online && <Notice>Conecte este dispositivo à internet para realizar o primeiro acesso.</Notice>}
  </Screen>;
}

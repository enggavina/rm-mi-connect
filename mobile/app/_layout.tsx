import { useEffect } from 'react';
import { ActivityIndicator, Text, View } from 'react-native';
import { Stack, router, useSegments } from 'expo-router';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { service } from '../src/core';
import { useApp } from '../src/ui/state';
import { C, Button } from '../src/ui/components';
export default function Layout() {
  const state = useApp(); const segments = useSegments();
  useEffect(() => { void service.initialize().catch(() => {}); }, []);
  useEffect(() => { if (!state.ready) return; const route = segments[0]; if (!state.sessionUserId && route !== 'login') router.replace('/login'); else if (state.sessionUserId && !state.operator && route !== 'identify' && route !== 'login') router.replace('/identify'); else if (state.operator && (route === 'login' || route === 'identify')) router.replace('/celula'); }, [state.ready, state.sessionUserId, state.operator, segments]);
  return <SafeAreaProvider><StatusBar style="dark" backgroundColor={C.white} />{state.ready ? <Stack key={state.operator?.operador_id ?? 'identification'} screenOptions={{ headerShown: false, animation: 'slide_from_right', contentStyle: { backgroundColor: C.bg } }} /> : <View style={{ flex: 1, backgroundColor: C.bg, justifyContent: 'center', alignItems: 'center', padding: 24, gap: 20 }}><ActivityIndicator color={C.primary} size="large" /><Text>{state.error || 'Preparando o EM…'}</Text>{state.error && <Button title="Tentar novamente" onPress={() => { void service.initialize().catch(() => {}); }} />}</View>}</SafeAreaProvider>;
}

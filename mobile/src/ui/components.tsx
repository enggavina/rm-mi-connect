import React, { useState } from 'react';
import { ActivityIndicator, KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type TextInputProps, type ViewStyle } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, usePathname, type Href } from 'expo-router';
import * as Haptics from 'expo-haptics';
import { service } from '../core';
import { useApp } from './state';

export const C = { bg: '#F2F5F8', ink: '#14243A', muted: '#536579', line: '#D5DFE9', primary: '#086955', navy: '#102C46', white: '#FFFFFF', danger: '#AD263D', amber: '#9C5800', pale: '#E4F4ED' };
export const s = StyleSheet.create({
  body: { fontSize: 16, lineHeight: 24, color: C.ink }, muted: { fontSize: 14, lineHeight: 21, color: C.muted },
  title: { fontSize: 30, fontWeight: '800', color: C.ink }, h2: { fontSize: 21, fontWeight: '700', color: C.ink },
  card: { backgroundColor: C.white, padding: 20, borderRadius: 16, borderColor: C.line, borderWidth: 1, gap: 12 },
  row: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 12 },
  input: { minHeight: 54, borderWidth: 1, borderColor: '#9CAFBF', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, color: C.ink, backgroundColor: C.white, fontSize: 17 },
});
export function Button({ title, onPress, secondary, danger, disabled, busy }: { title: string; onPress: () => void; secondary?: boolean; danger?: boolean; disabled?: boolean; busy?: boolean }) {
  return <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityState={{ disabled: disabled || busy }} disabled={disabled || busy} onPress={() => { void Haptics.selectionAsync().catch(() => {}); onPress(); }} style={({ pressed }) => ({ minHeight: 52, paddingHorizontal: 18, paddingVertical: 14, borderRadius: 10, alignItems: 'center', justifyContent: 'center', flexDirection: 'row', gap: 8, opacity: disabled || busy ? .45 : pressed ? .8 : 1, backgroundColor: danger ? C.danger : secondary ? '#E7EDF3' : C.primary })}>
    {busy && <ActivityIndicator color={secondary ? C.ink : C.white} />}<Text style={{ fontSize: 16, fontWeight: '700', color: secondary ? C.ink : C.white }}>{title}</Text>
  </Pressable>;
}
export function Field({ label, ...props }: TextInputProps & { label: string }) { return <View style={{ gap: 7 }}><Text style={{ color: C.ink, fontSize: 15, fontWeight: '600' }}>{label}</Text><TextInput accessibilityLabel={label} placeholderTextColor={C.muted} {...props} style={[s.input, props.multiline && { minHeight: 110, textAlignVertical: 'top' }, props.style]} /></View>; }
export function Notice({ children, error }: { children: React.ReactNode; error?: boolean }) { return <View accessibilityRole="alert" style={{ backgroundColor: error ? '#FFE9ED' : C.pale, borderRadius: 10, padding: 14 }}><Text style={[s.body, { color: error ? C.danger : C.primary }]}>{children}</Text></View>; }
export function Card({ children, style }: { children: React.ReactNode; style?: ViewStyle }) { return <View style={[s.card, style]}>{children}</View>; }
export function Badge({ text, alert }: { text: string; alert?: boolean }) { return <View style={{ alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 7, backgroundColor: alert ? '#FFE9D0' : '#E7EDF3' }}><Text style={{ color: alert ? C.amber : C.ink, fontSize: 13, fontWeight: '700' }}>{text}</Text></View>; }
const nav: [string, Href][] = [['Células', '/celula'], ['Recebimento', '/recebimento'], ['Formulários', '/formularios'], ['Revisões', '/revisao-form'], ['Aprovações', '/aprovacao'], ['Peritagem', '/peritagem']];
export function Screen({ title, subtitle, children, auth = false }: { title: string; subtitle?: string; children: React.ReactNode; auth?: boolean }) {
  const state = useApp(); const path = usePathname();
  return <SafeAreaView style={{ flex: 1, backgroundColor: C.navy }} edges={['top', 'left', 'right']}>
    <View style={{ padding: 16, backgroundColor: C.navy, gap: 10 }}><View style={[s.row, { justifyContent: 'space-between' }]}><Text style={{ color: C.white, fontSize: 19, fontWeight: '800', letterSpacing: 1 }}>RM <Text style={{ color: '#71D8BC' }}>·</Text> MI CONNECT</Text>{state.operator && <Pressable accessibilityRole="button" onPress={() => { void service.switchOperator().then(() => router.replace('/identify')); }} style={{ minHeight: 44, justifyContent: 'center' }}><Text style={{ color: C.white, fontSize: 15 }}>{state.operator.nome} · Trocar</Text></Pressable>}</View>
      {!auth && <View style={[s.row, { justifyContent: 'space-between' }]}><Text style={{ color: state.online ? '#91E5C7' : '#FFD298', flexShrink: 1 }}>{state.online ? '● Online' : '● Offline'} · {state.pendingMedia} mídias · {state.pendingMutations} envios pendentes</Text><Pressable accessibilityRole="button" disabled={state.syncing || !state.online} onPress={() => { void service.sync(true).catch(() => {}); }} style={{ minHeight: 44, justifyContent: 'center' }}><Text style={{ color: C.white, fontWeight: '700' }}>{state.syncing ? 'Sincronizando…' : 'Sincronizar agora'}</Text></Pressable></View>}
    </View>
    {!auth && <View style={{ backgroundColor: C.white, borderBottomWidth: 1, borderColor: C.line }}><ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 10 }}>{nav.map(([text, href]) => <Pressable key={text} accessibilityRole="tab" accessibilityState={{ selected: path === href }} onPress={() => router.navigate(href)} style={{ padding: 16, minHeight: 52, borderBottomWidth: 3, borderColor: path === href ? C.primary : 'transparent' }}><Text style={{ color: path === href ? C.primary : C.muted, fontWeight: '700' }}>{text}</Text></Pressable>)}</ScrollView></View>}
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: C.bg }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ padding: 20, paddingBottom: 60, gap: 20, maxWidth: 1100, width: '100%', alignSelf: 'center' }}><View style={{ gap: 6 }}><Text style={s.title}>{title}</Text>{subtitle && <Text style={s.muted}>{subtitle}</Text>}</View>{!auth && state.error && <Notice error>{state.error}</Notice>}{children}</ScrollView></KeyboardAvoidingView>
  </SafeAreaView>;
}
export function Select({ label, value, options, onChange, multiple = false, disabled = false }: { label: string; value: string | string[]; options: { value: string; label: string }[]; onChange: (value: string[]) => void; multiple?: boolean; disabled?: boolean }) {
  const [open, setOpen] = useState(false); const [search, setSearch] = useState(''); const selected = Array.isArray(value) ? value : value ? [value] : [];
  return <View style={{ gap: 7 }}><Text style={{ fontSize: 15, fontWeight: '600', color: C.ink }}>{label}</Text><Button secondary disabled={disabled} title={selected.length ? options.filter(x => selected.includes(x.value)).map(x => x.label).join(', ') || 'Selecionado' : 'Selecionar…'} onPress={() => setOpen(true)} />
    <Modal visible={open} onRequestClose={() => setOpen(false)} animationType="slide"><SafeAreaView style={{ flex: 1, backgroundColor: C.bg, padding: 20, gap: 14 }}><Text style={s.h2}>{label}</Text><Field label="Buscar" value={search} onChangeText={setSearch} /><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ gap: 8 }}>{options.filter(x => x.label.toLocaleLowerCase().includes(search.toLocaleLowerCase())).map(x => <Button key={x.value} secondary={!selected.includes(x.value)} title={`${selected.includes(x.value) ? '✓ ' : ''}${x.label}`} onPress={() => { onChange(multiple ? selected.includes(x.value) ? selected.filter(v => v !== x.value) : [...selected, x.value] : [x.value]); if (!multiple) setOpen(false); }} />)}{!options.length && <Notice>Nenhum item disponível. Sincronize o catálogo com conexão.</Notice>}</ScrollView><Button title="Concluir seleção" onPress={() => setOpen(false)} /></SafeAreaView></Modal>
  </View>;
}

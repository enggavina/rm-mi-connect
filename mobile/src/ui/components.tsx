import React, { useState } from 'react';
import { ActivityIndicator, Image, KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type TextInputProps, type ViewStyle } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, type Href } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import * as Haptics from 'expo-haptics';
import { service } from '../core';
import { showSyncRecovery } from '../core/sync-recovery';
import { useApp } from './state';

export const C = {
  bg: '#F5F5F6', ink: '#0E1724', navy: '#0E1724', muted: '#616875', line: '#DFE2E7',
  brand: '#E73E42', primary: '#BF2D35', white: '#FFFFFF', danger: '#A52330',
  amber: '#80530D', pale: '#FFF0F1', soft: '#F0F1F3',
};
export const s = StyleSheet.create({
  body: { fontSize: 16, lineHeight: 24, color: C.ink },
  muted: { fontSize: 14, lineHeight: 21, color: C.muted },
  title: { fontSize: 29, lineHeight: 36, fontWeight: '800', letterSpacing: -.7, color: C.ink },
  h2: { fontSize: 20, lineHeight: 27, fontWeight: '700', color: C.ink },
  card: { backgroundColor: C.white, padding: 20, borderRadius: 16, borderColor: C.line, borderWidth: 1, gap: 12 },
  row: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 12 },
  input: { minHeight: 54, borderWidth: 1, borderColor: '#BDC2CB', borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, color: C.ink, backgroundColor: C.white, fontSize: 17 },
});

export function BrandLockup() {
  return <View accessible accessibilityLabel="EM, MI Electric Brasil" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
    <Image source={require('../../assets/brand/mi-symbol.png')} style={{ width: 46, height: 46 }} resizeMode="contain" />
    <View><Text style={{ fontSize: 27, lineHeight: 29, fontWeight: '900', letterSpacing: -.8, color: C.ink }}>EM</Text>
      <Text style={{ color: C.muted, fontSize: 12, lineHeight: 17, fontWeight: '600' }}>MI Electric Brasil</Text></View>
  </View>;
}
export function Button({ title, onPress, secondary, danger, disabled, busy }: { title: string; onPress: () => void; secondary?: boolean; danger?: boolean; disabled?: boolean; busy?: boolean }) {
  return <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityState={{ disabled: disabled || busy }} disabled={disabled || busy}
    onPress={() => { void Haptics.selectionAsync().catch(() => {}); onPress(); }}
    style={({ pressed }) => ({ minHeight: 52, paddingHorizontal: 18, paddingVertical: 14, borderRadius: 11, alignItems: 'center', justifyContent: 'center', flexDirection: 'row', gap: 8,
      opacity: disabled || busy ? .45 : pressed ? .8 : 1, backgroundColor: danger ? C.danger : secondary ? C.soft : C.primary })}>
    {busy && <ActivityIndicator color={secondary ? C.ink : C.white} />}
    <Text style={{ fontSize: 16, fontWeight: '700', color: secondary ? C.ink : C.white }}>{title}</Text>
  </Pressable>;
}
export function Field({ label, ...props }: TextInputProps & { label: string }) {
  return <View style={{ gap: 7 }}><Text style={{ color: C.ink, fontSize: 14, fontWeight: '600' }}>{label}</Text>
    <TextInput accessibilityLabel={label} placeholderTextColor={C.muted} selectionColor={C.primary} {...props} style={[s.input, props.multiline && { minHeight: 110, textAlignVertical: 'top' }, props.style]} />
  </View>;
}
export function Notice({ children, error }: { children: React.ReactNode; error?: boolean }) {
  return <View accessibilityRole="alert" style={{ backgroundColor: error ? '#FFE8EC' : C.soft, borderRadius: 11, padding: 14, borderLeftWidth: 3, borderLeftColor: error ? C.danger : '#A4ABB5' }}>
    <Text style={[s.body, { color: error ? C.danger : C.ink }]}>{children}</Text>
  </View>;
}
export function Card({ children, style }: { children: React.ReactNode; style?: ViewStyle }) { return <View style={[s.card, style]}>{children}</View>; }
export function Badge({ text, alert }: { text: string; alert?: boolean }) {
  return <View style={{ alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 7, backgroundColor: alert ? '#FFF1D9' : C.soft }}>
    <Text style={{ color: alert ? C.amber : C.muted, fontSize: 12, fontWeight: '700' }}>{text}</Text>
  </View>;
}
type ScreenProps = { title: string; subtitle?: string; children: React.ReactNode; auth?: boolean; backHref?: Href; backLabel?: string; eyebrow?: string; scrollRef?: React.RefObject<ScrollView | null>; floatingFooter?: React.ReactNode; };
export function Screen({ title, subtitle, children, auth = false, backHref, backLabel = 'Voltar', eyebrow, scrollRef, floatingFooter }: ScreenProps) {
  const state = useApp();
  const [menu, setMenu] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [menuError, setMenuError] = useState('');
  const pending = state.pendingMedia + state.pendingMutations;
  const open = (href: Href) => { setMenu(false); router.navigate(href); };
  const switchOperator = async () => {
    setSwitching(true); setMenuError('');
    try { await service.switchOperator(); setMenu(false); router.replace('/identify'); }
    catch (error) { setMenuError(error instanceof Error ? error.message : 'Não foi possível trocar o operador.'); }
    finally { setSwitching(false); }
  };
  return <SafeAreaView style={{ flex: 1, backgroundColor: C.white }} edges={['top', 'left', 'right']}>
    <View style={{ paddingHorizontal: 20, paddingVertical: 12, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: 1, borderBottomColor: C.line }}>
      <BrandLockup />
      {!auth && <Pressable accessibilityRole="button" accessibilityLabel="Abrir menu do operador" onPress={() => setMenu(true)} style={{ width: 46, height: 46, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: C.soft }}>
        <Feather name="menu" size={23} color={C.ink} />
      </Pressable>}
    </View>
    {!auth && showSyncRecovery(state) && <View accessibilityLiveRegion="polite" style={{ backgroundColor: C.ink, paddingHorizontal: 20, paddingVertical: 8, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={{ color: C.white, fontSize: 12, fontWeight: '600' }}>{state.online ? 'Dados aguardando envio' : 'Sem conexão'}</Text>
        <Text style={{ color: '#C4C8D0', fontSize: 11 }}>{pending ? `${state.pendingMedia} arquivos · ${state.pendingMutations} registros aguardando envio` : 'Você pode continuar trabalhando neste dispositivo.'}</Text>
      </View>
      {state.online && <Pressable accessibilityRole="button" accessibilityLabel="Sincronizar agora" accessibilityState={{ disabled: state.syncing }} disabled={state.syncing}
        onPress={() => { void service.sync(true).catch(() => {}); }} style={{ minHeight: 40, paddingHorizontal: 4, flexDirection: 'row', alignItems: 'center', gap: 7 }}>
        {state.syncing ? <ActivityIndicator size="small" color={C.white} /> : <Feather name="refresh-cw" size={15} color={C.white} />}
        <Text style={{ color: C.white, fontSize: 12, fontWeight: '600' }}>{state.syncing ? 'Sincronizando' : 'Sincronizar'}</Text>
      </Pressable>}
    </View>}
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: C.bg }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView ref={scrollRef} style={{ flex: 1 }} keyboardShouldPersistTaps="handled" contentContainerStyle={{ padding: 20, paddingBottom: 56, gap: 20, maxWidth: auth ? 560 : 1200, width: '100%', alignSelf: 'center' }}>
        {backHref && <Pressable accessibilityRole="button" accessibilityLabel={backLabel} onPress={() => router.navigate(backHref)} style={{ minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 9, alignSelf: 'flex-start' }}>
          <Feather name="arrow-left" color={C.primary} size={20} /><Text style={{ color: C.primary, fontSize: 15, fontWeight: '700' }}>{backLabel}</Text>
        </Pressable>}
        <View style={{ gap: 7 }}>
          {!!eyebrow && <Text style={{ color: C.primary, fontSize: 11, lineHeight: 16, fontWeight: '800', letterSpacing: 1.4 }}>{eyebrow.toLocaleUpperCase('pt-BR')}</Text>}
          <Text style={s.title}>{title}</Text>{subtitle && <Text style={s.muted}>{subtitle}</Text>}
        </View>
        {!auth && state.error && <Notice error>{state.error}</Notice>}
        {!auth && state.mediaCacheNotice && <Notice>{state.mediaCacheNotice}</Notice>}
        {children}
      </ScrollView>
      {floatingFooter && <View style={{ padding: 12, paddingBottom: 24, borderTopWidth: 1, borderTopColor: C.line, backgroundColor: C.white }}>{floatingFooter}</View>}
    </KeyboardAvoidingView>
    <Modal visible={menu} onRequestClose={() => setMenu(false)} animationType="slide" presentationStyle="pageSheet">
      <SafeAreaView style={{ flex: 1, backgroundColor: C.bg }}>
        <ScrollView contentContainerStyle={{ padding: 24, gap: 24, width: '100%', maxWidth: 600, alignSelf: 'center' }}>
          <View style={[s.row, { justifyContent: 'space-between' }]}><BrandLockup /><Pressable accessibilityRole="button" accessibilityLabel="Fechar menu" onPress={() => setMenu(false)} style={{ padding: 12 }}><Feather name="x" size={24} color={C.ink} /></Pressable></View>
          <Card><Text style={s.h2}>{state.operator?.nome}</Text><Text style={s.muted}>{state.operator?.cargo || 'Operador'} · {state.operator?.matricula}</Text>
            <Button title="Minhas células" onPress={() => open('/celula')} />
            <Button secondary busy={switching} title="Trocar operador" onPress={() => { void switchOperator(); }} />
            {!!menuError && <Notice error>{menuError}</Notice>}
          </Card>
          <Card><Text style={s.h2}>Outras atividades</Text>
            <Button secondary title="Recebimento de equipamento" onPress={() => open('/recebimento')} />
          </Card>
          <Text style={s.muted}>A troca de operador mantém os rascunhos e os envios pendentes de cada pessoa.</Text>
        </ScrollView>
      </SafeAreaView>
    </Modal>
  </SafeAreaView>;
}
export function Select({ label, value, options, onChange, multiple = false, disabled = false }: { label: string; value: string | string[]; options: { value: string; label: string }[]; onChange: (value: string[]) => void; multiple?: boolean; disabled?: boolean }) {
  const [open, setOpen] = useState(false); const [search, setSearch] = useState('');
  const [draft, setDraft] = useState<string[]>([]);
  const selected = Array.isArray(value) ? value : typeof value === 'string' && (value !== '' || options.some(option => option.value === '')) ? [value] : [];
  const active = multiple ? draft : selected;
  const visible = options.filter(option => option.label.toLocaleLowerCase().includes(search.toLocaleLowerCase()));
  const cancel = () => { setOpen(false); setDraft([]); setSearch(''); };
  return <View style={{ gap: 7 }}>
    <Text style={{ fontSize: 14, fontWeight: '600', color: C.ink }}>{label}</Text>
    <Button secondary disabled={disabled} title={selected.length ? options.filter(option => selected.includes(option.value)).map(option => option.label).join(', ') || 'Selecionado' : 'Selecionar…'} onPress={() => { setDraft([...selected]); setSearch(''); setOpen(true); }} />
    <Modal visible={open} onRequestClose={cancel} animationType="slide">
      <SafeAreaView style={{ flex: 1, backgroundColor: C.bg, padding: 20, gap: 14 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
          <Text style={[s.h2, { flex: 1 }]}>{label}</Text>
          <Pressable accessibilityRole="button" accessibilityLabel={`Cancelar seleção de ${label}`} onPress={cancel} style={{ minHeight: 48, paddingHorizontal: 10, flexDirection: 'row', alignItems: 'center', gap: 6 }}>
            <Feather name="x" size={20} color={C.primary} /><Text style={{ color: C.primary, fontWeight: '700', fontSize: 16 }}>Cancelar</Text>
          </Pressable>
        </View>
        <KeyboardAvoidingView style={{ flex: 1, gap: 14 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <Field label="Buscar" value={search} onChangeText={setSearch} />
          {multiple && <Text style={s.muted}>Marque as opções e confirme para salvar a seleção.</Text>}
          <ScrollView style={{ flex: 1 }} keyboardShouldPersistTaps="handled" contentContainerStyle={{ gap: 8 }}>
            {visible.map(option => <Button key={option.value} secondary={!active.includes(option.value)} disabled={disabled} title={`${active.includes(option.value) ? '✓ ' : ''}${option.label}`} onPress={() => {
              if (multiple) setDraft(current => current.includes(option.value) ? current.filter(item => item !== option.value) : [...current, option.value]);
              else { onChange([option.value]); setOpen(false); }
            }} />)}
            {!visible.length && <Notice>{options.length ? 'Nenhum resultado para esta busca.' : 'Nenhum item disponível.'}</Notice>}
          </ScrollView>
          {multiple && <Button title="Confirmar seleção" disabled={disabled} onPress={() => { onChange([...draft]); setOpen(false); }} />}
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  </View>;
}

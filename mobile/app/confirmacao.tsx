import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { service, type Row } from '../src/core';
import { useApp } from '../src/ui/state';
import { Button, Card, Notice, Screen, s } from '../src/ui/components';
export default function Confirmacao() {
  const { id, tipo } = useLocalSearchParams<{ id?: string; tipo?: string }>(); const state = useApp(); const [item,setItem] = useState<Row | null>(null);
  useEffect(() => { if (id) service.operation(id).then(setItem).catch(() => {}); }, [id,state.revision]);
  return <Screen title="Registro salvo" subtitle={`${tipo || 'Atividade'} armazenado neste dispositivo.`}><Card><Text style={s.h2}>{item?.status === 'completed' ? 'Recebido pelo servidor' : 'Na fila de sincronização'}</Text><Notice>{item?.status === 'completed' ? 'O Supabase confirmou o envio. A ponte com o Bubble processará a atualização em seguida.' : 'Você pode continuar trabalhando. O envio será processado quando houver conexão e uma sessão válida.'}</Notice>{item?.last_error && <Notice error>{item.last_error}</Notice>}<Text selectable style={s.muted}>Protocolo: {id}</Text><Button title="Voltar para as células" onPress={() => router.replace('/celula')} /><Button secondary title="Sincronizar agora" busy={state.syncing} disabled={!state.online} onPress={() => { void service.sync(true).catch(() => {}); }} /></Card></Screen>;
}

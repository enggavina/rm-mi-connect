import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { router, useLocalSearchParams, type Href } from 'expo-router';
import { service, type Row } from '../src/core';
import { useApp } from '../src/ui/state';
import { Button, Card, Notice, Screen, s } from '../src/ui/components';
export default function Confirmacao() {
  const { id, tipo, projeto, celula } = useLocalSearchParams<{ id?: string; tipo?: string; projeto?: string; celula?: string }>(); const state = useApp(); const [item,setItem] = useState<Row | null>(null);
  const destination: Href = projeto && celula ? { pathname: '/projeto', params: { projeto, celula } } : '/celula';
  const backLabel = projeto && celula ? 'Voltar ao projeto' : 'Escolher célula';
  useEffect(() => { if (id) service.operation(id).then(setItem).catch(() => {}); }, [id,state.revision]);
  return <Screen title="Registro salvo" subtitle={`${tipo || 'Atividade'} armazenado neste dispositivo.`} backHref={destination} backLabel={backLabel}><Card><Text style={s.h2}>{item?.status === 'completed' ? 'Registro sincronizado' : 'Na fila de sincronização'}</Text><Notice>{item?.status === 'completed' ? 'O envio foi confirmado. Você pode continuar as atividades do projeto.' : 'Você pode continuar trabalhando. O envio será processado quando houver conexão e uma sessão válida.'}</Notice>{item?.last_error && <Notice error>{item.last_error}</Notice>}<Text selectable style={s.muted}>Protocolo: {id}</Text><Button title={backLabel} onPress={() => router.replace(destination)} /><Button secondary title="Sincronizar agora" busy={state.syncing} disabled={!state.online} onPress={() => { void service.sync(true).catch(() => {}); }} /></Card></Screen>;
}

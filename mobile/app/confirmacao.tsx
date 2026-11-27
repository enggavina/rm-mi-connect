import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { router, useLocalSearchParams, type Href } from 'expo-router';
import { service, type Row } from '../src/core';
import { showSyncRecovery } from '../src/core/sync-recovery';
import { EXECUTION_RPC, parseExecutionReceipt } from '../src/core/execution';
import type { ReceivingOpeningState } from '../src/core/receiving-opening';
import { useApp, useRows } from '../src/ui/state';
import { Button, Card, Notice, Screen, s } from '../src/ui/components';
export default function Confirmacao() {
  const { id, tipo, projeto, celula } = useLocalSearchParams<{ id?: string; tipo?: string; projeto?: string; celula?: string }>(); const state = useApp(); const [loadedItem,setItem] = useState<Row | null>(null);
  const item = loadedItem && loadedItem.id === id && loadedItem.actor_id === state.operator?.operador_id ? loadedItem : null;
  const [openingState, setOpening] = useState<ReceivingOpeningState | null>(null);
  const opening = openingState?.owner === state.sessionUserId && openingState.actor === state.operator?.operador_id && openingState.receivingId === id ? openingState : null;
  const allocations = useRows('rm_celulas_projeto');
  const closed = allocations.rows.some(row => row.projeto_id === projeto && row.celula_id === celula && row.visibilidade === false);
  const destination: Href = projeto && celula ? closed ? { pathname: '/projetos', params: { celula } } : { pathname: '/projeto', params: { projeto, celula } } : '/celula';
  const backLabel = projeto && celula ? closed ? 'Projetos da célula' : 'Voltar ao projeto' : 'Escolher célula';
  let executionReview = false;
  if (item?.rpc_name === EXECUTION_RPC && item.status === 'completed') { try { executionReview = parseExecutionReceipt(item.result).disposition === 'review'; } catch { /* A malformed result does not authorize another command. */ } }
  useEffect(() => { let live = true; if (id) {
    service.operation(id).then(value => { if (live) setItem(value); }).catch(() => {});
    service.receivingOpeningInfo(id).then(value => { if (live) setOpening(value); }).catch(() => { if (live) setOpening(null); });
  } return () => { live = false; }; }, [id,state.revision,state.operator?.operador_id,state.sessionUserId]);
  const title = executionReview ? 'Recebido para revisão' : item?.status === 'completed' ? 'Registro sincronizado' : opening?.receipt?.attachments_pending ? opening.receipt.opening_created ? 'Projeto aberto; anexos pendentes' : 'Projeto identificado; anexos pendentes' : opening?.receipt ? 'Projeto confirmado no banco' : 'Na fila de sincronização';
  const message = executionReview ? 'O apontamento foi recebido e preservado. A gestão precisa conferir o registro antes de confirmar a mudança no acompanhamento.' : item?.status === 'completed' ? 'O envio foi confirmado. Você pode continuar as atividades do projeto.'
    : opening?.receipt?.attachments_pending ? opening.receipt.opening_created ? 'O projeto já está disponível em Recebimentos no portal web. Fotos e nota fiscal continuam sendo enviadas, com o mesmo protocolo.' : 'O projeto foi identificado. Fotos e nota fiscal continuam sendo enviadas, com o mesmo protocolo.'
    : opening?.receipt ? 'O recebimento já está confirmado no banco. A confirmação final deste dispositivo continua na fila, com o protocolo original.' : item?.rpc_name === 'rm_submit_recebimento_v1' ? 'Você pode continuar trabalhando. Com conexão, a abertura do projeto tem prioridade sobre o envio dos anexos. Os dados permanecem salvos até a confirmação.' : 'Você pode continuar trabalhando. O envio será processado quando houver conexão e uma sessão válida.';
  return <Screen title="Registro salvo" subtitle={`${tipo || 'Atividade'} armazenado neste dispositivo.`} backHref={destination} backLabel={backLabel}><Card><Text style={s.h2}>{title}</Text><Notice>{message}</Notice>{item?.last_error && <Notice error>{item.last_error}</Notice>}{item?.status !== 'completed' && opening?.error && <Notice error>A abertura ainda não foi confirmada: {opening.error}</Notice>}{(item || opening) && <Text selectable style={s.muted}>Protocolo: {id}</Text>}<Button title={backLabel} onPress={() => router.replace(destination)} />{item?.status !== 'completed' && state.online && (showSyncRecovery(state) || item?.rpc_name === 'rm_submit_recebimento_v1') && <Button secondary title="Sincronizar agora" busy={state.syncing} disabled={!state.online} onPress={() => { void service.sync(true).catch(() => {}); }} />}</Card></Screen>;
}

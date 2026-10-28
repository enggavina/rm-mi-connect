import { useRef, useState } from 'react';
import { Modal, Pressable, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import type { OutboxRow, Row } from '../core';
import { cellCompletionRequirements, cellStatusLabel, cellStatusOptions, queuedProjectActions } from '../domain/project-actions';
import { useActionDraft } from './action-draft';
import { Badge, Button, C, Notice, Select, s } from './components';

export function CellStatusAction({ allocation, queue, ready, records, photos, catalogsLoaded }: { allocation: Row; queue: OutboxRow[]; ready: boolean; records: Row[]; photos: Row[]; catalogsLoaded: boolean }) {
  const [open, setOpen] = useState(false);
  const action = useActionDraft(`cell-status:${allocation.id}:${allocation.updated_at}`, { status: allocation.status as string });
  const pending = queuedProjectActions(queue, 'rm_update_cell_status_v1', { field: 'p_celula_projeto_id', id: allocation.id })[0];
  const receipt = pending?.operation.id || (action.draft?.submitted ? action.draft.id : undefined);
  const requirements = cellCompletionRequirements(allocation, records, photos, queue, catalogsLoaded && ready);
  const currentRequirements = useRef(requirements); currentRequirements.current = requirements;
  const finalizing = action.draft?.values.status === 'finalizado';
  function showReceipt(id: string) { setOpen(false); router.push({ pathname: '/confirmacao', params: { id, tipo: 'Status', projeto: allocation.projeto_id, celula: allocation.celula_id } }); }
  async function submit() {
    if (receipt || !ready) return;
    const id = await action.submit('rm_update_cell_status_v1', values => {
      if (!cellStatusOptions.some(option => option.value === values.status)) throw new Error('Selecione um status válido.');
      if (values.status === allocation.status) throw new Error('Selecione um status diferente do atual.');
      if (values.status === 'finalizado') {
        const check = currentRequirements.current;
        if (!check.loaded) throw new Error('Aguarde o carregamento dos formulários e fotos antes de finalizar.');
        if (!check.canFinalize) throw new Error(`Faltam ${check.missingForms} formulário(s) e ${check.missingPhotos} foto(s) obrigatória(s).`);
      }
      return { p_celula_projeto_id: allocation.id, p_status: values.status };
    });
    if (id) showReceipt(id);
  }
  return <>
    <Pressable accessibilityRole="button" accessibilityLabel={`Alterar status: ${cellStatusLabel(allocation.status)}`} onPress={() => setOpen(true)} style={{ minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 6 }}><Badge text={cellStatusLabel(allocation.status)} /><Feather name="edit-2" size={15} color={C.primary} />{receipt && <Badge text="Envio registrado" alert />}</Pressable>
    <Modal visible={open} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setOpen(false)}><SafeAreaView style={{ flex: 1, backgroundColor: C.bg, padding: 24, gap: 20 }}>
      <Text style={s.h2}>Status da célula{allocation.numero_projeto ? ` · OS ${allocation.numero_projeto}` : ''}</Text><Text style={s.body}>Status atual: {cellStatusLabel(allocation.status)}</Text>
      {!ready || !action.draft ? <Notice>Consultando alterações salvas neste dispositivo…</Notice> : receipt ? <><Notice>{pending ? `Há uma alteração para ${cellStatusLabel(String(pending.params.p_status))} aguardando confirmação. Ela mantém o operador que registrou o envio.` : 'Esta alteração já foi registrada. Aguarde a atualização do projeto antes de alterar novamente.'}</Notice>{!!pending?.operation.last_error && <Notice error>{pending.operation.last_error}</Notice>}<Button title="Consultar envio" onPress={() => showReceipt(receipt)} /></> : <>
        <Select label="Novo status" value={action.draft.values.status} options={[...cellStatusOptions]} onChange={values => action.update({ status: values[0] })} disabled={action.busy} />
        {finalizing && <Notice error={requirements.loaded && !requirements.canFinalize}>{!requirements.loaded ? 'Carregando formulários e fotos para verificar a finalização…' : !requirements.canFinalize ? `Faltam ${requirements.missingForms} formulário(s) e ${requirements.missingPhotos} foto(s) obrigatória(s). Complete os itens antes de finalizar.` : 'Todos os formulários vinculados e fotos obrigatórias estão registrados ou na fila de envio. A finalização será confirmada após a sincronização.'}</Notice>}
        <Button title="Salvar status" busy={action.busy} disabled={!!action.saving || action.draft.values.status === allocation.status || (finalizing && !requirements.canFinalize)} onPress={() => { void submit(); }} />
      </>}{!!action.error && <Notice error>{action.error}</Notice>}<Button secondary title="Fechar" disabled={action.busy} onPress={() => setOpen(false)} />
    </SafeAreaView></Modal>
  </>;
}

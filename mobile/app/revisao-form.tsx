import { Text } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { FormScreen } from '../src/ui/form-screen';
import { useRows } from '../src/ui/state';
import { Badge, Button, Card, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';
import { canReviseRecord } from '../src/domain/journey';

export default function Revisao() {
  const { registro, projeto, celula } = useLocalSearchParams<{ registro?: string; projeto?: string; celula?: string }>();
  const records = useRows('rm_registros_formulario'); const { context, error } = useJourney(celula, projeto);
  if (registro) return <FormScreen recordId={registro} projectId={projeto} cellId={celula} />;
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Selecione um projeto" />;
  const rows = records.rows.filter(record => canReviseRecord(context, record));
  return <Screen title="Revisões solicitadas" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Corrija as observações da engenharia e envie para nova análise.">
    {records.error && <Notice error>{records.error}</Notice>}{!rows.length && <Notice>Nenhum formulário em revisão neste projeto e célula.</Notice>}
    {rows.map(record => <Card key={record.id}><Badge text="Revisar" alert /><Text style={s.h2}>{record.descricao || 'Formulário'} · {record.codigo_text}</Text><Notice error>{record.parecer || (record.observacao_list ?? []).join('\n') || 'Revisão solicitada pela engenharia.'}</Notice><Button title="Abrir correção" disabled={!context.canEdit} onPress={() => router.push({ pathname: '/revisao-form', params: { registro: record.id, projeto: context.project.id, celula: context.cell.id } })} /></Card>)}
  </Screen>;
}

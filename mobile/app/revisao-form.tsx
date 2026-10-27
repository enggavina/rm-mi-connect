import { Text } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { FormScreen } from '../src/ui/form-screen';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, Card, Notice, Screen, s } from '../src/ui/components';
export default function Revisao() {
  const { registro } = useLocalSearchParams<{ registro?: string }>(); const app=useApp(); const records = useRows('rm_registros_formulario');
  if (registro) return <FormScreen recordId={registro} />;
  const rows = records.rows.filter(r => r.status === 'direcionado' && (app.operator?.perfil === 'administrador' || app.operator?.celulas_vinculadas.some(link => link.celula_id === r.celula_id)));
  return <Screen title="Revisões solicitadas" subtitle="Corrija as observações da engenharia e envie para nova análise.">{records.error && <Notice error>{records.error}</Notice>}{!rows.length && <Notice>Nenhum formulário em revisão no catálogo local.</Notice>}{rows.map(r => <Card key={r.id}><Badge text="Revisar" alert /><Text style={s.h2}>{r.descricao || 'Formulário'} · {r.codigo_text}</Text><Text style={s.body}>Projeto {r.numero_projeto_rm}</Text><Notice error>{r.parecer || (r.observacao_list ?? []).join('\n') || 'Revisão solicitada pela engenharia.'}</Notice><Button title="Abrir correção" onPress={() => router.push({ pathname:'/revisao-form', params:{ registro:r.id } })} /></Card>)}</Screen>;
}

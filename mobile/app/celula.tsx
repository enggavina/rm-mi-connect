import { Text, View, useWindowDimensions } from 'react-native';
import { router } from 'expo-router';
import { allowedCells, cellAllocations } from '../src/domain/journey';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, Card, Notice, Screen, s } from '../src/ui/components';

export default function Celula() {
  const { width } = useWindowDimensions();
  const app = useApp(); const cells = useRows('rm_celulas'); const projects = useRows('rm_projetos'); const allocations = useRows('rm_celulas_projeto');
  const available = allowedCells(app.operator, cells.rows);
  return <Screen title="Escolha sua célula" eyebrow="Operação" subtitle="Selecione onde você vai trabalhar para consultar os projetos alocados.">
    <View style={s.row}><Badge text={`${available.length} ${available.length === 1 ? 'célula disponível' : 'células disponíveis'}`} /><Text style={s.muted}>{app.operator?.nome}</Text></View>
    {(cells.error || allocations.error || projects.error) && <Notice error>{cells.error || allocations.error || projects.error}</Notice>}
    {!available.length && <Notice>Nenhuma célula está vinculada a este operador. Solicite o vínculo ao supervisor e sincronize novamente.</Notice>}
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 14 }}>{available.map(cell => { const count = cellAllocations(app.operator, cell.id, projects.rows, allocations.rows).length; return <Card key={cell.id} style={{ flexBasis: width >= 1000 ? '31%' : width >= 680 ? '47%' : '100%', flexGrow: 1, minHeight: 186 }}>
      {!!cell.codigo && <Text style={s.muted}>{cell.codigo}</Text>}<Text style={s.h2}>{cell.nome}</Text><Badge text={`${count} ${count === 1 ? 'projeto alocado' : 'projetos alocados'}`} />
      <Button title={`Entrar em ${cell.nome}`} onPress={() => router.push({ pathname: '/projetos', params: { celula: cell.id } })} />
    </Card>; })}</View>
  </Screen>;
}

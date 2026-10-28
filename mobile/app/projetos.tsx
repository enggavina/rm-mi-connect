import { useState } from 'react';
import { Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { canAccessCell, cellAllocations } from '../src/domain/journey';
import { label } from '../src/domain/forms';
import { useApp, useRows } from '../src/ui/state';
import { Badge, Button, Card, Field, Notice, Screen, Select, s } from '../src/ui/components';

export default function Projetos() {
  const { celula } = useLocalSearchParams<{ celula?: string }>(); const app = useApp();
  const cells = useRows('rm_celulas'); const projects = useRows('rm_projetos'); const allocations = useRows('rm_celulas_projeto'); const stages = useRows('rm_aprovacoes_etapas');
  const [search, setSearch] = useState(''); const [filter, setFilter] = useState('');
  const cell = cells.rows.find(c => c.id === celula); const allowed = canAccessCell(app.operator, celula);
  const allocated = cellAllocations(app.operator, celula, projects.rows, allocations.rows);
  const visible = allocated.filter(a => (!filter || (filter === 'waiting' ? stages.rows.some(stage => stage.projeto_id === a.projeto_id && stage.celula_origem_id === celula && stage.status === 'nulo') : a.status === filter)) && `${a.numero_projeto} ${a.cliente_nome_export} ${a.tipo_equipamento_nome_export}`.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()));
  return <Screen title="Projetos alocados" eyebrow={cell?.nome || 'Célula'} backHref="/celula" backLabel="Trocar célula" subtitle="Abra um projeto para acessar seus formulários e fotos.">
    {!allowed || !cell ? <><Notice error>{!allowed ? 'Escolha uma célula vinculada ao operador identificado.' : 'Esta célula ainda não está disponível no catálogo local. Sincronize novamente.'}</Notice><Button title="Escolher célula" onPress={() => router.replace('/celula')} /></> : <>
      <Badge text={`${allocated.length} ${allocated.length === 1 ? 'projeto alocado' : 'projetos alocados'}`} />
      <Field label="Buscar projeto / OS, cliente ou equipamento" value={search} onChangeText={setSearch} />
      <Select label="Status" value={filter} options={[{ value: '', label: 'Todos' }, ...['pendente', 'em_dia', 'atrasado', 'waiting', 'finalizado', 'retornado'].map(value => ({ value, label: value === 'waiting' ? 'Aguardando aprovação' : label(value) }))]} onChange={v => setFilter(v[0] ?? '')} />
      {(allocations.error || projects.error || cells.error) && <Notice error>{allocations.error || projects.error || cells.error}</Notice>}
      {!visible.length && <Notice>{allocated.length ? 'Nenhum projeto corresponde à busca e ao status selecionados.' : 'Nenhum projeto liberado para esta célula no catálogo local. Sincronize para receber as alocações do planejamento.'}</Notice>}
      {visible.map(a => <Card key={a.id}><View style={[s.row, { justifyContent: 'space-between' }]}><Text style={s.h2}>OS {a.numero_projeto}</Text><Badge text={label(a.status)} /></View><Text style={s.body}>{a.cliente_nome_export}</Text><Text style={s.muted}>{a.tipo_equipamento_nome_export || a.escopo_abreviado}</Text>{a.bloqueada === 'sim' && <Badge text="Execução bloqueada" alert />}{a.data_limite && <Badge text={`Prazo: ${new Date(a.data_limite).toLocaleDateString('pt-BR')}`} alert={Date.parse(a.data_limite) < Date.now() && a.status !== 'finalizado'} />}<Button title="Abrir projeto" onPress={() => router.push({ pathname: '/projeto', params: { celula: celula!, projeto: a.projeto_id } })} /></Card>)}
    </>}
  </Screen>;
}

import { useCallback, useRef, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import { service, type OutboxRow, type Row } from '../src/core';
import { canAccessCell, cellAllocations } from '../src/domain/journey';
import { projectQrContextCurrent, projectQrContextKey, readProjectQr, type ProjectQrContext } from '../src/domain/project-qr';
import { cellProjectLogs, cellProjectStages, cellStatusOptions, frontProjectPhoto, projectClientName } from '../src/domain/project-actions';
import { label } from '../src/domain/forms';
import { pageItems } from '../src/domain/pagination';
import { useApp, useRouteFocused, useRows } from '../src/ui/state';
import { useQueue } from '../src/ui/queue';
import { PageControls } from '../src/ui/pagination';
import { CellStatusAction } from '../src/ui/cell-status-action';
import { MediaImage, QrScanner } from '../src/ui/media';
import { Badge, Button, C, Card, Field, Notice, Screen, Select, s } from '../src/ui/components';

function ProjectCard({ allocation, project, clients, records, catalogsLoaded, stages, logs, users, queue, queueReady }: { allocation: Row; project?: Row; clients: Row[]; records: Row[]; catalogsLoaded: boolean; stages: Row[]; logs: Row[]; users: Row[]; queue: OutboxRow[]; queueReady: boolean }) {
  const [history, setHistory] = useState(false);
  const photos = useRows('rm_fotos', { field: 'projeto_id', value: allocation.projeto_id });
  const front = frontProjectPhoto(allocation.projeto_id, photos.rows); const ownStages = cellProjectStages(allocation, stages); const ownLogs = cellProjectLogs(allocation, logs);
  const number = project?.numero || allocation.numero_projeto; const title = number ? `OS ${number}` : 'Projeto em recebimento';
  const params = { celula: allocation.celula_id, projeto: allocation.projeto_id };
  const approved = ownStages.filter(stage => stage.status === 'aprovado').length;
  return <Card>
    <View style={[s.row, { justifyContent: 'space-between' }]}><Text style={s.h2}>{title}</Text><Pressable accessibilityRole="button" accessibilityLabel={`Comentários · ${title}`} onPress={() => router.push({ pathname: '/comentarios', params })} style={{ minHeight: 46, minWidth: 46, alignItems: 'center', justifyContent: 'center', borderRadius: 10, backgroundColor: C.soft }}><Feather name="message-square" size={22} color={C.primary} /></Pressable></View>
    <Text style={s.body}>{projectClientName(project, allocation, clients)}</Text><Text style={s.muted}>{project?.nome || allocation.tipo_equipamento_nome_export || allocation.escopo_abreviado}</Text>
    {front ? <View style={{ gap: 6 }}><MediaImage expand uri={front.foto_url} height={190} label={`Vista frontal · ${title}`} /><Text style={s.muted}>Toque na foto frontal para ampliar.</Text></View> : <Text style={s.muted}>{photos.loaded ? 'Foto frontal não disponível neste projeto.' : 'Carregando foto frontal…'}</Text>}
    {!!photos.error && <Notice error>{photos.error}</Notice>}
    <CellStatusAction allocation={allocation} queue={queue} ready={queueReady} records={records} photos={photos.rows} catalogsLoaded={catalogsLoaded && photos.loaded && !photos.error} />
    <View style={s.row}><Badge text={`${approved} ${approved === 1 ? 'etapa aprovada' : 'etapas aprovadas'}`} /><Badge text={`${ownLogs.length} ${ownLogs.length === 1 ? 'registro no histórico' : 'registros no histórico'}`} /></View>
    {!!ownLogs.length && <Button secondary title={history ? 'Recolher histórico de aprovações' : 'Consultar histórico de aprovações'} onPress={() => setHistory(!history)} />}
    {history && ownLogs.map(log => <View key={log.id} style={{ gap: 4, borderTopWidth: 1, borderColor: C.line, paddingTop: 10 }}><Text style={s.body}>{label(log.status_aprovacao)} · {users.find(user => user.id === log.aprovador_id)?.nome || 'Aprovador registrado'}</Text><Text style={s.muted}>{new Date(log.data_aprovacao || log.created_at).toLocaleString('pt-BR')}</Text></View>)}
    {allocation.bloqueada === 'sim' && <Badge text="Execução bloqueada" alert />}
    {allocation.data_limite && <Badge text={`Prazo: ${new Date(allocation.data_limite).toLocaleDateString('pt-BR')}`} alert={Date.parse(allocation.data_limite) < Date.now() && allocation.status !== 'finalizado'} />}
    <Button title="Abrir projeto" onPress={() => router.push({ pathname: '/projeto', params })} />
  </Card>;
}

export default function Projetos() {
  const { celula } = useLocalSearchParams<{ celula?: string }>(); const app = useApp();
  const focused = useRouteFocused(); const active = useRef(false); const currentCell = useRef(celula); currentCell.current = celula;
  useFocusEffect(useCallback(() => { active.current = true; return () => { active.current = false; }; }, []));
  const cells = useRows('rm_celulas'); const projects = useRows('rm_projetos'); const allocations = useRows('rm_celulas_projeto'); const stages = useRows('rm_aprovacoes_etapas');
  const clients = useRows('rm_clientes'); const logs = useRows('rm_logs_aprovacao'); const users = useRows('rm_users'); const queue = useQueue();
  const records = useRows('rm_registros_formulario', { field: 'celula_id', value: celula });
  const [search, setSearch] = useState(''); const [filter, setFilter] = useState(''); const [page, setPage] = useState(0);
  const [qrError, setQrError] = useState(''); const [qrBusy, setQrBusy] = useState(false); const qrReading = useRef(false);
  const [manualQr, setManualQr] = useState(false); const [qrValue, setQrValue] = useState('');
  const qrContext = (): ProjectQrContext => ({ ...service.getSnapshot(), cellId: currentCell.current, focused: active.current, catalogRevision: service.getCatalogRevision() });
  async function openQr(value: string) {
    if (qrReading.current || !active.current) return;
    qrReading.current = true; setQrBusy(true); setQrError('');
    try {
      const result = await readProjectQr(value, { context: qrContext, list: service.list });
      if (!active.current) return;
      if (!result.ok) { setQrError(result.reason); return; }
      if (!projectQrContextCurrent(result.contextKey, qrContext())) { setQrError('A célula, o operador ou o catálogo mudou. Leia o QR Code novamente.'); return; }
      setQrValue(''); setManualQr(false);
      router.push({ pathname: '/projeto', params: result.params });
    } finally { qrReading.current = false; setQrBusy(false); }
  }
  const scrollRef = useRef<ScrollView>(null);
  const changePage = (next: number) => { setPage(next); requestAnimationFrame(() => scrollRef.current?.scrollTo({ y: 0, animated: false })); };
  const cell = cells.rows.find(row => row.id === celula); const allowed = canAccessCell(app.operator, celula);
  const allocated = cellAllocations(app.operator, celula, projects.rows, allocations.rows);
  const visible = allocated.filter(allocation => {
    const project = projects.rows.find(row => row.id === allocation.projeto_id);
    return (!filter || (filter === 'waiting' ? cellProjectStages(allocation, stages.rows).some(stage => stage.status == null || stage.status === 'nulo') : allocation.status === filter))
      && `${project?.numero || allocation.numero_projeto} ${projectClientName(project, allocation, clients.rows)} ${project?.nome || ''} ${allocation.tipo_equipamento_nome_export || ''}`.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase());
  });
  const paged = pageItems(visible, page, 10);
  const error = allocations.error || projects.error || cells.error || clients.error || records.error || logs.error || queue.error;
  return <Screen scrollRef={scrollRef} title="Projetos alocados" eyebrow={cell?.nome || 'Célula'} backHref="/celula" backLabel="Trocar célula" subtitle="Abra um projeto ou consulte as atividades da célula.">
    {!allowed || !cell ? <><Notice error>{!allowed ? 'Escolha uma célula vinculada ao operador identificado.' : 'Esta célula ainda não está disponível no catálogo local. Sincronize novamente.'}</Notice><Button title="Escolher célula" onPress={() => router.replace('/celula')} /></> : <>
      <Badge text={`${allocated.length} ${allocated.length === 1 ? 'projeto alocado' : 'projetos alocados'}`} />
      <Card><Text style={s.h2}>Abrir pelo QR Code</Text><Text style={s.muted}>Leia a etiqueta EM para abrir um projeto desta célula. Sem conexão, o projeto precisa estar disponível no catálogo deste dispositivo.</Text>
        <QrScanner key={projectQrContextKey({ ...app, cellId: celula, focused, catalogRevision: service.getCatalogRevision() })} disabled={!focused || qrBusy || app.syncing} onRead={value => { void openQr(value); }} />
        <Button secondary disabled={qrBusy} title={manualQr ? 'Cancelar digitação do código' : 'Digitar código do projeto'} onPress={() => { setManualQr(!manualQr); setQrValue(''); setQrError(''); }} />
        {manualQr && <><Field label="Código do projeto (UUID)" value={qrValue} onChangeText={setQrValue} autoCapitalize="none" autoCorrect={false} placeholder="Cole o código exibido na etiqueta EM" editable={!qrBusy} /><Button title="Abrir pelo código" busy={qrBusy} disabled={!qrValue} onPress={() => { void openQr(qrValue); }} /></>}
        {!!qrError && <Notice error>{qrError}</Notice>}
      </Card>
      <Field label="Buscar projeto / OS, cliente ou equipamento" value={search} onChangeText={value => { setSearch(value); setPage(0); }} />
      <Select label="Status" value={filter} options={[{ value: '', label: 'Todos' }, ...cellStatusOptions, { value: 'waiting', label: 'Aguardando aprovação' }]} onChange={values => { setFilter(values[0] ?? ''); setPage(0); }} />
      {!!error && <Notice error>{error}</Notice>}
      {!visible.length && <Notice>{allocated.length ? 'Nenhum projeto corresponde à busca e ao status selecionados.' : 'Nenhum projeto liberado para esta célula no catálogo local. Sincronize para receber as alocações do planejamento.'}</Notice>}
      <PageControls page={paged.page} pages={paged.pages} onChange={changePage} />
      {paged.items.map(allocation => <ProjectCard key={allocation.id} allocation={allocation} project={projects.rows.find(project => project.id === allocation.projeto_id)} clients={clients.rows} records={records.rows} catalogsLoaded={allocations.loaded && records.loaded && !allocations.error && !records.error} stages={stages.rows} logs={logs.rows} users={users.rows} queue={queue.rows} queueReady={queue.ready} />)}
      <PageControls page={paged.page} pages={paged.pages} onChange={changePage} />
    </>}
  </Screen>;
}

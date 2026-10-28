import { useState } from 'react';
import { Text, View } from 'react-native';
import { router } from 'expo-router';
import { useRows } from './state';
import { Badge, Button, Card, Field, Notice, Screen, s } from './components';
import { label } from '../domain/forms';
import { assignedForms } from '../domain/journey';
import { MediaImage } from './media';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from './journey';

export function FormList({ peritagem = false, projectId, cellId }: { peritagem?: boolean; projectId?: string; cellId?: string }) {
  const { context, error } = useJourney(cellId, projectId);
  const forms = useRows('rm_forms'); const records = useRows('rm_registros_formulario'); const answers = useRows('rm_respostas');
  const [search, setSearch] = useState(''); const [expanded, setExpanded] = useState<string | null>(null);
  if (!context.ok) return <JourneyUnavailable context={context} error={error} title="Selecione um projeto" />;
  const matches = (text: string) => text.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase());
  const assigned = assignedForms(context.allocation, forms.rows).filter(form => !peritagem || form.tipo === 'peritagem');
  const ids = new Set(assigned.map(form => form.id));
  const available = assigned.filter(form => matches(`${form.titulo ?? ''} ${form.descricao ?? ''}`));
  const submitted = records.rows.filter(record => record.projeto_id === projectId && record.celula_id === cellId && ids.has(record.form_id) && matches(`${record.descricao ?? ''} ${record.numero_projeto_rm ?? ''} ${record.codigo_text ?? ''} ${forms.rows.find(form => form.id === record.form_id)?.titulo ?? ''}`))
    .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
  return <Screen title={peritagem ? 'Peritagem' : 'Formulários do projeto'} eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Modelos vinculados a este projeto e célula, com seus registros e revisões.">
    {!context.canEdit && <Notice error>{context.allocation.motivo_bloqueio || 'Execução bloqueada pelo planejamento. Os registros continuam disponíveis para consulta.'}</Notice>}
    <Field label="Buscar formulário ou registro" value={search} onChangeText={setSearch} />
    {(forms.error || records.error || answers.error) && <Notice error>{forms.error || records.error || answers.error}</Notice>}
    <Text style={s.h2}>Formulários vinculados</Text>
    {!available.length && <Notice>{assigned.length ? 'Nenhum formulário corresponde à busca.' : 'Nenhum formulário disponível neste vínculo de projeto e célula. Sincronize para receber as definições do planejamento.'}</Notice>}
    {available.map(form => <Card key={form.id}><Text style={s.h2}>{form.titulo}</Text>{!!form.descricao && <Text style={s.muted}>{form.descricao}</Text>}<View style={s.row}><Badge text={form.tipo === 'peritagem' ? 'Peritagem' : 'Inspeção'} />{!form.ativo && <Badge text="Modelo inativo" alert />}</View><Button title="Abrir preenchimento" disabled={!context.canEdit || !form.ativo} onPress={() => router.push({ pathname: '/registro-form', params: { projeto: context.project.id, celula: context.cell.id, form: form.id } })} /></Card>)}
    <Text style={s.h2}>Registros enviados</Text>
    {!submitted.length && <Notice>Nenhum registro encontrado para estes formulários no catálogo local.</Notice>}
    {submitted.map(record => <Card key={record.id}>
      <Badge text={label(record.status)} alert={record.status === 'direcionado'} /><Text style={s.h2}>{record.descricao || forms.rows.find(form => form.id === record.form_id)?.titulo || 'Formulário'}{record.codigo_text ? ` · ${record.codigo_text}` : ''}</Text>
      {record.status === 'direcionado' && <Button title="Corrigir revisão" disabled={!context.canEdit} onPress={() => router.push({ pathname: '/revisao-form', params: { registro: record.id, projeto: context.project.id, celula: context.cell.id } })} />}
      <Button secondary title={expanded === record.id ? 'Recolher respostas' : 'Consultar respostas'} onPress={() => setExpanded(expanded === record.id ? null : record.id)} />
      {expanded === record.id && !answers.rows.some(answer => answer.registro_formulario_id === record.id) && <Notice>As respostas deste registro ainda não estão disponíveis neste dispositivo.</Notice>}
      {expanded === record.id && answers.rows.filter(answer => answer.registro_formulario_id === record.id).sort((a, b) => a.indice - b.indice).map(answer => <Card key={answer.id}><Text style={s.body}>{answer.indice}. {answer.enunciado}</Text><Text style={s.muted}>{[answer.resposta, ...(answer.itens ?? []), answer.date_inicio, answer.data_fim, answer.hora].filter(Boolean).join(' · ') || '—'}</Text>{(answer.fotos_urls ?? []).filter(Boolean).map((uri: string, i: number) => <MediaImage key={i} uri={uri} />)}{answer.assinatura_url && <MediaImage uri={answer.assinatura_url} height={130} />}</Card>)}
    </Card>)}
  </Screen>;
}

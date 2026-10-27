import { useState } from 'react';
import { Platform, Pressable, Text, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import type { Answer, Row } from '../core';
import { Button, C, Card, Field, Notice, Select, s } from './components';
import { Photos, Signature } from './media';
import { emptyAnswer } from '../domain/forms';

function DateField({ label, value, mode = 'date', onChange, disabled }: { label: string; value?: string | null; mode?: 'date' | 'time'; onChange: (s: string) => void; disabled?: boolean }) {
  const [open, setOpen] = useState(false); const date = value && !Number.isNaN(Date.parse(value)) ? new Date(value) : new Date();
  return <View style={{ gap: 8 }}><Text style={s.muted}>{label}</Text><Button secondary disabled={disabled} title={value ? mode === 'date' ? date.toLocaleDateString('pt-BR') : date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : 'Selecionar'} onPress={() => setOpen(true)} />{open && <><DateTimePicker value={date} mode={mode} is24Hour locale="pt-BR" display={Platform.OS === 'ios' ? 'spinner' : 'default'} onChange={(event, next) => { if (Platform.OS !== 'ios') setOpen(false); if (event.type !== 'dismissed' && next) onChange(next.toISOString()); }} />{Platform.OS === 'ios' && <Button title="Concluir" onPress={() => setOpen(false)} />}</>}</View>;
}
export function Question({ q, answer, items, users, clients, onChange, disabled, error, onMediaBusy }: { q: Row; answer?: Answer; items: Row[]; users: Row[]; clients: Row[]; onChange: (a: Answer) => void; disabled?: boolean; error?: string; onMediaBusy?: (busy:boolean) => void }) {
  const a = answer ?? emptyAnswer(q); const update = (patch: Partial<Answer>) => onChange({ ...a, ...patch, is_na: false });
  if (q.tipo === 'subt_tulo') return <View style={{ borderLeftWidth: 4, borderColor: C.primary, padding: 16, gap: 6 }}><Text style={s.h2}>{q.enunciado}</Text>{q.subtitulo && <Text style={s.body}>{q.subtitulo}</Text>}</View>;
  const options = items.filter(i => i.questao_id === q.id).sort((a,b) => a.indice - b.indice).map(i => ({ value: i.id, label: i.descricao }));
  const selectedIds = a.itens_questoes_ids?.length ? a.itens_questoes_ids : options.filter(o => o.label === a.resposta || a.itens?.includes(o.label)).map(o => o.value);
  function selected(ids: string[]) { update({ itens_questoes_ids: ids, itens: options.filter(i => ids.includes(i.value)).map(i => i.label), resposta: ['lista_suspensa', 'escolha__nica'].includes(q.tipo) ? options.find(i => i.value === ids[0])?.label ?? '' : null }); }
  let input;
  switch (q.tipo) {
    case 'texto_curto': case 'texto_longo': case 'numero': input = <Field label={q.dimensoes ? `Resposta · ${String(q.dimensoes).replace(/_/g, ' ')}` : 'Resposta'} value={a.resposta ?? ''} editable={!disabled} multiline={q.tipo === 'texto_longo'} keyboardType={q.tipo === 'numero' ? 'decimal-pad' : 'default'} onChangeText={resposta => update({ resposta })} />; break;
    case 'data': case 'hora': {
      const interval = ['intervalo_de_datas','intervalo_de_hor_rios'].includes(q.subtipo);
      const mode = q.tipo === 'hora' ? 'time' : 'date';
      input = <View style={{ gap: 12 }}><DateField label={interval ? 'Início' : q.tipo === 'hora' ? 'Hora' : 'Data'} value={interval || q.tipo === 'data' ? a.date_inicio : a.hora} mode={mode} disabled={disabled} onChange={v => update(q.tipo === 'hora' ? {hora:v,...(interval ? {date_inicio:v} : {})} : {date_inicio:v})} />{interval && <DateField label="Fim" value={a.data_fim} mode={mode} disabled={disabled} onChange={data_fim => update({ data_fim })} />}</View>; break;
    }
    case 'lista_suspensa': case 'lista_multi_sele__o': input = <Select label="Opções" options={options} value={selectedIds} multiple={q.tipo === 'lista_multi_sele__o'} disabled={disabled} onChange={selected} />; break;
    case 'escolha__nica': case 'caixas_de_sele__o': input = <View style={{ gap: 8 }}>{options.map(item => { const checked = selectedIds.includes(item.value); return <Pressable key={item.value} disabled={disabled} accessibilityRole={q.tipo === 'escolha__nica' ? 'radio' : 'checkbox'} accessibilityState={{ checked: !!checked, disabled }} onPress={() => selected(q.tipo === 'escolha__nica' ? [item.value] : checked ? selectedIds.filter(i => i !== item.value) : [...selectedIds,item.value])} style={{ padding: 16, minHeight: 54, borderRadius: 10, borderWidth: 1, borderColor: checked ? C.primary : C.line, backgroundColor: checked ? C.pale : C.white }}><Text style={s.body}>{checked ? '●' : '○'}  {item.label}</Text></Pressable>; })}{!options.length && <Notice error>Esta questão não possui opções no catálogo sincronizado.</Notice>}</View>; break;
    case 'foto': case 'foto_antes_depois': input = <Photos values={a.fotos_urls ?? []} onChange={fotos_urls => update({ fotos_urls })} beforeAfter={q.tipo === 'foto_antes_depois'} disabled={disabled} onBusyChange={onMediaBusy} />; break;
    case 'assinatura': input = <Signature value={a.assinatura_url} onChange={assinatura_url => update({ assinatura_url })} disabled={disabled} />; break;
    case 'colaborador': case 'cliente': {
      const list = q.tipo === 'cliente' ? clients : users.filter(u => u.status === 'ativo' && (!q.colaborador_filtro_perfil || u.perfil === q.colaborador_filtro_perfil));
      input = <Select label={q.tipo === 'cliente' ? 'Cliente' : 'Colaborador'} value={a.resposta ?? ''} options={list.map(r => ({ value: r.nome, label: r.nome }))} onChange={ids => update({ resposta: ids[0] })} disabled={disabled} />; break;
    }
    default: input = <Notice error>Tipo de questão desconhecido: {q.tipo}. Atualize o aplicativo antes de enviar este formulário.</Notice>;
  }
  return <Card><View style={s.row}><Text style={[s.h2, { flex: 1 }]}>{q.indice}. {q.enunciado}{q.obrigatorio ? ' *' : ''}</Text></View>{q.subtitulo && <Text style={s.muted}>{q.subtitulo}</Text>}{a.is_na ? <><Notice>Não se aplica (N/A)</Notice>{!disabled && <Button secondary title="Preencher esta questão" onPress={() => onChange(emptyAnswer(q))} />}</> : input}{!!error && <Notice error>{error}</Notice>}</Card>;
}

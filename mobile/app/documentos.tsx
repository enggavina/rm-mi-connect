import { useState } from 'react';
import { Text } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import type { Row } from '../src/core';
import { useRows } from '../src/ui/state';
import { Badge, Card, Field, Notice, Screen, s } from '../src/ui/components';
import { DocumentLink } from '../src/ui/documents';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';
import { label } from '../src/domain/forms';

export default function Documentos() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>(); const { context, error } = useJourney(celula, projeto);
  const attachments = useRows('rm_docs'); const reports = useRows('rm_documentos'); const [search, setSearch] = useState('');
  if (!context.ok) return <JourneyUnavailable context={context} error={error} />;
  const p = context.project; const special: Row[] = [];
  if (p.arquivo_nota_fiscal_url) special.push({ id: `invoice:${p.id}`, nome: `Nota fiscal${p.nota_fiscal ? ` ${p.nota_fiscal}` : ''}`, arquivo_url: p.arquivo_nota_fiscal_url, tipo_documento: 'Nota fiscal' });
  if (p.documento_proposta_url) special.push({ id: `proposal:${p.id}`, nome: 'Proposta', arquivo_url: p.documento_proposta_url, tipo_documento: 'Proposta' });
  const seen = new Set<string>();
  const all = [...special, ...attachments.rows.filter(row => row.projeto_id === projeto), ...reports.rows.filter(row => row.projeto_id === projeto)].filter(row => { const key = row.arquivo_url || row.id; if (seen.has(key)) return false; seen.add(key); return true; });
  const visible = all.filter(row => `${row.nome} ${row.descricao || ''} ${row.tipo_documento || ''}`.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()));
  return <Screen title="Documentos do projeto" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Anexos, nota fiscal e relatórios vinculados ao projeto.">
    {(attachments.error || reports.error) && <Notice error>{attachments.error || reports.error}</Notice>}
    <Field label="Buscar documento" value={search} onChangeText={setSearch} /><Badge text={`${visible.length} documentos`} />
    {!visible.length && <Notice>{all.length ? 'Nenhum documento corresponde à busca.' : 'Nenhum documento cadastrado neste projeto.'}</Notice>}
    {visible.map(row => <Card key={row.id}><Text style={s.h2}>{row.nome || 'Documento'}</Text>{!!row.tipo_documento && <Badge text={row.tipo_documento} />}{!!row.status && <Badge text={label(row.status)} />}{!!row.descricao && <Text style={s.body}>{row.descricao}</Text>}{!!row.data_vencimento && <Text style={s.muted}>Validade: {new Date(row.data_vencimento).toLocaleDateString('pt-BR')}</Text>}
      {row.arquivo_url ? <DocumentLink uri={row.arquivo_url} /> : <Notice>O documento está cadastrado, mas não há um link de arquivo disponível para abrir.</Notice>}
    </Card>)}
  </Screen>;
}

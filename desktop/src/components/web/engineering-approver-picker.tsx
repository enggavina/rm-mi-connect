'use client';

import { useId, useState } from 'react';
import type { WebRow } from '@/server/web/data';
import s from './engineering.module.css';

export function EngineeringApproverPicker({ label, options, all, selected, onChange, destinationPending = false }: {
  label: string; options: WebRow[]; all: WebRow[]; selected: string[];
  onChange: (ids: string[]) => void; destinationPending?: boolean;
}) {
  const [query, setQuery] = useState(''), [candidate, setCandidate] = useState('');
  const searchId = useId(), selectId = useId();
  const available = new Set(options.map(row => row.id));
  const selectedSet = new Set(selected);
  const personLabel = (row: WebRow) => `${row.nome || 'Referência não disponível'}${row.matricula ? ` · matrícula ${row.matricula}` : ''}`;
  const filter = query.trim().toLocaleLowerCase();
  const candidates = options.filter(row => !selectedSet.has(row.id) && personLabel(row).toLocaleLowerCase().includes(filter));
  const chosen = candidates.some(row => row.id === candidate) ? candidate : '';
  return <fieldset className={s.approvers}>
    <legend>{label}</legend>
    <p className={s.muted}>Selecione identidades ativas vinculadas à célula. Inclua de 1 a 100 aprovadores.</p>
    {selected.length ? <ul className={s.approverList} aria-label={`Selecionados: ${label}`}>
      {selected.map((id, index) => { const row = all.find(person => person.id === id) ?? { id, nome: 'Referência não disponível' }; const name = personLabel(row);
        return <li key={`${id}-${index}`}><span>{name}{!available.has(id) && <small>Sem vínculo elegível nesta célula. Remova para reconfigurar.</small>}</span>
          <button type="button" className="button small secondary" aria-label={`Remover ${name} de ${label}`} onClick={() => onChange(selected.filter(value => value !== id))}>Remover</button></li>;
      })}
    </ul> : <p className={s.muted}>Nenhum aprovador selecionado.</p>}
    <div className="field"><label htmlFor={searchId}>Filtrar por nome ou matrícula</label><input id={searchId} type="search" value={query} onChange={event => { setQuery(event.target.value); setCandidate(''); }} disabled={destinationPending} /></div>
    <div className="field"><label htmlFor={selectId}>Selecionar aprovador</label><select id={selectId} value={chosen} onChange={event => setCandidate(event.target.value)} disabled={destinationPending || selected.length >= 100}>
      <option value="">{destinationPending ? 'Escolha a célula de destino primeiro' : candidates.length ? 'Selecione uma pessoa' : 'Nenhum aprovador disponível'}</option>
      {candidates.map(row => <option key={row.id} value={row.id}>{personLabel(row)}</option>)}
    </select></div>
    <button type="button" className="button small secondary" aria-label={`Adicionar aprovador: ${label}`} disabled={!chosen || selected.length >= 100}
      onClick={() => { if (chosen && !selectedSet.has(chosen)) onChange([...selected, chosen]); setCandidate(''); }}>Adicionar aprovador</button>
  </fieldset>;
}

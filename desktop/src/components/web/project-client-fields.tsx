'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { createProjectClientMatcher, type ProjectClientChoice } from './project-client-match';

export const projectClientMatchDelay = 400;
export function ProjectClientFields({ clients, initialName = '', initialClientId = '', autoFill = true, disabled = false }: {
  clients: ProjectClientChoice[]; initialName?: string; initialClientId?: string; autoFill?: boolean; disabled?: boolean;
}) {
  const [name, setName] = useState(initialName), [clientId, setClientId] = useState(initialClientId);
  const [notice, setNotice] = useState('');
  const manual = useRef(false), selected = useRef(initialClientId);
  const matchClient = useMemo(() => createProjectClientMatcher(clients), [clients]);
  useEffect(() => {
    if (!autoFill || disabled || manual.current || clientId) return;
    const timer = setTimeout(() => {
      if (manual.current || selected.current) return;
      const match = matchClient(name);
      if (match.kind === 'match') {
        selected.current = match.client.id; setClientId(match.client.id);
        setNotice('Cliente preenchido pelo nome do projeto. Confira antes de salvar.');
      } else setNotice(match.kind === 'ambiguous' ? 'Mais de um cliente corresponde ao nome do projeto. Selecione o cliente.' : '');
    }, projectClientMatchDelay);
    return () => clearTimeout(timer);
  }, [name, clientId, autoFill, disabled, matchClient]);
  return <>
    <div className="field"><label htmlFor="nome">Nome do projeto</label><input id="nome" name="nome" value={name} onChange={event => setName(event.target.value)} maxLength={500} placeholder="Identificação do projeto" /></div>
    <div className="field"><label htmlFor="cliente_id">Cliente</label><select id="cliente_id" name="cliente_id" value={clientId} aria-describedby={notice ? 'project-client-notice' : undefined} onChange={event => {
      manual.current = true; selected.current = event.target.value; setClientId(event.target.value); setNotice('');
    }}><option value="">Selecione o cliente</option>{clientId && !clients.some(client => client.id === clientId) && <option value={clientId}>Cliente atual indisponível</option>}{clients.map(client => <option key={client.id} value={client.id}>{client.nome || 'Cliente sem nome'}</option>)}</select>
      <p className="form-note" id="project-client-notice" role="status" aria-live="polite">{notice}</p>
    </div>
  </>;
}

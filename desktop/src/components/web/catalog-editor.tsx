'use client';
import { useEffect, useRef, useState } from 'react';
import { deleteCatalog, saveCatalog } from '@/server/web/catalog-actions';
import type { EditableCatalogKind, SaveCatalogInput } from '@/server/web/catalog-policy';
import type { WebRow } from '@/server/web/data';
import { catalogFailureState, catalogLabels, confirmsCatalogDeletion, freezeCatalogAttempt, readCatalogForm, type CatalogAttempt, type CatalogFields } from './catalog-model';
import { Icon } from './icons';

export function CatalogEditor({ kind, entry }: { kind: EditableCatalogKind; entry?: WebRow }) {
  const label = catalogLabels[kind], back = `/cadastros?kind=${kind}`;
  const [id] = useState(() => entry?.id || crypto.randomUUID());
  const [busy, setBusy] = useState(false), [uncertain, setUncertain] = useState(false), [stale, setStale] = useState(false);
  const [error, setError] = useState(''), [fieldErrors, setFieldErrors] = useState<CatalogFields>({});
  const [deleting, setDeleting] = useState(false), [confirmation, setConfirmation] = useState('');
  const [unauthorized, setUnauthorized] = useState(false);
  const inFlight = useRef(false), attempt = useRef<CatalogAttempt | null>(null), errorBox = useRef<HTMLDivElement>(null);
  useEffect(() => { if (error) errorBox.current?.focus(); }, [error]);
  useEffect(() => {
    if (!busy && !uncertain) return;
    const preventLoss = (event: BeforeUnloadEvent) => { if (attempt.current) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', preventLoss);
    return () => window.removeEventListener('beforeunload', preventLoss);
  }, [busy, uncertain]);

  async function send(value: CatalogAttempt) {
    if (inFlight.current || stale || (attempt.current && attempt.current.action !== value.action)) return;
    inFlight.current = true; setBusy(true); setError(''); setFieldErrors({}); setUnauthorized(false);
    attempt.current ??= freezeCatalogAttempt(value);
    try {
      const current = attempt.current;
      const result = await (current.action === 'save' ? saveCatalog(current.payload) : deleteCatalog(current.payload));
      if (result.ok) {
        attempt.current = null; setUncertain(false);
        // Remove the navigation guard only after the server confirmed the operation.
        setBusy(false);
        setTimeout(() => window.location.assign(`${back}&resultado=${current.action === 'save' ? 'salvo' : 'excluido'}`), 0);
      } else {
        const state = catalogFailureState(result); setError(result.error); setUncertain(state.uncertain); setStale(state.stale); setUnauthorized(state.unauthorized);
        const fields: CatalogFields = {};
        for (const [key, messages] of Object.entries(result.fieldErrors ?? {})) {
          if (messages?.length) fields[key.replace(/^changes\./, '')] = messages.join(' ');
        }
        setFieldErrors(fields);
        if (!state.uncertain) attempt.current = null;
      }
    } catch {
      setUncertain(true); setError('A conexão foi interrompida. Tente confirmar novamente; o mesmo envio será usado para evitar duplicação.');
    } finally { inFlight.current = false; setBusy(false); }
  }
  function save(form: HTMLFormElement) {
    if (attempt.current) { void send(attempt.current); return; }
    const parsed = readCatalogForm(kind, new FormData(form));
    setFieldErrors(parsed.errors);
    if (Object.keys(parsed.errors).length) { setError('Confira os campos destacados.'); return; }
    if (entry && typeof entry.updated_at !== 'string') { setStale(true); setError('Não foi possível confirmar a versão deste cadastro. Recarregue os dados.'); return; }
    const payload = { kind, id, expected_updated_at: entry?.updated_at ?? null, changes: parsed.changes, submissionId: crypto.randomUUID() } as SaveCatalogInput;
    void send({ action: 'save', payload });
  }
  function remove() {
    if (attempt.current) { void send(attempt.current); return; }
    if (!entry || !confirmsCatalogDeletion(entry.nome, confirmation) || typeof entry.updated_at !== 'string') return;
    void send({ action: 'delete', payload: { kind, id, expected_updated_at: entry.updated_at, submissionId: crypto.randomUUID() } });
  }
  const locked = busy || uncertain || stale || unauthorized;
  const inputError = (name: string) => ({ 'aria-invalid': !!fieldErrors[name], 'aria-describedby': fieldErrors[name] ? `${name}-error` : undefined });
  const message = (name: string) => fieldErrors[name] ? <span id={`${name}-error`} style={{ color: '#a12e39', fontWeight: 400 }}>{fieldErrors[name]}</span> : null;
  return <>
    {error && <div ref={errorBox} tabIndex={-1} role="alert" className="notice error">{error}{fieldErrors.changes && <p>{fieldErrors.changes}</p>}</div>}
    {uncertain && <div className="notice">Os dados deste envio estão preservados até a confirmação. Use “Tentar confirmar envio” antes de iniciar outra alteração.</div>}
    {stale && <div className="notice">O cadastro mudou ou deixou de estar disponível. Recarregue os dados antes de editar novamente. <a href={`/cadastros/${kind}/${id}/editar`} className="text-link">Recarregar cadastro</a></div>}
    {unauthorized && <div className="notice">Sua autorização precisa ser verificada novamente. <a href="/login" className="text-link">Voltar ao acesso</a></div>}
    <form onSubmit={event => { event.preventDefault(); if (!deleting) save(event.currentTarget); }}>
      <fieldset disabled={locked || deleting} style={{ margin: 0, padding: 0, border: 0 }}>
        <div className="form-grid">
          <div className="field span-all"><label htmlFor="nome">Nome *</label><input id="nome" name="nome" defaultValue={entry?.nome ?? ''} required maxLength={200} autoComplete="off" {...inputError('nome')} />{message('nome')}</div>
          {kind !== 'types' && <div className="field"><label htmlFor="codigo">Código</label><input id="codigo" name="codigo" defaultValue={entry?.codigo ?? ''} maxLength={80} autoComplete="off" {...inputError('codigo')} />{message('codigo')}</div>}
          {kind === 'types' && <div className="field"><label htmlFor="sigla">Sigla</label><input id="sigla" name="sigla" defaultValue={entry?.sigla ?? ''} maxLength={30} autoComplete="off" {...inputError('sigla')} />{message('sigla')}</div>}
          {kind === 'clients' && <div className="field span-all"><label htmlFor="descricao">Descrição</label><textarea id="descricao" name="descricao" defaultValue={entry?.descricao ?? ''} maxLength={4000} {...inputError('descricao')} />{message('descricao')}</div>}
          {kind === 'cells' && <div className="field"><label htmlFor="ordem">Ordem de exibição</label><input id="ordem" name="ordem" type="number" min={0} max={1_000_000} step={1} defaultValue={entry?.ordem ?? ''} {...inputError('ordem')} />{!entry && <span className="form-note">Deixe vazio para adicionar a nova célula ao final.</span>}{message('ordem')}</div>}
        </div>
      </fieldset>
      <div className="form-actions"><span className="form-note">* Campo obrigatório</span><button type="button" className="button secondary" disabled={busy || uncertain} onClick={() => window.location.assign(back)}>Cancelar</button>
        {!deleting && <button className="button" disabled={busy || stale || unauthorized}>{busy ? 'Salvando…' : uncertain ? 'Tentar confirmar envio' : <><Icon name="check" size={16} />Salvar {label.singular}</>}</button>}
      </div>
    </form>
    {entry && <section aria-labelledby="delete-catalog-title" style={{ marginTop: 36, paddingTop: 24, borderTop: '1px solid var(--line)' }}>
      <h2 id="delete-catalog-title" style={{ fontSize: 14 }}>Excluir {label.singular}</h2>
      <p className="form-note">A exclusão é permanente. Cadastros em uso por outros registros não podem ser excluídos.</p>
      {!deleting ? <button type="button" className="button secondary" disabled={locked} onClick={() => { setDeleting(true); setConfirmation(''); setError(''); }}>Excluir {label.singular}</button> : <form onSubmit={event => { event.preventDefault(); remove(); }} style={{ marginTop: 16 }}>
        <p className="notice">Você está excluindo <strong>{entry.nome}</strong>. Confira o nome antes de continuar.</p>
        <div className="field"><label htmlFor="confirm-delete">Digite “{entry.nome}” para confirmar</label><input id="confirm-delete" value={confirmation} onChange={event => setConfirmation(event.target.value)} required autoComplete="off" disabled={locked} /></div>
        <div className="form-actions"><button type="button" className="button secondary" disabled={busy || uncertain} onClick={() => { setDeleting(false); setConfirmation(''); setError(''); }}>Manter cadastro</button>
          <button type="submit" className="button" disabled={busy || stale || unauthorized || (!uncertain && !confirmsCatalogDeletion(entry.nome, confirmation))}>{busy ? 'Excluindo…' : uncertain ? 'Tentar confirmar envio' : 'Confirmar exclusão'}</button></div>
      </form>}
    </section>}
  </>;
}

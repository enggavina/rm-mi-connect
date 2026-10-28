import { useEffect, useRef, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { service, type RpcName } from '../core';
import { useApp } from './state';

interface ActionDraft<T> { id: string; values: T; submitted?: boolean }
export function useActionDraft<T extends object>(scope: string, initial: T) {
  const app = useApp(); const actorId = app.operator?.operador_id; const key = `action:${actorId}:${scope}`;
  const activeKey = useRef(key); activeKey.current = key;
  const [draft, setDraft] = useState<ActionDraft<T> | null>(null); const current = useRef<ActionDraft<T> | null>(null);
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [saving, setSaving] = useState(0);
  const pending = useRef(Promise.resolve()); const saveError = useRef(''); const sending = useRef(false);
  const fresh = (): ActionDraft<T> => ({ id: Crypto.randomUUID(), values: { ...initial } });
  useEffect(() => {
    let live = true; current.current = null; setDraft(null); setError(''); saveError.current = '';
    service.getLocal<ActionDraft<T>>(key).then(async saved => {
      const operation = saved ? await service.operation(saved.id) : null;
      if (!live) return; const value = saved ? { ...saved, submitted: saved.submitted || !!operation } : fresh(); current.current = value; setDraft(value);
    }).catch(e => { if (live) setError(e.message); });
    return () => { live = false; };
  }, [key]);
  function persist(next: ActionDraft<T>) {
    current.current = next; setDraft(next); setSaving(count => count + 1);
    const write = service.saveLocal(key, next).then(() => { if (activeKey.current === key) saveError.current = ''; }).catch(e => { if (activeKey.current === key) { saveError.current = e.message; setError(e.message); } }).finally(() => setSaving(count => Math.max(0, count - 1)));
    pending.current = Promise.all([pending.current, write]).then(() => undefined);
  }
  function update(patch: Partial<T>) { if (current.current && !current.current.submitted && !sending.current) persist({ ...current.current, values: { ...current.current.values, ...patch } }); }
  async function submit(rpc: RpcName, build: (values: T) => Record<string, unknown>): Promise<string | null> {
    if (sending.current || !current.current) return null;
    if (current.current.submitted) return current.current.id;
    const value = current.current;
    sending.current = true; setBusy(true); setError('');
    try {
      await pending.current; if (saveError.current) throw new Error(saveError.current);
      const params = build(value.values);
      await service.saveLocal(key, value);
      if (activeKey.current !== key || service.getSnapshot().operator?.operador_id !== actorId) throw new Error('O contexto ou operador mudou. Seu rascunho foi preservado; identifique o autor para enviar.');
      await service.enqueue(rpc, params, value.id);
      const sent = { ...value, submitted: true }; if (activeKey.current === key) { current.current = sent; setDraft(sent); } await service.saveLocal(key, sent);
      return sent.id;
    } catch (e) { setError(e instanceof Error ? e.message : 'Não foi possível registrar esta ação.'); return null; }
    finally { sending.current = false; setBusy(false); }
  }
  function startAnother() { if (current.current?.submitted && !sending.current) { persist(fresh()); setError(''); } }
  return { draft, update, submit, startAnother, error, busy, saving };
}

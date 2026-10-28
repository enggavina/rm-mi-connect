import { useEffect, useState, useSyncExternalStore } from 'react';
import { service, type CatalogFilterField, type Row } from '../core';
export function useApp() { return useSyncExternalStore(service.subscribe, service.getSnapshot, service.getSnapshot); }
export function useRows(table: string, where?: { field: CatalogFilterField; value?: string }) {
  const { revision, ready } = useApp();
  const [rows, setRows] = useState<Row[]>([]);
  const [error, setError] = useState('');
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    let live = true; setLoaded(false);
    if (where && !where.value) { setRows([]); setError(''); setLoaded(true); return; }
    if (ready) service.list(table, where ? { field: where.field, value: where.value! } : undefined).then(r => { if (live) { setRows(r); setError(''); setLoaded(true); } }).catch(e => { if (live) setError(String(e.message ?? e)); });
    return () => { live = false; };
  }, [table, revision, ready, where?.field, where?.value]);
  return { rows, error, loaded };
}

import { useEffect, useState, useSyncExternalStore } from 'react';
import { service, type Row } from '../core';
export function useApp() { return useSyncExternalStore(service.subscribe, service.getSnapshot, service.getSnapshot); }
export function useRows(table: string) {
  const { revision, ready } = useApp();
  const [rows, setRows] = useState<Row[]>([]);
  const [error, setError] = useState('');
  useEffect(() => { let live = true; if (ready) service.list(table).then(r => { if (live) { setRows(r); setError(''); } }).catch(e => { if (live) setError(String(e.message ?? e)); }); return () => { live = false; }; }, [table, revision, ready]);
  return { rows, error };
}

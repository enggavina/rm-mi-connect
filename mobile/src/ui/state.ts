import { useCallback, useEffect, useState, useSyncExternalStore } from 'react';
import { useFocusEffect } from 'expo-router';
import { service, type CatalogFilterField, type Row } from '../core';
import { SharedReadCache } from '../core/read-cache';
const reads = new SharedReadCache<Row>();
const noSubscribe = () => () => {};
export function useApp() { return useSyncExternalStore(service.subscribe, service.getSnapshot, service.getSnapshot); }
export function useRouteFocused() {
  const [focused, setFocused] = useState(false);
  useFocusEffect(useCallback(() => { setFocused(true); return () => setFocused(false); }, []));
  return focused;
}
export function useRows(table: string, where?: { field: CatalogFilterField; value?: string }) {
  const focused = useRouteFocused();
  const revision = useSyncExternalStore(focused ? service.subscribe : noSubscribe, service.getCatalogRevision, service.getCatalogRevision);
  const [rows, setRows] = useState<Row[]>([]);
  const [error, setError] = useState('');
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    let live = true;
    if (!focused) return;
    setLoaded(false);
    if (where && !where.value) { setRows([]); setError(''); setLoaded(true); return; }
    const filter = where ? { field: where.field, value: where.value! } : undefined;
    if (revision >= 0) reads.read(JSON.stringify([table, filter?.field, filter?.value]), revision, () => service.list(table, filter)).then(r => { if (live) { setRows(r); setError(''); setLoaded(true); } }).catch(e => { if (live) setError(String(e.message ?? e)); });
    return () => { live = false; };
  }, [table, revision, focused, where?.field, where?.value]);
  return { rows, error, loaded };
}

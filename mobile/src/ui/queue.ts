import { useEffect, useState } from 'react';
import { service, type OutboxRow } from '../core';
import { useApp, useRouteFocused } from './state';

export function useQueue() {
  const app = useApp(); const focused = useRouteFocused(); const [rows, setRows] = useState<OutboxRow[]>([]); const [ready, setReady] = useState(false); const [error, setError] = useState('');
  useEffect(() => { let live = true; if (focused && app.ready) service.listQueue().then(queue => { if (live) { setRows(queue); setReady(true); setError(''); } }).catch(e => { if (live) { setError(e.message); setReady(false); } }); return () => { live = false; }; }, [focused, app.ready, app.revision]);
  return { rows, ready, error };
}

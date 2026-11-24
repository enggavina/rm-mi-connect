'use client';

import { useEffect } from 'react';

export function OperationHistory() {
  useEffect(() => {
    // A restored history page must confirm the current office and operator again.
    const hide = (event: PageTransitionEvent) => {
      if (event.persisted) document.documentElement.dataset.operationRevalidate = 'true';
    };
    const reload = (event: PageTransitionEvent) => {
      if (event.persisted) window.location.reload();
    };
    window.addEventListener('pagehide', hide);
    window.addEventListener('pageshow', reload);
    return () => {
      delete document.documentElement.dataset.operationRevalidate;
      window.removeEventListener('pagehide', hide);
      window.removeEventListener('pageshow', reload);
    };
  }, []);
  return null;
}

'use client';
export default function PortalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <div className="empty-state"><h1>Não foi possível carregar esta área</h1><p>Confira sua conexão e tente novamente. Seus dados continuam no banco.</p><button className="button" onClick={reset}>Tentar novamente</button></div>;
}

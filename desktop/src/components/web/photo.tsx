'use client';
import { useEffect, useRef, useState } from 'react';
import { Icon } from './icons';
export function Photo({ url, title }: { url: string; title: string }) {
  const [open, setOpen] = useState(false); const [failed, setFailed] = useState(false); const close = useRef<HTMLButtonElement>(null); const trigger = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!open) return; const previous = document.body.style.overflow; document.body.style.overflow = 'hidden'; close.current?.focus();
    const keydown = (event: KeyboardEvent) => { if (event.key === 'Escape') setOpen(false); if (event.key === 'Tab') { event.preventDefault(); close.current?.focus(); } };
    document.addEventListener('keydown', keydown); return () => { document.body.style.overflow = previous; document.removeEventListener('keydown', keydown); trigger.current?.focus(); };
  }, [open]);
  const safe = (() => { try { const parsed = new URL(url); return parsed.protocol === 'https:' && !parsed.username && !parsed.password; } catch { return false; } })();
  if (!safe || failed) return <div className="photo-preview"><span className="form-note">Prévia indisponível</span></div>;
  return <><button type="button" ref={trigger} className="photo-preview" aria-label={`Ampliar ${title}`} onClick={() => setOpen(true)}><img src={url} alt={title} loading="lazy" referrerPolicy="no-referrer" onError={() => setFailed(true)} /></button>{open && <div className="dialog-backdrop" onClick={event => { if (event.target === event.currentTarget) setOpen(false); }}><section role="dialog" aria-modal="true" aria-label={title} className="image-dialog"><div className="dialog-header"><h2>{title}</h2><button type="button" ref={close} className="icon-button" aria-label="Fechar foto" onClick={() => setOpen(false)}><Icon name="close" size={24} /></button></div><div className="dialog-image"><img src={url} alt={title} referrerPolicy="no-referrer" /></div></section></div>}</>;
}

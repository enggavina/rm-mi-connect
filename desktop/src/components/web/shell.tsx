'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Icon } from './icons';
import type { CorporateCapability } from '@/server/web/sso-policy';
import { activePortalItem, portalNavigation, portalShortcuts } from './navigation';
import s from './home-modules.module.css';
export function PortalShell({ profile, capabilities, children }: { profile: { nome: string; perfil: string; cargo?: string | null }; capabilities?: CorporateCapability[]; children: React.ReactNode }) {
  const path = usePathname(); const [open, setOpen] = useState(false);
  const groups = portalNavigation(capabilities);
  const shortcuts = portalShortcuts(capabilities);
  const current = activePortalItem(path, groups.flatMap(group => group.items));
  const sidebar = useRef<HTMLElement>(null), toggle = useRef<HTMLButtonElement>(null);
  const closeNavigation = useCallback(() => { setOpen(false); requestAnimationFrame(() => toggle.current?.focus()); }, []);
  useEffect(() => {
    if (!open) return;
    const previousOverflow = document.body.style.overflow; document.body.style.overflow = 'hidden';
    sidebar.current?.querySelector<HTMLElement>('nav a[href]')?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); closeNavigation(); return; }
      if (event.key !== 'Tab') return;
      const controls = [...(sidebar.current?.querySelectorAll<HTMLElement>('a[href],button:not(:disabled)') ?? [])].filter(element => element.getClientRects().length > 0);
      const first = controls[0], last = controls.at(-1); if (!first || !last) return;
      if (event.shiftKey && (document.activeElement === first || !sidebar.current?.contains(document.activeElement))) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || !sidebar.current?.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
    };
    const desktop = window.matchMedia('(min-width: 651px)'), resized = () => { if (desktop.matches) setOpen(false); };
    window.addEventListener('keydown', keydown); desktop.addEventListener('change', resized);
    return () => { document.body.style.overflow = previousOverflow; window.removeEventListener('keydown', keydown); desktop.removeEventListener('change', resized); };
  }, [open, closeNavigation]);
  const initials = profile.nome.trim().split(/\s+/).slice(0, 2).map(word => word[0]).join('');
  return <div className="portal"><a className="skip-link" href="#conteudo">Ir para o conteúdo</a>
    {open && <button className="sidebar-backdrop" tabIndex={-1} aria-label="Fechar navegação" onClick={closeNavigation} />}
    <aside ref={sidebar} id="navegacao-principal" className={`sidebar ${open ? 'is-open' : ''}`} aria-label="Navegação principal" role={open ? 'dialog' : undefined} aria-modal={open ? true : undefined}>
      <Link href="/painel" className="sidebar-brand" onClick={() => setOpen(false)}><span className="brand-symbol"><Image src="/mi-electric-brasil.svg" alt="" width={43} height={43} priority /></span><span><strong>EM</strong><small>MI Electric Brasil</small></span></Link>
      <div className={s.sidebarHeading}><div className="sidebar-label">Atalhos</div><button className={`icon-button ${s.sidebarClose}`} type="button" aria-label="Fechar menu" onClick={closeNavigation}><Icon name="close" size={17} /></button></div>
      <nav aria-label="Atalhos do EM">{shortcuts.map(item => <Link key={item.href} href={item.href} aria-current={current?.href === item.href ? 'page' : undefined} onClick={() => setOpen(false)}><Icon name={item.icon} /><span>{item.label}</span>{current?.href === item.href && <span className="nav-mark" />}</Link>)}</nav>
      <p className={s.sidebarHint}>Todas as funcionalidades estão nos cards da página inicial.</p>
      <div className="sidebar-note"><span className="connection-dot" /><span>Uma operação conectada<small>Web e mobile na mesma base</small></span></div>
      <div className="sidebar-bottom"><span className="avatar">{initials || 'EM'}</span><span className="user-copy"><strong>{profile.nome}</strong><small>{profile.cargo || (profile.perfil === 'administrador' ? 'Administrador' : 'Equipe MI Electric')}</small></span><form action="/auth/logout" method="post"><button className="icon-button" aria-label="Sair da plataforma" title="Sair da plataforma"><Icon name="logout" size={18} /></button></form></div>
    </aside>
    <div className="portal-body"><header className="topbar"><div className="topbar-path"><button ref={toggle} className="icon-button mobile-nav-button" onClick={() => setOpen(true)} aria-label="Abrir navegação" aria-controls="navegacao-principal" aria-expanded={open}><Icon name="menu" /></button><span>Oficina</span><Icon name="chevron" size={14} /><strong>{current?.label || 'Projeto'}</strong></div><div className="topbar-meta"><span className="workspace-label"><span className="connection-dot" />Ambiente operacional</span><span className="topbar-divider" /><span className="topbar-date">{new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'long', timeZone: 'America/Sao_Paulo' }).format(new Date())}</span></div></header>
      {children}
    </div>
  </div>;
}

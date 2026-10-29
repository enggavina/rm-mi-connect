'use client';
import { useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Icon, type IconName } from './icons';
const navigation: { href: string; label: string; icon: IconName }[] = [
  { href: '/painel', label: 'Visão geral', icon: 'dashboard' }, { href: '/projetos', label: 'Projetos', icon: 'folder' },
  { href: '/planejamento', label: 'Planejamento', icon: 'board' }, { href: '/cronograma', label: 'Cronograma', icon: 'calendar' },
  { href: '/formularios', label: 'Formulários', icon: 'clipboard' }, { href: '/cadastros', label: 'Cadastros', icon: 'settings' },
];
export function PortalShell({ profile, children }: { profile: { nome: string; perfil: string; cargo?: string | null }; children: React.ReactNode }) {
  const path = usePathname(); const [open, setOpen] = useState(false);
  const current = navigation.find(item => path.startsWith(item.href));
  const initials = profile.nome.trim().split(/\s+/).slice(0, 2).map(word => word[0]).join('');
  return <div className="portal"><a className="skip-link" href="#conteudo">Ir para o conteúdo</a>
    {open && <button className="sidebar-backdrop" aria-label="Fechar navegação" onClick={() => setOpen(false)} />}
    <aside className={`sidebar ${open ? 'is-open' : ''}`} aria-label="Navegação principal">
      <Link href="/painel" className="sidebar-brand" onClick={() => setOpen(false)}><span className="brand-symbol"><Image src="/mi-electric-brasil.svg" alt="" width={43} height={43} priority /></span><span><strong>EM</strong><small>MI Electric Brasil</small></span></Link>
      <div className="sidebar-label">GESTÃO DA OFICINA</div>
      <nav>{navigation.map(item => <Link key={item.href} href={item.href} aria-current={path.startsWith(item.href) ? 'page' : undefined} onClick={() => setOpen(false)}><Icon name={item.icon} /><span>{item.label}</span>{path.startsWith(item.href) && <span className="nav-mark" />}</Link>)}</nav>
      <div className="sidebar-note"><span className="connection-dot" /><span>Uma operação conectada<small>Web e mobile na mesma base</small></span></div>
      <div className="sidebar-bottom"><span className="avatar">{initials || 'EM'}</span><span className="user-copy"><strong>{profile.nome}</strong><small>{profile.cargo || (profile.perfil === 'administrador' ? 'Administrador' : 'Equipe MI Electric')}</small></span><form action="/auth/logout" method="post"><button className="icon-button" aria-label="Sair da plataforma" title="Sair da plataforma"><Icon name="logout" size={18} /></button></form></div>
    </aside>
    <div className="portal-body"><header className="topbar"><div className="topbar-path"><button className="icon-button mobile-nav-button" onClick={() => setOpen(true)} aria-label="Abrir navegação"><Icon name="menu" /></button><span>Oficina</span><Icon name="chevron" size={14} /><strong>{current?.label || 'Projeto'}</strong></div><div className="topbar-meta"><span className="workspace-label"><span className="connection-dot" />Ambiente operacional</span><span className="topbar-divider" /><span className="topbar-date">{new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'long', timeZone: 'America/Sao_Paulo' }).format(new Date())}</span></div></header>
      <main id="conteudo" className="workspace">{children}</main><footer className="portal-footer"><span>EM <span>·</span> MI Electric Brasil</span><span>Gestão da operação</span></footer>
    </div>
  </div>;
}

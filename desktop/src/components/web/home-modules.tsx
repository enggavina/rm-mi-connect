import { Icon } from './icons';
import { portalHomeModules } from './navigation';
import type { CorporateCapability } from '@/server/web/sso-policy';
import s from './home-modules.module.css';

const descriptions: Record<string, string> = {
  Operação: 'Acompanhe os equipamentos e os registros da oficina.',
  Planejamento: 'Organize os trabalhos, a sequência e os prazos.',
  Cadastros: 'Mantenha os dados e os modelos usados pela equipe.',
};

export function HomeModules({ capabilities }: { capabilities?: readonly CorporateCapability[] }) {
  const groups = portalHomeModules(capabilities);
  if (!groups.length) return null;
  return <div className={s.groups} data-home-modules>{groups.map(group => <section className={s.group} key={group.label} aria-label={group.label}>
    <div className={s.heading}><div><h2>{group.label}</h2><p>{descriptions[group.label]}</p></div><span>{group.items.length} {group.items.length === 1 ? 'funcionalidade' : 'funcionalidades'}</span></div>
    <div className={s.cards}>{group.items.map(item => <a className={s.card} href={item.href} key={item.href} data-home-module={item.href}>
      <span className={s.icon}><Icon name={item.icon} size={22} /></span><div className={s.copy}><h3>{item.label}</h3><p>{item.description}</p></div><span className={s.arrow}><Icon name="arrow" size={17} /></span>
    </a>)}</div>
  </section>)}</div>;
}

import './globals.css';
export const metadata = { title: { default: 'EM · MI Electric Brasil', template: '%s · EM' }, description: 'Gestão da oficina: projetos, planejamento, formulários e evidências da MI Electric Brasil.', robots: { index: false, follow: false } };
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt-BR"><body>{children}</body></html>;
}

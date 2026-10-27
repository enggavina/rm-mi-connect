import './globals.css';
export const metadata = { title: 'RM · MI Connect', description: 'Operação de revisão de motores' };
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt-BR"><body>{children}</body></html>;
}

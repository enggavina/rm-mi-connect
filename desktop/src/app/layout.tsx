import './globals.css';
export const metadata = { title: 'EM · MI Electric Brasil', description: 'Da célula ao projeto: formulários e galeria para a operação da MI Electric Brasil.' };
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt-BR"><body>{children}</body></html>;
}

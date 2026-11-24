export const dynamic = 'force-dynamic';

export const metadata = {
  title: 'EM Operacional',
  description: 'Consulte as células e os projetos autorizados na sua oficina.',
  referrer: 'same-origin' as const,
};

export default function OperationLayout({ children }: { children: React.ReactNode }) {
  return children;
}

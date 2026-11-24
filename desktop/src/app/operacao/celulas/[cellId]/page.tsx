import { loadOperation } from '@/server/operation/session';
import { OperationView, operationPageNumber } from '../../operation-view';

export default async function OperationProjectsPage({ params, searchParams }: {
  params: Promise<{ cellId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const [{ cellId }, { page }] = await Promise.all([params, searchParams]);
  const result = await loadOperation({ cellId, page: operationPageNumber(page) });
  return <OperationView result={result} kind="projects" />;
}

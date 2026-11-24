import { loadOperationValidation } from '@/server/operation/validation';
import { OperationView, operationPageNumber } from '../../../operation-view';

export default async function OperationValidationProjectsPage({ params, searchParams }: {
  params: Promise<{ cellId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const [{ cellId }, { page }] = await Promise.all([params, searchParams]);
  const result = await loadOperationValidation({ cellId, page: operationPageNumber(page) });
  return <OperationView result={result} kind="projects" base="/operacao/validacao" />;
}

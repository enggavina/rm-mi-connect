import { loadOperationValidation } from '@/server/operation/validation';
import { OperationView } from '../../../../../operation-view';

export default async function OperationValidationProjectPage({ params }: { params: Promise<{ cellId: string; projectId: string }> }) {
  const { cellId, projectId } = await params;
  return <OperationView result={await loadOperationValidation({ cellId, projectId })} kind="project" base="/operacao/validacao" />;
}

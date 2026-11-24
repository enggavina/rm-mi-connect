import { OperationView } from '@/app/operacao/operation-view';
import { loadOperationValidation } from '@/server/operation/validation';

export default async function OperationValidationFormPage({ params }: {
  params: Promise<{ cellId: string; projectId: string; formId: string }>;
}) {
  const { cellId, projectId, formId } = await params;
  return <OperationView result={await loadOperationValidation({ cellId, projectId, formId })} kind="form" base="/operacao/validacao" />;
}

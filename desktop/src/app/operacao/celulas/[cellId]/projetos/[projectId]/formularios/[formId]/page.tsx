import { OperationView } from '@/app/operacao/operation-view';
import { loadOperation } from '@/server/operation/session';

export default async function OperationFormPage({ params }: {
  params: Promise<{ cellId: string; projectId: string; formId: string }>;
}) {
  const { cellId, projectId, formId } = await params;
  return <OperationView result={await loadOperation({ cellId, projectId, formId })} kind="form" />;
}

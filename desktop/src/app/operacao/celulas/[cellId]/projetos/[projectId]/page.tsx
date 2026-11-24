import { loadOperation } from '@/server/operation/session';
import { OperationView } from '../../../../operation-view';

export default async function OperationProjectPage({ params }: { params: Promise<{ cellId: string; projectId: string }> }) {
  const { cellId, projectId } = await params;
  return <OperationView result={await loadOperation({ cellId, projectId })} kind="project" />;
}

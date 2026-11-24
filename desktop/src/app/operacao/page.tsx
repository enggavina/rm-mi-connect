import { loadOperation } from '@/server/operation/session';
import { OperationView } from './operation-view';

export default async function OperationCellsPage() {
  return <OperationView result={await loadOperation()} kind="cells" />;
}

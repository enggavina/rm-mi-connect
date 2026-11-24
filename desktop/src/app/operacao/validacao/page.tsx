import { loadOperationValidation } from '@/server/operation/validation';
import { OperationView } from '../operation-view';

export default async function OperationValidationPage() {
  return <OperationView result={await loadOperationValidation()} kind="cells" base="/operacao/validacao" />;
}

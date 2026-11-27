import { z } from 'zod';
import { uuid } from './policy';
import { WorkshopContextError } from './workshop-context';

export const androidOperationLabels = {
  rm_submit_recebimento_v1: 'Recebimento',
  rm_submit_form_inspection_v1: 'Formulário',
  rm_submit_form_revision_v1: 'Correção de formulário',
  rm_record_cell_photo_v1: 'Registro de foto',
  rm_transition_stage_approval_v1: 'Aprovação de etapa',
  rm_update_cell_status_v1: 'Atualização de status',
  rm_add_cell_comment_v1: 'Comentário',
  rm_record_execution_event_v1: 'Apontamento de execução',
} as const;

const timestamp = z.iso.datetime({ offset: true });
const operation = z.enum(Object.keys(androidOperationLabels) as (keyof typeof androidOperationLabels)[]);
const receiptSchema = z.object({ protocol: uuid, operation, project_id: uuid,
  project_number: z.string().nullable(), phase: z.enum(['opened', 'confirmed']), recorded_at: timestamp,
  last_retry_at: timestamp.nullable(), form_record_id: uuid.nullable() }).strict();

export const androidProtocolQuery = z.string().trim().toLowerCase().pipe(uuid);

export function checkAndroidProtocol(value: unknown, protocol: string) {
  if (value === null) return null;
  const parsed = receiptSchema.safeParse(value);
  if (!parsed.success || parsed.data.protocol !== protocol
    || (parsed.data.phase === 'opened' && parsed.data.operation !== 'rm_submit_recebimento_v1')) {
    throw new WorkshopContextError('WORKSHOP_UNAVAILABLE');
  }
  return parsed.data;
}

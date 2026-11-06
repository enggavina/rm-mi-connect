import {z} from 'zod';
const uuid=z.string().uuid().transform(value=>value.toLowerCase());
const timestamp=z.string().datetime({offset:true});
export const projectDeleteCountsSchema=z.object({equipment:z.number().int().nonnegative(),cells:z.number().int().nonnegative(),photos:z.number().int().nonnegative(),
  form_records:z.number().int().nonnegative(),answers:z.number().int().nonnegative(),approvals:z.number().int().nonnegative(),comments:z.number().int().nonnegative(),
  notifications:z.number().int().nonnegative(),documents:z.number().int().nonnegative(),commercial:z.number().int().nonnegative(),laboratory:z.number().int().nonnegative()}).strict();
export const projectDeleteSnapshotSchema=z.object({project:z.object({id:uuid,numero:z.string().nullable(),nome:z.string().nullable(),updated_at:timestamp}).strict(),
  can_delete:z.boolean(),reason:z.string().nullable(),counts:projectDeleteCountsSchema,private_files:z.number().int().nonnegative(),context_version:z.string().regex(/^[a-f0-9]{64}$/)}).strict();
export type ProjectDeleteSnapshot=z.infer<typeof projectDeleteSnapshotSchema>;
export const deleteProjectSchema=z.object({submissionId:uuid,id:uuid,expected_updated_at:timestamp,expected_context_version:z.string().regex(/^[a-f0-9]{64}$/),
  confirm_delete:z.literal(true),justificativa:z.string().trim().min(1,'Informe a justificativa.').max(2000).refine(value=>!value.includes('\u0000'))}).strict();
export type DeleteProjectInput=z.infer<typeof deleteProjectSchema>;

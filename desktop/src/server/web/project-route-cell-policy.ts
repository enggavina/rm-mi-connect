import {z} from 'zod';
import {uuid} from './policy';

const timestamp=z.string().datetime({offset:true});
const common={submissionId:uuid,projeto_id:uuid,celula_projeto_id:uuid,expected_project_updated_at:timestamp,
  expected_allocation_updated_at:timestamp,expected_context_version:z.string().regex(/^[a-f0-9]{64}$/),confirm_change:z.literal(true)};
export const manageProjectRouteCellSchema=z.discriminatedUnion('action',[
  z.object({...common,action:z.literal('forms'),forms_ids:z.array(uuid).max(500)}).strict(),
  z.object({...common,action:z.literal('remove')}).strict(),
]).superRefine((value,ctx)=>{if(value.action==='forms'&&new Set(value.forms_ids).size!==value.forms_ids.length)
  ctx.addIssue({code:'custom',path:['forms_ids'],message:'Selecione cada formulário uma única vez.'});});
export type ManageProjectRouteCellInput=z.infer<typeof manageProjectRouteCellSchema>;
export const projectRouteCellResultSchema=z.object({projeto_id:uuid,celula_projeto_id:uuid,action:z.enum(['forms','remove']),
  context_version:z.string().regex(/^[a-f0-9]{64}$/),changed_ids:z.array(uuid).max(1),retirada:z.boolean(),forms_ids:z.array(uuid).max(2000)});

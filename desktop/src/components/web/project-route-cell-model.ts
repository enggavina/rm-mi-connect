import type {ProjectRouteCellSnapshot} from '@/server/web/project-route-cell-data';
import type {ManageProjectRouteCellInput} from '@/server/web/project-route-cell-policy';
import {freezeEngineeringRequest} from './engineering-model';

export function routeFormsChanged(original:readonly string[],selected:readonly string[]){
  return original.length!==selected.length||original.some(id=>!selected.includes(id));
}
function common(snapshot:ProjectRouteCellSnapshot,submissionId:string){
  if(!snapshot.complete||snapshot.project.closed||snapshot.allocation.retirada)throw new Error('Recarregue a configuração desta célula antes de alterar.');
  return {submissionId,projeto_id:snapshot.project.id,celula_projeto_id:snapshot.allocation.id,
    expected_project_updated_at:snapshot.project.updated_at,expected_allocation_updated_at:snapshot.allocation.updated_at,
    expected_context_version:snapshot.context_version,confirm_change:true as const};
}
export function routeFormsRequest(snapshot:ProjectRouteCellSnapshot,selected:readonly string[],submissionId:string):ManageProjectRouteCellInput{
  if(!snapshot.can_edit_forms)throw new Error(snapshot.forms_reason||'Os formulários desta célula permanecem em consulta.');
  if(selected.length>500||new Set(selected).size!==selected.length)throw new Error('Selecione até 500 formulários diferentes.');
  for(const id of snapshot.allocation.forms_ids){const form=snapshot.forms.find(row=>row.id===id);if(!selected.includes(id)&&(!form||!form.can_remove))
    throw new Error(form?.reason||'Um formulário já utilizado não pode ser removido.');}
  if(selected.some(id=>{const form=snapshot.forms.find(row=>row.id===id);return !form||!form.ativo&&!form.assigned;}))throw new Error('Selecione um formulário disponível nesta célula.');
  if(!routeFormsChanged(snapshot.allocation.forms_ids,selected))throw new Error('Não há alterações nos formulários para salvar.');
  return freezeEngineeringRequest({...common(snapshot,submissionId),action:'forms',forms_ids:[...selected]});
}
export function removeRouteCellRequest(snapshot:ProjectRouteCellSnapshot,confirmed:boolean,submissionId:string):ManageProjectRouteCellInput{
  if(!snapshot.can_remove_cell)throw new Error(snapshot.remove_reason||'Esta célula possui uso operacional e não pode ser removida.');
  if(!confirmed)throw new Error('Confirme a remoção desta célula do roteiro.');
  return freezeEngineeringRequest({...common(snapshot,submissionId),action:'remove'});
}

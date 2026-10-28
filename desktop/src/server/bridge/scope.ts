import type { Entity, Row } from './mapping';
import type { Constraint } from './client';

export function isOperationalProject(raw: Row): boolean {
  const status=String(raw['Status PCP'] || raw.status_pcp || '');
  return !raw['Data Real de Entrega'] && !raw.data_real_de_entrega &&
    !['Cancelado','cancelado','Finalizado para faturar','finalizando_para_faturar'].includes(status);
}
export function chunkIds(ids: string[], size=25) { const groups:string[][]=[];for(let i=0;i<ids.length;i+=size)groups.push(ids.slice(i,i+size));return groups; }
export function scopedGroups(entity: Entity, projectIds: string[], recordIds: string[]): Constraint[][] {
  const field = entity.table==='rm_respostas' ? 'Registro_Formulario'
    : ['rm_celulas_projeto','rm_comentarios','rm_documentos'].includes(entity.table) ? 'Projeto'
      : entity.table==='rm_docs' ? 'Projeto_rm'
      : entity.table==='rm_logs_aprovacao' ? 'Projeto_RM'
      : ['rm_equipamentos','rm_fotos','rm_registros_formulario','rm_aprovacoes_etapas'].includes(entity.table) ? 'ProjetoRM' : null;
  if (!field) return [[]];
  return chunkIds(entity.table==='rm_respostas'?recordIds:projectIds).map(ids=>[{key:field,constraint_type:'in',value:ids}]);
}

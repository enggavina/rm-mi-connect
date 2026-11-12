import {z} from 'zod';
import type {CorporateCapability} from './sso-policy';

type Field={key:string;label:string;group:'project'|'equipment'|'allocation';kind:'text'|'date'|'datetime'|'number';width:number};
export const allocationExportFields=[
 {key:'project_number',label:'Número do projeto',group:'project',kind:'text',width:22},
 {key:'project_name',label:'Nome do projeto',group:'project',kind:'text',width:38},
 {key:'client_name',label:'Cliente',group:'project',kind:'text',width:35},
 {key:'project_status',label:'Status global do projeto',group:'project',kind:'text',width:28},
 {key:'project_pcp_status',label:'Status PCP do projeto',group:'project',kind:'text',width:30},
 {key:'arrival_at',label:'Chegada do equipamento',group:'project',kind:'datetime',width:24},
 {key:'project_planned_start',label:'Início previsto do projeto',group:'project',kind:'date',width:24},
 {key:'project_planned_end',label:'Fim previsto do projeto',group:'project',kind:'date',width:24},
 {key:'contract_date',label:'Data contratual',group:'project',kind:'date',width:20},
 {key:'renegotiated_date',label:'Data renegociada',group:'project',kind:'date',width:21},
 {key:'inspection_start',label:'Início da peritagem',group:'project',kind:'date',width:22},
 {key:'inspection_end',label:'Fim da peritagem',group:'project',kind:'date',width:22},
 {key:'repair_start',label:'Início do reparo',group:'project',kind:'date',width:22},
 {key:'repair_end',label:'Fim do reparo',group:'project',kind:'date',width:22},
 {key:'project_delivered_at',label:'Entrega realizada do projeto',group:'project',kind:'date',width:26},
 {key:'project_manager',label:'Gestor do projeto',group:'project',kind:'text',width:30},
 {key:'project_scope',label:'Escopo do projeto',group:'project',kind:'text',width:45},
 {key:'equipment_type',label:'Tipo de equipamento',group:'equipment',kind:'text',width:38},
 {key:'equipment_description',label:'Descrição do equipamento',group:'equipment',kind:'text',width:45},
 {key:'manufacturer',label:'Fabricante',group:'equipment',kind:'text',width:24},
 {key:'model',label:'Modelo',group:'equipment',kind:'text',width:24},
 {key:'serial_number',label:'Número de série',group:'equipment',kind:'text',width:25},
 {key:'power',label:'Potência',group:'equipment',kind:'text',width:20},
 {key:'motor_plate',label:'Placa do motor',group:'equipment',kind:'text',width:24},
 {key:'voltage',label:'Tensão do estator',group:'equipment',kind:'text',width:23},
 {key:'current',label:'Corrente do estator',group:'equipment',kind:'text',width:23},
 {key:'speed',label:'Rotação',group:'equipment',kind:'text',width:20},
 {key:'frequency',label:'Frequência',group:'equipment',kind:'text',width:20},
 {key:'weight',label:'Peso',group:'equipment',kind:'text',width:20},
 {key:'cell_name',label:'Célula',group:'allocation',kind:'text',width:30},
 {key:'allocation_status',label:'Status da célula',group:'allocation',kind:'text',width:32},
 {key:'allocation_start',label:'Início da alocação',group:'allocation',kind:'date',width:22},
 {key:'allocation_due',label:'Prazo da alocação',group:'allocation',kind:'date',width:22},
 {key:'allocation_finished',label:'Fim realizado na célula',group:'allocation',kind:'date',width:24},
 {key:'allocation_responsible',label:'Responsável da célula',group:'allocation',kind:'text',width:30},
 {key:'priority',label:'Prioridade da célula',group:'allocation',kind:'text',width:24},
 {key:'visible',label:'Visível no mobile',group:'allocation',kind:'text',width:22},
 {key:'blocked',label:'Célula bloqueada',group:'allocation',kind:'text',width:22},
 {key:'block_reason',label:'Motivo do bloqueio',group:'allocation',kind:'text',width:42},
 {key:'delay_reason',label:'Motivo do atraso',group:'allocation',kind:'text',width:42},
 {key:'planned_hours',label:'Horas previstas',group:'allocation',kind:'number',width:20},
 {key:'actual_hours',label:'Horas realizadas',group:'allocation',kind:'number',width:20},
 {key:'allocation_note',label:'Observação da alocação',group:'allocation',kind:'text',width:45},
] as const satisfies readonly Field[];
export type AllocationExportField=typeof allocationExportFields[number]['key'];
export const allocationExportDefaultFields:readonly AllocationExportField[]=['project_number','client_name','equipment_description','equipment_type','cell_name','allocation_status','allocation_start','allocation_due','allocation_responsible'];
export const allocationExportScopes:CorporateCapability[]=['em.portal.read','em.planning.read','em.projects.read'];
export const allocationExportLimits={cells:200,rows:20_000,bodyBytes:16_384} as const;
const fieldKeys=allocationExportFields.map(field=>field.key);
export const allocationExportSchema=z.object({
 cell_ids:z.array(z.string().uuid().transform(id=>id.toLowerCase())).min(1).max(allocationExportLimits.cells),
 fields:z.array(z.enum(fieldKeys as [AllocationExportField,...AllocationExportField[]])).min(1).max(fieldKeys.length),
}).strict().superRefine((value,context)=>{
 if(new Set(value.cell_ids).size!==value.cell_ids.length)context.addIssue({code:'custom',path:['cell_ids'],message:'Células repetidas.'});
 if(new Set(value.fields).size!==value.fields.length)context.addIssue({code:'custom',path:['fields'],message:'Campos repetidos.'});
});
export type AllocationExportRequest=z.infer<typeof allocationExportSchema>;
export const allocationExportMime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

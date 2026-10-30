import type { ProjectEquipmentChanges, ProjectEquipmentSnapshot, SaveProjectEquipmentInput } from '@/server/web/project-equipment-policy';
import { freezeEngineeringRequest } from './engineering-model';

export const equipmentFieldGroups = [
  { id: 'identificacao', title: 'Identificação do equipamento', fields: [
    { key: 'placa_motor', label: 'Placa do motor' },
    { key: 'fabricante', label: 'Fabricante' },
    { key: 'modelo', label: 'Modelo' },
    { key: 'numero_serie', label: 'Número de série' },
    { key: 'embarcacao', label: 'Embarcação' },
    { key: 'descricao', label: 'Descrição técnica', multiline: true },
  ] },
  { id: 'eletricos', title: 'Dados elétricos', fields: [
    { key: 'potencia', label: 'Potência' },
    { key: 'rotacao', label: 'Rotação' },
    { key: 'tensao_estator', label: 'Tensão do estator' },
    { key: 'tipo_tensao', label: 'Tipo de tensão' },
    { key: 'corrente_estator', label: 'Corrente do estator' },
    { key: 'corrente_partida', label: 'Corrente' },
    { key: 'frequencia', label: 'Frequência' },
    { key: 'ligacao', label: 'Ligação' },
    { key: 'fp', label: 'Fator de potência (FP)', numeric: true },
    { key: 'fs', label: 'Fator de serviço (FS)', numeric: true },
    { key: 'numero_cabos', label: 'Número de cabos', numeric: true },
  ] },
  { id: 'construcao', title: 'Construção e classificação', fields: [
    { key: 'classe_isolamento', label: 'Classe de isolamento' },
    { key: 'grau_ip', label: 'Grau de proteção (IP)' },
    { key: 'forma', label: 'Forma' },
    { key: 'regime', label: 'Regime' },
    { key: 'peso', label: 'Peso' },
    { key: 'componentes', label: 'Componentes', multiline: true },
    { key: 'certificado', label: 'Certificado' },
    { key: 'norma', label: 'Norma' },
  ] },
] as const;

export type ProjectEquipmentField = typeof equipmentFieldGroups[number]['fields'][number]['key'];
export const equipmentFieldLabels = Object.fromEntries(equipmentFieldGroups.flatMap(group => group.fields.map(field => [field.key, field.label]))) as Record<ProjectEquipmentField, string>;
export type ProjectEquipmentDraft = Record<ProjectEquipmentField, string>;
export function projectEquipmentDraft(snapshot: ProjectEquipmentSnapshot): ProjectEquipmentDraft {
  const row = snapshot.equipment;
  return Object.fromEntries(equipmentFieldGroups.flatMap(group => group.fields.map(field => [field.key, row?.[field.key] == null ? '' : String(row[field.key])]))) as ProjectEquipmentDraft;
}
const decimalValue = (value: string): string | null => {
  const match = value.match(/^([+-]?)(\d+)(?:\.(\d+))?$/); if (!match) return null;
  const integral = match[2].replace(/^0+(?=\d)/, ''), fractional = (match[3] || '').replace(/0+$/, '');
  const zero = integral === '0' && !fractional;
  return `${!zero && match[1] === '-' ? '-' : ''}${integral}${fractional ? '.' + fractional : ''}`;
};
function changedDecimal(value: string, label: string) {
  const normalized = value.trim().replace(',', '.');
  if (!/^[+-]?\d{1,30}(?:\.\d{1,20})?$/.test(normalized)) throw new Error(`${label}: informe um decimal sem separador de milhares, com até 30 dígitos inteiros e 20 decimais.`);
  return normalized;
}
/** Unchanged legacy values are skipped before validating the editable limits. */
export function projectEquipmentChanges(snapshot: ProjectEquipmentSnapshot, draft: ProjectEquipmentDraft): ProjectEquipmentChanges {
  const original = projectEquipmentDraft(snapshot), changes: Record<string, string | number | null> = {};
  for (const key of Object.keys(original) as ProjectEquipmentField[]) {
    const current = draft[key]; if (typeof current !== 'string') throw new Error('Confira os dados técnicos.');
    if (current === original[key]) continue;
    if (current === '') { changes[key] = null; continue; }
    if (key === 'fp' || key === 'fs') {
      const normalized = changedDecimal(current, equipmentFieldLabels[key]);
      if (decimalValue(normalized) !== decimalValue(original[key])) changes[key] = normalized;
    } else if (key === 'numero_cabos') {
      if (!/^\d{1,10}$/.test(current.trim())) throw new Error('Número de cabos: informe um inteiro entre 0 e 2.147.483.647.');
      const number = Number(current.trim());
      if (number > 2_147_483_647) throw new Error('Número de cabos: informe um inteiro entre 0 e 2.147.483.647.');
      if (String(number) !== original[key]) changes[key] = number;
    } else if (key === 'placa_motor') {
      if (!['c___placa', 's___placa'].includes(current)) throw new Error('Selecione a condição da placa do motor.');
      changes[key] = current;
    } else {
      if (current.length > 10_000 || current.includes('\u0000')) throw new Error(`${equipmentFieldLabels[key]}: use até 10.000 caracteres válidos.`);
      changes[key] = current;
    }
  }
  return changes as ProjectEquipmentChanges;
}
export function projectEquipmentRequest(snapshot: ProjectEquipmentSnapshot, draft: ProjectEquipmentDraft, submissionId: string): SaveProjectEquipmentInput {
  if (snapshot.binding_state !== 'linked' || !snapshot.can_edit || !snapshot.equipment || snapshot.project.closed
    || snapshot.project.equipamento_id !== snapshot.equipment.id || snapshot.equipment.projeto_id !== snapshot.project.id) throw new Error('O vínculo do equipamento precisa ser conferido antes de editar.');
  const changes = projectEquipmentChanges(snapshot, draft);
  if (!Object.keys(changes).length) throw new Error('Altere um dado técnico antes de confirmar.');
  return freezeEngineeringRequest({ submissionId, projeto_id: snapshot.project.id, equipamento_id: snapshot.equipment.id,
    expected_project_updated_at: snapshot.project.updated_at, expected_equipment_updated_at: snapshot.equipment.updated_at,
    expected_context_version: snapshot.context_version, confirm_change: true, changes });
}
export function projectEquipmentMatches(snapshot: ProjectEquipmentSnapshot, project: { id: string; updated_at: string; equipamento_id?: string | null; tipo_equipamento_id?: string | null; status_pcp?: string | null; data_real_de_entrega?: string | null }) {
  return snapshot.project.id === project.id && snapshot.project.updated_at === project.updated_at
    && snapshot.project.equipamento_id === (project.equipamento_id ?? null)
    && snapshot.project.tipo_equipamento_id === (project.tipo_equipamento_id ?? null)
    && snapshot.project.status_pcp === (project.status_pcp ?? null)
    && snapshot.project.data_real_de_entrega === (project.data_real_de_entrega ?? null);
}
export function equipmentDisplayValue(key: ProjectEquipmentField, value: unknown) {
  if (value == null || value === '') return 'Não informado';
  if (key === 'placa_motor') return value === 'c___placa' ? 'Com placa' : value === 's___placa' ? 'Sem placa' : String(value);
  return String(value);
}

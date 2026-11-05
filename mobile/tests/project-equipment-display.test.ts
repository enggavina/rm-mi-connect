import test from 'node:test';
import assert from 'node:assert/strict';
import type { Operator, Row } from '../src/core/types';
import { cellAllocations } from '../src/domain/journey';
import { indexProjectEquipment, linkedProjectEquipment, projectEquipmentDescription, projectMatchesSearch } from '../src/domain/project-actions';

const project: Row = { id: 'project-1', equipamento_id: 'equipment-1', nome: 'Projeto' };
const equipment: Row = { id: 'equipment-1', projeto_id: 'project-1', descricao: 'Motor trifásico' };
const allocation: Row = { id: 'allocation-1', projeto_id: 'project-1', celula_id: 'cell-1', visibilidade: true };

test('equipment display requires both canonical links and preserves a legacy description first', () => {
  const index = indexProjectEquipment([equipment]);
  assert.equal(linkedProjectEquipment(project, index), equipment);
  assert.equal(projectEquipmentDescription(project, index), 'Motor trifásico');
  assert.equal(projectEquipmentDescription({ ...project, descricao_equipamento: 'Descrição legada' }, index), 'Descrição legada');
  assert.equal(projectEquipmentDescription({ ...project, equipamento_id: null }, index), undefined);
  assert.equal(projectEquipmentDescription({ ...project, equipamento_id: 'other' }, index), undefined);
  assert.equal(projectEquipmentDescription(project, indexProjectEquipment([{ ...equipment, projeto_id: 'other-project' }])), undefined);
  assert.deepEqual(project, { id: 'project-1', equipamento_id: 'equipment-1', nome: 'Projeto' });
});

test('partial sync and conflicting or duplicate equipment records never invent a link', () => {
  assert.equal(linkedProjectEquipment(project, indexProjectEquipment([])), undefined);
  assert.equal(projectEquipmentDescription(project, indexProjectEquipment([])), undefined);
  assert.equal(linkedProjectEquipment(project, indexProjectEquipment([equipment, { ...equipment, descricao: 'Duplicado' }])), undefined);
  assert.equal(projectEquipmentDescription(project, indexProjectEquipment([equipment, { ...equipment, descricao: 'Duplicado' }])), undefined);
  const duplicate = indexProjectEquipment([equipment, { ...equipment, projeto_id: 'other' }, equipment]);
  assert.equal(projectEquipmentDescription(project, duplicate), undefined);
});

test('local search matches the linked description only within the already permitted cell project', () => {
  const other: Row = { id: 'project-2', equipamento_id: 'equipment-2', nome: 'Outro' };
  const otherEquipment: Row = { id: 'equipment-2', projeto_id: 'project-2', descricao: 'Turbina reservada' };
  const index = indexProjectEquipment([equipment, otherEquipment]);
  const operator: Operator = { operador_id: 'operator', matricula: '1', nome: 'Operador', perfil: 'mobile', perfil_assinante: [], celulas_vinculadas: [{ celula_id: 'cell-1', nome: 'Célula' }], authenticated_at: '2026-01-01T00:00:00Z' };
  const projects = [project, other];
  const allocations = [allocation, { id: 'allocation-2', projeto_id: 'project-2', celula_id: 'cell-2', visibilidade: true }];
  const visible = cellAllocations(operator, 'cell-1', projects, allocations);
  const find = (query: string) => visible.filter(row => projectMatchesSearch(query, projects.find(item => item.id === row.projeto_id), row, [], index));
  assert.equal(find('TRIFÁSICO').length, 1);
  assert.equal(find('Turbina reservada').length, 0);
  assert.equal(projectMatchesSearch('Turbina reservada', other, allocation, [], index), false);
  assert.equal(projectMatchesSearch('Motor trifásico', project, allocation, [], indexProjectEquipment([])), false);
  assert.equal(projectMatchesSearch('legada', { ...project, descricao_equipamento: 'Descrição legada' }, allocation, [], index), true);
});

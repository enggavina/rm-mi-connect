import assert from 'node:assert/strict';
import test from 'node:test';
import { allocationStatusOptions, cellStatusLabels, cellStatuses } from '../src/server/web/cell-statuses';
import { planCellSchema } from '../src/server/web/policy';
import { stageRuleConfigSchema } from '../src/server/web/operational-stage-rule-policy';
import { display } from '../src/components/web/ui';

const id='00000000-0000-4000-8000-000000000001',version='2026-11-12T12:00:00.123456+00:00';
const input={submissionId:id,projeto_id:id,celula_id:id,expected_updated_at:null};
test('the same cell-status options support initial allocation and later planning without adding project fields',()=>{
  for(const status of cellStatuses){
    assert.equal(planCellSchema.safeParse({...input,expected_updated_at:version,changes:{status}}).success,true);
    assert.equal(planCellSchema.safeParse({...input,changes:{status}}).success,status!=='retornado');
  }
  for(const status of [null,'',123,'unknown'])assert.equal(planCellSchema.safeParse({...input,changes:{status}}).success,false);
  assert.equal(planCellSchema.safeParse({...input,changes:{status_pcp:'coletado'}}).success,false);
  assert.equal(planCellSchema.safeParse({...input,changes:{observacao:'Preserve old allocation'}}).success,true);
  assert.equal(allocationStatusOptions(false).includes('retornado'),false);
  assert.equal(allocationStatusOptions(true).includes('retornado'),true);
});
test('collection statuses retain readable values in the allocation, audit and existing approval configuration',()=>{
  for(const status of ['aguardando_coleta','coletado'] as const){
    assert.equal(display(status),cellStatusLabels[status]);
    assert.equal(stageRuleConfigSchema.safeParse({celula_destino_id:id,status_cel_proj:status,bloquear_avanco_sem_aprov:false,aprovadores_ids:[id],aprovadores_retorno_ids:[id]}).success,true);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { executionQuality } from '../src/server/web/quality-policy';
import type { ExecutionAllocation, ExecutionSession, ExecutionSnapshot } from '../src/server/web/execution-data';
const at='2026-11-17T12:00:00Z';
const allocation=(id:string,patch:Partial<ExecutionAllocation>={}):ExecutionAllocation=>({id,project_id:'p',cell_id:'c',numero_projeto:null,cliente_nome:null,cell_name:'Montagem',status:'pendente',retired:false,project_closed:false,visible:false,blocked:false,planned_start:at,planned_end:at,updated_at:at,...patch});
const session=(allocation_id:string,patch:Partial<ExecutionSession>={}):ExecutionSession=>({id:allocation_id,allocation_id,project_id:'p',cell_id:'c',numero_projeto:null,cell_name:null,operator_id:'o',operator_name:null,state:'running',needs_review:false,last_event_id:null,last_captured_at:at,last_received_at:at,version:'a'.repeat(64),confirmed_minutes:null,effort_source:null,clock_warning:false,has_review:false,...patch});
const input=(allocations:ExecutionAllocation[],sessions:ExecutionSession[]=[]):ExecutionSnapshot=>({as_of:at,filters:{project_id:null,cell_id:null,session_id:null,include_closed:false},complete:true,total:allocations.length,allocations,sessions,detail:null});
test('partial and empty cohorts do not manufacture zero coverage',()=>{
  assert.equal(executionQuality({...input([]),complete:false,total:2001}),null);
  const result=executionQuality(input([]))!;assert.equal(result.datedPercent,null);assert.equal(result.receivedPercent,null);assert.deepEqual(result.rows,[]);
});
test('active hidden stages count; closed, retired and N/A stages do not distort denominators',()=>{
  const source=input([allocation('active'),allocation('retired',{retired:true}),allocation('closed',{project_closed:true}),allocation('done',{status:'finalizado'}),allocation('na',{status:'n_a'})]);
  const before=structuredClone(source),r=executionQuality(source)!;
  assert.equal(r.total,1);assert.equal(r.datedPercent,100);assert.equal(r.receivedPercent,0);assert.deepEqual(r.rows[0].reasons,['no_evidence']);assert.deepEqual(source,before);
});
test('coverage counts stages once with multiple operators and excludes void or unreceived evidence',()=>{
  const r=executionQuality(input([allocation('a'),allocation('b'),allocation('c')],[session('a'),session('a',{id:'other'}),session('b',{state:'void'}),session('c',{last_received_at:null})]))!;
  assert.equal(r.received,1);assert.equal(r.receivedPercent,33.3);assert.deepEqual(r.rows.map(row=>row.allocation.id),['b','c']);
});
test('date quality uses Sao Paulo civil days and preserves the original timestamps',()=>{
  const r=executionQuality(input([allocation('same-day',{planned_start:'2026-11-18T02:30:00Z',planned_end:'2026-11-17T08:00:00-03:00'}),allocation('inverted',{planned_start:'2026-11-18T12:00:00Z',planned_end:at}),allocation('empty',{planned_start:null,planned_end:null})]))!;
  assert.equal(r.dated,1);assert.equal(r.datedPercent,33.3);assert.ok(r.rows.find(row=>row.allocation.id==='inverted')!.reasons.includes('inverted_dates'));assert.ok(!r.rows.find(row=>row.allocation.id==='same-day')!.reasons.includes('inverted_dates'));
});
test('review evidence is received but not an accepted physical progress assertion; reconciled clocks are not pending',()=>{
  const r=executionQuality(input([allocation('a'),allocation('b'),allocation('c')],[session('a',{state:'review',needs_review:true}),session('b',{clock_warning:true}),session('c',{clock_warning:true,has_review:true})]))!;
  assert.equal(r.received,3);assert.equal(r.review,2);assert.deepEqual(r.rows.map(row=>row.allocation.id),['a','b']);assert.equal(r.rows[0].reasons.includes('no_evidence'),false);
});

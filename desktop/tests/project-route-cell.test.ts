import test from 'node:test';
import assert from 'node:assert/strict';
import {createProjectRouteCellData,type ProjectRouteCellSnapshot} from '../src/server/web/project-route-cell-data';
import {manageProjectRouteCellSchema} from '../src/server/web/project-route-cell-policy';
import {createProjectRouteCellActions} from '../src/server/web/project-route-cell-mutations';
import {routeFormsRequest,removeRouteCellRequest} from '../src/components/web/project-route-cell-model';
import {canMoveProjectRouteItem,projectRouteRequest} from '../src/components/web/project-route-model';
import type {CorporateCapability} from '../src/server/web/sso-policy';

const id=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const version='2026-11-06T12:34:56.123456+00:00';
function snapshot():ProjectRouteCellSnapshot{return {project:{id:id(1),numero:'OS',status_pcp:null,data_real_de_entrega:null,updated_at:version,closed:false},
  allocation:{id:id(2),projeto_id:id(1),celula_id:id(3),celula_nome:'Montagem',status:'em_andamento',retirada:false,updated_at:version,forms_ids:[id(4),id(5)]},
  forms:[{id:id(4),titulo:'Respondido',ativo:true,assigned:true,can_remove:false,reason:'Há resposta persistida.'},{id:id(5),titulo:'Sem uso',ativo:true,assigned:true,can_remove:true,reason:null},
    {id:id(6),titulo:'Novo',ativo:true,assigned:false,can_remove:true,reason:null}],context_version:'a'.repeat(64),can_edit_forms:true,forms_reason:null,
  can_remove_cell:false,remove_reason:'Há resposta persistida.',removal_counts:{photos:1,rules:1,reviewer_assignments:0},complete:true};}
const caps:CorporateCapability[]=['em.portal.read','em.projects.read','em.planning.read','em.planning.manage','em.forms.read','em.photos.read','em.approvals.read'];

test('route forms preserve a used link while adding and removing independent unused configurations',()=>{
  const value=snapshot(),request=routeFormsRequest(value,[id(4),id(6)],id(10));
  assert.equal(request.action,'forms');if(request.action!=='forms')return;
  assert.deepEqual(request.forms_ids,[id(4),id(6)]);assert.equal(request.expected_context_version,value.context_version);
  assert.equal(request.expected_project_updated_at,version);assert.equal(request.expected_allocation_updated_at,version);
  assert.equal(Object.isFrozen(request.forms_ids),true);assert.throws(()=>routeFormsRequest(value,[id(6)],id(10)),/resposta/);
  assert.throws(()=>routeFormsRequest(value,[id(4),id(5)],id(10)),/alterações/);
  assert.throws(()=>routeFormsRequest(value,[id(4),id(6),id(6)],id(10)),/diferentes/);
  assert.throws(()=>routeFormsRequest(value,[id(4),id(99)],id(10)),/disponível/);
});
test('cell removal requires explicit confirmation and actual eligibility',()=>{
  assert.throws(()=>removeRouteCellRequest(snapshot(),true,id(10)),/resposta/);
  const free={...snapshot(),can_remove_cell:true,remove_reason:null};
  assert.throws(()=>removeRouteCellRequest(free,false,id(10)),/Confirme/);
  const value=removeRouteCellRequest(free,true,id(10));assert.equal(value.action,'remove');assert.equal(value.confirm_change,true);
  assert.equal(manageProjectRouteCellSchema.safeParse({...value,confirm_change:false}).success,false);
  assert.equal(manageProjectRouteCellSchema.safeParse({...value,actor_id:id(20)}).success,false);
  assert.throws(()=>removeRouteCellRequest({...free,allocation:{...free.allocation,retirada:true}},true,id(10)),/Recarregue/);
});
test('route reader validates allocation scope and protects choices before querying',async()=>{
  let value:any=snapshot();const calls:any[]=[];const client={rpc:async(name:string,args:any)=>{calls.push({name,args});return {error:null,data:value};}} as any;
  const limited=createProjectRouteCellData(client,caps.filter(c=>c!=='em.forms.read'));
  await assert.rejects(limited.getProjectRouteCell(id(1),id(2)),/Acesso/);assert.equal(calls.length,0);
  const reader=createProjectRouteCellData(client,caps);assert.equal((await reader.getProjectRouteCell(id(1),id(2)))?.forms.length,2);
  assert.equal((await reader.getProjectRouteCell(id(1),id(2),true))?.forms.length,3);
  for(const bad of [{...snapshot(),allocation:{...snapshot().allocation,projeto_id:id(99)}},{...snapshot(),complete:false},
    {...snapshot(),forms:snapshot().forms.map(f=>({...f,assigned:false}))},{...snapshot(),allocation:{...snapshot().allocation,retirada:true}}]){
    value=bad;await assert.rejects(reader.getProjectRouteCell(id(1),id(2),true),/conferir/);
  }
  value={...snapshot(),private_snapshot:'never',forms:snapshot().forms.map(f=>({...f,internal_payload:'never'}))};
  assert.equal(JSON.stringify(await reader.getProjectRouteCell(id(1),id(2),true)).includes('never'),false);
});
function actionFixture(options:{role?:string;capabilities?:CorporateCapability[];wrong?:boolean}={}){
  const calls:any[]=[];const value=snapshot();
  const access:any={client:{},user:{id:id(80)},profile:{id:id(81),perfil:options.role??'administrador'},sso:{capabilities:options.capabilities??caps}};
  const actions=createProjectRouteCellActions({actionUser:async()=>access,mutate:async(...args)=>{
    calls.push(args);const payload:any=args[2];return {ok:true,data:{operation:'manage_project_route_cell',id:id(2),projeto_id:id(1),updated_at:version,idempotent_replay:false,
      record:{projeto_id:id(1),celula_projeto_id:id(2),action:payload.action,context_version:'b'.repeat(64),changed_ids:[id(2)],
        retirada:payload.action==='remove',forms_ids:options.wrong?[id(99)]:payload.forms_ids??[],private_payload:'never'}}};}});
  return {...actions,calls,value};
}
test('route actions require resource reads and return only the confirmed matching DTO',async()=>{
  const request=routeFormsRequest(snapshot(),[id(4),id(6)],id(10));
  for(const f of [actionFixture({role:'auditor'}),actionFixture({capabilities:caps.filter(c=>c!=='em.forms.read')})]){
    assert.equal((await f.manageProjectRouteCell(request)).ok,false);assert.equal(f.calls.length,0);
  }
  const f=actionFixture();const result=await f.manageProjectRouteCell(request);assert.ok(result.ok);assert.equal(JSON.stringify(result).includes('never'),false);
  assert.equal(f.calls[0][1],'manage_project_route_cell');assert.equal(f.calls[0][3],'em.planning.manage');
  const wrong=await actionFixture({wrong:true}).manageProjectRouteCell(request);assert.equal(wrong.ok,false);if(!wrong.ok)assert.equal(wrong.code,'UNAVAILABLE');
  const removal=removeRouteCellRequest({...snapshot(),can_remove_cell:true},true,id(10));
  const noPhotos=actionFixture({capabilities:caps.filter(c=>c!=='em.photos.read')});assert.equal((await noPhotos.manageProjectRouteCell(removal)).ok,false);assert.equal(noPhotos.calls.length,0);
});
test('executed approvals anchor their cells while unused cells can move inside open intervals',()=>{
  const items=[1,2,3,4,5].map((n,index)=>({id:id(n),updated_at:version,celula_id:id(n+10),celula_nome:String(n),status:'pendente',visibilidade:true,indice:index+1,can_reorder:n!==3}));
  const route:any={project:{id:id(40),updated_at:version},items,route_version:'a'.repeat(64)};
  assert.equal(canMoveProjectRouteItem(route,items,id(1),1),true);assert.equal(canMoveProjectRouteItem(route,items,id(2),3),false);
  assert.equal(canMoveProjectRouteItem(route,items,id(3),4),false);assert.equal(canMoveProjectRouteItem(route,items,id(4),4),true);
  assert.throws(()=>projectRouteRequest(route,[items[2],items[0],items[1],items[3],items[4]],id(20)),/posição/);
});

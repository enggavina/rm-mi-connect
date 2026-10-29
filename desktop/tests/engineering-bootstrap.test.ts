import test from 'node:test';
import assert from 'node:assert/strict';
import { engineeringBootstrapId, engineeringBootstrapSql, prepareEngineeringBootstrap, type EngineeringLookups } from '../src/server/bridge/engineering-bootstrap';
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const at = '2026-10-01T00:00:00.000Z';
const lookup = (): EngineeringLookups => ({
  matrices: [{ id: id(1), bubble_id:'100x1', celula_id:id(2), tipo_equipamento_id:id(3), updated_at:at, sync_source:'bubble' }],
  cells: [{id:id(2),bubble_id:'100x2'},{id:id(4),bubble_id:'100x4'}], users:[{id:id(5),bubble_id:'100x5',status:'ativo'}],
  photos:[],stages:[],options:[{option_set_key:'statusetapa',option_key:'nulo',bubble_display:'Nulo'},
    {option_set_key:'status_cel_proj',option_key:'finalizado',bubble_display:'Finalizado'},
    {option_set_key:'categoriafoto',option_key:'obrigat_ria',bubble_display:'Obrigatória'}],
});
const source = () => ({cutoff:at,photos:[{_id:'100x10','Created Date':at,'Modified Date':at,Celula_Tipo_Equipamento:'100x1',Celula:'100x2',Titulo:'Frontal',Tag:'{{ft_front}}'}] as Record<string,unknown>[],
  stages:[{_id:'100x11','Created Date':at,'Modified Date':at,Celula_Tipo_Equipamento:'100x1',celula_origem:'100x2',celula_destino:'100x4',status_cel_proj:'Finalizado',
    Aprovador:'100x5',Aprovadores:['100x5','100x5'],Aprovadores_retorno:[],Vinculo_entre_celulas:true}] as Record<string,unknown>[]});
test('engineering recovery preserves missing numbering, raw tag and legacy approvers without inventing catalogs or ACL',()=>{
  const plan=prepareEngineeringBootstrap(source(),lookup()), group=plan.groups[0];
  assert.deepEqual(plan.counts,{photos:1,stages:1,parents:1});
  assert.equal(group.photos[0].numero,null);assert.equal(group.photos[0].cadastro_foto_id,null);
  assert.equal(group.photos[0].categoria_foto,null);assert.equal(group.photos[0].identificador_foto_key,null);
  assert.equal(group.photos[0].tag,'{{ft_front}}');assert.equal(group.photos[0].projeto_id,null);
  assert.deepEqual(group.stages[0].aprovadores_ids,[id(5),id(5)]);
  assert.equal(group.stages[0].aprovador_id,id(5));assert.deepEqual(group.stages[0].aprovadores_retorno_ids,[]);
  assert.equal(group.stages[0].status_cel_proj,'finalizado');assert.equal(group.stages[0].status,'nulo');
  assert.deepEqual(prepareEngineeringBootstrap(source(),lookup()),plan);
  assert.notEqual(engineeringBootstrapId('rm_fotos','100x10'),engineeringBootstrapId('rm_aprovacoes_etapas','100x10'));
});
test('engineering recovery rejects allocated or captured records, duplicates, missing references and local ownership',()=>{
  for(const change of [{ProjetoRM:'100x20'},{Celula_Projeto:'100x21'},{foto:'https://example.invalid/photo'},
    {fotos:['photo']},{Celula:'100x99'},{Celula:'100x4'},{Celula_Tipo_Equipamento:'100x99'},
    {'Categoria Foto':'unknown'},{Numero:1.2},{'Modified Date':'2027-01-01'}]) {
    const raw=source();Object.assign(raw.photos[0],change);assert.throws(()=>prepareEngineeringBootstrap(raw,lookup()));
  }
  const raw=source();raw.photos.push({...raw.photos[0]});assert.throws(()=>prepareEngineeringBootstrap(raw,lookup()),/Duplicate/);
  const local=lookup();local.matrices[0].sync_source='supabase';assert.throws(()=>prepareEngineeringBootstrap(source(),local),/Locally/);
  const captured=source();captured.stages[0]['Aprovado por']='100x5';assert.throws(()=>prepareEngineeringBootstrap(captured,lookup()),/Captured/);
  const missing=source();missing.stages[0].Aprovador='100x99';assert.throws(()=>prepareEngineeringBootstrap(missing,lookup()),/Unresolved/);
});
test('engineering bootstrap is rollback by default, insert only and locks a pair before existing-row checks',()=>{
  const raw=source();raw.photos[0].Titulo="'); delete from public.rm_users; --";
  const group=prepareEngineeringBootstrap(raw,lookup()).groups[0], sql=engineeringBootstrapSql(group);
  assert.match(sql,/rollback;\s*$/);assert.doesNotMatch(sql,/delete from public\.rm_users/);
  assert.doesNotMatch(sql,/\bupdate public\.|\bdelete from\b/i);
  assert.ok(sql.indexOf('engineering_pair_lock(')<sql.indexOf('where id=incoming.id'));
  assert.match(sql,/Bootstrap refuses to overwrite/);assert.match(sql,/Engineering changed since/);
  assert.match(engineeringBootstrapSql(group,true),/commit;\s*$/);
});

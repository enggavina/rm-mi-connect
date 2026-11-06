import test from 'node:test';
import assert from 'node:assert/strict';
import type {SupabaseClient} from '@supabase/supabase-js';
import {deleteProjectSchema} from '../src/server/web/project-delete-policy';
import {createProjectDeleteData} from '../src/server/web/project-delete-data';
import {createProjectDeleteCleanup} from '../src/server/web/project-delete-cleanup';

const projectId='abcdef01-2345-4678-8abc-0123456789ab';
const otherId='abcdef02-2345-4678-8abc-0123456789ab';
const submissionId='abcdef03-2345-4678-8abc-0123456789ab';
const leaseId='abcdef04-2345-4678-8abc-0123456789ab';
const version='2026-11-06T18:03:24.123456+00:00';
const context='a'.repeat(64);
const request={submissionId,id:projectId,expected_updated_at:version,expected_context_version:context,confirm_delete:true,justificativa:'Projeto duplicado.'};
const capabilities=['em.portal.read','em.projects.read','em.projects.manage'] as const;
const snapshot={project:{id:projectId,numero:'EM-42',nome:'Motor',updated_at:version},can_delete:true,reason:null,
  counts:{equipment:1,cells:2,photos:3,form_records:4,answers:5,approvals:6,comments:7,notifications:8,documents:9,commercial:0,laboratory:0},
  private_files:1,context_version:context};

test('project deletion requires an explicit confirmation, nonblank justification and both concurrency versions',()=>{
  assert.deepEqual(deleteProjectSchema.parse({...request,id:projectId.toUpperCase(),justificativa:'  Projeto duplicado. \n'}),request);
  const invalid=[
    {...request,confirm_delete:undefined},{...request,confirm_delete:false},
    ...['',' ','\t\n','\u00a0\u2003\ufeff'].map(justificativa=>({...request,justificativa})),
    {...request,justificativa:'Motivo\u0000oculto'},{...request,justificativa:'x'.repeat(2001)},
    {...request,expected_updated_at:undefined},{...request,expected_context_version:undefined},
    {...request,expected_context_version:'a'.repeat(63)},{...request,actor_id:otherId},
  ];
  for(const input of invalid)assert.equal(deleteProjectSchema.safeParse(input).success,false);
});

function dataFixture(response:unknown=snapshot,error:unknown=null,throws=false){
  const calls:{name:string;payload:unknown}[]=[];
  const db={rpc:async(name:string,payload:unknown)=>{calls.push({name,payload});if(throws)throw new Error('private SQL details');return{data:response,error};}} as unknown as SupabaseClient;
  return{db,calls};
}

test('delete discovery checks all granted scopes before querying and never queries invalid project IDs',async()=>{
  for(const allowed of [[],capabilities.slice(0,2),capabilities.slice(1)]){
    const fixture=dataFixture();
    await assert.rejects(createProjectDeleteData(fixture.db,allowed).getProjectDeleteSnapshot(projectId),/Acesso não autorizado/);
    assert.deepEqual(fixture.calls,[]);
  }
  const fixture=dataFixture();
  assert.equal(await createProjectDeleteData(fixture.db,capabilities).getProjectDeleteSnapshot('../another-project'),null);
  assert.deepEqual(fixture.calls,[]);
});

test('delete discovery returns a strictly scoped snapshot with the exact database version',async()=>{
  const fixture=dataFixture();
  const result=await createProjectDeleteData(fixture.db,capabilities).getProjectDeleteSnapshot(projectId.toUpperCase());
  assert.deepEqual(result,snapshot);
  assert.deepEqual(fixture.calls,[{name:'rm_web_project_delete_snapshot_v1',payload:{p_project_id:projectId}}]);
  assert.equal(await createProjectDeleteData(dataFixture(null).db,capabilities).getProjectDeleteSnapshot(projectId),null);
});

test('delete discovery rejects cross-project, contradictory or private/malformed snapshots',async()=>{
  const invalid=[
    {...snapshot,project:{...snapshot.project,id:otherId}},
    {...snapshot,reason:'There are shared records'},
    {...snapshot,private_journal:{payload:'must not escape'}},
    {...snapshot,project:{...snapshot.project,bubble_id:'legacy-secret'}},
    {...snapshot,counts:{...snapshot.counts,photos:-1}},
    {...snapshot,context_version:'bad'},
    {...snapshot,project:{...snapshot.project,updated_at:'yesterday'}},
  ];
  for(const response of invalid){
    await assert.rejects(createProjectDeleteData(dataFixture(response).db,capabilities).getProjectDeleteSnapshot(projectId),/^Error: Não foi possível confirmar o contexto da exclusão\.$/);
  }
  const blocked={...snapshot,can_delete:false,reason:'Um documento possui vínculo com outro projeto.'};
  assert.deepEqual(await createProjectDeleteData(dataFixture(blocked).db,capabilities).getProjectDeleteSnapshot(projectId),blocked);
});

test('delete discovery hides raw RPC and transport errors',async()=>{
  for(const fixture of [dataFixture(null,{message:'private table and SQL'}),dataFixture(null,null,true)]){
    await assert.rejects(createProjectDeleteData(fixture.db,capabilities).getProjectDeleteSnapshot(projectId),/^Error: Não foi possível conferir as dependências deste projeto\.$/);
  }
});

const job={id:otherId,lease_token:leaseId,bucket_id:'rm-documentos',object_path:`web-dossier/${projectId}/${submissionId}.pdf`};
const secondJob={...job,id:submissionId,object_path:`web-dossier/${projectId}/${otherId}.png`};
type CleanupOptions={claim?:unknown;claimError?:unknown;removeErrors?:unknown[];removeThrows?:boolean;ack?:unknown;ackError?:unknown};
function cleanupFixture(options:CleanupOptions={}){
  const rpcCalls:{name:string;payload:unknown}[]=[];
  const removals:{bucket:string;paths:string[]}[]=[];
  const db={
    rpc:async(name:string,payload:unknown)=>{
      rpcCalls.push({name,payload});
      return name==='rm_project_delete_files_claim_v1'
        ?{data:options.claim===undefined?[job]:options.claim,error:options.claimError??null}
        :{data:options.ack===undefined?true:options.ack,error:options.ackError??null};
    },
    storage:{from:(bucket:string)=>({remove:async(paths:string[])=>{
      const index=removals.length;removals.push({bucket,paths});
      if(options.removeThrows)throw new Error('Storage unreachable');
      return{data:null,error:options.removeErrors?.[index]??null};
    }})},
  } as unknown as SupabaseClient;
  return{cleanup:createProjectDeleteCleanup(db),rpcCalls,removals};
}

test('cleanup processes only the leased private files within the requested scope and budget',async()=>{
  const fixture=cleanupFixture({claim:[job,secondJob]});
  assert.deepEqual(await fixture.cleanup.drain(2,submissionId),{claimed:2,completed:2});
  assert.deepEqual(fixture.removals,[{bucket:'rm-documentos',paths:[job.object_path]},{bucket:'rm-documentos',paths:[secondJob.object_path]}]);
  assert.deepEqual(fixture.rpcCalls,[
    {name:'rm_project_delete_files_claim_v1',payload:{p_limit:2,p_submission_id:submissionId}},
    {name:'rm_project_delete_files_finish_v1',payload:{p_id:job.id,p_lease_token:job.lease_token,p_success:true}},
    {name:'rm_project_delete_files_finish_v1',payload:{p_id:secondJob.id,p_lease_token:secondJob.lease_token,p_success:true}},
  ]);
});

test('cleanup handles an empty queue without touching Storage',async()=>{
  const fixture=cleanupFixture({claim:[]});
  assert.deepEqual(await fixture.cleanup.drain(),{claimed:0,completed:0});
  assert.deepEqual(fixture.removals,[]);
});

test('cleanup rejects an invalid service budget or scope before acquiring leases',async()=>{
  for(const limit of [0,6,1.5,NaN,Infinity]){
    const fixture=cleanupFixture();await assert.rejects(fixture.cleanup.drain(limit),/Invalid cleanup budget/);
    assert.deepEqual(fixture.rpcCalls,[]);assert.deepEqual(fixture.removals,[]);
  }
  const fixture=cleanupFixture();await assert.rejects(fixture.cleanup.drain(1,'all-projects'),/Invalid cleanup scope/);
  assert.deepEqual(fixture.rpcCalls,[]);assert.deepEqual(fixture.removals,[]);
});

test('cleanup fails closed on unknown buckets, unsafe paths, duplicate jobs or excess claims',async()=>{
  const claims=[
    [{...job,bucket_id:'public-photos'}],
    [{...job,object_path:`web-dossier/${projectId}/../shared.pdf`}],
    [{...job,object_path:`web-dossier/${projectId}/${submissionId}.exe`}],
    [{...job,object_path:`web-dossier/${'-'.repeat(36)}/${submissionId}.pdf`}],
    [{...job,object_path:`web-dossier/${projectId}/${'-'.repeat(36)}.pdf`}],
    [{...job,unexpected:'private payload'}],
    [job,{...secondJob,id:job.id}],
    [job,{...secondJob,object_path:job.object_path}],
    Array(6).fill(job),
  ];
  for(const claim of claims){
    const fixture=cleanupFixture({claim});await assert.rejects(fixture.cleanup.drain(5),/Invalid cleanup claim/);
    assert.deepEqual(fixture.removals,[]);assert.equal(fixture.rpcCalls.length,1);
  }
  const overBudget=cleanupFixture({claim:[job,secondJob]});
  await assert.rejects(overBudget.cleanup.drain(1),/Invalid cleanup claim/);
  assert.deepEqual(overBudget.removals,[]);
});

test('cleanup reports missing files as complete and retains failed files for the durable retry',async()=>{
  for(const error of [{statusCode:404},{statusCode:'404'}]){
    const fixture=cleanupFixture({removeErrors:[error]});
    assert.deepEqual(await fixture.cleanup.drain(1),{claimed:1,completed:1});
    assert.deepEqual(fixture.rpcCalls[1].payload,{p_id:job.id,p_lease_token:job.lease_token,p_success:true});
  }
  for(const options of [{removeErrors:[{statusCode:503,message:'temporarily unavailable'}]},{removeThrows:true}]){
    const fixture=cleanupFixture(options);
    assert.deepEqual(await fixture.cleanup.drain(1),{claimed:1,completed:0});
    assert.deepEqual(fixture.rpcCalls[1].payload,{p_id:job.id,p_lease_token:job.lease_token,p_success:false});
  }
});

test('cleanup never treats an unconfirmed lease completion as successful or processes the next job',async()=>{
  for(const options of [{ack:false},{ack:null},{ackError:{message:'lease no longer held'}}]){
    const fixture=cleanupFixture({...options,claim:[job,secondJob]});
    await assert.rejects(fixture.cleanup.drain(2),/^Error: Cleanup confirmation unavailable$/);
    assert.equal(fixture.removals.length,1);assert.equal(fixture.rpcCalls.length,2);
  }
  const unavailable=cleanupFixture({claimError:{message:'private SQL'}});
  await assert.rejects(unavailable.cleanup.drain(1),/^Error: Cleanup unavailable$/);
  assert.deepEqual(unavailable.removals,[]);
});

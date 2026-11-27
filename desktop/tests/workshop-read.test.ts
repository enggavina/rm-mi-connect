import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createFormTemplateData } from '../src/server/web/form-template-data';
import { createWebData } from '../src/server/web/data';
import { createCatalogWorkshopAuthorizer } from '../src/server/web/catalog-workshop';
import { checkedWorkshopPage, workshopReadResult, type WorkshopRead, type WorkshopReadResource } from '../src/server/web/workshop-read-policy';
import { CORPORATE_ISSUER, CorporateAuthError, type CorporateCapability, type VerifiedCorporateSession } from '../src/server/web/sso-policy';
import { WorkshopContextError, type WorkshopContext } from '../src/server/web/workshop-context';
import type { SsoContext } from '../src/server/web/auth-policy';
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const caps: CorporateCapability[] = ['em.portal.read','em.catalogs.read','em.catalogs.manage','em.form_templates.read'];
const legacyForbidden = { from() { assert.fail('unscoped query'); }, rpc() { assert.fail('old RPC'); } } as unknown as SupabaseClient;
const version = '2026-11-18T12:00:00.123456+00:00';
const content = { titulo: 'LOCAL template', descricao: null, title: null, description: null, tipo: null, questions: [] };
const draft = { id:id(1),family_id:id(1),kind:'new',state:'draft',source_form_id:null,source_version:null,published_form_id:null,content,
  source_snapshot:{usa_aprovacao:true,has_cover:true,links_redacted:true},created_at:version,updated_at:version };

test('catalog list and entry use scoped RPC results without raw table/version requests', async () => {
  const calls: unknown[] = [];
  const read: WorkshopRead = async (resource,args) => { calls.push([resource,args]); return resource === 'catalog_entry' ? { id:id(1),nome:'LOCAL' } : { rows:[{id:id(1),nome:'LOCAL'}],total:1,page:2,pageSize:50 }; };
  const data=createWebData(legacyForbidden,caps,read);
  const result=await data.getCatalogs({kind:'clients',q:' %LOCAL_ ',page:2});
  assert.equal(result.total,1); assert.equal(result.kind,'clients');
  assert.equal((await data.getCatalogEntry('types',id(1)))?.id,id(1));
  assert.equal(await data.getCatalogEntry('types','bad'),null);
  assert.deepEqual(calls,[['catalog_list',{kind:'clients',q:'LOCAL',page:2}],['catalog_entry',{kind:'types',id:id(1)}]]);
});
test('Equipe uses a separate exact request and refreshes membership for each search', async () => {
  const viewer = id(1), current: SsoContext = { subject: viewer, bindingId: id(2), sessionHash: 'LOCAL', capabilities: caps };
  const corporate: VerifiedCorporateSession = { accessToken: 'synthetic.jwt.signature', user: { id: viewer, email: 'qa@example.invalid' },
    expiresAt: Date.now() + 60_000, decision: { application: 'em', issuer: CORPORATE_ISSUER, subject: viewer, app_access: true,
      capabilities: caps, all_employees: false, fields: [], export_allowed: false } };
  const context: WorkshopContext = { version: 2, application: 'em', channel: 'web', authority: CORPORATE_ISSUER,
    workshop: { id: id(3), code: 'BMA', name: 'BMA', active: true, revision: 1, updated_at: version },
    principals: [{ kind: 'corporate', issuer: CORPORATE_ISSUER, subject: viewer, revision: 1 }], issued_at: version, expires_at: version };
  let hasOperator = true;
  const authorizer = createCatalogWorkshopAuthorizer({ reader: {
    async readWeb() { assert.fail('Unscoped roster fallback'); },
    async readTeam(s) {
      assert.equal(s, corporate);
      return { context, members: [{ kind: 'corporate', subject: viewer }, ...(hasOperator ? [{ kind: 'operator' as const, subject: id(4) }] : [])] };
    },
  }, async mint() { assert.fail('No writes'); }, async mintRead(value) {
    assert.equal(value.resource, 'workshop_team'); assert.equal(value.context, context);
  } });
  authorizer.remember(current, corporate);
  const first = await authorizer.authorizeTeamRead(current, id(10), { q: 'operador', page: 1, members: [{ kind: 'operator', subject: id(5) }] });
  assert.deepEqual(first, { office: id(3), args: { q: 'operador', page: 1,
    members: [{ kind: 'corporate', subject: viewer }, { kind: 'operator', subject: id(4) }] } });
  hasOperator = false;
  const data = createWebData(legacyForbidden, caps, async (resource, args) => {
    assert.equal(resource, 'workshop_team'); assert.deepEqual(args, { q: 'operador', page: 1 });
    const roster = await authorizer.authorizeTeamRead(current, id(11), args);
    assert.deepEqual(roster.args.members, [{ kind: 'corporate', subject: viewer }]);
    return { rows: [], total: 0, page: 1, pageSize: 50 };
  });
  assert.equal((await data.getCatalogs({ kind: 'users', q: 'operador' })).total, 0);
  await assert.rejects(authorizer.authorizeRead(current, id(9), 'workshop_team', {}), CorporateAuthError);
});
test('model lists and snapshots retain versions while reducing source metadata', async () => {
  const calls: unknown[]=[];
  const read: WorkshopRead = async(resource,args)=>{
    calls.push([resource,args]);
    if(resource==='template_list') return {drafts:[{id:id(1)}],published:[],draftTotal:1,publishedTotal:0,page:1,pageSize:25};
    if(resource==='template_draft') return {draft,publication:null};
    if(resource==='template_form') return {form:{id:id(2),titulo:'LOCAL',ativo:true,updated_at:version},content,source_snapshot:draft.source_snapshot,version:7,family_id:id(1)};
    return [{option_set_key:'tipo_quest_o',option_key:'texto_curto',bubble_display:'Texto curto',sort_order:1}];
  };
  const data=createFormTemplateData(legacyForbidden,caps,read);
  assert.equal((await data.listFormTemplates({state:'bad'})).draftTotal,1);
  const snapshot=await data.getFormTemplate(id(1));assert.equal(snapshot?.draft.updated_at,version);assert.equal(snapshot?.draft.source_snapshot.has_cover,true);assert.equal(snapshot?.draft.source_snapshot.links_redacted,true);
  assert.equal((await data.getPublishedFormTemplate(id(2)))?.version,7);
  assert.equal((await data.getFormTemplateChoices()).questionTypes.length,1);
  assert.deepEqual(calls.map(c=>(c as unknown[])[0]),['template_list','template_draft','template_form','template_choices']);
  assert.equal(JSON.stringify(snapshot).includes('imagem_capa_url'),false);
});
test('scope failures never retry through unscoped queries or fabricate empty lists', async () => {
  const error=new WorkshopContextError('WORKSHOP_UNAVAILABLE');
  const read:WorkshopRead=async()=>{throw error;};
  const catalogs=createWebData(legacyForbidden,caps,read),models=createFormTemplateData(legacyForbidden,caps,read);
  for(const action of [()=>catalogs.getCatalogs(),()=>catalogs.getCatalogEntry('clients',id(1)),()=>models.listFormTemplates(),()=>models.getFormTemplate(id(1)),()=>models.getPublishedFormTemplate(id(1)),()=>models.getFormTemplateChoices()]) await assert.rejects(action(),e=>e===error);
});
test('wrong page, duplicate rows, impossible totals, wrong identities and response office are refused', async () => {
  const page={rows:[{id:id(1)}],total:1,page:1,pageSize:50};
  for(const patch of [{page:2},{total:0},{rows:[{id:id(1)},{id:id(1)}]},{rows:[{id:'bad'}]},{total:NaN}]) assert.throws(()=>checkedWorkshopPage({...page,...patch},1,50));
  const expected={requestId:id(1),resource:'template_form' as const,workshopId:id(2)};
  const envelope={request_id:id(1),resource:'template_form',workshop_id:id(2),data:null};
  assert.equal(workshopReadResult(envelope,expected),null);
  for(const patch of [{request_id:id(3)},{resource:'catalog_list'},{workshop_id:id(3)}]) assert.throws(()=>workshopReadResult({...envelope,...patch},expected));
  const data=createFormTemplateData(legacyForbidden,caps,async()=>({draft:{...draft,id:id(3)},publication:null}));
  await assert.rejects(data.getFormTemplate(id(1)));
});
test('read authorizer requires verified request identity and every required capability, consulting current authority each time', async () => {
  const context:SsoContext={subject:id(1),bindingId:id(2),sessionHash:'LOCAL',capabilities:[...caps]};
  const corporate:VerifiedCorporateSession={accessToken:'synthetic.jwt.signature',user:{id:id(1),email:'qa@example.invalid'},expiresAt:Date.now()+60000,
    decision:{application:'em',issuer:CORPORATE_ISSUER,subject:id(1),app_access:true,capabilities:[...caps],all_employees:false,fields:[],export_allowed:false}};
  const workshop:WorkshopContext={version:2,application:'em',channel:'web',authority:CORPORATE_ISSUER,workshop:{id:id(3),code:'BMA',name:'BMA',active:true,revision:1,updated_at:version},principals:[{kind:'corporate',issuer:CORPORATE_ISSUER,subject:id(1),revision:1}],issued_at:version,expires_at:version};
  let reads=0,mints=0;
  const authorizer=createCatalogWorkshopAuthorizer({reader:{async readWeb(s){assert.equal(s,corporate);reads++;return workshop;}},async mint(){assert.fail('no mutation permit');},async mintRead(args){mints++;assert.equal(args.sessionHash,'LOCAL');assert.equal(args.context,workshop);}});
  authorizer.remember(context,corporate);
  for(const resource of ['catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices'] as WorkshopReadResource[]) assert.equal(await authorizer.authorizeRead(context,id(4),resource,{}),id(3));
  assert.equal(reads,6);assert.equal(mints,6);assert.equal(JSON.stringify(context).includes(corporate.accessToken),false);
  await assert.rejects(authorizer.authorizeRead({...context},id(4),'catalog_list',{}),CorporateAuthError);
  context.capabilities=['em.catalogs.manage'];await assert.rejects(authorizer.authorizeRead(context,id(4),'catalog_entry',{}),CorporateAuthError);assert.equal(reads,6);
});

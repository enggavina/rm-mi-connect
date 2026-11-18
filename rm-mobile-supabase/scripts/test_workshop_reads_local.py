"""Disposable PostgreSQL only: scoped readers, preservation, and real races."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timezone,timedelta
from threading import Barrier
import hashlib,json,os,shutil,socket,subprocess,tempfile,time
from pathlib import Path
import psycopg
from psycopg.types.json import Jsonb
import prepare_workshop_reads_release as release
from test_workshop_ownership_local import execute,OFFICES,DECLARATION
ROOT=release.ROOT
def key(n):return f'05900000-0000-4000-8000-{n:012d}'
def main():
 root=Path(tempfile.mkdtemp(prefix='em-workshop-reads-test-')).resolve();data=root/'data';running=False;success=False;checks=[]
 flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0;programs={n:shutil.which(n) for n in ['initdb','pg_ctl','createdb','psql']}
 if not all(programs.values()):raise RuntimeError('PostgreSQL binaries required')
 def command(cmd):
  with(root/'commands.log').open('ab') as output:r=subprocess.run(cmd,stdout=output,stderr=output,creationflags=flags,timeout=180)
  if r.returncode:raise RuntimeError('Local PostgreSQL failed: '+str(root/'commands.log'))
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 def dsn(db):return f'host=127.0.0.1 port={port} dbname={db} user=postgres'
 def bootstrap(db,through):
  command([programs['createdb'],'-h','127.0.0.1','-p',str(port),'-U','postgres',db])
  with psycopg.connect(dsn(db),autocommit=True) as c:
   execute(c,(ROOT/'tests/bootstrap.sql').read_text(encoding='utf-8'))
   for f in sorted((ROOT/'migrations').glob('*.sql')):
    if f.name[:3]<=through:execute(c,f.read_text(encoding='utf-8'))
 try:
  print('LOCAL: scoped portal reads PostgreSQL, synthetic data only',flush=True)
  command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
  command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
  bootstrap('read_contracts','059')
  command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','read_contracts','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests/web_workshop_reads.sql')])
  checks.append('two_offices_search_counts_pages_nested_redaction_unknown_metadata_one_use_body_session_mfa_roles_logout')
  with psycopg.connect(dsn('read_contracts'),autocommit=True) as c:c.execute("set search_path=''");manifest=c.execute(release.MANIFEST_QUERY).fetchone()[0]
  manifest_bytes=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
  if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Review changed read manifest')
  release.MANIFEST.write_bytes(manifest_bytes);source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
  bootstrap('read_release','058')
  with psycopg.connect(dsn('read_release'),autocommit=True) as c:
   c.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
   for f in sorted((ROOT/'migrations').glob('*.sql')):
    if f.name[:3]<'059':c.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(f.name[:3],f.stem[4:],[] if f.name[:3]<='017' else [f.read_text(encoding='utf-8')]))
   c.execute("insert into public.rm_clientes(id,nome) values(%s,'LOCAL preservation client')",(key(101),))
   rehearsal=release.release_sql(source_hash,manifest_hash);assert execute(c,rehearsal)['old_functions_preserved']
   assert c.execute("select to_regclass('rm_private.workshop_read_permits')").fetchone()[0] is None
   checks.append('preservation_rehearsal_reverts_all_objects_without_business_edits')
   sabotages=["update public.rm_clientes set nome='TAMPERED';",'grant select on rm_private.workshop_read_permits to authenticated;',
    'grant execute on function public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb) to authenticated;',
    'grant execute on function public.rm_web_workshop_read_v1(uuid,text,jsonb) to service_role;',
    'alter function rm_private.workshop_read_data_v1(text,jsonb,uuid) security definer;',
    'alter function public.rm_web_mutate_v1(uuid,text,jsonb) security invoker;',
    'create index unwanted_read_index on public.rm_clientes(nome);',
    "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",'create table storage.unwanted_read_table(id int);',
    'alter table public.rm_forms disable trigger workshop_catalog_lifecycle;']
   for sabotage in sabotages:
    try:execute(c,rehearsal.replace('do $verify$',sabotage+'\ndo $verify$',1))
    except psycopg.Error as e:c.execute('rollback');assert e.sqlstate=='P0001',(e.sqlstate,str(e))
    else:raise AssertionError('Read sabotage accepted: '+sabotage)
   checks.append('ten_data_acl_function_body_trigger_index_and_history_sabotages_rejected')
   assert execute(c,release.release_sql(source_hash,manifest_hash,apply=True))['old_rows_preserved']
   c.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,0,0)',(Jsonb(OFFICES),DECLARATION))
   c.execute('insert into auth.users(id) values(%s)',(key(11),));c.execute("insert into public.rm_users(id,auth_user_id,nome,perfil) values(%s,%s,'LOCAL read admin','administrador')",(key(12),key(11)))
   c.execute('insert into auth.sessions(id,user_id) values(%s,%s)',(key(13),key(11)))
   c.execute("insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values(%s,'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',%s,%s,%s,true,%s,clock_timestamp())",(key(15),key(14),key(12),key(11),key(12)))
   c.execute("select public.rm_sso_session_put_v1(%s,%s,%s,%s,clock_timestamp()+interval '30 minutes')",('6'*64,key(15),key(13),'opaque-local-read-session'))
   c.execute("insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',%s,%s)",(key(101),OFFICES[0]['id']))
  args={'kind':'clients','q':'','page':1}
  def mint(c,rid,resource='catalog_list',filters=None):
   stamp=datetime.now(timezone.utc);issuer='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
   context={'version':2,'application':'em','channel':'web','authority':issuer,'workshop':{'id':OFFICES[0]['id'],'code':'BMA','name':'LOCAL office','active':True,'revision':1,'updated_at':stamp.isoformat()},
    'principals':[{'kind':'corporate','issuer':issuer,'subject':key(14),'revision':1}],'issued_at':stamp.isoformat(),'expires_at':(stamp+timedelta(minutes=5)).isoformat()}
   c.execute('select public.rm_sso_workshop_read_permit_v1(%s,%s,%s,%s,%s)',('6'*64,rid,resource,Jsonb(args if filters is None else filters),Jsonb(context)))
  def consume(rid,barrier=None,application='em_workshop_read'):
   with psycopg.connect(dsn('read_release')+' application_name='+application,autocommit=True) as c:
    c.execute("set role authenticated;set statement_timeout='6s'");c.execute("select set_config('request.jwt.claim.sub',%s,false)",(key(11),));c.execute("select set_config('request.jwt.claims',%s,false)",(json.dumps({'session_id':key(13),'aal':'aal1'}),))
    if barrier:barrier.wait(timeout=5)
    try:
     value=c.execute('select public.rm_web_workshop_read_v1(%s,%s,%s)',(rid,'catalog_list',Jsonb(args))).fetchone()[0]
     assert value['data']['total']==1 and len(value['data']['rows'])==1
     return '00000'
    except psycopg.Error as e:return e.sqlstate
  with psycopg.connect(dsn('read_release'),autocommit=True) as c,psycopg.connect(dsn('read_release')) as held:
   mint(c,key(601));barrier=Barrier(2)
   with ThreadPoolExecutor(2) as pool:
    a=pool.submit(consume,key(601),barrier);b=pool.submit(consume,key(601),barrier);assert sorted([a.result(timeout=7),b.result(timeout=7)])==['00000','42501']
   checks.append('real_concurrent_consumption_returns_data_once_and_denies_replay')
   mint(c,key(602));c.execute("update rm_private.workshop_read_permits set expires_at=clock_timestamp()+interval '2 seconds' where read_id=%s",(key(602),))
   held.execute('lock table public.rm_clientes in access exclusive mode')
   with ThreadPoolExecutor(1) as pool:
    waiting=pool.submit(consume,key(602),None,'em_delayed_read');deadline=time.monotonic()+1.5
    while time.monotonic()<deadline:
     c.execute('select pg_stat_clear_snapshot()')
     if c.execute("select exists(select 1 from pg_stat_activity where application_name='em_delayed_read' and wait_event_type='Lock')").fetchone()[0]:break
     time.sleep(.02)
    else:raise AssertionError('Read did not reach data lock')
    time.sleep(2.1);held.rollback();assert waiting.result(timeout=4)=='42501'
   assert c.execute('select exists(select 1 from rm_private.workshop_read_permits where read_id=%s)',(key(602),)).fetchone()[0]
   checks.append('real_expiry_during_data_wait_returns_no_data_and_rolls_back_consumption')
   # Local-only pause after the actual visibility decision. A concurrent legacy
   # version insertion must not change the detail snapshot after authorization.
   c.execute("insert into public.rm_forms(id,titulo) values(%s,'LOCAL stable snapshot form')",(key(301),))
   c.execute("insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('form_model',%s,%s)",(key(301),OFFICES[0]['id']))
   c.execute('insert into public.rm_form_template_families(id,created_by) values(%s,%s)',(key(777),key(12)))
   original=c.execute("select pg_get_functiondef('rm_private.workshop_read_visible_v1(text,uuid,uuid)'::regprocedure)").fetchone()[0]
   c.execute(original.replace('rm_private.workshop_read_visible_v1(','rm_private.local_visible_original_v1('))
   c.execute("revoke all on function rm_private.local_visible_original_v1(text,uuid,uuid) from public,anon,authenticated,service_role")
   c.execute("""create or replace function rm_private.workshop_read_visible_v1(p_kind text,p_id uuid,p_office uuid) returns boolean language plpgsql stable set search_path='' as $$
    declare allowed boolean;begin allowed:=rm_private.local_visible_original_v1(p_kind,p_id,p_office);
    if p_kind='form_model' and p_id='05900000-0000-4000-8000-000000000301' then perform pg_advisory_xact_lock(5959,11);end if;return allowed;end$$;""")
   mint(c,key(604),'template_form',{'id':key(301)})
   held.execute('select pg_advisory_xact_lock(5959,11)')
   def detail():
    with psycopg.connect(dsn('read_release')+' application_name=em_snapshot_read',autocommit=True) as other:
     other.execute("set role authenticated;set statement_timeout='6s'");other.execute("select set_config('request.jwt.claim.sub',%s,false)",(key(11),));other.execute("select set_config('request.jwt.claims',%s,false)",(json.dumps({'session_id':key(13),'aal':'aal1'}),))
     return other.execute('select public.rm_web_workshop_read_v1(%s,%s,%s)',(key(604),'template_form',Jsonb({'id':key(301)}))).fetchone()[0]['data']
   with ThreadPoolExecutor(1) as pool:
    waiting=pool.submit(detail);deadline=time.monotonic()+2
    while time.monotonic()<deadline:
     c.execute('select pg_stat_clear_snapshot()')
     if c.execute("select exists(select 1 from pg_stat_activity where application_name='em_snapshot_read' and wait_event_type='Lock')").fetchone()[0]:break
     time.sleep(.02)
    else:raise AssertionError('Snapshot did not reach visibility pause')
    held.execute('insert into public.rm_form_template_versions(family_id,version,form_id,legacy,published_by) values(%s,77,%s,true,%s)',(key(777),key(301),key(12)));held.commit()
    snapshot=waiting.result(timeout=5);assert snapshot['version']==1 and snapshot['family_id'] is None,snapshot
   c.execute(original);c.execute('drop function rm_private.local_visible_original_v1(text,uuid,uuid)')
   checks.append('real_detail_visibility_and_snapshot_are_atomic_during_concurrent_version_insertion')
   mint(held,key(603))
   def logout():
    with psycopg.connect(dsn('read_release'),autocommit=True) as other:other.execute("set statement_timeout='4s'");other.execute('select public.rm_sso_session_delete_v1(%s)',('6'*64,))
   with ThreadPoolExecutor(1) as pool:
    waiting=pool.submit(logout);time.sleep(.2);assert not waiting.done();held.commit();waiting.result(timeout=5)
   assert c.execute('select count(*) from rm_private.workshop_read_permits').fetchone()[0]==0
   checks.append('real_issuance_logout_order_cascades_all_read_permits')
  names=['prepare_workshop_reads_release.py','test_workshop_reads_local.py','prepare_workshop_ownership_release.py','prepare_workshop_reference_release.py','test_workshop_ownership_local.py']
  support={n:hashlib.sha256((ROOT/'scripts'/n).read_bytes()).hexdigest() for n in names};support['web_workshop_reads.sql']=hashlib.sha256((ROOT/'tests/web_workshop_reads.sql').read_bytes()).hexdigest()
  proof={'local_only':True,'production_data_copied':False,'source_sha256':source_hash,'manifest_sha256':manifest_hash,'passed':len(checks),'checks':checks,'support_sha256':support}
  (ROOT.parent/'.tmp/workshop-reads-local-proof.json').write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8');print(json.dumps(proof),flush=True);success=True
 finally:
  if running:command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
  if success:
   if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-workshop-reads-test-'):raise RuntimeError('Unexpected cleanup target')
   shutil.rmtree(root)
  else:print('Local diagnostics preserved at '+str(root),flush=True)
if __name__=='__main__':main()

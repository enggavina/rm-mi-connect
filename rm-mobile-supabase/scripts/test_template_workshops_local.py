"""Disposable PG only: template origins, publication, preservation and real races."""
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,os,shutil,socket,subprocess,tempfile,time
from pathlib import Path
from datetime import datetime,timezone,timedelta
import psycopg
from psycopg.types.json import Jsonb
import prepare_template_workshops_release as release
from test_workshop_ownership_local import execute,OFFICES,DECLARATION
ROOT=release.ROOT
def key(n):return f'05800000-0000-4000-8000-{n:012d}'
def main():
    root=Path(tempfile.mkdtemp(prefix='em-template-workshops-test-')).resolve();data=root/'data';running=False;success=False;checks=[]
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0;programs={n:shutil.which(n) for n in ['initdb','pg_ctl','createdb','psql']}
    if not all(programs.values()):raise RuntimeError('PostgreSQL binaries required')
    def command(cmd):
        with (root/'commands.log').open('ab') as output:r=subprocess.run(cmd,stdout=output,stderr=output,creationflags=flags,timeout=180)
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
        print('LOCAL: isolated template workshops PostgreSQL; no production data',flush=True)
        command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
        command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
        bootstrap('template_contracts','058')
        command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','template_contracts','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests/web_template_workshops.sql')])
        checks.append('create_copy_version_save_publish_delete_replay_legacy_source_adoption_rollback_expiry_mfa_logout')
        with psycopg.connect(dsn('template_contracts'),autocommit=True) as c:
            c.execute("set search_path=''");manifest=c.execute(release.MANIFEST_QUERY).fetchone()[0]
        manifest_bytes=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
        if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Review changed template manifest')
        release.MANIFEST.write_bytes(manifest_bytes)
        source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
        bootstrap('template_release','057')
        with psycopg.connect(dsn('template_release'),autocommit=True) as c:
            c.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for f in sorted((ROOT/'migrations').glob('*.sql')):
                if f.name[:3]<'058':c.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(f.name[:3],f.stem[4:],[] if f.name[:3]<='017' else [f.read_text(encoding='utf-8')]))
            c.execute('insert into auth.users(id) values(%s)',(key(11),));c.execute("insert into public.rm_users(id,auth_user_id,nome,perfil) values(%s,%s,'LOCAL template admin','administrador')",(key(12),key(11)))
            c.execute('insert into auth.sessions(id,user_id) values(%s,%s)',(key(13),key(11)))
            c.execute("insert into public.rm_forms(id,titulo) values(%s,'LOCAL source')",(key(20),))
            c.execute('insert into public.rm_form_template_families(id,created_by) values(%s,%s)',(key(21),key(12)))
            c.execute("insert into public.rm_form_template_drafts(id,family_id,kind,content,source_snapshot,created_by,updated_by) values(%s,%s,'new',%s,%s,%s,%s)",
              (key(21),key(21),Jsonb({'titulo':'','descricao':None,'title':None,'description':None,'tipo':None,'questions':[]}),Jsonb({'usa_aprovacao':True,'imagem_capa_url':None,'celulas_ids':[],'equipes_ids':[]}),key(12),key(12)))
            c.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,0,0)',(Jsonb(OFFICES),DECLARATION))
            c.execute("select rm_private.workshop_catalog_adopt_bma_v1('f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff',0,0,1)")
            rehearsal=release.release_sql(source_hash,manifest_hash,1,1)
            assert execute(c,rehearsal)['template_seed_verified'];assert c.execute("select to_regclass('rm_private.workshop_template_ownership')").fetchone()[0] is None
            checks.append('preservation_rehearsal_rolls_back_schema_and_reviewed_seed')
            sabotages=["update public.rm_form_template_drafts set content=content||'{\"titulo\":\"TAMPERED\"}';",
             'grant select on rm_private.workshop_template_ownership to authenticated;',
             'grant execute on function public.rm_sso_template_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to authenticated;',
             'alter function public.rm_web_mutate_v1(uuid,text,jsonb) security invoker;',
             'alter table public.rm_form_template_drafts disable trigger workshop_template_lifecycle;',
             'create index unwanted_template_index on public.rm_forms(titulo);',
             "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",
             'create table storage.unwanted_template_table(id int);',
             "update rm_private.template_workshop_write_settings set runtime_sha=repeat('a',40);",
             "create or replace function public.rm_web_mutate_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin return '{}'::jsonb;end$$;"]
            for sabotage in sabotages:
                try:execute(c,rehearsal.replace('do $verify$',sabotage+'\ndo $verify$',1))
                except psycopg.Error as e:c.execute('rollback');assert e.sqlstate=='P0001',(e.sqlstate,str(e))
                else:raise AssertionError('Template sabotage accepted: '+sabotage)
            checks.append('ten_data_acl_body_trigger_index_history_seed_sabotages_rejected')
            assert execute(c,release.release_sql(source_hash,manifest_hash,1,1,apply=True))['old_rows_preserved']
            c.execute("insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values(%s,'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',%s,%s,%s,true,%s,clock_timestamp())",(key(15),key(14),key(12),key(11),key(12)))
            c.execute('select public.rm_sso_session_put_v1(%s,%s,%s,%s,clock_timestamp()+interval \'30 minutes\')',('8'*64,key(15),key(13),'opaque-local-template-session'))
            c.execute('update rm_private.sso_settings set require_sso=true');c.execute('select rm_private.activate_catalog_workshop_writes_v1(%s,%s)',('a'*40,key(90)));c.execute('select rm_private.activate_template_workshop_writes_v1(%s,%s)',('a'*40,key(90)))
        payload={'id':key(61),'kind':'new','source_form_id':None}
        def mint(c):
            stamp=datetime.now(timezone.utc)
            ctx={'version':2,'application':'em','channel':'web','authority':'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
             'workshop':{'id':OFFICES[0]['id'],'code':'BMA','name':'LOCAL office','active':True,'revision':1,'updated_at':stamp.isoformat()},
             'principals':[{'kind':'corporate','issuer':'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','subject':key(14),'revision':1}],
             'issued_at':stamp.isoformat(),'expires_at':(stamp+timedelta(minutes=5)).isoformat()}
            c.execute('select public.rm_sso_template_workshop_permit_v1(%s,%s,%s,%s,%s)',('8'*64,key(62),'create_form_template',Jsonb(payload),Jsonb(ctx)))
        def call(c):
            c.execute("set role authenticated;set statement_timeout='6s'");c.execute("select set_config('request.jwt.claim.sub',%s,false)",(key(11),));c.execute("select set_config('request.jwt.claims',%s,false)",(json.dumps({'session_id':key(13),'aal':'aal1'}),))
            try:c.execute('select public.rm_web_mutate_v1(%s,%s,%s)',(key(62),'create_form_template',Jsonb(payload)))
            except psycopg.Error as e:return e.sqlstate
            raise AssertionError('Expected template conflict')
        with psycopg.connect(dsn('template_release'),autocommit=True) as c,psycopg.connect(dsn('template_release')) as held:
            mint(c);held.execute("select pg_advisory_xact_lock(hashtextextended('em:workshop-template:v1:draft:'||%s,0))",(key(61),))
            assert call(c)=='PT409';c.execute('reset role');held.rollback();checks.append('real_second_connection_origin_lock_preserves_all_rows')
            c.execute("update rm_private.template_workshop_write_permits set expires_at=clock_timestamp()+interval '2 seconds' where submission_id=%s",(key(62),))
            held.execute("select pg_advisory_xact_lock(hashtextextended('form-draft:'||%s,19))",(key(61),))
            def delayed():
                with psycopg.connect(dsn('template_release')+' application_name=em_template_delayed',autocommit=True) as other:return call(other)
            with ThreadPoolExecutor(1) as pool:
                waiting=pool.submit(delayed);deadline=time.monotonic()+1.5
                while time.monotonic()<deadline:
                    c.execute('select pg_stat_clear_snapshot()')
                    if c.execute("select exists(select 1 from pg_stat_activity where application_name='em_template_delayed' and wait_event_type='Lock')").fetchone()[0]:break
                    time.sleep(.02)
                else:raise AssertionError('Writer did not reach core wait')
                time.sleep(2.1);held.rollback();assert waiting.result(timeout=4)=='42501'
            for table,column in [('public.rm_form_template_drafts','id'),('public.rm_form_template_families','id'),('rm_private.web_mutation_receipts','client_submission_id')]:
                assert not c.execute(f'select exists(select 1 from {table} where {column}=%s)',(key(62) if 'receipts' in table else key(61),)).fetchone()[0]
            checks.append('real_expiry_after_core_wait_rolls_back_draft_family_receipt_and_origin')
            mint(held)
            def logout():
                with psycopg.connect(dsn('template_release'),autocommit=True) as other:other.execute("set statement_timeout='4s'");other.execute('select public.rm_sso_session_delete_v1(%s)',('8'*64,))
            with ThreadPoolExecutor(1) as pool:
                waiting=pool.submit(logout);time.sleep(.2);assert not waiting.done();held.commit();waiting.result(timeout=5)
            assert c.execute('select count(*) from rm_private.template_workshop_write_permits').fetchone()[0]==0
            checks.append('real_issuer_logout_order_removes_template_and_action_permits')
        names=['prepare_template_workshops_release.py','test_template_workshops_local.py','prepare_catalog_writes_release.py','prepare_workshop_ownership_release.py','prepare_workshop_reference_release.py','test_workshop_ownership_local.py']
        support={n:hashlib.sha256((ROOT/'scripts'/n).read_bytes()).hexdigest() for n in names};support['web_template_workshops.sql']=hashlib.sha256((ROOT/'tests/web_template_workshops.sql').read_bytes()).hexdigest()
        proof={'local_only':True,'production_data_copied':False,'source_sha256':source_hash,'manifest_sha256':manifest_hash,'passed':len(checks),'checks':checks,'support_sha256':support}
        (ROOT.parent/'.tmp/template-workshops-local-proof.json').write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8');print(json.dumps(proof),flush=True);success=True
    finally:
        if running:command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
        if success:
            if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-template-workshops-test-'):raise RuntimeError('Unexpected cleanup target')
            shutil.rmtree(root)
        else:print('Local diagnostics preserved at '+str(root),flush=True)
if __name__=='__main__':main()

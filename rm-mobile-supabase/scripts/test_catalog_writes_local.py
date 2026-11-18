"""Disposable PG, scoped catalog contract and pinned preservation envelope."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import psycopg
import prepare_catalog_writes_release as release
from test_workshop_ownership_local import execute

ROOT=release.ROOT
def key(n):return f'05700000-0000-4000-8000-{n:012d}'
def main():
    root=Path(tempfile.mkdtemp(prefix='em-catalog-writes-test-')).resolve();data=root/'data';running=False;success=False
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    programs={n:shutil.which(n) for n in ['initdb','pg_ctl','createdb','psql']}
    if not all(programs.values()):raise RuntimeError('PostgreSQL binaries required')
    checks=[]
    def command(cmd):
        with (root/'commands.log').open('ab') as output:r=subprocess.run(cmd,stdout=output,stderr=output,creationflags=flags,timeout=180)
        if r.returncode:raise RuntimeError('Local PostgreSQL failed: '+str(root/'commands.log'))
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    dsn=f'host=127.0.0.1 port={port} dbname=catalog_writes user=postgres'
    try:
        print('LOCAL: disposable scoped catalog PostgreSQL, no production data',flush=True)
        command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
        command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
        command([programs['createdb'],'-h','127.0.0.1','-p',str(port),'-U','postgres','catalog_writes'])
        with psycopg.connect(dsn,autocommit=True) as c:
            execute(c,(ROOT/'tests/bootstrap.sql').read_text(encoding='utf-8'))
            for f in sorted((ROOT/'migrations').glob('*.sql')):
                if f.name[:3]<'057':execute(c,f.read_text(encoding='utf-8'))
            c.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for f in sorted((ROOT/'migrations').glob('*.sql')):
                if f.name[:3]<'057':c.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(f.name[:3],f.stem[4:],[] if f.name[:3]<='017' else [f.read_text(encoding='utf-8')]))
            c.execute('begin');execute(c,release.SOURCE.read_text(encoding='utf-8').replace('begin;','',1).rsplit('commit;',1)[0]);c.execute("set search_path=''")
            manifest=c.execute(release.MANIFEST_QUERY).fetchone()[0];c.execute('rollback')
            manifest_bytes=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
            if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Review changed manifest')
            release.MANIFEST.write_bytes(manifest_bytes)
            source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
            rehearsal=release.release_sql(source_hash,manifest_hash)
            proof=execute(c,rehearsal);assert proof['staged_disabled'] and proof['exact_dispatch_only']
            assert c.execute("select to_regclass('rm_private.catalog_workshop_write_settings')").fetchone()[0] is None
            checks.append('preservation_envelope_rehearsal_rolls_back_all_objects')
            sabotages=[
                'grant select on rm_private.catalog_workshop_write_permits to authenticated;',
                'grant execute on function public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to authenticated;',
                'alter function public.rm_web_mutate_v1(uuid,text,jsonb) security invoker;',
                'alter function rm_private.web_mutate_scoped_catalog_v1(uuid,text,jsonb) security definer;',
                'create table storage.unwanted_scope_test(id int);',
                "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",
                'alter table public.rm_projetos disable trigger workshop_catalog_reference_guard;',
                'create index unwanted_scope_index on public.rm_clientes(nome);',
                "update rm_private.catalog_workshop_write_settings set runtime_sha=repeat('a',40);",
                "create or replace function public.rm_web_mutate_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin return '{}'::jsonb;end$$;",
            ]
            for sabotage in sabotages:
                try:execute(c,rehearsal.replace('do $verify$',sabotage+'\ndo $verify$',1))
                except psycopg.Error as e:c.execute('rollback');assert e.sqlstate=='P0001',(e.sqlstate,str(e))
                else:raise AssertionError('Preservation sabotage accepted: '+sabotage)
            checks.append('ten_acl_function_body_owner_trigger_index_history_seed_sabotages_rejected')
            assert execute(c,release.release_sql(source_hash,manifest_hash,apply=True))['old_rows_preserved']
        command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','catalog_writes','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests/web_catalog_workshops.sql')])
        checks.append('transactional_authority_activation_no_bypass_create_edit_delete_replay_expiry_mfa_logout')
        # Commit only local synthetic setup for independent-connection races.
        setup=(ROOT/'tests/web_catalog_workshops.sql').read_text(encoding='utf-8').split('-- A fresh original')[0]
        setup='\n'.join(line for line in setup.splitlines() if not line.startswith('\\'))+'\ncommit;'
        with psycopg.connect(dsn,autocommit=True) as c:execute(c,setup)
        payload={'kind':'clients','id':key(61),'expected_updated_at':None,'changes':{'nome':'LOCAL race scoped client'}}
        from psycopg.types.json import Jsonb
        with psycopg.connect(dsn,autocommit=True) as c,psycopg.connect(dsn) as held:
            # Context fixture from a temporary helper is recreated in this session.
            definition=(ROOT/'tests/web_catalog_workshops.sql').read_text(encoding='utf-8')
            for name,end in [('cw_id','create function pg_temp.cw_check'),('cw_context','create function pg_temp.cw_payload')]:
                begin=definition.index('create function pg_temp.'+name);execute(c,definition[begin:definition.index(end,begin)])
            def mint(conn,office=1):
                ctx=c.execute('select pg_temp.cw_context(%s)',(office,)).fetchone()[0]
                conn.execute('select public.rm_sso_catalog_workshop_permit_v1(%s,%s,%s,%s,%s)',('9'*64,key(62),'save_catalog',Jsonb(payload),Jsonb(ctx)))
            mint(c)
            held.execute("select pg_advisory_xact_lock(hashtextextended('em:workshop-catalog:v1:client:'||%s,0))",(key(61),))
            c.execute('set role authenticated');c.execute("select set_config('request.jwt.claim.sub',%s,false)",(key(11),));c.execute("select set_config('request.jwt.claims',%s,false)",(json.dumps({'session_id':key(13),'aal':'aal1'}),))
            try:c.execute('select public.rm_web_mutate_v1(%s,%s,%s)',(key(62),'save_catalog',Jsonb(payload)))
            except psycopg.Error as e:assert e.sqlstate=='PT409',(e.sqlstate,str(e))
            else:raise AssertionError('Concurrent root lock ignored')
            c.execute('reset role');held.rollback()
            assert not c.execute('select exists(select 1 from public.rm_clientes where id=%s)',(key(61),)).fetchone()[0]
            checks.append('real_second_connection_catalog_lock_rejects_without_partial_row')
            c.execute("update rm_private.catalog_workshop_write_permits set expires_at=clock_timestamp()+interval '2 seconds' where submission_id=%s",(key(62),))
            held.execute("select pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17))")
            def delayed_write():
                with psycopg.connect(dsn+' application_name=em_catalog_delayed_writer',autocommit=True) as other:
                    other.execute("set statement_timeout='6s';set role authenticated")
                    other.execute("select set_config('request.jwt.claim.sub',%s,false)",(key(11),))
                    other.execute("select set_config('request.jwt.claims',%s,false)",(json.dumps({'session_id':key(13),'aal':'aal1'}),))
                    try:other.execute('select public.rm_web_mutate_v1(%s,%s,%s)',(key(62),'save_catalog',Jsonb(payload)))
                    except psycopg.Error as e:return e.sqlstate
                    raise AssertionError('Expired scope committed')
            with ThreadPoolExecutor(1) as pool:
                waiting=pool.submit(delayed_write);deadline=time.monotonic()+1.5
                while time.monotonic()<deadline:
                    c.execute('select pg_stat_clear_snapshot()')
                    if c.execute("select exists(select 1 from pg_stat_activity where application_name='em_catalog_delayed_writer' and wait_event_type='Lock')").fetchone()[0]:break
                    time.sleep(.02)
                else:raise AssertionError('Scoped writer did not reach core lock')
                time.sleep(2.1);held.rollback();assert waiting.result(timeout=4)=='42501'
            assert not c.execute('select exists(select 1 from public.rm_clientes where id=%s)',(key(61),)).fetchone()[0]
            assert not c.execute('select exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=%s)',(key(62),)).fetchone()[0]
            checks.append('real_core_wait_expiry_rolls_back_business_row_receipt_and_ownership')
            # Issuance and logout use binding -> session -> permits. Logout must
            # wait for the in-flight issuer and then remove both permit kinds.
            mint(held)
            def logout():
                with psycopg.connect(dsn,autocommit=True) as other:
                    other.execute("set statement_timeout='4s'")
                    other.execute('select public.rm_sso_session_delete_v1(%s)',('9'*64,))
            with ThreadPoolExecutor(1) as pool:
                waiting=pool.submit(logout);time.sleep(.2);assert not waiting.done();held.commit();waiting.result(timeout=5)
            assert c.execute('select count(*) from rm_private.catalog_workshop_write_permits').fetchone()[0]==0
            assert c.execute('select count(*) from rm_private.sso_action_permits').fetchone()[0]==0
            checks.append('real_issuance_logout_race_no_deadlock_and_both_permits_removed')
        files=['prepare_catalog_writes_release.py','test_catalog_writes_local.py','prepare_workshop_ownership_release.py','prepare_workshop_reference_release.py','test_workshop_ownership_local.py']
        support={n:hashlib.sha256((ROOT/'scripts'/n).read_bytes()).hexdigest() for n in files}
        support['web_catalog_workshops.sql']=hashlib.sha256((ROOT/'tests/web_catalog_workshops.sql').read_bytes()).hexdigest()
        proof={'local_only':True,'production_data_copied':False,'source_sha256':source_hash,'manifest_sha256':manifest_hash,'passed':len(checks),'checks':checks,'support_sha256':support}
        target=ROOT.parent/'.tmp/catalog-writes-local-proof.json';target.write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8');print(json.dumps(proof),flush=True);success=True
    finally:
        if running:command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
        if success:
            if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-catalog-writes-test-'):raise RuntimeError('Unexpected cleanup target')
            shutil.rmtree(root)
        else:print('Local failure diagnostics preserved at '+str(root),flush=True)
if __name__=='__main__':main()

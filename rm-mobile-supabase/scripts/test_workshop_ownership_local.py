"""Disposable loopback PostgreSQL: 053 preservation envelope and real races.

No production connections, credentials or business rows are used. Requires
PostgreSQL binaries on PATH and psycopg; the generator uses stdlib only.
"""
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
from psycopg.types.json import Jsonb
import prepare_workshop_ownership_release as release

ROOT=release.ROOT
OFFICES=[{'id':f'05300000-0000-4000-8000-{n:012d}','code':code} for n,code in enumerate(['BMA','BRJ','BBH'],1)]
DECLARATION='c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2'

def execute(connection,source):
    cursor=connection.execute(source,prepare=False);proof=None
    while True:
        if cursor.description and cursor.description[0].name=='proof':proof=cursor.fetchone()[0]
        if not cursor.nextset():break
    return proof

def main():
    root=Path(tempfile.mkdtemp(prefix='em-ownership-test-')).resolve();data=root/'data';running=False
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    programs={name:shutil.which(name) for name in ['initdb','pg_ctl','createdb','psql']}
    if not all(programs.values()):raise RuntimeError('PostgreSQL binaries required')
    checks=[]
    def command(args):
        with (root/'commands.log').open('ab') as output:
            result=subprocess.run(args,stdout=output,stderr=output,creationflags=flags,timeout=120)
        if result.returncode:raise RuntimeError('Disposable PostgreSQL command failed; see '+str(root/'commands.log'))
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    def dsn(db):return f'host=127.0.0.1 port={port} dbname={db} user=postgres'
    def bootstrap(db,through):
        command([programs['createdb'],'-h','127.0.0.1','-p',str(port),'-U','postgres',db])
        with psycopg.connect(dsn(db),autocommit=True) as connection:
            execute(connection,(ROOT/'tests/bootstrap.sql').read_text(encoding='utf-8'))
            for file in sorted((ROOT/'migrations').glob('*.sql')):
                if file.name[:3]<=through:execute(connection,file.read_text(encoding='utf-8'))
    try:
        print('LOCAL: initialize disposable ownership PostgreSQL',flush=True)
        command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
        command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
        bootstrap('em_ownership_manifest','053')
        with psycopg.connect(dsn('em_ownership_manifest'),autocommit=True) as connection:
            connection.execute("set search_path=''")
            manifest=connection.execute(release.MANIFEST_QUERY).fetchone()[0]
        manifest_bytes=(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n').encode()
        if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Existing manifest differs; review required')
        release.MANIFEST.write_bytes(manifest_bytes)
        command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','em_ownership_manifest','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests/workshop_ownership_foundation.sql')])
        checks.append('functional_scope_acl_replay_preservation_and_late_offline_tests')
        bootstrap('em_ownership_release','052')
        with psycopg.connect(dsn('em_ownership_release'),autocommit=True) as connection:
            connection.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for file in sorted((ROOT/'migrations').glob('*.sql')):
                if file.name[:3]<'053':connection.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(file.name[:3],file.stem[4:],[] if file.name[:3]<='017' else [file.read_text(encoding='utf-8')]))
            connection.execute("insert into public.rm_projetos(id,nome) values('05300000-0000-4000-8000-000000000011','LOCAL preserved root');insert into public.rm_celulas(id,nome) values('05300000-0000-4000-8000-000000000012','LOCAL preserved cell')")
            source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
            rehearsal=release.release_sql(source_hash,manifest_hash)
            proof=execute(connection,rehearsal)
            assert proof['old_rows_preserved'] and connection.execute("select to_regclass('rm_private.workshop_references')").fetchone()[0] is None
            checks.append('rehearsal_preserves_all_previous_tables_functions_auth_storage_roles_history')
            mutations=[
                "update public.rm_projetos set nome='TAMPERED' where id='05300000-0000-4000-8000-000000000011';",
                'grant select on rm_private.workshop_references to authenticated;',
                'grant execute on function rm_private.workshop_ownership_readiness_v1() to service_role;',
                'alter function public.rm_user_has_element_permission(uuid,text) owner to authenticated;',
                "insert into rm_private.workshop_references values('05300000-0000-4000-8000-000000000099','BMA','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1');",
                'create table storage.unexpected_ownership_test(id int);',
                "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",
            ]
            for mutation in mutations:
                try:execute(connection,rehearsal.replace('do $verify$',mutation+'\ndo $verify$',1))
                except psycopg.Error as error:
                    connection.execute('rollback')
                    assert error.sqlstate=='P0001',str(error)
                else:raise AssertionError('Preservation sabotage was accepted')
                assert connection.execute("select to_regclass('rm_private.workshop_references')").fetchone()[0] is None
            checks.append('seven_sabotages_rejected_and_rolled_back_atomically')
            applied=execute(connection,release.release_sql(source_hash,manifest_hash,apply=True))
            assert applied['new_tables_empty'] and connection.execute("select count(*) from rm_private.workshop_references").fetchone()[0]==0
            checks.append('atomic_apply_preserves_existing_data_and_creates_empty_foundation')
        # Initial adoption waits for a concurrent legacy root insert, then rejects
        # stale counts; both contenders use real PostgreSQL locks/connections.
        def adopt(np,nc):
            with psycopg.connect(dsn('em_ownership_release')+' application_name=em_ownership_adopter',autocommit=True) as connection:
                connection.execute("set statement_timeout='10s';set lock_timeout='7s'")
                try:return {'result':connection.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,%s,%s)',(Jsonb(OFFICES),DECLARATION,np,nc)).fetchone()[0]}
                except psycopg.Error as error:return {'sqlstate':error.sqlstate}
        with psycopg.connect(dsn('em_ownership_release'),autocommit=True) as connection:
            np,nc=connection.execute('select (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas)').fetchone()
            with psycopg.connect(dsn('em_ownership_release')) as writer,ThreadPoolExecutor(2) as pool:
                writer.execute("insert into public.rm_projetos(id,nome) values('05300000-0000-4000-8000-000000000021','LOCAL concurrent root')")
                waiting=pool.submit(adopt,np,nc)
                deadline=time.monotonic()+5
                while time.monotonic()<deadline:
                    connection.execute('select pg_stat_clear_snapshot()')
                    if connection.execute("select exists(select 1 from pg_stat_activity where application_name='em_ownership_adopter' and wait_event_type='Lock')").fetchone()[0]:break
                    time.sleep(.02)
                else:raise AssertionError('Adopter did not wait for the legacy writer')
                writer.commit();assert waiting.result()['sqlstate']=='PT409'
            assert connection.execute('select count(*) from rm_private.workshop_legacy_adoption').fetchone()[0]==0
            checks.append('concurrent_legacy_insert_blocks_then_invalidates_stale_initial_batch')
            with ThreadPoolExecutor(2) as pool:
                results=list(pool.map(lambda _:adopt(np+1,nc),range(2)))
            assert sorted(item['result']['replayed'] for item in results)==[False,True]
            assert connection.execute('select count(*) from rm_private.workshop_legacy_adoption').fetchone()[0]==1
            checks.append('two_concurrent_adoptions_have_one_batch_and_one_exact_replay')
        result={'local_only':True,'production_data_copied':False,'checks':checks,'passed':len(checks),'source_sha256':source_hash,'manifest_sha256':manifest_hash,
                'support_sha256':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in [Path(__file__),Path(release.__file__)]},'preservation_proof':applied}
        output=ROOT.parent/'.tmp/workshop-ownership-local-proof.json'
        output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
    finally:
        if running or (data/'postmaster.pid').exists():command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
        if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-ownership-test-'):raise RuntimeError('Unsafe cleanup target')
        # Preserve failed local diagnostics; successful runs contain no user files.
        if 'result' in locals():shutil.rmtree(root)

if __name__=='__main__':main()

"""Disposable local PostgreSQL proofs for 054: preservation and real races."""
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
import prepare_workshop_origin_release as release
from test_workshop_ownership_local import execute,OFFICES,DECLARATION

ROOT=release.ROOT
P1='05400000-0000-4000-8000-000000000011'
P2='05400000-0000-4000-8000-000000000012'
C1='05400000-0000-4000-8000-000000000013'
P3='05400000-0000-4000-8000-000000000014'
BMA=OFFICES[0]['id']

def main():
    root=Path(tempfile.mkdtemp(prefix='em-origin-test-')).resolve();data=root/'data';running=False
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    programs={name:shutil.which(name) for name in ['initdb','pg_ctl','createdb','psql']}
    if not all(programs.values()):raise RuntimeError('PostgreSQL binaries required')
    checks=[]
    def command(args):
        with (root/'commands.log').open('ab') as output:
            result=subprocess.run(args,stdout=output,stderr=output,creationflags=flags,timeout=120)
        if result.returncode:raise RuntimeError('Disposable PostgreSQL failed: '+str(root/'commands.log'))
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    def dsn(db):return f'host=127.0.0.1 port={port} dbname={db} user=postgres'
    def bootstrap(db,through):
        command([programs['createdb'],'-h','127.0.0.1','-p',str(port),'-U','postgres',db])
        with psycopg.connect(dsn(db),autocommit=True) as c:
            execute(c,(ROOT/'tests/bootstrap.sql').read_text(encoding='utf-8'))
            for file in sorted((ROOT/'migrations').glob('*.sql')):
                if file.name[:3]<=through:execute(c,file.read_text(encoding='utf-8'))
    def denied(c,sql,state,params=None):
        try:c.execute(sql,params)
        except psycopg.Error as e:assert e.sqlstate==state,(e.sqlstate,str(e))
        else:raise AssertionError('Expected denial: '+state)
    try:
        print('LOCAL: initialize disposable origin PostgreSQL',flush=True)
        command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
        command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
        bootstrap('em_origin_manifest','054')
        with psycopg.connect(dsn('em_origin_manifest'),autocommit=True) as c:
            c.execute("set search_path=''")
            manifest=c.execute(release.MANIFEST_QUERY).fetchone()[0]
        manifest_bytes=(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n').encode()
        if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Existing manifest differs; review required')
        release.MANIFEST.write_bytes(manifest_bytes)
        for test in ['workshop_ownership_foundation.sql','workshop_origin_retention.sql']:
            command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','em_origin_manifest','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests'/test)])
        checks.append('real_application_deletion_retention_offline_replay_immutability_acl_and_rollback')
        bootstrap('em_origin_release','053')
        with psycopg.connect(dsn('em_origin_release'),autocommit=True) as c:
            c.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for file in sorted((ROOT/'migrations').glob('*.sql')):
                if file.name[:3]<'054':c.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(file.name[:3],file.stem[4:],[] if file.name[:3]<='017' else [file.read_text(encoding='utf-8')]))
            c.execute("insert into public.rm_projetos(id,nome) values(%s,'LOCAL preserved first'),(%s,'LOCAL preserved second')",(P1,P2))
            c.execute("insert into public.rm_celulas(id,nome) values(%s,'LOCAL preserved cell')",(C1,))
            c.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,2,1)',(Jsonb(OFFICES),DECLARATION))
            source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
            rehearsal=release.release_sql(source_hash,manifest_hash)
            proof=execute(c,rehearsal)
            assert proof['old_rows_preserved'] and proof['origin_readiness']['project_origins']==2 and proof['origin_readiness']['cell_origins']==1
            assert c.execute("select to_regclass('rm_private.workshop_object_origins')").fetchone()[0] is None
            checks.append('rollback_envelope_preserves_all_old_rows_functions_auth_storage_roles_and_history')
            mutations=[
                "update public.rm_projetos set nome='TAMPERED';",
                'grant select on rm_private.workshop_object_origins to authenticated;',
                'grant execute on function rm_private.workshop_assert_origin_v1(text,uuid,uuid) to service_role;',
                'alter function public.rm_user_has_element_permission(uuid,text) owner to authenticated;',
                "alter table rm_private.workshop_object_origins disable trigger workshop_origins_immutable;update rm_private.workshop_object_origins set workshop_id='"+OFFICES[1]['id']+"';alter table rm_private.workshop_object_origins enable trigger workshop_origins_immutable;",
                'create table storage.unexpected_origin_test(id int);',
                "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",
                'create index unwanted_origin_index on public.rm_projetos(nome);',
                'create trigger unwanted_origin_trigger before truncate on rm_private.workshop_project_ownership for each statement execute function rm_private.workshop_origin_immutable_v1();',
                "create or replace function rm_private.workshop_ownership_readiness_v1() returns jsonb language sql set search_path='' as $fake$select '{}'::jsonb$fake$;",
            ]
            for mutation in mutations:
                denied(c,rehearsal.replace('do $verify$',mutation+'\ndo $verify$',1),'P0001')
                c.execute('rollback')
                assert c.execute("select to_regclass('rm_private.workshop_object_origins')").fetchone()[0] is None
            checks.append('ten_preservation_sabotages_rejected_and_atomically_rolled_back')
        # A writer already changing a live map must finish before the release
        # captures its snapshot; its committed namespace must be in the seed.
        def apply_waiting():
            with psycopg.connect(dsn('em_origin_release')+' application_name=em_origin_migrator',autocommit=True) as c:
                return execute(c,release.release_sql(source_hash,manifest_hash,apply=True))
        with psycopg.connect(dsn('em_origin_release'),autocommit=True) as c,psycopg.connect(dsn('em_origin_release')) as writer,ThreadPoolExecutor(2) as pool:
            writer.execute("insert into public.rm_projetos(id,nome) values(%s,'LOCAL concurrent writer')",(P3,))
            writer.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)',(P3,BMA))
            waiting=pool.submit(apply_waiting)
            deadline=time.monotonic()+4
            while time.monotonic()<deadline:
                c.execute('select pg_stat_clear_snapshot()')
                if c.execute("select exists(select 1 from pg_stat_activity where application_name='em_origin_migrator' and wait_event_type='Lock')").fetchone()[0]:break
                time.sleep(.02)
            else:raise AssertionError('Migration did not wait for live writer')
            writer.commit();applied=waiting.result()
            assert applied['origin_seed_matches'] and applied['origin_readiness']['project_origins']==3
            assert c.execute('select workshop_id from rm_private.workshop_object_origins where object_kind=\'project\' and object_id=%s',(P3,)).fetchone()[0]==__import__('uuid').UUID(BMA)
            checks.append('release_locks_live_maps_before_snapshot_and_seeds_only_verified_origins')
        with psycopg.connect(dsn('em_origin_release'),autocommit=True) as c,psycopg.connect(dsn('em_origin_release')) as held:
            held.execute("select rm_private.workshop_assert_origin_v1('project',%s,%s)",(P1,BMA))
            denied(c,'delete from public.rm_projetos where id=%s','PT409',(P1,))
            assert c.execute('select count(*) from public.rm_projetos where id=%s',(P1,)).fetchone()[0]==1
            assert c.execute('select count(*) from rm_private.workshop_origin_retirements where object_id=%s',(P1,)).fetchone()[0]==0
            # A different object's operation is independent of the held key.
            c.execute('delete from public.rm_projetos where id=%s',(P2,))
            held.commit();c.execute('delete from public.rm_projetos where id=%s',(P1,))
            checks.append('same_origin_use_vs_delete_fails_without_deadlock_unrelated_origin_progresses_retry_retires')
            c.execute("insert into public.rm_projetos(id,nome) values(%s,'LOCAL late offline root')",(P1,))
            denied(c,'insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)','PT410',(P1,BMA))
            denied(c,'insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)','PT410',(P1,OFFICES[1]['id']))
            held.execute('delete from public.rm_celulas where id=%s',(C1,))
            denied(c,"select rm_private.workshop_assert_origin_v1('cell',%s,%s)",'PT409',(C1,BMA))
            denied(c,'insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(%s,%s)','PT409',(C1,BMA))
            held.rollback();c.execute("select rm_private.workshop_assert_origin_v1('cell',%s,%s)",(C1,BMA))
            checks.append('delete_vs_late_use_busy_then_rollback_restores_live_origin_retired_uuid_cannot_rebind')
        result={'local_only':True,'production_data_copied':False,'checks':checks,'passed':len(checks),'source_sha256':source_hash,'manifest_sha256':manifest_hash,
          'support_sha256':{file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in [Path(__file__),Path(release.__file__),Path(release.previous.__file__),ROOT/'tests/workshop_origin_retention.sql',ROOT/'tests/workshop_ownership_foundation.sql']},'preservation_proof':applied}
        (ROOT.parent/'.tmp/workshop-origin-local-proof.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
    finally:
        if running or (data/'postmaster.pid').exists():command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
        if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-origin-test-'):raise RuntimeError('Unsafe cleanup target')
        if 'result' in locals():shutil.rmtree(root)

if __name__=='__main__':main()

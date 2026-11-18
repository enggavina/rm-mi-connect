"""Disposable loopback PG: direct-root integrity, real races and 055 envelope."""
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
import prepare_workshop_reference_release as release
from test_workshop_ownership_local import execute,OFFICES,DECLARATION

ROOT=release.ROOT
def key(n):return f'05500000-0000-4000-8000-{n:012d}'
BMA=OFFICES[0]['id'];BRJ=OFFICES[1]['id']

def main():
    root=Path(tempfile.mkdtemp(prefix='em-reference-test-')).resolve();data=root/'data';running=False
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    programs={n:shutil.which(n) for n in ['initdb','pg_ctl','createdb','psql']}
    if not all(programs.values()):raise RuntimeError('PostgreSQL binaries required')
    checks=[]
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
    def denied(c,statement,state,params=None):
        try:c.execute(statement,params)
        except psycopg.Error as e:assert e.sqlstate==state,(e.sqlstate,str(e))
        else:raise AssertionError('Expected '+state)
    def fixture(c):
        c.execute("insert into public.rm_projetos(id,nome) values(%s,'LOCAL initial project')",(key(11),))
        c.execute("insert into public.rm_celulas(id,nome) values(%s,'LOCAL initial cell')",(key(12),))
        c.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,1,1)',(Jsonb(OFFICES),DECLARATION))
        c.execute("insert into public.rm_projetos(id,nome) select x,'LOCAL later project' from unnest(%s::uuid[])x",([key(n) for n in [21,31,41,51]],))
        c.execute("insert into public.rm_celulas(id,nome) select x,'LOCAL later cell' from unnest(%s::uuid[])x",([key(22),key(42)],))
        c.execute('insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(%s,%s)',(key(22),BRJ))
    try:
        print('LOCAL: initialize disposable workshop reference PostgreSQL',flush=True)
        command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
        command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
        bootstrap('ref_manifest','055')
        with psycopg.connect(dsn('ref_manifest'),autocommit=True) as c:
            c.execute("set search_path=''");manifest=c.execute(release.MANIFEST_QUERY).fetchone()[0]
        manifest_bytes=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
        if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Review changed manifest')
        release.MANIFEST.write_bytes(manifest_bytes)
        for test in ['workshop_ownership_foundation.sql','workshop_origin_retention.sql','workshop_direct_references.sql']:
            command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','ref_manifest','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests'/test)])
        checks.append('all_direct_rules_original_foundations_authenticated_write_and_real_delete_preserved')
        bootstrap('ref_release','054')
        with psycopg.connect(dsn('ref_release'),autocommit=True) as c:
            c.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for f in sorted((ROOT/'migrations').glob('*.sql')):
                if f.name[:3]<'055':c.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(f.name[:3],f.stem[4:],[] if f.name[:3]<='017' else [f.read_text(encoding='utf-8')]))
            fixture(c)
            source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
            rehearsal=release.release_sql(source_hash,manifest_hash)
            proof=execute(c,rehearsal);assert proof['old_functions_preserved'] and not proof['isolation_active']
            assert c.execute("select to_regprocedure('rm_private.workshop_reference_readiness_v1()')").fetchone()[0] is None
            checks.append('rehearsal_preserves_all_rows_functions_acl_auth_storage_roles_and_history')
            sabotages=[
                "update public.rm_projetos set nome='TAMPERED';",
                'grant execute on function rm_private.workshop_reference_pair_v1(uuid,uuid,text,uuid) to service_role;',
                'alter function public.rm_user_has_element_permission(uuid,text) owner to authenticated;',
                'create table storage.unwanted_reference_test(id int);',
                "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",
                'alter table public.rm_comentarios disable trigger workshop_direct_reference_guard;',
                'drop trigger workshop_direct_reference_guard on public.rm_fotos;',
                'alter function rm_private.workshop_guard_reference_v1() security invoker;',
                'create index unwanted_reference_index on public.rm_projetos(nome);',
                'create trigger unwanted_reference_trigger before truncate on public.rm_fotos for each statement execute function rm_private.workshop_origin_immutable_v1();',
            ]
            for sabotage in sabotages:
                try:execute(c,rehearsal.replace('do $verify$',sabotage+'\ndo $verify$',1))
                except psycopg.Error as e:c.execute('rollback');assert e.sqlstate=='P0001',(e.sqlstate,str(e))
                else:raise AssertionError('Preservation sabotage accepted')
                assert c.execute("select to_regprocedure('rm_private.workshop_reference_readiness_v1()')").fetchone()[0] is None
            checks.append('ten_sabotages_rejected_without_changes')
            # A historical crossed pair must be reported, never silently fixed.
            c.execute('insert into public.rm_comentarios(id,projeto_id,celula_id,evento) values(%s,%s,%s,$event$LOCAL reference$event$)',(key(81),key(11),key(22)))
            try:execute(c,rehearsal)
            except psycopg.Error as e:c.execute('rollback');assert e.sqlstate=='P0001' and 'Existing cross-workshop' in str(e)
            else:raise AssertionError('Historical crossed pair silently accepted')
            assert c.execute('select count(*) from public.rm_comentarios where id=%s',(key(81),)).fetchone()[0]==1
            c.execute('delete from public.rm_comentarios where id=%s',(key(81),))
            checks.append('historical_conflict_aborts_installation_and_keeps_original_record')
        def install():
            with psycopg.connect(dsn('ref_release')+' application_name=em_reference_installer',autocommit=True) as c:
                return execute(c,release.release_sql(source_hash,manifest_hash,apply=True))
        with psycopg.connect(dsn('ref_release')) as writer,psycopg.connect(dsn('ref_release'),autocommit=True) as observer,ThreadPoolExecutor(2) as pool:
            writer.execute('insert into public.rm_celulas_projeto(projeto_id,celula_id) values(%s,%s)',(key(11),key(12)))
            waiting=pool.submit(install);deadline=time.monotonic()+4
            while time.monotonic()<deadline:
                observer.execute('select pg_stat_clear_snapshot()')
                if observer.execute("select exists(select 1 from pg_stat_activity where application_name='em_reference_installer' and wait_event_type='Lock')").fetchone()[0]:break
                time.sleep(.02)
            else:raise AssertionError('Installer did not wait for existing writer')
            writer.commit();applied=waiting.result();assert applied['readiness']['conflicts']==0
            assert sum(r['pairs'] for r in applied['readiness']['rules'])==1
        checks.append('installation_locks_before_snapshot_and_preserves_concurrent_admitted_reference')
        with psycopg.connect(dsn('ref_release'),autocommit=True) as c,psycopg.connect(dsn('ref_release')) as held:
            # Shared mode: same project/cell writers can both finish their SQL
            # while the other transaction is still open.
            held.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(11),key(12)))
            c.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(11),key(12)))
            denied(c,'update rm_private.workshop_cell_ownership set workshop_id=workshop_id where cell_id=%s','PT409',(key(12),))
            held.commit();c.execute('update rm_private.workshop_cell_ownership set workshop_id=workshop_id where cell_id=%s',(key(12),))
            checks.append('ordinary_shared_writers_coexist_classification_busy_then_retry_preserves_rows')
            held.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(21),key(22)))
            denied(c,'insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)','PT409',(key(21),BMA))
            assert c.execute('select count(*) from rm_private.workshop_object_origins where object_id=%s',(key(21),)).fetchone()[0]==0
            held.commit()
            denied(c,'insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)','PT409',(key(21),BMA))
            c.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)',(key(21),BRJ))
            held.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)',(key(31),BMA))
            denied(c,'insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)','PT409',(key(31),key(22)))
            held.commit();denied(c,'insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)','PT409',(key(31),key(22)))
            c.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(31),key(12)))
            checks.append('reference_vs_classification_both_directions_busy_or_reject_crossed_retry_never_assigns_origin')
            c.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(41),key(42)))
            held.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)',(key(41),BMA))
            denied(c,'insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(%s,%s)','PT409',(key(42),BRJ))
            held.commit();denied(c,'insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(%s,%s)','PT409',(key(42),BRJ))
            c.execute('insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(%s,%s)',(key(42),BMA))
            checks.append('inverse_classifications_on_unknown_pair_cannot_commit_conflicting_offices')
            for isolation in ['repeatable read','serializable']:
                held.execute('set transaction isolation level '+isolation)
                assert held.execute('show transaction_isolation').fetchone()[0]==isolation
                held.execute('select count(*) from public.rm_comentarios')
                c.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(51),key(12)))
                denied(held,'insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)','PT409',(key(51),BRJ));held.rollback()
                held.execute('set transaction isolation level '+isolation)
                denied(held,'insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)','PT409',(key(11),key(12)));held.rollback()
            c.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)',(key(51),BMA))
            checks.append('stale_repeatable_or_serializable_snapshot_cannot_bypass_current_reference_checks')
            held.execute('insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)',(key(11),key(12)))
            denied(c,'delete from rm_private.workshop_project_ownership where id=%s','PT409',(key(11),));held.rollback()
            c.execute('delete from rm_private.workshop_project_ownership where id=%s',(key(11),))
            denied(c,'insert into public.rm_comentarios(projeto_id,celula_id,evento) values(%s,%s,$event$LOCAL reference$event$)','PT410',(key(11),key(12)))
            assert c.execute('select count(*) from public.rm_projetos where id=%s',(key(11),)).fetchone()[0]==1
            assert c.execute("select (rm_private.workshop_reference_readiness_v1()->>'conflicts')::bigint").fetchone()[0]==0
            checks.append('retirement_vs_reference_retry_keeps_original_project_and_refuses_late_pair')
        result={'local_only':True,'production_data_copied':False,'checks':checks,'passed':len(checks),'source_sha256':source_hash,'manifest_sha256':manifest_hash,
          'support_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [Path(__file__),Path(release.__file__),Path(release.baseline.__file__),ROOT/'tests/workshop_direct_references.sql']},'preservation_proof':applied}
        (ROOT.parent/'.tmp/workshop-reference-local-proof.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
    finally:
        if running or (data/'postmaster.pid').exists():command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
        if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-reference-test-'):raise RuntimeError('Unsafe cleanup target')
        if 'result' in locals():shutil.rmtree(root)

if __name__=='__main__':main()

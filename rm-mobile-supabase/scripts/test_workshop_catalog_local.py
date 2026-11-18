"""Disposable loopback PG: catalog ownership, real races and 056 envelope."""
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
import prepare_workshop_catalog_release as release
from test_workshop_ownership_local import execute,OFFICES,DECLARATION

ROOT=release.ROOT
def key(n):return f'05600000-0000-4000-8000-{n:012d}'
BMA=OFFICES[0]['id'];BRJ=OFFICES[1]['id']

def main():
    root=Path(tempfile.mkdtemp(prefix='em-catalog-test-')).resolve();data=root/'data';running=False
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
        c.execute("insert into public.rm_clientes(id,nome) values(%s,'LOCAL original client')",(key(21),))
        c.execute("insert into public.rm_tipos_equipamento(id,nome) values(%s,'LOCAL original type')",(key(22),))
        c.execute("insert into public.rm_celulas(id,nome) values(%s,'LOCAL original cell')",(key(12),))
        c.execute("insert into public.rm_forms(id,titulo,celulas_ids) values(%s,'LOCAL original form',%s)",(key(23),[key(12)]))
        c.execute("insert into public.rm_projetos(id,nome,cliente_id,tipo_equipamento_id) values(%s,'LOCAL original project',%s,%s)",(key(11),key(21),key(22)))
        c.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,1,1)',(Jsonb(OFFICES),DECLARATION))
    def adopt(c,clients=1):return c.execute('select rm_private.workshop_catalog_adopt_bma_v1(%s,%s,1,1)',(release.POLICY_SHA,clients)).fetchone()[0]
    try:
        print('LOCAL: disposable catalog ownership PostgreSQL, synthetic business rows only',flush=True)
        command([programs['initdb'],'-D',str(data),'-U','postgres','-A','trust','-E','UTF8','--no-locale','--no-sync'])
        command([programs['pg_ctl'],'-D',str(data),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port}','-w','start']);running=True
        bootstrap('catalog_manifest','056')
        with psycopg.connect(dsn('catalog_manifest'),autocommit=True) as c:
            c.execute("set search_path=''");manifest=c.execute(release.MANIFEST_QUERY).fetchone()[0]
        manifest_bytes=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
        if release.MANIFEST.exists() and release.MANIFEST.read_bytes()!=manifest_bytes:raise RuntimeError('Review changed catalog manifest')
        release.MANIFEST.write_bytes(manifest_bytes)
        for test in ['workshop_ownership_foundation.sql','workshop_origin_retention.sql','workshop_direct_references.sql','workshop_catalog_ownership.sql']:
            command([programs['psql'],'-X','-q','-h','127.0.0.1','-p',str(port),'-U','postgres','-d','catalog_manifest','-v','ON_ERROR_STOP=1','-f',str(ROOT/'tests'/test)])
        checks.append('three_catalogs_exact_adoption_reverse_references_arrays_retention_original_apis_and_private_acl')
        bootstrap('catalog_release','055')
        with psycopg.connect(dsn('catalog_release'),autocommit=True) as c:
            c.execute('create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for f in sorted((ROOT/'migrations').glob('*.sql')):
                if f.name[:3]<'056':c.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',(f.name[:3],f.stem[4:],[] if f.name[:3]<='017' else [f.read_text(encoding='utf-8')]))
            fixture(c)
            source_hash=hashlib.sha256(release.SOURCE.read_bytes()).hexdigest();manifest_hash=hashlib.sha256(manifest_bytes).hexdigest()
            rehearsal=release.release_sql(source_hash,manifest_hash,1,1,1)
            proof=execute(c,rehearsal);assert proof['catalog_seed_verified'] and not proof['isolation_active']
            assert c.execute("select to_regclass('rm_private.workshop_catalog_ownership')").fetchone()[0] is None
            checks.append('full_preservation_envelope_rehearsal_reverts_schema_and_catalog_metadata')
            sabotages=[
                "update public.rm_clientes set nome='TAMPERED';",
                'grant select on rm_private.workshop_catalog_ownership to authenticated;',
                'grant execute on function rm_private.workshop_catalog_scope_v1(text,uuid) to service_role;',
                'alter function public.rm_user_has_element_permission(uuid,text) owner to authenticated;',
                'create table storage.unwanted_catalog_test(id int);',
                "update supabase_migrations.schema_migrations set name='TAMPERED' where version='001';",
                'alter table public.rm_projetos disable trigger workshop_catalog_reference_guard;',
                'alter function rm_private.workshop_catalog_guard_reference_v1() security invoker;',
                'create index unwanted_catalog_index on public.rm_clientes(nome);',
                "alter table rm_private.workshop_catalog_ownership disable trigger workshop_catalog_immutable;update rm_private.workshop_catalog_ownership set workshop_id='"+BRJ+"';alter table rm_private.workshop_catalog_ownership enable trigger workshop_catalog_immutable;",
            ]
            for sabotage in sabotages:
                try:execute(c,rehearsal.replace('do $verify$',sabotage+'\ndo $verify$',1))
                except psycopg.Error as e:c.execute('rollback');assert e.sqlstate=='P0001',(e.sqlstate,str(e))
                else:raise AssertionError('Catalog preservation sabotage accepted')
                assert c.execute("select to_regclass('rm_private.workshop_catalog_ownership')").fetchone()[0] is None
            checks.append('ten_metadata_data_function_trigger_acl_and_history_sabotages_rejected')
        def install():
            with psycopg.connect(dsn('catalog_release')+' application_name=em_catalog_installer',autocommit=True) as c:
                return execute(c,release.release_sql(source_hash,manifest_hash,1,1,1,apply=True))
        with psycopg.connect(dsn('catalog_release')) as writer,psycopg.connect(dsn('catalog_release'),autocommit=True) as observer,ThreadPoolExecutor(2) as pool:
            writer.execute("update public.rm_clientes set nome='LOCAL legitimate concurrent edit' where id=%s",(key(21),))
            waiting=pool.submit(install);deadline=time.monotonic()+4
            while time.monotonic()<deadline:
                observer.execute('select pg_stat_clear_snapshot()')
                if observer.execute("select exists(select 1 from pg_stat_activity where application_name='em_catalog_installer' and wait_event_type='Lock')").fetchone()[0]:break
                time.sleep(.02)
            else:raise AssertionError('Installer did not wait for admitted catalog writer')
            writer.commit();applied=waiting.result();assert applied['readiness']['conflicts']==0
            assert observer.execute('select nome from public.rm_clientes where id=%s',(key(21),)).fetchone()[0]=='LOCAL legitimate concurrent edit'
        checks.append('installation_lock_precedes_baseline_and_preserves_committed_concurrent_business_edit')
        with psycopg.connect(dsn('catalog_release'),autocommit=True) as c,psycopg.connect(dsn('catalog_release')) as held:
            c.execute("insert into public.rm_projetos(id,nome) select x,'LOCAL later project' from unnest(%s::uuid[])x",([key(41),key(51)],))
            c.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s),(%s,%s)',(key(41),BRJ,key(51),BMA))
            c.execute("insert into public.rm_clientes(id,nome) values(%s,'LOCAL later client'),(%s,'LOCAL inverse client')",(key(31),key(33)))
            assert adopt(c)['replayed']
            assert c.execute("select count(*) from rm_private.workshop_catalog_ownership where object_kind='client'").fetchone()[0]==1
            held.execute('update public.rm_projetos set cliente_id=%s where id=%s',(key(21),key(11)))
            c.execute('update public.rm_projetos set cliente_id=%s where id=%s',(key(21),key(51)))
            denied(c,'delete from public.rm_clientes where id=%s','PT409',(key(21),));held.rollback()
            checks.append('normal_same_catalog_writers_share_keys_and_retirement_does_not_block_on_fk_cycle')
            held.execute('update public.rm_projetos set cliente_id=%s where id=%s',(key(31),key(11)))
            denied(c,"insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',%s,%s)",'PT409',(key(31),BRJ));held.commit()
            denied(c,"insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',%s,%s)",'PT409',(key(31),BRJ))
            c.execute("insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',%s,%s)",(key(31),BMA))
            held.execute("insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',%s,%s)",(key(33),BRJ))
            denied(c,'update public.rm_projetos set cliente_id=%s where id=%s','PT409',(key(33),key(11)));held.commit()
            denied(c,'update public.rm_projetos set cliente_id=%s where id=%s','PT409',(key(33),key(11)))
            c.execute('update public.rm_projetos set cliente_id=%s where id=%s',(key(33),key(41)))
            checks.append('reference_and_catalog_classification_races_in_both_directions_never_commit_crossed_scope')
            for isolation in ['repeatable read','serializable']:
                held.execute('set transaction isolation level '+isolation)
                denied(held,'update public.rm_projetos set cliente_id=%s where id=%s','PT409',(key(21),key(51)));held.rollback()
            checks.append('old_snapshot_cannot_bypass_catalog_reference_checks')
            c.execute('delete from public.rm_tipos_equipamento where id=%s',(key(22),))
            assert c.execute('select tipo_equipamento_id from public.rm_projetos where id=%s',(key(11),)).fetchone()[0] is None
            denied(c,"insert into public.rm_tipos_equipamento(id,nome) values(%s,'LOCAL late type')",'PT410',(key(22),))
            assert adopt(c)['replayed']
            assert c.execute("select (rm_private.workshop_catalog_readiness_v1()->>'conflicts')::bigint").fetchone()[0]==0
            checks.append('delete_keeps_origin_uses_existing_fk_cleanup_late_id_reuse_denied_and_batch_retry_never_reassigns')
        # First adoption serialization uses actual separate transactions. Only
        # synthetic rows exist here; after a retry new objects remain unknown.
        with psycopg.connect(dsn('catalog_manifest'),autocommit=True) as c:fixture(c)
        def initial_adopt():
            with psycopg.connect(dsn('catalog_manifest')) as c:return adopt(c)
        with ThreadPoolExecutor(2) as pool:results=list(pool.map(lambda _:initial_adopt(),range(2)))
        assert sorted(r['replayed'] for r in results)==[False,True]
        checks.append('two_initial_catalog_adoptions_create_one_receipt_and_one_exact_acknowledgement')
        result={'local_only':True,'production_data_copied':False,'checks':checks,'passed':len(checks),'source_sha256':source_hash,'manifest_sha256':manifest_hash,'policy_sha256':release.POLICY_SHA,
          'support_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [Path(__file__),Path(release.__file__),Path(release.baseline.__file__),Path(release.previous.__file__),ROOT/'tests/workshop_catalog_ownership.sql']},'preservation_proof':applied}
        (ROOT.parent/'.tmp/workshop-catalog-local-proof.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
    finally:
        if running or (data/'postmaster.pid').exists():command([programs['pg_ctl'],'-D',str(data),'-m','fast','-w','stop'])
        if root.parent!=Path(tempfile.gettempdir()).resolve() or not root.name.startswith('em-catalog-test-'):raise RuntimeError('Unsafe cleanup target')
        if 'result' in locals():shutil.rmtree(root)

if __name__=='__main__':main()

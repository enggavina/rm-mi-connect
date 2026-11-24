"""Capture and verify 060 object preservation in disposable PostgreSQL."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile

import psycopg

import prepare_workshop_operations_release as release
from test_workshop_ownership_local import execute


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    temporary_parent = Path(tempfile.gettempdir()).resolve()
    directory = Path(tempfile.mkdtemp(prefix='em-workshop-operations-', dir=temporary_parent)).resolve()
    data = directory / 'data'
    log = directory / 'commands.log'
    binaries = {name: shutil.which(name) for name in ('initdb', 'pg_ctl', 'createdb')}
    if not all(binaries.values()):
        raise RuntimeError('PostgreSQL binaries required')
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    running = False
    success = False

    def command(name, *args):
        with log.open('ab') as output:
            result = subprocess.run([binaries[name], *args], stdout=output, stderr=output,
                                    creationflags=flags, timeout=180, check=False)
        if result.returncode:
            raise RuntimeError(f'Local PostgreSQL failed. See {log}')

    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]

    def connect(database):
        return psycopg.connect(host='127.0.0.1', port=port, dbname=database, user='postgres', autocommit=True)

    try:
        command('initdb', '-D', str(data), '-U', 'postgres', '-A', 'trust', '-E', 'UTF8',
                '--no-locale', '--no-sync')
        command('pg_ctl', '-D', str(data), '-l', str(directory / 'server.log'),
                '-o', f'-h 127.0.0.1 -p {port}', '-w', 'start')
        running = True
        command('createdb', '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres', 'operations_release')
        migrations = sorted(release.SOURCE.parent.glob('*.sql'))
        with connect('operations_release') as connection:
            execute(connection, (release.ROOT / 'tests/bootstrap.sql').read_text(encoding='utf-8'))
            connection.execute('create schema supabase_migrations')
            connection.execute('create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[])')
            for path in migrations:
                version = path.name[:3]
                if version >= release.VERSION:
                    break
                source = path.read_text(encoding='utf-8')
                execute(connection, source)
                connection.execute('insert into supabase_migrations.schema_migrations values(%s,%s,%s)',
                                   (version, path.stem[4:], [] if version <= '017' else [source]))
            connection.execute("insert into public.rm_clientes(nome) values('LOCAL 060 preservation fixture')")

        command('createdb', '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres',
                '-T', 'operations_release', 'operations_manifest')
        with connect('operations_manifest') as connection:
            execute(connection, release.SOURCE.read_text(encoding='utf-8'))
            connection.execute("set search_path=''")
            manifest = connection.execute(release.MANIFEST_QUERY).fetchone()[0]
        contents = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode()
        if release.MANIFEST.exists():
            if release.MANIFEST.read_bytes() != contents:
                raise RuntimeError('Reviewed operations manifest differs')
        else:
            release.MANIFEST.write_bytes(contents)

        source_hash = sha256(release.SOURCE)
        manifest_hash = sha256(release.MANIFEST)
        rehearsal = release.release_sql(source_hash, manifest_hash)
        checks = []
        with connect('operations_release') as connection:
            connection.execute("set search_path=''")
            original = connection.execute(release.CONSTRAINT_QUERY).fetchone()[0]
            proof = execute(connection, rehearsal)
            if not all(proof[name] for name in ('old_rows_preserved', 'old_identity_acl_preserved',
                                               'only_expected_dispatchers_replaced', 'only_expected_constraint_replaced',
                                               'private_helpers_and_grants_verified', 'roles_preserved')):
                raise AssertionError('Release preservation proof failed')
            if connection.execute(release.CONSTRAINT_QUERY).fetchone()[0] != original:
                raise AssertionError('Rehearsal did not roll back')
            checks.append('rollback_preserves_original_dispatchers_and_constraint')
            mutations = (
                ("update public.rm_clientes set nome='Changed fixture';", 'Old business/Auth/Storage rows changed'),
                ('alter function public.rm_web_mutate_v1(uuid,text,jsonb) security invoker;',
                 'Old function identity/ACL/body changed'),
                (f'grant execute on function {release.ISSUER} to authenticated;',
                 'Old function identity/ACL/body changed'),
                (f'grant execute on function {release.ADDED[0]} to authenticated;',
                 'Workshop operation grants differ'),
                (f'alter table {release.PERMITS} drop constraint {release.CONSTRAINT};',
                 'Resource check attributes changed'),
                ('create view public.local_unwanted_view as select 1 as id;',
                 'Relation identities/ACLs or default grants changed'),
                ('alter default privileges in schema public grant select on tables to authenticated;',
                 'Relation identities/ACLs or default grants changed'),
                ("update supabase_migrations.schema_migrations set name='changed' where version='001';",
                 'Old migration history changed'),
            )
            for sql, expected in mutations:
                try:
                    execute(connection, rehearsal.replace('do $verify$', sql + '\ndo $verify$', 1))
                except psycopg.Error as error:
                    connection.execute('rollback')
                    if expected not in str(error):
                        raise
                else:
                    raise AssertionError('Invalid release was accepted')
            checks.append('rejects_unexpected_sql_data_schema_history_and_grant_changes')
            execute(connection, release.release_sql(source_hash, manifest_hash, apply=True))
            if connection.execute(release.MANIFEST_QUERY).fetchone()[0] != manifest:
                raise AssertionError('Committed objects differ from reviewed manifest')
            grants = connection.execute(release.FUNCTION_GRANTS).fetchone()[0]
            if not all(grants.values()):
                raise AssertionError('A committed grant differs')
            checks.append('commit_keeps_old_acl_history_and_expected_resource_constraint')

        support = (Path(__file__), Path(release.__file__), Path(release.baseline.__file__))
        record = {
            'local_only': True,
            'production_data_copied': False,
            'source_sha256': source_hash,
            'manifest_sha256': manifest_hash,
            'checks': checks,
            'preservation_mutations_refused': len(mutations),
            'support_sha256': {path.name: sha256(path) for path in support},
        }
        target = release.ROOT.parent / '.tmp/workshop-operations-local-release-proof.json'
        target.parent.mkdir(exist_ok=True)
        target.write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(record), flush=True)
        success = True
    finally:
        if running:
            command('pg_ctl', '-D', str(data), '-m', 'fast', '-w', 'stop')
        if success:
            if directory.parent != temporary_parent or not directory.name.startswith('em-workshop-operations-'):
                raise RuntimeError('Unexpected temporary PostgreSQL cleanup target')
            shutil.rmtree(directory)
        else:
            print(f'Diagnostic files preserved at {directory}', flush=True)


if __name__ == '__main__':
    main()

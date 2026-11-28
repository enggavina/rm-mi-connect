"""Exercise Acessos and the EM in two databases in the same disposable local cluster."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from hashlib import sha256
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from time import time
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx
import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[2]
AUTHORITY = 'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
READER_KEY = 'k' * 43
OFFICE_SAVE = '/v2/admin/em/workshops/save'
BINDING_SAVE = '/v2/admin/em/workshop-bindings/save'
COMMENTS = 'rm_add_cell_comment_v1'


def identifier(number):
    return f'60930000-0000-4000-8000-{number:012}'


def authorization(identity):
    return {'Authorization': f'Bearer synthetic_lifecycle_user.{identity}.fixture'}


def rpc(connection, name, *values):
    statement = sql.SQL('select public.{}({})').format(sql.Identifier(name), sql.SQL(',').join(sql.Placeholder() for _ in values))
    return connection.execute(statement, values).fetchone()[0]


def role(connection, name, subject=None, session=None):
    claims = {'role': name, 'sub': subject, 'aal': 'aal2', 'iss': AUTHORITY, 'session_id': session, 'exp': int(time()) + 900}
    connection.execute("select set_config('request.jwt.claims',%s,true),set_config('request.jwt.claim.sub',%s,true)",
                       (json.dumps(claims), subject or ''))
    connection.execute(sql.SQL('set local role {}').format(sql.Identifier(name)))


@contextmanager
def central_http(source, dsn):
    from permissions.app import create_app
    from permissions.config import AUTH_URL, Settings
    from permissions.service import PermissionsClient
    from permissions.workshops import WorkshopClient

    key = 'sb_publishable_synthetic_lifecycle_test'
    settings = Settings(origin='https://authority.example.test', supabase_url=AUTH_URL, publishable_key=key)
    users = {authorization(label)['Authorization'][7:]: user
             for label, user in [('admin', source.A), ('bma', source.B), ('brj', source.U)]}

    def local_supabase(request):
        assert request.url.host == AUTH_URL.removeprefix('https://') and not request.url.query
        assert request.headers['apikey'] == key
        token = request.headers.get('authorization', '').removeprefix('Bearer ')
        subject = users.get(token)
        if request.url.path == '/auth/v1/user':
            return httpx.Response(200 if subject else 401, json={'id': subject, 'app_metadata': {'provider': 'azure'}})
        assert request.url.path.startswith('/rest/v1/rpc/')
        name = request.url.path.rsplit('/', 1)[-1]
        assert name in {'cp_admin_set_em_workshop_v1', 'cp_admin_set_em_workshop_binding_v1',
                        'cp_my_em_workshop_context_v1', 'cp_em_mobile_workshop_context_v1'}
        server_reader = name == 'cp_em_mobile_workshop_context_v1'
        assert subject or server_reader and not token
        # Only the hosted Auth/REST transport is replaced. The authority SQL
        # decides every response using synthetic identities in the local cluster.
        args = json.loads(request.content or '{}')
        try:
            with psycopg.connect(dsn) as connection:
                role(connection, 'anon' if server_reader else 'authenticated', subject)
                statement = sql.SQL('select public.{}({})').format(sql.Identifier(name), sql.SQL(',').join(
                    sql.SQL('{} => {}').format(sql.Identifier(k), sql.Placeholder()) for k in args))
                value = connection.execute(statement, tuple(args.values())).fetchone()[0]
            return httpx.Response(200, json=value)
        except psycopg.Error as error:
            if error.sqlstate not in {'42501', '22023', 'PT409'}:
                print(f'Unexpected fixture SQL error in {name}: {error.sqlstate} {error.diag.message_primary}', file=sys.stderr)
            return httpx.Response({'42501': 403, '22023': 400, 'PT409': 409}.get(error.sqlstate, 500),
                                  json={'code': error.sqlstate, 'message': 'Local authority fixture'})

    transport = httpx.MockTransport(local_supabase)
    permissions = PermissionsClient(settings, transport=transport)
    workshops = WorkshopClient(permissions, reader_token=READER_KEY)
    with TestClient(create_app(settings, client=permissions, workshop_client=workshops)) as client:
        yield client


def workshop(client, fixture, active, revision):
    return client.post(OFFICE_SAVE, headers=authorization('admin'),
                       json=dict(id=fixture['office'], code=fixture['code'], name=fixture['code'], active=active, expected_revision=revision))


def change_binding(client, office, kind, subject, enabled, revision):
    response = client.post(BINDING_SAVE, headers=authorization('admin'),
        json=dict(kind=kind, subject=subject, label=f'{office["code"]} {kind}', workshop_id=office['office'],
                  enabled=enabled, expires_at=None, expected_revision=revision))
    assert response.status_code == 200 and response.json()['enabled'] == enabled, response.status_code


def context(client, fixture, channel):
    if channel == 'web':
        return client.get('/v2/me/em/workshop-context', headers=authorization(fixture['code'].lower()))
    return client.post('/v2/services/em/workshop-context', headers={'Authorization':'Bearer ' + READER_KEY},
                       json=dict(device_subject=fixture['device'], operator_subject=fixture['operator']))


def prepare_em(central_dsn, offices, spare_office):
    connection_params = conninfo_to_dict(central_dsn)
    assert connection_params['host'] == '127.0.0.1' and connection_params['dbname'] == 'em_workshop_fixture'
    database = 'em_lifecycle_fixture'
    with psycopg.connect(central_dsn, autocommit=True) as connection:
        connection.execute(sql.SQL('create database {}').format(sql.Identifier(database)))
    dsn = make_conninfo(central_dsn, dbname=database)
    files = [ROOT / 'rm-mobile-supabase/tests/bootstrap.sql', *sorted((ROOT / 'rm-mobile-supabase/migrations').glob('*.sql'))]
    args = ['psql', '-X', '-q', '-w', '-d', dsn, '-v', 'ON_ERROR_STOP=1', '-c', 'set client_min_messages=warning']
    for path in files:
        args.extend(['-f', str(path)])
    completed = subprocess.run(args, capture_output=True, timeout=180)
    if completed.returncode:
        raise RuntimeError(completed.stderr.decode('utf-8', errors='replace')[-1000:])

    with psycopg.connect(dsn) as db:
        adoption = [{'id': f['office'], 'code': f['code']} for f in offices] + [{'id': spare_office, 'code': 'BBH'}]
        manifest = ROOT / 'rm-mobile-supabase/workshops/adoption.json'
        db.execute('select rm_private.workshop_adopt_bma_roots_v1(%s,%s,0,0)', (Jsonb(adoption), sha256(manifest.read_bytes()).hexdigest()))
        db.execute('update rm_private.sso_settings set require_sso=true where singleton')
        for f in offices:
            db.execute('insert into auth.users(id) values(%s),(%s)', (f['device'], f['web_auth']))
            db.execute('insert into auth.sessions(id,user_id) values(%s,%s),(%s,%s)',
                       (f['device_session'], f['device'], f['web_session'], f['web_auth']))
            db.execute("insert into public.rm_users(id,auth_user_id,nome,perfil,matricula) values(%s,%s,'Tablet local','mobile',null),"
                       "(%s,null,'Operador local','mobile',%s),(%s,%s,'PCP local','administrador',null)",
                       (f['tablet'], f['device'], f['operator'], 'OP-' + f['code'], f['web_profile'], f['web_auth']))
            db.execute("insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) "
                       "values(extensions.digest(%s,'sha256'),%s,%s,%s,clock_timestamp()+interval '45 minutes')",
                       (f['delegation'], f['device'], f['tablet'], f['operator']))
            db.execute('insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) '
                       'values(%s,%s,%s,%s,%s,true,%s,clock_timestamp())',
                       (f['binding'], AUTHORITY, f['viewer'], f['web_profile'], f['web_auth'], f['web_profile']))
            db.execute("insert into public.rm_projetos(id,numero,nome,status_pcp) values(%s,'OS-IGUAL-QA',%s,'executando')", (f['project'], f['code']))
            db.execute('insert into rm_private.workshop_project_ownership(id,workshop_id) values(%s,%s)', (f['project'], f['office']))
            db.execute('insert into public.rm_celulas(id,nome) values(%s,%s)', (f['cell'], f['code']))
            db.execute('insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(%s,%s)', (f['cell'], f['office']))
            if f['code'] == 'BMA':
                db.execute('insert into public.rm_tablet_celula_users(celula_id,identidade_id) values(%s,%s)', (f['cell'], f['operator']))
            db.execute("insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite) "
                       "values(%s,%s,%s,'em_dia',true,current_date,current_date+3)", (f['allocation'], f['project'], f['cell']))
    return dsn


def portal_gantt(dsn, fixture, grant):
    filters = dict(project_id=None, cell_id=None, include_closed=False, project_details=True, can_manage=False)
    with psycopg.connect(dsn) as db:
        role(db, 'service_role', fixture['web_auth'], fixture['web_session'])
        db.execute("select public.rm_sso_session_put_v1(%s,%s,%s,'lifecycle-fixture-session',clock_timestamp()+interval '5 minutes')",
                   (fixture['delegation'], fixture['binding'], fixture['web_session']))
        request = str(uuid4())
        rpc(db, 'rm_sso_workshop_read_permit_v1', fixture['delegation'], request, 'gantt_snapshot', Jsonb(filters), Jsonb(grant))
        role(db, 'authenticated', fixture['web_auth'], fixture['web_session'])
        data = rpc(db, 'rm_web_workshop_read_v1', request, 'gantt_snapshot', Jsonb(filters))
        assert data['workshop_id'] == fixture['office']
        assert [row['id'] for row in data['data']['items']] == [fixture['allocation']]


def send_comment(dsn, fixture, grant, protocol, text):
    payload = Jsonb({'p_celula_projeto_id': fixture['allocation'], 'p_comentario': text})
    with psycopg.connect(dsn) as db:
        role(db, 'service_role')
        rpc(db, 'rm_authorize_mobile_workshop_mutation_v1', fixture['device'], fixture['device_session'], fixture['delegation'],
            Jsonb(grant), protocol, COMMENTS, payload)
    with psycopg.connect(dsn) as db:
        role(db, 'authenticated', fixture['device'], fixture['device_session'])
        return rpc(db, 'rm_mobile_workshop_mutate_v1', protocol, COMMENTS, payload, fixture['delegation'])


def assert_active(client, dsn, fixture):
    reply = context(client, fixture, 'web')
    assert reply.status_code == 200 and reply.headers['cache-control'] == 'no-store', reply.status_code
    portal_gantt(dsn, fixture, reply.json())
    reply = context(client, fixture, 'mobile')
    assert reply.status_code == 200 and reply.headers['cache-control'] == 'no-store', reply.status_code
    grant = reply.json()
    assert operation_cells(dsn, fixture, grant) == [fixture['cell']]
    return grant


def operation_cells(dsn, fixture, grant):
    with psycopg.connect(dsn) as db:
        role(db, 'service_role')
        cells = rpc(db, 'rm_online_operation_read_v1', fixture['device'], fixture['device_session'], fixture['delegation'],
                    Jsonb(grant), None, None, 1)
        assert cells['kind'] == 'cells'
        ids = [cell['id'] for cell in cells['items']]
        android = rpc(db, 'rm_mobile_workshop_catalog_v1', fixture['device'], fixture['device_session'],
                      fixture['delegation'], Jsonb(grant), 'rm_celulas', None, None, False)
        assert [cell['id'] for cell in android['rows']] == ids
        return ids


def cell_permissions(central_dsn, dsn, fixture, cell, change=None, local_role='service_role'):
    with psycopg.connect(central_dsn) as central:
        role(central, 'authenticated', fixture['viewer'])
        team = rpc(central, 'cp_my_em_workshop_team_v1')
    with psycopg.connect(dsn) as db:
        role(db, local_role, fixture['web_auth'], fixture['web_session'])
        return rpc(db, 'rm_sso_cell_operators_v1', fixture['delegation'], Jsonb(team['context']), Jsonb(team['members']),
                   cell, Jsonb(change) if change else None)


def deny_cell_permission(state, *args, **kwargs):
    try:
        cell_permissions(*args, **kwargs)
    except psycopg.Error as error:
        assert error.sqlstate == state, (error.sqlstate, error.diag.message_primary)
    else:
        raise AssertionError(f'Expected refusal {state}')


def snapshot(dsn):
    with psycopg.connect(dsn) as db:
        return [db.execute(sql.SQL("select md5(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text) from {} r").format(
            sql.Identifier(*name.split('.')))).fetchone()[0] for name in (
            'public.rm_projetos', 'public.rm_celulas_projeto', 'public.rm_comentarios', 'rm_private.mobile_mutation_receipts')]


def exercise(source, central_dsn, _metadata, central_source):
    with psycopg.connect(central_dsn, autocommit=True) as db:
        from scripts.prepare_em_workshops_release import release_sql

        db.execute(release_sql(sha256(source.PROPOSAL.read_bytes()).hexdigest(), apply=True))
        db.execute("insert into permission_private.em_workshop_service_keys(application,token_sha256,active) values('em',%s,true)",
                   (sha256(READER_KEY.encode()).hexdigest(),))
        for capability in ('em.planning.read', 'em.catalogs.read'):
            db.execute("insert into permission_private.permissions(app_id,code,label,kind,is_active) "
                       "values(%s,%s,'Permissão local','function',true)", (source.APP, capability))
            for viewer in (source.B, source.U):
                db.execute("insert into permission_private.grants(subject,app_id,permission_code,granted_by) "
                           "values(%s,%s,%s,%s)", (viewer, source.APP, capability, source.A))
        team_contract = central_source / 'supabase/proposals/20261127_em_workshop_team.sql'
        # The original schema capture predates the roster's MFA check.
        db.execute('create table if not exists auth.mfa_factors (user_id uuid, factor_type text, status text)')
        db.execute(team_contract.read_text(encoding='utf-8'))
    offices = []
    names = ('device', 'device_session', 'tablet', 'operator', 'web_auth', 'web_profile', 'web_session', 'binding', 'project', 'cell', 'allocation')
    for index, (office, code, viewer) in enumerate(((source.W1, 'BMA', source.B), (source.W2, 'BRJ', source.U)), 1):
        offices.append(dict(office=office, code=code, viewer=viewer, delegation=str(index)*64,
                            **{name: identifier(index*100 + i) for i, name in enumerate(names)}))
    bma, brj = offices
    dsn = prepare_em(central_dsn, offices, identifier(500))
    checks = []
    with central_http(source, central_dsn) as client:
        for fixture, active in ((bma, True), (brj, False)):
            reply = workshop(client, fixture, active, 0)
            assert reply.status_code == 200, (fixture['code'], reply.status_code)
            for kind, field in (('corporate', 'viewer'), ('device', 'device'), ('operator', 'operator')):
                change_binding(client, fixture, kind, fixture[field], active, 0)
        assert context(client, brj, 'web').status_code == context(client, brj, 'mobile').status_code == 403
        bma_grant = assert_active(client, dsn, bma)
        checks.append('Staging disabled grants keeps BMA working and BRJ closed')

        with psycopg.connect(dsn) as db:
            rpc(db, 'rm_observe_mobile_workshop_android_v1', bma['device'], bma['device_session'], bma['delegation'], Jsonb(bma_grant), '1.2.24', 27)
            db.execute('select rm_private.activate_workshop_legacy_bma_catalog_v1(%s,%s)', (bma['device'], bma['device_session']))
            for gate in ('activate_workshop_legacy_bma_operations_v1', 'activate_workshop_legacy_bma_people_v1',
                         'activate_workshop_legacy_operator_reads_v1', 'activate_workshop_legacy_mobile_writes_v1'):
                db.execute(sql.SQL('select rm_private.{}()').format(sql.Identifier(gate)))
        assert workshop(client, brj, True, 1).status_code == 200
        assert context(client, brj, 'web').status_code == context(client, brj, 'mobile').status_code == 403
        change_binding(client, brj, 'device', brj['device'], True, 1)
        assert context(client, brj, 'mobile').status_code == 403
        change_binding(client, brj, 'operator', brj['operator'], True, 1)
        change_binding(client, brj, 'corporate', brj['viewer'], True, 1)
        portal_gantt(dsn, brj, context(client, brj, 'web').json())
        assert operation_cells(dsn, brj, context(client, brj, 'mobile').json()) == []
        row = cell_permissions(central_dsn, dsn, brj, brj['cell'])[0]
        assert row['id'] == brj['operator'] and row['revision'] == 0 and not row['managed'] and not row['legacy']
        grant = dict(operator=brj['operator'], enabled=True, revision=0)
        deny_cell_permission('42501', central_dsn, dsn, brj, brj['cell'], grant, local_role='authenticated')
        deny_cell_permission('42501', central_dsn, dsn, bma, brj['cell'], grant)
        deny_cell_permission('42501', central_dsn, dsn, brj, brj['cell'], {**grant, 'operator': bma['operator']})
        def concurrent_grant(_):
            try:
                assert cell_permissions(central_dsn, dsn, brj, brj['cell'], grant) == {'changed': True}
                return 'granted'
            except psycopg.Error as error:
                return error.sqlstate

        with ThreadPoolExecutor(max_workers=2) as workers:
            assert sorted(workers.map(concurrent_grant, range(2))) == ['PT409', 'granted']
        deny_cell_permission('PT409', central_dsn, dsn, brj, brj['cell'], grant)
        assert operation_cells(dsn, brj, context(client, brj, 'mobile').json()) == [brj['cell']]
        assert cell_permissions(central_dsn, dsn, brj, brj['cell'], {**grant, 'enabled': False, 'revision': 1}) == {'changed': True}
        assert operation_cells(dsn, brj, context(client, brj, 'mobile').json()) == []
        assert cell_permissions(central_dsn, dsn, brj, brj['cell'], {**grant, 'revision': 2}) == {'changed': True}
        bma_row = cell_permissions(central_dsn, dsn, bma, bma['cell'])[0]
        assert bma_row['legacy'] and not bma_row['managed']
        assert cell_permissions(central_dsn, dsn, bma, bma['cell'],
                                {'operator': bma['operator'], 'enabled': False, 'revision': 0}) == {'changed': False}
        with psycopg.connect(dsn) as db:
            audit = db.execute('select enabled,actor_id,workshop_id from rm_private.workshop_cell_operator_events '
                               'where operator_id=%s order by revision', (brj['operator'],)).fetchall()
            assert [(state, str(actor), str(office)) for state, actor, office in audit] == [
                (state, brj['web_profile'], brj['office']) for state in (True, False, True)]
        checks.append('A fresh BRJ operator receives and loses the first cell through current roster and local admin authorization')

        brj_grant = assert_active(client, dsn, brj)
        assert_active(client, dsn, bma)
        checks.append('Explicit activation and bindings authorize each Gantt and operational catalog independently')

        protocol = str(uuid4())
        pending_text = 'Comentário preservado após perda da confirmação no ensaio local'
        written = send_comment(dsn, brj, brj_grant, protocol, pending_text)
        assert written['projeto_id'] == brj['project']
        preserved = snapshot(dsn)
        assert workshop(client, brj, False, 2).status_code == 200
        assert context(client, brj, 'web').status_code == context(client, brj, 'mobile').status_code == 403
        assert_active(client, dsn, bma)
        assert snapshot(dsn) == preserved
        checks.append('Suspension rejects both contexts while BMA and EM business records remain intact')

        assert workshop(client, brj, True, 2).status_code == 409
        assert context(client, brj, 'mobile').status_code == 403
        assert workshop(client, brj, True, 3).status_code == 200
        brj_grant = assert_active(client, dsn, brj)
        assert brj_grant['workshop']['revision'] == 4
        replay = send_comment(dsn, brj, brj_grant, protocol, pending_text)
        assert replay['idempotent_replay'] is True and replay['comentario_id'] == written['comentario_id']
        assert snapshot(dsn) == preserved
        checks.append('Fresh reactivation replays the original offline acknowledgement exactly once')

        original_code = str(uuid4())
        text = 'Registro local de ida e volta entre oficinas'
        bma_grant = context(client, bma, 'mobile').json()
        original = send_comment(dsn, bma, bma_grant, original_code, text)
        before_transfer = snapshot(dsn)
        change_binding(client, brj, 'device', bma['device'], True, 1)
        assert context(client, bma, 'mobile').status_code == 403
        change_binding(client, brj, 'operator', bma['operator'], True, 1)
        moved = context(client, bma, 'mobile')
        assert moved.status_code == 200 and moved.json()['workshop']['id'] == brj['office']
        try:
            send_comment(dsn, bma, moved.json(), original_code, text)
        except psycopg.Error as exc:
            assert exc.sqlstate in ('42501', 'PT404'), exc.sqlstate
        else:
            raise AssertionError('The transferred pair could replay a protocol still owned by BMA')
        assert snapshot(dsn) == before_transfer
        checks.append('A physically transferred device and operator cannot replay the original workshop protocol')

        change_binding(client, bma, 'device', bma['device'], True, 2)
        assert context(client, bma, 'mobile').status_code == 403
        change_binding(client, bma, 'operator', bma['operator'], True, 2)
        returned = context(client, bma, 'mobile')
        assert returned.status_code == 200 and returned.json()['workshop']['id'] == bma['office']
        again = send_comment(dsn, bma, returned.json(), original_code, text)
        assert again['comentario_id'] == original['comentario_id'] and again['idempotent_replay'] is True
        assert snapshot(dsn) == before_transfer
        checks.append('Returning the original pair to its own workshop preserves the exact business receipt')

    with psycopg.connect(central_dsn) as db:
        history = db.execute("select (after_state->>'active')::boolean,actor from permission_private.em_workshop_audit "
                             "where workshop_id=%s and action in('workshop.create','workshop.update') order by id", (brj['office'],)).fetchall()
        assert [(active, str(actor)) for active, actor in history] == [(value, source.A) for value in (False, True, False, True)]
        bindings = db.execute('select enabled,revision from permission_private.em_workshop_bindings where workshop_id=%s', (brj['office'],)).fetchall()
        assert bindings == [(True, 2)] * 3
        checks.append('Central audit records all four lifecycle states and preserves the original three active bindings')

    return {'checks': checks, 'passed': len(checks), 'isolated_central_and_em': True, 'production_writes': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--central-source', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    path = args.central_source.resolve() / 'scripts/test_em_workshops_sql_local.py'
    spec = importlib.util.spec_from_file_location('central_workshop_fixture', path)
    source = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source)
    sys.argv = [sys.argv[0], '--metadata', str(args.metadata), '--report', str(args.report)]
    source.main(lambda dsn, metadata: exercise(source, dsn, metadata, args.central_source.resolve()))

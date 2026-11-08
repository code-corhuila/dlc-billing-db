"""Apply only to the specifically inspected legacy local Docker test database."""
import json
import os
from pathlib import Path
import secrets
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
DOCKER = 'C:/Program Files/Docker/Docker/resources/bin/docker.exe'
TARGET = 'dlc-billing-db'
DATABASE = 'dlc-billing-db'


def main():
    password = secrets.token_urlsafe(32)
    login = 'billing_deploy_' + uuid4().hex[:12]
    env = dict(os.environ, LIQUIBASE_COMMAND_PASSWORD=password, DEPLOY_PASSWORD=password)

    def run(*args, stdin=None):
        p = subprocess.run([DOCKER, *args], input=stdin, text=True, encoding='utf-8',
                           capture_output=True, env=env, timeout=180)
        if p.returncode:
            raise RuntimeError((p.stdout+p.stderr).replace(password, '[redacted]')[-4000:])
        return p.stdout

    def sql(body):
        return run('exec', '-i', '-e', 'DEPLOY_PASSWORD', TARGET, 'psql', '-U', 'billing_test',
                   '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', '-At', stdin=body)

    output = ROOT / '.local-validation'
    output.mkdir(exist_ok=True)
    backup = 'billing-before-' + uuid4().hex[:12] + '.dump'
    run('exec', TARGET, 'pg_dump', '-U', 'billing_test', '-d', DATABASE, '-Fc', '-f', '/tmp/'+backup)
    run('cp', TARGET+':/tmp/'+backup, str(output/backup))
    query = """SELECT 'prices',count(*),md5(COALESCE(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text),'')) FROM billing.procedure_prices t
    UNION ALL SELECT 'rules',count(*),md5(COALESCE(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text),'')) FROM billing.additional_price_rules t
    UNION ALL SELECT 'replays',count(*),md5(COALESCE(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text),'')) FROM billing.idempotency_records t;"""
    before = sql(query)
    history_table = ('billing.databasechangelog' if sql(
        "SELECT to_regclass('billing.databasechangelog') IS NOT NULL;").strip()=='t'
        else 'public.databasechangelog')
    prior_count = int(sql('SELECT count(*) FROM '+history_table+';').strip())
    history = sql('SELECT id,author,filename,md5sum FROM '+history_table+' ORDER BY orderexecuted;')
    if sql("SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='billing';").strip()=='billing_test':
        sql((ROOT/'deploy/legacy-local-owner-transition.sql').read_text(encoding='utf-8'))
    sql((ROOT/'deploy/bootstrap.sql').read_text(encoding='utf-8'))
    sql("\\getenv password DEPLOY_PASSWORD\nCREATE ROLE " + login + " LOGIN PASSWORD :'password'; GRANT billing_migrator TO "
        + login + "; ALTER ROLE " + login + " SET role='billing_migrator';")
    try:
        def migrate(command):
            result = run('run', '--rm', '--network', 'dlc-billing-test-net', '--mount',
                f'type=bind,source={ROOT},target=/workspace,readonly', '-e', 'LIQUIBASE_COMMAND_PASSWORD',
                'liquibase/liquibase:4.31.1', '--search-path=/workspace',
                '--changelog-file=changelog/changelog-master.yaml',
                '--url=jdbc:postgresql://'+TARGET+':5432/'+DATABASE, '--username='+login,
                '--default-schema-name=billing', '--liquibase-schema-name=billing', command)
            (output/('liquibase-'+command+'.log')).write_text(result,encoding='utf-8')
            print('Local Liquibase:',command,flush=True)
        migrate('validate')
        migrate('update')
        migrate('status')
        if before != sql(query):
            raise AssertionError('Existing financial data changed')
        if history != sql('SELECT id,author,filename,md5sum FROM billing.databasechangelog WHERE orderexecuted<='
                          +str(prior_count)+' ORDER BY orderexecuted;'):
            raise AssertionError('Historical changeset identities/checksums changed')
        result = dict(target=TARGET,database=DATABASE,backup=backup,
            changesets=sql('SELECT count(*) FROM billing.databasechangelog;').strip(),
            methods=sql('SELECT method FROM billing.payment_methods WHERE active ORDER BY method;').splitlines(),
            existing_data_preserved=True,old_history_preserved=True,
            correction_applied=sql("SELECT count(*) FROM billing.databasechangelog WHERE id='billing-031-financial-boundaries';").strip()=='1')
        (output/'application-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps(result),flush=True)
    finally:
        sql('DROP ROLE '+login+';')


if __name__=='__main__':
    main()

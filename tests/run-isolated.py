"""Run the real changelog and every SQL suite on disposable PostgreSQL 16 only."""
import os
from pathlib import Path
import secrets
import shutil
import runpy
import subprocess
import sys
import time
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def main():
    docker = shutil.which('docker')
    if not docker:
        candidate = Path('C:/Program Files/Docker/Docker/resources/bin/docker.exe')
        docker = str(candidate) if candidate.is_file() else 'docker'
    prefix = 'billing-db-test-' + uuid4().hex[:12]
    password = secrets.token_urlsafe(32)
    env = dict(os.environ, POSTGRES_PASSWORD=password, TEST_DB_PASSWORD=password,
               LIQUIBASE_COMMAND_PASSWORD=password)

    def run(*args, stdin=None):
        result = subprocess.run([docker, *args], input=stdin, text=True, encoding='utf-8',
                                capture_output=True, env=env, timeout=180)
        if result.returncode:
            raise RuntimeError((result.stdout + result.stderr).replace(password, '[redacted]')[-4000:])
        return result.stdout

    def sql(body, database='billing_test'):
        return run('exec', '-i', '-w', '/workspace/tests', '-e', 'TEST_DB_PASSWORD', prefix, 'psql',
                   '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', stdin=body)

    def migrate(command, source=ROOT, database='billing_test'):
        print('Liquibase:', command, flush=True)
        return run('run', '--rm', '--network', prefix, '--mount',
                   f'type=bind,source={source},target=/workspace,readonly',
                   '-e', 'LIQUIBASE_COMMAND_PASSWORD', 'liquibase/liquibase:4.31.1',
                   '--search-path=/workspace', '--changelog-file=changelog/changelog-master.yaml',
                   '--url=jdbc:postgresql://postgres:5432/' + database, '--username=billing_migrator',
                   '--default-schema-name=billing', '--liquibase-schema-name=billing', command)

    network = container = False
    try:
        run('version', '--format', '{{.Server.Version}}')
        run('network', 'create', prefix)
        network = True
        api_options = ['-p', '127.0.0.1::5432'] if '--api-only' in sys.argv else []
        run('run', '-d', '--name', prefix, '--network', prefix, '--network-alias', 'postgres',
            '--mount', f'type=bind,source={ROOT},target=/workspace,readonly',
            *api_options, '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_DB=billing_test', 'postgres:16-alpine')
        container = True
        for _ in range(60):
            try:
                sql('SELECT 1;')
                break
            except RuntimeError:
                time.sleep(1)
        else:
            raise RuntimeError('Disposable PostgreSQL did not become ready')
        sql((ROOT / 'deploy/bootstrap.sql').read_text(encoding='utf-8'))
        sql("\\getenv password TEST_DB_PASSWORD\nALTER ROLE billing_migrator PASSWORD :'password';")
        migrate('validate')
        migrate('update')
        before = sql('SELECT count(*) FROM billing.databasechangelog;')
        migrate('update')
        if sql('SELECT count(*) FROM billing.databasechangelog;') != before:
            raise RuntimeError('Repeat migration changed history')
        # Exercise the seed against pre-existing owner choices, including a missing code.
        seed = (ROOT / '02_dml/00_inserts/030_payment_methods.sql').read_text(encoding='utf-8')
        sql("BEGIN; SET LOCAL ROLE billing_migrator; "
            "UPDATE billing.payment_methods SET active=false WHERE method='CASH'; "
            "DELETE FROM billing.payment_methods WHERE method='OTHER'; "
            "INSERT INTO billing.payment_methods(method,active) VALUES('OWNER_CUSTOM',false); "
            + seed + """
            DO $$ BEGIN
              IF NOT EXISTS(SELECT FROM billing.payment_methods WHERE method='CASH' AND NOT active)
                OR NOT EXISTS(SELECT FROM billing.payment_methods WHERE method='OWNER_CUSTOM' AND NOT active)
                OR NOT EXISTS(SELECT FROM billing.payment_methods WHERE method='OTHER' AND active)
              THEN RAISE EXCEPTION 'Payment seed overwrote owner choices or omitted missing code'; END IF;
            END $$; ROLLBACK;
            """)
        print('PASS: payment method seed preserves owner configuration', flush=True)
        if '--api-only' in sys.argv:
            runpy.run_path(str(ROOT / 'tests/support/api-compatibility.py'))['verify'](ROOT, prefix, run, sql, password)
        else:
            for suite in sorted((ROOT / 'tests').glob('*.sql')):
                sql(suite.read_text(encoding='utf-8-sig'))
                print('PASS:', suite.name, flush=True)
            runpy.run_path(str(ROOT / 'tests/support/boundary-concurrency.py'))['verify'](docker, prefix, env, sql)
        if '--upgrade' in sys.argv or '--restore' in sys.argv:
            runpy.run_path(str(ROOT / 'tests/support/upgrade-recovery.py'))['verify'](
                ROOT, prefix, run, sql, migrate, '--upgrade' in sys.argv, '--restore' in sys.argv)
        print('PASS: real Liquibase validation, update and repeat update', flush=True)
    finally:
        # Only exact UUID-named resources created by this run; no volumes/host ports.
        try:
            if container:
                run('rm', '-f', '-v', prefix)
        finally:
            if network:
                run('network', 'rm', prefix)


if __name__ == '__main__':
    main()

"""Fresh shared PostgreSQL only. No external database URL or credentials accepted."""
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
APPOINTMENTS = Path(os.environ['APPOINTMENTS_DB_SOURCE']).resolve()
PREFIX = 'billing-extension-test-' + uuid4().hex[:12]
PASSWORD = secrets.token_urlsafe(32)
CONTAINER = PREFIX + '-postgres'


def run(*args, stdin=None):
    result = subprocess.run(args, input=stdin, capture_output=True, text=True,
                            env=dict(os.environ, TEST_DB_PASSWORD=PASSWORD,
                                     POSTGRES_PASSWORD=PASSWORD,
                                     LIQUIBASE_COMMAND_PASSWORD=PASSWORD), timeout=180)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).replace(PASSWORD, '[redacted]')[-3500:])
    return result.stdout


def sql(text):
    return run('docker', 'exec', '-i', '-e', 'TEST_DB_PASSWORD', CONTAINER,
               'psql', '-U', 'postgres', '-d', 'di_lucca', '-v', 'ON_ERROR_STOP=1', stdin=text)


def migrate(source, owner, history):
    run('docker', 'run', '--rm', '--network', PREFIX, '--mount',
        f'type=bind,source={source},target=/workspace,readonly',
        '-e', 'LIQUIBASE_COMMAND_PASSWORD', 'liquibase/liquibase:4.31.1',
        '--search-path=/workspace', '--changelog-file=changelog/changelog-master.yaml',
        '--url=jdbc:postgresql://postgres:5432/di_lucca', '--username=' + owner + '_migrator',
        '--default-schema-name=' + owner, '--liquibase-schema-name=' + history,
        'update', '--context-filter=qa')


created = False
network = False
try:
    run('docker', 'network', 'create', PREFIX)
    network = True
    run('docker', 'run', '-d', '--name', CONTAINER, '--network', PREFIX,
        '--network-alias', 'postgres', '-e', 'POSTGRES_PASSWORD',
        '-e', 'POSTGRES_DB=di_lucca', 'postgres:16-alpine')
    created = True
    for _ in range(60):
        try:
            sql('SELECT 1;')
            break
        except RuntimeError:
            time.sleep(1)
    else:
        raise RuntimeError('Disposable PostgreSQL did not become ready')
    sources = (APPOINTMENTS, ROOT) if '--appointments-first' in sys.argv else (ROOT, APPOINTMENTS)
    for source in sources:
        sql((source / 'deploy/bootstrap.sql').read_text())
    for role in ('appointments_migrator', 'billing_migrator'):
        sql("\\getenv password TEST_DB_PASSWORD\nALTER ROLE " + role + " PASSWORD :'password';")
    migrate(APPOINTMENTS, 'appointments', 'appointments_liquibase')
    migrate(ROOT, 'billing', 'billing')
    sql((APPOINTMENTS / 'deploy/bootstrap.sql').read_text())
    sql((ROOT / 'deploy/bootstrap.sql').read_text())
    migrate(ROOT, 'billing', 'billing')
    sql("""DO $$ BEGIN
      IF (SELECT n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
          WHERE e.extname='btree_gist') <> 'appointments_extensions'
        OR has_schema_privilege('billing_runtime','appointments_extensions','USAGE')
        OR has_schema_privilege('billing_runtime','appointments','USAGE')
        OR has_schema_privilege('appointments_runtime','billing','USAGE')
        OR has_schema_privilege('billing_migrator','appointments_extensions','CREATE')
      THEN RAISE EXCEPTION 'Shared extension or owner isolation violated'; END IF;
    END $$;""")
    for name in ('runtime-permissions', 'billable-snapshots', 'invoice-storage', 'invoice-draft-permissions'):
        sql((ROOT / 'tests' / (name + '.sql')).read_text())
    print('PASS: both real changelogs, repeat bootstrap/migration, shared extension and owner isolation; four Billing SQL suites')
finally:
    # Exact UUID-prefixed resources created above; no external resources or host ports.
    if created:
        run('docker', 'rm', '-f', '-v', CONTAINER)
    if network:
        run('docker', 'network', 'rm', PREFIX)

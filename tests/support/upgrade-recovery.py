"""Upgrade from the committed pre-boundary baseline and logical restore, exclusively in the test cluster."""
from io import BytesIO
from pathlib import Path
import os
import subprocess
import tempfile
import time
from uuid import uuid4
from zipfile import ZipFile


def fingerprint(sql, database, tables=None):
    restriction = '' if tables is None else " AND tablename IN (" + ','.join("'" + t + "'" for t in tables) + ')'
    return sql("""
    SELECT format($query$SELECT %L AS table_name,count(*) AS rows,
      md5(COALESCE(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text),'')) AS fingerprint
      FROM billing.%I t;$query$,tablename,tablename)
    FROM pg_tables WHERE schemaname='billing'
    """ + restriction + " ORDER BY tablename;\n\\gexec\n", database)


def verify(root, container, run, sql, migrate, upgrade, restore):
    source_db = 'billing_test'
    if upgrade:
        # Git archive reads committed source; it never checks out or resets user work.
        revision = subprocess.check_output(['git', 'rev-parse', os.environ.get('BILLING_UPGRADE_BASELINE', '5c0df70')], cwd=root, text=True).strip()
        archive = subprocess.check_output(['git', 'archive', '--format=zip', revision], cwd=root)
        with tempfile.TemporaryDirectory(prefix='billing-upgrade-') as directory:
            baseline = Path(directory).resolve()
            with ZipFile(BytesIO(archive)) as bundle:
                if any(not (baseline / name).resolve().is_relative_to(baseline) for name in bundle.namelist()):
                    raise RuntimeError('Archive path escaped the disposable source directory')
                bundle.extractall(baseline)
            source_db = 'billing_upgrade'
            sql('CREATE DATABASE billing_upgrade;')
            sql((baseline / 'deploy/bootstrap.sql').read_text(encoding='utf-8-sig'), source_db)
            migrate('update', baseline, source_db)
            patient, invoice, payment, price = [str(uuid4()) for _ in range(4)]
            fixture = (root / 'tests/support/invoice-fixture.sql').read_text(encoding='utf-8')
            sql(fixture + f"""
            INSERT INTO billing.payment_methods(method,active) VALUES('CASH',false),('UPGRADE_TEST',true);
            INSERT INTO billing.procedure_prices(price_id,procedure_code,name,base_price,valid_from,version,created_by,created_at,updated_at)
            VALUES('{price}','UPGRADE','Historical price',10.00,now(),1,gen_random_uuid(),now(),now());
            INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
            VALUES('{invoice}','{patient}',10,10,gen_random_uuid());
            SELECT pg_temp.seed_invoice_items('{invoice}');
            UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number='{invoice}',issued_at=now()
            WHERE invoice_id='{invoice}';
            SET ROLE billing_runtime;
            INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
            VALUES('{payment}','{invoice}',4,'UPGRADE_TEST',gen_random_uuid(),now());
            """, source_db)
            tables = ['procedure_prices', 'invoices', 'invoice_items', 'payments', 'billable_items', 'encounter_accounts']
            before = fingerprint(sql, source_db, tables)
            migrate('validate', root, source_db)
            invalid = str(uuid4())
            sql(f"""INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
            VALUES('{invalid}','{patient}',10,10,gen_random_uuid());
            UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number='{invalid}',issued_at=now()
            WHERE invoice_id='{invalid}';""", source_db)
            try:
                migrate('update', root, source_db)
            except RuntimeError as error:
                if 'Existing issued invoice history requires owner reconciliation' not in str(error):
                    raise
            else:
                raise AssertionError('Upgrade certified inconsistent historical invoice')
            # Exact invalid synthetic row owned by this probe; never an automatic
            # recovery procedure for real financial history.
            sql(f"DELETE FROM billing.invoices WHERE invoice_id='{invalid}';", source_db)
            print('PASS: inconsistent historical invoice stops migration without data rewriting', flush=True)
            migrate('update', root, source_db)
            if fingerprint(sql, source_db, tables) != before:
                raise AssertionError('Upgrade changed existing financial data')
            sql("""DO $$ BEGIN
              IF NOT EXISTS(SELECT FROM billing.payment_methods WHERE method='CASH' AND NOT active)
                OR NOT EXISTS(SELECT FROM billing.payment_methods WHERE method='BANK_TRANSFER' AND active)
              THEN RAISE EXCEPTION 'Upgrade changed owner method choices'; END IF;
            END $$;""", source_db)
            migrate('update', root, source_db)
            print('PASS: upgrade from ' + revision[:12] + ' preserves financial row counts/hashes and owner configuration', flush=True)
    if restore:
        before = fingerprint(sql, source_db)
        started = time.monotonic()
        run('exec', container, 'pg_dump', '-U', 'postgres', '-d', source_db,
            '-Fc', '-f', '/tmp/billing-test-backup.dump')
        sql('CREATE DATABASE billing_restored;')
        run('exec', container, 'pg_restore', '-U', 'postgres', '-d', 'billing_restored',
            '--exit-on-error', '/tmp/billing-test-backup.dump')
        if fingerprint(sql, 'billing_restored') != before:
            raise AssertionError('Restore changed table counts or row hashes')
        sql((root / 'tests/runtime-permissions.sql').read_text(encoding='utf-8-sig'), 'billing_restored')
        print(f'PASS: pg_dump/pg_restore, all Billing table fingerprints and restored runtime grants ({time.monotonic()-started:.2f}s)', flush=True)

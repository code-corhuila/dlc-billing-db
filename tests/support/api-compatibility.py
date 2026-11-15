"""Focused real JDBC compatibility tests; disposable loopback-only DB and random secrets."""
import os
from pathlib import Path
import shutil
import subprocess
from xml.etree import ElementTree


def verify(root, container, run, sql, password):
    api = Path(os.environ.get('BILLING_API_SOURCE', str(root.parent / 'dlc-billing-api'))).resolve()
    classes = ['PaymentTransactionTest', 'InvoiceIssuanceTransactionTest',
               'InvoiceDraftTransactionTest', 'PriceCorrectionRecordingTest']
    sql("\\getenv password TEST_DB_PASSWORD\nALTER ROLE billing_runtime PASSWORD :'password';")
    port = run('port', container, '5432/tcp').strip().rsplit(':', 1)[1]
    env = dict(os.environ, BILLING_TEST_JDBC_URL='jdbc:postgresql://127.0.0.1:' + port + '/billing_test',
               BILLING_TEST_DB_USER='billing_migrator', BILLING_TEST_DB_PASSWORD=password,
               BILLING_TEST_RUNTIME_DB_PASSWORD=password)
    result = subprocess.run([shutil.which('mvn') or 'mvn', '-o', '-q', '-Dtest=' + ','.join(classes), 'clean', 'test'],
                            cwd=api, env=env, capture_output=True, text=True, encoding='utf-8',
                            errors='replace', timeout=240)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).replace(password, '[redacted]')[-7000:])
    total = 0
    for name in classes:
        report = api / 'target/surefire-reports' / ('TEST-com.dilucca.billing.infrastructure.persistence.' + name + '.xml')
        suite = ElementTree.parse(report).getroot()
        if any(int(suite.get(key, '0')) for key in ('failures', 'errors', 'skipped')):
            raise AssertionError('API tests failed or skipped: ' + name)
        total += int(suite.get('tests', '0'))
    if not total:
        raise AssertionError('No API compatibility tests executed')
    print(f'PASS: {total} actual API transaction tests, no failures/errors/skips', flush=True)

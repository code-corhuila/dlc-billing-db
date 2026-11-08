"""Real owner HTTP + Chromium acceptance using current Billing schema/artifacts.

Uses the existing owner integration harness. Its users, credentials, databases,
broker and services are disposable; the migrated persistent test DB is untouched.
"""
import os
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
API = ROOT.parent / 'dlc-billing-api'


def main():
    python = API / 'target/event-contract-env/Scripts/python.exe'
    source = API / 'tests/integration'
    env = dict(os.environ,
        PATH='C:/Program Files/Docker/Docker/resources/bin'+os.pathsep+os.environ['PATH'],
        PYTHONUTF8='1', PYTHONPATH=str(source),
        IAM_DB_SOURCE=str(API/'target/real-iam-integration/iam-db'), BILLING_DB_SOURCE=str(ROOT),
        APPOINTMENTS_DB_SOURCE=str(API/'target/appointments-db-source'),
        IAM_RUNTIME_IMAGE='dlc-iam-api:billing-integration-5d53afa',
        BILLING_RUNTIME_IMAGE='dlc-billing-api:db031-local',
        GATEWAY_RUNTIME_IMAGE='dlc-api-gateway:billing-runtime-test',
        APPOINTMENTS_RUNTIME_IMAGE='dlc-appointments-api:billing-integration-73ed387',
        FRONT_RUNTIME_IMAGE='dlc-front:billing-logout-local',
        IAM_PORTAL_IMAGE='dlc-iam-portal:billing-integration',
        BILLING_PORTAL_IMAGE='dlc-billing-portal:db031-local',
        BILLING_PORTAL_RELEASE='2.0.4-local-20261107',
        DLC_DOCS_SOURCE=str(ROOT.parent/'dlc-docs'))
    output = ROOT/'.local-validation'
    output.mkdir(exist_ok=True)
    for required in (python, Path(env['IAM_DB_SOURCE'])/'deploy/bootstrap.sql',
                     Path(env['APPOINTMENTS_DB_SOURCE'])/'deploy/bootstrap.sql',
                     API/'target/browser-runtime/node_modules/playwright'):
        if not required.exists():
            raise RuntimeError('Missing real integration dependency: '+str(required))
    results = {}
    for module in ('test_payment_pdf_real_owners', 'test_browser_financial'):
        print('Starting real integration:',module,flush=True)
        with (output/(module+'.log')).open('w',encoding='utf-8') as log:
            result = subprocess.run([str(python),'-m','unittest',module,'-v'],cwd=API,env=env,
                                    stdout=log,stderr=subprocess.STDOUT,timeout=900)
        if result.returncode:
            raise RuntimeError('Integration failed; inspect private local evidence: '+module+'.log')
        results[module] = 'passed'
        print('PASS:',module,flush=True)
    (output/'integration-result.json').write_text(json.dumps(results,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()

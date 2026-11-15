"""Two real PostgreSQL sessions; explicit row-lock observation, no timing-only assertion."""
from concurrent.futures import ThreadPoolExecutor
import subprocess
import time
from uuid import uuid4


def verify(docker, container, env, sql):
    for issuance_first in (True, False):
        invoice, patient, account, appointment, item, extra = [str(uuid4()) for _ in range(6)]
        sql(f"""
        INSERT INTO billing.encounter_accounts(encounter_account_id,clinical_record_id,consultation_id,patient_id,appointment_id)
        VALUES('{account}',gen_random_uuid(),gen_random_uuid(),'{patient}','{appointment}');
        INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
        item_type,description,quantity,unit_price,created_by,status)
        VALUES('{item}','{account}','{patient}','{appointment}',gen_random_uuid(),gen_random_uuid(),
          'BASE_PROCEDURE','Race first',1,10,gen_random_uuid(),'BILLED'),
        ('{extra}','{account}','{patient}','{appointment}',gen_random_uuid(),gen_random_uuid(),
          'BASE_PROCEDURE','Race extra',1,99,gen_random_uuid(),'BILLED');
        INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
        VALUES('{invoice}','{patient}',10,10,gen_random_uuid());
        INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id) VALUES('{invoice}','{patient}','{item}');
        """)
        issue = (f"UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number='{invoice}',"
                 f"issued_at=clock_timestamp(),updated_at=clock_timestamp() WHERE invoice_id='{invoice}';")
        allocate = f"INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id) VALUES('{invoice}','{patient}','{extra}');"
        first, second = (issue, allocate) if issuance_first else (allocate, issue)
        holder = subprocess.Popen([docker, 'exec', '-i', container, 'psql', '-q', '-U', 'postgres',
                                   '-d', 'billing_test', '-v', 'ON_ERROR_STOP=1'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, encoding='utf-8', env=env)
        try:
            holder.stdin.write('BEGIN; SET LOCAL ROLE billing_runtime;\n' + first + '\n\\echo HELD\n')
            holder.stdin.flush()
            while True:
                line = holder.stdout.readline()
                if line.strip() == 'HELD':
                    break
                if not line:
                    raise RuntimeError('Lock holder failed: ' + holder.stderr.read())
            marker = 'boundary-' + uuid4().hex

            def competing_write():
                try:
                    sql("\\set VERBOSITY verbose\nSET application_name='" + marker
                        + "'; SET ROLE billing_runtime;\n" + second)
                except RuntimeError as error:
                    if '23514' not in str(error):
                        raise
                    return 'rejected'
                return 'accepted'

            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(competing_write)
                try:
                    deadline = time.monotonic() + 10
                    while 'LOCK_OBSERVED' not in sql(
                        "SELECT 'LOCK_OBSERVED' FROM pg_stat_activity WHERE application_name='"
                        + marker + "' AND wait_event_type='Lock';"):
                        if future.done() or time.monotonic() > deadline:
                            raise AssertionError('Competing write did not wait for the invoice lock')
                        time.sleep(0.05)
                finally:
                    holder.stdin.write('COMMIT;\n\\q\n')
                    holder.stdin.flush()
                if future.result(timeout=20) != 'rejected':
                    raise AssertionError('Concurrent write crossed the financial boundary')
            holder.wait(timeout=10)
            if holder.returncode:
                raise RuntimeError('Lock holder commit failed: ' + holder.stderr.read())
            print('PASS: concurrent ' + ('issue then allocation' if issuance_first else 'allocation then issue'), flush=True)
        finally:
            if holder.poll() is None:
                holder.kill()
                holder.wait(timeout=10)

#!/usr/bin/env python3
"""Exercise historical upgrades, export/restoration rollback, schema rules and idempotence.

The target must be a disposable PostgreSQL16 test database. This test resets its
public schema. It never reads .env. Supply the URL and explicit reset switch.
"""
import subprocess,pathlib,json,importlib.util
root=pathlib.Path(__file__).resolve().parents[1]
import os,sys
if sys.argv[1:]!=['--reset-test-schema']:
 raise SystemExit('Usage: test_storage_migration.py --reset-test-schema (isolated test database only)')
url=os.environ.get('REPORTS_NORMALIZED_TEST_DATABASE_URL','')
if not url:raise SystemExit('Set REPORTS_NORMALIZED_TEST_DATABASE_URL explicitly; no .env is loaded')
def sql(s):
 r=subprocess.run(['psql','--dbname',url,'-X','-q','-A','-t','-v','ON_ERROR_STOP=1'],input=s,text=True,capture_output=True)
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout.strip()
spec=importlib.util.spec_from_file_location('rollback',root/'scripts/storage_rollback.py');rollback=importlib.util.module_from_spec(spec);spec.loader.exec_module(rollback)
# Require an explicitly named test database before resetting its isolated schema.
identity=sql('SELECT current_database()')
if not identity.endswith('_test'):raise SystemExit('The database name must end with _test')
print('Isolated migration test database:',identity)
for version in [6,5]:
 sql('DROP SCHEMA public CASCADE; CREATE SCHEMA public;')
 sql((root/f'engine/tests/fixtures/legacy_{version}_schema.sql').read_text())
 definition={'title':{'en':'Legacy','th':'ข้อมูล'},'source':'rows','fields':[{'name':'x','label':{'en':'X'},'type':'integer','role':'measure','unit':None,'decimals':0}],'union':['rows','rows'],'where':[{'field':'x','op':'in','value':[1,2,None,True,'q'] }],'calculator':{'name':'series','x':{'to':3},'exprs':[{'name':'y','expr':'x*x'}]},'value_labels':{'x':{'1':{'en':'One'}}}}
 theme={'light':{'canvas':'#ffffff','surface':'#ffffff','surface_alt':'#ffffff','border':'#ffffff','text_primary':'#ffffff','text_muted':'#ffffff','accent':'#ffffff','on_accent':'#ffffff','positive':'#ffffff','warning':'#ffffff','negative':'#ffffff','info':'#ffffff','caution':'#ffffff','other':'#ffffff','series':['#ffffff']*8},'dark':None}
 q=rollback.literal
 seed="INSERT INTO catalog_projects(slug,name,description,tagline,theme) VALUES('legacy','{\"en\":\"Legacy\",\"pt\":\"Compatível\"}','{}','{}',"+q(json.dumps(theme))+');\n'
 seed+="INSERT INTO reports(project_slug,slug,title,description,metadata) VALUES('legacy','report','{\"en\":\"Report\"}','{}','{\"sort_order\":2,\"tags\":[\"a\",\"a\"],\"card_order\":[\"second\",\"first\"],\"period_source\":{\"collection\":\"rows\",\"field\":\"time\"}}');\n"
 seed+="INSERT INTO report_cards(project_slug,report_slug,card_id,config) VALUES('legacy','report','card','{\"list\":[null,true,1,1.5,\"q\",{},[]],\"nest\":{\"q\":\"__reports_sql_null__\"}}');\nINSERT INTO site_settings(key,value) VALUES('test','{\"nested\":[{\"value\":1}]}');\n"
 if version==6:
  seed+="INSERT INTO calculation_versions(project_slug,calculation_id,version,status,definition) VALUES('legacy','calculation',1,'draft',"+q(json.dumps(definition))+');\n'
  seed+="INSERT INTO datasets(project_slug,report_slug,dataset_id,calculation_id,calculation_version) VALUES('legacy','report','dataset','calculation',1);"
 else:seed+="INSERT INTO datasets(project_slug,report_slug,dataset_id,spec) VALUES('legacy','report','dataset',"+q(json.dumps(definition))+');'
 sql(seed)
 for f in sorted((root/'engine/migrations').glob('*.sql')):sql('BEGIN;\n'+f.read_text()+'\nCOMMIT;')
 assert sql("SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND (data_type IN ('json','jsonb','ARRAY') OR udt_name LIKE '\\_%')")=='0'
 snap=json.loads(sql(rollback.export_sql()))
 print('v'+str(version),'exported tables',len(snap['tables']))
 assert snap['tables']['catalog_projects'][0]['theme']=={'light':theme['light']}
 assert snap['tables']['report_cards'][0]['config']['list']==[None,True,1,1.5,'q',{},[]]
 assert snap['tables']['calculation_versions'][0]['definition']['where'][0]['value']==[1,2,None,True,'q']
 for f in sorted((root/'engine/migrations').glob('*.sql')):sql('BEGIN;\n'+f.read_text()+'\nCOMMIT;')
 assert json.loads(sql(rollback.export_sql()))==snap
 # Restore into historical006, then re-upgrade: canonical snapshot must be identical.
 sql('DROP SCHEMA public CASCADE; CREATE SCHEMA public;')
 sql(rollback.restore_sql(snap,(root/'engine/tests/fixtures/legacy_6_schema.sql').read_text()))
 for f in sorted((root/'engine/migrations').glob('*.sql')):sql('BEGIN;\n'+f.read_text()+'\nCOMMIT;')
 again=json.loads(sql(rollback.export_sql()))
 assert again==snap,(snap,again)
 print('v'+str(version),'roundtrip and idempotence passed')

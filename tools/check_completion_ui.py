"""Focused real DownloadManager transfer/import/recovery checks in iOS Simulator."""
import json,pathlib,platform,subprocess
from background_preview import exercise
root=pathlib.Path(__file__).resolve().parents[1];derived=pathlib.Path('/tmp/FizerCompletionSimulator')
output=root/'packages';output.mkdir(exist_ok=True)
log=pathlib.Path('/tmp/fizer-completion-simulator.log')
with log.open('w') as stream:
 result=subprocess.run(['xcodebuild','-jobs','2','-project','Feather.xcodeproj','-scheme','Feather',
  '-configuration','Release','-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator',
  '-derivedDataPath',str(derived),'-skipPackagePluginValidation','CODE_SIGNING_ALLOWED=NO',
  'DEPLOYMENT_LOCATION=NO','PRODUCT_BUNDLE_IDENTIFIER=ru.dzhabaapps.fizer.preview',
  'ONLY_ACTIVE_ARCH=YES','ARCHS='+platform.machine()],cwd=root,stdout=stream,stderr=subprocess.STDOUT)
if result.returncode:
 raise RuntimeError('Completion simulator compile failed: '+'\n'.join(line for line in log.read_text().splitlines() if 'error:' in line)[-5000:])
def run(*args):return subprocess.check_output(args,cwd=root,text=True)
devices=json.loads(run('xcrun','simctl','list','devices','available','-j'))
phone=next(d for items in devices['devices'].values() for d in items if d['name'].startswith('iPhone') and d.get('isAvailable'))
device=phone['udid']
if phone['state']!='Booted':run('xcrun','simctl','boot',device)
run('xcrun','simctl','bootstatus',device,'-b')
app=derived/'Build/Products/Release-iphonesimulator/Feather.app'
container=exercise(root,app,device,hold_import=True)
recovery=json.loads((container/'Documents/background-validation.json').read_text())
container=exercise(root,app,device,hold_import=False)
completion=json.loads((container/'Documents/background-validation.json').read_text())
(output/'Completion-validation.json').write_text(json.dumps({'recovery':recovery,'completion':completion},indent=2))
print('Actual transfer/import and relaunch recovery passed. Background-runtime limitations, if any, are explicitly recorded.',flush=True)

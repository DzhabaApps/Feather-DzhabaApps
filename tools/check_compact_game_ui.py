"""Capture the actual GTA detail in iOS Simulator before shipping the new layout."""
import pathlib,subprocess,platform,os,time,json
root=pathlib.Path(__file__).resolve().parents[1];output=root/'packages';output.mkdir(exist_ok=True)
derived=pathlib.Path('/tmp/DRStoreCompactSimulator');log=output/'Compact-simulator-build.log'
with log.open('w') as stream:
 result=subprocess.run(['xcodebuild','-jobs','2','-project','Feather.xcodeproj','-scheme','Feather',
  '-configuration','Release','-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator',
  '-derivedDataPath',str(derived),'-skipPackagePluginValidation','CODE_SIGNING_ALLOWED=NO',
  'DEPLOYMENT_LOCATION=NO','PRODUCT_BUNDLE_IDENTIFIER=ru.dzhabaapps.fizer.preview',
  'ONLY_ACTIVE_ARCH=YES','ARCHS='+platform.machine()],cwd=root,stdout=stream,stderr=subprocess.STDOUT)
if result.returncode:
 raise RuntimeError('Simulator build failed: '+'\n'.join(l for l in log.read_text().splitlines() if 'error:' in l)[-4000:])
def run(*args,**kwargs):return subprocess.check_output(args,cwd=root,text=True,**kwargs)
devices=json.loads(run('xcrun','simctl','list','devices','available','-j'))
phone=next(d for items in devices['devices'].values() for d in items if d['name'].startswith('iPhone') and d.get('isAvailable'))
device=phone['udid']
if phone['state']!='Booted':run('xcrun','simctl','boot',device)
run('xcrun','simctl','bootstatus',device,'-b')
run('xcrun','simctl','status_bar',device,'override','--time','9:41','--batteryState','charged','--batteryLevel','100')
app=derived/'Build/Products/Release-iphonesimulator/Feather.app'
run('xcrun','simctl','install',device,str(app))
env={**os.environ,'SIMCTL_CHILD_FIZER_PREVIEW_SCREEN':'game-detail'}
run('xcrun','simctl','launch',device,'ru.dzhabaapps.fizer.preview',env=env)
container=pathlib.Path(run('xcrun','simctl','get_app_container',device,'ru.dzhabaapps.fizer.preview','data').strip())
report=container/'Documents/compact-game-ready.json';deadline=time.monotonic()+90
while not report.exists() and time.monotonic()<deadline:time.sleep(0.5)
assert report.exists(), 'Real GTA detail did not become ready'
checks=json.loads(report.read_text());assert checks['files']>0 and checks['videoResolved'],checks
time.sleep(6)
for appearance in ['light','dark']:
 run('xcrun','simctl','ui',device,'appearance',appearance);time.sleep(1)
 run('xcrun','simctl','io',device,'screenshot',str(output/('DR-Store-GTA-compact-'+appearance+'.png')))
(output/'Compact-game-validation.json').write_text(json.dumps({**checks,'simulator_screenshots':'light/dark','physical_installation':'pending'},indent=2))
print('Compact GTA detail: real game/file/video loaded; native light/dark screenshots captured',flush=True)

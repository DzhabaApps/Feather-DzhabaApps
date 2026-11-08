"""Exercise actual collection taps, video navigation, back and search in Simulator."""
import pathlib,subprocess,platform,json,shutil
root=pathlib.Path(__file__).resolve().parents[1];output=root/'packages';output.mkdir(exist_ok=True)
from native_player_ui import prepare_native_ui
prepare_native_ui(root)
def run(*args):return subprocess.check_output(args,cwd=root,text=True)
devices=json.loads(run('xcrun','simctl','list','devices','available','-j'))
phone=next(d for items in devices['devices'].values() for d in items if d['name'].startswith('iPhone') and d.get('isAvailable'))
device=phone['udid']
if phone['state']!='Booted':run('xcrun','simctl','boot',device)
run('xcrun','simctl','bootstatus',device,'-b')
run('xcrun','simctl','ui',device,'appearance','light')
run('xcrun','simctl','status_bar',device,'override','--time','9:41','--batteryState','charged','--batteryLevel','100')
result=pathlib.Path('/tmp/DRStoreInstructionCollections.xcresult')
log=output/'Instruction-collections-UI-test.log'
with log.open('w') as stream:
 proc=subprocess.run(['xcodebuild','test','-jobs','2','-project','Feather.xcodeproj','-scheme','InstructionNativeUI',
  '-configuration','Debug','-destination','id='+device,'-parallel-testing-enabled','NO',
  '-derivedDataPath','/tmp/DRStoreCollectionsSimulator','-resultBundlePath',str(result),
  '-only-testing:InstructionNativeUITests/NativePlayerUITests/testInstructionCollections',
  '-skipPackagePluginValidation','CODE_SIGNING_ALLOWED=NO','DEPLOYMENT_LOCATION=NO',
  'ONLY_ACTIVE_ARCH=YES','ARCHS='+platform.machine()],cwd=root,stdout=stream,stderr=subprocess.STDOUT)
attachments=pathlib.Path('/tmp/DRStoreCollectionAttachments')
if result.exists():
 subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(attachments)],check=False)
 if attachments.exists():
  shutil.make_archive(str(output/'Instruction-collections-UI-screenshots'),'zip',attachments)
  manifest=attachments/'manifest.json'
  if manifest.exists():
   for test in json.loads(manifest.read_text()):
    for attachment in test.get('attachments',[]):
     suggested=attachment.get('suggestedHumanReadableName','')
     for label in ['home','gta','search']:
      if suggested.startswith('DR-Store-instruction-collections-'+label+'_'):
       shutil.copy2(attachments/attachment['exportedFileName'],output/('DR-Store-instruction-collections-'+label+'.png'))
if proc.returncode:
 lines=log.read_text(errors='replace').splitlines()
 print('\n'.join(l for l in lines if 'error:' in l.lower() or 'failed' in l.lower())[-6000:],flush=True)
 raise RuntimeError('Native collection navigation test failed; see diagnostics')
assert all((output/('DR-Store-instruction-collections-'+name+'.png')).exists() for name in ['home','gta','search'])
(output/'Instruction-collections-validation.json').write_text(json.dumps({'passed':True,'method':'XCTest actual native taps',
 'scenarios':['published general videos','GTA collection','WhatsApp collection','video screen','back navigation','search'],
 'physical_installation':'pending'},indent=2))
print('Native instruction collections: general cards, collections, video, back and search passed',flush=True)

"""Build the real app for iOS Simulator and capture its settings screens."""
import json
import os
import pathlib
import plistlib
import subprocess
import time
from background_preview import exercise

root = pathlib.Path(__file__).resolve().parents[1]
derived = pathlib.Path('/tmp/FizerSimulator')
output = root/'packages'

def run(*args, **kwargs):
    return subprocess.run(args, cwd=root, check=True, text=True, **kwargs)

build_log = pathlib.Path('/tmp/fizer-simulator-build.log')
with build_log.open('w') as log:
    result = subprocess.run([
        'xcodebuild', '-project', 'Feather.xcodeproj', '-scheme', 'Feather',
        '-configuration', 'Release', '-sdk', 'iphonesimulator',
        '-destination', 'generic/platform=iOS Simulator',
        '-derivedDataPath', str(derived), '-skipPackagePluginValidation',
        'CODE_SIGNING_ALLOWED=NO', 'DEPLOYMENT_LOCATION=NO',
        'PRODUCT_BUNDLE_IDENTIFIER=ru.dzhabaapps.fizer.preview',
    ], cwd=root, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    errors = [line for line in build_log.read_text().splitlines() if 'error:' in line]
    raise RuntimeError('Simulator build failed: '+'\n'.join(errors[-12:]))

devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j', capture_output=True).stdout)
phone = next(d for runtime, items in devices['devices'].items() for d in items if d['name'].startswith('iPhone') and d.get('isAvailable'))
device = phone['udid']
if phone['state'] != 'Booted':
    run('xcrun', 'simctl', 'boot', device)
run('xcrun', 'simctl', 'bootstatus', device, '-b')
run('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100')
run('xcrun', 'simctl', 'ui', device, 'appearance', 'light')
app = derived/'Build/Products/Release-iphonesimulator/Feather.app'
run('xcrun', 'simctl', 'install', device, str(app))
container = exercise(root, app, device)
validation=container/'Documents/background-validation.json'
if validation.exists(): (output/'Background-validation.json').write_bytes(validation.read_bytes())
screens = ['library', 'copies', 'new-copy', 'store-news', 'app-detail', 'settings', 'installation', 'storage', 'advanced', 'help', 'access-expired', 'access-offline', 'access-checking', 'cancellation-check', 'store', 'store-finance', 'store-social', 'store-games']
for screen in screens:
    subprocess.run(['xcrun', 'simctl', 'terminate', device, 'ru.dzhabaapps.fizer.preview'], cwd=root, capture_output=True)
    env = os.environ.copy()
    env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN'] = screen
    run('xcrun', 'simctl', 'launch', device, 'ru.dzhabaapps.fizer.preview', env=env)
    # Let the simulator's first-launch system notification disappear before QA.
    time.sleep(15 if screen == 'settings' else 5)
    path = output/f'Fizer-{screen}.png'
    run('xcrun', 'simctl', 'io', device, 'screenshot', str(path))
    assert path.stat().st_size > 10000
print(f'Native iOS Simulator screenshots: {len(screens)} screens captured')
cancel_validation = container/'Documents/cancellation-validation.json'
cancel_checks = json.loads(cancel_validation.read_text())
assert cancel_checks and all(value is True for value in cancel_checks.values()), cancel_checks
cancel_checks['commit'] = plistlib.loads((app/'Info.plist').read_bytes())['CFBundleVersion']
(output/'Cancellation-validation.json').write_text(json.dumps(cancel_checks), encoding='utf-8')

subprocess.run(['xcrun', 'simctl', 'terminate', device, 'ru.dzhabaapps.fizer.preview'], cwd=root, capture_output=True)
env = os.environ.copy(); env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN'] = 'cache-check'
run('xcrun', 'simctl', 'launch', device, 'ru.dzhabaapps.fizer.preview', env=env)
result = container/'Documents/cache-test-result.json'
deadline = time.monotonic()+15
while time.monotonic()<deadline and not result.exists(): time.sleep(1)
assert result.exists() and all(json.loads(result.read_text()).values()), 'Native library cleanup lost app files or installation/subscription data'
cleanup = json.loads(result.read_text())
cleanup['commit'] = __import__('plistlib').loads((app/'Info.plist').read_bytes())['CFBundleVersion']
(output/'Cleanup-validation.json').write_text(json.dumps(cleanup), encoding='utf-8')
print('Native library cleanup: downloaded and prepared apps removed; installation credentials and paid-period marker preserved')

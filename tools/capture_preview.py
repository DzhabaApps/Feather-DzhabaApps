"""Build the real app for iOS Simulator and capture its settings screens."""
import json
import os
import pathlib
import subprocess
import time

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
for screen in ['settings', 'installation', 'advanced', 'help']:
    subprocess.run(['xcrun', 'simctl', 'terminate', device, 'ru.dzhabaapps.fizer.preview'], cwd=root, capture_output=True)
    env = os.environ.copy()
    env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN'] = screen
    run('xcrun', 'simctl', 'launch', device, 'ru.dzhabaapps.fizer.preview', env=env)
    time.sleep(5)
    path = output/f'Fizer-{screen}.png'
    run('xcrun', 'simctl', 'io', device, 'screenshot', str(path))
    assert path.stat().st_size > 10000
print('Native iOS Simulator screenshots: 4 screens captured')

"""Repair packaging only when all application sources match the tested commit."""
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.request
import urllib.error

PIN = '88eac52f8aebd6dcdcb0b4685aee1a6397eb8e4b'
JOB = '114746378958'
subprocess.run(['git', 'fetch', '--depth=1', 'origin', PIN], check=True)
changed = set(subprocess.check_output(['git', 'diff', '--name-only', '--no-renames', PIN, 'HEAD'], text=True).splitlines())
allowed = {'Makefile', 'tools/finalize_app_metadata.py', 'tools/package_validated.py'}
if not changed or not changed <= allowed:
    subprocess.run(['make', 'full'], check=True)
    sys.exit(0)
folder = pathlib.Path('packages'); folder.mkdir(exist_ok=True)
# Use the checkout's existing CI credential only against GitHub's API. Never
# print it or forward it to the signed log-download redirect.
header = subprocess.check_output(['git', 'config', '--get', 'http.https://github.com/.extraheader'], text=True).strip()
name, value = header.split(':', 1)
assert name.lower() == 'authorization'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
try:
    with urllib.request.build_opener(NoRedirect).open(urllib.request.Request(
        'https://api.github.com/repos/DzhabaApps/Feather-DzhabaApps/actions/jobs/' + JOB + '/logs',
        headers={'Authorization': value.strip(), 'User-Agent': 'DR-Store-build'}), timeout=30) as response:
        log = response.read()
except urllib.error.HTTPError as error:
    assert error.code == 302, 'Cannot read prior validation; use make full'
    location = error.headers['Location']
    from urllib.parse import urlsplit
    assert urlsplit(location).scheme == 'https'
    with urllib.request.urlopen(location, timeout=60) as response:
        log = response.read()
text = log.decode(errors='replace')
markers = {
    'icon_selection': 'Icon selection: background completion, stale read, concurrent request, duplicate, error, reopen and all three choices passed',
    'native_avkit_ui': 'Native AVKit XCTest: fullscreen, system skip/scrub, hiding controls and repeated return passed.',
    'native_instruction_playback': 'Native instruction player: remote GitHub frames, seeking, pause and cleanup passed.',
    'native_background_transfer': 'actual durable bytes verified and relaunch imported successfully',
    'transport': 'Native MP4 range transport passed:',
    'storage': 'Storage regression: accurate breakdown, orphan cleanup, session-folder reuse, credentials/archives/transfers preservation passed',
    'cancellation': 'Cancellation: durable stop, ignored tombstones, cooperative import cancellation passed',
    'screenshots': 'Native iOS Simulator screenshots: 22 screens captured',
}
assert all(v in text for v in markers.values())
assert PIN in text and "assert info['CFBundleDevelopmentRegion'] == 'ru'" in text
assert '** BUILD SUCCEEDED **' in text
(folder / 'Previous-native-validation.log').write_bytes(log)
report = {'source_commit': PIN, 'artifact_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
          'source_job': int(JOB), 'application_and_test_sources_unchanged': True, 'changed_files': sorted(changed),
          'checks': {key: True for key in markers}, 'log_sha256': hashlib.sha256(log).hexdigest(),
          'actual_system_icon_dialog_verified': False}
(folder / 'Validated-source.json').write_text(json.dumps(report, indent=2))
print('Exact application sources retain passed native/model checks; rebuilding and checking packaging only.', flush=True)
subprocess.run(['make', 'iphoneos'], check=True)

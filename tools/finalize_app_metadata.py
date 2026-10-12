"""Finalize Russian app metadata before signing; Xcode can override the source plist."""
import copy
import pathlib
import plistlib
import sys

def finalize(app):
    path = pathlib.Path(app) / 'Info.plist'
    before = plistlib.loads(path.read_bytes())
    after = copy.deepcopy(before)
    after['CFBundleDevelopmentRegion'] = 'ru'
    after['CFBundleLocalizations'] = list(dict.fromkeys(before.get('CFBundleLocalizations', []) + ['ru']))
    assert all(after[k] == v for k, v in before.items() if k not in {'CFBundleDevelopmentRegion', 'CFBundleLocalizations'})
    path.write_bytes(plistlib.dumps(after, fmt=plistlib.FMT_BINARY))
    assert plistlib.loads(path.read_bytes()) == after
    print('Final app metadata: Russian development language and supported localization verified.')

if __name__ == '__main__':
    finalize(sys.argv[1])

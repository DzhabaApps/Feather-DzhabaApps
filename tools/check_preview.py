"""Validate translations, formatting arguments and the isolated IPA artifact."""
import argparse
import json
import pathlib
import plistlib
import re
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
catalog = json.loads((root/'Feather/Resources/Localizable.xcstrings').read_text(encoding='utf-8'))
formats = re.compile(r'%(?:\d+\$)?(?:lld|ld|@|d|f|s|u)')
for key, entry in catalog['strings'].items():
    value = entry.get('localizations', {}).get('ru', {}).get('stringUnit', {}).get('value')
    assert value, f'Missing Russian translation: {key}'
    assert sorted(formats.findall(key)) == sorted(formats.findall(value)), f'Format mismatch: {key}'
paths = list((root/'Feather').rglob('*.swift')) + list((root/'NimbleKit/Sources/NimbleViews').rglob('*.swift')) + list((root/'NimbleKit/Sources/NimbleExtensions').rglob('*.swift'))
for path in paths:
    for key in re.findall(r'\.localized\("((?:[^"\\]|\\.)*)"', path.read_text(encoding='utf-8')):
        if '\\(' in key:
            continue
        decoded = json.loads('"'+key+'"')
        assert decoded in catalog['strings'], f'Missing catalog key in {path.name}: {decoded}'
assert (root/'Feather/Resources/GPL-3.0.txt').is_file()
print(f"Russian catalog: {len(catalog['strings'])} entries and formatting arguments verified")

parser = argparse.ArgumentParser()
parser.add_argument('--ipa', type=pathlib.Path)
args = parser.parse_args()
if args.ipa:
    with zipfile.ZipFile(args.ipa) as ipa:
        app = 'Payload/Feather.app/'
        info = plistlib.loads(ipa.read(app+'Info.plist'))
        assert info['CFBundleIdentifier'] == 'ru.dzhabaapps.fizer.preview'
        assert info['CFBundleDisplayName'] == 'Физер-тест'
        schemes = [s for t in info.get('CFBundleURLTypes', []) for s in t.get('CFBundleURLSchemes', [])]
        assert 'fizer-preview' in schemes and 'feather' not in schemes
        assert any(n.startswith(app+'ru.lproj/') for n in ipa.namelist())
        assert app+'GPL-3.0.txt' in ipa.namelist()
        assert not any('signing-assets/' in n for n in ipa.namelist()), 'Preview must not embed client credentials'
        for name in ['server.crt', 'server.pem', 'commonName.txt']:
            assert len(ipa.read(app+name)) > 0
        assert ipa.testzip() is None
    print('IPA: isolation, Russian resources, SSL assets, license and archive integrity verified')

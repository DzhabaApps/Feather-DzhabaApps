"""The production task permission must match the production bundle, not preview."""
import pathlib
import plistlib
import tempfile
import zipfile
from promote_ipa import promote

with tempfile.TemporaryDirectory() as folder:
    source = pathlib.Path(folder)/'preview.ipa'
    target = pathlib.Path(folder)/'production.ipa'
    info = {'CFBundleIdentifier':'ru.dzhabaapps.fizer.preview', 'CFBundleDisplayName':'Feather Test',
            'CFBundleShortVersionString':'fixture', 'CFBundleVersion':'fixture',
            'BGTaskSchedulerPermittedIdentifiers':['ru.dzhabaapps.fizer.preview.userTask.*'],
            'CFBundleURLTypes':[{'CFBundleURLSchemes':['fizer-preview']}]}
    with zipfile.ZipFile(source, 'w') as archive:
        archive.writestr('Payload/Feather.app/Info.plist', plistlib.dumps(info))
        archive.writestr('Payload/Feather.app/Feather', b'executable-fixture')
    promote(source, target, version='fixture', commit='fixture')
    with zipfile.ZipFile(target) as archive:
        result = plistlib.loads(archive.read('Payload/Feather.app/Info.plist'))
        assert result['BGTaskSchedulerPermittedIdentifiers'] == [result['CFBundleIdentifier']+'.userTask.*']
        assert archive.read('Payload/Feather.app/Feather') == b'executable-fixture'
    print('Production background permission regression passed')

"""Promote the tested unsigned IPA by changing only its installation metadata.

The bot must sign the result with the purchaser's certificate before installation.
Executable code and all other resources are preserved byte for byte.
"""
import argparse
import copy
import hashlib
import pathlib
import plistlib
import zipfile


def promote(source: pathlib.Path, destination: pathlib.Path, *, version: str = '2.9.0', commit: str = '691201c06a2b05acaf79a1ea6a6040b447ac36ac') -> None:
    assert source.resolve() != destination.resolve()
    metadata_path = 'Payload/Feather.app/Info.plist'
    with zipfile.ZipFile(source) as original:
        assert original.testzip() is None
        info = plistlib.loads(original.read(metadata_path))
        assert info['CFBundleIdentifier'] == 'ru.dzhabaapps.fizer.preview'
        assert info['CFBundleDisplayName'] == 'Feather Test'
        assert info['CFBundleShortVersionString'] == version
        assert info['CFBundleVersion'] == commit
        assert not any('signing-assets/' in n for n in original.namelist())
        info['CFBundleIdentifier'] = 'thewonderofyou.Feather'
        info['CFBundleDisplayName'] = 'Feather'
        for url_type in info['CFBundleURLTypes']:
            url_type['CFBundleURLSchemes'] = ['feather' if s == 'fizer-preview' else s for s in url_type['CFBundleURLSchemes']]
        destination.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(destination, 'w') as result:
            for entry in original.infolist():
                data = plistlib.dumps(info, fmt=plistlib.FMT_BINARY) if entry.filename == metadata_path else original.read(entry)
                result.writestr(copy.copy(entry), data)
        with zipfile.ZipFile(destination) as result:
            assert result.testzip() is None
            assert original.namelist() == result.namelist()
            for entry in original.infolist():
                if entry.filename != metadata_path:
                    assert original.read(entry) == result.read(entry.filename), entry.filename
                assert result.getinfo(entry.filename).external_attr == entry.external_attr
    print('Production IPA: old production identity restored; executable and resources unchanged.')
    print('SHA256:', hashlib.file_digest(destination.open('rb'), 'sha256').hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=pathlib.Path)
    parser.add_argument('destination', type=pathlib.Path)
    parser.add_argument('--version', default='2.9.0')
    parser.add_argument('--commit', default='691201c06a2b05acaf79a1ea6a6040b447ac36ac')
    args = parser.parse_args()
    promote(args.source, args.destination, version=args.version, commit=args.commit)

"""Compile the real catalog decoder and exercise external-file metadata on macOS."""
import pathlib, subprocess, tempfile, os
with tempfile.TemporaryDirectory(prefix='catalog-files-') as td:
    root=pathlib.Path(td)
    sources=list(pathlib.Path('AltSourceKit/Sources/AltSourceKit').rglob('*.swift'))
    subprocess.run(['xcrun','swiftc','-emit-library','-emit-module','-module-name','AltSourceKit',
                    *map(str,sources),'-emit-module-path',str(root/'AltSourceKit.swiftmodule'),
                    '-o',str(root/'libAltSourceKit.dylib')],check=True)
    subprocess.run(['xcrun','swiftc','-I',td,'-L',td,'-lAltSourceKit',
                    'Feather/Backend/Observable/CatalogFileSize.swift','tools/catalog-files-tests/main.swift',
                    '-o',str(root/'check')],check=True)
    subprocess.run([str(root/'check')],env={**os.environ,'DYLD_LIBRARY_PATH':td},check=True)

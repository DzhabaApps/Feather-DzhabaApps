"""Exercise the actual DownloadManager with a slow local fixture in iOS Simulator."""
import http.server
import io
import json
import os
import pathlib
import plistlib
import subprocess
import threading
import time
import zipfile

IDENTITY = 'ru.dzhabaapps.fizer.preview'

def exercise(root, app, device):
    def run(*args, **kwargs):
        return subprocess.run(args, cwd=root, check=True, text=True, **kwargs)
    # The localhost exception exists only in the installed simulator copy, never in the IPA.
    info_path = app/'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.setdefault('NSAppTransportSecurity', {}).setdefault('NSExceptionDomains', {})['localhost'] = {'NSExceptionAllowsInsecureHTTPLoads': True}
    info_path.write_bytes(plistlib.dumps(info))
    run('xcrun', 'simctl', 'install', device, str(app))
    fixture = io.BytesIO()
    with zipfile.ZipFile(fixture, 'w', compression=zipfile.ZIP_STORED) as archive:
        archive.writestr('Payload/BackgroundFixture.app/Info.plist', plistlib.dumps({'CFBundleIdentifier':'ru.dzhabaapps.background.fixture','CFBundleName':'Фоновая проверка','CFBundleDisplayName':'Фоновая проверка','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundlePackageType':'APPL'}))
        archive.writestr('Payload/BackgroundFixture.app/padding.dat', b'fixture!' * (512 * 1024))
    payload = fixture.getvalue()
    started = threading.Event()
    completed = threading.Event()
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_GET(self):
            if self.path != '/fixture.ipa':
                page=b'<html><body>Background test</body></html>'
                self.send_response(200); self.send_header('Content-Length',str(len(page))); self.end_headers(); self.wfile.write(page); return
            self.send_response(200)
            self.send_header('Content-Length',str(len(payload)))
            self.send_header('Content-Type','application/octet-stream')
            self.end_headers()
            started.set()
            try:
                for offset in range(0,len(payload),65536):
                    self.wfile.write(payload[offset:offset+65536]); self.wfile.flush(); time.sleep(0.5)
                completed.set()
            except (BrokenPipeError,ConnectionResetError): pass
    server=http.server.ThreadingHTTPServer(('localhost',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    url=f'http://localhost:{server.server_port}/fixture.ipa'
    container=pathlib.Path(run('xcrun','simctl','get_app_container',device,IDENTITY,'data',capture_output=True).stdout.strip())
    env=os.environ.copy();env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN']='background-transfer';env['SIMCTL_CHILD_FIZER_BACKGROUND_TEST_URL']=url
    try:
        subprocess.run(['xcrun','simctl','terminate',device,IDENTITY],cwd=root,capture_output=True)
        run('xcrun','simctl','launch',device,IDENTITY,env=env)
        assert started.wait(30), 'Native background session did not start the fixture request'
        run('xcrun','simctl','openurl',device,f'http://localhost:{server.server_port}/home')
        deadline=time.monotonic()+45
        lifecycle=container/'Documents/background-test-lifecycle.txt'
        received=[]
        while time.monotonic()<deadline:
            received=list((container/'Library/Application Support/FizerDownloads').glob('*/package.ipa'))
            if completed.is_set() and received and lifecycle.exists(): break
            time.sleep(1)
        assert lifecycle.exists(), 'The app did not enter the background'
        assert completed.is_set() and received, 'Download failed to complete and persist while backgrounded'
        assert received[0].read_bytes()==payload, 'Background file differs from the served fixture'
        # Terminate after delivery, before foreground unpacking, and recover the persisted package.
        run('xcrun','simctl','terminate',device,IDENTITY)
        env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN']='library'
        run('xcrun','simctl','launch',device,IDENTITY,env=env)
        result=container/'Documents/background-test-result.json'
        deadline=time.monotonic()+30
        while time.monotonic()<deadline and not result.exists(): time.sleep(1)
        assert result.exists() and json.loads(result.read_text())['imported'] is True, 'Completed package did not recover/import on relaunch'
        print('Native background download: switched to Safari, completed outside app, durable bytes verified, relaunch imported successfully',flush=True)
        return container
    finally:
        server.shutdown();server.server_close()

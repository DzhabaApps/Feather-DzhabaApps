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
import uuid

IDENTITY = 'ru.dzhabaapps.fizer.preview'

def exercise(root, app, device):
    def run(*args, **kwargs):
        return subprocess.run(args, cwd=root, check=True, text=True, **kwargs)
    # Loopback HTTP is allowed only in the installed simulator copy, never in the IPA.
    info_path = app/'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.setdefault('NSAppTransportSecurity', {})['NSAllowsArbitraryLoads'] = True
    info_path.write_bytes(plistlib.dumps(info))
    # Background XPC services authenticate the caller; an unsigned simulator app
    # is not a representative counterpart of the individually signed iPhone build.
    run('codesign','--force','--deep','--sign','-','--identifier',IDENTITY,str(app))
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
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    url=f'http://127.0.0.1:{server.server_port}/fixture.ipa'
    container=pathlib.Path(run('xcrun','simctl','get_app_container',device,IDENTITY,'data',capture_output=True).stdout.strip())
    env=os.environ.copy();env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN']='background-transfer';env['SIMCTL_CHILD_FIZER_BACKGROUND_TEST_URL']=url
    try:
        subprocess.run(['xcrun','simctl','terminate',device,IDENTITY],cwd=root,capture_output=True)
        run('xcrun','simctl','launch',device,IDENTITY,env=env)
        assert started.wait(150), 'Native background session did not start the fixture request'
        run('xcrun','simctl','openurl',device,f'http://127.0.0.1:{server.server_port}/home')
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
        (container/'Documents/background-validation.json').write_text(json.dumps({'backgroundTransfer':'passed-native-simulator','persistentRecovery':'passed','commit':info['CFBundleVersion']}),encoding='utf-8')
        print('Native background download: switched to Safari, completed outside app, durable bytes verified, relaunch imported successfully',flush=True)
        return container
    except Exception:
        diagnostic=container/'Documents/background-test-diagnostic.txt'
        print('Background preview diagnostic:',diagnostic.read_text(encoding='utf-8') if diagnostic.exists() else 'No app diagnostic: preview view did not appear',flush=True)
        records=list((container/'Library/Application Support/FizerDownloads').glob('*.json'))
        print('Persisted download records:',len(records),flush=True)
        logs=subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','4m','--style','compact','--predicate','process == "Feather" AND (eventMessage CONTAINS "error" OR eventMessage CONTAINS "download")'],capture_output=True,text=True)
        print('Simulator download diagnostics:',logs.stdout[-6000:],flush=True)
        if started.is_set() or 'NSCocoaErrorDomain Code=4097' not in logs.stdout or 'com.apple.nsurlsessiond' not in logs.stdout:
            raise
        # Apple DTS recommends physical devices for background session verification.
        # Only this exact unavailable simulator service is a skip; network, byte,
        # persistence or import failures still fail the build above.
        print('::warning::Native background transfer UNVERIFIED: simulator nsurlsessiond XPC service unavailable (4097). Real-device test required. Checking recovery/import separately.',flush=True)
        subprocess.run(['xcrun','simctl','terminate',device,IDENTITY],cwd=root,capture_output=True)
        token=str(uuid.uuid4()).upper()
        journal=container/'Library/Application Support/FizerDownloads'
        (journal/token).mkdir(parents=True,exist_ok=True)
        (journal/token/'package.ipa').write_bytes(payload)
        (journal/(token+'.json')).write_text(json.dumps({'token':token,'id':'background-integration','url':url,'source':url,'displayName':'Фоновая проверка'}),encoding='utf-8')
        env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN']='library'
        run('xcrun','simctl','launch',device,IDENTITY,env=env)
        result=container/'Documents/background-test-result.json'
        deadline=time.monotonic()+60
        while time.monotonic()<deadline and not result.exists():time.sleep(1)
        assert result.exists() and json.loads(result.read_text())['imported'] is True, 'Persisted fixture recovery/import failed'
        (container/'Documents/background-validation.json').write_text(json.dumps({'backgroundTransfer':'unverified-simulator-service-4097','persistentRecovery':'passed','commit':info['CFBundleVersion']}),encoding='utf-8')
        print('Native persisted fixture recovery/import passed; this is NOT a passed background transfer test.',flush=True)
        return container
    finally:
        server.shutdown();server.server_close()

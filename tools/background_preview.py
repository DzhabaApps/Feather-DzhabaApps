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
    # Sign the simulator build consistently with its preview identity.
    run('codesign','--force','--deep','--sign','-','--identifier',IDENTITY,str(app))
    run('xcrun', 'simctl', 'install', device, str(app))
    fixture = io.BytesIO()
    with zipfile.ZipFile(fixture, 'w', compression=zipfile.ZIP_STORED) as archive:
        archive.writestr('Payload/BackgroundFixture.app/Info.plist', plistlib.dumps({'CFBundleIdentifier':'ru.dzhabaapps.background.fixture','CFBundleName':'Фоновая проверка','CFBundleDisplayName':'Фоновая проверка','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundlePackageType':'APPL'}))
        archive.writestr('Payload/BackgroundFixture.app/padding.dat', b'fixture!' * (512 * 1024))
    payload = fixture.getvalue()
    started = threading.Event()
    completed = threading.Event()
    release_body = threading.Event()
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
            if not release_body.wait(180): return
            try:
                for offset in range(0,len(payload),65536):
                    self.wfile.write(payload[offset:offset+65536]); self.wfile.flush(); time.sleep(0.5)
                completed.set()
            except (BrokenPipeError,ConnectionResetError): pass
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    url=f'http://127.0.0.1:{server.server_port}/fixture.ipa'
    container=pathlib.Path(run('xcrun','simctl','get_app_container',device,IDENTITY,'data',capture_output=True).stdout.strip())
    env=os.environ.copy();env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN']='background-transfer';env['SIMCTL_CHILD_FIZER_BACKGROUND_TEST_URL']=url;env['SIMCTL_CHILD_FIZER_BACKGROUND_TEST_HOLD_IMPORT']='1'
    try:
        subprocess.run(['xcrun','simctl','terminate',device,IDENTITY],cwd=root,capture_output=True)
        for name in ['background-test-lifecycle.txt','background-test-result.json','background-test-diagnostic.txt']:
            (container/'Documents'/name).unlink(missing_ok=True)
        run('xcrun','simctl','launch',device,IDENTITY,env=env)
        assert started.wait(150), 'In-process download did not start the fixture request'
        run('xcrun','simctl','openurl',device,f'http://127.0.0.1:{server.server_port}/home')
        lifecycle=container/'Documents/background-test-lifecycle.txt'
        deadline=time.monotonic()+20
        while time.monotonic()<deadline and not lifecycle.exists(): time.sleep(0.5)
        assert lifecycle.exists(), 'The app did not enter the background'
        release_body.set()
        def delivered(timeout):
            deadline=time.monotonic()+timeout
            while time.monotonic()<deadline:
                received=list((container/'Library/Application Support/FizerDownloads').glob('*/package.ipa'))
                if completed.is_set() and received: return received
                time.sleep(1)
            return []
        received=delivered(45)
        background_status='passed-native-simulator'
        foreground_status='covered-by-byte-verified-background-transfer'
        if not received:
            diagnostic=container/'Documents/background-test-diagnostic.txt'
            detail=diagnostic.read_text(encoding='utf-8') if diagnostic.exists() else ''
            logs=subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','4m','--style','compact','--predicate','process == "Feather" AND eventMessage CONTAINS "error"'],capture_output=True,text=True).stdout
            assert 'continued-rejected BGTaskSchedulerErrorDomain 1' in detail and 'associating with audio session (0x0), error -10879' in logs, 'Download failed without the documented simulator runtime limitation'
            print('UNVERIFIED: simulator rejects continued task and audio session; checking actual transfer in foreground',flush=True)
            run('xcrun','simctl','launch',device,IDENTITY,env=env)
            received=delivered(90)
            assert received, 'Actual foreground download failed to complete and persist'
            background_status='unverified-simulator-runtime-unavailable'
            foreground_status='passed-native-simulator'
        assert received[0].read_bytes()==payload, 'Received file differs from the served fixture'
        # Terminate after delivery, before foreground unpacking, and recover the persisted package.
        run('xcrun','simctl','terminate',device,IDENTITY)
        env['SIMCTL_CHILD_FIZER_PREVIEW_SCREEN']='library'
        env.pop('SIMCTL_CHILD_FIZER_BACKGROUND_TEST_HOLD_IMPORT',None)
        run('xcrun','simctl','launch',device,IDENTITY,env=env)
        result=container/'Documents/background-test-result.json'
        deadline=time.monotonic()+30
        while time.monotonic()<deadline and not result.exists(): time.sleep(1)
        assert result.exists() and json.loads(result.read_text())['imported'] is True and json.loads(result.read_text())['source']==url, 'Completed package did not recover/import on relaunch'
        (container/'Documents/background-validation.json').write_text(json.dumps({'backgroundTransfer':background_status,'foregroundTransfer':foreground_status,'persistentRecovery':'passed','commit':info['CFBundleVersion']}),encoding='utf-8')
        print(f'Native transfer validation: background={background_status}; foreground={foreground_status}; actual durable bytes verified and relaunch imported successfully',flush=True)
        return container
    except Exception:
        diagnostic=container/'Documents/background-test-diagnostic.txt'
        print('Background preview diagnostic:',diagnostic.read_text(encoding='utf-8') if diagnostic.exists() else 'No app diagnostic: preview view did not appear',flush=True)
        records=list((container/'Library/Application Support/FizerDownloads').glob('*.json'))
        print('Persisted download records:',len(records),flush=True)
        logs=subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','4m','--style','compact','--predicate','process == "Feather" AND (eventMessage CONTAINS "error" OR eventMessage CONTAINS "download")'],capture_output=True,text=True)
        print('Simulator download diagnostics:',logs.stdout[-6000:],flush=True)
        # New transfers are in-process. A retired daemon's XPC warning cannot
        # justify skipping a failure in the current transport.
        raise
    finally:
        release_body.set();server.shutdown();server.server_close()

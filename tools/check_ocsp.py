"""Exercise the exact OCSP decoder with real DER responses and AddressSanitizer."""
from pathlib import Path
import os
import subprocess
import tempfile

prefix = subprocess.run(['brew', '--prefix', 'openssl@3'], capture_output=True, text=True)
if prefix.returncode:
    subprocess.run(['brew', 'install', 'openssl@3'], check=True)
    prefix = subprocess.run(['brew', '--prefix', 'openssl@3'], capture_output=True, text=True, check=True)
openssl = Path(prefix.stdout.strip())
with tempfile.TemporaryDirectory(prefix='dr-ocsp-') as temporary:
    executable = Path(temporary) / 'check'
    subprocess.run(['clang++', '-std=c++17', '-O1', '-g', '-fsanitize=address',
                    '-fno-omit-frame-pointer', '-I'+str(openssl/'include'),
                    '-L'+str(openssl/'lib'), 'tools/ocsp-tests/check.cpp', '-lcrypto',
                    '-o', str(executable)], check=True)
    subprocess.run([str(executable)], env=dict(os.environ, ASAN_OPTIONS='abort_on_error=1'), check=True)

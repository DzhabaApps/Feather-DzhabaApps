"""Exercise the exact OCSP decoder with real DER responses and AddressSanitizer."""
from pathlib import Path
import os
import subprocess
import tempfile

print('OCSP regression: locating OpenSSL', flush=True)
brew_env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1')
prefix = subprocess.run(['brew', '--prefix', 'openssl@3'], capture_output=True, text=True, timeout=45, env=brew_env)
if prefix.returncode:
    subprocess.run(['brew', 'install', 'openssl@3'], check=True, timeout=240, env=brew_env)
    prefix = subprocess.run(['brew', '--prefix', 'openssl@3'], capture_output=True, text=True, check=True, timeout=45, env=brew_env)
openssl = Path(prefix.stdout.strip())
with tempfile.TemporaryDirectory(prefix='dr-ocsp-') as temporary:
    executable = Path(temporary) / 'check'
    print('OCSP regression: compiling AddressSanitizer harness', flush=True)
    subprocess.run(['clang++', '-std=c++17', '-O1', '-g', '-fsanitize=address',
                    '-fno-omit-frame-pointer', '-I'+str(openssl/'include'),
                    '-L'+str(openssl/'lib'), 'tools/ocsp-tests/check.cpp', '-lcrypto',
                    '-o', str(executable)], check=True, timeout=90)
    print('OCSP regression: running parser checks', flush=True)
    subprocess.run([str(executable)], env=dict(os.environ, ASAN_OPTIONS='abort_on_error=1'), check=True, timeout=90)

"""Focused native checks for the isolated TLS experiment; never a public release."""
import json
import os
import pathlib
import subprocess

assert os.environ.get('GITHUB_REF') == 'refs/heads/codex/local-install-lab', 'Lab packaging is restricted to its own branch'
subprocess.run(['make', 'verify', 'iphoneos'], check=True)
root = pathlib.Path('packages')
assert not list(pathlib.Path('Feather').rglob('dr-local-server.pem'))
report = {
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'native_model_checks': 'passed', 'iphoneos_build': 'passed', 'ipa_integrity': 'passed',
    'ui_tests': 'not-run-isolated-backend-experiment', 'physical_ios_installation': 'pending',
    'tls_private_key_in_ci': False,
}
(root/'Local-TLS-validation.json').write_text(json.dumps(report, indent=2))
print('Isolated TLS experiment: native model checks and iPhone compilation passed; real iOS installation pending.')

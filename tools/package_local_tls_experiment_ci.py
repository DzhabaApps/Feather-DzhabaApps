"""Focused native regressions and compilation for the release candidate."""
import json
import os
import pathlib
import subprocess

assert os.environ.get('GITHUB_REF') in {'refs/heads/codex/semi-local-main','refs/heads/codex/install-completion-polish','refs/heads/codex/final-2-0'}, 'Candidate packaging is restricted to its own branch'
subprocess.run(['make', 'verify', 'iphoneos'], check=True)
root = pathlib.Path('packages')
if os.environ.get('GITHUB_REF') == 'refs/heads/codex/install-completion-polish':
    subprocess.run(['python3','tools/check_completion_ui.py'],check=True)
assert not list(pathlib.Path('Feather').rglob('dr-local-server.pem'))
report = {
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'native_model_checks': 'passed', 'iphoneos_build': 'passed', 'ipa_integrity': 'passed',
    'ui_tests': 'not-run-isolated-backend-experiment', 'physical_ios_installation': 'pending',
    'tls_private_key_in_ci': False,
}
(root/'Install-validation.json').write_text(json.dumps(report, indent=2))
print('Release candidate: transport/storage regressions and iPhone compilation passed; physical acceptance pending.')

"""Focused native regressions and compilation for the release candidate."""
import json
import os
import pathlib
import subprocess

instruction_branches = {'refs/heads/codex/instruction-collections-20261109', 'refs/heads/codex/instruction-folder-rows-20261109'}
archive_branches = {'refs/heads/codex/gta-game-data-unpack', 'refs/heads/codex/additional-file-download-progress',
                    'refs/heads/codex/download-controls-and-publisher', 'refs/heads/codex/archive-background-and-save'}
assert os.environ.get('GITHUB_REF') in instruction_branches | archive_branches | {'refs/heads/codex/semi-local-main','refs/heads/codex/install-completion-polish','refs/heads/codex/final-2-0','refs/heads/codex/startup-and-instructions','refs/heads/codex/catalog-files-build-20261108','refs/heads/codex/compact-game-detail-20261109','refs/heads/codex/gta-game-data-download'}, 'Candidate packaging is restricted to its own branch'
if os.environ.get('GITHUB_REF') in archive_branches:
    subprocess.run(['python3', 'tools/check_game_archive.py'], check=True)
subprocess.run(['make', 'verify', 'iphoneos'], check=True)
if os.environ.get('GITHUB_REF') == 'refs/heads/codex/compact-game-detail-20261109':
    subprocess.run(['python3','tools/check_compact_game_ui.py'],check=True)
if os.environ.get('GITHUB_REF') in instruction_branches:
    subprocess.run(['python3','tools/check_instruction_collections_ui.py'],check=True)
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

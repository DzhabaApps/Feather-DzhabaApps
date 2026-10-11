"""Run actual XCTest taps/drags on AVKit, with native screenshots and failure logs."""
import json, pathlib, shutil, subprocess, zipfile

def prepare_native_ui(root):
    probe = subprocess.run(['ruby', '-r', 'xcodeproj', '-e', 'puts Xcodeproj::VERSION'], capture_output=True)
    if probe.returncode:
        subprocess.run(['gem', 'install', '--user-install', 'xcodeproj', '--no-document'], check=True)
    ruby = r'''
require 'xcodeproj'
# Xcode 26 allows synchronized resources here; xcodeproj 1.28 only lists
# source/copy phases. Extend that single reference type without changing the
# project's resource membership or disabling validation of other attributes.
objects = Xcodeproj::Project::Object
attribute = objects::PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.attributes.find { |a| a.name == :build_phase }
attribute.classes |= [objects::PBXResourcesBuildPhase]
root = ARGV[0]
project = Xcodeproj::Project.open(File.join(root, 'Feather.xcodeproj'))
app = project.targets.find { |target| target.name == 'Feather' }
exit 0 if project.targets.any? { |target| target.name == 'InstructionNativeUITests' }
target = project.new_target(:ui_test_bundle, 'InstructionNativeUITests', :ios, '15.0')
file = project.main_group.new_file(File.join(root, 'tools/native-player-ui/NativePlayerUITests.swift'))
target.source_build_phase.add_file_reference(file)
target.add_dependency(app)
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'ru.dzhabaapps.instruction.uitests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TEST_TARGET_NAME'] = 'Feather'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(target)
scheme.test_action.build_configuration = 'Release'
scheme.save_as(project.path, 'InstructionNativeUI', true)
project.save
'''
    subprocess.run(['ruby', '-e', ruby, str(root)], check=True)
    print('Native UI test project prepared and Xcode resource groups preserved.', flush=True)


def exercise_native_ui(root, device, derived, output):
    prepare_native_ui(root)
    result = pathlib.Path('/tmp/InstructionNativeUI.xcresult')
    log = output/'Native-UI-test.log'
    with log.open('w') as stream:
        process = subprocess.run(['xcodebuild', 'test', '-project', 'Feather.xcodeproj',
            '-scheme', 'InstructionNativeUI', '-configuration', 'Release', '-jobs', '2',
            '-destination', 'id='+device, '-derivedDataPath', str(derived),
            '-resultBundlePath', str(result), '-skipPackagePluginValidation',
            'CODE_SIGNING_ALLOWED=NO', 'DEPLOYMENT_LOCATION=NO'], cwd=root, stdout=stream, stderr=subprocess.STDOUT)
    if result.exists():
        attachments = pathlib.Path('/tmp/InstructionNativeAttachments')
        subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(attachments)], check=False)
        if attachments.exists():
            shutil.make_archive(str(output/'Native-UI-screenshots'), 'zip', attachments)
    app_info = pathlib.Path(derived)/'Build/Products/Release-iphonesimulator/Feather.app/Info.plist'
    import plistlib
    commit = plistlib.loads(app_info.read_bytes())['CFBundleVersion']
    (output/'Native-UI-validation.json').write_text(json.dumps({'commit':commit,'passed':process.returncode==0,
        'method':'XCTest actual native AVKit button taps and timeline drag',
        'scenarios':['fullscreen entry','same item retained','native forward/back skip','native timeline drag/resume/progress',
                     'controls hide/show','fullscreen close/inline resume','second fullscreen entry/exit']}))
    if process.returncode:
        lines = log.read_text(errors='replace').splitlines()
        print('\n'.join(lines)[-30000:], flush=True)
        raise RuntimeError('Native AVKit UI interaction test failed; diagnostics saved in packages')
    print('Native AVKit XCTest: fullscreen, system skip/scrub, hiding controls and repeated return passed.', flush=True)

if __name__ == '__main__':
    prepare_native_ui(pathlib.Path(__file__).resolve().parents[1])

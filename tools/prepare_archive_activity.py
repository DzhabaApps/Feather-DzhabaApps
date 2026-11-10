"""Embed the widget only in the opt-in iPhone trial build."""
import pathlib
import plistlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
ruby = r'''
require 'xcodeproj'
objects = Xcodeproj::Project::Object
attribute = objects::PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.attributes.find { |a| a.name == :build_phase }
attribute.classes |= [objects::PBXResourcesBuildPhase]
objects::PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet.class_eval do
  def display_name
    'Synchronized build phase exceptions'
  end
end
root, commit = ARGV
project = Xcodeproj::Project.open(File.join(root, 'Feather.xcodeproj'))
app = project.targets.find { |target| target.name == 'Feather' }
exit 0 if project.targets.any? { |target| target.name == 'ArchiveActivity' }
widget = project.new_target(:app_extension, 'ArchiveActivity', :ios, '16.2')
['ArchiveActivity/ArchiveActivityWidget.swift', 'Feather/Backend/Observable/ArchiveActivityAttributes.swift'].each do |source|
  ref = project.main_group.new_file(File.join(root, source))
  widget.source_build_phase.add_file_reference(ref)
end
widget.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'ru.dzhabaapps.fizer.preview.ArchiveActivity',
    'PRODUCT_NAME' => 'ArchiveActivity',
    'SWIFT_VERSION' => '5.0',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_FILE' => 'ArchiveActivity/Info.plist',
    'MARKETING_VERSION' => '2.2.8',
    'CURRENT_PROJECT_VERSION' => commit,
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'CODE_SIGNING_ALLOWED' => 'NO',
  })
end
app.build_configurations.each do |config|
  value = config.build_settings.fetch('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '$(inherited)')
  config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = Array(value).join(' ') + ' ARCHIVE_LIVE_ACTIVITY_TEST'
end
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed Archive Activity')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(widget.product_reference)
project.save
'''
subprocess.run(["ruby", "-e", ruby, str(root), commit], check=True)
widget_info = {"NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
(root / "ArchiveActivity/Info.plist").write_bytes(plistlib.dumps(widget_info))
app_info = root / "Feather/Resources/Info.plist"
data = plistlib.loads(app_info.read_bytes())
data["NSSupportsLiveActivities"] = True
app_info.write_bytes(plistlib.dumps(data, sort_keys=False))

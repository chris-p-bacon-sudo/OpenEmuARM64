require 'xcodeproj'

project_path = 'OpenEmu/OpenEmu.xcodeproj'
project = Xcodeproj::Project.open(project_path)

group = project.main_group.find_subpath('OpenEmu', true)
target = project.targets.find { |t| t.name == 'OpenEmu' }

abort("Target 'OpenEmu' not found") unless target

filename = 'PrefCloudSyncController.swift'

existing = project.files.find { |f| f.path == filename }
if existing
  puts "Already in project: #{filename}"
else
  file_ref = group.new_reference(File.join(File.dirname(project_path), 'OpenEmu', filename))
  file_ref.path = filename
  file_ref.source_tree = '<group>'
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{filename}"
end

project.save
puts "Project saved."

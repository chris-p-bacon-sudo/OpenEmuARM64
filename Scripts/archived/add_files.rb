require 'xcodeproj'

project_path = 'OpenEmu/OpenEmu.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Print info
puts "Opened project: #{project_path}"
puts "Targets: #{project.targets.map(&:name).join(', ')}"

group = project.main_group.find_subpath('OpenEmu', true)
target = project.targets.find { |t| t.name == 'OpenEmu' }

abort("Target 'OpenEmu' not found") unless target

files = [
  'OEGoogleDriveConfig.swift',
  'OESaveSyncManager.swift',
  'OESyncStatusOverlayView.swift'
]

files.each do |filename|
  full_path = File.join(File.dirname(project_path), 'OpenEmu', filename)
  
  # Skip if already in project
  existing = project.files.find { |f| f.path == filename }
  if existing
    puts "Already in project: #{filename}"
    next
  end
  
  file_ref = group.new_reference(full_path)
  file_ref.path = filename
  file_ref.source_tree = '<group>'
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{filename}"
end

project.save
puts "Project saved."

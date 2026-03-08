require 'xcodeproj'

project_path = '/Volumes/HD/shen/Documents/code/Lookin/Lookin.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'LookinClient' }

if target.nil?
  puts "Target LookinClient not found"
  exit(1)
end

# Find the group LookinClient/MCP
lookin_client_group = project.main_group.find_subpath('LookinClient', true)
mcp_group = lookin_client_group.find_subpath('MCP', true)

# Create file reference
file_path = 'MCP/LKMCPManager.swift' # relative to LookinClient? No, Lookin/LookinClient/MCP
full_path = '/Volumes/HD/shen/Documents/code/Lookin/LookinClient/MCP/LKMCPManager.swift'

file_ref = mcp_group.files.find { |f| f.path == 'LKMCPManager.swift' }
if file_ref.nil?
  file_ref = mcp_group.new_file(full_path)
end

# Ensure it's in the compile phase
source_build_phase = target.source_build_phase
build_file = source_build_phase.files.find { |f| f.file_ref == file_ref }

if build_file.nil?
  source_build_phase.add_file_reference(file_ref)
  puts "Added LKMCPManager.swift to target"
else
  puts "LKMCPManager.swift already in target"
end

project.save
puts "Successfully saved project!"

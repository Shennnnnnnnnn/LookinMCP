require 'xcodeproj'

project_path = '/Volumes/HD/shen/Documents/code/Lookin/Lookin.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'LookinClient' }

if target.nil?
  puts "Target LookinClient not found"
  exit(1)
end

target.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
end

project.save
puts "Successfully bumped MACOSX_DEPLOYMENT_TARGET to 13.0!"

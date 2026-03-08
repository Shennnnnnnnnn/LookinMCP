require 'xcodeproj'

project_path = '/Volumes/HD/shen/Documents/code/Lookin/Lookin.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Ensure the package reference is added
package_url = 'https://github.com/modelcontextprotocol/swift-sdk.git'
package_req = {
  :kind => 'upToNextMajorVersion',
  :minimumVersion => '0.11.0'
}

pkg_ref = project.root_object.package_references.find { |pr| pr.repositoryURL == package_url }
if pkg_ref.nil?
    pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    pkg_ref.repositoryURL = package_url
    pkg_ref.requirement = package_req
    project.root_object.package_references << pkg_ref
    puts "Added external package reference"
else
    puts "Package reference already exists"
end

# Find the specific target we need (LookinClient)
target = project.targets.find { |t| t.name == 'LookinClient' }

if target.nil?
  puts "Target LookinClient not found!"
  exit(1)
end

# Ensure the framework reference is added to the target
pkg_product = target.package_product_dependencies.find { |pp| pp.product_name == 'MCP' }
if pkg_product.nil?
    pkg_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    pkg_product.product_name = 'MCP'
    pkg_product.package = pkg_ref
    target.package_product_dependencies << pkg_product
    puts "Added MCP package product dependency to target"
else
    puts "MCP dependency already present in target"
end

frameworks_build_phase = target.build_phases.find { |bp| bp.isa == 'PBXFrameworksBuildPhase' }
if frameworks_build_phase
  # We just need to ensure the product is linked in the build phase if it's missing (rare, but good for completeness in xcodeproj gem)
  # Actually, adding to package_product_dependencies is usually enough for Xcode to pick it up, 
  # but sometimes we must explicitly add a build file for it in the frameworks phase.
  # We'll rely on the package_product_dependencies being sufficient, which works in Xcode 11+.
end

project.save
puts "Successfully saved project!"

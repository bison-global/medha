#
# iOS: compiles the C shim and links a prebuilt llama.xcframework (Metal).
# Build the framework first with tool/build_ios_llama.sh from the repo root.
#
Pod::Spec.new do |s|
  s.name             = 'medha_llama'
  s.version          = '0.1.0'
  s.summary          = "Medha's FFI bridge to llama.cpp."
  s.homepage         = 'https://bisonglobaltech.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Bison Global Tech' => 'dev@bisonglobaltech.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.vendored_frameworks = 'Frameworks/llama.xcframework'
  s.frameworks       = 'Foundation', 'Metal', 'MetalKit', 'Accelerate'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
  }
  s.swift_version = '5.0'
end

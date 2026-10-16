Gem::Specification.new do |spec|
  spec.name          = "dsl"
  spec.version       = "0.2.0"
  spec.summary       = "Protea DSL: architecture and device description toolchain"
  spec.description   = "A domain-specific language (DSL) for defining and simulating CPU architectures and peripheral devices."
  spec.authors       = ["Shamshura Egor"]
  spec.executables   = ["plod"]
  spec.files = Dir["lib/**/*", "targets/*.yaml", "exe/plod", "sim_gen/**/*", "dev_gen/CMakeLists.txt"]
  spec.require_paths = ["lib", "."]
  spec.bindir        = "exe"
end

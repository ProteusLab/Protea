Gem::Specification.new do |spec|
  spec.name          = "dsl"
  spec.version       = "0.1.0"
  spec.summary       = "DSL project"
  spec.description   = "A domain-specific language (DSL) for defining and simulating CPU architectures."
  spec.authors       = ["Shamshura Egor"]
  spec.files = Dir["lib/**/*", "sim_gen/**/*", "dev_gen/**/*"]
  spec.require_paths = ["lib", "."]
end

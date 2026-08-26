# frozen_string_literal: true

require 'yaml'

require_relative 'Plod/diagnostics'
require_relative 'Plod/types'
require_relative 'Plod/ir'
require_relative 'Plod/slate'
require_relative 'Plod/env'
require_relative 'Plod/decl'
require_relative 'Plod/body'
require_relative 'Plod/frontend'
require_relative 'Plod/sema'
require_relative 'Plod/backend/target'
require_relative 'Plod/backend/cpp'
require_relative 'Plod/cli'

module Plod
  VERSION = '0.2.0'

  def self.yaml_dump(obj)
    YAML.dump(obj)
  end

  def self.yaml_load(str)
    YAML.unsafe_load(str)
  end

  def self.yaml_load_file(path)
    YAML.unsafe_load_file(path)
  end
end

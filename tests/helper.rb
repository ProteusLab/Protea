# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'SDL/plod'
require_relative '../dev_gen/gen_hpp'

module Protea
  class PlodTestCase < Minitest::Test
    def setup
      System.reset
      Protea::GlobalCounter.reset
      Protea::Var.instance_variable_set(:@scope, nil)
      Protea::Var.instance_variable_set(:@scopes, [])
    end
  end

  class DevGenTestCase < Minitest::Test
    def setup
      DevGen.reset
    end

    def setup_devgen(devdesc: {}, self_name: nil)
      DevGen.instance_variable_set(:@devdesc, devdesc)
      DevGen.instance_variable_set(:@self, self_name)
    end

    def devgen_tmphash
      DevGen.instance_variable_get(:@tmphash)
    end
  end
end

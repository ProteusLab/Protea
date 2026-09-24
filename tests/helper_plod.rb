# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'yaml'

$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require 'Plod'

module Plod
  class TestCase < Minitest::Test
  end
end

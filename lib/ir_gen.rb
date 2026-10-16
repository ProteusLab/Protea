#!/usr/bin/ruby
# frozen_string_literal: true

require 'Common/base'
require 'ADL/builder'
require 'Target/RISC-V/32I'

require 'yaml'

yaml_data = Protea.serialize
File.write('IR.yaml', yaml_data)

#!/usr/bin/ruby
# frozen_string_literal: true

require 'Common/base'
require 'ADL/builder'
require 'Target/RISC-V/32I'

require 'yaml'

yaml_data = SimInfra.serialize
File.write('IR.yaml', yaml_data)

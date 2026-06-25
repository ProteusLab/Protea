#!/usr/bin/ruby
# frozen_string_literal: true

require 'ADL/base'
require 'ADL/builder'
require 'Target/RISC-V/32I'
require 'Target/RISC-V/32M'

yaml_data = SimInfra.serialize
File.write('IR.yaml', yaml_data)

#!/usr/bin/ruby
# frozen_string_literal: true
require 'yaml'

require 'Devices/clint'
require 'Devices/ns16550'
require 'Devices/uart8250'

System.process_semablocks

File.write(ARGV[0], System.desc.to_yaml)

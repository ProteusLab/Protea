#!/usr/bin/ruby
# frozen_string_literal: true
require 'yaml'

require 'Devices/uart8250'

System.process_semablocks

File.write('SDL.yaml', System.desc.to_yaml)

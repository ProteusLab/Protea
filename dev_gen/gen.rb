#!/usr/bin/ruby
# frozen_string_literal: true

require 'yaml'
require_relative 'gen_hpp'
require_relative 'timer'
require_relative 'uart'

SPECS = {
  Clint: DevGen::Timer,
  ns16550: DevGen::Uart,
  Uart8250: DevGen::Uart
}.freeze

ir = YAML.load_file(ARGV[0])

filter = ARGV[1]
out_path = ARGV[2]

devices = ir[:devices]
devices = devices.select { |name, _| name.to_sym == filter.to_sym } unless filter.nil?

devices.each do |name, desc|
  spec = SPECS[name.to_sym]
  raise "No spec registered for device #{name}" if spec.nil?

  header = DevGen.gen_header(name, desc, spec)
  if out_path.nil?
    puts header
  else
    File.write(out_path, header)
  end
end

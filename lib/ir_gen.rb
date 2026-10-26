#!/usr/bin/ruby
# frozen_string_literal: true

require 'optparse'

require 'ADL/base'
require 'ADL/builder'

options = { output: 'IR.yaml', target: nil }
OptionParser.new do |opts|
  opts.banner = 'Usage: ir_gen.rb --target DIR --output FILE'
  opts.on('-t', '--target PATH', 'Target directory or file to load') { |v| options[:target] = v }
  opts.on('-o', '--output PATH', 'Output file (default: IR.yaml)') { |v| options[:output] = v }
end.parse!

abort 'error: --target is required' if options[:target].nil?

paths = if File.directory?(options[:target])
          Dir[File.join(options[:target], '*.rb')].sort
        else
          [options[:target]]
        end
paths.each { |path| require File.expand_path(path) }

File.write(options[:output], SimInfra.serialize)

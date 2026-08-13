# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.test_files = FileList['tests/PlodTests/*_tests.rb',
                          'tests/DevGenTests/*_tests.rb']
  t.verbose = true
end

task default: :test

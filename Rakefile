# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.test_files = FileList['tests/Plod/*_tests.rb']
  t.verbose = true
end

desc 'Regenerate golden C++ headers from the current toolchain'
task 'golden:update' do
  require_relative 'lib/Plod'
  targets = Plod::Backend::Target::Registry.new([File.join(__dir__, 'targets')])
  {
    'lib/Devices/clint.rb' => :Clint,
    'lib/Devices/ns16550.rb' => :ns16550,
    'lib/Devices/uart8250.rb' => :Uart8250
  }.each do |src, device|
    fe = Plod::Frontend.load_file(src)
    abort "frontend errors in #{src}:\n#{fe.diag}" if fe.diag.error?
    target = targets.for_device(device)
    abort "no target for #{device}" unless target

    header = Plod::Backend::Cpp.generate(fe.program, device, target)
    golden = File.join(__dir__, 'tests', 'golden', "#{device}.hh")
    File.write(golden, header)
    puts "updated #{golden}"
  end
end

task default: :test

# frozen_string_literal: true

require_relative '../helper_plod'
require 'fileutils'

class X86DeviceRuntimeTests < Plod::TestCase
  ROOT = File.expand_path('../..', __dir__)
  DEVICES = { I8042: 'i8042', I82094AA: 'i82094aa', I8237: 'i8237', I8254: 'i8254', I8259: 'i8259' }.freeze
  SCENARIOS = %w[
    keyboard_commands keyboard_queues keyboard_ports dma_controls pit_events pit_invalid
    pic_interrupts pic_cascade pic_inta_overlap pic_randomized ioapic_registers ioapic_routing ioapic_extint pc_initialization
  ].freeze
  ASSERTIONS = %w[
    keyboard_bad_width keyboard_bad_write_width keyboard_bad_status_width keyboard_bad_command_width
    pit_bad_width pic_bad_width ioapic_bad_width ioapic_bad_id ioapic_bad_line pic_slave_inta
  ].freeze

  def self.binaries
    return @binaries if @binaries

    dir = Dir.mktmpdir('plod-x86-runtime-')
    Minitest.after_run { FileUtils.remove_entry(dir) }
    targets = Plod::Backend::Target::Registry.new([File.join(ROOT, 'targets')])
    DEVICES.each do |device, file|
      fe = Plod::Frontend.load_file(File.join(ROOT, 'lib', 'Devices', "#{file}.rb"))
      raise fe.diag.to_s if fe.diag.error?

      diag = Plod::Checker.check(fe.program)
      raise diag.to_s if diag.error?

      File.write(File.join(dir, "#{device}.hh"), Plod::Backend::Cpp.generate(fe.program, device, targets.for_device(device)))
    end
    runtime = File.join(ROOT, 'tests', 'support', 'device_runtime', 'x86_devices.cc')
    stub = File.join(ROOT, 'tests', 'support', 'gem5_stub')
    reference = File.join(ROOT, 'tests', 'support', 'gem5_reference')
    timer = File.join(reference, 'dev', 'intel_8254_timer.cc')
    generated = File.join(dir, 'generated')
    original = File.join(dir, 'original')
    commands = [
      ['g++', '-std=c++23', "-I#{dir}", "-I#{stub}", runtime, timer, '-o', generated],
      ['g++', '-std=c++23', '-DPLOD_REFERENCE', "-I#{reference}", "-I#{stub}", runtime, timer,
       *DEVICES.values.map { |file| File.join(reference, 'dev', 'x86', "#{file}.cc") }, '-o', original]
    ]
    commands.each do |command|
      out, status = Open3.capture2e(*command)
      raise "x86 runtime compilation failed:\n#{out}" unless status.success?
    end
    @binaries = [generated, original]
  end

  SCENARIOS.each do |scenario|
    define_method("test_matches_gem5_#{scenario}") do
      outputs = self.class.binaries.map do |binary|
        out, status = Open3.capture2e(binary, scenario)
        assert status.success?, "#{File.basename(binary)} #{scenario} failed:\n#{out}"
        assert_includes out, "OK #{scenario}"
        out
      end
      assert_equal outputs.last, outputs.first, "generated #{scenario} differs from source gem5"
    end
  end

  ASSERTIONS.each do |scenario|
    define_method("test_matches_gem5_assertion_#{scenario}") do
      self.class.binaries.each do |binary|
        output, status = Open3.capture2e(binary, scenario, rlimit_core: 0)
        assert status.signaled?, output
        assert_equal Signal.list.fetch('ABRT'), status.termsig
      end
    end
  end
end

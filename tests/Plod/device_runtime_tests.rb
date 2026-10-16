# frozen_string_literal: true

require_relative '../helper_plod'
require 'fileutils'

class DeviceRuntimeTests < Plod::TestCase
  ROOT = File.expand_path('../..', __dir__)
  SCENARIOS = %w[
    plic_geometry plic_interrupts plic_timing plic_checkpoint plic_contexts
    plic_randomized vio_registers vio_interrupts vio_checkpoint invalid_accesses
  ].freeze

  # Build once per suite. The reference sources and native RegisterBank are
  # frozen fixtures, so these tests work without the external gem5 checkout.
  def self.binaries
    return @binaries if @binaries

    dir = Dir.mktmpdir('plod-runtime-')
    Minitest.after_run { FileUtils.remove_entry(dir) }
    targets = Plod::Backend::Target::Registry.new([File.join(ROOT, 'targets')])
    { Plic: 'plic', MmioVirtIO: 'vio_mmio' }.each do |device, file|
      fe = Plod::Frontend.load_file(File.join(ROOT, 'lib', 'Devices', "#{file}.rb"))
      raise fe.diag.to_s if fe.diag.error?

      diag = Plod::Checker.check(fe.program)
      raise diag.to_s if diag.error?

      File.write(File.join(dir, "#{device}.hh"), Plod::Backend::Cpp.generate(fe.program, device, targets.for_device(device)))
    end
    runtime = File.join(ROOT, 'tests', 'support', 'device_runtime', 'devices.cc')
    stub = File.join(ROOT, 'tests', 'support', 'gem5_stub')
    reference = File.join(ROOT, 'tests', 'support', 'gem5_reference')
    generated = File.join(dir, 'generated')
    original = File.join(dir, 'original')
    commands = [
      ['g++', '-std=c++23', "-I#{dir}", "-I#{stub}", runtime, '-o', generated],
      ['g++', '-std=c++23', '-DPLOD_REFERENCE', "-I#{reference}", "-I#{stub}", runtime,
       File.join(reference, 'dev', 'riscv', 'plic.cc'), File.join(reference, 'dev', 'riscv', 'vio_mmio.cc'), '-o', original]
    ]
    commands.each do |command|
      out, status = Open3.capture2e(*command)
      raise "runtime compilation failed:\n#{out}" unless status.success?
    end
    @binaries = [generated, original]
  end

  def test_plic_mismatched_completion_asserts
    self.class.binaries.each do |binary|
      output, status = Open3.capture2e(binary, 'plic_bad_complete', rlimit_core: 0)
      assert status.signaled?, output
      assert_equal Signal.list.fetch('ABRT'), status.termsig
    end
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
end

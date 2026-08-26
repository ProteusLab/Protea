# frozen_string_literal: true

require_relative '../helper_plod'

class BackendCppTests < Plod::TestCase
  ROOT = File.expand_path('../..', __dir__)
  TARGETS = Plod::Backend::Target::Registry.new([File.join(ROOT, 'targets')])
  GOLDEN = File.join(ROOT, 'tests', 'golden')
  STUB = File.join(ROOT, 'tests', 'support', 'gem5_stub')

  DEVICES = {
    Clint: 'clint',
    ns16550: 'ns16550',
    Uart8250: 'uart8250'
  }.freeze

  def build(device)
    file = DEVICES.fetch(device)
    fe = Plod::Frontend.load_file(File.join(ROOT, 'lib', 'Devices', "#{file}.rb"))
    assert_empty fe.diag.to_s, "#{file}: #{fe.diag}"
    target = TARGETS.for_device(device)
    refute_nil target, "no target for #{device}"
    Plod::Backend::Cpp.generate(fe.program, device, target)
  end

  DEVICES.each_value do |file|
    define_method("test_golden_#{file}") do
      device = DEVICES.key(file)
      header = build(device)
      golden_path = File.join(GOLDEN, "#{device}.hh")
      assert File.exist?(golden_path), "missing golden #{golden_path}"
      assert_equal File.read(golden_path), header, "generated header for #{device} differs from golden (run `rake golden:update` to refresh)"
    end
  end

  def test_headers_compile
    Dir.mktmpdir do |tmp|
      DEVICES.each_key do |device|
        header = build(device)
        path = File.join(tmp, "#{device}.hh")
        File.write(path, header)
        out, status = Open3.capture2('g++', '-std=c++23', '-fsyntax-only', "-I#{STUB}", path)
        assert status.success?, "#{device}.hh failed to compile:\n#{out}"
      end
    end
  end

  def test_deterministic_output
    DEVICES.each_key do |device|
      assert_equal build(device), build(device), "#{device} generation is not deterministic"
    end
  end

  def test_for_loop_initializes_iterator
    header = build(:Clint)
    assert_includes header, 'for (int cid = 0; cid < nThread; ++cid)'
    assert_includes header, 'for (int cid = 0; cid < 4096; ++cid)'
    refute_includes header, 'cid < 0;'
  end

  def test_write_only_registers_reach_write_dispatch
    header = build(:Uart8250)
    %i[thr fcr].each do |reg|
      assert_includes header, "#{reg}_write(write_data);", ":wo register #{reg} missing from write dispatch"
    end
  end

  def test_read_only_registers_reach_read_dispatch
    header = build(:Uart8250)
    %i[rbr iir lsr msr].each do |reg|
      assert_includes header, "#{reg}_read()", ":ro register #{reg} missing from read dispatch"
    end
  end

  def test_no_qualified_definitions_inside_class
    DEVICES.each_key do |device|
      header = build(device)
      refute_match(/:\s*\n\s*#{device}::(getPort|init)\(/, header, 'qualified member definition inside class')
    end
  end

  def test_no_undefined_leaked_ruby_values
    DEVICES.each_key do |device|
      header = build(device)
      refute_includes header, 'regset', "#{device}: Ruby var hash leaked into C++"
      refute_includes header, '_tmp', "#{device}: temp variable leaked into C++"
      refute_includes header, ':name', "#{device}: Ruby hash literal leaked into C++"
    end
  end

  def test_enable_if_guards_dispatch
    header = build(:Uart8250)
    assert_includes header, '&& ((protea::_extract(lcr, 7, 1) == 0))', 'enableIf predicate missing from dispatch'
  end

  def test_sequential_register_dispatch_uses_cid
    header = build(:Clint)
    assert_includes header, 'uint64_t cid = (daddr - 0) / 4;'
    assert_includes header, 'msip_read(cid)'
    assert_includes header, 'msip_write(write_data, cid)'
  end

  def test_user_struct_is_emitted
    header = build(:ns16550)
    assert_includes header, 'struct fifo8 {'
    assert_includes header, 'uint8_t pop()'
  end
end

class ApiContractTests < Plod::TestCase
  ROOT = File.expand_path('../..', __dir__)
  LEGACY = File.join(ROOT, 'tests', 'golden', 'legacy')

  LEGACY_API = {
    Clint: {
      base: 'BasicPioDevice',
      methods: %w[
        msip_write msip_read msip_update mtimecmp_write mtimecmp_read
        mtime_read mtime_write raiseInterruptPin reg_init doReset
        read write getAddrRanges serialize unserialize getPort init
      ],
      params: 'ClintParams'
    },
    ns16550: {
      base: 'BasicPioDevice',
      methods: %w[
        rbr_read rbr_write thr_read thr_write ier_read ier_write iir_read iir_write
        fcr_read fcr_write lcr_read lcr_write mcr_read mcr_write lsr_read lsr_write
        msr_read msr_write scr_read scr_write dll_read dll_write dlm_read dlm_write
        read write getAddrRanges serialize unserialize getPort init
      ],
      params: 'ns16550Params'
    },
    Uart8250: {
      base: 'BasicPioDevice',
      methods: %w[
        rbr_read rbr_write thr_write thr_read ier_write ier_read iir_read iir_write
        fcr_read fcr_write lcr_read lcr_write mcr_write mcr_read lsr_read lsr_write
        msr_read msr_write scr_read scr_write dll_read dll_write dlm_read dlm_write
        dataAvailable intStatus processIntrEvent scheduleIntr clearIntr
        read write getAddrRanges serialize unserialize getPort init
      ],
      params: 'Uart8250Params'
    }
  }.freeze

  def self.api_from(text)
    methods = text.scan(/^\s*(?:virtual\s+)?[\w:<>*&\s]+?\b(\w+)\s*\(/).flatten.uniq
    classes = text.scan(/^\s*class\s+(\w+)\s*:\s*public\s+(\w+)/).flatten
    { methods: methods, classes: classes }
  end

  LEGACY_API.each do |device, expected|
    define_method("test_api_contract_#{device}") do
      legacy_path = File.join(LEGACY, "#{device}.hh")
      assert File.exist?(legacy_path), "missing legacy snapshot #{legacy_path}"
      legacy = File.read(legacy_path)

      assert_includes legacy, "class #{device} : public #{expected[:base]}"

      api = self.class.api_from(legacy)
      missing = expected[:methods] - api[:methods]
      assert_empty missing, "legacy #{device} lost methods: #{missing}"

      assert_includes legacy, "const #{expected[:params]} &params"
    end
  end
end

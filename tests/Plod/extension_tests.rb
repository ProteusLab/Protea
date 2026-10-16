# frozen_string_literal: true

require_relative '../helper_plod'

class PlodExtensionTests < Plod::TestCase
  ROOT = File.expand_path('../..', __dir__)

  def frontend(source)
    ruby = Plod::Pld::Translator.translate(source, 'extension.pld')
    fe = Plod::Frontend.load_source(ruby, 'extension.rb')
    assert_empty fe.diag.to_s, fe.diag.to_s
    fe
  end

  def checked(source)
    fe = frontend(source)
    diag = Plod::Checker.check(fe.program)
    assert_empty diag.to_s, diag.to_s
    fe
  end

  def test_collection_types_roundtrip
    types = [Plod::Types::Vector.new(Plod::Types::Bits.new(32)),
             Plod::Types::Map.new(Plod::Types::Str.new, Plod::Types::Vector.new(Plod::Types::Bits.new(8)))]
    types.each do |type|
      assert_equal type, Plod::Types.from_h(type.to_h)
      assert_equal type, Plod::Types.from_h(Plod.yaml_load(Plod.yaml_dump(type.to_h)))
    end
    assert_raises(ArgumentError) { Plod::Types::Vector.new(nil) }
    assert_raises(ArgumentError) { Plod::Types::Map.new(nil, types.first) }
  end

  def test_constructor_loops_const_and_nested_collections
    fe = checked(<<~PLD)
      abstract struct Params { int count; }
      abstract struct Out {}
      struct Output { vector<b32> ids; }
      device D {
        int count;
        vector<vector<b32>> values;
        map<b64, Output> pending;
        constructor(Params& params) : count(params.count) {
          values.resize(count);
          for (int i = 0; i < count; ++i) {
            values.at(i).resize(3, 0);
          }
        }
        void save(Out& out) const {
          map<b64, Output> copy = pending;
          for (int i = 0; i < pending.size(); i++) {
            Output entry = copy.firstValue();
            copy.eraseFirst();
          }
        }
      }
    PLD
    device = fe.program.devices.first
    assert device.methods.first.const
    assert_instance_of Plod::Types::Ref, device.ctor.args.first.last
    assert_equal :for, device.ctor.body.last.kind
    assert_equal fe.program.to_h, Plod::IR.from_h(fe.program.to_h).to_h
  end

  def test_runtime_layout_roundtrip_and_implicit_index
    fe = checked(<<~PLD)
      device D {
        int count;
        register words: size(4), offset(0x1000), window(0x1000) {
          layout { repeat(count, 0x80); repeat(3, 4); }
          void write(b32 data) { self = data | static_cast<b32>(cid); }
        }
      }
    PLD
    reg = fe.program.devices.first.registers.first
    assert reg.banked?
    assert_equal 2, reg.layout.size
    assert_equal 0x1000, reg.window
    roundtrip = Plod::IR.from_h(Plod.yaml_load(Plod.yaml_dump(fe.program.to_h)))
    assert_equal fe.program.to_h, roundtrip.to_h
    assert_instance_of Plod::IR::VarRef, roundtrip.devices.first.registers.first.layout.first.first
  end

  def test_collection_calls_check_arguments
    fe = frontend(<<~PLD)
      device D {
        vector<b32> values;
        map<b64, b32> pending;
        void bad() {
          values.push("bad");
          values.resize();
          pending.put(0, "bad");
          pending.firstKey(1);
        }
      }
    PLD
    diag = Plod::Checker.check(fe.program)
    assert diag.error?
    assert_includes diag.to_s, 'expects b32, got str'
    assert_includes diag.to_s, 'wrong number of arguments'
  end

  def test_invalid_layout_is_rejected
    [
      'layout {}',
      'layout { repeat("bad", 4); }',
      'layout { repeat(4, "bad"); }'
    ].each do |layout|
      fe = frontend("device D { register r: size(4), offset(0) { #{layout} } }")
      assert Plod::Checker.check(fe.program).error?, layout
    end
    fe = frontend('device D { register r: size(4), offset(0), window(3) {} }')
    assert Plod::Checker.check(fe.program).error?
  end

  def test_layout_cid_is_reserved
    ruby = Plod::Pld::Translator.translate(<<~PLD)
      device D {
        register r: size(4), offset(0) {
          layout { repeat(2, 4); }
          void write(b32 data, int cid) { self = data; }
        }
      }
    PLD
    fe = Plod::Frontend.load_source(ruby)
    assert fe.diag.error?
    assert_includes fe.diag.to_s, 'implicit bank index'
  end

  def test_c_and_ruby_precedence_matches_the_ast
    fe = checked(<<~PLD)
      device D {
        bool ready(int x, int y) { return (x == 1) & (y != 2); }
        int mask(int x) { return x & 3 == 1; }
      }
    PLD
    expressions = fe.program.devices.first.methods.map { |m| m.body.first.value }
    assert_equal :and, expressions.first.op
    assert_equal :eq, expressions.first.lhs.op
    assert_equal :ne, expressions.first.rhs.op
    assert_equal :and, expressions.last.op
    assert_equal :eq, expressions.last.rhs.op
  end

  def test_string_concatenation_and_literal_left_arithmetic
    checked(<<~PLD)
      abstract string toString(int n);
      device D {
        string key(int n) { return "word" + toString(n); }
        int calc(int n) { return 32 * n + 0x1000; }
      }
    PLD
  end

  def test_source_notices_and_line_numbers
    source = "/*\nCopyright test\n*/\n\ndevice D {}\n"
    fe = frontend(source)
    assert_equal "/*\nCopyright test\n*/", fe.program.notice
    tok = Plod::Pld::Lexer.tokenize(source).find { |t| t[1] == 'device' }
    assert_equal 5, tok.last
    error = assert_raises(Plod::Error) { Plod::Pld::Parser.parse("device D {\n\n?\n}", 'broken.pld') }
    assert_includes error.message, 'broken.pld:3'
  end

  def test_device_ir_roundtrips_with_layouts_and_checkpoints
    %w[plic vio_mmio i8042 i82094aa i8237 i8254 i8259].each do |file|
      fe = Plod::Frontend.load_file(File.join(ROOT, 'lib', 'Devices', "#{file}.rb"))
      assert_empty fe.diag.to_s
      assert_equal fe.program.to_h, Plod::IR.from_h(Plod.yaml_load(Plod.yaml_dump(fe.program.to_h))).to_h
    end
  end

  def test_i8042_directional_register_map
    path = File.join(ROOT, 'lib', 'Devices', 'i8042.rb')
    fe = Plod::Frontend.load_file(path)
    assert_empty fe.diag.to_s
    device = fe.program.devices.first
    assert_equal [[:output_buffer, 1, 0, :ro], [:input_buffer, 1, 0, :wo],
                  [:status, 1, 4, :ro], [:command, 1, 4, :wo]],
                 device.registers.map { |reg| [reg.name, reg.size, reg.offset, reg.access] }
  end

  def test_generic_bank_defaults_and_multidimensional_access
    fe = checked(<<~PLD)
      abstract struct PlicParams { int n_src; }
      device D {
        int count;
        constructor(PlicParams& params) : count(params.n_src) {}
        register scalar: size(4), offset(0) {
          b32 read() { return self; }
          void write(b32 data) { self = data; }
        }
        register words: size(4), offset(0x1000), window(0x1000) {
          layout { repeat(count, 32); repeat(2, 8); repeat(2, 4); }
          void write(b32 data) { self = data + static_cast<b32>(cid); }
        }
      }
    PLD
    registry = Plod::Backend::Target::Registry.new([File.join(ROOT, 'targets')])
    target = Plod::Backend::Target.from_h(name: 'generic', base: 'BasicPioDevice',
                                          ctor_base_args: 'params, params.pio_size', params_type: 'PlicParams',
                                          register_backend: 'gem5_bank', includes: registry.for_device(:Plic).includes)
    header = Plod::Backend::Cpp.generate(fe.program, :D, target)
    refute_includes header, 'void serialize(', 'native framework checkpoint methods must remain inherited'
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'D.hh'), header)
      File.write(File.join(dir, 'test.cc'), <<~CPP)
        #include "D.hh"
        int main() {
            gem5::PlicParams params; params.n_src = 2; params.pio_addr = 0x100000;
            gem5::D dev(params); dev.init();
            for (unsigned i = 0; i < 8; ++i) {
                auto offset = 0x1000 + (i / 4) * 32 + (i % 4) * 4;
                gem5::Packet pkt(dev.pioAddr + offset); pkt.setLE<uint32_t>(10);
                if (dev.write(&pkt) != dev.pioDelay || !pkt.response) return 1;
                dev.read(&pkt); if (pkt.getLE<uint32_t>() != 10 + i) return 2;
            }
            gem5::Packet scalar(dev.pioAddr); scalar.setLE<uint32_t>(0x11223344);
            dev.write(&scalar); dev.read(&scalar);
            if (scalar.getLE<uint32_t>() != 0x11223344) return 3;
            gem5::Packet partial(dev.pioAddr + 1, 1); partial.payload[0] = 0x55;
            dev.write(&partial); dev.read(&scalar);
            if (scalar.getLE<uint32_t>() != 0x11225544) return 4;
            gem5::Packet gap(dev.pioAddr + 0x1010); gap.setLE<uint32_t>(0xffffffff);
            dev.write(&gap); dev.read(&gap); if (gap.getLE<uint32_t>() != 0) return 5;
        }
      CPP
      exe = File.join(dir, 'test')
      out, status = Open3.capture2e('g++', '-std=c++23', "-I#{File.join(ROOT, 'tests/support/gem5_stub')}", File.join(dir, 'test.cc'), '-o', exe)
      assert status.success?, out
      out, status = Open3.capture2e(exe)
      assert status.success?, out
    end
  end

  def test_string_map_index_types
    checked(<<~PLD)
      device D {
        map<string, b32> values;
        b32 value() {
          values.set("key", 7);
          return values.get("key");
        }
      }
    PLD
  end

  def test_target_metadata_and_unknown_backend
    target = Plod::Backend::Target.from_h(name: 'test', base: 'Base', namespace: 'gem5::Test', params_type: 'Params', inherited_fields: ['field'], register_backend: 'word')
    assert_equal 'gem5::Test', target.namespace
    assert_equal 'Params', target.params_type
    assert_equal [:field], target.inherited_fields
    assert_raises(Plod::Error) { Plod::Backend::Target.from_h(base: 'Base', register_backend: 'unknown') }
    assert_raises(Plod::Error) { Plod::Backend::Target.from_h(base: 'Base', namespace: 'bad namespace') }
  end

  def test_typed_callback_parameters
    fe = checked(<<~PLD)
      abstract struct Packet { void setWord(b32 value); }
      device D {
        auto callback = [](b32 number, Packet* pkt) { pkt.setWord(number); };
      }
    PLD
    callback = fe.program.devices.first.lambdas.first
    assert_equal %i[number pkt], callback.args.map(&:first)
    assert_equal [Plod::Types::Bits.new(32), Plod::Types::Ptr.new(Plod::Types::Named.new(:Packet))], callback.args.map(&:last)
    assert_equal fe.program.to_h, Plod::IR.from_h(Plod.yaml_load(Plod.yaml_dump(fe.program.to_h))).to_h
    target = Plod::Backend::Target.from_h(base: 'Base')
    header = Plod::Backend::Cpp.generate(fe.program, :D, target)
    assert_includes header, 'std::function<void(uint32_t, Packet*)>'
    assert_includes header, '[this](uint32_t number, Packet* pkt)'
  end

  def test_else_if_method_condition_preserves_branch_chain
    fe = checked(<<~PLD)
      abstract struct Peer { bool pending(); }
      device D {
        Peer* keyboard;
        Peer* mouse;
        int value;
        void poll() {
          if (keyboard.pending()) { value = 1; }
          else if (mouse.pending()) { value = 2; }
          else if (keyboard.pending() & mouse.pending()) { value = 3; }
          else { value = 4; }
        }
      }
    PLD
    body = fe.program.devices.first.methods.first.body
    assert_equal 1, body.size
    assert_equal 2, body.first.elsif_list.size
    refute_nil body.first.else_body
    # An intervening call used as a statement still breaks the branch chain.
    fe = Plod::Frontend.load_source(<<~RUBY)
      AbstractMethod(:touch)
      Device(:D) {
        Method(:poll) { If(1) {}; touch; Else {} }
      }
    RUBY
    assert fe.diag.error?
  end

  def test_null_pointer_comparisons
    checked(<<~PLD)
      abstract struct Peer {}
      device D {
        Peer* peer;
        bool missing() { return peer == 0; }
        bool present() { return peer != 0; }
        bool reversed() { return 0 == peer; }
      }
    PLD
    fe = frontend(<<~PLD)
      abstract struct Peer {}
      device D { Peer* peer; bool invalid() { return peer == 1; } }
    PLD
    assert Plod::Checker.check(fe.program).error?
    fe = frontend(<<~PLD)
      abstract struct Peer {}
      device D { Peer* peer; bool invalid() { return peer < 0; } }
    PLD
    assert Plod::Checker.check(fe.program).error?
  end

  def test_abstract_auto_arguments_are_framework_bound
    checked(<<~PLD)
      abstract void take(auto value);
      device D {
        void invoke() { take(1); take("label"); }
      }
    PLD
    fe = frontend(<<~PLD)
      abstract void take(b32 value);
      device D { void invoke() { take("label"); } }
    PLD
    assert Plod::Checker.check(fe.program).error?
  end

  def test_custom_backend_requires_packet_methods_and_suppresses_range_default
    target = Plod::Backend::Target.from_h(base: 'Base', register_backend: 'custom')
    fe = checked('device D {}')
    error = assert_raises(Plod::Error) { Plod::Backend::Cpp.generate(fe.program, :D, target) }
    assert_includes error.message, 'device-defined read and write'
    fe = checked(<<~PLD)
      abstract struct Packet {}
      abstract struct AddrRangeList {}
      device D {
        b64 read(Packet* pkt) { return 0; }
        b64 write(Packet* pkt) { return 0; }
        AddrRangeList getAddrRanges() const { AddrRangeList ranges; return ranges; }
      }
    PLD
    header = Plod::Backend::Cpp.generate(fe.program, :D, target)
    assert_equal 1, header.scan('getAddrRanges() const').size
    assert_equal 1, header.scan('uint64_t read(').size
    refute_includes header, 'RangeSize(pioAddr, pioSize)'
    refute_includes header, 'void serialize('
  end
end

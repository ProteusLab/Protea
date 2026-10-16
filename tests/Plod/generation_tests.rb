# frozen_string_literal: true

require_relative '../helper_plod'

class DeclarativeGenerationTests < Plod::TestCase
  ROOT = File.expand_path('../..', __dir__)
  TARGETS = Plod::Backend::Target::Registry.new([File.join(ROOT, 'targets')])

  def frontend(source)
    fe = Plod::Frontend.load_source(source)
    assert_empty fe.diag.to_s, fe.diag.to_s
    fe
  end

  def checked(source)
    fe = frontend(source)
    assert_empty Plod::Checker.check(fe.program).to_s
    fe
  end

  def target(**options)
    Plod::Backend::Target.from_h({
      base: 'BasicPioDevice', ctor_base_args: 'params, 4', params_type: 'I8237Params',
      register_backend: 'custom', includes: TARGETS.for_device(:I8237).includes,
      packet: { latency: 7, width: 1 }
    }.merge(options))
  end

  def test_all_seven_ports_use_generation
    %i[Plic MmioVirtIO I8042 I82094AA I8237 I8254 I8259].each do |name|
      target = TARGETS.for_device(name)
      file = name == :MmioVirtIO ? 'vio_mmio' : name.to_s.downcase
      fe = Plod::Frontend.load_file(File.join(ROOT, 'lib', 'Devices', "#{file}.rb"))
      assert_empty fe.diag.to_s
      device = fe.program.devices.first
      refute_nil target.packet
      refute_nil device.checkpoint
      assert_empty device.methods.map(&:name) & %i[read write serialize unserialize]
      assert_equal fe.program.to_h, Plod::IR.from_h(Plod.yaml_load(Plod.yaml_dump(fe.program.to_h))).to_h
    end
  end

  def test_checkpoint_validation
    cases = {
      "Scalar('x', value); Scalar('x', value)" => 'duplicate checkpoint key',
      "Scalar('x', 7)" => 'writable device storage',
      "Scalar('x', fixed)" => 'writable device storage',
      "Scalar('x', values)" => 'unsupported checkpoint value',
      "Scalar('x', ptr)" => 'unsupported checkpoint value',
      "Array('x', value)" => 'unsupported checkpoint value',
      "Repeat(:i, 'bad') { Scalar(Literal('x') + toString(i), value) }" => 'count must be numeric',
      'Repeat(:i, -1) {}' => 'cannot be negative',
      'Repeat(:value, 2) {}' => 'without shadowing',
      'Repeat(:cp, 2) {}' => 'without shadowing',
      'Repeat(:_plod_entry, 2) {}' => 'without shadowing',
      "Delegate(value, Prefix: 'x')" => 'Delegate requires',
      "Inherit(); Scalar('x', value)" => 'only checkpoint entry',
      'AfterRestore(:missing)' => 'zero-argument void',
      'AfterRestore(:getter)' => 'zero-argument void',
      "OrderedMap(queue, Count: 'n', CountType: Auto(), Iter: :i, Key: :k, Value: :v) {}" => 'CountType',
      "OrderedMap(queue, Count: 'n', CountType: B32(), Iter: :i, Key: :i, Value: :v) {}" => 'distinct local names',
      'Return 1' => 'only declarative checkpoint entries'
    }
    cases.each do |entries, message|
      fe = frontend(<<~RUBY)
        AbstractMethod(:toString, value: Int(), Ret: String())
        Device(:D) {
          Field(:value, B8())
          Field(:values, Vector(B32()))
          Field(:ptr, Ptr(B8()))
          Field(:queue, Map(B64(), B32()))
          Const(:fixed, B8(), 1)
          Method(:getter, Ret: B8()) { Return value }
          Checkpoint { #{entries} }
        }
      RUBY
      diag = Plod::Checker.check(fe.program)
      assert diag.error?, entries
      assert_includes diag.to_s, message, entries
    end
  end

  def test_checkpoint_conflicts_and_missing_blocks
    fe = frontend(<<~RUBY)
      Device(:D) {
        Method(:serialize) {}
        Checkpoint {}
      }
    RUBY
    assert_includes Plod::Checker.check(fe.program).to_s, 'conflicts with handwritten'
    ['Checkpoint', 'Checkpoint {}; Checkpoint {}', 'Register(:r, Size: 1, Offset: 0) { Address }'].each do |body|
      fe = Plod::Frontend.load_source("Device(:D) { #{body} }")
      assert fe.diag.error?, body
    end
  end

  def test_address_validation
    fe = frontend("Device(:D) { Register(:r, Size: 1, Offset: 0) { Address { Literal('bad') } } }")
    assert_includes Plod::Checker.check(fe.program).to_s, 'Address must be numeric'
    fe = Plod::Frontend.load_source('Device(:D) { Field(:x, B64()); Register(:r, Size: 1, Offset: 0) { Address { x[] = 1; x } } }')
    assert_includes fe.diag.to_s, 'single expression'
    fe = checked('Device(:D) { Field(:x, B64()); Register(:r, Size: 1, Offset: 0) { Address { x } } }')
    assert_raises(Plod::Error) do
      Plod::Backend::Cpp.generate(fe.program, :D, target(packet: nil, register_backend: 'legacy'))
    end
  end

  def test_packet_policy_validation
    [{ unexpected: 1 }, { response: 'bogus' }, { width: 3 }, { atomic_swap: 'yes' },
     { after_write: 'hook' }, { latency: 'x();' }, { forward: { start: 0 } }].each do |packet|
      assert_raises(Plod::Error) { target(packet: packet) }
    end
    fe = checked('Device(:D) { Register(:r, Size: 1, Offset: 0) {} }')
    [{ latency: 'missing', width: 1 }, { latency: 0, width: 1, after_write: ['missing'] },
     { latency: 0, width: 4 }, { latency: 0, width: 1, read_response: 'before_payload', atomic_swap: true },
     { latency: 0, width: 1, forward: { start: 256, receiver: 'missing', read: 'readConfig', write: 'writeConfig', latency: 0 } }].each do |packet|
      assert_raises(Plod::Error) { Plod::Backend::Cpp.generate(fe.program, :D, target(packet: packet)) }
    end
    fe = checked('Device(:D) { Method(:read) {}; Method(:write) {} }')
    assert_raises(Plod::Error) { Plod::Backend::Cpp.generate(fe.program, :D, target) }
  end

  def compile_and_run(headers, body)
    Dir.mktmpdir('plod-generation-') do |dir|
      headers.each { |name, header| File.write(File.join(dir, "#{name}.hh"), header) }
      File.write(File.join(dir, 'test.cc'), body)
      exe = File.join(dir, 'test')
      out, status = Open3.capture2e('g++', '-std=c++23', "-I#{File.join(ROOT, 'tests/support/gem5_stub')}",
                                    File.join(dir, 'test.cc'), '-o', exe)
      assert status.success?, out
      if status.success?
        out, status = Open3.capture2e(exe)
        assert status.success?, out
      end
    end
  end

  def test_packet_addresses_response_order_and_hooks
    source = <<~RUBY
      AbstractStruct(:Probe) {
        Method(:readValue, Ret: B8())
        Method(:writeValue, data: B8())
      }
      Device(:DEVICE) {
        Field(:matched, B64(), 0x60)
        Field(:probe, Ptr(Probe()))
        Field(:hooks, B32(), 0)
        Method(:attach, p: Ptr(Probe())) { probe[] = p }
        Method(:relocate, addr: B64()) { matched[] = addr }
        Method(:afterWrite) { hooks[] = hooks + 1 }
        Method(:hookCount, Ret: B32()) { Return hooks }
        Register(:port, Size: 1, Offset: 0) {
          Address { matched }
          Method(:read, Ret: B8()) { Return probe.readValue }
          Method(:write, data: B8()) { probe.writeValue(data) }
        }
        Register(:readonly, Size: 1, Offset: 1, Type: :ro) {
          Method(:read, Ret: B8()) { Return probe.readValue }
        }
      }
    RUBY
    headers = {}
    %w[Before After].each do |name|
      fe = checked(source.sub('DEVICE', name))
      packet = { latency: 7, width: 1, response: 'atomic', after_write: ['afterWrite'],
                 unmapped: name == 'Before' ? 'ignore' : 'panic',
                 read_response: name == 'Before' ? 'before_payload' : 'after_payload',
                 write_response: name == 'Before' ? 'before_dispatch' : 'after_dispatch' }
      headers[name] = Plod::Backend::Cpp.generate(fe.program, name, target(packet: packet))
    end
    compile_and_run(headers, <<~CPP)
      #include "gem5_stub.hh"
      namespace gem5 {
      struct Probe {
          PacketPtr packet = nullptr;
          bool seen = false, reject = false;
          uint8_t value = 0x42;
          uint8_t readValue() { seen = packet->response; return value; }
          void writeValue(uint8_t data) {
              seen = packet->response;
              if (reject) throw std::runtime_error("rejected");
              value = data;
          }
      };
      }
      #include "Before.hh"
      #include "After.hh"
      using namespace gem5;
      template <typename D> void exercise(bool before) {
          I8237Params params; params.pio_addr = 0x1000;
          D dev(params); Probe probe; dev.attach(&probe);
          Packet read(0x60, 1); probe.packet = &read;
          assert(dev.read(&read) == 7 && read.response && !probe.seen);
          assert(read.getLE<uint8_t>() == 0x42);
          Packet write(0x60, 1); write.setLE<uint8_t>(0xa3); probe.packet = &write;
          assert(dev.write(&write) == 7 && write.response && probe.seen == before);
          assert(probe.value == 0xa3 && dev.hookCount() == 1);
          probe.reject = true;
          Packet rejected(0x60, 1); probe.packet = &rejected;
          try { dev.write(&rejected); assert(false); } catch (const std::runtime_error&) {}
          assert(rejected.response == before && dev.hookCount() == 1);
          Packet forbidden(params.pio_addr + 1, 1); probe.packet = &forbidden;
          try { dev.write(&forbidden); assert(false); } catch (const std::runtime_error&) {}
          assert(forbidden.response == before && dev.hookCount() == 1);
          dev.relocate(0x117);
          Packet moved(0x117, 1); probe.packet = &moved; dev.read(&moved);
          assert(moved.getLE<uint8_t>() == 0xa3);
          Packet old(0x60, 1); old.setLE<uint8_t>(0xd7);
          if (before) {
              dev.read(&old); assert(old.response && old.getLE<uint8_t>() == 0xd7);
          } else {
              try { dev.read(&old); assert(false); } catch (const std::runtime_error&) {}
          }
      }
      int main() { exercise<Before>(true); exercise<After>(false); }
    CPP
  end

  def test_checkpoint_storage_arrays_maps_and_restore_hook_order
    fe = checked(<<~RUBY)
      AbstractMethod(:toString, value: Int(), Ret: String())
      Struct(:Snapshot) { Field(:words, Vector(B32())) }
      Device(:Saved) {
        Field(:data, B8(), 7)
        Field(:cp, B32(), 0x123)
        Field(:calls, B32(), 0)
        Field(:observed, B8(), 0)
        Field(:flags, Array(Bool(), 2))
        Field(:values, Vector(B32()))
        Field(:queue, Map(B64(), Snapshot()))
        Register(:words, Size: 1, Offset: 0, Seqn: 2) {
          Method(:write, data: B8()) { calls[] = calls + 1; Self[] = data }
        }
        Method(:initializeState) {
          flags.set(0, 1); flags.set(1, 0)
          values.push(11); values.push(12)
          Var(:record, Snapshot())
          record.words.push(31)
          queue.put(9, record)
          record.words.push(32)
          queue.put(3, record)
        }
        Method(:firstRestore) { observed[] = data }
        Method(:lastRestore) { observed[] = observed + data }
        Method(:getObserved, Ret: B8()) { Return observed }
        Method(:getCalls, Ret: B32()) { Return calls }
        Checkpoint {
          Scalar('alias', data)
          Scalar('cp', cp)
          Array('flags', flags)
          Array('values', values)
          Repeat(:i, 2) { Scalar(Literal('word') + toString(i), words.at(i)) }
          OrderedMap(queue, Count: 'count', CountType: B32(), Iter: :i, Key: :tick, Value: :record) {
            Scalar(Literal('tick') + toString(i), tick)
            Array(Literal('record') + toString(i), record.words)
          }
          AfterRestore(:firstRestore, :lastRestore)
        }
      }
    RUBY
    header = Plod::Backend::Cpp.generate(fe.program, :Saved, target(env: { 'toString' => 'std::to_string' }))
    compile_and_run({ Saved: header }, <<~CPP)
      #include "Saved.hh"
      using namespace gem5;
      int main() {
          I8237Params params; Saved dev(params); dev.initializeState();
          for (unsigned i = 0; i < 2; ++i) {
              Packet pkt(i, 1); pkt.setLE<uint8_t>(i + 20); dev.write(&pkt);
          }
          CheckpointOut cp; dev.serialize(cp);
          assert(cp.values.at("alias") == "7" && cp.values.at("tick0") == "3");
          assert(cp.values.at("tick1") == "9" && cp.values.at("word1") == "21");
          cp.values["alias"] = "43";
          Saved restored(params); CheckpointIn in(cp); restored.unserialize(in);
          assert(restored.getCalls() == 0 && restored.getObserved() == 86);
          CheckpointOut result; restored.serialize(result); assert(result.values == cp.values);
          for (unsigned i = 0; i < 2; ++i) {
              Packet pkt(i, 1); restored.read(&pkt); assert(pkt.getLE<uint8_t>() == i + 20);
          }
          // A second restore merges map entries and replaces matching keys.
          restored.unserialize(in);
          CheckpointOut again; restored.serialize(again); assert(again.values == cp.values);
      }
    CPP
  end
end

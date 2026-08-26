# frozen_string_literal: true

require_relative '../helper_plod'

class FrontendSmokeTests < Plod::TestCase
  DEVICES = File.expand_path('../../lib/Devices', __dir__)

  def load_device(name)
    fe = Plod::Frontend.load_file(File.join(DEVICES, "#{name}.rb"))
    assert_empty fe.diag.to_s, "unexpected diagnostics loading #{name}:\n#{fe.diag}"
    fe
  end

  def test_load_uart8250
    fe = load_device(:uart8250)
    device = fe.program.devices.first
    assert_equal :Uart8250, device.name
    assert_equal 12, device.registers.size
    assert_equal 8, device.methods.size
    assert_equal 6, device.fields.size
    assert_equal 3, device.consts.size
    assert_equal 1, device.enums.size
    assert_equal 2, device.lambdas.size

    rbr = device.registers.first
    assert_equal :rbr, rbr.name
    assert_equal :ro, rbr.access
    refute_nil rbr.enable_if
    read = rbr.methods.first
    assert_equal :read, read.name
    assert read.body.size > 3
    assert read.body.last.kind == :return

    iir = device.registers.find { |r| r.name == :iir }
    assert_equal %i[ip iid zero], iir.fields.map(&:name)
  end

  def test_load_clint
    fe = load_device(:clint)
    device = fe.program.devices.first
    assert_equal :Clint, device.name
    assert_equal 3, device.registers.size
    refute_nil device.ctor
    assert_equal 6, device.ctor.inits.size
    assert device.ctor.body.any? { |s| s.kind == :exprstmt }

    msip = device.registers.find { |r| r.name == :msip }
    assert_equal 0x1000, msip.seqn
    assert_equal 3, msip.methods.size

    do_reset = device.methods.find { |m| m.name == :doReset }
    for_stmt = do_reset.body.find { |s| s.kind == :for }
    refute_nil for_stmt
    assert_equal :cid, for_stmt.iter
    assert_equal 0x1000, for_stmt.to.value
  end

  def test_load_ns16550
    fe = load_device(:ns16550)
    fifo = fe.program.components.find { |c| c.name == :fifo8 }
    refute_nil fifo
    refute fifo.abstract
    assert_equal %i[init push pop is_empty], fifo.methods.map(&:name)
    assert_equal 3, fifo.fields.size

    device = fe.program.devices.first
    assert_equal :ns16550, device.name
    rbr = device.registers.first
    assert_equal :ro, rbr.access
    refute_nil rbr.enable_if
  end

  def test_if_else_structure
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      AbstractStruct(:E) {
        Method(:scheduled, ret: Bool())
      }

      Device(:D) {
        Method(:m, x: Int()) {
          If(x == 1) {
            x[] = 2
          }
          .Elseif(x == 3) {
            x[] = 4
          }
          .Else {
            x[] = 5
          }
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    method = fe.program.devices.first.methods.first
    assert_equal 1, method.body.size
    if_node = method.body.first
    assert_equal :if, if_node.kind
    assert_equal 1, if_node.then_body.size
    assert_equal 1, if_node.elsif_list.length
    assert_equal :binop, if_node.elsif_list[0][0].kind
    assert_equal 1, if_node.elsif_list[0][1].size
    assert_equal 1, if_node.else_body.size
  end

  def test_value_call_not_duplicated_as_statement
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      AbstractStruct(:Dev) {
        Method(:readData, ret: B8())
      }

      Device(:D) {
        AbstractField(:device, Ptr(Dev()))

        Method(:m, ret: B8()) {
          Let :data, B8(), device.readData()
          Return data
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    body = fe.program.devices.first.methods.first.body
    assert_equal 3, body.size
    assert_equal :vardecl, body[0].kind
    assert_equal :assign, body[1].kind
    assert_equal :mcall, body[1].value.kind
    assert_equal :return, body[2].kind
  end

  def test_void_call_stays_statement
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Method(:a) {
          Return()
        }

        Method(:b) {
          a()
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    body = fe.program.devices.first.methods.find { |m| m.name == :b }.body
    assert_equal 1, body.size
    assert_equal :exprstmt, body[0].kind
    assert_equal :call, body[0].expr.kind
  end

  def test_unknown_name_reports_location
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Method(:m) {
          nope()
        }
      }
    RUBY
    assert fe.diag.error?
    assert_match(/unknown name 'nope'/, fe.diag.to_s)
    assert_match(/test\.rb:3/, fe.diag.to_s)
  end

  def test_register_self_and_fields
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:r, size: 0x1, offset: 0x0) {
          field :lo, 0x0
          field :hi, 0x7

          Method(:write, data: B8()) {
            this[] = 0
            hi[] = 1
            lo[] = data
          }
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    body = fe.program.devices.first.registers.first.methods.first.body
    assert_equal 3, body.size
    assert_equal :self, body[0].target.kind
    assert_equal :regfield, body[1].target.kind
    assert_equal :register, body[1].target.reg.subject
    assert_equal :regfield, body[2].target.kind
    assert_equal :lo, body[2].target.field
  end

  def test_seq_register_elem_access
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:bank, size: 0x4, offset: 0x0, seqn: 0x100) {
          Method(:read, cid: Int(), ret: B32()) {
            Return bank.at(cid)
          }
          Method(:write, data: B32(), cid: Int()) {
            bank.set(cid, data)
          }
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    reg = fe.program.devices.first.registers.first
    read = reg.methods.find { |m| m.name == :read }
    assert_equal :getelem, read.body.first.value.kind
    write = reg.methods.find { |m| m.name == :write }
    assert_equal :setelem, write.body.first.kind
  end

  def test_program_ir_yaml_round_trip
    fe = load_device(:clint)
    h = fe.program.to_h
    restored = Plod::IR.from_h(Plod.yaml_load(Plod.yaml_dump(h)))
    assert_equal :Clint, restored.devices.first.name
    assert_equal 3, restored.devices.first.registers.size
    msip = restored.devices.first.registers.find { |r| r.name == :msip }
    assert_equal 0x1000, msip.seqn
    assert_equal 3, msip.methods.size
    write = msip.methods.find { |m| m.name == :write }
    assert_equal :setelem, write.body.first.kind
    raise_stmt = msip.methods.find { |m| m.name == :read }.body.first
    assert_equal :return, raise_stmt.kind
    assert_equal :getelem, raise_stmt.value.kind
  end
end

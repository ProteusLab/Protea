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
    assert_equal %i[write update], msip.methods.map(&:name)

    mtimecmp = device.registers.find { |r| r.name == :mtimecmp }
    assert_empty mtimecmp.methods

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
        Method(:scheduled, Ret: Bool())
      }

      Device(:D) {
        Method(:m, x: Int()) {
          If(x == 1) {
            x[] = 2
          }
          Elseif(x == 3) {
            x[] = 4
          }
          Else {
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
        Method(:readData, Ret: B8())
      }

      Device(:D) {
        AbstractField(:device, Ptr(Dev()))

        Method(:m, Ret: B8()) {
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
        Register(:r, Size: 0x1, Offset: 0x0) {
          Field :lo, 0x0
          Field :hi, 0x7

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
        Register(:bank, Size: 0x4, Offset: 0x0, Seqn: 0x100) {
          Method(:read, Ret: B32()) {
            Return Self
          }
          Method(:write, data: B32()) {
            Self[] = data
          }
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    reg = fe.program.devices.first.registers.first
    read = reg.methods.find { |m| m.name == :read }
    assert_equal :return, read.body.first.kind
    assert_equal :getelem, read.body.first.value.kind
    assert_equal :self, read.body.first.value.container.kind
    assert_equal :selfindex, read.body.first.value.index.kind
    assert_equal 32, read.body.first.value.type.size
    write = reg.methods.find { |m| m.name == :write }
    assert_equal :assign, write.body.first.kind
    assert_equal :getelem, write.body.first.target.kind
    assert_equal :self, write.body.first.target.container.kind
    assert_equal :selfindex, write.body.first.target.index.kind
  end

  def test_seq_register_explicit_index_still_works
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:bank, Size: 0x4, Offset: 0x0, Seqn: 0x100) {
          Method(:read, Ret: B32()) {
            Let :v, B32(), bank.at(cid)
            Return v
          }
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    reg = fe.program.devices.first.registers.first
    read = reg.methods.find { |m| m.name == :read }
    assign = read.body.find { |s| s.kind == :assign }
    assert_equal :getelem, assign.value.kind
    assert_equal :var, assign.value.container.kind
    assert_equal :bank, assign.value.container.name
  end

  def test_seq_register_sibling_call_forwards_index
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:bank, Size: 0x4, Offset: 0x0, Seqn: 0x100) {
          Method(:touch) {
            Self[] = 1
          }
          Method(:write, data: B32()) {
            Self[] = data
            touch()
          }
        }
      }
    RUBY
    assert_empty fe.diag.to_s
    reg = fe.program.devices.first.registers.first
    write = reg.methods.find { |m| m.name == :write }
    call = write.body.find { |s| s.kind == :exprstmt }
    assert_equal :mcall, call.expr.kind
    assert_equal 1, call.expr.args.size
    assert_equal :selfindex, call.expr.args.first.kind
  end

  def test_seq_register_rejects_explicit_cid_arg
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:bank, Size: 0x4, Offset: 0x0, Seqn: 0x100) {
          Method(:read, cid: Int(), Ret: B32()) {
            Return bank.at(cid)
          }
        }
      }
    RUBY
    assert fe.diag.error?
    assert_match(/'cid' is the implicit bank index/, fe.diag.to_s)
  end

  def test_self_outside_banked_register
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:r, Size: 0x1, Offset: 0x0) {
          Method(:write, data: B8()) {
            Self[] = data
          }
        }
      }
    RUBY
    assert fe.diag.error?
    assert_match(/Self is only available inside methods of a banked/, fe.diag.to_s)
  end

  def test_self_in_device_method
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Method(:m) {
          Self[] = 1
        }
      }
    RUBY
    assert fe.diag.error?
    assert_match(/Self is only available inside methods of a banked/, fe.diag.to_s)
  end

  def test_this_is_whole_bank_in_banked_register
    fe = Plod::Frontend.load_source(<<~RUBY, 'test.rb')
      Device(:D) {
        Register(:bank, Size: 0x4, Offset: 0x0, Seqn: 0x100) {
          Method(:write, data: B32()) {
            this[] = data
          }
        }
      }
    RUBY
    assert fe.diag.error?
    assert_match(/'this' is the whole bank/, fe.diag.to_s)
  end

  def test_program_ir_yaml_round_trip
    fe = load_device(:clint)
    h = fe.program.to_h
    restored = Plod::IR.from_h(Plod.yaml_load(Plod.yaml_dump(h)))
    assert_equal :Clint, restored.devices.first.name
    assert_equal 3, restored.devices.first.registers.size
    msip = restored.devices.first.registers.find { |r| r.name == :msip }
    assert_equal 0x1000, msip.seqn
    assert_equal %i[write update], msip.methods.map(&:name)
    write = msip.methods.find { |m| m.name == :write }
    assert_equal :assign, write.body.first.kind
    assert_equal :getelem, write.body.first.target.kind
    update = msip.methods.find { |m| m.name == :update }
    if_stmt = update.body.find { |s| s.kind == :if }
    assert_equal :getelem, if_stmt.cond.kind
    assert_equal :self, if_stmt.cond.container.kind
    assert_equal :selfindex, if_stmt.cond.index.kind
  end
end

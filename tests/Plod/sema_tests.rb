# frozen_string_literal: true

require_relative '../helper_plod'

class SemaPositiveTests < Plod::TestCase
  DEVICES = File.expand_path('../../lib/Devices', __dir__)

  def check_device(name)
    fe = Plod::Frontend.load_file(File.join(DEVICES, "#{name}.rb"))
    assert_empty fe.diag.to_s, "frontend diagnostics for #{name}:\n#{fe.diag}"
    diag = Plod::Checker.check(fe.program)
    errors = diag.errors.map(&:to_s).reject { |e| e.include?('overlap') }
    assert_empty errors, "checker errors for #{name}:\n#{errors.join("\n")}"
    diag
  end

  def test_uart8250_type_checks
    check_device(:uart8250)
  end

  def test_clint_type_checks
    diag = check_device(:clint)
    assert diag.to_s.include?('overlap'), 'expected the known mtime/mtimecmp overlap warning'
  end

  def test_ns16550_type_checks
    check_device(:ns16550)
  end
end

class SemaNegativeTests < Plod::TestCase
  def check(source)
    fe = Plod::Frontend.load_source(source, 'test.rb')
    diag = fe.diag
    Plod::Checker.check(fe.program).each { |d| diag << d }
    diag
  end

  def test_unknown_name_in_body
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:m) {
          mystery[] = 1
        }
      }
    RUBY
    assert diag.to_s.include?("unknown name 'mystery'")
  end

  def test_unknown_method_call
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:m) {
          nothere()
        }
      }
    RUBY
    assert diag.to_s.match?(/unknown (function|name) 'nothere'/)
  end

  def test_wrong_arg_count
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:helper, x: Int()) {
          x[] = 0
        }
        Method(:m) {
          helper(1, 2)
        }
      }
    RUBY
    assert diag.to_s.include?("wrong number of arguments for 'helper'")
  end

  def test_arg_type_mismatch
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:helper, x: Int()) {
          x[] = 0
        }
        Method(:m, s: String()) {
          helper(s)
        }
      }
    RUBY
    assert diag.to_s.include?("argument x of 'helper' expects int, got str")
  end

  def test_void_return_with_value
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:m) {
          Return 5
        }
      }
    RUBY
    assert diag.to_s.include?('void method m cannot return a value')
  end

  def test_return_type_mismatch
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:m, ret: B8()) {
          Return 1000
        }
      }
    RUBY
    assert diag.to_s.include?('does not fit in b8')
  end

  def test_ro_register_with_write
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:r, size: 0x1, offset: 0x0, type: :ro) {
          Method(:write, data: B8()) {
            this[] = data
          }
        }
      }
    RUBY
    assert diag.to_s.include?('read-only register D.r must not define a write method')
  end

  def test_wo_register_with_read
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:r, size: 0x1, offset: 0x0, type: :wo) {
          Method(:read, ret: B8()) {
            Return this
          }
        }
      }
    RUBY
    assert diag.to_s.include?('write-only register D.r must not define a read method')
  end

  def test_read_wrong_return_type
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:r, size: 0x2, offset: 0x0) {
          Method(:read, ret: B8()) {
            Return this
          }
        }
      }
    RUBY
    assert diag.to_s.include?('read method of r must return b16')
  end

  def test_field_exceeds_register_width
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:r, size: 0x1, offset: 0x0) {
          Field :big, [0x0, 0x8]
        }
      }
    RUBY
    assert diag.to_s.include?('exceeds register width')
  end

  def test_overlapping_fields
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:r, size: 0x2, offset: 0x0) {
          Field :a, [0x0, 0x4]
          Field :b, [0x3, 0x8]
        }
      }
    RUBY
    assert diag.to_s.include?('fields r.a and r.b overlap')
  end

  def test_const_value_overflow
    diag = check(<<~RUBY)
      Device(:D) {
        Const(:c, B8(), 300)
      }
    RUBY
    assert diag.to_s.include?('does not fit in b8')
  end

  def test_register_offset_overlap_warns_without_enable_if
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:a, size: 0x4, offset: 0x0) {}
        Register(:b, size: 0x4, offset: 0x2) {}
      }
    RUBY
    assert diag.to_s.include?('overlap; dispatch order decides')
  end

  def test_register_offset_overlap_silent_with_enable_if
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:lcr, size: 0x1, offset: 0x3) {
          Field :dlab, 0x7
        }
        Register(:a, size: 0x1, offset: 0x0) {
          enableIf { lcr.dlab == 0 }
        }
        Register(:b, size: 0x1, offset: 0x0) {
          enableIf { lcr.dlab == 1 }
        }
      }
    RUBY
    refute diag.to_s.include?('overlap')
  end

  def test_ro_and_wo_overlap_is_fine
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:a, size: 0x1, offset: 0x0, type: :ro) {}
        Register(:b, size: 0x1, offset: 0x0, type: :wo) {}
      }
    RUBY
    refute diag.to_s.include?('overlap')
  end

  def test_unknown_register_field_access
    diag = check(<<~RUBY)
      Device(:D) {
        Register(:r, size: 0x1, offset: 0x0) {
          Field :lo, 0x0
        }
        Method(:m) {
          r.hi[] = 1
        }
      }
    RUBY
    assert diag.to_s.include?("unknown field or method 'hi' for register r")
  end

  def test_unknown_enum_value
    diag = check(<<~RUBY)
      Device(:D) {
        Enum(:e) {
          A(0)
        }
        Method(:m) {
          x[] = e.B
        }
        AbstractField(:x, Int())
      }
    RUBY
    assert diag.to_s.include?("unknown enum value 'B'")
  end

  def test_comparison_type_mismatch
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:m, s: String()) {
          If(s == 1) {
            Return()
          }
        }
      }
    RUBY
    assert diag.to_s.include?('cannot compare str with int')
  end

  def test_struct_unknown_member
    diag = check(<<~RUBY)
      Struct(:S) {
        Method(:hello) {
          Return()
        }
        Field(:f, Int())
      }

      Device(:D) {
        Field(:s, S())
        Method(:m) {
          s.nope()
        }
      }
    RUBY
    assert diag.to_s.include?("unknown member 'nope' for struct S")
  end

  def test_abstract_struct_late_bound_is_warning_not_error
    diag = check(<<~RUBY)
      AbstractStruct(:Env) {}

      Device(:D) {
        AbstractField(:env, Ptr(Env()))
        Method(:m) {
          env.anything()
        }
      }
    RUBY
    assert diag.to_s.include?('late-bound')
    refute diag.error?
  end

  def test_init_of_unknown_field
    diag = check(<<~RUBY)
      Device(:D) {
        Constructor() {
          Init(:nope, 1)
        }
      }
    RUBY
    assert diag.to_s.include?("Init of unknown field 'nope'")
  end

  def test_duplicate_device_member_names
    diag = check(<<~RUBY)
      Device(:D) {
        Field(:x, Int())
        Const(:x, Int(), 1)
      }
    RUBY
    assert diag.to_s.include?("duplicate name 'x'")
  end

  def test_index_must_be_numeric
    diag = check(<<~RUBY)
      Device(:D) {
        Field(:arr, Array(B8(), 4))
        Method(:m, s: String()) {
          arr[s][] = 1
        }
      }
    RUBY
    assert diag.to_s.include?('index must be numeric, got str')
  end

  def test_not_operator_requires_bits
    diag = check(<<~RUBY)
      Device(:D) {
        Method(:m, s: String()) {
          Return ~s
        }
      }
    RUBY
    assert diag.to_s.include?("'~' requires a bit value")
  end
end

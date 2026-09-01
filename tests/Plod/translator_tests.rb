# frozen_string_literal: true

require_relative '../helper_plod'

class TranslatorTests < Plod::TestCase
  PLD = File.expand_path('../../lib/Devices/uart8250.pld', __dir__)
  GOLDEN = File.expand_path('../../tests/golden/Uart8250.hh', __dir__)

  def test_lexer_hex_and_decimal_keep_spelling
    tokens = Plod::Pld::Lexer.tokenize('0x0A 10 0x1', 't.pld').first(3)
    assert_equal 0x0A, tokens[0][1][:value]
    assert_equal '0x0A', tokens[0][1][:raw]
    assert_equal 10, tokens[1][1][:value]
    assert_equal '10', tokens[1][1][:raw]
  end

  def test_lexer_comments_and_strings
    src = <<~PLD
      // line comment
      # other comment style
      "TX" "a\\"b"
    PLD
    tokens = Plod::Pld::Lexer.tokenize(src, 't.pld')
    strings = tokens.select { |t| t[0] == :string }
    assert_equal 'TX', strings[0][1][:value]
    assert_equal 'a"b', strings[1][1][:value]
  end

  def test_lexer_operators
    tokens = Plod::Pld::Lexer.tokenize('a |= b <<= c == d && e', 't.pld')
    ops = tokens.filter_map { |t| t[0] == :punct ? t[1] : nil }
    assert_equal %w[|= <<= == &&], ops
  end

  def test_translate_minimal_device
    src = <<~PLD
      abstract struct E {
          bool scheduled();
      }

      device D {
          const b8 ready = 0x1;

          register ctrl: size(0x1), offset(0x0), type(rw) {
              field en(0x0)
              field res(0x1, 0x3)

              b8 read() {
                  self = 0;
                  if (en) {
                      self |= 0x80;
                  }
                  return self;
              }
          }
      }
    PLD
    ruby = Plod::Pld::Translator.translate(src, 't.pld')
    assert_includes ruby, 'AbstractStruct(:E) do'
    assert_includes ruby, 'Method(:scheduled, ret: Bool())'
    assert_includes ruby, 'Const(:ready, B8(), 0x1)'
    assert_includes ruby, 'Register(:ctrl, size: 0x1, offset: 0x0, type: :rw)'
    assert_includes ruby, 'Field :en, 0x0'
    assert_includes ruby, 'Field :res, [0x1, 0x3]'
    assert_includes ruby, 'this[] = 0'
    assert_includes ruby, 'this[] = this | 0x80'
    assert_includes ruby, 'Return this'

    fe = Plod::Frontend.load_source(ruby, 't.rb')
    assert_empty fe.diag.to_s, "generated source must check clean:\n#{ruby}\n#{fe.diag}"
  end

  def test_translate_expressions
    src = <<~PLD
      abstract struct P {
          void ping();
      }

      device D {
          abstract int status;
          abstract P* platform;

          enum Ids {
              A: 0,
              B: 1
          }

          void m(int x) {
              int y = x * 2;
              bool z = static_cast<bool>(status);
              platform.ping();
              status &= ~(1 << 3);
              y = x + (1 | 2);
          }

          void k(Ids id) {
              status = Ids.A;
              status = id.B;
          }
      }
    PLD
    ruby = Plod::Pld::Translator.translate(src, 't.pld')
    assert_includes ruby, 'Let :y, Int(), x * 2'
    assert_includes ruby, 'Cast(Bool(), status)'
    assert_includes ruby, 'platform.ping'
    assert_includes ruby, 'status[] = status & ~(1 << 3)'
    assert_includes ruby, 'ids.A'
    assert_includes ruby, 'id.B'
    assert_includes ruby, 'Enum(:ids)'
  end

  def test_translate_else_chain
    src = <<~PLD
      device D {
          void m(int x) {
              if (x == 1) {
                  x = 2
              } else if (x == 3) {
                  x = 4
              } else {
                  x = 5
              }
          }
      }
    PLD
    ruby = Plod::Pld::Translator.translate(src, 't.pld')
    assert_includes ruby, 'If(x == 1) do'
    assert_includes ruby, 'Elseif(x == 3) do'
    assert_includes ruby, 'Else do'

    fe = Plod::Frontend.load_source(ruby, 't.rb')
    assert_empty fe.diag.to_s
    method = fe.program.devices.first.methods.first
    assert_equal 1, method.body.size
    if_node = method.body.first
    assert_equal 1, if_node.elsif_list.length
    refute_nil if_node.else_body
  end

  def test_translate_lambda_field_init
    src = <<~PLD
      abstract struct W {
          void process();
      }

      device D {
          W ev = W([]{ ping(); }, "TX");
      }
    PLD
    ruby = Plod::Pld::Translator.translate(src, 't.pld')
    assert_includes ruby, "Field(:ev, W(), Lambda { ping }, 'TX')"
  end

  def test_translate_uart8250_end_to_end
    ruby = Plod::Pld::Translator.translate_file(PLD)
    fe = Plod::Frontend.load_source(ruby, 'uart8250.rb')
    assert_empty fe.diag.to_s, "translated uart8250 must check clean:\n#{fe.diag}"

    diag = Plod::Checker.check(fe.program)
    assert_empty diag.to_s, "translated uart8250 must type-check:\n#{diag}"

    target = Plod::Backend::Target::Registry.new([File.expand_path('../../targets', __dir__)]).for_device(:Uart8250)
    refute_nil target
    header = Plod::Backend::Cpp.generate(fe.program, :Uart8250, target)
    assert_equal File.read(GOLDEN), header, 'translated uart8250 must build the byte-identical golden header'
  end

  def test_parser_reports_location_on_error
    error = assert_raises(Plod::Error) do
      Plod::Pld::Parser.parse('device D {', 't.pld')
    end
    assert_match(/t\.pld:1/, error.message)
  end

  def test_parser_rejects_unknown_type
    error = assert_raises(Plod::Error) do
      Plod::Pld::Parser.parse('device D { void m(Undefined x) {} }', 't.pld')
    end
    assert_match(/not a known type/, error.message)
  end
end

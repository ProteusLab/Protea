# lira/ir_ops.rb
require_relative 'arch'

module Lira
  class TypeCheckError < StandardError; end

  module BaseOp
    NOT = :not
    NEG = :neg
    ADD = :add
    SUB = :sub
    MUL = :mul
    AND = :and
    ORR = :orr
    XOR = :xor
    LSL = :lsl
    LSR = :lsr
    ASR = :asr
    EQ = :eq
    NE = :ne
    SLT = :slt
    SLE = :sle
    SGT = :sgt
    SGE = :sge
    ULT = :ult
    ULE = :ule
    UGT = :ugt
    UGE = :uge
    DIV_U = :div_u
    DIV_S = :div_s
    REM_U = :rem_u
    REM_S = :rem_s
    ROR = :ror
    ROL = :rol
    ADD_OVERFLOW = :add_overflow
    SUB_OVERFLOW = :sub_overflow
    SELECT = :select
    EXTEND_SIGN = :extend_sign
    EXTEND_ZERO = :extend_zero
    EXTRACT_LOW = :extract_low
    POPCNT = :popcnt
    CTZ = :ctz
    CLZ = :clz
    REVERSE = :reverse
  end

  class UnaryOp < Operation
    def initialize(out_bits, semantic_base, name: nil)
      name ||= "#{semantic_base}_#{out_bits}"
      super(name, [], [out_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'input width must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'output width must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'input != output' unless inputs[0] == outputs[0]
    end
  end

  class BinaryOp < Operation
    def initialize(bits, semantic_base, name: nil)
      name ||= "#{semantic_base}_#{bits}"
      super(name, [], [bits, bits], [bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'input[0] must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'input[1] must be positive' unless inputs[1] > 0
      raise TypeCheckError, 'output must be positive' unless outputs[0] > 0
      unless inputs[0] == inputs[1] && inputs[0] == outputs[0]
        raise TypeCheckError, "mismatched widths: #{inputs} -> #{outputs[0]}"
      end
    end
  end

  class CmpOp < Operation
    def initialize(bits, semantic_base, out_bits = 1, name: nil)
      name ||= "#{semantic_base}_#{bits}"
      super(name, [], [bits, bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'input[0] must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'input[1] must be positive' unless inputs[1] > 0
      raise TypeCheckError, 'output must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'input widths differ' unless inputs[0] == inputs[1]
    end
  end

  class TernaryOp < Operation
    def initialize(bits, semantic_base, name: nil)
      name ||= "#{semantic_base}_#{bits}"
      super(name, [], [bits, bits, bits], [bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'input[0] must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'input[1] must be positive' unless inputs[1] > 0
      raise TypeCheckError, 'input[2] must be positive' unless inputs[2] > 0
      raise TypeCheckError, 'output must be positive' unless outputs[0] > 0
      unless inputs[0] == inputs[1] && inputs[0] == inputs[2] && inputs[0] == outputs[0]
        raise TypeCheckError, "mismatched widths: #{inputs} -> #{outputs[0]}"
      end
    end
  end

  class ExtendOp < Operation
    def initialize(in_bits, out_bits, semantic_base, name: nil)
      name ||= "#{semantic_base}_#{in_bits}_to_#{out_bits}"
      super(name, [], [in_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'input width must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'output width must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'input >= output' unless inputs[0] < outputs[0]
    end
  end

  class ExtractLowOp < Operation
    def initialize(in_bits, out_bits, semantic_base, name: nil)
      name ||= "#{semantic_base}_#{in_bits}_to_#{out_bits}"
      super(name, [], [in_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'input width must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'output width must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'output > input' unless outputs[0] <= inputs[0]
    end
  end

  class Not < UnaryOp
    def initialize(bits); super(bits, BaseOp::NOT); end
  end

  class Neg < UnaryOp
    def initialize(bits); super(bits, BaseOp::NEG); end
  end

  class Add < BinaryOp
    def initialize(bits); super(bits, BaseOp::ADD); end
  end

  class Sub < BinaryOp
    def initialize(bits); super(bits, BaseOp::SUB); end
  end

  class Mul < BinaryOp
    def initialize(bits); super(bits, BaseOp::MUL); end
  end

  class And < BinaryOp
    def initialize(bits); super(bits, BaseOp::AND); end
  end

  class Orr < BinaryOp
    def initialize(bits); super(bits, BaseOp::ORR); end
  end

  class Xor < BinaryOp
    def initialize(bits); super(bits, BaseOp::XOR); end
  end

  class Lsl < BinaryOp
    def initialize(bits); super(bits, BaseOp::LSL); end
  end

  class Lsr < BinaryOp
    def initialize(bits); super(bits, BaseOp::LSR); end
  end

  class Asr < BinaryOp
    def initialize(bits); super(bits, BaseOp::ASR); end
  end

  class Eq < CmpOp
    def initialize(bits); super(bits, BaseOp::EQ); end
  end

  class Ne < CmpOp
    def initialize(bits); super(bits, BaseOp::NE); end
  end

  class Slt < CmpOp
    def initialize(bits); super(bits, BaseOp::SLT); end
  end

  class Sle < CmpOp
    def initialize(bits); super(bits, BaseOp::SLE); end
  end

  class Sgt < CmpOp
    def initialize(bits); super(bits, BaseOp::SGT); end
  end

  class Sge < CmpOp
    def initialize(bits); super(bits, BaseOp::SGE); end
  end

  class Ult < CmpOp
    def initialize(bits); super(bits, BaseOp::ULT); end
  end

  class Ule < CmpOp
    def initialize(bits); super(bits, BaseOp::ULE); end
  end

  class Ugt < CmpOp
    def initialize(bits); super(bits, BaseOp::UGT); end
  end

  class Uge < CmpOp
    def initialize(bits); super(bits, BaseOp::UGE); end
  end

  class ExtendSign < ExtendOp
    def initialize(in_bits, out_bits); super(in_bits, out_bits, BaseOp::EXTEND_SIGN); end
  end

  class ExtendZero < ExtendOp
    def initialize(in_bits, out_bits); super(in_bits, out_bits, BaseOp::EXTEND_ZERO); end
  end

  class ExtractLow < ExtractLowOp
    def initialize(in_bits, out_bits); super(in_bits, out_bits, BaseOp::EXTRACT_LOW); end
  end

  class Popcnt < UnaryOp
    def initialize(bits); super(bits, BaseOp::POPCNT); end
  end

  class Ctz < UnaryOp
    def initialize(bits); super(bits, BaseOp::CTZ); end
  end

  class Clz < UnaryOp
    def initialize(bits); super(bits, BaseOp::CLZ); end
  end

  class Reverse < UnaryOp
    def initialize(bits); super(bits, BaseOp::REVERSE); end
  end

  class RemU < BinaryOp
    def initialize(bits); super(bits, BaseOp::REM_U); end
  end

  class RemS < BinaryOp
    def initialize(bits); super(bits, BaseOp::REM_S); end
  end

  class Ror < BinaryOp
    def initialize(bits); super(bits, BaseOp::ROR); end
  end

  class Rol < BinaryOp
    def initialize(bits); super(bits, BaseOp::ROL); end
  end

  class AddOverflow < CmpOp
    def initialize(bits); super(bits, BaseOp::ADD_OVERFLOW, out_bits: 1); end
  end

  class SubOverflow < CmpOp
    def initialize(bits); super(bits, BaseOp::SUB_OVERFLOW, out_bits: 1); end
  end

  class DivU < TernaryOp
    def initialize(bits); super(bits, BaseOp::DIV_U); end
  end

  class DivS < TernaryOp
    def initialize(bits); super(bits, BaseOp::DIV_S); end
  end

  class Select < Operation
    def initialize(bits)
      name = "select_#{bits}"
      super(name, [], [1, bits, bits], [bits],
            semantic_base: BaseOp::SELECT, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def check_signature
      raise TypeCheckError, 'true/false branches mismatch' unless inputs[1] == inputs[2] && inputs[1] == outputs[0]
    end
  end
end

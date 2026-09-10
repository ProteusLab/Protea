# lira/ir_ops.rb
require_relative 'arch'

module Lira
  class TypeCheckError < StandardError; end

  module BaseOp
    NOT = "not"
    NEG = "neg"
    ADD = "add"
    SUB = "sub"
    MUL = "mul"
    AND = "and"
    ORR = "orr"
    XOR = "xor"
    LSL = "lsl"
    LSR = "lsr"
    ASR = "asr"
    EQ = "eq"
    NE = "ne"
    SLT = "slt"
    SLE = "sle"
    SGT = "sgt"
    SGE = "sge"
    ULT = "ult"
    ULE = "ule"
    UGT = "ugt"
    UGE = "uge"
    DIV_U = "div_u"
    DIV_S = "div_s"
    REM_U = "rem_u"
    REM_S = "rem_s"
    ROR = "ror"
    ROL = "rol"
    ADD_OVERFLOW = "add_overflow"
    SUB_OVERFLOW = "sub_overflow"
    SELECT = "select"
    EXTEND_SIGN = "extend_sign"
    EXTEND_ZERO = "extend_zero"
    EXTRACT_LOW = "extract_low"
    POPCNT = "popcnt"
    CTZ = "ctz"
    CLZ = "clz"
    REVERSE = "reverse"
  end

  class UnaryOp < Operation
    def initialize(out_bits)
      semantic_base = self.class.op_base
      super("#{semantic_base}_#{out_bits}", [], [out_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[0]).restore_from(op)
    end

    def check_signature
      raise TypeCheckError, 'input width must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'output width must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'input != output' unless inputs[0] == outputs[0]
    end
  end

  class BinaryOp < Operation
    def initialize(bits)
      semantic_base = self.class.op_base
      super("#{semantic_base}_#{bits}", [], [bits, bits], [bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[0]).restore_from(op)
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
    def initialize(bits)
      semantic_base = self.class.op_base
      super("#{semantic_base}_#{bits}", [], [bits, bits], [1],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[0]).restore_from(op)
    end

    def check_signature
      raise TypeCheckError, 'input[0] must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'input[1] must be positive' unless inputs[1] > 0
      raise TypeCheckError, 'input widths differ' unless inputs[0] == inputs[1]
    end
  end

  class TernaryOp < Operation
    def initialize(bits)
      semantic_base = self.class.op_base
      super("#{semantic_base}_#{bits}", [], [bits, bits, bits], [bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[0]).restore_from(op)
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
    def initialize(in_bits, out_bits)
      semantic_base = self.class.op_base
      super("#{semantic_base}_#{in_bits}_to_#{out_bits}", [], [in_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[0], op.outputs[0]).restore_from(op)
    end

    def check_signature
      raise TypeCheckError, 'input width must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'output width must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'input >= output' unless inputs[0] < outputs[0]
    end
  end

  class ExtractLowOp < Operation
    def initialize(in_bits, out_bits)
      semantic_base = self.class.op_base
      super("#{semantic_base}_#{in_bits}_to_#{out_bits}", [], [in_bits], [out_bits],
            semantic_base: semantic_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[0], op.outputs[0]).restore_from(op)
    end

    def check_signature
      raise TypeCheckError, 'input width must be positive' unless inputs[0] > 0
      raise TypeCheckError, 'output width must be positive' unless outputs[0] > 0
      raise TypeCheckError, 'output > input' unless outputs[0] <= inputs[0]
    end
  end

  class Not < UnaryOp
    self.op_base = BaseOp::NOT

    def initialize(bits); super(bits); end
  end

  class Neg < UnaryOp
    self.op_base = BaseOp::NEG

    def initialize(bits); super(bits); end
  end

  class Add < BinaryOp
    self.op_base = BaseOp::ADD

    def initialize(bits); super(bits); end
  end

  class Sub < BinaryOp
    self.op_base = BaseOp::SUB

    def initialize(bits); super(bits); end
  end

  class Mul < BinaryOp
    self.op_base = BaseOp::MUL

    def initialize(bits); super(bits); end
  end

  class And < BinaryOp
    self.op_base = BaseOp::AND

    def initialize(bits); super(bits); end
  end

  class Orr < BinaryOp
    self.op_base = BaseOp::ORR

    def initialize(bits); super(bits); end
  end

  class Xor < BinaryOp
    self.op_base = BaseOp::XOR

    def initialize(bits); super(bits); end
  end

  class Lsl < BinaryOp
    self.op_base = BaseOp::LSL

    def initialize(bits); super(bits); end
  end

  class Lsr < BinaryOp
    self.op_base = BaseOp::LSR

    def initialize(bits); super(bits); end
  end

  class Asr < BinaryOp
    self.op_base = BaseOp::ASR

    def initialize(bits); super(bits); end
  end

  class Eq < CmpOp
    self.op_base = BaseOp::EQ

    def initialize(bits); super(bits); end
  end

  class Ne < CmpOp
    self.op_base = BaseOp::NE

    def initialize(bits); super(bits); end
  end

  class Slt < CmpOp
    self.op_base = BaseOp::SLT

    def initialize(bits); super(bits); end
  end

  class Sle < CmpOp
    self.op_base = BaseOp::SLE

    def initialize(bits); super(bits); end
  end

  class Sgt < CmpOp
    self.op_base = BaseOp::SGT

    def initialize(bits); super(bits); end
  end

  class Sge < CmpOp
    self.op_base = BaseOp::SGE

    def initialize(bits); super(bits); end
  end

  class Ult < CmpOp
    self.op_base = BaseOp::ULT

    def initialize(bits); super(bits); end
  end

  class Ule < CmpOp
    self.op_base = BaseOp::ULE

    def initialize(bits); super(bits); end
  end

  class Ugt < CmpOp
    self.op_base = BaseOp::UGT

    def initialize(bits); super(bits); end
  end

  class Uge < CmpOp
    self.op_base = BaseOp::UGE

    def initialize(bits); super(bits); end
  end

  class ExtendSign < ExtendOp
    self.op_base = BaseOp::EXTEND_SIGN

    def initialize(in_bits, out_bits); super(in_bits, out_bits); end
  end

  class ExtendZero < ExtendOp
    self.op_base = BaseOp::EXTEND_ZERO

    def initialize(in_bits, out_bits); super(in_bits, out_bits); end
  end

  class ExtractLow < ExtractLowOp
    self.op_base = BaseOp::EXTRACT_LOW

    def initialize(in_bits, out_bits); super(in_bits, out_bits); end
  end

  class Popcnt < UnaryOp
    self.op_base = BaseOp::POPCNT

    def initialize(bits); super(bits); end
  end

  class Ctz < UnaryOp
    self.op_base = BaseOp::CTZ

    def initialize(bits); super(bits); end
  end

  class Clz < UnaryOp
    self.op_base = BaseOp::CLZ

    def initialize(bits); super(bits); end
  end

  class Reverse < UnaryOp
    self.op_base = BaseOp::REVERSE

    def initialize(bits); super(bits); end
  end

  class RemU < BinaryOp
    self.op_base = BaseOp::REM_U

    def initialize(bits); super(bits); end
  end

  class RemS < BinaryOp
    self.op_base = BaseOp::REM_S

    def initialize(bits); super(bits); end
  end

  class Ror < BinaryOp
    self.op_base = BaseOp::ROR

    def initialize(bits); super(bits); end
  end

  class Rol < BinaryOp
    self.op_base = BaseOp::ROL

    def initialize(bits); super(bits); end
  end

  class AddOverflow < CmpOp
    self.op_base = BaseOp::ADD_OVERFLOW

    def initialize(bits); super(bits); end
  end

  class SubOverflow < CmpOp
    self.op_base = BaseOp::SUB_OVERFLOW

    def initialize(bits); super(bits); end
  end

  class DivU < TernaryOp
    self.op_base = BaseOp::DIV_U

    def initialize(bits); super(bits); end
  end

  class DivS < TernaryOp
    self.op_base = BaseOp::DIV_S

    def initialize(bits); super(bits); end
  end

  class Select < Operation
    self.op_base = BaseOp::SELECT

    def initialize(bits)
      name = "select_#{bits}"
      super(name, [], [1, bits, bits], [bits],
            semantic_base: self.class.op_base, semantic_func: nil, semantic_table: nil)
      check_signature
    end

    def self.from_operation(op)
      new(op.inputs[1]).restore_from(op)
    end

    def check_signature
      raise TypeCheckError, 'true/false branches mismatch' unless inputs[1] == inputs[2] && inputs[1] == outputs[0]
    end
  end

  def self.from_operation(op)
    sb = op.semantic_base
    return op if sb.nil?

    cls = Operation.typed_ops[sb]
    raise "Unexpected operation with semantic #{sb}" if cls.nil?

    cls.from_operation(op)
  end
end

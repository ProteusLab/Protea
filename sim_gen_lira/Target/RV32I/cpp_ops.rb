# sim_gen_lira/Target/RISC-V/cpp_ops.rb
# RISC-V ISA-specific C++ codegen overrides.
# Shift operations mask the shift amount to log2(XLEN) bits (RISC-V spec §2.4).

require_relative '../../cpp_ops'

module Lira
  module CppCodegen
    private

    def cpp_type_bits
      [1, 8, 16, 32, 64, 128].find { |s| s >= inputs[0] } || 128
    end
  end

  class Lsl
    def cpp_body
      mask = cpp_type_bits - 1
      "b &= #{mask}; return a << b;"
    end
  end

  class Lsr
    def cpp_body
      mask = cpp_type_bits - 1
      "b &= #{mask}; return a >> b;"
    end
  end

  class Asr
    def cpp_body
      t = Utility::HelperCpp.gen_type(inputs[0])
      ts = Utility::HelperCpp.gen_type(inputs[0], true)
      mask = cpp_type_bits - 1
      "b &= #{mask}; return (#{t})((#{ts})a >> b);"
    end
  end

  class Operation
    alias_method :cpp_body_base, :cpp_body

    def cpp_body
      case semantic_base
      when BaseOp::LSL          then "b &= #{cpp_type_bits - 1}; return a << b;"
      when BaseOp::LSR          then "b &= #{cpp_type_bits - 1}; return a >> b;"
      when BaseOp::ASR
        t = Utility::HelperCpp.gen_type(inputs[0])
        ts = Utility::HelperCpp.gen_type(inputs[0], true)
        "b &= #{cpp_type_bits - 1}; return (#{t})((#{ts})a >> b);"
      else
        cpp_body_base
      end
    end
  end
end

require_relative '../lib/lira/ir_ops'
require_relative '../lib/Utility/helper_cpp'

module Lira
  module CppCodegen
    def cpp_func_name
      name
    end

    def cpp_return_type
      Utility::HelperCpp.gen_type(outputs[0])
    end

    def cpp_params
      inputs.map.with_index { |w, i|
        "#{Utility::HelperCpp.gen_type(w)} #{('a'.ord + i).chr}"
      }.join(', ')
    end

    def cpp_body
      case semantic_base
      when BaseOp::NOT          then 'return ~a;'
      when BaseOp::NEG          then 'return -a;'
      when BaseOp::ADD          then 'return a + b;'
      when BaseOp::SUB          then 'return a - b;'
      when BaseOp::MUL          then 'return a * b;'
      when BaseOp::AND          then 'return a & b;'
      when BaseOp::ORR          then 'return a | b;'
      when BaseOp::XOR          then 'return a ^ b;'
      when BaseOp::EQ           then 'return (a == b) ? 1 : 0;'
      when BaseOp::NE           then 'return (a != b) ? 1 : 0;'
      when BaseOp::SLT          then signed_cmp('<')
      when BaseOp::SLE          then signed_cmp('<=')
      when BaseOp::SGT          then signed_cmp('>')
      when BaseOp::SGE          then signed_cmp('>=')
      when BaseOp::ULT          then 'return (a < b) ? 1 : 0;'
      when BaseOp::ULE          then 'return (a <= b) ? 1 : 0;'
      when BaseOp::UGT          then 'return (a > b) ? 1 : 0;'
      when BaseOp::UGE          then 'return (a >= b) ? 1 : 0;'
      when BaseOp::LSL          then "return a << b;"
      when BaseOp::LSR          then "return a >> b;"
      when BaseOp::ASR          then asr_body
      when BaseOp::DIV_U        then 'return (b == 0) ? c : a / b;'
      when BaseOp::DIV_S        then div_s_body
      when BaseOp::SELECT       then 'return a ? b : c;'
      when BaseOp::REM_U        then rem_u_body
      when BaseOp::REM_S        then rem_s_body
      when BaseOp::EXTEND_SIGN  then extend_sign_body
      when BaseOp::EXTEND_ZERO  then extend_zero_body
      when BaseOp::EXTRACT_LOW  then extract_low_body
      else raise "No cpp_body defined for operation #{semantic_base}"
      end
    end

    def to_cpp
      body_indented = cpp_body.lines.map { |l| "  #{l.chomp}" }.join("\n")
      <<~CPP
      static inline #{cpp_return_type} #{cpp_func_name}(#{cpp_params}) {
      #{body_indented}
      }
      CPP
    end

    private

    def signed_cmp(op)
      t = Utility::HelperCpp.gen_type(inputs[0], true)
      "return ((#{t})a #{op} (#{t})b) ? 1 : 0;"
    end

    def asr_body
      t = Utility::HelperCpp.gen_type(inputs[0])
      ts = Utility::HelperCpp.gen_type(inputs[0], true)
      "return (#{t})((#{ts})a >> b);"
    end

    def div_s_body
      t = Utility::HelperCpp.gen_type(inputs[0])
      ts = Utility::HelperCpp.gen_type(inputs[0], true)
      "return (b == 0) ? c : (#{t})((#{ts})a / (#{ts})b);"
    end

    def rem_u_body
      <<~CPP
      if (b == 0) return a;
      return a % b;
      CPP
    end

    def rem_s_body
      t = Utility::HelperCpp.gen_type(inputs[0])
      ts = Utility::HelperCpp.gen_type(inputs[0], true)
      <<~CPP
      if (b == 0) return a;
      #{ts} res = (#{ts})a % (#{ts})b;
      return (#{t})res;
      CPP
    end

    def extend_sign_body
      return 'return a;' if inputs[0] == 1
      t = Utility::HelperCpp.gen_type(outputs[0])
      <<~CPP
      #{t} val = a & (((#{t})1 << #{inputs[0]}) - 1);
      #{t} sign = (val >> (#{inputs[0]} - 1)) & 1;
      if (sign)
        return val | (~(((#{t})1 << #{inputs[0]}) - 1));
      else
        return val;
      CPP
    end

    def extend_zero_body
      t = Utility::HelperCpp.gen_type(outputs[0])
      "return a & (((#{t})1 << #{inputs[0]}) - 1);"
    end

    def extract_low_body
      t = Utility::HelperCpp.gen_type(inputs[0])
      "return a & (((#{t})1 << #{outputs[0]}) - 1);"
    end
  end

  class Operation;    include CppCodegen; end
  class UnaryOp;      include CppCodegen; end
  class BinaryOp;     include CppCodegen; end
  class CmpOp;        include CppCodegen; end
  class TernaryOp;    include CppCodegen; end
  class ExtendOp;     include CppCodegen; end
  class ExtractLowOp; include CppCodegen; end
  class Select;       include CppCodegen; end

  class CmpOp
    def cpp_return_type
      Utility::HelperCpp.gen_type(1)
    end
  end

  class ExtendOp
    def cpp_return_type
      Utility::HelperCpp.gen_type(outputs[0])
    end

    def cpp_params
      "#{Utility::HelperCpp.gen_type(inputs[0])} a"
    end
  end

  class ExtractLowOp
    def cpp_return_type
      Utility::HelperCpp.gen_type(outputs[0])
    end

    def cpp_params
      "#{Utility::HelperCpp.gen_type(inputs[0])} a"
    end
  end

  class Select
    def cpp_params
      "uint8_t cond, #{Utility::HelperCpp.gen_type(inputs[1])} a, #{Utility::HelperCpp.gen_type(inputs[1])} b"
    end
  end

  class ExtendSign
    def cpp_body
      return 'return a;' if inputs[0] == 1
      t = Utility::HelperCpp.gen_type(outputs[0])
      <<~CPP
      #{t} val = a & (((#{t})1 << #{inputs[0]}) - 1);
      #{t} sign = (val >> (#{inputs[0]} - 1)) & 1;
      if (sign)
        return val | (~(((#{t})1 << #{inputs[0]}) - 1));
      else
        return val;
      CPP
    end
  end

  class ExtendZero
    def cpp_body
      t = Utility::HelperCpp.gen_type(outputs[0])
      "return a & (((#{t})1 << #{inputs[0]}) - 1);"
    end
  end

  class ExtractLow
    def cpp_body
      t = Utility::HelperCpp.gen_type(inputs[0])
      "return a & (((#{t})1 << #{outputs[0]}) - 1);"
    end
  end

  class Popcnt
    def cpp_body
      case inputs[0]
      when 8
        <<~CPP
        unsigned cnt = 0;
        while (a) { cnt += a & 1; a >>= 1; }
        return cnt;
        CPP
      when 16
        'return popcnt_8(a & 0xFF) + popcnt_8((a >> 8) & 0xFF);'
      when 32
        'return popcnt_16(a & 0xFFFF) + popcnt_16((a >> 16) & 0xFFFF);'
      when 64
        'return popcnt_32(a & 0xFFFFFFFF) + popcnt_32((a >> 32) & 0xFFFFFFFF);'
      when 128
        'return popcnt_64((uint64_t)a) + popcnt_64((uint64_t)(a >> 64));'
      else raise 'Unsupported popcnt size'
      end
    end
  end

  class Ctz
    def cpp_body
      bits = inputs[0]
      if bits == 128
        <<~CPP
        if (a == 0) return 128;
        uint64_t lo = (uint64_t)a;
        if (lo) return ctz_64(lo);
        else return 64 + ctz_64((uint64_t)(a >> 64));
        CPP
      else
        <<~CPP
        if (a == 0) return #{bits};
        unsigned n = 0;
        while ((a & 1) == 0) { a >>= 1; n++; }
        return n;
        CPP
      end
    end
  end

  class Clz
    def cpp_body
      bits = inputs[0]
      if bits == 128
        <<~CPP
        if (a == 0) return 128;
        uint64_t hi = (uint64_t)(a >> 64);
        if (hi) return clz_64(hi);
        else return 64 + clz_64((uint64_t)a);
        CPP
      else
        mask = case bits
               when 8  then '0x80'
               when 16 then '0x8000'
               when 32 then '0x80000000'
               when 64 then '0x8000000000000000ULL'
               end
        <<~CPP
        if (a == 0) return #{bits};
        unsigned n = 0;
        while ((a & #{mask}) == 0) { a <<= 1; n++; }
        return n;
        CPP
      end
    end
  end

  class Reverse
    def cpp_body
      case inputs[0]
      when 8
        <<~CPP
        a = ((a & 0xF0) >> 4) | ((a & 0x0F) << 4);
        a = ((a & 0xCC) >> 2) | ((a & 0x33) << 2);
        a = ((a & 0xAA) >> 1) | ((a & 0x55) << 1);
        return a;
        CPP
      when 16
        <<~CPP
        a = ((a & 0xFF00) >> 8) | ((a & 0x00FF) << 8);
        a = ((a & 0xF0F0) >> 4) | ((a & 0x0F0F) << 4);
        a = ((a & 0xCCCC) >> 2) | ((a & 0x3333) << 2);
        a = ((a & 0xAAAA) >> 1) | ((a & 0x5555) << 1);
        return a;
        CPP
      when 32
        <<~CPP
        a = ((a & 0xFFFF0000) >> 16) | ((a & 0x0000FFFF) << 16);
        a = ((a & 0xFF00FF00) >> 8) | ((a & 0x00FF00FF) << 8);
        a = ((a & 0xF0F0F0F0) >> 4) | ((a & 0x0F0F0F0F) << 4);
        a = ((a & 0xCCCCCCCC) >> 2) | ((a & 0x33333333) << 2);
        a = ((a & 0xAAAAAAAA) >> 1) | ((a & 0x55555555) << 1);
        return a;
        CPP
      when 64
        <<~CPP
        a = ((a & 0xFFFFFFFF00000000ULL) >> 32) | ((a & 0x00000000FFFFFFFFULL) << 32);
        a = ((a & 0xFFFF0000FFFF0000ULL) >> 16) | ((a & 0x0000FFFF0000FFFFULL) << 16);
        a = ((a & 0xFF00FF00FF00FF00ULL) >> 8) | ((a & 0x00FF00FF00FF00FFULL) << 8);
        a = ((a & 0xF0F0F0F0F0F0F0F0ULL) >> 4) | ((a & 0x0F0F0F0F0F0F0F0FULL) << 4);
        a = ((a & 0xCCCCCCCCCCCCCCCCULL) >> 2) | ((a & 0x3333333333333333ULL) << 2);
        a = ((a & 0xAAAAAAAAAAAAAAAAULL) >> 1) | ((a & 0x5555555555555555ULL) << 1);
        return a;
        CPP
      when 128
        <<~CPP
        uint64_t lo = (uint64_t)a;
        uint64_t hi = (uint64_t)(a >> 64);
        return ((uint128_t)reverse_64(lo) << 64) | reverse_64(hi);
        CPP
      end
    end
  end
end

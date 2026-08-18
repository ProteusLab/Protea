require 'Utility/helper_cpp'
require 'Utility/fp_helper_cpp'

# Floating point C++ emitters, mixed into CodeGen::CppGenerator.
# Relies on @emitter/@mapping and CppGenerator#map_operand/#map_n_operands,
# so it is not usable on its own.
module CodeGen
  module FPEmitters
    # RISC-V RM to SoftFloat RM mapping
    # RNE=0 -> softfloat_round_near_even(0), RTZ=1 -> softfloat_round_minMag(1),
    # RDN=2 -> softfloat_round_min(2), RUP=3 -> softfloat_round_max(3),
    # RMM=4 -> softfloat_round_near_maxMag(4), DYN=7 -> read from fcsr
    SOFTFLOAT_RM_MAP = {
      0 => 'softfloat_round_near_even',
      1 => 'softfloat_round_minMag',
      2 => 'softfloat_round_min',
      3 => 'softfloat_round_max',
      4 => 'softfloat_round_near_maxMag',
      7 => nil # DYN - handled specially
    }.freeze

    # Emit code to set SoftFloat rounding mode before FP operation
    # For most instruction in softfloat, rounding mode is defined
    # by global variable, so we have to change it before we execute.
    # We also store it into a temporal variable, so we can restore it later.
    def emit_rm_setup(rm, tmp_var = '_rm_save')
      return unless rm # nil means no rm handling needed

      # DYN (rm == 7) means "use the rounding mode from fcsr". writeCSR keeps
      # softfloat_roundingMode synced with fcsr.frm, so for DYN we leave the
      # global as-is (save/restore only, no override).
      rm_const = SOFTFLOAT_RM_MAP[rm]
      @emitter.emit_line("uint_fast8_t #{tmp_var} = softfloat_roundingMode;")
      @emitter.emit_line("softfloat_roundingMode = #{rm_const};") if rm_const
    end

    # Emit code to restore SoftFloat rounding mode after FP operation
    def emit_rm_restore(tmp_var = '_rm_save')
      @emitter.emit_line("softfloat_roundingMode = #{tmp_var};")
    end

    # Emits binary fp operation.
    # This is different from RV32I binop, because:
    # 1. typing is different (check Utility/fp_helper_cpp.rb)
    # 2. Rounding mode has to be changed
    def emit_fp_binary(opname, operation, dst_type:, src_types:, rm: nil)
      dst  = map_operand(operation[:oprnds][0])
      src1 = map_operand(operation[:oprnds][1])
      src2 = map_operand(operation[:oprnds][2])

      t1 = Utility.gen_typed_tmp(src1, src_types[0])
      t2 = Utility.gen_typed_tmp(src2, src_types[1])
      tr = Utility.gen_typed_tmp(dst,  dst_type)

      if Utility::FP_INFO[src_types[0]]
        info = Utility::FP_INFO[src_types[0]]
        @emitter.emit_line("#{info[:c_type]} #{t1} = { #{info[:unpack]}(#{src1}) };")
      else
        ctype = Utility::INT_INFO[src_types[0]]
        @emitter.emit_line("#{ctype} #{t1} = (#{ctype})(#{src1});")
      end

      if Utility::FP_INFO[src_types[1]]
        info = Utility::FP_INFO[src_types[1]]
        @emitter.emit_line("#{info[:c_type]} #{t2} = { #{info[:unpack]}(#{src2}) };")
      else
        ctype = Utility::INT_INFO[src_types[1]]
        @emitter.emit_line("#{ctype} #{t2} = (#{ctype})(#{src2});")
      end

      # Set rounding mode before operation if rm is specified
      emit_rm_setup(rm) if rm

      if Utility::FP_INFO[dst_type]
        ctype = Utility::FP_INFO[dst_type][:c_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{t1}, #{t2});")
        pack = Utility::FP_INFO[dst_type][:pack]
        @emitter.emit_line("#{dst} = #{pack % tr};")
      else
        ctype = Utility::INT_INFO[dst_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{t1}, #{t2});")
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end

      # Restore rounding mode after operation if rm was set
      emit_rm_restore if rm
    end

    # float -> int conversions need to be handled separately, because
    # they break general pattern of softfloat instructions by demanding
    # rounding mode as an argument (they ignore global constant that all other
    # fp functions use for some unknown reason).
    def emit_fp_to_int_conv(opname, operation, dst_type:, src_type:, rounding_mode:, exact: true)
      dst = map_operand(operation[:oprnds][0])
      src = map_operand(operation[:oprnds][1])

      ts = Utility.gen_typed_tmp(src, src_type)
      tr = Utility.gen_typed_tmp(dst, dst_type)

      if Utility::FP_INFO[src_type]
        info = Utility::FP_INFO[src_type]
        @emitter.emit_line("#{info[:c_type]} #{ts} = { #{info[:unpack]}(#{src}) };")
      else
        ctype = Utility::INT_INFO[src_type]
        @emitter.emit_line("#{ctype} #{ts} = (#{ctype})(#{src});")
      end

      exact_arg = exact ? '1' : '0'
      # softfloat's fXX_to_iXX takes an explicit rounding mode argument and does
      # not understand DYN(7); for DYN use the live softfloat_roundingMode global
      # which writeCSR keeps synced with fcsr.frm.
      sf_rm = rounding_mode == 7 ? 'softfloat_roundingMode' : rounding_mode
      @emitter.emit_line("#{Utility::INT_INFO[dst_type]} #{tr} = #{opname}(#{ts}, #{sf_rm}, #{exact_arg});")
      # RISC-V sign-extends all W-form (32-bit) integer results to XLEN, even
      # the unsigned fcvt.wu.* variants.
      if %i[i32 u32].include?(dst_type)
        @emitter.emit_line("#{dst} = (uint64_t)(int64_t)(int32_t)#{tr};")
      else
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end
    end

    # There is no min/max/neg functions in softfloat,
    # so we have to implement them ourselves
    def emit_fp_min_max(opname, operation, type:)
      dst, src1, src2 = map_n_operands(operation, 3)
      t1 = Utility.gen_typed_tmp(src1, type)
      t2 = Utility.gen_typed_tmp(src2, type)
      tr = Utility.gen_typed_tmp(dst, type)
      info = Utility::FP_INFO[type]
      prefix = type == :f32 ? 'f32' : 'f64'
      sign_bit = type == :f32 ? 31 : 63

      @emitter.emit_line("#{info[:c_type]} #{t1} = { #{info[:unpack]}(#{src1}) };")
      @emitter.emit_line("#{info[:c_type]} #{t2} = { #{info[:unpack]}(#{src2}) };")
      @emitter.emit_line("#{info[:c_type]} #{tr};")

      # Bitwise NaN detection. Couldn't find softfloat's one, also this would faster with JIT
      # in comparison to function call.
      if type == :f32
        @emitter.emit_line("bool _a_nan = ((#{t1}.v >> 23) & 0xFF) == 0xFF && (#{t1}.v & 0x7FFFFF) != 0;")
        @emitter.emit_line("bool _b_nan = ((#{t2}.v >> 23) & 0xFF) == 0xFF && (#{t2}.v & 0x7FFFFF) != 0;")
        # signaling NaN: quiet bit (mantissa MSB) clear
        @emitter.emit_line("bool _a_snan = _a_nan && (#{t1}.v & 0x400000) == 0;")
        @emitter.emit_line("bool _b_snan = _b_nan && (#{t2}.v & 0x400000) == 0;")
      else
        @emitter.emit_line("bool _a_nan = ((#{t1}.v >> 52) & 0x7FF) == 0x7FF && (#{t1}.v & 0xFFFFFFFFFFFFF) != 0;")
        @emitter.emit_line("bool _b_nan = ((#{t2}.v >> 52) & 0x7FF) == 0x7FF && (#{t2}.v & 0xFFFFFFFFFFFFF) != 0;")
        @emitter.emit_line("bool _a_snan = _a_nan && (#{t1}.v & 0x8000000000000ULL) == 0;")
        @emitter.emit_line("bool _b_snan = _b_nan && (#{t2}.v & 0x8000000000000ULL) == 0;")
      end

      # RISC-V raises the invalid-operation flag when either fmin/fmax operand
      # is a signaling NaN.
      @emitter.emit_line("if (_a_snan || _b_snan) softfloat_exceptionFlags |= softfloat_flag_invalid;")

      is_min = opname.include?('min')

      canonical_nan = type == :f32 ? '0x7FC00000U' : '0x7FF8000000000000ULL'

      @emitter.emit_line('{')
      # if both are NaN, return the canonical quiet NaN; if only one is NaN,
      # return the other (numeric) operand.
      @emitter.emit_line("  if (_a_nan && _b_nan) #{tr}.v = #{canonical_nan};")
      @emitter.emit_line("  else if (_a_nan) #{tr} = #{t2};")
      @emitter.emit_line("  else if (_b_nan) #{tr} = #{t1};")
      @emitter.emit_line('  else {')
      if is_min
        # smaller or neg zero
        @emitter.emit_line("    if (#{prefix}_lt(#{t1}, #{t2}) || (#{prefix}_eq(#{t1}, #{t2}) && ((#{t1}.v >> #{sign_bit}) & 1))) #{tr} = #{t1};")
      else
        # larger or pos zero
        @emitter.emit_line("    if (#{prefix}_lt(#{t2}, #{t1}) || (#{prefix}_eq(#{t1}, #{t2}) && ((#{t2}.v >> #{sign_bit}) & 1))) #{tr} = #{t1};")
      end
      @emitter.emit_line("    else #{tr} = #{t2};")
      @emitter.emit_line('  }')
      @emitter.emit_line('}')

      pack = info[:pack]
      @emitter.emit_line("#{dst} = #{pack % tr};")
    end

    def gen_fp_neg(tmp_name, type)
      case type
      when :f32 then "#{tmp_name}.v ^= 0x80000000U;"
      when :f64 then "#{tmp_name}.v ^= 0x8000000000000000ULL;"
      end
    end

    # same as above
    def emit_fp_unary(opname, operation, dst_type:, src_type:, rm: nil)
      dst = map_operand(operation[:oprnds][0])
      src = map_operand(operation[:oprnds][1])

      ts = Utility.gen_typed_tmp(src, src_type)
      tr = Utility.gen_typed_tmp(dst, dst_type)

      if Utility::FP_INFO[src_type]
        info = Utility::FP_INFO[src_type]
        @emitter.emit_line("#{info[:c_type]} #{ts} = { #{info[:unpack]}(#{src}) };")
      else
        ctype = Utility::INT_INFO[src_type]
        @emitter.emit_line("#{ctype} #{ts} = (#{ctype})(#{src});")
      end

      # Set rounding mode before operation if rm is specified
      emit_rm_setup(rm) if rm

      if Utility::FP_INFO[dst_type]
        ctype = Utility::FP_INFO[dst_type][:c_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{ts});")
        pack = Utility::FP_INFO[dst_type][:pack]
        @emitter.emit_line("#{dst} = #{pack % tr};")
      else
        ctype = Utility::INT_INFO[dst_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{ts});")
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end

      # Restore rounding mode after operation if rm was set
      emit_rm_restore if rm
    end

    # RV64F has FMA instructions that have 3 sources, so this
    # new emitter is necessary.
    def emit_fp_ternary(opname, operation,
                        dst_type:,
                        src_types:,
                        negate_src: [],
                        rm: nil)
      dst  = map_operand(operation[:oprnds][0])
      src1 = map_operand(operation[:oprnds][1])
      src2 = map_operand(operation[:oprnds][2])
      src3 = map_operand(operation[:oprnds][3])

      srcs  = [src1, src2, src3]
      svars = []

      srcs.each_with_index do |src, i|
        ty = src_types[i]
        t  = Utility.gen_typed_tmp(src, ty)
        svars << t

        if Utility::FP_INFO[ty]
          info = Utility::FP_INFO[ty]
          @emitter.emit_line("#{info[:c_type]} #{t} = { #{info[:unpack]}(#{src}) };")
          if negate_src.include?(i)
            # TODO: change for gen_fp_neg
            negation = gen_fp_neg(t, ty)
            @emitter.emit_line(negation)
            # negf = ty == :f32 ? 'f32_neg' : 'f64_neg'
            # @emitter.emit_line("#{t} = #{negf}(#{t});")
          end

        else
          ctype = Utility::INT_INFO[ty]
          @emitter.emit_line("#{ctype} #{t} = (#{ctype})(#{src});")

          @emitter.emit_line("#{t} = -#{t};") if negate_src.include?(i)
        end
      end

      tr = Utility.gen_typed_tmp(dst, dst_type)

      # Set rounding mode before operation if rm is specified
      emit_rm_setup(rm) if rm

      if Utility::FP_INFO[dst_type]
        ctype = Utility::FP_INFO[dst_type][:c_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{svars.join(', ')});")
        pack = Utility::FP_INFO[dst_type][:pack]
        @emitter.emit_line("#{dst} = #{pack % tr};")
      else
        ctype = Utility::INT_INFO[dst_type]
        @emitter.emit_line("#{ctype} #{tr} = #{opname}(#{svars.join(', ')});")
        @emitter.emit_line("#{dst} = (uint64_t)#{tr};")
      end

      # Restore rounding mode after operation if rm was set
      emit_rm_restore if rm
    end

    # No softfloat lib function, so hand-written again
    def emit_sign_inject(operation, width:, mode:)
      dst, src1, src2 = map_n_operands(operation, 3)

      mag_mask, sign_mask =
        if width == 32
          [Utility::F32_MAG_MASK, Utility::F32_SIGN_MASK]
        else
          [Utility::F64_MAG_MASK, Utility::F64_SIGN_MASK]
        end

      sign_expr =
        case mode
        when :copy   then "(#{src2} & #{sign_mask})"
        when :neg    then "(~#{src2} & #{sign_mask})"
        when :xor    then "(#{src1} ^ (#{src2} & #{sign_mask}))"
        end

      result = if mode == :xor
                 sign_expr
               else
                 "(#{src1} & #{mag_mask}) | #{sign_expr}"
               end
      result = "0xFFFFFFFF00000000ULL | (uint64_t)(#{result})" if width == 32
      @emitter.emit_line("#{dst} = #{result};")
    end
  end
end

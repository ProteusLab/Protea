require 'Utility/helper_cpp'
# frozen_string_literal: true

# Semantics Generator: Converts IR to C++ code
module CodeGen
  class CppGenerator
    attr_reader :emitter, :mapping

    def initialize(emitter, mapping = {})
      @emitter = emitter
      @mapping = mapping
    end

    def binary_operation(emitter, operation, op_str)
      dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
      src1 = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
      src2 = @mapping[operation[:oprnds][2][:name]] || operation[:oprnds][2][:name]

      src1 = src1.nil? ? operation[:oprnds][1][:value] : src1
      src2 = src2.nil? ? operation[:oprnds][2][:value] : src2

      emitter.emit_line("#{dst} = #{src1} #{op_str} #{src2};")
    end

    def self.generate_statement(operation)
      emitter = Utility::GenEmitter.new
      CppGenerator.new(emitter, operation[:attrs][:mapping]).generate_statement(operation)
      emitter.to_s
    end

    def cpu_write_reg(dst)
      "cpu.set#{dst[:regset]}"
    end

    def cpu_read_reg(dst)
      "cpu.get#{dst[:regset]}"
    end

    def cpu_write_mem(addr, val)
      "cpu.m_memory->write(#{addr}, #{val})"
    end

    def cpu_read_mem(dst, addr)
      "cpu.m_memory->read<#{Utility::HelperCpp.gen_small_type(dst[:type])}>(#{addr})"
    end

    def generate_statement(operation)
      case operation[:name]
      when :add
        binary_operation(@emitter, operation, '+')
      when :sub
        binary_operation(@emitter, operation, '-')
      when :mul
        binary_operation(@emitter, operation, '*')
      when :div
        binary_operation(@emitter, operation, '/')
      when :shr
        binary_operation(@emitter, operation, '>>')
      when :shl
        binary_operation(@emitter, operation, '<<')
      when :and
        binary_operation(@emitter, operation, '&')
      when :or
        binary_operation(@emitter, operation, '|')
      when :xor
        binary_operation(@emitter, operation, '^')
      when :lt
        binary_operation(@emitter, operation, '<')
      when :gt
        binary_operation(@emitter, operation, '>')
      when :le
        binary_operation(@emitter, operation, '<=')
      when :ge
        binary_operation(@emitter, operation, '>=')
      when :eq
        binary_operation(@emitter, operation, '==')
      when :ne
        binary_operation(@emitter, operation, '!=')
      when :let
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        src = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        src = src.nil? ? operation[:oprnds][1][:value] : src
        @emitter.emit_line("#{dst} = #{src};")
      when :new_var
        var_name = operation[:oprnds][0][:name]
        var_type = Utility::HelperCpp.gen_small_type(operation[:oprnds][0][:type])
        @emitter.emit_line("#{var_type} #{var_name};")
      when :cast
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        src = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        src = src.nil? ? operation[:oprnds][1][:value] : src
        bitsize_dst = Utility.get_type(operation[:oprnds][0][:type]).bitsize
        bitsize_src = Utility.get_type(operation[:oprnds][1][:type]).bitsize
        cast_type = Utility::HelperCpp.gen_type(operation[:oprnds][0][:type])
        if Utility.get_type(operation[:oprnds][0][:type]).typeof == :s && bitsize_src < bitsize_dst
          @emitter.emit_line("#{dst} = (static_cast<#{cast_type}>(#{src}) << #{bitsize_dst - bitsize_src}) >> #{bitsize_dst - bitsize_src};")
        else
          @emitter.emit_line("#{dst} = static_cast<#{cast_type}>(#{src});")
        end
      when :readReg
        src = operation[:oprnds][1]
        src_name = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        expr = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        expr = expr.nil? ? operation[:oprnds][0][:value] : expr

        @emitter.emit_line("#{expr} = #{cpu_read_reg(src)}<#{Utility::HelperCpp.gen_small_type(src[:type])}>(#{src_name});")
      when :writeReg
        dst = operation[:oprnds][0]
        dst_name = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        expr = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        expr = expr.nil? ? operation[:oprnds][1][:value] : expr

        @emitter.emit_line("#{cpu_write_reg(dst)}(#{dst_name}, #{expr});")
      when :branch
        val = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        @emitter.emit_line("cpu.setPC(#{val});")
      when :readMem
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        addr = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        @emitter.emit_line("#{dst} = #{cpu_read_mem operation[:oprnds][0], addr};")
      when :writeMem
        addr = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        val = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        @emitter.emit_line("#{cpu_write_mem addr, val};")
      when :extract
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        src = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]

        @emitter.emit_line("#{dst} = static_cast<#{Utility::HelperCpp.gen_small_type operation[:oprnds][0][:type]}>(#{src} << #{operation[:oprnds][3][:value]});")
      when :sysCall
        @emitter.emit_line('cpu.doExit();')
      when :select
        dst = @mapping[operation[:oprnds][0][:name]] || operation[:oprnds][0][:name]
        cond = @mapping[operation[:oprnds][1][:name]] || operation[:oprnds][1][:name]
        true_val = @mapping[operation[:oprnds][2][:name]] || operation[:oprnds][2][:name]
        false_val = @mapping[operation[:oprnds][3][:name]] || operation[:oprnds][3][:name]

        @emitter.emit_line("#{dst} = #{cond} ? #{true_val} : #{false_val};")
      end
    end
  end
end

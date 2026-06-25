# frozen_string_literal: true

require_relative '../lib/lira/ir'
require_relative 'cpp_ops'
require_relative '../lib/Utility/helper_cpp'

module LiraCppGen
  module OpRegistry
    @ops = {}

    def self.ops=(map)
      @ops = map
    end

    def self.lookup(name)
      @ops[name] or raise "Unknown operation: #{name}"
    end
  end

  class StmtEmitter
    def initialize(translator)
      @t = translator
    end

    def stmt
      @t.current_stmt
    end

    def emit(line)
      @t.emit(line)
    end

    def indent(&block)
      @t.indent(&block)
    end

    def context
      @t.context
    end

    def resolve_var(name)
      @t.resolve_var(name, stmt)
    end

    def declare(name, width)
      @t.declare_var(name, width)
    end

    def var_width(name)
      @t.var_width(name)
    end

    def emit_code
      raise NotImplementedError
    end
  end

  class OpEmitter < StmtEmitter
    def emit_code
      s = stmt
      out = s.outputs[0]
      declare(out, s.outputs_types[0])
      inputs = s.inputs.map { |i| resolve_var(i) }
      op = OpRegistry.lookup(s.specifier)

      if op.semantic_base == Lira::BaseOp::SELECT
        emit("#{out} = #{inputs[0]} ? #{inputs[1]} : #{inputs[2]};")
      else
        emit("#{out} = #{op.cpp_func_name}(#{inputs.join(', ')});")
      end
    end
  end

  class ConstEmitter < StmtEmitter
    def emit_code
      s = stmt
      out = s.outputs[0]
      width = s.outputs_types[0]
      return if @t.var_declared?(out)

      emit("#{Utility::HelperCpp.gen_type(width)} #{out} = #{s.specifier};")
      @t.register_var(out, width)
    end
  end

  class DynConstEmitter < StmtEmitter
    def emit_code
      s = stmt
      out = s.outputs[0]
      width = s.outputs_types[0]
      return if @t.var_declared?(out)

      emit("#{Utility::HelperCpp.gen_type(width)} #{out} = #{s.specifier};")
      @t.register_var(out, width)
    end
  end

  class ReadEmitter < StmtEmitter
    def emit_code
      s = stmt
      rf = s.specifier
      idx = resolve_var(s.inputs[0])
      out = s.outputs[0]
      width = s.outputs_types[0]
      declare(out, width)
      if context == :execute
        emit("#{out} = cpu.get#{rf}<#{Utility::HelperCpp.gen_type(width)}>(#{idx});")
      else
        raise "Unexpected read statement in decode section"
      end
    end
  end

  class WriteEmitter < StmtEmitter
    def emit_code
      s = stmt
      rf = s.specifier
      idx = resolve_var(s.inputs[0])
      val = resolve_var(s.inputs[1])
      emit("cpu.set#{rf}(#{idx}, #{val});") if context == :execute
    end
  end

  class EnvEmitter < StmtEmitter
    def emit_code
      s = stmt
      func = s.specifier
      inputs = s.inputs.map { |i| resolve_var(i) }
      outputs = s.outputs
      out_types = s.outputs_types

      func = resolve_env_func(func, out_types, inputs)

      return unless context == :execute

      if outputs.empty?
        emit("cpu.#{func}(#{inputs.join(', ')});")
      elsif outputs.size == 1
        out = outputs[0]
        declare(out, out_types[0])
        emit("#{out} = cpu.#{func}(#{inputs.join(', ')});")
      else
        outputs.each_with_index { |out, i| declare(out, out_types[i]) }
        emit("std::tie(#{outputs.join(', ')}) = cpu.#{func}(#{inputs.join(', ')});")
      end
    end

    private

    def resolve_env_func(func, out_types, inputs)
      if func == 'readMem' && out_types.size == 1
        "readMem#{out_types[0]}"
      elsif func == 'writeMem' && inputs.size >= 2
        width = var_width(stmt.inputs[1]) || 32
        "writeMem#{width}"
      else
        func
      end
    end
  end

  class CondEnvEmitter < StmtEmitter
    def emit_code
      s = stmt
      cond = resolve_var(s.inputs[0])
      inputs = s.inputs[1...-s.outputs.size].map { |i| resolve_var(i) }
      on_false = s.inputs[-s.outputs.size..].map { |i| resolve_var(i) }
      func = s.specifier

      emit("if (#{cond}) {")
      indent { emit_cond_true(s, func, inputs) }
      emit('} else {')
      indent { emit_cond_false(s, on_false) }
      emit('}')
    end

    private

    def emit_cond_true(st, func, inputs)
      st.outputs.each_with_index do |out, i|
        declare(out, st.outputs_types[i])
        emit("#{out} = cpu.#{func}(#{inputs.join(', ')});")
      end
    end

    def emit_cond_false(st, on_false)
      st.outputs.each_with_index { |out, i| emit("#{out} = #{on_false[i]};") }
    end
  end

  class InputEmitter < StmtEmitter
    def emit_code
      s = stmt
      idx = s.specifier.to_i
      out = s.outputs[0]
      width = s.outputs_types[0]
      declare(out, width)
      emit(context == :decode || context == :snippet ? "#{out} = raw_insn;" : "#{out} = insn.operand#{idx};")
    end
  end

  class OutputEmitter < StmtEmitter
    def emit_code
      s = stmt
      val = resolve_var(s.inputs[0])
      idx = s.specifier.to_i
      if context == :snippet
        emit("return #{val};")
      else
        emit("insn.operand#{idx} = #{val};")
      end
    end
  end

  EMITTER_MAP = {
    'op' => OpEmitter,
    'const' => ConstEmitter,
    'dyn_const' => DynConstEmitter,
    'read' => ReadEmitter,
    'write' => WriteEmitter,
    'env' => EnvEmitter,
    'cond_env' => CondEnvEmitter,
    'input' => InputEmitter,
    'output' => OutputEmitter
  }.freeze

  class Translator
    attr_reader :context, :current_stmt

    def initialize(seq, context = :execute, indent = 0)
      @seq = seq
      @context = context
      @indent = indent
      @output = []
      @var_widths = {}
    end

    def translate
      @seq.stmts.each { |stmt| translate_stmt(stmt) }
      @output.join("\n")
    end

    def declare_var(name, width)
      return if var_declared?(name)

      emit("#{Utility::HelperCpp.gen_type(width)} #{name};")
      register_var(name, width)
    end

    def var_declared?(name)
      @var_widths.key?(name)
    end

    def var_width(name)
      @var_widths[name]
    end

    def register_var(name, width)
      @var_widths[name] = width
    end

    def resolve_var(name, stmt)
      return name if var_declared?(name)

      if name =~ /^_t\d+$/
        width = 32
        width = stmt.outputs_types[0] if stmt.respond_to?(:outputs_types) && stmt.outputs_types.any?
        emit("#{Utility::HelperCpp.gen_type(width)} #{name} = 0;")
        register_var(name, width)
        return name
      end
      raise "Unknown variable #{name} in #{stmt&.inspect}"
    end

    def emit(line)
      @output << (' ' * @indent + line)
    end

    def indent
      @indent += 2
      yield
      @indent -= 2
    end

    private

    def translate_stmt(stmt)
      emitter_class = EMITTER_MAP[stmt.kind] or raise "Unknown statement kind: #{stmt.kind}"
      @current_stmt = stmt
      emitter_class.new(self).emit_code
    end
  end
end

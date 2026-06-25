# lira/ir_builder.rb
require_relative 'ir'
require_relative 'arch'
require_relative 'ir_ops'

module Lira
  class Value
    attr_accessor :name, :width

    def initialize(name, width = 32)
      @name = name
      @width = width
      @shape = Shape.new(1, nil)
    end

    def to_s
      name
    end

    def inspect
      "Value(#{name}, #{width})"
    end

    def ==(other)
      other.is_a?(Value) && name == other.name && width == other.width
    end
  end

  class SeqBuilder
    attr_reader :stmts, :temp_counter

    def initialize
      @stmts = []
      @temp_counter = 0
    end

    def new_temp(width = 32)
      @temp_counter += 1
      Value.new("_t#{@temp_counter}", width)
    end

    def emit_op(op, inputs, out_bits)
      out = new_temp(out_bits)
      add_op(op, inputs, [out.name])
      out
    end

    def check_width_match(a, b)
      raise "width mismatch: #{a.width} != #{b.width}" if a.width != b.width
    end

    # ------------------------------------------------------------------
    # NOTE: Building ruby/lira/ir_ops.rb objects
    # ------------------------------------------------------------------
    def add(a, b)
      check_width_match(a, b)
      emit_op(Add.new(a.width), [a.name, b.name], a.width)
    end

    def sub(a, b)
      check_width_match(a, b)
      emit_op(Sub.new(a.width), [a.name, b.name], a.width)
    end

    def mul(a, b)
      check_width_match(a, b)
      emit_op(Mul.new(a.width), [a.name, b.name], a.width)
    end

    def and_(a, b)
      check_width_match(a, b)
      emit_op(And.new(a.width), [a.name, b.name], a.width)
    end

    def orr(a, b)
      check_width_match(a, b)
      emit_op(Orr.new(a.width), [a.name, b.name], a.width)
    end

    def xor(a, b)
      check_width_match(a, b)
      emit_op(Xor.new(a.width), [a.name, b.name], a.width)
    end

    def lsl(a, b)
      check_width_match(a, b)
      emit_op(Lsl.new(a.width), [a.name, b.name], a.width)
    end

    def lsr(a, b)
      check_width_match(a, b)
      emit_op(Lsr.new(a.width), [a.name, b.name], a.width)
    end

    def asr(a, b)
      check_width_match(a, b)
      emit_op(Asr.new(a.width), [a.name, b.name], a.width)
    end

    def slt(a, b)
      check_width_match(a, b)
      emit_op(Slt.new(a.width), [a.name, b.name], 1)
    end

    def sle(a, b)
      check_width_match(a, b)
      emit_op(Sle.new(a.width), [a.name, b.name], 1)
    end

    def sgt(a, b)
      check_width_match(a, b)
      emit_op(Sgt.new(a.width), [a.name, b.name], 1)
    end

    def sge(a, b)
      check_width_match(a, b)
      emit_op(Sge.new(a.width), [a.name, b.name], 1)
    end

    def ult(a, b)
      check_width_match(a, b)
      emit_op(Ult.new(a.width), [a.name, b.name], 1)
    end

    def ule(a, b)
      check_width_match(a, b)
      emit_op(Ule.new(a.width), [a.name, b.name], 1)
    end

    def ugt(a, b)
      check_width_match(a, b)
      emit_op(Ugt.new(a.width), [a.name, b.name], 1)
    end

    def uge(a, b)
      check_width_match(a, b)
      emit_op(Uge.new(a.width), [a.name, b.name], 1)
    end

    def eq(a, b)
      check_width_match(a, b)
      emit_op(Eq.new(a.width), [a.name, b.name], 1)
    end

    def ne(a, b)
      check_width_match(a, b)
      emit_op(Ne.new(a.width), [a.name, b.name], 1)
    end

    def rem_u(a, b)
      check_width_match(a, b)
      emit_op(RemU.new(a.width), [a.name, b.name], a.width)
    end

    def rem_s(a, b)
      check_width_match(a, b)
      emit_op(RemS.new(a.width), [a.name, b.name], a.width)
    end

    def ror(a, b)
      check_width_match(a, b)
      emit_op(Ror.new(a.width), [a.name, b.name], a.width)
    end

    def rol(a, b)
      check_width_match(a, b)
      emit_op(Rol.new(a.width), [a.name, b.name], a.width)
    end

    def add_overflow(a, b)
      check_width_match(a, b)
      emit_op(AddOverflow.new(a.width), [a.name, b.name], 1)
    end

    def sub_overflow(a, b)
      check_width_match(a, b)
      emit_op(SubOverflow.new(a.width), [a.name, b.name], 1)
    end

    def not_(a)
      emit_op(Not.new(a.width), [a.name], a.width)
    end

    def neg(a)
      emit_op(Neg.new(a.width), [a.name], a.width)
    end

    def popcnt(a)
      emit_op(Popcnt.new(a.width), [a.name], a.width)
    end

    def ctz(a)
      emit_op(Ctz.new(a.width), [a.name], a.width)
    end

    def clz(a)
      emit_op(Clz.new(a.width), [a.name], a.width)
    end

    def reverse(a)
      emit_op(Reverse.new(a.width), [a.name], a.width)
    end

    def extend_sign(a, to_width)
      raise "extend_sign: input width #{a.width} >= output width #{to_width}" if a.width >= to_width
      emit_op(ExtendSign.new(a.width, to_width), [a.name], to_width)
    end

    def extend_zero(a, to_width)
      raise "extend_zero: input width #{a.width} >= output width #{to_width}" if a.width >= to_width
      emit_op(ExtendZero.new(a.width, to_width), [a.name], to_width)
    end

    def extract_low(a, out_width)
      raise "extract_low: output width #{out_width} > input width #{a.width}" if out_width > a.width
      emit_op(ExtractLow.new(a.width, out_width), [a.name], out_width)
    end

    def div_u(a, b, default)
      check_width_match(a, b)
      raise "div_u: default width mismatch" if a.width != default.width
      emit_op(DivU.new(a.width), [a.name, b.name, default.name], a.width)
    end

    def div_s(a, b, default)
      check_width_match(a, b)
      raise "div_s: default width mismatch" if a.width != default.width
      emit_op(DivS.new(a.width), [a.name, b.name, default.name], a.width)
    end

    def select(cond, true_val, false_val)
      raise "select: condition must be 1-bit" unless cond.width == 1
      raise "select: true/false widths mismatch" unless true_val.width == false_val.width
      emit_op(
        Select.new(true_val.width),
        [cond.name, true_val.name, false_val.name],
        true_val.width
      )
    end


    # ------------------------------------------------------------------
    # NOTE: Building ruby/lira/ir_std.rb objects
    # ------------------------------------------------------------------
    def read(rf, rsi, shape = Shape.new(1, nil))
      width = rf.reg_size.lanes_base
      out = new_temp(width)
      stmt = Statement.new(shape, [out.name], [width], 'read', rf.name, [rsi.name])
      @stmts << stmt
      out
    end

    def write(rf, rsi, value, shape = Shape.new(1, nil))
      stmt = Statement.new(shape, [], [], 'write', rf.name, [rsi.name, value.name])
      @stmts << stmt
    end

    def const(value, width = 32)
      out = new_temp(width)
      stmt = Statement.new(Shape.new(1, nil), [out.name], [width], 'const', value.to_s, [])
      @stmts << stmt
      out
    end

    def dyn_const(name, width = 32)
      out = new_temp(width)
      stmt = Statement.new(Shape.new(1, nil), [out.name], [width], 'dyn_const', name, [])
      @stmts << stmt
      out
    end

    def env(env_func, inputs)
      outputs = env_func.outputs.map { |w| new_temp(w) }
      stmt = Statement.new(
        Shape.new(1, nil),
        outputs.map(&:name),
        env_func.outputs,
        'env',
        env_func.name,
        inputs.map(&:name)
      )
      @stmts << stmt
      outputs
    end

    def cond_env(env_func, cond, inputs, on_false)
      outputs = env_func.outputs.map { |w| new_temp(w) }
      all_inputs = [cond.name] + inputs.map(&:name) + on_false.map(&:name)
      stmt = Statement.new(
        Shape.new(1, nil),
        outputs.map(&:name),
        env_func.outputs,
        'cond_env',
        env_func.name,
        all_inputs
      )
      @stmts << stmt
      outputs
    end

    def input(idx, width = 32)
      out = new_temp(width)
      stmt = Statement.new(Shape.new(1, nil), [out.name], [width], 'input', idx.to_s, [])
      @stmts << stmt
      out
    end

    def output(value, idx)
      stmt = Statement.new(Shape.new(1, nil), [], [], 'output', idx.to_s, [value.name])
      @stmts << stmt
    end

    def add_op(operation, inputs, outputs, shape = Shape.new(1, nil))
      stmt = Statement.new(shape, outputs, operation.outputs, 'op', operation.name, inputs)
      @stmts << stmt
    end

    def op(operation, inputs)
      raise "Operation #{operation.name} has #{operation.outputs.size} outputs, use op_multi" if operation.outputs.size != 1
      emit_op(operation, inputs.map(&:name), operation.outputs.first)
    end

    def op_multi(operation, inputs)
      outputs = operation.outputs.map { |w| new_temp(w) }
      add_op(operation, inputs.map(&:name), outputs.map(&:name))
      outputs
    end

    def build
      StatementSeq.new(@stmts)
    end

    def +(other)
      @stmts.concat(other.stmts)
      @temp_counter = [@temp_counter, other.temp_counter].max
      self
    end
  end

  class BaseBuilder
    attr_reader :seq

    def initialize
      @seq = SeqBuilder.new
      @op_cache = {}
    end

    def cache_op(op_class, *args)
      op = op_class.new(*args)
      @op_cache[op.name] ||= op
    end

    def operations_map
      @op_cache.each_value.to_h { |op| [op.name, op] }
    end

    # ------------------------------------------------------------------
    # NOTE: Building ruby/lira/ir_ops.rb objects
    # ------------------------------------------------------------------
    def add(a, b)
      cache_op(Add, a.width)
      @seq.add(a, b)
    end

    def sub(a, b)
      cache_op(Sub, a.width)
      @seq.sub(a, b)
    end

    def mul(a, b)
      cache_op(Mul, a.width)
      @seq.mul(a, b)
    end

    def and_(a, b)
      cache_op(And, a.width)
      @seq.and_(a, b)
    end

    def orr(a, b)
      cache_op(Orr, a.width)
      @seq.orr(a, b)
    end

    def xor(a, b)
      cache_op(Xor, a.width)
      @seq.xor(a, b)
    end

    def lsl(a, b)
      cache_op(Lsl, a.width)
      @seq.lsl(a, b)
    end

    def lsr(a, b)
      cache_op(Lsr, a.width)
      @seq.lsr(a, b)
    end

    def asr(a, b)
      cache_op(Asr, a.width)
      @seq.asr(a, b)
    end

    def slt(a, b)
      cache_op(Slt, a.width)
      @seq.slt(a, b)
    end

    def sle(a, b)
      cache_op(Sle, a.width)
      @seq.sle(a, b)
    end

    def sgt(a, b)
      cache_op(Sgt, a.width)
      @seq.sgt(a, b)
    end

    def sge(a, b)
      cache_op(Sge, a.width)
      @seq.sge(a, b)
    end

    def ult(a, b)
      cache_op(Ult, a.width)
      @seq.ult(a, b)
    end

    def ule(a, b)
      cache_op(Ule, a.width)
      @seq.ule(a, b)
    end

    def ugt(a, b)
      cache_op(Ugt, a.width)
      @seq.ugt(a, b)
    end

    def uge(a, b)
      cache_op(Uge, a.width)
      @seq.uge(a, b)
    end

    def eq(a, b)
      cache_op(Eq, a.width)
      @seq.eq(a, b)
    end

    def ne(a, b)
      cache_op(Ne, a.width)
      @seq.ne(a, b)
    end

    def rem_u(a, b)
      cache_op(RemU, a.width)
      @seq.rem_u(a, b)
    end

    def rem_s(a, b)
      cache_op(RemS, a.width)
      @seq.rem_s(a, b)
    end

    def ror(a, b)
      cache_op(Ror, a.width)
      @seq.ror(a, b)
    end

    def rol(a, b)
      cache_op(Rol, a.width)
      @seq.rol(a, b)
    end

    def add_overflow(a, b)
      cache_op(AddOverflow, a.width)
      @seq.add_overflow(a, b)
    end

    def sub_overflow(a, b)
      cache_op(SubOverflow, a.width)
      @seq.sub_overflow(a, b)
    end

    def not_(a)
      cache_op(Not, a.width)
      @seq.not_(a)
    end

    def neg(a)
      cache_op(Neg, a.width)
      @seq.neg(a)
    end

    def popcnt(a)
      cache_op(Popcnt, a.width)
      @seq.popcnt(a)
    end

    def ctz(a)
      cache_op(Ctz, a.width)
      @seq.ctz(a)
    end

    def clz(a)
      cache_op(Clz, a.width)
      @seq.clz(a)
    end

    def reverse(a)
      cache_op(Reverse, a.width)
      @seq.reverse(a)
    end

    def extend_sign(a, to_width)
      cache_op(ExtendSign, a.width, to_width)
      @seq.extend_sign(a, to_width)
    end

    def extend_zero(a, to_width)
      cache_op(ExtendZero, a.width, to_width)
      @seq.extend_zero(a, to_width)
    end

    def extract_low(a, out_width)
      cache_op(ExtractLow, a.width, out_width)
      @seq.extract_low(a, out_width)
    end

    def div_u(a, b, default)
      cache_op(DivU, a.width)
      @seq.div_u(a, b, default)
    end

    def div_s(a, b, default)
      cache_op(DivS, a.width)
      @seq.div_s(a, b, default)
    end

    def select(cond, true_val, false_val)
      cache_op(Select, true_val.width)
      @seq.select(cond, true_val, false_val)
    end

    # ------------------------------------------------------------------
    # NOTE: Building ruby/lira/ir_std.rb objects
    # ------------------------------------------------------------------
    def read(rf, rsi, shape = Shape.new(1, nil))
      @seq.read(rf, rsi, shape)
    end

    def write(rf, rsi, value, shape = Shape.new(1, nil))
      @seq.write(rf, rsi, value, shape)
    end

    def const(value, width = 32)
      @seq.const(value, width)
    end

    def dyn_const(name, width = 32)
      @seq.dyn_const(name, width)
    end

    def env(env_func, inputs)
      @seq.env(env_func, inputs)
    end

    def cond_env(env_func, cond, inputs, on_false)
      @seq.cond_env(env_func, cond, inputs, on_false)
    end

    def input(idx, width = 32)
      @seq.input(idx, width)
    end

    def output(value, idx)
      @seq.output(value, idx)
    end

    def op(operation, inputs)
      @op_cache[operation.name] ||= operation
      @seq.op(operation, inputs)
    end

    def op_multi(operation, inputs)
      @seq.op_multi(operation, inputs)
    end
  end

  class SnippetBuilder < BaseBuilder
    attr_reader :name

    def initialize(name)
      super()
      @name = name
    end

    def build
      Snippet.new(@name, @seq.build)
    end
  end

  class InstructionBuilder < BaseBuilder
    attr_reader :name, :operand_sizes, :operand_names, :encoding

    def initialize(name, operand_sizes, operand_names, encoding)
      super()
      @name = name
      @operand_sizes = operand_sizes
      @operand_names = operand_names
      @encoding = encoding
    end

    def add_input_operand(idx, width = nil)
      w = width || (@operand_sizes[idx] if idx < @operand_sizes.size) || 32
      input(idx, w)
    end

    def build
      Instruction.new(
        @name, [],
        @operand_sizes, @operand_names,
        @encoding,
        @seq.build
      )
    end
  end

  class ArchBuilder
    attr_reader :name, :attributes, :register_files, :system_registers,
                :environment_functions, :tables_int, :operations,
                :snippets, :instructions

    def initialize(name, attributes = [])
      @name = name
      @attributes = attributes
      @register_files = []
      @system_registers = []
      @environment_functions = []
      @tables_int = []
      @operations = []
      @snippets = []
      @instructions = []
    end

    def add_register_file(rf)
      @register_files << rf
      self
    end

    def add_system_register(sr)
      @system_registers << sr
      self
    end

    def add_env_func(env)
      @environment_functions << env
      self
    end

    def add_table_int(table)
      @tables_int << table
      self
    end

    def add_operation(op)
      @operations << op
      self
    end

    def add_snippet(snippet)
      @snippets << snippet
      self
    end

    def add_instruction(instr)
      @instructions << instr
      self
    end

    def build
      Arch.new(
        @name, @attributes,
        register_files: @register_files,
        system_registers: @system_registers,
        environment_functions: @environment_functions,
        tables_int: @tables_int,
        operations: @operations,
        snippets: @snippets,
        instructions: @instructions
      )
    end
  end
end

# lira/lira_gen.rb
# !/usr/bin/env ruby

require_relative 'ADL/base'
require_relative 'ADL/builder'
require_relative 'lira/arch'
require_relative 'lira/ir'
require_relative 'lira/ir_builder'
require_relative 'lira/ir_ops'
require_relative 'lira/arch_ser_yaml'
require_relative 'lira/ir_ser_txt'
require_relative 'Utility/lira_utils'

class LiraSerializer
  OP_MAP = {
    add: Lira::Add,
    sub: Lira::Sub,
    mul: Lira::Mul,
    and: Lira::And,
    or: Lira::Orr,
    xor: Lira::Xor,
    shl: Lira::Lsl,
    shr: Lira::Lsr,
    ashr: Lira::Asr
  }.freeze

  CMP_OP_MAP_S = {
    eq: Lira::Eq,
    ne: Lira::Ne,
    lt: Lira::Slt,
    gt: Lira::Sgt,
    le: Lira::Sle,
    ge: Lira::Sge
  }.freeze

  CMP_OP_MAP_U = {
    eq: Lira::Eq,
    ne: Lira::Ne,
    lt: Lira::Ult,
    gt: Lira::Ugt,
    le: Lira::Ule,
    ge: Lira::Uge
  }.freeze

  class StmtHandler
    def initialize(serializer)
      @ser = serializer
    end

    def handle(stmt)
      raise NotImplementedError
    end

    private

    attr_reader :ser

    def resolved(op)     = ser.resolved(op)
    def builder          = ser.builder
    def vars             = ser.vars
    def operand_names    = ser.operand_names
    def arch_builder     = ser.arch_builder
    def current_instr    = ser.current_instr
    def store(var, val)  = ser.store_result(var, val)
  end

  class NewVarHandler < StmtHandler
    def handle(stmt)
      var = stmt.oprnds[0]
      width = ADLToLiraUtils.convert_type(var.type)
      width = 1 if width < 1
      vars[var] = builder.seq.new_temp(width)
    end
  end

  class LetHandler < StmtHandler
    def handle(stmt)
      rhs_val = resolved(stmt.oprnds[1])
      vars[stmt.oprnds[0]] = rhs_val if rhs_val
    end
  end

  class DecodeLetHandler < StmtHandler
    def handle(stmt)
      lhs, rhs = stmt.oprnds
      if rhs.is_a?(SimInfra::Var) && rhs.name.to_s.start_with?('f_')
        val = ser.resolve_field(rhs)
        if val && val.width != ADLToLiraUtils.convert_type(lhs.type)
          val = builder.extend_zero(val, ADLToLiraUtils.convert_type(lhs.type))
        end
        vars[lhs] = val if val
      else
        rhs_val = ADLToLiraUtils.resolve_operand(rhs, builder, vars, [], arch_builder)
        vars[lhs] = rhs_val if rhs_val
      end
    end
  end

  class AluOpHandler < StmtHandler
    def handle(stmt)
      name = stmt.name
      oprnds = stmt.oprnds
      a = resolved(oprnds[1])
      b = resolved(oprnds[2])
      return if a.nil? || b.nil?

      lhs_signed = oprnds[1].type.to_s.start_with?('s')
      store(oprnds[0], ser.op_alu(name, lhs_signed, a, b))
    end
  end

  class CmpOpHandler < StmtHandler
    def handle(stmt)
      name = stmt.name
      oprnds = stmt.oprnds
      a = resolved(oprnds[1])
      b = resolved(oprnds[2])
      return if a.nil? || b.nil?

      unsigned = oprnds[1].type.to_s.start_with?('u')
      store(oprnds[0], ser.op_cmp(name, unsigned, a, b))
    end
  end

  class SelectHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      cond = resolved(oprnds[1])
      t = resolved(oprnds[2])
      f = resolved(oprnds[3])
      return if cond.nil? || t.nil? || f.nil?

      store(oprnds[0], builder.select(cond, t, f))
    end
  end

  class CastHandler < StmtHandler
    def handle(stmt)
      name = stmt.name
      oprnds = stmt.oprnds
      src = resolved(oprnds[1])
      return if src.nil?

      store(oprnds[0], ser.widen_or_truncate(name, oprnds[0].type, src, oprnds[1].type))
    end
  end

  class DecodeCastHandler < StmtHandler
    def handle(stmt)
      name = stmt.name
      oprnds = stmt.oprnds
      lhs, rhs = oprnds
      src = vars[rhs]
      if src
        vars[lhs] = ser.widen_or_truncate(name, lhs.type, src, rhs.type)
      elsif rhs.is_a?(SimInfra::Var) && rhs.name.to_s.start_with?('f_')
        val = ser.resolve_field(rhs, lhs.type)
        vars[lhs] = val if val
      else
        rhs_val = ADLToLiraUtils.resolve_operand(rhs, builder, vars, [], arch_builder)
        vars[lhs] = rhs_val if rhs_val
      end
    end
  end

  class ExtractHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      val = resolved(oprnds[1])
      return if val.nil?

      hi = oprnds[2].value
      lo = oprnds[3].value
      width = hi - lo + 1
      width = 1 if width < 1
      store(oprnds[0], builder.extract_low(val, width))
    end
  end

  class ReadRegHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      reg_var = oprnds[1]
      idx = operand_names.index(reg_var.name.to_s)
      if idx
        reg_num = builder.input(idx, ADLToLiraUtils.convert_type(reg_var.type))
        rf_name = reg_var.regset.to_s
        rf = arch_builder.register_files.find { |r| r.name == rf_name }
        unless rf
          warn "Register file '#{rf_name}' not found, skipping statement"
          return
        end
        store(oprnds[0], builder.read(rf, reg_num))
      else
        val = resolved(reg_var)
        store(oprnds[0], val) if val
      end
    end
  end

  class WriteRegHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      reg_var = oprnds[0]
      val = resolved(oprnds[1])
      return if val.nil?

      idx = operand_names.index(reg_var.name.to_s)
      if idx
        reg_num = builder.input(idx, ADLToLiraUtils.convert_type(reg_var.type))
        rf_name = reg_var.regset.to_s
        rf = arch_builder.register_files.find { |r| r.name == rf_name }
        unless rf
          warn "Register file '#{rf_name}' not found, skipping statement"
          return
        end
        builder.write(rf, reg_num, val)
      elsif ADLToLiraUtils::SPECIAL_REGS.include?(reg_var.name.to_s)
        ef = ADLToLiraUtils.find_env_func(arch_builder, 'setPC', [32], [])
        unless ef
          warn "Environment function 'setPC' not registered, skipping statement"
          return
        end
        builder.env(ef, [val])
      else
        warn "Register file '#{reg_var.regset}' not found, skipping statement"
      end
    end
  end

  class ReadMemHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      out_type = ADLToLiraUtils.convert_type(oprnds[0].type)
      addr = resolved(oprnds[1])
      return if addr.nil?

      ef = ADLToLiraUtils.find_env_func(arch_builder, stmt.attrs.to_s, [addr.width], [out_type])
      unless ef
        warn "Environment function #{stmt.attrs} wasn't registered, skipping statement"
        return
      end
      store(oprnds[0], builder.env(ef, [addr])[0])
    end
  end

  class WriteMemHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      addr = resolved(oprnds[0])
      val = resolved(oprnds[1])
      return if addr.nil? || val.nil?

      ef = ADLToLiraUtils.find_env_func(arch_builder, stmt.attrs.to_s, [addr.width, val.width], [])
      unless ef
        warn "Environment function #{stmt.attrs} wasn't registered, skipping statement"
        return
      end
      builder.env(ef, [addr, val])
    end
  end

  class BranchHandler < StmtHandler
    def handle(stmt)
      target = resolved(stmt.oprnds[0])
      return if target.nil?

      ef = ADLToLiraUtils.find_env_func(arch_builder, 'setPC', [32], [])
      unless ef
        warn "Environment function 'setPC' not registered, skipping statement"
        return
      end
      builder.env(ef, [target])
    end
  end

  class SysCallHandler < StmtHandler
    def handle(stmt)
      ef = ADLToLiraUtils.find_env_func(arch_builder, 'sysCall', [], [])
      unless ef
        warn "Environment function 'sysCall' not registered, skipping statement"
        return
      end
      builder.env(ef, [])
    end
  end

  class RemHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      a = resolved(oprnds[1])
      b = resolved(oprnds[2])
      return if a.nil? || b.nil?

      unsigned = oprnds[1].type.to_s.start_with?('u')
      store(oprnds[0], unsigned ? builder.rem_u(a, b) : builder.rem_s(a, b))
    end
  end

  class DivHandler < StmtHandler
    def handle(stmt)
      oprnds = stmt.oprnds
      a = resolved(oprnds[1])
      b = resolved(oprnds[2])
      return if a.nil? || b.nil?

      unsigned = oprnds[1].type.to_s.start_with?('u')
      default_val = builder.const(0, a.width)
      store(oprnds[0], unsigned ? builder.div_u(a, b, default_val) : builder.div_s(a, b, default_val))
    end
  end

  HANDLER_MAP = {
    new_var: NewVarHandler,
    let: LetHandler,
    add: AluOpHandler,
    sub: AluOpHandler,
    mul: AluOpHandler,
    and: AluOpHandler,
    or: AluOpHandler,
    xor: AluOpHandler,
    shl: AluOpHandler,
    shr: AluOpHandler,
    ashr: AluOpHandler,

    lt: CmpOpHandler,
    gt: CmpOpHandler,
    le: CmpOpHandler,
    ge: CmpOpHandler,
    eq: CmpOpHandler,
    ne: CmpOpHandler,

    select: SelectHandler,

    cast: CastHandler, zext: CastHandler,

    extract: ExtractHandler,

    readReg: ReadRegHandler,
    writeReg: WriteRegHandler,

    readMem: ReadMemHandler,
    writeMem: WriteMemHandler,

    branch: BranchHandler,
    sysCall: SysCallHandler,

    rem: RemHandler,
    div: DivHandler
  }.freeze

  DECODE_HANDLER_MAP = HANDLER_MAP.merge(
    let: DecodeLetHandler,
    cast: DecodeCastHandler,
    zext: DecodeCastHandler
  ).freeze

  attr_reader :builder, :vars, :operand_names, :arch_builder
  attr_accessor :current_instr, :raw_enc

  def initialize(arch_name, arch_attributes = [])
    @arch_name = arch_name
    @arch_attributes = arch_attributes
    @arch_builder = nil
    @builder = nil
    @vars = nil
    @operand_names = nil
    @current_instr = nil

    @decode_cache = {}
    @decode_snip_id = 0
    @encode_cache = {}
    @encode_snip_id = 0
    @constraint_cache = {}
    @constraint_snip_id = 0
    @ops_used = {}
  end

  def resolved(op)
    ADLToLiraUtils.resolve_operand(op, @builder, @vars, @operand_names, @arch_builder)
  end

  def store_result(var, val)
    @vars[var] = val if val
    val
  end

  def op_alu(adl_name, lhs_signed, a, b)
    op_name = adl_name == :shr && lhs_signed ? :ashr : adl_name
    op_class = OP_MAP[op_name] or raise "Unknown ALU op: #{adl_name}"
    @builder.op(op_class.new(a.width), [a, b])
  end

  def op_cmp(adl_name, unsigned, a, b)
    op_map = unsigned ? CMP_OP_MAP_U : CMP_OP_MAP_S
    op_class = op_map[adl_name] or raise "Unknown cmp op: #{adl_name}"
    @builder.op(op_class.new(a.width), [a, b])
  end

  def widen_or_truncate(name, dest_type, src, src_type)
    dest_width = ADLToLiraUtils.convert_type(dest_type)
    dest_width = 1 if dest_width < 1
    src_expected_width = ADLToLiraUtils.convert_type(src_type)
    src = @builder.extract_low(src, src_expected_width) if src.width > src_expected_width
    return src if src.width == dest_width

    if name == :zext || dest_type.to_s.start_with?('u')
      @builder.extend_zero(src, dest_width)
    else
      @builder.extend_sign(src, dest_width)
    end
  end

  def resolve_field(field_var, dest_type = :b32)
    field_name = field_var.name.to_s[2..]
    field = @current_instr.fields.find { |f| f.value.name.to_s == "f_#{field_name}" }
    unless field
      warn "Field #{field_name} not found"
      return nil
    end
    ADLToLiraUtils.extract_field(@builder, @raw_enc, field, dest_type)
  end

  def collect_ops(_seq)
    @builder.operations_map.each { |name, op| @ops_used[name] = op }
  end

  def stmt_to_lira(stmt)
    handler_class = HANDLER_MAP[stmt.name] or raise "Unhandled statement: #{stmt.name}"
    handler_class.new(self).handle(stmt)
  end

  def generate_semantic(instr)
    return Lira::StatementSeq.new([]) if instr.code.tree.empty?

    @builder = Lira::InstructionBuilder.new(
      instr.name.to_s, [], [],
      Lira::InstructionEncoding.new(32, 0, 0, [], '', '', '')
    )
    @vars = {}
    @operand_names = collect_operand_names(instr)
    instr.code.tree.each { |stmt| stmt_to_lira(stmt) }
    seq = @builder.seq.build
    collect_ops(seq)
    seq
  end

  def generate_decode_snippets(instr, operand_vars)
    decode_snippet_names = []
    @current_instr = instr
    return [] if instr.operand_map.nil? || instr.operand_map.empty?

    instr.operand_list.each do |op_name|
      op_scope = instr.operand_map[op_name]
      next unless op_scope

      @builder = Lira::SnippetBuilder.new('temp_operand')
      @vars = {}
      @raw_enc = @builder.input(0, 32)

      op_scope.tree.each do |stmt|
        handler_class = DECODE_HANDLER_MAP[stmt.name]
        next unless handler_class

        handler_class.new(self).handle(stmt)
      end

      val = @vars[op_scope.vars[op_name]]
      @builder.output(val || @builder.const(0, 32), 0)

      snippet = @builder.build
      collect_ops(snippet.seq)
      seq_str = Lira::IrSerTxt.serialize_statement_seq(snippet.seq)

      snip_name = if @decode_cache.key?(seq_str)
                    @decode_cache[seq_str]
                  else
                    unique_name = "decode_#{@decode_snip_id}"
                    snippet.name = unique_name
                    @arch_builder.add_snippet(snippet)
                    @decode_snip_id += 1
                    @decode_cache[seq_str] = unique_name
                    unique_name
                  end
      decode_snippet_names << snip_name
    end

    decode_snippet_names
  ensure
    @current_instr = nil
  end

  def generate_encode_snippet(instr, operand_vars)
    @builder = Lira::SnippetBuilder.new('temp_encode')

    operand_values = operand_vars.each_with_index.map do |var, idx|
      width = ADLToLiraUtils.convert_type(var.type)
      width = 1 if width < 1
      @builder.input(idx, width)
    end

    base = @builder.const(0, 32)
    instr.fields.each do |field|
      hi = field.from
      lo = field.to
      width = hi - lo + 1
      width = 1 if width < 1
      field_var_name = field.value.name.to_s
      value_num = field.value.value
      if value_num
        const_val = @builder.const(value_num, width)
        const_val = @builder.extend_zero(const_val, 32) if const_val.width < 32
        shifted = @builder.lsl(const_val, @builder.const(lo, 32))
        base = @builder.orr(base, shifted)
      elsif field_var_name =~ /^f_(.+)$/
        rest = $1
        op_high = op_low = nil
        operand_name = rest

        # Split immediate fields encode a sub-range of the single `imm`
        # operand: `f_imm11_5` -> imm[11:5], `f_imm12` -> imm[12].
        if rest =~ /^imm(\d+)_(\d+)$/
          op_high = ::Regexp.last_match(1).to_i
          op_low = ::Regexp.last_match(2).to_i
          operand_name = 'imm'
        elsif rest =~ /^imm(\d+)$/
          op_high = op_low = ::Regexp.last_match(1).to_i
          operand_name = 'imm'
        end

        idx = operand_vars.index { |v| v.name.to_s == operand_name }
        if idx
          op_val = operand_values[idx]
          op_val = @builder.extend_zero(op_val, 32) if op_val.width < 32

          # Extract imm[op_high:op_low] before placing it at the field offset.
          if op_low
            op_val = @builder.lsr(op_val, @builder.const(op_low, 32)) if op_low != 0
            mask = (1 << (op_high - op_low + 1)) - 1
            op_val = @builder.and_(op_val, @builder.const(mask, 32))
          end

          shifted = @builder.lsl(op_val, @builder.const(lo, 32))
          base = @builder.orr(base, shifted)
        end
      end
    end

    @builder.output(base, 0)
    snippet = @builder.build
    collect_ops(snippet.seq)
    seq_str = Lira::IrSerTxt.serialize_statement_seq(snippet.seq)

    if @encode_cache.key?(seq_str)
      @encode_cache[seq_str]
    else
      unique_name = "encode_#{@encode_snip_id}"
      snippet.name = unique_name
      @arch_builder.add_snippet(snippet)
      @encode_snip_id += 1
      @encode_cache[seq_str] = unique_name
      unique_name
    end
  end

  def generate_constraint_snippet(const_part, const_mask)
    @builder = Lira::SnippetBuilder.new('temp_constraint')
    raw = @builder.input(0, 32)
    masked = @builder.and_(raw, @builder.const(const_mask, 32))
    result = op_cmp(:eq, false, masked, @builder.const(const_part, 32))
    @builder.output(result, 0)
    snippet = @builder.build
    collect_ops(snippet.seq)
    seq_str = Lira::IrSerTxt.serialize_statement_seq(snippet.seq)

    if @constraint_cache.key?(seq_str)
      @constraint_cache[seq_str]
    else
      unique_name = "constraint_#{@constraint_snip_id}"
      snippet.name = unique_name
      @arch_builder.add_snippet(snippet)
      @constraint_snip_id += 1
      @constraint_cache[seq_str] = unique_name
      unique_name
    end
  end

  def collect_operand_vars(instr)
    return [] if instr.operand_map.nil? || instr.operand_map.empty?

    instr.operand_list.map { |name| instr.operand_map[name].vars[name] }.compact
  end

  def collect_operand_names(instr)
    collect_operand_vars(instr).map { |v| v.name.to_s }
  end

  def convert_instruction(instr)
    operand_vars = collect_operand_vars(instr)
    operand_names = collect_operand_names(instr)
    @operand_names = operand_names
    @current_instr = instr
    semantic = generate_semantic(instr)

    decode_snippets = []
    encode_snippet = ''
    decode_snippets = generate_decode_snippets(instr, operand_vars) if !instr.operand_map.empty? && operand_vars.any?
    encode_snippet = generate_encode_snippet(instr, operand_vars) if instr.fields.any? && operand_vars.any?

    const_part = 0
    const_mask = 0
    instr.fields.each do |field|
      value_num = field.value.value
      low_bit = field.to
      high_bit = field.from
      width = high_bit - low_bit + 1
      unless value_num.nil?
        const_part |= (value_num << low_bit)
        const_mask |= (((1 << width) - 1) << low_bit)
      end
    end

    operand_sizes = operand_vars.map { |v| ADLToLiraUtils.convert_type(v.type) }
    constraint_decode = generate_constraint_snippet(const_part, const_mask)
    encoding = Lira::InstructionEncoding.new(32, const_part, const_mask, decode_snippets, encode_snippet,
                                             constraint_decode, '')
    Lira::Instruction.new(instr.name.to_s, [], operand_sizes, operand_names, encoding, semantic,
                          instr.asm_str.to_s)
  ensure
    @current_instr = nil
  end

  def build_arch
    @arch_builder = Lira::ArchBuilder.new(@arch_name, @arch_attributes)

    SimInfra.class_variable_get(:@@regfiles).each do |rf|
      regs = rf.regs.map do |reg|
        Lira::Register.new(reg.name.to_s, reg.attrs.map(&:to_s))
      end
      lira_rf = Lira::RegisterFile.new(rf.name.to_s, [], Lira::Shape.new(32, nil), regs)
      @arch_builder.add_register_file(lira_rf)
    end

    env_funcs = SimInfra.interface_functions.dup
    env_funcs.uniq! { |f| [f[:name], f[:return_types], f[:argument_types]] }
    env_funcs.each do |ef|
      inputs = ef[:argument_types].map { |t| ADLToLiraUtils.convert_type(t) }
      outputs = ef[:return_types].map { |t| ADLToLiraUtils.convert_type(t) }
      lira_ef = Lira::EnvironmentFunction.new(ef[:name].to_s, [], inputs, outputs)
      @arch_builder.add_env_func(lira_ef)
    end

    @arch_builder.add_env_func(Lira::EnvironmentFunction.new('getPC', [], [], [32]))
    @arch_builder.add_env_func(Lira::EnvironmentFunction.new('setPC', [], [32], []))

    SimInfra.class_variable_get(:@@instructions).each do |instr|
      lira_instr = convert_instruction(instr)
      @arch_builder.add_instruction(lira_instr)
    rescue StandardError => e
      warn "Skipping #{instr.name}: #{e}"
    end

    @ops_used.each_value do |op|
      @arch_builder.add_operation(op)
    end

    @arch_builder.build
  end
end

require 'optparse'
require 'pathname'

def load_target(path)
  target_path = Pathname.new(path)
  if target_path.directory?
    Dir.glob(target_path.join('*.rb')).sort.each do |file|
      require_relative file
    end
  elsif target_path.file? && target_path.extname == '.rb'
    require_relative target_path
  else
    warn "Target '#{path}' is neither a directory nor a .rb file"
    exit 1
  end
end

def extract_arch_name(_loaded_modules)
  target_name = nil
  instructions = SimInfra.class_variable_get(:@@instructions)
  target_name = instructions.first.feature.to_s unless instructions.empty?
  target_name ||= 'TargetArch'
  [target_name, []]
end

def main
  options = {
    output: 'lira.yaml'
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    opts.on('-o', '--output FILE', 'Output YAML file (default: lira.yaml)') do |f|
      options[:output] = f
    end
    opts.on('-t', '--target PATH', 'Target architecture directory or .rb file') do |p|
      options[:target] = p
    end
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!

  load_target(options[:target])

  arch_name, arch_attrs = extract_arch_name(nil)
  serializer = LiraSerializer.new(arch_name, arch_attrs)
  arch = serializer.build_arch
  Lira::ArchSerYaml.write_arch(arch, options[:output])
  puts "Serialized architecture to #{options[:output]}"
end

main if __FILE__ == $0

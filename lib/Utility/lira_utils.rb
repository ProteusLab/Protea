# lira/lira_utils.rb

require_relative '../lira/ir_ops'

module ADLToLiraUtils

  SPECIAL_REGS = %w[pc].freeze

  def self.convert_type(adl_type)
    return 32 if adl_type.nil?
    case adl_type.to_s
    when /^b(\d+)$/ then $1.to_i
    when /^u(\d+)$/, /^s(\d+)$/, /^r(\d+)$/ then $1.to_i
    else 32
    end
  end

  def self.resolve_operand(op, builder, vars, operand_names, arch_builder = nil)
    return nil if op.nil?
    return vars[op] if vars.key?(op)

    case op
    when Integer
      builder.const(op, 32)
    when SimInfra::Constant
      builder.const(op.value, 32)
    when SimInfra::Var
      resolve_var(op, builder, vars, operand_names, arch_builder)
    else
      raise "Cannot resolve operand: #{op.inspect}"
    end
  end

  def self.resolve_var(var, builder, vars, operand_names, arch_builder)
    width = convert_type(var.type)
    width = 1 if width < 1

    if (idx = operand_names.index(var.name.to_s))
      return resolve_operand_var(var, idx, width, builder, vars, arch_builder)
    end
    if SPECIAL_REGS.include?(var.name.to_s)
      return resolve_special_reg(var, builder, vars, arch_builder)
    end
    val = builder.seq.new_temp(width)
    vars[var] = val
    val
  end

  def self.resolve_operand_var(var, idx, width, builder, vars, arch_builder)
    input_val = builder.input(idx, width)
    vars[var] = input_val
    return input_val unless var.regset

    rf_name = var.regset.to_s
    rf = arch_builder.register_files.find { |rf| rf.name == rf_name }
    unless rf
      warn "Register file '#{rf_name}' not found, skipping statement"
      return nil
    end
    read_val = builder.seq.new_temp(width)
    builder.read(rf, input_val)
    vars[var] = read_val
    read_val
  end

  def self.resolve_special_reg(var, builder, vars, arch_builder)
    ef = find_env_func(arch_builder, "getPC", [], [32])
    unless ef
      warn "Environment function 'getPC' not registered"
      return nil
    end
    val = builder.env(ef, [])[0]
    vars[var] = val
    val
  end

  def self.find_env_func(arch_builder, name, input_types, output_types)
    arch_builder.environment_functions.find do |ef|
      ef.name == name && ef.inputs == input_types && ef.outputs == output_types
    end
  end

  def self.extract_field(builder, enc, field, dest_type)
    low_bit = field.to
    high_bit = field.from
    width = high_bit - low_bit + 1
    shifted = builder.lsr(enc, builder.const(low_bit, 32))
    val = builder.extract_low(shifted, width)
    dest_width = convert_type(dest_type)
    if width != dest_width
      if dest_type.to_s.start_with?('s')
        val = builder.extend_sign(val, dest_width)
      else
        val = builder.extend_zero(val, dest_width)
      end
    end
    val
  end
end

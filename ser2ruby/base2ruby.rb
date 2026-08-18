require "Utility/gen_emitter"

# Helper methods for Intermediate Representation
module IRHelper
  module_function

  def generate_regfile(emitter, regfile)
    emitter.emit_line "RegisterFile(#{regfile[:name]}) {"
    emitter.increase_indent

    regfile[:regs].each do |reg|
      attrs_str = ", #{reg[:attrs].map { |s| ":#{s}" }.join(', ')}"
      emitter.emit_line("r#{reg[:size]} #{reg[:name]}#{reg[:attrs].empty? ? '' : attrs_str}")
    end

    emitter.decrease_indent
    emitter.emit_line '}'
  end

  def generate_regfiles(regfiles)
    emitter = Utility::GenEmitter.new
    regfiles.each do |regfile|
      generate_regfile(emitter, regfile)
    end
    emitter.increase_indent_all 2
    emitter
  end

  def generate_instruction(emitter, insn)
    emitter.emit_line("Instruction(:#{insn[:name]}) {")
    emitter.increase_indent

    string_fields = insn[:fields].map do |field|
      if !field[:value][:value_num].nil?
        "field(:#{field[:value][:name]}, #{field[:from]}, #{field[:to]}, 0b#{field[:value][:value_num].to_s(2)})"
      else
        "field(:#{field[:value][:name]}, #{field[:from]}, #{field[:to]})"
      end
    end
    emitter.emit_line("encoding :#{insn[:frmt]}, [#{string_fields.join(', ')}]")
    emitter.emit_line("asm { \"#{insn[:asm_str]}\" }")

    emitter.decrease_indent
    emitter.emit_line('}')
  end

  def generate_instructions(instructions)
    emitter = Utility::GenEmitter.new
    instructions.each do |insn|
      generate_instruction(emitter, insn)
    end
    emitter.increase_indent_all 2
    emitter
  end

  def ir2ruby(ir)
    isa_name = ir[:isa_name]

    regfiles = generate_regfiles(ir[:regfiles]).to_s
    instructions = generate_instructions(ir[:instructions]).to_s


"module #{isa_name.upcase}
#{regfiles}

#{instructions}
end
"
  end
end


require 'yaml'

yaml_data = YAML.load_file('sim_lib/generated/IR.yaml')
yaml_data[:isa_name] = "RISCV"

puts IRHelper.ir2ruby(yaml_data)

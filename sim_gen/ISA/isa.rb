module SimGen
    module ISA
        module Helper
            module_function
            def find_max_reg(regfiles)
                max_reg_size = 0
                regfiles.each do |regfile|
                    regfile[:regs].each do |reg|
                        if reg[:size] > max_reg_size
                            max_reg_size = reg[:size]
                        end
                    end
                end
                max_reg_size
            end

            def find_max_operands(instructions)
                max_operands = 0
                max_size = 0
                instructions.each do |insn|
                    operands_count = 0
                    insn[:map][:tree].each do |node|
                        if node[:name] == :new_var && !node[:attrs].nil? && node[:attrs].include?(:op)
                            operands_count += 1
                            max_size = Utility.get_type(node[:oprnds][0][:type]).bitsize if Utility.get_type(node[:oprnds][0][:type]).bitsize > max_size
                        end
                    end
                    max_operands = operands_count if operands_count > max_operands
                end
                [max_operands, max_size]
            end

            def generate_fields_struct(max_operands, max_size)
                emitter = Utility::GenEmitter.new
                for i in 0...max_operands
                    emitter.emit_line("uint#{max_size}_t operand#{i};")
                end
                emitter.increase_indent_all(2)
                emitter
            end

            def generate_instruction_struct(input_ir)
                max_operands, max_size = find_max_operands(input_ir[:instructions])
                fields_struct = generate_fields_struct(max_operands, max_size)
"struct Instruction {
  Opcode m_opc;
#{fields_struct.to_s}
};"
            end

            def get_addr_type(instructions)
                instructions.each { |insn| 
                    insn[:code][:tree].each { |node|
                        return node[:oprnds][0][:type] if node[:name] == :writeMem || node[:name] == :readMem 
                    }
                }
            end

            def is_terminator_instruction(insn)
                insn[:code][:tree].each { |node|
                    return true if node[:name] == :branch || node[:name] == :sysCall
                }
                false
            end

            def generate_is_terminator_function(input_ir)
                emitter = Utility::GenEmitter.new
                emitter.emit_line("inline constexpr bool isTerminator(Opcode opc) {")
                emitter.increase_indent
                emitter.emit_line("switch (opc) {")
                emitter.increase_indent
                input_ir[:instructions].each do |insn|
                    emitter.emit_line("case Opcode::k#{insn[:name].to_s.upcase}:") if is_terminator_instruction(insn)
                end
                emitter.emit_line("return true;")
                emitter.decrease_indent
                emitter.emit_line("default:")
                emitter.increase_indent
                emitter.emit_line("return false;")
                emitter.decrease_indent
                emitter.emit_line("}")
                emitter.decrease_indent
                emitter.emit_line("}")
                emitter
            end
        end
    end
end

module SimGen
    module ISA
        module Header
            module_function

            def generate_isa_header(input_ir)
                type = Helper.get_addr_type input_ir[:instructions]
                type_str = Utility::HelperCpp::gen_type type

                instruction_struct = Helper.generate_instruction_struct(input_ir)
                is_terminator_function = Helper.generate_is_terminator_function(input_ir)
                max_xlen = SimGen::Helper::find_max_xlen(input_ir[:regfiles])
"#ifndef GENERATED_#{input_ir[:isa_name].upcase}_ISA_HH_INCLUDED
#define GENERATED_#{input_ir[:isa_name].upcase}_ISA_HH_INCLUDED

#include <cstdint>

namespace prot::isa {
using Addr = #{type_str};
using Word = uint#{max_xlen}_t;

enum class Opcode : uint32_t {
#{input_ir[:instructions].map { |insn| "  k#{insn[:name].to_s.upcase}," }.join("\n")}
};

#{instruction_struct.to_s}

#{is_terminator_function.to_s}

inline constexpr std::size_t getILen(Opcode opc) {
  switch (opc) {
    #{input_ir[:instructions].map { |insn| "case Opcode::k#{insn[:name].to_s.upcase}: return #{insn[:XLEN]};" }.join("\n    ")}
    default: return 4;
  }
}

} // namespace prot::isa

#endif // GENERATED_#{input_ir[:isa_name].upcase}_ISA_HH_INCLUDED"
            end
        end
    end
end

module SimGen
  module ISA
    module Helper
      module_function

      def find_max_regsize(regfiles)
        max = 0
        regfiles.each do |rf|
          rf.regs.each do |reg|
            max = rf.reg_size.lanes_base if rf.reg_size.lanes_base > max
          end
        end
        max
      end

      def find_max_operands(instructions)
        max_operands = 0
        max_size = 0
        instructions.each do |insn|
          size = insn.operand_sizes.size
          max_operands = size if size > max_operands
          insn.operand_sizes.each do |s|
            max_size = s if s > max_size
          end
        end
        [max_operands, max_size]
      end

      def generate_fields_struct(max_operands, max_size)
        emitter = Utility::GenEmitter.new
        (0...max_operands).each do |i|
          emitter.emit_line("uint#{max_size}_t operand#{i};")
        end
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_instruction_struct(instructions)
        max_operands, max_size = find_max_operands(instructions)
        fields_struct = generate_fields_struct(max_operands, max_size)
        <<~CPP
          struct Instruction {
            Opcode m_opc;
            #{fields_struct.to_s}
          };
        CPP
      end

      def is_terminator_instruction(insn)
        seq = insn.semantic
        return false unless seq && seq.stmts
        seq.stmts.any? do |stmt|
          stmt.kind == 'env' && (stmt.specifier == 'setPC' || stmt.specifier == 'sysCall')
        end
      end

      def generate_is_terminator_function(instructions)
        emitter = Utility::GenEmitter.new
        emitter.emit_line("inline constexpr bool isTerminator(Opcode opc) {")
        emitter.increase_indent
        emitter.emit_line("switch (opc) {")
        emitter.increase_indent
        instructions.each do |insn|
          if is_terminator_instruction(insn)
            emitter.emit_line("case Opcode::k#{insn.name.to_s.upcase}: return true;")
          end
        end
        emitter.emit_line("default: return false;")
        emitter.decrease_indent
        emitter.emit_line("}")
        emitter.decrease_indent
        emitter.emit_line("}")
        emitter
      end

      def get_addr_type_from_instructions(instructions)
        instructions.each do |insn|
          seq = insn.semantic
          next unless seq && seq.stmts
          seq.stmts.each do |stmt|
            if stmt.kind == 'env' && (stmt.specifier == 'readMem' || stmt.specifier == 'writeMem')
              addr_input = stmt.inputs[0]
              return 32
            end
          end
        end
        32 # fallback
      end
    end

    module Header
      module_function

      def generate_isa_header(arch)
        isa_name = arch.name
        regfiles = arch.register_files
        instructions = arch.instructions

        max_xlen = Helper.find_max_regsize(regfiles)
        addr_width = Helper.get_addr_type_from_instructions(instructions)
        addr_type = case addr_width
                    when 8 then "uint8_t"
                    when 16 then "uint16_t"
                    when 32 then "uint32_t"
                    when 64 then "uint64_t"
                    else "uint32_t"
                    end

        opcode_enum = instructions.map { |insn| "  k#{insn.name.to_s.upcase}," }.join("\n")
        instruction_struct = Helper.generate_instruction_struct(instructions)
        is_terminator_function = Helper.generate_is_terminator_function(instructions)

        get_ilen_lines = instructions.map do |insn|
        enc_size = insn.encoding.encoded_size || 32
        len = enc_size / 8
        "case Opcode::k#{insn.name.to_s.upcase}: return #{len};"
        end.join("\n    ")

        <<~CPP
          #ifndef GENERATED_#{isa_name.upcase}_ISA_HH_INCLUDED
          #define GENERATED_#{isa_name.upcase}_ISA_HH_INCLUDED

          #include <cstdint>

          namespace prot::isa {
            using Addr = #{addr_type};
            using Word = uint#{max_xlen}_t;

            enum class Opcode : uint32_t {
          #{opcode_enum}
            };

          #{instruction_struct}

          #{is_terminator_function.to_s}

            inline constexpr std::size_t getILen(Opcode opc) {
              switch (opc) {
                #{get_ilen_lines}
                default: return 4;
              }
            }

          } // namespace prot::isa

          #endif // GENERATED_#{isa_name.upcase}_ISA_HH_INCLUDED
        CPP
      end
    end
  end
end

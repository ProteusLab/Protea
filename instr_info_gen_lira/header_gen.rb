# instr_info_gen_lira/header_gen.rb
# Emits instr_info.hh: an LLVM-MCInstrDesc-like constexpr table of per-instruction
# classification flags and metadata, indexed by Opcode.

require_relative '../lib/lira/classify'

module InstrInfoGen
  module Header
    module_function

    def max_operands(instructions)
      instructions.map { |insn| insn.operand_sizes.size }.max || 0
    end

    def opcode_name(insn)
      "k#{insn.name.to_s.upcase}"
    end

    def camel(sym)
      sym.to_s.split('_').map(&:capitalize).join
    end

    def flag_constant(sym)
      "k#{camel(sym)}"
    end

    def accessor_name(sym)
      c = camel(sym)
      c[0].downcase + c[1..]
    end

    def flags_expr(flag_syms)
      return '0u' if flag_syms.empty?
      flag_syms.map { |sym| "flag::#{flag_constant(sym)}" }.join(' | ')
    end

    def role_expr(roles, i)
      "Role::#{flag_constant(roles[i] || :imm)}"
    end

    def desc_row(insn, max_ops)
      desc = Lira::Classify.describe(insn)
      names = (0...max_ops).map { |i| "\"#{insn.operand_names[i]}\"" }.join(', ')
      sizes = (0...max_ops).map { |i| insn.operand_sizes[i] || 0 }.join(', ')
      roles = (0...max_ops).map { |i| role_expr(desc.roles, i) }.join(', ')
      encoded_size = insn.encoding.encoded_size || 32
      const_part = format('0x%x', insn.encoding.const_encoding_part)
      const_mask = format('0x%x', insn.encoding.const_mask)
      flags = flags_expr(desc.flags)
      "  {\"#{insn.name}\", #{insn.operand_names.size}, {#{names}}, {#{sizes}}, {#{roles}}, " \
        "#{encoded_size}, #{desc.mem_width}, #{const_part}, #{const_mask}, #{flags}, \"#{desc.ext}\"},"
    end

    def generate(arch)
      name = arch.name
      instructions = arch.instructions
      max_ops = max_operands(instructions)
      max_encoded_size = instructions.map { |insn| insn.encoding.encoded_size || 32 }.max || 32
      const_type = max_encoded_size > 32 ? 'uint64_t' : 'uint32_t'

      opcode_enum = instructions.map { |insn| "  #{opcode_name(insn)}," }.join("\n")

      flag_constants = Lira::Classify::FLAGS.each_with_index.map do |sym, i|
        "inline constexpr uint32_t #{flag_constant(sym)} = 1u << #{i};"
      end.join("\n")

      flag_accessors = Lira::Classify::FLAGS.map do |sym|
        "  [[nodiscard]] constexpr bool #{accessor_name(sym)}() const { return flags & flag::#{flag_constant(sym)}; }"
      end.join("\n")

      role_enum = Lira::Classify::ROLES.each_with_index.map do |sym, i|
        "#{flag_constant(sym)} = #{i}"
      end.join(', ')

      desc_rows = instructions.map { |insn| desc_row(insn, max_ops) }.join("\n")

      <<~CPP
        #ifndef GENERATED_#{name.upcase}_INSTR_INFO_HH_INCLUDED
        #define GENERATED_#{name.upcase}_INSTR_INFO_HH_INCLUDED

        // Per-instruction classification flags and metadata derived from the LIRA
        // semantic IR (env setPC/readMem*/writeMem*/sysCall statements).
        //
        // The Opcode enum duplicates the sim/asm isa.hh enums; all three are emitted
        // from the same instruction list in the same order, so values are
        // static_cast-interconvertible.
        //
        // The extension each instruction belongs to (ext) is not derivable from
        // the semantic; it is preserved by the lowering in the LIRA instruction
        // attributes as an { ext: <feature> } mapping and read back here.
        // Everything else is derived from the semantic IR.
        //
        // Known limitations of the derived-only classification:
        //  - instructions with empty semantics (ebreak, fence) carry no flags,
        //    all-imm roles, and mem_width 0;
        //  - isCallLike is opcode-static (`jal x0` still reports call-like).

        #include <array>
        #include <cstddef>
        #include <cstdint>
        #include <string_view>

        namespace prot::instr_info {

        enum struct Opcode : uint32_t {
        #{opcode_enum}
        };

        // Per-operand role, in operand_names order.
        enum struct Role : uint8_t { #{role_enum} };

        inline constexpr std::size_t kNumOpcodes = #{instructions.size};
        inline constexpr std::size_t kMaxOperands = #{max_ops};

        namespace flag {
        #{flag_constants}
        } // namespace flag

        struct InstrDesc {
          std::string_view name;
          uint8_t num_operands;
          std::array<std::string_view, kMaxOperands> operand_names; // "" padded
          std::array<uint8_t, kMaxOperands> operand_sizes;          // bit widths, 0 padded
          std::array<Role, kMaxOperands> operand_roles;             // kImm padded
          uint8_t encoded_size;                                     // bits
          uint8_t mem_width;                                        // access size in bytes; 0 if not a mem op
          #{const_type} const_encoding_part;
          #{const_type} const_mask;
          uint32_t flags;
          std::string_view ext;                                     // extension id (e.g. "RV32I"); "" if unknown

        #{flag_accessors}
          [[nodiscard]] constexpr std::size_t encodedBytes() const { return encoded_size / 8u; }
        };

        inline constexpr std::array<InstrDesc, kNumOpcodes> kInstrDescs = {{
        #{desc_rows}
        }};

        [[nodiscard]] inline constexpr const InstrDesc &get(Opcode opc) {
          return kInstrDescs[static_cast<std::size_t>(opc)];
        }

        } // namespace prot::instr_info

        #endif // GENERATED_#{name.upcase}_INSTR_INFO_HH_INCLUDED
      CPP
    end
  end
end

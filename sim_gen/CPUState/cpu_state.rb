# frozen_string_literal: true

require 'lib/Utility/gen_emitter'
require 'Utility/helper_cpp'

# SimGen - simulation code generator
module SimGen
  # SimGen::CPUState - methods for CPUState header generation
  module CPUState
    # Helper methods for CPUState generation
    module Helper
      module_function

      def increase_icount_func
        emitter = Utility::GenEmitter.new
        emitter.emit_line('// Function to increase instruction count')
        emitter.emit_line('void increaseICount() {')
        emitter.increase_indent
        emitter.emit_line('++m_icount;')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.increase_indent_all(2)
        emitter
      end

      def find_pc_reg(regfiles)
        regfiles.each do |regfile|
          regfile[:regs].each do |reg|
            return reg if reg[:attrs].include? :pc
          end
        end
        raise 'PC register not found in the register files'
      end

      def generate_pc_decl(regfiles)
        emitter = Utility::GenEmitter.new
        pc_reg = find_pc_reg(regfiles)
        emitter.emit_line('// Program Counter')
        emitter.emit_line("#{Utility::HelperCpp.gen_type(pc_reg[:size])} m_pc;")
        emitter.emit_blank_line
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_pc_functions(regfiles)
        emitter = Utility::GenEmitter.new
        pc_reg = find_pc_reg(regfiles)
        emitter.emit_line('// Set PC function')
        emitter.emit_line("void setPC(const #{Utility::HelperCpp.gen_type(pc_reg[:size])} value) {")
        emitter.increase_indent
        emitter.emit_line('m_pc = value;')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.emit_blank_line
        emitter.emit_line('// Read PC function')
        emitter.emit_line("#{Utility::HelperCpp.gen_type(pc_reg[:size])} getPC() const {")
        emitter.increase_indent
        emitter.emit_line('return m_pc;')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.emit_blank_line
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_cpu_regsets(regfiles)
        emitter = Utility::GenEmitter.new
        regfiles.each do |regfile|
          regfile_size = regfile[:regs].size - regfile[:regs].count { |reg| reg[:attrs].include? :pc }
          emitter.emit_line("// Register file: #{regfile[:name]}")
          regsize = regfile[:regs][0][:size]
          array_str = "std::array<#{Utility::HelperCpp.gen_type(regsize)}, #{regfile_size}> m_#{regfile[:name]}{};"
          emitter.emit_line(array_str)
          emitter.emit_blank_line
        end
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_if_zero_reg_check(emitter, regfile)
        regfile[:regs].each_with_index do |reg, reg_index|
          if reg[:attrs].include? :zero
            emitter.emit_line("if (reg == #{reg_index}) return; // #{reg[:name]} is zero register")
          end
        end
      end

      def generate_set_reg_functions(regfiles)
        emitter = Utility::GenEmitter.new
        regfiles.each do |regfile|
          emitter.emit_line("// Set register function for #{regfile[:name]}")
          emitter.emit_line('template<std::integral T>')
          emitter.emit_line("void set#{regfile[:name]}(const std::size_t reg, const T value) {")
          emitter.increase_indent
          generate_if_zero_reg_check(emitter, regfile)
          emitter.emit_line("m_#{regfile[:name]}[reg] = value;")
          emitter.decrease_indent
          emitter.emit_line('}')
          emitter.emit_blank_line
        end
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_read_reg_functions(regfiles)
        emitter = Utility::GenEmitter.new
        regfiles.each do |regfile|
          emitter.emit_line("// Read register function for #{regfile[:name]}")
          emitter.emit_line('template<std::integral T>')
          emitter.emit_line("T get#{regfile[:name]}(const std::size_t reg) const {")
          emitter.increase_indent
          emitter.emit_line("return static_cast<T>(m_#{regfile[:name]}[reg]);")
          emitter.decrease_indent
          emitter.emit_line('}')
          emitter.emit_blank_line
        end
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_do_exit_func
        emitter = Utility::GenEmitter.new
        emitter.emit_line('// Function to stop the CPU execution')
        emitter.emit_line('void doExit() {')
        emitter.increase_indent
        emitter.emit_line('m_exit_code = static_cast<int>(m_XRegs[10]);')
        emitter.emit_line('m_finished = true;')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_dump_func(regfiles)
        emitter = Utility::GenEmitter.new
        emitter.emit_line("void CPU::dump(std::ostream &ost) const {")
        emitter.increase_indent

        emitter.emit_line("fmt::println(ost, \"---CPU STATE DUMP---\");")
        regfiles.each do |regfile|
          regfile[:regs].each do |register|
            emitter.emit_line("fmt::print(ost, \"X[{:02}] = {:#010x} \", effIdx, get#{regfile[:name]}());")
          end
        end

        emitter
      end
    end
  end
end

# SimGen - simulation code generator
module SimGen
  # SimGen::CPUState - methods for CPUState header generation
  module CPUState
    module Header
      module_function

      def generate_cpu_state(input_ir)
        pc_decl = Helper.generate_pc_decl(input_ir[:regfiles])
        pc_functions = Helper.generate_pc_functions(input_ir[:regfiles])
        regsets_decl = Helper.generate_cpu_regsets(input_ir[:regfiles])
        setreg_funcs = Helper.generate_set_reg_functions(input_ir[:regfiles])
        readreg_funcs = Helper.generate_read_reg_functions(input_ir[:regfiles])
        do_exit_func = Helper.generate_do_exit_func
        increase_icount_func = Helper.increase_icount_func

        base_type = Utility::HelperCpp.gen_type input_ir[:regfiles][0][:regs][0][:size]
"#ifndef GENERATED_#{input_ir[:isa_name].upcase}_CPUSTATE_HH_INCLUDED
#define GENERATED_#{input_ir[:isa_name].upcase}_CPUSTATE_HH_INCLUDED

#include \"memory.hh\"
extern \"C\" {
#include \"softfloat.h\"
}

#include <array>
#include <cstddef>
#include <cstdint>

namespace prot::memory {
class Memory;
} // prot::memory

namespace prot::state {
using namespace prot::memory;

class CPU final {
public:
#{regsets_decl}
#{pc_decl}
  // Instruction count
  std::size_t m_icount{0};

  // Pointer to memory
  Memory *m_memory{nullptr};

  // Finished flag
  bool m_finished{false};

  int m_exit_code{0};

  // FP rounding mode (fcsr.frm); fflags are backed by softfloat_exceptionFlags
  std::uint64_t m_frm{0};

  static uint_fast8_t frmToSoftfloat(std::uint64_t frm) {
    switch (frm) {
    case 0: return softfloat_round_near_even;
    case 1: return softfloat_round_minMag;
    case 2: return softfloat_round_min;
    case 3: return softfloat_round_max;
    case 4: return softfloat_round_near_maxMag;
    default: return softfloat_round_near_even;
    }
  }

  std::uint64_t readCSR(std::uint64_t csr) {
    switch (csr) {
    case 0x001: return softfloat_exceptionFlags & 0x1f;
    case 0x002: return m_frm & 0x7;
    case 0x003: return ((m_frm & 0x7) << 5) | (softfloat_exceptionFlags & 0x1f);
    default: return 0;
    }
  }

  void writeCSR(std::uint64_t csr, std::uint64_t val) {
    switch (csr) {
    case 0x001:
      softfloat_exceptionFlags = val & 0x1f;
      break;
    case 0x002:
      m_frm = val & 0x7;
      softfloat_roundingMode = frmToSoftfloat(m_frm);
      break;
    case 0x003:
      softfloat_exceptionFlags = val & 0x1f;
      m_frm = (val >> 5) & 0x7;
      softfloat_roundingMode = frmToSoftfloat(m_frm);
      break;
    default:
      break;
    }
  }

  explicit CPU(Memory *mem) : m_memory(mem) {}

#{setreg_funcs}
#{readreg_funcs}
#{pc_functions}
  #{base_type} getSysCallNum() const;
  #{base_type} getSysCallArg(std::size_t num) const;
  #{base_type} getSysCallRet() const;
  void emulateSysCall();

#{do_exit_func}

#{increase_icount_func}
};

} // prot::state

#endif // GENERATED_#{input_ir[:isa_name].upcase}_CPUSTATE_HH_INCLUDED
"
      end
    end

    module TranslationUnit
      module_function

      def generate_cpu_state(input_ir)
        # Currently, no implementation is needed for the CPUState translation unit.
        ''
      end
    end
  end
end

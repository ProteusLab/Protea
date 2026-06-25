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
        regfiles.each do |rf|
          rf.regs.each do |reg|
            return [reg, rf] if reg.attributes.any? { |a| a.to_s == 'pc' }
          end
        end
        raise 'PC register not found in the register files'
      end

      def generate_pc_decl(regfiles)
        emitter = Utility::GenEmitter.new
        pc_reg, = find_pc_reg(regfiles)
        emitter.emit_line('// Program Counter')
        emitter.emit_line("#{Utility::HelperCpp.gen_type(regfiles[0].reg_size.lanes_base)} m_pc;")
        emitter.emit_blank_line
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_pc_functions(regfiles)
        emitter = Utility::GenEmitter.new
        pc_reg, = find_pc_reg(regfiles)
        pc_type = Utility::HelperCpp.gen_type(regfiles[0].reg_size.lanes_base)
        emitter.emit_line('// Set PC function')
        emitter.emit_line("void setPC(const #{pc_type} value) {")
        emitter.increase_indent
        emitter.emit_line('m_pc = value;')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.emit_blank_line
        emitter.emit_line('// Read PC function')
        emitter.emit_line("#{pc_type} getPC() const {")
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
        regfiles.each do |rf|
          pc_count = rf.regs.count { |r| r.attributes.any? { |a| a.to_s == 'pc' } }
          rf_size = rf.regs.size - pc_count
          emitter.emit_line("// Register file: #{rf.name}")
          regsize = rf.reg_size.lanes_base
          array_str = "std::array<#{Utility::HelperCpp.gen_type(regsize)}, #{rf_size}> m_#{rf.name}{};"
          emitter.emit_line(array_str)
          emitter.emit_blank_line
        end
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_if_zero_reg_check(emitter, rf)
        rf.regs.each_with_index do |reg, reg_index|
            if reg.attributes.any? { |a| a.to_s == 'zero' }
            emitter.emit_line("if (reg == #{reg_index}) return; // #{reg.name} is zero register")
          end
        end
      end

      def generate_set_reg_functions(regfiles)
        emitter = Utility::GenEmitter.new
        regfiles.each do |rf|
          emitter.emit_line("// Set register function for #{rf.name}")
          emitter.emit_line('template<std::integral T>')
          emitter.emit_line("void set#{rf.name}(const std::size_t reg, const T value) {")
          emitter.increase_indent
          generate_if_zero_reg_check(emitter, rf)
          emitter.emit_line("m_#{rf.name}[reg] = value;")
          emitter.decrease_indent
          emitter.emit_line('}')
          emitter.emit_blank_line
        end
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_read_reg_functions(regfiles)
        emitter = Utility::GenEmitter.new
        regfiles.each do |rf|
          emitter.emit_line("// Read register function for #{rf.name}")
          emitter.emit_line('template<std::integral T>')
          emitter.emit_line("T get#{rf.name}(const std::size_t reg) const {")
          emitter.increase_indent
          emitter.emit_line("return static_cast<T>(m_#{rf.name}[reg]);")
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
        emitter.emit_line('void doExit(isa::Word code) {')
        emitter.increase_indent
        emitter.emit_line('m_finished = true;')
        emitter.emit_line('m_code = code;')
        emitter.emit_line("fmt::println(\"Exiting with code {}...\", code);")
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.increase_indent_all(2)
        emitter
      end

      def gen_input_args(args)
        args.map { |arg| Utility::HelperCpp.gen_type(arg) }.join(', ')
      end

      def generate_interface_func(interface_functions)
        emitter = Utility::GenEmitter.new

        emitter.emit_line('// Interface functions')
        interface_functions.each do |ifunc|

          if ifunc[:return_types].size == 0
            emitter.emit_line("void #{ifunc[:name]}(#{gen_input_args(ifunc[:argument_types])});")
          elsif ifunc[:return_types].size == 1
            emitter.emit_line("#{gen_input_args(ifunc[:return_types])} #{ifunc[:name]}(#{gen_input_args(ifunc[:argument_types])});")
          else
            emitter.emit_line("std::tuple<#{gen_input_args(ifunc[:return_types])}> #{ifunc[:name]}(#{gen_input_args(ifunc[:argument_types])});")
          end
        end
        emitter.emit_blank_line
        emitter.increase_indent_all(2)
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

      def generate_cpu_state(arch)
        regfiles = arch.register_files
        pc_decl = Helper.generate_pc_decl(regfiles)
        pc_functions = Helper.generate_pc_functions(regfiles)
        regsets_decl = Helper.generate_cpu_regsets(regfiles)
        setreg_funcs = Helper.generate_set_reg_functions(regfiles)
        readreg_funcs = Helper.generate_read_reg_functions(regfiles)
        do_exit_func = Helper.generate_do_exit_func
        increase_icount_func = Helper.increase_icount_func
        iface = arch.environment_functions.reject { |ef| %w[setPC getPC].include?(ef.name) }
        iface_hashes = iface.map { |ef| { name: ef.name, argument_types: ef.inputs, return_types: ef.outputs } }
        interface_func = Helper.generate_interface_func(iface_hashes)

        base_type = Utility::HelperCpp.gen_type regfiles[0].reg_size.lanes_base
        isa_name = arch.name
"#ifndef GENERATED_#{isa_name.upcase}_CPUSTATE_HH_INCLUDED
#define GENERATED_#{isa_name.upcase}_CPUSTATE_HH_INCLUDED

#include \"memory.hh\"

#include <array>
#include <cstddef>
#include <cstdint>
#include <fmt/core.h>
#include <fmt/ostream.h>

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

  // Exit code
  isa::Word m_code{0};

  explicit CPU(Memory *mem) : m_memory(mem) {}

#{setreg_funcs}
#{readreg_funcs}
#{pc_functions}
#{interface_func}
#{do_exit_func}

#{increase_icount_func}
};

} // prot::state

#endif // GENERATED_#{isa_name.upcase}_CPUSTATE_HH_INCLUDED
"
      end
    end

    module TranslationUnit
      module_function

      def generate_cpu_state(arch)
        # Currently, no implementation is needed for the CPUState translation unit.
        ''
      end
    end
  end
end

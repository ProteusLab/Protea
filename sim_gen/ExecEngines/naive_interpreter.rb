module SimGen
  module NaiveInterpreter
    module Header
      module_function

      def generate_naive_interpreter(input_ir)
        "#ifndef GENERATED_#{input_ir[:isa_name].upcase}_INTERPRETER_HH_INCLUDED
#define GENERATED_#{input_ir[:isa_name].upcase}_INTERPRETER_HH_INCLUDED

#include \"base_exec_engine.hh\"

namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

class Interpreter : public ExecEngine {
public:
void execute(CPU &cpu, const Instruction &insn) override;
};
} // namespace generated::#{input_ir[:isa_name].downcase}::engine

#endif // GENERATED_#{input_ir[:isa_name].downcase}_INTERPRETER_HH_INCLUDED
"
      end
    end
  end
end

module SimGen
  module NaiveInterpreter
    module TranslationUnit
      module_function

      def map_operands(insn)
        operands = {}
        cnt = 0
        insn[:map][:tree].each do |node|
          if node[:name] == :new_var && !node[:attrs].nil? && node[:attrs].include?(:op)
            operands[node[:oprnds][0][:name]] = "insn.operand#{cnt}"
            cnt += 1
          end
        end
        operands[:pc] = 'cpu.getPC()'
        operands
      end

      def cpu_write_reg(dst)
        "cpu.set#{dst[:regset]}"
      end

      def cpu_read_reg(dst)
        "cpu.get#{dst[:regset]}"
      end

      def cpu_write_mem(addr, val)
        "cpu.m_memory->write(#{addr}, #{val})"
      end

      def cpu_read_mem(dst, addr)
        "cpu.m_memory->read<#{Utility::HelperCpp.gen_small_type(dst[:type])}>(#{addr})"
      end

      def generate_exec_function(instruction, funcs)
        emitter = Utility::GenEmitter.new
        operand_map = map_operands(instruction)

        emitter.emit_line("void do#{instruction[:name].to_s.upcase}(CPU &cpu, const Instruction &insn) {")
        emitter.increase_indent

        gen = CodeGen::CppGenerator.new(emitter, operand_map)
        funcs_name = funcs.map { |func| func[:name] }
        instruction[:code][:tree].each do |node|
          if funcs_name.include?(node[:name])
            emitter.emit_line("cpu.#{node[:name]}(#{node[:oprnds].map { |op| op[:name] }.join(', ')});")
          else
            gen.generate_statement(node)
          end
        end
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.emit_blank_line
        emitter
      end

      def generate_exec_functions(input_ir)
        emitter = Utility::GenEmitter.new
        input_ir[:instructions].each do |instruction|
          temp_emitter = generate_exec_function(instruction, input_ir[:interface_functions])
          emitter.concat(temp_emitter)
        end
        emitter
      end

      def is_branch_instruction(instruction)
        for node in instruction[:code][:tree]
          return true if node[:name] == :branch
        end
        false
      end

      def generate_function_is_branch(input_ir)
        emitter = Utility::GenEmitter.new
        emitter.emit_line('bool isBranchInstruction(const Instruction &insn) {')
        emitter.increase_indent
        emitter.emit_line('switch (insn.m_opc) {')
        emitter.increase_indent
        input_ir[:instructions].each do |instruction|
          emitter.emit_line("case Opcode::k#{instruction[:name].to_s.upcase}:") if is_branch_instruction(instruction)
        end
        emitter.emit_line('return true;')
        emitter.decrease_indent
        emitter.emit_line('default:')
        emitter.increase_indent
        emitter.emit_line('return false;')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.decrease_indent
        emitter.emit_line('}')
        emitter.increase_indent_all(2)
        emitter
      end

      def generate_naive_interpreter(input_ir)
        is_branch_function = generate_function_is_branch(input_ir)
        exec_functions = generate_exec_functions(input_ir)

        "#include \"naive_interpreter.hh\"

#include <cassert>

namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

namespace {
#{is_branch_function}

#{exec_functions}

template <typename T>
constexpr auto toUnderlying(T val)
  requires std::is_enum_v<T>
{
  return static_cast<std::underlying_type_t<T>>(val);
}

class ExecHandlersMap {
public:
  using ExecHandler = void (*)(CPU &cpu, const Instruction &insn);

private:
  std::array<ExecHandler, #{input_ir[:instructions].size}> m_handlers{};

public:
  constexpr ExecHandlersMap() {
    #{input_ir[:instructions].map { |insn| "m_handlers[toUnderlying(Opcode::k#{insn[:name].to_s.upcase})] = &do#{insn[:name].to_s.upcase};" }.join("\n    ")}
  }

  [[nodiscard]] ExecHandler get(Opcode opcode) const {
    assert(toUnderlying(opcode) < m_handlers.size());
    auto toRet = m_handlers[toUnderlying(opcode)];
    assert(toRet != nullptr);
    return toRet;
  }
};

constexpr ExecHandlersMap kExecHandlers{};
} // namespace

void Interpreter::execute(CPU &cpu, const Instruction &insn) {
  const auto handler = kExecHandlers.get(insn.m_opc);

  auto oldPC = cpu.getPC();

  handler(cpu, insn);

  if (!isBranchInstruction(insn)) {
    cpu.setPC(oldPC + getILen(insn.m_opc));
  }
}

} // namespace prot::engine
"
      end
    end
  end
end

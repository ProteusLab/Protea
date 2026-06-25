require_relative '../cpp_gen'

module SimGen
  module NaiveInterpreter
    module Header
      module_function

      def generate_naive_interpreter(arch)
<<~CPP
  #ifndef GENERATED_#{arch.name.upcase}_INTERPRETER_HH_INCLUDED
  #define GENERATED_#{arch.name.upcase}_INTERPRETER_HH_INCLUDED

  #include "base_exec_engine.hh"

  namespace prot::engine {
    class Interpreter : public ExecEngine {
    public:
      void execute(CPU &cpu, const Instruction &insn) override;
    };
  }

  #endif
CPP
      end
    end

    module TranslationUnit
      module_function

      def generate_naive_interpreter(arch)
        exec_functions = []
        branch_insns = []

        arch.instructions.each do |insn|
          name = insn.name.to_s.upcase
          seq = insn.semantic

          if seq && seq.stmts.any?
            translator = LiraCppGen::Translator.new(seq, :execute, 2)
            body = translator.translate
          else
            body = "  // no semantic"
          end

          exec_functions <<
<<~CPP
  void do#{name}(CPU &cpu, const Instruction &insn) {
    #{body}
  }
CPP

          if seq && seq.stmts.any? && seq.stmts.any? { |s| s.kind == 'env' && s.specifier == 'setPC' }
            branch_insns << "case Opcode::k#{name}: return true;"
          end
        end

        is_branch =
<<~CPP
bool isBranchInstruction(const Instruction &insn) {
  switch (insn.m_opc) {
    #{branch_insns.join("\n")}
    default: return false;
  }
}
CPP

        handlers_init = arch.instructions.map do |insn|
          "m_handlers[toUnderlying(Opcode::k#{insn.name.to_s.upcase})] = &do#{insn.name.to_s.upcase};"
        end.join("\n    ")

<<~CPP
#include "naive_interpreter.hh"
#include "base_ops.h"

#include <cassert>
#include <array>

namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

namespace {
#{is_branch}
#{exec_functions.join("\n\n")}

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
  std::array<ExecHandler, #{arch.instructions.size}> m_handlers{};
public:
  constexpr ExecHandlersMap() {
    #{handlers_init}
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
  if (!handler) return;
  auto oldPC = cpu.getPC();
  handler(cpu, insn);
  if (!isBranchInstruction(insn))
    cpu.setPC(oldPC + getILen(insn.m_opc));
}
}
CPP
      end
    end
  end
end

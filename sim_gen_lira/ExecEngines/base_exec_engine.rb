require "sim_gen/Utility/sim_utility"

module SimGen
  module BaseExecEngine
    module Header
      module_function

      def generate_base_exec_engine(arch)
<<~CPP
#ifndef GENERATED_#{arch.name.upcase}_EXEC_ENGINE_HH_INCLUDED
#define GENERATED_#{arch.name.upcase}_EXEC_ENGINE_HH_INCLUDED

#include \"cpu_state.hh\"
#include \"isa.hh\"
#include \"memory.hh\"

namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

struct ExecEngine {
  virtual ~ExecEngine() = default;

  virtual void execute(CPU &cpu, const Instruction &insn) = 0;
  virtual void step(CPU &cpu);
};
} // namespace prot::engine

#endif // GENERATED_#{arch.name.upcase}_EXEC_ENGINE_HH_INCLUDED
CPP
      end
    end

    module TranslationUnit
      module_function

      def generate_base_exec_engine(arch)
<<~CPP
#include "base_exec_engine.hh"
#include "memory.hh"
#include "decoder.hh"

namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

void ExecEngine::step(CPU &cpu) {
  const auto bytes = cpu.m_memory->read<uint32_t>(cpu.getPC());
  auto instr_opt = decoder::decode(bytes);
  if (instr_opt) {
    execute(cpu, *instr_opt);
    cpu.increaseICount();
  }
}
} // namespace prot::engine
CPP
       end
    end
  end
end

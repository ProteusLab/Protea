require 'sim_gen/Utility/sim_utility'

module SimGen
  module BaseExecEngine
    module Header
      module_function

      def generate_base_exec_engine(input_ir)
        "#ifndef GENERATED_#{input_ir[:isa_name].upcase}_EXEC_ENGINE_HH_INCLUDED
#define GENERATED_#{input_ir[:isa_name].upcase}_EXEC_ENGINE_HH_INCLUDED

#include \"cpu_state.hh\"
#include \"isa.hh\"
#include \"memory.hh\"
extern \"C\" {
#include \"softfloat.h\"
}


namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

struct ExecEngine {
  virtual ~ExecEngine() = default;

  virtual void execute(CPU &cpu, const Instruction &insn) = 0;
  virtual void step(CPU &cpu);
};
} // namespace prot::engine

#endif // GENERATED_#{input_ir[:isa_name].upcase}_EXEC_ENGINE_HH_INCLUDED
"
      end
    end

    module TranslationUnit
      module_function

      def generate_base_exec_engine(input_ir)
        max_xlen = SimGen::Helper.find_max_xlen(input_ir[:regfiles])

        "#include \"base_exec_engine.hh\"
#include \"memory.hh\"
#include \"decoder.hh\"
extern \"C\" {
#include \"softfloat.h\"
}

namespace prot::engine {
using namespace prot::state;
using namespace prot::isa;

void ExecEngine::step(CPU &cpu) {
  const auto bytes = cpu.m_memory->read<uint#{max_xlen}_t>(cpu.getPC());

  auto &&instr = decoder::decode(bytes);

  execute(cpu, *instr);
  cpu.increaseICount();
}
} // namespace prot::engine
"
      end
    end
  end
end

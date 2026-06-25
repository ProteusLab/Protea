module SimGen
  module Hart
    module Header
      module_function

      def get_addr_type(instructions)
        instructions.each do |insn|
          seq = insn.semantic
          next unless seq && seq.stmts
          seq.stmts.each do |stmt|
            if stmt.kind == 'env' && (stmt.specifier == 'writeMem' || stmt.specifier == 'readMem')
              return 32
            end
          end
        end
        32
      end

      def generate_hart(arch)
        type = get_addr_type(arch.instructions)
        type_str = Utility::HelperCpp.gen_type(type)

        <<~CPP
          #ifndef GENERATED_#{arch.name.upcase}_HART_HH_INCLUDED
          #define GENERATED_#{arch.name.upcase}_HART_HH_INCLUDED

          #include <memory>

          #include "cpu_state.hh"
          #include "elf_loader.hh"
          #include "base_exec_engine.hh"
          #include "memory.hh"

          namespace prot::hart {
            using namespace prot::state;
            using namespace prot::isa;
            using namespace prot::elf_loader;
            using namespace prot::engine;
            using namespace prot::memory;

            class Hart {
            public:
              Hart(std::unique_ptr<Memory> mem, std::unique_ptr<ExecEngine> engine);

              void setSP(#{type_str} addr);

              void load(const ElfLoader &loader);

              void setPC(#{type_str} addr);

              void run() {
                while (!m_cpu->m_finished) {
                  m_engine->step(*m_cpu);
                }
              }

              auto getIcount() const { return m_cpu->m_icount; }
              auto getExitCode() const { return m_cpu->m_code; }

            private:
              std::unique_ptr<Memory> m_mem;
              std::unique_ptr<CPU> m_cpu;
              std::unique_ptr<ExecEngine> m_engine;
            };
          }

          #endif
        CPP
      end
    end

    module TranslationUnit
      module_function

      def get_addr_type(instructions)
        instructions.each do |insn|
          seq = insn.semantic
          next unless seq && seq.stmts
          seq.stmts.each do |stmt|
            if stmt.kind == 'env' && (stmt.specifier == 'writeMem' || stmt.specifier == 'readMem')
              return 32
            end
          end
        end
        32
      end

      def generate_hart(arch)
        type = get_addr_type(arch.instructions)
        type_str = Utility::HelperCpp.gen_type(type)

        <<~CPP
          #include "hart.hh"

          namespace prot::hart {
            Hart::Hart(std::unique_ptr<Memory> mem, std::unique_ptr<ExecEngine> engine)
                : m_mem(std::move(mem)), m_cpu(std::make_unique<CPU>(m_mem.get())),
                  m_engine(std::move(engine)) {}

            void Hart::load(const ElfLoader &loader) {
              loader.loadMemory(*m_mem);
              setPC(loader.getEntryPoint());
            }

            void Hart::setSP(#{type_str} addr) { m_cpu->setXRegs(2, addr); }
            void Hart::setPC(#{type_str} addr) { m_cpu->setPC(addr); }
          }
        CPP
      end
    end
  end
end

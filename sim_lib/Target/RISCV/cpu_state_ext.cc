#include "cpu_state.hh"

namespace prot::state {

void CPU::sysCall() {
  switch (const auto syscallNum = getXRegs<isa::Word>(17)) {
  case 93:
    doExit(getXRegs<isa::Word>(10));
    break;
  default:
    throw std::runtime_error{
        fmt::format("Unknown syscall w/ num {}", syscallNum)};
  }
}

} // namespace prot::state

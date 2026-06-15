#include "cpu_state.hh"
#include <cstdint>

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

void CPU::writeMem8(uint32_t addr, uint8_t value) {
  m_memory->write<uint8_t>(addr, value);
}

void CPU::writeMem16(uint32_t addr, uint16_t value) {
  m_memory->write<uint16_t>(addr, value);
}

void CPU::writeMem32(uint32_t addr, uint32_t value) {
  m_memory->write<uint32_t>(addr, value);
}

uint8_t CPU::readMem8(uint32_t addr) { return m_memory->read<uint8_t>(addr); }

uint16_t CPU::readMem16(uint32_t addr) {
  return m_memory->read<uint16_t>(addr);
}

uint32_t CPU::readMem32(uint32_t addr) {
  return m_memory->read<uint32_t>(addr);
}

} // namespace prot::state

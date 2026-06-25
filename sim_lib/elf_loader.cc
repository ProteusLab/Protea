#include "elf_loader.hh"

#include <elfio/elfio.hpp>

#include <ranges>

namespace prot::elf_loader {

using namespace prot::memory;

ElfLoader::~ElfLoader() = default;

void ElfLoader::validate() const {
  if (m_elf->get_type() != ELFIO::ET_EXEC) {
    throw std::invalid_argument{"Invalud ELF type"};
  }

  if (m_elf->get_encoding() != ELFIO::ELFDATA2LSB) {
    throw std::invalid_argument{"Invalid ELF encoding"};
  }

  if (m_elf->get_class() != ELFIO::ELFCLASS32) {
    throw std::invalid_argument{"Invalid ELF class"};
  }

  if (m_elf->get_machine() != ELFIO::EM_RISCV) {
    throw std::invalid_argument{"Invalid machine"};
  }
}

ElfLoader::ElfLoader(std::istream &stream)
    : m_elf(std::make_unique<ELFIO::elfio>()) {
  if (!m_elf->load(stream)) {
    throw std::invalid_argument{"1"};
  }
  validate();
}

ElfLoader::ElfLoader(const std::filesystem::path &filename)
    : m_elf(std::make_unique<ELFIO::elfio>()) {
  if (!m_elf->load(filename)) {
    throw std::invalid_argument{"Could not load elf file."};
  }
  validate();
}

isa::Addr ElfLoader::getEntryPoint() const { return m_elf->get_entry(); }

void ElfLoader::loadMemory(Memory &mem) const {
  for (const auto &seg :
       m_elf->segments | std::views::filter([](const auto &seg) {
         return seg->get_type() == ELFIO::PT_LOAD;
       })) {
    mem.writeBlock(
        std::as_bytes(std::span{seg->get_data(), seg->get_file_size()}),
        seg->get_virtual_address());

    mem.fillBlock(seg->get_virtual_address() + seg->get_file_size(),
                  std::byte(), seg->get_memory_size() - seg->get_file_size());
  }
}

} // namespace prot::elf_loader

#ifndef PROT_ELF_LOADER_HH_INCLUDED
#define PROT_ELF_LOADER_HH_INCLUDED

#include <filesystem>
#include <istream>
#include <memory>

// clang-format off
#include "memory.hh"
#include "isa.hh"
// clang-format on

// NOLINTNEXTLINE
namespace ELFIO {

// forward decl
class elfio;

} // namespace ELFIO

namespace prot::elf_loader {

class ElfLoader {
public:
  explicit ElfLoader(std::istream &stream);
  explicit ElfLoader(const std::filesystem::path &filename);

  ElfLoader(ElfLoader &&elf) = default;
  ElfLoader &operator=(ElfLoader &&elf) = default;

  void loadMemory(memory::Memory &mem) const;
  [[nodiscard]] isa::Addr getEntryPoint() const;

  ~ElfLoader();

private:
  void validate() const;

  std::unique_ptr<ELFIO::elfio> m_elf;
};

} // namespace prot::elf_loader

#endif // PROT_ELF_LOADER_HH_INCLUDED

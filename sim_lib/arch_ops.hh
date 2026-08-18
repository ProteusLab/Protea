#ifndef PROT_ARCH_OPS_HH_INCLUDED
#define PROT_ARCH_OPS_HH_INCLUDED

#include <cstdint>

namespace prot::arch {

class ArchitectureSupport {
public:
  virtual ~ArchitectureSupport() = default;

  [[nodiscard]] virtual std::uint32_t f32_classify(std::uint32_t value) const = 0;
  [[nodiscard]] virtual std::uint32_t f64_classify(std::uint64_t value) const = 0;
};

} // namespace prot::arch

#endif // PROT_ARCH_OPS_HH_INCLUDED

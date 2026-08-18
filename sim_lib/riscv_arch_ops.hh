#ifndef PROT_RISCV_ARCH_OPS_HH_INCLUDED
#define PROT_RISCV_ARCH_OPS_HH_INCLUDED

#include "arch_ops.hh"

namespace prot::arch {

class RISCVArchitectureSupport final : public ArchitectureSupport {
public:
  [[nodiscard]] std::uint32_t f32_classify(std::uint32_t value) const override;
  [[nodiscard]] std::uint32_t f64_classify(std::uint64_t value) const override;
};

} // namespace prot::arch

#endif // PROT_RISCV_ARCH_OPS_HH_INCLUDED

#include "riscv_arch_ops.hh"

namespace prot::arch {

std::uint32_t RISCVArchitectureSupport::f32_classify(std::uint32_t value) const {
  const std::uint32_t sign = value >> 31;
  const std::uint32_t exp = (value >> 23) & 0xFF;
  const std::uint32_t frac = value & 0x7FFFFF;

  if (exp == 0xFF) {
    if (frac == 0) {
      return sign ? (1u << 0) : (1u << 7);
    }
    return (frac & (1u << 22)) ? (1u << 9) : (1u << 8);
  }

  if (exp == 0) {
    if (frac == 0) {
      return sign ? (1u << 3) : (1u << 4);
    }
    return sign ? (1u << 2) : (1u << 5);
  }

  return sign ? (1u << 1) : (1u << 6);
}

std::uint32_t RISCVArchitectureSupport::f64_classify(std::uint64_t value) const {
  const std::uint64_t sign = value >> 63;
  const std::uint64_t exp = (value >> 52) & 0x7FF;
  const std::uint64_t frac = value & 0xFFFFFFFFFFFFFULL;

  if (exp == 0x7FF) {
    if (frac == 0) {
      return sign ? (1u << 0) : (1u << 7);
    }
    return (frac & (1ULL << 51)) ? (1u << 9) : (1u << 8);
  }

  if (exp == 0) {
    if (frac == 0) {
      return sign ? (1u << 3) : (1u << 4);
    }
    return sign ? (1u << 2) : (1u << 5);
  }

  return sign ? (1u << 1) : (1u << 6);
}

} // namespace prot::arch

#include "memory.hh"

#include "isa.hh"

#include <algorithm>
#include <cassert>
#include <vector>

extern "C" {
#include <sys/mman.h>
}

namespace prot::memory {

namespace {

class PlainMemory : public Memory {
  struct Unmap {
    std::size_t m_size = 0;

  public:
    explicit Unmap(std::size_t size) noexcept : m_size(size) {}

    void operator()(void *ptr) const noexcept { ::munmap(ptr, m_size); }
  };

public:
  explicit PlainMemory(std::size_t size, isa::Addr start)
      : m_storage(
            [size] {
              auto *ptr =
                  ::mmap(NULL, size, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
              if (ptr == MAP_FAILED) {
                throw std::runtime_error{""};
              }

              return static_cast<std::byte *>(ptr);
            }(),
            Unmap{size}),
        m_data(m_storage.get(), size), m_start(start) {
    if (m_data.size() + m_start < m_start) {
      throw std::invalid_argument{""};
    }
  }

  uint8_t read8(isa::Addr addr) const override {
    return *reinterpret_cast<const uint8_t *>(translateAddr(addr));
  }

  uint16_t read16(isa::Addr addr) const override {
    return *reinterpret_cast<const uint16_t *>(translateAddr(addr));
  }

  uint32_t read32(isa::Addr addr) const override {
    return *reinterpret_cast<const uint32_t *>(translateAddr(addr));
  }

  void write8(isa::Addr addr, uint8_t val) override {
    *reinterpret_cast<uint8_t *>(translateAddr(addr)) = val;
  }

  void write16(isa::Addr addr, uint16_t val) override {
    *reinterpret_cast<uint16_t *>(translateAddr(addr)) = val;
  }

  void write32(isa::Addr addr, uint32_t val) override {
    *reinterpret_cast<uint32_t *>(translateAddr(addr)) = val;
  }

  void writeBlock(std::span<const std::byte> src, isa::Addr addr) override {
    // checkRange(addr, src.size());
    std::memcpy(translateAddr(addr), src.data(), src.size());
  }

  void readBlock(isa::Addr addr, std::span<std::byte> dest) const override {
    // checkRange(addr, dest.size());
    std::memcpy(dest.data(), translateAddr(addr), dest.size());
  }

private:
  [[nodiscard]] std::size_t addrToOffset(isa::Addr addr) const {
    assert(addr >= m_start && addr <= m_start + m_data.size());
    return addr - m_start;
  }

  [[nodiscard]] std::byte *translateAddr(isa::Addr addr) {
    return m_data.data() + addrToOffset(addr);
  }

  [[nodiscard]] const std::byte *translateAddr(isa::Addr addr) const {
    return m_data.data() + addrToOffset(addr);
  }

  void checkRange(isa::Addr addr, std::size_t size) const {
    assert(addr + size >= addr);
    if (addr < m_start) {
      throw std::invalid_argument{""};
    }

    if (addr + size > m_data.size() + m_start) {
      throw std::invalid_argument{""};
    }
  }

  std::unique_ptr<std::byte, Unmap> m_storage;
  std::span<std::byte> m_data;
  isa::Addr m_start{};
};

} // namespace

std::unique_ptr<Memory> makePlain(std::size_t size, isa::Addr start /* = 0 */) {
  return std::make_unique<PlainMemory>(size, start);
}

} // namespace prot::memory

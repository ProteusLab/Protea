#ifndef INCLUDE_JIT_BASE_HH_INCLUDED
#define INCLUDE_JIT_BASE_HH_INCLUDED

// clang-format off
#include "naive_interpreter.hh"
#include "decoder.hh"
// clang-format on

#include <functional>
#include <map>
#include <unordered_map>
#include <vector>

namespace prot::engine {

using JitFunction = void (*)(CPU &);

class JitEngine : public Interpreter {
  static constexpr std::size_t kExecThreshold = 10;

public:
  void step(CPU &cpu) override;

protected:
  struct TbCache {
    static constexpr std::uint64_t kInvalidAddr{0};
    static constexpr std::uint64_t kSizeLog2{22};
    static constexpr std::uint64_t kSize{1ULL << kSizeLog2};
    static constexpr std::uint64_t kGpaGranularityLog2{2};

    struct Entry {
      JitFunction func{};
      std::uint32_t gpa{};
    };

    JitFunction lookup(std::uint32_t gpa) const {
      const auto &entry = get(gpa);
      return entry.gpa == gpa ? entry.func : nullptr;
    }

    void insert(std::uint32_t gpa, JitFunction func) {
      get(gpa) = Entry{.func = func, .gpa = gpa};
    }

  private:
    const Entry &get(std::uint32_t gpa) const { return m_cache[getHash(gpa)]; }

    Entry &get(std::uint32_t gpa) { return m_cache[getHash(gpa)]; }

    [[nodiscard]] static constexpr std::uint32_t getHash(std::uint32_t gpa) {
      return (gpa >> kGpaGranularityLog2) & (kSize - 1);
    }

    std::array<Entry, kSize> m_cache;
  };

  // simple bb counting
  struct BBInfo final {
    std::vector<isa::Instruction> insns;
    std::size_t num_exec{};
  };

  [[nodiscard]] const BBInfo *getBBInfo(isa::Addr pc) const;

private:
  void interpret(CPU &cpu, BBInfo &info);

  void execute(CPU &cpu, const isa::Instruction &insn) final {
    Interpreter::execute(cpu, insn);
  }

private:
  [[nodiscard]] virtual JitFunction translate(const BBInfo &info) = 0;

  TbCache m_tbCache;
  std::unordered_map<isa::Addr, BBInfo> m_cacheBB;
};

class CachedInterpreter final : public JitEngine {
  JitFunction translate(const BBInfo & /* unused */) override {
    return nullptr;
  }
};

// Helper class to store JITed code
// Especially helpful for libraries w/out propper mem pool support
class CodeHolder final {
  struct Unmap {
    std::size_t m_size = 0;

  public:
    explicit Unmap(std::size_t size) noexcept : m_size(size) {}

    void operator()(void *ptr) const noexcept;
  };

public:
  explicit CodeHolder(std::span<const std::byte> src);

  template <typename T> [[nodiscard]] auto as() const {
    return reinterpret_cast<T>(m_data.get());
  }

  void operator()(CPU &state) const { as<JitFunction>()(state); }

private:
  std::unique_ptr<std::byte, Unmap> m_data;
};

} // namespace prot::engine

#endif // INCLUDE_JIT_BASE_HH_INCLUDED

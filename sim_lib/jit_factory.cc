#include "jit_factory.hh"

#include "base_jit.hh"

#include <algorithm>
#include <ranges>

namespace prot::engine {

const std::unordered_map<std::string_view,
                         std::function<std::unique_ptr<ExecEngine>()>>
    JitFactory::kFactories = {
        {"cached-interp",
         []() { return std::make_unique<CachedInterpreter>(); }},
};

std::vector<std::string_view> JitFactory::backends() {
  std::vector<std::string_view> res(kFactories.size());
  std::ranges::copy(kFactories | std::views::keys, res.begin());
  return res;
}

std::unique_ptr<ExecEngine>
JitFactory::createEngine(const std::string &backend) {
  auto it = kFactories.find(backend);
  if (it != kFactories.end()) {
    return it->second();
  }

  throw std::invalid_argument("Undefined JIT backend: " + backend);
}

bool JitFactory::exist(const std::string &backend) {
  return kFactories.contains(backend);
}

} // namespace prot::engine

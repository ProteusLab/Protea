#include "base_jit.hh"
#include "elf_loader.hh"
#include "hart.hh"
#include "jit_factory.hh"
#include "memory.hh"
#include "naive_interpreter.hh"

#include <CLI/CLI.hpp>
#include <fmt/core.h>
#include <fmt/ostream.h>

#include <chrono>
#include <filesystem>
#include <memory>

int main(int argc, const char *argv[]) try {
  std::filesystem::path elfPath;
  constexpr prot::isa::Addr kDefaultStack = 0x7fffffff;
  prot::isa::Addr stackTop = kDefaultStack;
  std::string jitBackend;
  bool propagateExit = false;

  CLI::App app{"Generated simulator with JIT support"};

  app.add_option("elf", elfPath, "Path to executable ELF file")
      ->required()
      ->check(CLI::ExistingFile);
  app.add_flag("--propagate-exit", propagateExit,
               "Propagate exit code from guest to host");

  app.add_option("--jit", jitBackend, "Use JIT with specified backend")
      ->check(CLI::IsMember(prot::engine::JitFactory::backends()));

  CLI11_PARSE(app, argc, argv);

  auto hart = [&] {
    prot::elf_loader::ElfLoader loader{elfPath};

    std::unique_ptr<prot::engine::ExecEngine> engine;
    if (!jitBackend.empty()) {
      engine = prot::engine::JitFactory::createEngine(jitBackend);
    } else {
      engine = std::make_unique<prot::engine::Interpreter>();
    }

    prot::hart::Hart hart{prot::memory::makePlain(4ULL << 30U),
                          std::move(engine)};
    hart.load(loader);
    hart.m_cpu->setXRegs<uint32_t>(2, kDefaultStack);
    return hart;
  }();

  auto start = std::chrono::high_resolution_clock::now();
  hart.run();
  auto end = std::chrono::high_resolution_clock::now();
  std::chrono::duration<double> duration = end - start;

  fmt::println("icount: {}", hart.getIcount());
  fmt::println("time: {} s", duration.count());
  fmt::println("MIPS: {:.2f}",
               hart.getIcount() / (duration.count() * 1'000'000));

  return propagateExit ? hart.getExitCode() : EXIT_SUCCESS;
} catch (const std::exception &ex) {
  fmt::println(std::cerr, "Caught exception of type {}: {}", typeid(ex).name(),
               ex.what());
  return EXIT_FAILURE;
} catch (...) {
  fmt::println(std::cerr, "Unknown exception caught");
  return EXIT_FAILURE;
}

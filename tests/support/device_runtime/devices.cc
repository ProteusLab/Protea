#ifdef PLOD_REFERENCE
#include "dev/riscv/plic.hh"
#include "dev/riscv/vio_mmio.hh"
#else
#include "Plic.hh"
#include "MmioVirtIO.hh"
#endif
#include <iostream>

using namespace gem5;

// The original devices keep MMIO entry points protected; expose them only in
// the harness, so both versions are driven through the same public operations.
class TestPlic : public Plic {
  public:
    using Plic::Plic;
    using Plic::read;
    using Plic::write;
};
class TestVio : public RiscvISA::MmioVirtIO {
  public:
    using MmioVirtIO::MmioVirtIO;
    using MmioVirtIO::read;
    using MmioVirtIO::write;
    using MmioVirtIO::setInterrupts;
};

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename D> uint32_t readWord(D& dev, Addr offset) {
    Packet pkt(dev.pioAddr + offset);
    Tick latency = dev.read(&pkt);
    check(pkt.response, "read response");
    check(latency == (std::is_same_v<D, TestPlic> ? dev.pioDelay : 0), "read latency");
    return pkt.getLE<uint32_t>();
}
template <typename D> void writeWord(D& dev, Addr offset, uint32_t value) {
    Packet pkt(dev.pioAddr + offset);
    pkt.setLE<uint32_t>(value);
    Tick latency = dev.write(&pkt);
    check(pkt.response, "write response");
    check(latency == (std::is_same_v<D, TestPlic> ? dev.pioDelay : 0), "write latency");
}
bool irq(System& system, int hart = 0, int interrupt = 11) {
    return system.threads[hart]->cpu.active.contains({hart, interrupt});
}
void dump(const CheckpointOut& cp) {
    for (const auto& [key, value] : cp.values) std::cout << key << '=' << value << '\n';
}
PlicParams plicParams(System& system) {
    PlicParams p; p.system = &system; p.pio_addr = 0xc000000; return p;
}

void plicGeometry() {
    System system;
    auto p = plicParams(system);
    TestPlic dev(p); dev.init();
    for (unsigned i = 0; i < 65; ++i) check(readWord(dev, i * 4) == 0, "priority reset");
    writeWord(dev, 4, 0x11223344);
    Packet partial(dev.pioAddr + 5, 2); partial.payload = {0xaa, 0xbb};
    dev.write(&partial);
    check(readWord(dev, 4) == 0x11bbaa44, "partial priority write");
    Packet byte(dev.pioAddr + 6, 1); dev.read(&byte);
    check(byte.payload[0] == 0xbb, "partial read");
    Packet multiple(dev.pioAddr + 8, 8);
    multiple.setLE<uint64_t>(0x0000000700000005ULL); dev.write(&multiple);
    check(readWord(dev, 8) == 5 && readWord(dev, 12) == 7, "spanning priority write");
    for (Addr gap : {Addr(65 * 4), Addr(0xffc), Addr(0x100c), Addr(0x107c),
                    Addr(0x200c), Addr(0x207c), Addr(0x2200), Addr(0x200008),
                    Addr(0x200ffc), Addr(0x204000), Addr(0x3fffffc)}) {
        writeWord(dev, gap, 0xffffffff); check(readWord(dev, gap) == 0, "reserved RAZ/WI");
    }
    writeWord(dev, 0x1000, 0xffffffff);
    check(readWord(dev, 0x1000) == 0, "pending read only");
    for (unsigned ctx = 0; ctx < 4; ++ctx) {
        writeWord(dev, 0x2000 + ctx * 0x80 + 8, 1);
        check(readWord(dev, 0x2000 + ctx * 0x80 + 8) == 1, "multidimensional enable");
        writeWord(dev, 0x200000 + ctx * 0x1000, ctx + 2);
        check(readWord(dev, 0x200000 + ctx * 0x1000) == ctx + 2, "threshold spacing");
    }
    AtomicOp operation; operation.callback = [](uint8_t* ptr) {
        uint32_t value; std::memcpy(&value, ptr, 4); value ^= 0xff; std::memcpy(ptr, &value, 4);
    };
    Packet atomic(dev.pioAddr + 8); atomic.atomic = &operation; atomic.cmd.v = MemCmd::SwapReq;
    check(dev.read(&atomic) == dev.pioDelay && atomic.response, "atomic response");
    check(readWord(dev, 8) == (5 ^ 0xff), "atomic read-modify-write");
    CheckpointOut cp; dev.serialize(cp); dump(cp);
}

void plicInterrupts() {
    System system; auto p = plicParams(system); TestPlic dev(p); dev.init();
    writeWord(dev, 4, 5); writeWord(dev, 8, 5);
    writeWord(dev, 0x2000, 6); writeWord(dev, 0x2080, 6);
    dev.post(2); dev.post(1);
    check(readWord(dev, 0x1000) == 6, "pending bits");
    runUntil(29); check(!irq(system), "no interrupt before latency");
    runUntil(30); check(irq(system) && irq(system, 0, 9), "M/S context IRQs");
    check(readWord(dev, 0x200004) == 1, "priority tie picks lowest ID");
    check(readWord(dev, 0x200004) == 1, "repeat claim");
    check(readWord(dev, 0x201004) == 0, "pending prevents duplicate claim");
    check(readWord(dev, 0x1000) == 4, "claim clears pending");
    writeWord(dev, 0x200004, 1);
    runUntil(60);
    check(readWord(dev, 0x201004) == 2, "second context claims next IRQ");
    writeWord(dev, 0x201004, 2); runUntil(90);
    check(!irq(system) && !irq(system, 0, 9), "all sources drained");
    dev.post(1); runUntil(120);
    writeWord(dev, 0x200000, 5); check(!irq(system), "threshold equality suppresses IRQ");
    writeWord(dev, 0x200000, 4); check(irq(system), "threshold applies immediately");
    writeWord(dev, 4, 3); runUntil(150); check(!irq(system), "priority changes pending source");
    writeWord(dev, 0x2000, 0); runUntil(180); check(!irq(system), "disable source");
    writeWord(dev, 4, 9); writeWord(dev, 0x2000, 2); runUntil(210);
    check(irq(system), "reenable pending source");
    dev.clear(1); runUntil(240); check(!irq(system), "external clear");
    // Source 0 is not forcibly masked by the original implementation.
    writeWord(dev, 0, 20); writeWord(dev, 0x2000, 1); dev.post(0); runUntil(270);
    check(!irq(system), "source zero does not signal IRQ");
    check(readWord(dev, 0x200004) == 0 && (readWord(dev, 0x1000) & 1) == 0, "source zero claim quirk");
    CheckpointOut cp; dev.serialize(cp); dump(cp);
    std::cout << "warnings=" << warnings.size() << '\n';
}

void plicTiming() {
    System system; auto p = plicParams(system); p.hart_config = "M"; TestPlic dev(p); dev.init();
    writeWord(dev, 4, 2); writeWord(dev, 8, 4); writeWord(dev, 0x2000, 6);
    dev.post(1); dev.clear(1); dev.post(2);
    check(events.size() == 1, "same edge schedules one event");
    CheckpointOut first; dev.serialize(first);
    check(first.values.at("n_outputs") == "1", "same tick replaces snapshot");
    check(first.values.at("output_tick0") == "30", "latency in cycles");
    runUntil(5); dev.clear(2);
    runUntil(15); dev.post(1);
    runUntil(30); check(irq(system), "first delayed snapshot retained");
    check(readWord(dev, 0x200004) == 0, "stale output checks live pending");
    runUntil(40); check(!irq(system), "second snapshot clears IRQ");
    runUntil(50); check(irq(system), "third snapshot posts IRQ");
    check(readWord(dev, 0x200004) == 1, "third snapshot claims source");
    writeWord(dev, 0x200004, 1); runUntil(80);
    CheckpointOut cp; dev.serialize(cp); dump(cp);
}

void plicCheckpoint() {
    System system; auto p = plicParams(system); CheckpointOut cp;
    {
        TestPlic dev(p); dev.init();
        writeWord(dev, 4, 7); writeWord(dev, 8, 8);
        writeWord(dev, 0x2000, 6); writeWord(dev, 0x2080, 6);
        dev.post(1); runUntil(30); check(readWord(dev, 0x200004) == 1, "claim before save");
        runUntil(35); dev.post(2); dev.serialize(cp);
        check(cp.values.at("n_outputs") == "2", "multiple pending snapshots saved");
    }
    check(events.empty(), "destroyed device removed event");
    TestPlic restored(p); restored.init(); CheckpointIn input(cp); restored.unserialize(input);
    CheckpointOut restoredCp; restored.serialize(restoredCp);
    check(restoredCp.values == cp.values, "complete checkpoint roundtrip");
    check(events.size() == 1 && events.begin()->first == 60, "earliest restored event scheduled");
    check(readWord(restored, 0x200004) == 1, "outstanding claim restored");
    writeWord(restored, 0x200004, 1);
    runUntil(60); check(!irq(system), "restored clear snapshot");
    runUntil(70); check(irq(system), "restored pending snapshot");
    check(readWord(restored, 0x201004) == 2, "restored alternate context claim");
    CheckpointOut final; restored.serialize(final); dump(final);
}

void plicContexts() {
    for (const auto& config : {std::string("M"), std::string("MS,MS"), std::string("M,,S")}) {
        System system; auto p = plicParams(system); p.hart_config = config;
        TestPlic dev(p); dev.init();
        CheckpointOut cp; dev.serialize(cp); dump(cp);
    }
    for (int count : {1, 2, 3, 4}) {
        System system; auto p = plicParams(system); p.hart_config = ""; p.n_contexts = count;
        TestPlic dev(p); dev.init(); CheckpointOut cp; dev.serialize(cp);
        check(cp.values.at("lastID").size() == unsigned(2 * ((count + 1) / 2) * 2 - 1), "odd context count forms M/S pairs");
        dump(cp);
    }
}

// Deterministic operations span every source-word boundary and exercise
// delayed outputs while claims, thresholds and enables change independently.
void plicRandomized() {
    uint32_t rng = 0x12345678;
    auto random = [&] { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; };
    for (int sources : {1, 31, 32, 33, 65, 1024}) {
        System system; auto p = plicParams(system); p.n_src = sources;
        TestPlic dev(p); dev.init();
        uint64_t digest = 1469598103934665603ULL;
        for (unsigned step = 0; step < 600; ++step) {
            unsigned src = random() % sources, ctx = random() % 4;
            switch (random() % 7) {
              case 0: dev.post(src); break;
              case 1: dev.clear(src); break;
              case 2: writeWord(dev, src * 4, random() % 16); break;
              case 3: writeWord(dev, 0x2000 + ctx * 0x80 + (src / 32) * 4, random()); break;
              case 4: writeWord(dev, 0x200000 + ctx * 0x1000, random() % 8); break;
              case 5: {
                uint32_t id = readWord(dev, 0x200004 + ctx * 0x1000);
                digest = (digest ^ id) * 1099511628211ULL;
                writeWord(dev, 0x200004 + ctx * 0x1000, id); break;
              }
              case 6: runUntil(curTick() + random() % 9); break;
            }
            digest = (digest ^ readWord(dev, 0x1000 + (src / 32) * 4)) * 1099511628211ULL;
            for (unsigned i = 0; i < 4; ++i) {
                digest = (digest ^ irq(system, i / 2, (i % 2) ? 9 : 11)) * 1099511628211ULL;
            }
        }
        runUntil(curTick() + 40);
        std::cout << "sources=" << sources << " digest=" << digest << '\n';
        CheckpointOut cp; dev.serialize(cp); dump(cp);
    }
}

void vioRegisters() {
    Platform platform; VirtIODeviceBase vio; RiscvMmioVirtIOParams p;
    p.platform = &platform; p.vio = &vio; p.pio_addr = 0x10008000;
    TestVio dev(p);
    check(readWord(dev, 0) == 0x74726976 && readWord(dev, 4) == 1, "magic/version");
    check(readWord(dev, 8) == 2 && readWord(dev, 0xc) == 0x1af4, "device/vendor ID");
    check(readWord(dev, 0x10) == vio.deviceFeatures, "host features low word");
    writeWord(dev, 0x14, 2); check(readWord(dev, 0x10) == 0, "host high features zero");
    writeWord(dev, 0x24, 3); check(readWord(dev, 0x24) == 2, "guest selector reads host selector");
    writeWord(dev, 0x20, 7); check(vio.guestFeatures == 0, "unimplemented guest features ignored");
    writeWord(dev, 0x24, 0); writeWord(dev, 0x20, 0xaabbccdd);
    check(readWord(dev, 0x20) == 0xaabbccdd, "guest features");
    writeWord(dev, 0x28, 4096); check(readWord(dev, 0x28) == 4096, "page size");
    writeWord(dev, 0x30, 0x10002); check(readWord(dev, 0x30) == 2, "queue selector native narrowing");
    check(readWord(dev, 0x34) == 128 && readWord(dev, 0x38) == 128, "queue sizes");
    writeWord(dev, 0x38, 256); writeWord(dev, 0x38, 512);
    check(vio.queueSize == 128, "resize hint ignored");
    writeWord(dev, 0x3c, 4096); check(readWord(dev, 0x3c) == 4096, "alignment");
    writeWord(dev, 0x40, 0x12345); check(readWord(dev, 0x40) == 0x12345, "queue address");
    writeWord(dev, 0x50, 0x10009); check(vio.notify == 9, "notification native narrowing");
    writeWord(dev, 0x70, 0xff); check(readWord(dev, 0x70) == 0xff, "status");
    for (Addr offset : {Addr(0), Addr(4), Addr(8), Addr(0xc), Addr(0x10), Addr(0x34), Addr(0x60)}) writeWord(dev, offset, 0xffffffff);
    check(readWord(dev, 0) == 0x74726976, "read-only value unchanged");
    check(readWord(dev, 0x50) == 0 && readWord(dev, 0x64) == 0, "write-only reads zero");
    for (unsigned size : {1, 2, 4, 8}) {
        Packet config(p.pio_addr + 0x108, size);
        check(dev.read(&config) == 0 && vio.forwarded == &config && vio.configOffset == 8 && !vio.configWrite && config.response, "config read forwarded");
        config.response = false;
        check(dev.write(&config) == 0 && vio.forwarded == &config && vio.configOffset == 8 && vio.configWrite && config.response, "config write forwarded");
    }
    std::cout << "warnings=" << warnings.size() << '\n';
    std::cout << "features=" << vio.guestFeatures << " address=" << vio.address << " status=" << +vio.status << '\n';
}

void vioInterrupts() {
    Platform platform; VirtIODeviceBase vio; RiscvMmioVirtIOParams p; p.platform = &platform; p.vio = &vio;
    TestVio dev(p);
    check(bool(vio.kickCallback), "kick callback registered");
    vio.kickCallback(); vio.kickCallback();
    check(readWord(dev, 0x60) == 1 && platform.posts == 1 && platform.active.contains(8), "kick posts one IRQ edge");
    dev.setInterrupts(3); writeWord(dev, 0x64, 1);
    check(readWord(dev, 0x60) == 2 && platform.clears == 0, "partial ack retains IRQ");
    writeWord(dev, 0x64, 4); check(readWord(dev, 0x60) == 2, "unrelated ack ignored");
    writeWord(dev, 0x64, 2); check(platform.clears == 1 && platform.active.empty(), "final ack clears IRQ");
    writeWord(dev, 0x64, 3); check(platform.clears == 1, "zero ack creates no edge");
    vio.kickCallback(); check(platform.posts == 2, "subsequent kick reposts");
    std::cout << "posts=" << platform.posts << " clears=" << platform.clears << '\n';
}

void vioCheckpoint() {
    Platform platform; VirtIODeviceBase vio; RiscvMmioVirtIOParams p; p.platform = &platform; p.vio = &vio;
    TestVio dev(p); dev.powerState = 17;
    writeWord(dev, 0x14, 2); writeWord(dev, 0x24, 3); vio.kickCallback();
    CheckpointOut cp; dev.serialize(cp);
    check(cp.values.size() == 1 && cp.values.at("clocked.powerState") == "17", "inherited checkpoint saves power state only");
    TestVio restored(p); CheckpointIn input(cp); restored.unserialize(input);
    check(restored.powerState == 17, "inherited checkpoint restore");
    check(readWord(restored, 0x14) == 0 && readWord(restored, 0x24) == 0 && readWord(restored, 0x60) == 0, "source transport checkpoint defaults");
    dump(cp);
}

template <typename F> void expectPanic(F f) {
    bool raised = false; try { f(); } catch (const std::runtime_error&) { raised = true; }
    check(raised, "expected panic/fatal");
}
void invalidAccesses() {
    Platform platform; VirtIODeviceBase vio; RiscvMmioVirtIOParams p; p.platform = &platform; p.vio = &vio;
    TestVio dev(p);
    for (unsigned size : {0, 1, 2, 8}) {
        Packet pkt(0, size); expectPanic([&] { dev.read(&pkt); }); expectPanic([&] { dev.write(&pkt); });
    }
    for (Addr offset : {Addr(1), Addr(0x18), Addr(0x48), Addr(0x74), Addr(0xfc)}) {
        expectPanic([&] { readWord(dev, offset); }); expectPanic([&] { writeWord(dev, offset, 0); });
    }
    expectPanic([&] { writeWord(dev, 0x28, 2048); });
    expectPanic([&] { writeWord(dev, 0x3c, 8192); });
    expectPanic([&] { writeWord(dev, 0x70, 256); });
    System system; auto pp = plicParams(system);
    pp.n_contexts = 2; expectPanic([&] { TestPlic conflict(pp); });
    pp.n_contexts = 0; pp.hart_config = "MX"; expectPanic([&] { TestPlic bad(pp); });
    pp.hart_config = "M"; TestPlic plic(pp); plic.init();
    Packet outOfRange(plic.pioAddr + plic.pioSize);
    expectPanic([&] { plic.read(&outOfRange); }); expectPanic([&] { plic.write(&outOfRange); });
    std::cout << "invalid accesses rejected\n";
}

int main(int argc, char** argv) {
    try {
        check(argc == 2, "scenario required");
        std::string scenario(argv[1]);
        if (scenario == "plic_geometry") plicGeometry();
        else if (scenario == "plic_interrupts") plicInterrupts();
        else if (scenario == "plic_timing") plicTiming();
        else if (scenario == "plic_checkpoint") plicCheckpoint();
        else if (scenario == "plic_contexts") plicContexts();
        else if (scenario == "plic_randomized") plicRandomized();
        else if (scenario == "vio_registers") vioRegisters();
        else if (scenario == "vio_interrupts") vioInterrupts();
        else if (scenario == "vio_checkpoint") vioCheckpoint();
        else if (scenario == "invalid_accesses") invalidAccesses();
        else if (scenario == "plic_bad_complete") {
            System system; auto p = plicParams(system); TestPlic dev(p); dev.init();
            writeWord(dev, 0x200004, 1);
            throw std::runtime_error("mismatched completion did not assert");
        }
        else throw std::runtime_error("unknown scenario");
        check(events.empty(), "no event leaked");
        std::cout << "OK " << scenario << '\n';
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n'; return 1;
    }
}

#ifdef PLOD_REFERENCE
#include "dev/x86/i8042.hh"
#include "dev/x86/i82094aa.hh"
#include "dev/x86/i8237.hh"
#include "dev/x86/i8254.hh"
#include "dev/x86/i8259.hh"
#else
#include "I8042.hh"
#include "I82094AA.hh"
#include "I8237.hh"
#include "I8254.hh"
#include "I8259.hh"
#endif
#include <iostream>

using namespace gem5;
using namespace gem5::X86ISA;

class TestPic : public I8259 {
  public:
    using I8259::I8259;
    using I8259::init;
    using I8259::getVector;
};
void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
void dump(const CheckpointOut& cp) {
    for (const auto& [key, value] : cp.values) std::cout << key << '=' << value << '\n';
}
template <typename D> CheckpointOut snapshot(const D& dev) {
    CheckpointOut cp; dev.serialize(cp); return cp;
}
template <typename D> uint32_t read(D& dev, Addr address, unsigned size=1) {
    Packet pkt(address, size); pkt.setLE<uint8_t>(0xa5);
    check(dev.read(&pkt) == 7 && pkt.response, "read response/latency");
    return size == 1 ? pkt.getLE<uint8_t>() : pkt.getLE<uint32_t>();
}
template <typename D> void write(D& dev, Addr address, uint32_t value, unsigned size=1) {
    Packet pkt(address, size);
    if (size == 1) pkt.setLE<uint8_t>(value); else pkt.setLE<uint32_t>(value);
    check(dev.write(&pkt) == 7 && pkt.response, "write response/latency");
}
IntSourcePinBase& source(SimObject& dev, const std::string& name, int index=0) {
    return dynamic_cast<IntSourcePinBase&>(dev.getPort(name, index));
}
IntSinkPinBase& sink(SimObject& dev, const std::string& name, int index=0) {
    return dynamic_cast<IntSinkPinBase&>(dev.getPort(name, index));
}
void dumpPins(SimObject& dev, const std::string& name, int count=2) {
    for (int i = 0; i < count; ++i) {
        auto& pin = source(dev, name, i);
        check(!pin.high && pin.raises == pin.lowers, "pulse shape");
        std::cout << name << '[' << i << "]=" << pin.pinName << ':' << pin.raises << ':' << pin.lowers << '\n';
    }
}
template <typename F> bool fails(F fn) {
    try { fn(); } catch (const std::runtime_error&) { return true; }
    return false;
}

void keyboardCommands() {
    // Exhaust every command byte, including RAM ranges, unknown commands and
    // fatal commands. Dump state after rejected transactions as well.
    for (unsigned command = 0; command < 256; ++command) {
        ps2::Device keyboard, mouse;
        keyboard.response = {0xfa, 0xab}; mouse.response = {0xfa, 0x12};
        I8042Params p; p.keyboard = &keyboard; p.mouse = &mouse;
        I8042 dev(p); dev.init(); warnings.clear();
        bool commandFailed = fails([&] { write(dev, p.command_port, command); });
        bool dataFailed = fails([&] { write(dev, p.data_port, 1); });
        std::cout << "command=" << command << ':' << commandFailed << ':' << dataFailed << ':' << warnings.size() << '\n';
        std::cout << "status=" << read(dev, p.command_port) << ":data=" << read(dev, p.data_port) << '\n';
        dump(snapshot(dev)); dumpPins(dev, "keyboard_int_pin"); dumpPins(dev, "mouse_int_pin");
        for (auto value : keyboard.writes) std::cout << "keyboard=" << +value << '\n';
        for (auto value : mouse.writes) std::cout << "mouse=" << +value << '\n';
    }
}
void keyboardQueues() {
    ps2::Device keyboard, mouse;
    I8042Params p; p.keyboard = &keyboard; p.mouse = &mouse;
    I8042 dev(p); dev.init();
    check(read(dev, p.command_port) == 0x10, "8042 initial status");
    write(dev, p.command_port, 0x60); write(dev, p.data_port, 3);
    write(dev, p.command_port, 0xd3); write(dev, p.data_port, 0x88);
    check(read(dev, p.command_port) == 0x31, "8042 mouse status");
    keyboard.pending = {0x11, 0x22}; mouse.pending = {0x33};
    for (auto expected : {0x88, 0x11, 0x22, 0x33}) {
        check(read(dev, p.data_port) == unsigned(expected), "8042 keyboard priority/prefetch");
        std::cout << "status=" << read(dev, p.command_port) << '\n';
    }
    dumpPins(dev, "keyboard_int_pin"); dumpPins(dev, "mouse_int_pin");
    write(dev, p.command_port, 0x60); // checkpoint a pending command
    auto cp = snapshot(dev); dump(cp);
    cp.values["dataPort"] = "112"; cp.values["commandPort"] = "116";
    I8042 restored(p); CheckpointIn in(cp); restored.unserialize(in);
    auto ranges = restored.getAddrRanges();
    check(ranges.size() == 2 && ranges[0].start == 112 && ranges[1].start == 116, "8042 restored noncontiguous ranges");
    write(restored, 112, 0x43); write(restored, 116, 0x20);
    check(read(restored, 112) == 0x43, "8042 command restored");
    dump(snapshot(restored));
    check(fails([&] { read(dev, 0x61); }), "8042 undefined read");
    check(fails([&] { write(dev, 0x61, 0); }), "8042 undefined write");
    p.mouse = nullptr; check(fails([&] { I8042 invalid(p); }), "8042 missing mouse");
    p.mouse = &mouse; p.keyboard = nullptr;
    check(fails([&] { I8042 invalid(p); }), "8042 missing keyboard");
}

void keyboardPorts() {
    ps2::Device keyboard, mouse;
    I8042Params p; p.keyboard = &keyboard; p.mouse = &mouse;
    p.data_port = 0x170; p.command_port = 0x140;
    I8042 dev(p); dev.init();
    auto ranges = dev.getAddrRanges();
    check(ranges.size() == 2 && ranges[0].start == p.data_port && ranges[1].start == p.command_port,
          "8042 independently configured ports");
    check(read(dev, p.command_port) == 0x10, "8042 configured status port");
    write(dev, p.command_port, 0x60); write(dev, p.data_port, 3);
    write(dev, p.command_port, 0xd2); write(dev, p.data_port, 0x91);
    check(read(dev, p.command_port) == 0x11, "8042 configured output ready");
    check(read(dev, p.data_port) == 0x91, "8042 configured output port");
    check(read(dev, p.command_port) == 0x10, "8042 configured output consumed");
    write(dev, p.command_port, 0xd4); write(dev, p.data_port, 0xf4);
    check(mouse.writes == std::vector<uint8_t>{0xf4}, "8042 configured mouse forwarding");
    write(dev, p.data_port, 0xed);
    check(keyboard.writes == std::vector<uint8_t>{0xed}, "8042 configured keyboard forwarding");
    for (Addr address : {Addr(0x60), Addr(0x64), p.data_port + 4, p.command_port + 1}) {
        check(fails([&] { read(dev, address); }), "8042 unmapped read");
        check(fails([&] { write(dev, address, 0); }), "8042 unmapped write");
    }
    dump(snapshot(dev)); dumpPins(dev, "keyboard_int_pin"); dumpPins(dev, "mouse_int_pin");

    // Identical configured ports retain data-port precedence in both directions.
    p.data_port = p.command_port = 0x180;
    I8042 aliased(p); aliased.init();
    check(read(aliased, 0x180) == 0, "8042 aliased data read precedes status");
    write(aliased, 0x180, 0xf4);
    check(keyboard.writes.back() == 0xf4, "8042 aliased data write precedes command");
    dump(snapshot(aliased));
}

void dmaControls() {
    I8237Params p; p.pio_addr = 0x80;
    I8237 dev(p); dev.init();
    check(read(dev, p.pio_addr + 8) == 0 && read(dev, p.pio_addr + 13) == 0, "DMA status/temp reset");
    for (Addr address = 0; address < 8; ++address) {
        check(fails([&] { read(dev, p.pio_addr + address); }), "DMA unimplemented read");
        check(fails([&] { write(dev, p.pio_addr + address, 0); }), "DMA unimplemented write");
    }
    for (unsigned reg = 8; reg < 16; ++reg) {
        for (unsigned value = 0; value < 256; ++value) {
            write(dev, p.pio_addr + 13, 0);
            bool rejected = fails([&] { write(dev, p.pio_addr + reg, value); });
            std::cout << reg << ':' << value << ':' << rejected << ':' << snapshot(dev).values.at("maskReg") << '\n';
        }
    }
    for (unsigned reg : {9, 10, 11, 12, 14, 15}) {
        check(fails([&] { read(dev, p.pio_addr + reg); }), "DMA illegal control read");
    }
    write(dev, p.pio_addr + 15, 0xa5);
    auto cp = snapshot(dev); check(cp.values.size() == 1 && cp.values.at("maskReg") == "5", "DMA partial checkpoint");
    I8237 restored(p); CheckpointIn in(cp); restored.unserialize(in);
    dump(snapshot(restored));
    Packet spanning(p.pio_addr + 12, 4); spanning.payload = {0, 0, 0, 0x0a};
    check(dev.write(&spanning) == 7 && spanning.response, "DMA spanning register writes");
    check(snapshot(dev).values.at("maskReg") == "10", "DMA spanning side effects");
    Packet mixed(p.pio_addr + 8, 2);
    check(fails([&] { dev.read(&mixed); }), "DMA spanning illegal read");
    check(fails([&] { read(dev, p.pio_addr + 16); }), "DMA bank bounds");
}

constexpr Tick pitInterval = Tick(sim_clock::as_float::s / 1193180.0);
void program(I8254& dev, unsigned num, uint16_t count, uint8_t mode) {
    dev.writeControl(uint8_t((num << 6) | 0x30 | (mode << 1)));
    dev.writeCounter(num, count & 0xff); dev.writeCounter(num, count >> 8);
}
void pitEvents() {
    I8254Params p; p.pio_addr = 0x40;
    CheckpointOut cp;
    {
        I8254 dev(p); dev.init();
        check(read(dev, p.pio_addr + 3) == 0xff, "PIT control reads as all ones");
        write(dev, p.pio_addr + 3, 0x30);
        write(dev, p.pio_addr, 5); write(dev, p.pio_addr, 0);
        program(dev, 1, 4, 2); program(dev, 2, 3, 0);
        dev.startup();
        runUntil(pitInterval * 2);
        write(dev, p.pio_addr + 3, 0); // latch counter 0
        check(read(dev, p.pio_addr) == 3 && read(dev, p.pio_addr) == 0, "PIT count latch");
        runUntil(pitInterval * 3);
        check(dev.outputHigh(2) && !dev.outputHigh(0), "PIT independent counters");
        check(source(dev, "int_pin").raises == 0, "PIT only counter 0 signals interrupt");
        cp = snapshot(dev); dump(cp);
        runUntil(pitInterval * 5);
        check(dev.outputHigh(0) && source(dev, "int_pin").raises == 1, "PIT one-shot event");
        dumpPins(dev, "int_pin");
    }
    check(events.empty(), "PIT timer cleanup");
    currentTick = pitInterval * 3;
    {
        I8254 restored(p); CheckpointIn in(cp); restored.unserialize(in); restored.startup();
        runUntil(pitInterval * 5);
        check(restored.outputHigh(0), "PIT restored deadline"); dumpPins(restored, "int_pin");
        program(restored, 0, 4, 2);
        runUntil(pitInterval * 15);
        check(source(restored, "int_pin").raises == 4, "PIT periodic interrupts");
        dump(snapshot(restored)); dumpPins(restored, "int_pin");
    }
}
void pitInvalid() {
    I8254Params p; I8254 dev(p);
    for (unsigned data = 0; data < 256; ++data) {
        std::cout << "control=" << data << ':' << fails([&] { dev.writeControl(data); }) << '\n';
    }
    check(fails([&] { read(dev, p.pio_addr + 4); }), "PIT undefined read");
    check(fails([&] { write(dev, p.pio_addr + 4, 0); }), "PIT undefined write");
}

void initializePic(TestPic& dev, uint8_t vector, bool cascade, bool autoEoi=false) {
    write(dev, dev.pioAddr, cascade ? 0x19 : 0x1b);
    write(dev, dev.pioAddr + 1, vector);
    if (cascade) { write(dev, dev.pioAddr + 1, 4); write(dev, dev.pioAddr + 1, autoEoi ? 3 : 1); }
}
void picInterrupts() {
    I8259Params p; p.pio_addr = 0x20;
    TestPic dev(p);
    sink(dev, "inputs", 1).high = true;
    dev.init(); dev.raiseInterruptPin(1);
    check(read(dev, p.pio_addr) == 0, "PIC initial high pin suppresses duplicate edge");
    initializePic(dev, 0x27, true);
    dev.signalInterrupt(1); dev.signalInterrupt(6);
    check(read(dev, p.pio_addr) == 0x42, "PIC requests");
    check(read(dev, PhysAddrIntA) == 0x26, "PIC highest line wins");
    write(dev, p.pio_addr, 0x0a); check(read(dev, p.pio_addr) == 0x40, "PIC read ISR");
    write(dev, p.pio_addr, 0x20); // EOI and queued IRQ1
    check(read(dev, PhysAddrIntA) == 0x21, "PIC queued IRQ");
    write(dev, p.pio_addr, 0x61);
    dev.maskAll(); dev.signalInterrupt(7);
    write(dev, p.pio_addr, 0x0b); check(read(dev, p.pio_addr) == 0, "PIC masked request discarded");
    dev.unmaskAll(); dev.lowerInterruptPin(1); dev.raiseInterruptPin(1); dev.raiseInterruptPin(1);
    check(read(dev, p.pio_addr) == 2, "PIC rising edge only");
    dump(snapshot(dev)); dumpPins(dev, "output");
    auto cp = snapshot(dev); TestPic restored(p); CheckpointIn in(cp); restored.unserialize(in);
    check(read(restored, PhysAddrIntA) == 0x21, "PIC restored pending interrupt");
    dump(snapshot(restored));
    check(dev.getAddrRanges().size() == 2, "PIC acknowledges INTA");
    Packet unknown(dev.pioAddr + 2, 1); unknown.setLE<uint8_t>(0x7c); dev.read(&unknown);
    check(unknown.getLE<uint8_t>() == 0x7c, "PIC undefined read retains packet");
    check(fails([&] { dev.signalInterrupt(8); }), "PIC invalid interrupt");
    p.port_inputs_connection_count = 9;
    check(fails([&] { TestPic invalid(p); }), "PIC input count");
}
void picCascade() {
    I8259Params p; p.pio_addr = 0xa0; p.mode = enums::I8259Slave;
    TestPic slave(p); slave.init(); initializePic(slave, 0x70, true, true);
    p.pio_addr = 0x20; p.mode = enums::I8259Master; p.slave = &slave;
    TestPic master(p); master.init(); initializePic(master, 0x20, true);
    slave.signalInterrupt(3); master.signalInterrupt(2);
    check(read(master, PhysAddrIntA) == 0x73, "PIC cascade vector");
    auto cp = snapshot(slave); check(cp.values.at("ISR") == "0", "PIC slave auto EOI");
    dump(cp); dump(snapshot(master));
    check(slave.getAddrRanges().size() == 1, "PIC slave range excludes INTA");
    initializePic(master, 0x28, false, true); write(master, p.pio_addr + 1, 3);
    // Preserve the single-mode quirk: ICW2 returns to normal mask writes,
    // skipping ICW4 even when ICW1 says to expect it.
    check(read(master, p.pio_addr + 1) == 3, "PIC single mode skips ICW4");
    dump(snapshot(master)); dumpPins(master, "output"); dumpPins(slave, "output");
}
void picIntaOverlap() {
    for (Addr offset : {Addr(0), Addr(1)}) {
        I8259Params p; p.pio_addr = PhysAddrIntA - offset;
        TestPic dev(p); dev.init(); initializePic(dev, 0x20, true);
        dev.signalInterrupt(3);
        // INTA consumes IRQ3, then normal register decoding replaces the vector.
        check(read(dev, PhysAddrIntA) == 0, "PIC overlapping INTA followed by PIO read");
        auto cp = snapshot(dev);
        check(cp.values.at("IRR") == "0" && cp.values.at("ISR") == "8", "PIC overlapping INTA side effects");
        dump(cp);
    }
}
void picRandomized() {
    I8259Params p; p.pio_addr = 0x20; TestPic dev(p); dev.init(); initializePic(dev, 0x20, true);
    uint32_t state = 0x5139;
    for (unsigned step = 0; step < 1000; ++step) {
        state = state * 1664525 + 1013904223; unsigned line = (state >> 16) & 7;
        switch (state % 8) {
          case 0: dev.signalInterrupt(line); break;
          case 1: dev.raiseInterruptPin(line); break;
          case 2: dev.lowerInterruptPin(line); break;
          case 3: write(dev, p.pio_addr + 1, state >> 24); break;
          case 4: std::cout << "ack=" << read(dev, PhysAddrIntA) << '\n'; break;
          case 5: write(dev, p.pio_addr, 0x60 | line); break;
          case 6: write(dev, p.pio_addr, 0x20); break;
          case 7: write(dev, p.pio_addr, 0x0a | (line & 1)); break;
        }
        std::cout << step << ':' << read(dev, p.pio_addr) << ':' << read(dev, p.pio_addr + 1) << ':' << source(dev, "output").raises << '\n';
        if (step % 50 == 0) dump(snapshot(dev));
    }
    dump(snapshot(dev));
}

void dumpMessages() {
    for (const auto& record : interruptRecords)
        std::cout << "message=" << record.tick << ':' << record.address << ':' << record.message << ':' << record.timing << '\n';
    interruptRecords.clear();
}
void ioapicRegisters() {
    System sys; I82094AAParams p; p.system = &sys; p.pio_addr = 0xfec00000;
    I82094AA dev(p); dev.init();
    check(read(dev, p.pio_addr, 4) == 0, "IOAPIC selector reset");
    check(dev.readReg(0) == 0x1000000 && dev.readReg(1) == 0x170014 && dev.readReg(2) == 0x1000000, "IOAPIC identity");
    for (unsigned i = 0; i < 24; ++i) {
        check(dev.readReg(0x10 + i * 2) == 0x10000, "IOAPIC masked reset");
        write(dev, p.pio_addr, 0x10 + i * 2, 4); write(dev, p.pio_addr + 16, 0xffffffff, 4);
        check(read(dev, p.pio_addr + 16, 4) == 0x1ffff, "IOAPIC bottom reserved bits");
        dev.writeReg(0x11 + i * 2, 0xffffffff);
        check(dev.readReg(0x11 + i * 2) == 0xff000000, "IOAPIC top reserved bits");
    }
    write(dev, p.pio_addr, 0x101, 4); check(read(dev, p.pio_addr, 4) == 1, "IOAPIC selector truncation");
    write(dev, p.pio_addr + 16, 0, 4); check(read(dev, p.pio_addr + 16, 4) == 0x170014, "IOAPIC version readonly");
    dev.writeReg(0, 0xfe000000); dev.writeReg(2, 0xcd000000);
    check(dev.readReg(0) == 0xfe000000 && dev.readReg(2) == 0xcd000000, "IOAPIC ID writes");
    for (auto reg : {3, 0x0f, 0x41, 0xff}) {
        check(dev.readReg(reg) == 0, "IOAPIC undefined register read"); dev.writeReg(reg, 0xdeadbeef);
    }
    check(fails([&] { read(dev, p.pio_addr + 4, 4); }), "IOAPIC illegal read");
    check(fails([&] { write(dev, p.pio_addr + 4, 0, 4); }), "IOAPIC illegal write");
    dump(snapshot(dev));
    I82094AA restored(p); auto cp = snapshot(dev); CheckpointIn in(cp); restored.unserialize(in);
    dump(snapshot(restored));
    auto& port = dynamic_cast<IntRequestPort<I82094AA>&>(restored.getPort("int_requestor", -1));
    port.connected = false; check(fails([&] { restored.init(); }), "IOAPIC disconnected port");
}
void ioapicRouting() {
    System sys(4); std::array<Interrupts,4> local;
    for (unsigned i = 0; i < 4; ++i) {
        local[i].initialApicId = 10 + i; local[i].logicalDestination = (i % 2) ? 2 : 1;
        sys.threads[i]->cpu.interruptController = &local[i];
    }
    I82094AAParams p; p.system = &sys; p.pio_addr = 0xfec00000;
    I82094AA dev(p); dev.init();
    dev.requestInterrupt(0); check(interruptRecords.empty(), "IOAPIC masked IRQ");
    dev.writeReg(0x11, 3 << 24); dev.writeReg(0x10, 0x59);
    dev.raiseInterruptPin(0); dev.raiseInterruptPin(0);
    check(interruptRecords.size() == 1, "IOAPIC suppress duplicate rising edge"); dumpMessages();
    dev.lowerInterruptPin(0); dev.raiseInterruptPin(0); dumpMessages();
    dev.writeReg(0x11, 0xff000000); dev.requestInterrupt(0);
    check(interruptRecords.size() == 4, "IOAPIC physical broadcast"); dumpMessages();
    dev.writeReg(0x11, 1 << 24); dev.writeReg(0x10, 0x800 | 0x5a);
    dev.requestInterrupt(0); check(interruptRecords.size() == 2, "IOAPIC logical destination"); dumpMessages();
    dev.writeReg(0x10, 0x900 | 0x5b);
    for (int i = 0; i < 5; ++i) { dev.requestInterrupt(0); dumpMessages(); }
    auto cp = snapshot(dev); dump(cp);
    I82094AA restored(p); CheckpointIn in(cp); restored.unserialize(in); restored.init();
    restored.requestInterrupt(0); dumpMessages();
    dev.writeReg(0x10, 0x100 | 0x5c);
    check(fails([&] { dev.requestInterrupt(0); }), "IOAPIC physical lowest priority rejected");
    sys.timing = true;
    dev.writeReg(0x10, 0xa000 | 0x63); dev.writeReg(0x11, 2 << 24);
    dev.requestInterrupt(0); check(interruptRecords.empty(), "IOAPIC timing queued");
    runUntil(4); check(interruptRecords.empty(), "IOAPIC latency");
    runUntil(5); check(interruptRecords.size() == 1, "IOAPIC timing delivery"); dumpMessages();
}
void ioapicExtint() {
    System sys(2); I8259Params picp; picp.pio_addr = 0x20;
    TestPic pic(picp); pic.init(); initializePic(pic, 0x20, true);
    I82094AAParams p; p.system = &sys;
    I82094AA dev(p); dev.init();
    acknowledge = [&] { return uint8_t(read(pic, PhysAddrIntA)); };
    pic.signalInterrupt(4); dev.writeReg(0x10, 0x700); dev.writeReg(0x11, 1 << 24);
    dev.requestInterrupt(0);
    check(interruptRecords.size() == 2, "IOAPIC atomic ExtInt acknowledge then trigger");
    check((interruptRecords.back().message >> 8 & 0xff) == 0x24, "IOAPIC ExtInt PIC vector"); dumpMessages();
    write(pic, picp.pio_addr, 0x20); pic.signalInterrupt(6);
    sys.timing = true; dev.requestInterrupt(0);
    // Modifying the table while the acknowledge is outstanding must not
    // change the message captured for that transaction.
    dev.writeReg(0x10, 0x31); dev.writeReg(0x11, 0xff000000);
    runUntil(5); check(interruptRecords.size() == 1, "IOAPIC delayed acknowledge"); dumpMessages();
    runUntil(9); check(interruptRecords.empty(), "IOAPIC second transport latency");
    runUntil(10); check(interruptRecords.size() == 1, "IOAPIC delayed ExtInt trigger");
    check((interruptRecords.back().message >> 8 & 0xff) == 0x26, "IOAPIC delayed PIC vector");
    check((interruptRecords.back().message & 0xff) == 1, "IOAPIC captured destination"); dumpMessages();
    dump(snapshot(dev)); dump(snapshot(pic));
    acknowledge = [] { return uint8_t(0x41); };
}
void pcInitialization() {
    I8254Params timerp; I8254 timer(timerp);
    timer.writeControl(0x34); timer.writeControl(0); timer.writeCounter(0, 0); timer.writeCounter(0, 0);
    System sys; I82094AAParams p; p.system = &sys;
    I82094AA ioApic(p); ioApic.init();
    // Keep the exact public BitUnion API consumed by gem5's Pc::init().
    I82094AA::RedirTableEntry entry = 0;
    static_assert(sizeof(entry) == 8);
    entry.mask = 1; entry.deliveryMode = delivery_mode::ExtInt; entry.vector = 0x20;
    ioApic.writeReg(0x10, entry.bottomDW); ioApic.writeReg(0x11, entry.topDW);
    entry.deliveryMode = delivery_mode::Fixed; entry.vector = 0x24;
    ioApic.writeReg(0x18, entry.bottomDW); ioApic.writeReg(0x19, entry.topDW);
    entry.vector = 0x21;
    ioApic.writeReg(0x12, entry.bottomDW); ioApic.writeReg(0x13, entry.topDW);
    check(ioApic.readReg(0x10) == 0x10720 && ioApic.readReg(0x18) == 0x10024, "PC APIC initialization");
    entry.dest = 3; entry.mask = 0; entry.trigger = 1; entry.polarity = 1; entry.destMode = 1;
    ioApic.writeReg(0x14, entry.bottomDW); ioApic.writeReg(0x15, entry.topDW);
    check(ioApic.readReg(0x14) == 0xa821 && ioApic.readReg(0x15) == 0x03000000, "public APIC entry fields");
    I8237::Register reg("compatibility"); reg.update(0x17); check(reg.get() == 0x17, "DMA public register alias");
    dump(snapshot(ioApic)); dump(snapshot(timer));
}
void assertionScenario(const std::string& name) {
    Packet pkt(0, name == "ioapic_bad_width" ? 1 : 4);
    if (name == "keyboard_bad_width" || name == "keyboard_bad_write_width" ||
        name == "keyboard_bad_status_width" || name == "keyboard_bad_command_width") {
        ps2::Device keyboard, mouse; I8042Params p; p.keyboard=&keyboard; p.mouse=&mouse;
        I8042 dev(p);
        const bool commandPort = name == "keyboard_bad_status_width" || name == "keyboard_bad_command_width";
        Packet invalid(commandPort ? p.command_port : p.data_port, 4);
        if (name == "keyboard_bad_write_width" || name == "keyboard_bad_command_width") dev.write(&invalid);
        else dev.read(&invalid);
    } else if (name == "pit_bad_width") { I8254Params p; I8254 dev(p); dev.read(&pkt); }
    else if (name == "pic_bad_width") { I8259Params p; TestPic dev(p); dev.write(&pkt); }
    else if (name == "ioapic_bad_width") { System sys; I82094AAParams p; p.system=&sys; I82094AA dev(p); dev.read(&pkt); }
    else if (name == "ioapic_bad_id") { I82094AAParams p; p.apic_id=255; I82094AA dev(p); }
    else if (name == "ioapic_bad_line") { I82094AAParams p; I82094AA dev(p); dev.raiseInterruptPin(24); }
    else if (name == "pic_slave_inta") { I8259Params p; p.mode=enums::I8259Slave; TestPic dev(p); read(dev, PhysAddrIntA); }
    else throw std::runtime_error("unknown assertion scenario");
}
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::string scenario = argv[1];
    try {
        if (scenario == "keyboard_commands") keyboardCommands();
        else if (scenario == "keyboard_queues") keyboardQueues();
        else if (scenario == "keyboard_ports") keyboardPorts();
        else if (scenario == "dma_controls") dmaControls();
        else if (scenario == "pit_events") pitEvents();
        else if (scenario == "pit_invalid") pitInvalid();
        else if (scenario == "pic_interrupts") picInterrupts();
        else if (scenario == "pic_cascade") picCascade();
        else if (scenario == "pic_inta_overlap") picIntaOverlap();
        else if (scenario == "pic_randomized") picRandomized();
        else if (scenario == "ioapic_registers") ioapicRegisters();
        else if (scenario == "ioapic_routing") ioapicRouting();
        else if (scenario == "ioapic_extint") ioapicExtint();
        else if (scenario == "pc_initialization") pcInitialization();
        else assertionScenario(scenario);
        std::cout << "OK " << scenario << '\n';
    } catch (const std::exception& error) { std::cerr << "FAIL " << scenario << ": " << error.what() << '\n'; return 1; }
}
